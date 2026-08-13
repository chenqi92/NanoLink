package handler

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

var (
	buildNamePattern     = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._ -]{0,99}$`)
	buildStageIDPattern  = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`)
	buildVariablePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]{0,99}$`)
	buildImagePattern    = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9./:_@-]{0,499}$`)
)

type buildStage struct {
	ID             string   `json:"id"`
	Name           string   `json:"name"`
	Command        string   `json:"command"`
	Needs          []string `json:"needs"`
	AllowFailure   bool     `json:"allowFailure"`
	TimeoutSeconds int      `json:"timeoutSeconds"`
}

type buildVariable struct {
	Name     string `json:"name"`
	Value    string `json:"value,omitempty"`
	Secret   bool   `json:"secret"`
	Required bool   `json:"required"`
}

type buildPipelineRequest struct {
	Name             string          `json:"name" binding:"required"`
	Description      string          `json:"description"`
	AgentID          string          `json:"agentId" binding:"required"`
	SourceType       string          `json:"sourceType" binding:"required"`
	SourceURL        string          `json:"sourceUrl"`
	SourceRef        string          `json:"sourceRef"`
	RunnerType       string          `json:"runnerType" binding:"required"`
	ContainerImage   string          `json:"containerImage"`
	Stages           []buildStage    `json:"stages" binding:"required"`
	Variables        []buildVariable `json:"variables"`
	ArtifactPattern  string          `json:"artifactPattern" binding:"required"`
	ArtifactName     string          `json:"artifactName" binding:"required"`
	KeepArtifacts    int             `json:"keepArtifacts"`
	PublishProjectID *uint           `json:"publishProjectId"`
	TimeoutSeconds   int             `json:"timeoutSeconds"`
	Schedule         string          `json:"schedule"`
	Enabled          *bool           `json:"enabled"`
}

type buildPipelineView struct {
	database.BuildPipeline
	Stages       []buildStage        `json:"stages"`
	Variables    []buildVariable     `json:"variables"`
	Runs         []database.BuildRun `json:"runs,omitempty"`
	WebhookToken string              `json:"webhookToken,omitempty"`
}

type buildRunRequest struct {
	Version string `json:"version"`
}

type BuildHandler struct {
	db                 *gorm.DB
	grpc               *grpcserver.Server
	deployment         *DeploymentHandler
	codec              service.SecretCodec
	storageRoot        string
	externalURL        string
	maxSource          int64
	maxArtifact        int64
	tokenTTL           time.Duration
	fetchTimeout       time.Duration
	maxLog             int
	allowedSourceHosts map[string]bool
	logger             *zap.SugaredLogger
	dispatchMu         sync.Mutex
	schedulerStop      chan struct{}
	schedulerDone      chan struct{}
}

func NewBuildHandler(db *gorm.DB, grpcServer *grpcserver.Server, deployment *DeploymentHandler, codec service.SecretCodec, cfg config.BuildConfig, externalURL string, logger *zap.SugaredLogger) (*BuildHandler, error) {
	root, err := filepath.Abs(cfg.StoragePath)
	if err != nil {
		return nil, fmt.Errorf("resolve build storage path: %w", err)
	}
	for _, child := range []string{"sources", "artifacts"} {
		if err := os.MkdirAll(filepath.Join(root, child), 0o750); err != nil {
			return nil, fmt.Errorf("create build storage: %w", err)
		}
	}
	allowedHosts := make(map[string]bool, len(cfg.AllowedSourceHosts))
	for _, host := range cfg.AllowedSourceHosts {
		host = strings.ToLower(strings.TrimSuffix(strings.TrimSpace(host), "."))
		if host != "" {
			allowedHosts[host] = true
		}
	}
	return &BuildHandler{
		db: db, grpc: grpcServer, deployment: deployment, codec: codec,
		storageRoot: root, externalURL: strings.TrimRight(strings.TrimSpace(externalURL), "/"),
		maxSource: cfg.MaxSourceBytes, maxArtifact: cfg.MaxArtifactBytes,
		tokenTTL:     time.Duration(cfg.DownloadTTLMin) * time.Minute,
		fetchTimeout: time.Duration(cfg.FetchTimeoutSec) * time.Second,
		maxLog:       cfg.MaxLogBytes, allowedSourceHosts: allowedHosts, logger: logger,
		schedulerStop: make(chan struct{}), schedulerDone: make(chan struct{}),
	}, nil
}

func (h *BuildHandler) ListPipelines(c *gin.Context) {
	var rows []database.BuildPipeline
	if err := h.db.Order("updated_at DESC").Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list build pipelines"})
		return
	}
	views := make([]buildPipelineView, 0, len(rows))
	for _, row := range rows {
		view, err := h.pipelineView(row, false)
		if err != nil {
			h.logger.Warnf("decode pipeline %d: %v", row.ID, err)
			continue
		}
		views = append(views, view)
	}
	c.JSON(http.StatusOK, views)
}

func (h *BuildHandler) GetPipeline(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var row database.BuildPipeline
	if err := h.db.First(&row, id).Error; err != nil {
		respondDeploymentDBError(c, err, "build pipeline")
		return
	}
	view, err := h.pipelineView(row, true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "pipeline definition is invalid"})
		return
	}
	c.JSON(http.StatusOK, view)
}

func (h *BuildHandler) CreatePipeline(c *gin.Context) {
	var req buildPipelineRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateBuildPipelineRequest(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.validatePublishTarget(req.PublishProjectID, req.ArtifactName); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	stagesJSON, variablesJSON, err := h.encodeDefinition(req.Stages, req.Variables, nil)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	plainToken, tokenHash, err := newArtifactToken()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create webhook token"})
		return
	}
	user := GetCurrentUser(c)
	enabled := req.Enabled == nil || *req.Enabled
	row := database.BuildPipeline{
		Name: strings.TrimSpace(req.Name), Description: strings.TrimSpace(req.Description), AgentID: strings.TrimSpace(req.AgentID),
		SourceType: strings.ToLower(strings.TrimSpace(req.SourceType)), SourceURL: strings.TrimSpace(req.SourceURL), SourceRef: strings.TrimSpace(req.SourceRef),
		RunnerType: strings.ToLower(strings.TrimSpace(req.RunnerType)), ContainerImage: strings.TrimSpace(req.ContainerImage),
		StagesJSON: stagesJSON, VariablesJSON: variablesJSON, ArtifactPattern: strings.TrimSpace(req.ArtifactPattern), ArtifactName: strings.TrimSpace(req.ArtifactName), KeepArtifacts: req.KeepArtifacts,
		PublishProjectID: req.PublishProjectID, TimeoutSeconds: req.TimeoutSeconds, Schedule: strings.TrimSpace(req.Schedule), Enabled: enabled,
		WebhookTokenHash: tokenHash, WebhookTokenHint: plainToken[:8], CreatedBy: user.ID,
	}
	if row.TimeoutSeconds == 0 {
		row.TimeoutSeconds = 1800
	}
	if err := h.db.Create(&row).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "pipeline name already exists or definition is invalid"})
		return
	}
	view, _ := h.pipelineView(row, false)
	view.WebhookToken = plainToken
	c.JSON(http.StatusCreated, view)
}

func (h *BuildHandler) UpdatePipeline(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var existing database.BuildPipeline
	if err := h.db.First(&existing, id).Error; err != nil {
		respondDeploymentDBError(c, err, "build pipeline")
		return
	}
	var req buildPipelineRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateBuildPipelineRequest(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.validatePublishTarget(req.PublishProjectID, req.ArtifactName); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var oldVariables []buildVariable
	_ = json.Unmarshal([]byte(existing.VariablesJSON), &oldVariables)
	stagesJSON, variablesJSON, err := h.encodeDefinition(req.Stages, req.Variables, oldVariables)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	existing.Name = strings.TrimSpace(req.Name)
	existing.Description = strings.TrimSpace(req.Description)
	existing.AgentID = strings.TrimSpace(req.AgentID)
	existing.SourceType = strings.ToLower(strings.TrimSpace(req.SourceType))
	existing.SourceURL = strings.TrimSpace(req.SourceURL)
	existing.SourceRef = strings.TrimSpace(req.SourceRef)
	existing.RunnerType = strings.ToLower(strings.TrimSpace(req.RunnerType))
	existing.ContainerImage = strings.TrimSpace(req.ContainerImage)
	existing.StagesJSON = stagesJSON
	existing.VariablesJSON = variablesJSON
	existing.ArtifactPattern = strings.TrimSpace(req.ArtifactPattern)
	existing.ArtifactName = strings.TrimSpace(req.ArtifactName)
	existing.KeepArtifacts = req.KeepArtifacts
	existing.PublishProjectID = req.PublishProjectID
	existing.TimeoutSeconds = req.TimeoutSeconds
	if existing.TimeoutSeconds == 0 {
		existing.TimeoutSeconds = 1800
	}
	existing.Schedule = strings.TrimSpace(req.Schedule)
	if req.Enabled != nil {
		existing.Enabled = *req.Enabled
	}
	if err := h.db.Save(&existing).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "failed to update pipeline"})
		return
	}
	view, _ := h.pipelineView(existing, false)
	c.JSON(http.StatusOK, view)
}

func (h *BuildHandler) RotateWebhookToken(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	plain, hash, err := newArtifactToken()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to rotate webhook token"})
		return
	}
	result := h.db.Model(&database.BuildPipeline{}).Where("id = ?", id).Updates(map[string]any{"webhook_token_hash": hash, "webhook_token_hint": plain[:8]})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to rotate webhook token"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "build pipeline not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"webhookToken": plain, "webhookTokenHint": plain[:8]})
}

func (h *BuildHandler) RunPipeline(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var request buildRunRequest
	if c.Request.ContentLength != 0 {
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}
	var pipeline database.BuildPipeline
	if err := h.db.First(&pipeline, id).Error; err != nil {
		respondDeploymentDBError(c, err, "build pipeline")
		return
	}
	if pipeline.SourceType == database.BuildSourceUpload {
		c.JSON(http.StatusBadRequest, gin.H{"error": "upload-source pipelines must be started by uploading a source archive"})
		return
	}
	user := GetCurrentUser(c)
	run, err := h.dispatchPipeline(pipeline, buildDispatchInput{Version: request.Version, Trigger: database.BuildTriggerManual, UserID: user.ID, Username: user.Username, BaseURL: requestBaseURL(c)})
	if err != nil {
		status := http.StatusConflict
		if errors.Is(err, errInvalidBuildInput) {
			status = http.StatusBadRequest
		}
		c.JSON(status, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusAccepted, run)
}

func (h *BuildHandler) UploadAndRun(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var pipeline database.BuildPipeline
	if err := h.db.First(&pipeline, id).Error; err != nil {
		respondDeploymentDBError(c, err, "build pipeline")
		return
	}
	if pipeline.SourceType != database.BuildSourceUpload {
		c.JSON(http.StatusBadRequest, gin.H{"error": "this pipeline does not use an uploaded source"})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, h.maxSource+(1<<20))
	fileHeader, err := c.FormFile("source")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source archive is required"})
		return
	}
	if fileHeader.Size <= 0 || fileHeader.Size > h.maxSource {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "source archive exceeds the configured limit"})
		return
	}
	name := filepath.Base(fileHeader.Filename)
	if err := validateBuildArchiveName(name); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	sourcePath, size, digest, err := h.storeUploadedSource(pipeline.ID, fileHeader)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	user := GetCurrentUser(c)
	run, err := h.dispatchPipeline(pipeline, buildDispatchInput{
		Version: c.PostForm("version"), Trigger: database.BuildTriggerManual, UserID: user.ID, Username: user.Username, BaseURL: requestBaseURL(c),
		SourcePath: sourcePath, SourceName: name, SourceSize: size, SourceSHA256: digest,
	})
	if err != nil {
		_ = os.Remove(sourcePath)
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusAccepted, run)
}

func (h *BuildHandler) GetRun(c *gin.Context) {
	var run database.BuildRun
	if err := h.db.Preload("Pipeline").Preload("Artifact").First(&run, "id = ?", c.Param("runId")).Error; err != nil {
		respondDeploymentDBError(c, err, "build run")
		return
	}
	h.reconcileRunTimeout(&run)
	c.JSON(http.StatusOK, run)
}

func (h *BuildHandler) ListRuns(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if limit < 1 {
		limit = 1
	}
	if limit > 200 {
		limit = 200
	}
	var runs []database.BuildRun
	query := h.db.Preload("Pipeline").Preload("Artifact").Order("created_at DESC").Limit(limit)
	if raw := strings.TrimSpace(c.Query("pipelineId")); raw != "" {
		query = query.Where("pipeline_id = ?", raw)
	}
	if err := query.Find(&runs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list build runs"})
		return
	}
	c.JSON(http.StatusOK, runs)
}

func (h *BuildHandler) DownloadArtifact(c *gin.Context) {
	var artifact database.BuildArtifact
	if err := h.db.First(&artifact, "id = ?", c.Param("artifactId")).Error; err != nil {
		respondDeploymentDBError(c, err, "build artifact")
		return
	}
	path, err := h.safeStoredPath(artifact.Path, "artifacts")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid artifact path"})
		return
	}
	c.Header("X-Artifact-SHA256", artifact.SHA256)
	c.FileAttachment(path, artifact.Name)
}

func (h *BuildHandler) pipelineView(row database.BuildPipeline, withRuns bool) (buildPipelineView, error) {
	view := buildPipelineView{BuildPipeline: row}
	if err := json.Unmarshal([]byte(row.StagesJSON), &view.Stages); err != nil {
		return view, err
	}
	if strings.TrimSpace(row.VariablesJSON) != "" {
		if err := json.Unmarshal([]byte(row.VariablesJSON), &view.Variables); err != nil {
			return view, err
		}
	}
	for i := range view.Variables {
		if view.Variables[i].Secret {
			view.Variables[i].Value = ""
		}
	}
	if withRuns {
		if err := h.db.Where("pipeline_id = ?", row.ID).Preload("Artifact").Order("created_at DESC").Limit(50).Find(&view.Runs).Error; err != nil {
			return view, err
		}
	}
	return view, nil
}

func (h *BuildHandler) encodeDefinition(stages []buildStage, variables, existing []buildVariable) (string, string, error) {
	stages = topologicalBuildStages(stages)
	stagesBytes, err := json.Marshal(stages)
	if err != nil {
		return "", "", err
	}
	oldSecrets := map[string]string{}
	for _, variable := range existing {
		if variable.Secret {
			oldSecrets[variable.Name] = variable.Value
		}
	}
	for i := range variables {
		variables[i].Name = strings.TrimSpace(variables[i].Name)
		if !variables[i].Secret {
			continue
		}
		if variables[i].Value == "" {
			if encrypted := oldSecrets[variables[i].Name]; encrypted != "" {
				variables[i].Value = encrypted
				continue
			}
			if variables[i].Required {
				return "", "", fmt.Errorf("secret variable %s requires a value", variables[i].Name)
			}
			continue
		}
		if h.codec == nil {
			return "", "", errors.New("secret encryption is unavailable")
		}
		encrypted, err := h.codec.EncryptSecret(variables[i].Value)
		if err != nil {
			return "", "", fmt.Errorf("encrypt variable %s: %w", variables[i].Name, err)
		}
		variables[i].Value = encrypted
	}
	variablesBytes, err := json.Marshal(variables)
	return string(stagesBytes), string(variablesBytes), err
}

func topologicalBuildStages(stages []buildStage) []buildStage {
	byID := make(map[string]buildStage, len(stages))
	order := make(map[string]int, len(stages))
	indegree := make(map[string]int, len(stages))
	children := make(map[string][]string, len(stages))
	for index, stage := range stages {
		byID[stage.ID] = stage
		order[stage.ID] = index
		indegree[stage.ID] = len(stage.Needs)
		for _, need := range stage.Needs {
			children[need] = append(children[need], stage.ID)
		}
	}
	result := make([]buildStage, 0, len(stages))
	for len(result) < len(stages) {
		candidate := ""
		for _, stage := range stages {
			if indegree[stage.ID] == 0 && byID[stage.ID].ID != "" && (candidate == "" || order[stage.ID] < order[candidate]) {
				candidate = stage.ID
			}
		}
		if candidate == "" {
			return stages
		}
		result = append(result, byID[candidate])
		delete(byID, candidate)
		for _, child := range children[candidate] {
			indegree[child]--
		}
	}
	return result
}

func (h *BuildHandler) runtimeVariables(raw string) (map[string]string, error) {
	var variables []buildVariable
	if strings.TrimSpace(raw) != "" {
		if err := json.Unmarshal([]byte(raw), &variables); err != nil {
			return nil, err
		}
	}
	result := make(map[string]string, len(variables))
	for _, variable := range variables {
		value := variable.Value
		if variable.Secret && value != "" {
			if h.codec == nil {
				return nil, errors.New("secret decryption is unavailable")
			}
			plain, err := h.codec.DecryptSecret(value)
			if err != nil {
				return nil, fmt.Errorf("decrypt variable %s: %w", variable.Name, err)
			}
			value = plain
		}
		if variable.Required && value == "" {
			return nil, fmt.Errorf("required variable %s is empty", variable.Name)
		}
		result[variable.Name] = value
	}
	return result, nil
}

func validateBuildPipelineRequest(req *buildPipelineRequest) error {
	req.Name = strings.TrimSpace(req.Name)
	req.SourceType = strings.ToLower(strings.TrimSpace(req.SourceType))
	req.RunnerType = strings.ToLower(strings.TrimSpace(req.RunnerType))
	req.ArtifactPattern = strings.TrimSpace(req.ArtifactPattern)
	req.ArtifactName = strings.TrimSpace(req.ArtifactName)
	if !buildNamePattern.MatchString(req.Name) {
		return errors.New("pipeline name must be 1-100 safe characters")
	}
	if strings.TrimSpace(req.AgentID) == "" {
		return errors.New("build agent is required")
	}
	if !matchesBuildSource(req.SourceType) {
		return errors.New("sourceType must be git, url, or upload")
	}
	if req.SourceType == database.BuildSourceGit {
		if err := validateGitSourceURL(req.SourceURL); err != nil {
			return err
		}
	} else if req.SourceType == database.BuildSourceURL {
		if err := validateRemoteSourceURL(req.SourceURL); err != nil {
			return err
		}
	} else if strings.TrimSpace(req.SourceURL) != "" {
		return errors.New("upload sources cannot define sourceUrl")
	}
	if req.RunnerType != database.BuildRunnerDocker && req.RunnerType != database.BuildRunnerHost {
		return errors.New("runnerType must be docker or host")
	}
	if req.RunnerType == database.BuildRunnerDocker && !buildImagePattern.MatchString(strings.TrimSpace(req.ContainerImage)) {
		return errors.New("containerImage is required and contains unsupported characters")
	}
	if err := validateBuildStages(req.Stages); err != nil {
		return err
	}
	if len(req.Variables) > 100 {
		return errors.New("a pipeline can define at most 100 variables")
	}
	seenVariables := map[string]bool{}
	for _, variable := range req.Variables {
		if !buildVariablePattern.MatchString(strings.TrimSpace(variable.Name)) || seenVariables[variable.Name] {
			return errors.New("variable names must be unique shell-style identifiers")
		}
		seenVariables[variable.Name] = true
		if len(variable.Value) > 16_000 {
			return fmt.Errorf("variable %s is too large", variable.Name)
		}
	}
	if err := validateBuildArtifactPattern(req.ArtifactPattern); err != nil {
		return err
	}
	if filepath.Base(req.ArtifactName) != req.ArtifactName || req.ArtifactName == "" || len(req.ArtifactName) > 255 {
		return errors.New("artifactName must be a file name")
	}
	if req.TimeoutSeconds == 0 {
		req.TimeoutSeconds = 1800
	}
	if req.TimeoutSeconds < 30 || req.TimeoutSeconds > 86400 {
		return errors.New("timeoutSeconds must be between 30 and 86400")
	}
	if req.KeepArtifacts == 0 {
		req.KeepArtifacts = 20
	}
	if req.KeepArtifacts < 1 || req.KeepArtifacts > 200 {
		return errors.New("keepArtifacts must be between 1 and 200")
	}
	if req.Schedule != "" {
		if err := validateCronExpression(req.Schedule); err != nil {
			return err
		}
	}
	if req.PublishProjectID != nil && *req.PublishProjectID == 0 {
		return errors.New("publishProjectId must be positive")
	}
	return nil
}

func validateBuildStages(stages []buildStage) error {
	if len(stages) == 0 || len(stages) > 30 {
		return errors.New("a pipeline must contain between 1 and 30 stages")
	}
	ids := map[string]bool{}
	for _, stage := range stages {
		if !buildStageIDPattern.MatchString(strings.TrimSpace(stage.ID)) || ids[stage.ID] {
			return errors.New("stage ids must be unique and use letters, numbers, dash, or underscore")
		}
		ids[stage.ID] = true
		if strings.TrimSpace(stage.Name) == "" || len(stage.Name) > 100 || strings.TrimSpace(stage.Command) == "" || len(stage.Command) > 16000 {
			return errors.New("every stage requires a valid name and command")
		}
		if stage.TimeoutSeconds < 0 || stage.TimeoutSeconds > 86400 {
			return fmt.Errorf("stage %s timeout is invalid", stage.ID)
		}
	}
	indegree := make(map[string]int, len(stages))
	children := make(map[string][]string, len(stages))
	for _, stage := range stages {
		seen := map[string]bool{}
		for _, need := range stage.Needs {
			if need == stage.ID || !ids[need] || seen[need] {
				return fmt.Errorf("stage %s has an invalid dependency", stage.ID)
			}
			seen[need] = true
			indegree[stage.ID]++
			children[need] = append(children[need], stage.ID)
		}
	}
	queue := make([]string, 0)
	for id := range ids {
		if indegree[id] == 0 {
			queue = append(queue, id)
		}
	}
	visited := 0
	for len(queue) > 0 {
		id := queue[0]
		queue = queue[1:]
		visited++
		for _, child := range children[id] {
			indegree[child]--
			if indegree[child] == 0 {
				queue = append(queue, child)
			}
		}
	}
	if visited != len(stages) {
		return errors.New("stage dependencies contain a cycle")
	}
	return nil
}

func validateBuildArtifactPattern(pattern string) error {
	if pattern == "" || len(pattern) > 500 || filepath.IsAbs(pattern) || strings.Contains(pattern, "..") || strings.Contains(pattern, `\`) {
		return errors.New("artifactPattern must be a safe relative path or glob")
	}
	return nil
}

func matchesBuildSource(source string) bool {
	return source == database.BuildSourceGit || source == database.BuildSourceURL || source == database.BuildSourceUpload
}

func (h *BuildHandler) validatePublishTarget(projectID *uint, artifactName string) error {
	if projectID == nil {
		return nil
	}
	var project database.DeploymentProject
	if err := h.db.First(&project, *projectID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("publish target does not exist")
		}
		return errors.New("failed to validate publish target")
	}
	if _, err := deploymentArtifactSuffix(project.Type, artifactName); err != nil {
		return fmt.Errorf("artifact is incompatible with publish target: %w", err)
	}
	return nil
}

func validateGitSourceURL(raw string) error {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u == nil {
		return errors.New("Git source must be an absolute HTTP(S) or SSH URL without an embedded password")
	}
	_, hasPassword := u.User.Password()
	if u.Host == "" || (u.Scheme != "http" && u.Scheme != "https" && u.Scheme != "ssh") || hasPassword {
		return errors.New("Git source must be an absolute HTTP(S) or SSH URL without an embedded password")
	}
	if (u.Scheme == "http" || u.Scheme == "https") && u.User != nil {
		return errors.New("Git HTTP(S) URL must not embed credentials; use agent-managed credentials")
	}
	return nil
}

func validateRemoteSourceURL(raw string) error {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil {
		return errors.New("URL source must be an absolute HTTP(S) URL without embedded credentials")
	}
	return validateBuildArchiveName(filepath.Base(u.Path))
}

func validateBuildArchiveName(name string) error {
	lower := strings.ToLower(name)
	if name == "" || filepath.Base(name) != name {
		return errors.New("source archive name is invalid")
	}
	for _, suffix := range []string{".zip", ".tar", ".tar.gz", ".tgz"} {
		if strings.HasSuffix(lower, suffix) {
			return nil
		}
	}
	return errors.New("source archive must be .zip, .tar, .tar.gz, or .tgz")
}

func requestBaseURL(c *gin.Context) string {
	scheme := "http"
	if c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") {
		scheme = "https"
	}
	return scheme + "://" + c.Request.Host
}

func (h *BuildHandler) callbackURL(base, endpoint, token string) (string, error) {
	if h.externalURL != "" {
		base = h.externalURL
	}
	base = strings.TrimRight(strings.TrimSpace(base), "/")
	if base == "" {
		return "", errors.New("server.external_url is required for scheduled build callbacks")
	}
	return base + endpoint + "?" + url.Values{"token": []string{token}}.Encode(), nil
}

func (h *BuildHandler) safeStoredPath(raw, area string) (string, error) {
	abs, err := filepath.Abs(raw)
	if err != nil {
		return "", err
	}
	root := filepath.Join(h.storageRoot, area)
	rel, err := filepath.Rel(root, abs)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", errors.New("stored path escapes build storage")
	}
	return abs, nil
}

func (h *BuildHandler) storeUploadedSource(pipelineID uint, header *multipart.FileHeader) (string, int64, string, error) {
	dir := filepath.Join(h.storageRoot, "sources", strconv.FormatUint(uint64(pipelineID), 10))
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", 0, "", fmt.Errorf("prepare source storage: %w", err)
	}
	suffix := buildArchiveSuffix(header.Filename)
	finalPath := filepath.Join(dir, uuid.NewString()+suffix)
	tmpPath := finalPath + ".upload"
	input, err := header.Open()
	if err != nil {
		return "", 0, "", fmt.Errorf("read source archive: %w", err)
	}
	defer input.Close()
	output, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
	if err != nil {
		return "", 0, "", fmt.Errorf("create source archive: %w", err)
	}
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(output, hash), io.LimitReader(input, h.maxSource+1))
	closeErr := output.Close()
	if copyErr != nil || closeErr != nil || written <= 0 || written > h.maxSource {
		_ = os.Remove(tmpPath)
		return "", 0, "", errors.New("source archive exceeds the configured limit or could not be stored")
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		return "", 0, "", fmt.Errorf("finalize source archive: %w", err)
	}
	return finalPath, written, hex.EncodeToString(hash.Sum(nil)), nil
}

func buildArchiveSuffix(name string) string {
	lower := strings.ToLower(name)
	for _, suffix := range []string{".tar.gz", ".tgz", ".zip", ".tar"} {
		if strings.HasSuffix(lower, suffix) {
			return suffix
		}
	}
	return ".archive"
}

func tokenMatches(plain, expectedHash string) bool {
	digest := sha256.Sum256([]byte(strings.TrimSpace(plain)))
	provided := hex.EncodeToString(digest[:])
	return plain != "" && len(provided) == len(expectedHash) && subtle.ConstantTimeCompare([]byte(provided), []byte(expectedHash)) == 1
}
