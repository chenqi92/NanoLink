package handler

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

var (
	releaseVersionPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`)
	serviceNamePattern    = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.@-]{0,159}$`)
)

type DeploymentHandler struct {
	db          *gorm.DB
	grpc        *grpcserver.Server
	storageRoot string
	externalURL string
	maxArtifact int64
	downloadTTL time.Duration
	logger      *zap.SugaredLogger
	dispatchMu  sync.Mutex
}

type deploymentProjectRequest struct {
	Name         string `json:"name" binding:"required"`
	Type         string `json:"type" binding:"required"`
	AgentID      string `json:"agentId" binding:"required"`
	DeployPath   string `json:"deployPath" binding:"required"`
	ServiceName  string `json:"serviceName"`
	HealthURL    string `json:"healthUrl"`
	KeepReleases int    `json:"keepReleases"`
}

type deploymentProjectView struct {
	database.DeploymentProject
	Releases    []database.DeploymentRelease `json:"releases"`
	Deployments []database.DeploymentTask    `json:"deployments"`
}

func NewDeploymentHandler(db *gorm.DB, grpcServer *grpcserver.Server, cfg config.DeploymentConfig, externalURL string, logger *zap.SugaredLogger) (*DeploymentHandler, error) {
	root, err := filepath.Abs(cfg.StoragePath)
	if err != nil {
		return nil, fmt.Errorf("resolve deployment storage path: %w", err)
	}
	if err := os.MkdirAll(root, 0o750); err != nil {
		return nil, fmt.Errorf("create deployment storage: %w", err)
	}
	return &DeploymentHandler{
		db:          db,
		grpc:        grpcServer,
		storageRoot: root,
		externalURL: strings.TrimRight(strings.TrimSpace(externalURL), "/"),
		maxArtifact: cfg.MaxArtifactBytes,
		downloadTTL: time.Duration(cfg.DownloadTTLMin) * time.Minute,
		logger:      logger,
	}, nil
}

func (h *DeploymentHandler) ListProjects(c *gin.Context) {
	var projects []database.DeploymentProject
	if err := h.db.Order("updated_at DESC").Find(&projects).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list deployment projects"})
		return
	}
	c.JSON(http.StatusOK, projects)
}

func (h *DeploymentHandler) GetProject(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var project database.DeploymentProject
	if err := h.db.First(&project, id).Error; err != nil {
		respondDeploymentDBError(c, err, "project")
		return
	}
	var releases []database.DeploymentRelease
	var tasks []database.DeploymentTask
	if err := h.db.Where("project_id = ?", id).Order("created_at DESC").Find(&releases).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list releases"})
		return
	}
	if err := h.db.Where("project_id = ?", id).Preload("Release").Order("created_at DESC").Limit(50).Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list deployments"})
		return
	}
	c.JSON(http.StatusOK, deploymentProjectView{DeploymentProject: project, Releases: releases, Deployments: tasks})
}

func (h *DeploymentHandler) CreateProject(c *gin.Context) {
	var req deploymentProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateDeploymentProjectRequest(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	user := GetCurrentUser(c)
	project := database.DeploymentProject{
		Name: strings.TrimSpace(req.Name), Type: strings.ToLower(req.Type), AgentID: strings.TrimSpace(req.AgentID),
		DeployPath: path.Clean(req.DeployPath), ServiceName: strings.TrimSpace(req.ServiceName), HealthURL: strings.TrimSpace(req.HealthURL),
		KeepReleases: req.KeepReleases, CreatedBy: user.ID,
	}
	if project.KeepReleases == 0 {
		project.KeepReleases = 5
	}
	if err := h.db.Create(&project).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "project name already exists or project is invalid"})
		return
	}
	c.JSON(http.StatusCreated, project)
}

func (h *DeploymentHandler) UpdateProject(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var req deploymentProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateDeploymentProjectRequest(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var project database.DeploymentProject
	if err := h.db.First(&project, id).Error; err != nil {
		respondDeploymentDBError(c, err, "project")
		return
	}
	project.Name = strings.TrimSpace(req.Name)
	project.Type = strings.ToLower(req.Type)
	project.AgentID = strings.TrimSpace(req.AgentID)
	project.DeployPath = path.Clean(req.DeployPath)
	project.ServiceName = strings.TrimSpace(req.ServiceName)
	project.HealthURL = strings.TrimSpace(req.HealthURL)
	project.KeepReleases = req.KeepReleases
	if err := h.db.Save(&project).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "failed to update project"})
		return
	}
	c.JSON(http.StatusOK, project)
}

func (h *DeploymentHandler) UploadRelease(c *gin.Context) {
	projectID, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var project database.DeploymentProject
	if err := h.db.First(&project, projectID).Error; err != nil {
		respondDeploymentDBError(c, err, "project")
		return
	}

	// This route deliberately bypasses the general 1 MB JSON limit, but retains
	// a deployment-specific hard cap. The extra 1 MB covers multipart headers.
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, h.maxArtifact+(1<<20))
	version := strings.TrimSpace(c.PostForm("version"))
	if !releaseVersionPattern.MatchString(version) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "version must contain only letters, numbers, dot, dash, or underscore"})
		return
	}
	fileHeader, err := c.FormFile("artifact")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "artifact file is required"})
		return
	}
	if fileHeader.Size <= 0 || fileHeader.Size > h.maxArtifact {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": fmt.Sprintf("artifact must be between 1 byte and %d bytes", h.maxArtifact)})
		return
	}
	artifactName := filepath.Base(fileHeader.Filename)
	suffix, err := deploymentArtifactSuffix(project.Type, artifactName)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	id := uuid.NewString()
	projectDir := filepath.Join(h.storageRoot, strconv.FormatUint(uint64(projectID), 10))
	if err := os.MkdirAll(projectDir, 0o750); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to prepare artifact storage"})
		return
	}
	tmpPath := filepath.Join(projectDir, id+".upload")
	finalPath := filepath.Join(projectDir, id+suffix)
	in, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read artifact"})
		return
	}
	defer in.Close()
	out, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create artifact"})
		return
	}
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(out, hash), io.LimitReader(in, h.maxArtifact+1))
	closeErr := out.Close()
	if copyErr != nil || closeErr != nil || written <= 0 || written > h.maxArtifact {
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "artifact exceeds the configured limit or could not be stored"})
		return
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to finalize artifact"})
		return
	}

	user := GetCurrentUser(c)
	release := database.DeploymentRelease{
		ID: id, ProjectID: projectID, Version: version, ArtifactName: artifactName,
		ArtifactPath: finalPath, ArtifactSize: written, SHA256: hex.EncodeToString(hash.Sum(nil)),
		Notes: strings.TrimSpace(c.PostForm("notes")), CreatedBy: user.ID,
	}
	if err := h.db.Create(&release).Error; err != nil {
		_ = os.Remove(finalPath)
		c.JSON(http.StatusConflict, gin.H{"error": "this version already exists"})
		return
	}
	c.JSON(http.StatusCreated, release)
}

func (h *DeploymentHandler) DeployRelease(c *gin.Context) {
	projectID, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	releaseID := strings.TrimSpace(c.Param("releaseId"))
	var project database.DeploymentProject
	var release database.DeploymentRelease
	if err := h.db.First(&project, projectID).Error; err != nil {
		respondDeploymentDBError(c, err, "project")
		return
	}
	if err := h.db.Where("id = ? AND project_id = ?", releaseID, projectID).First(&release).Error; err != nil {
		respondDeploymentDBError(c, err, "release")
		return
	}
	h.dispatch(c, project, release, database.DeploymentActionDeploy)
}

func (h *DeploymentHandler) RollbackRelease(c *gin.Context) {
	projectID, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	releaseID := strings.TrimSpace(c.Param("releaseId"))
	var project database.DeploymentProject
	var release database.DeploymentRelease
	if err := h.db.First(&project, projectID).Error; err != nil {
		respondDeploymentDBError(c, err, "project")
		return
	}
	if err := h.db.Where("id = ? AND project_id = ?", releaseID, projectID).First(&release).Error; err != nil {
		respondDeploymentDBError(c, err, "release")
		return
	}
	h.dispatch(c, project, release, database.DeploymentActionRollback)
}

func (h *DeploymentHandler) dispatch(c *gin.Context, project database.DeploymentProject, release database.DeploymentRelease, action string) {
	h.dispatchMu.Lock()
	defer h.dispatchMu.Unlock()

	user := GetCurrentUser(c)
	now := time.Now()
	cutoff := now.Add(-(h.downloadTTL + 5*time.Minute))
	_ = h.db.Model(&database.DeploymentTask{}).
		Where("project_id = ? AND status IN ? AND started_at < ?", project.ID, []string{database.DeploymentStatusQueued, database.DeploymentStatusRunning}, cutoff).
		Updates(map[string]any{
			"status":      database.DeploymentStatusFailed,
			"error":       "deployment timed out before a new release was requested",
			"finished_at": &now,
		}).Error
	var active int64
	if err := h.db.Model(&database.DeploymentTask{}).
		Where("project_id = ? AND status IN ?", project.ID, []string{database.DeploymentStatusQueued, database.DeploymentStatusRunning}).
		Count(&active).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check active deployments"})
		return
	}
	if active > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "this project already has a deployment in progress"})
		return
	}
	commandID := uuid.NewString()
	task := database.DeploymentTask{
		ID: uuid.NewString(), ProjectID: project.ID, ReleaseID: release.ID, AgentID: project.AgentID,
		CommandID: commandID, Action: action, Status: database.DeploymentStatusQueued,
		CreatedBy: user.ID, CreatedByName: user.Username, StartedAt: &now,
	}
	params := map[string]string{
		"project_type": project.Type, "version": release.Version, "deploy_path": project.DeployPath,
		"service_name": project.ServiceName, "health_url": project.HealthURL,
		"keep_releases": strconv.Itoa(project.KeepReleases),
	}
	commandType := pb.CommandType_DEPLOY_ROLLBACK
	if action == database.DeploymentActionDeploy {
		plainToken, tokenHash, err := newArtifactToken()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create artifact token"})
			return
		}
		expires := now.Add(h.downloadTTL)
		task.ArtifactTokenHash = tokenHash
		task.ArtifactTokenExpires = &expires
		params["artifact_url"] = h.artifactURL(c, task.ID, plainToken)
		params["artifact_sha256"] = release.SHA256
		params["artifact_size"] = strconv.FormatInt(release.ArtifactSize, 10)
		params["artifact_name"] = release.ArtifactName
		commandType = pb.CommandType_DEPLOY_EXECUTE
	}
	if err := h.db.Create(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create deployment task"})
		return
	}

	h.grpc.RegisterDispatchedCommand(commandID, project.AgentID, user.ID, user.Username, commandType.String())
	cmd := &pb.Command{CommandId: commandID, Type: commandType, Target: project.DeployPath, Params: params}
	if err := h.grpc.SendCommandToAgent(project.AgentID, cmd); err != nil {
		finished := time.Now()
		h.db.Model(&task).Updates(map[string]any{
			"status": database.DeploymentStatusFailed, "error": err.Error(), "finished_at": &finished,
			"artifact_token_hash": "", "artifact_token_expires": nil,
		})
		task.Status = database.DeploymentStatusFailed
		task.Error = err.Error()
		task.FinishedAt = &finished
		c.JSON(http.StatusConflict, gin.H{"error": "agent is offline or cannot accept the deployment", "details": err.Error(), "task": task})
		return
	}
	h.db.Model(&task).Update("status", database.DeploymentStatusRunning)
	task.Status = database.DeploymentStatusRunning
	c.JSON(http.StatusAccepted, task)
}

func (h *DeploymentHandler) GetTask(c *gin.Context) {
	var task database.DeploymentTask
	if err := h.db.Preload("Project").Preload("Release").First(&task, "id = ?", c.Param("taskId")).Error; err != nil {
		respondDeploymentDBError(c, err, "deployment")
		return
	}
	// A server restart or an agent disconnect can prevent the final gRPC result
	// from arriving. Reconcile old running tasks so the UI never spins forever.
	if (task.Status == database.DeploymentStatusQueued || task.Status == database.DeploymentStatusRunning) &&
		task.StartedAt != nil && time.Since(*task.StartedAt) > h.downloadTTL+5*time.Minute {
		finished := time.Now()
		task.Status = database.DeploymentStatusFailed
		task.Error = "deployment timed out before the agent returned a result"
		task.FinishedAt = &finished
		_ = h.db.Model(&task).Updates(map[string]any{
			"status": task.Status, "error": task.Error, "finished_at": task.FinishedAt,
		}).Error
	}
	c.JSON(http.StatusOK, task)
}

// HandleCommandResult is wired into the gRPC result fan-out in main.
func (h *DeploymentHandler) HandleCommandResult(agentID, commandID, output string, success bool) {
	var task database.DeploymentTask
	if err := h.db.Where("command_id = ? AND agent_id = ?", commandID, agentID).First(&task).Error; err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			h.logger.Warnf("deployment result lookup failed: %v", err)
		}
		return
	}
	if task.Status != database.DeploymentStatusQueued && task.Status != database.DeploymentStatusRunning {
		// Ignore duplicate or late results. In particular, a task that timed out
		// must not overwrite the current release after a newer deployment starts.
		return
	}
	finished := time.Now()
	updates := map[string]any{
		"output": output, "finished_at": &finished,
		"artifact_token_hash": "", "artifact_token_expires": nil,
	}
	if success {
		updates["status"] = database.DeploymentStatusSuccess
		if err := h.db.Model(&database.DeploymentProject{}).Where("id = ?", task.ProjectID).Update("current_release_id", task.ReleaseID).Error; err != nil {
			h.logger.Warnf("failed to update project current release: %v", err)
		}
	} else {
		updates["status"] = database.DeploymentStatusFailed
		updates["error"] = output
	}
	if err := h.db.Model(&task).Updates(updates).Error; err != nil {
		h.logger.Warnf("failed to persist deployment result: %v", err)
	}
}

// DownloadArtifact is intentionally unauthenticated by browser session. The
// agent receives a high-entropy, task-scoped token that expires quickly.
func (h *DeploymentHandler) DownloadArtifact(c *gin.Context) {
	var task database.DeploymentTask
	if err := h.db.First(&task, "id = ?", c.Param("taskId")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "artifact token not found"})
		return
	}
	token := strings.TrimSpace(c.Query("token"))
	digest := sha256.Sum256([]byte(token))
	provided := hex.EncodeToString(digest[:])
	if token == "" || task.ArtifactTokenExpires == nil || time.Now().After(*task.ArtifactTokenExpires) ||
		len(provided) != len(task.ArtifactTokenHash) || subtle.ConstantTimeCompare([]byte(provided), []byte(task.ArtifactTokenHash)) != 1 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "artifact token is invalid or expired"})
		return
	}
	var release database.DeploymentRelease
	if err := h.db.First(&release, "id = ?", task.ReleaseID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "release not found"})
		return
	}
	artifactPath, err := h.safeStoredArtifact(release.ArtifactPath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid artifact path"})
		return
	}
	c.Header("X-Artifact-SHA256", release.SHA256)
	c.FileAttachment(artifactPath, release.ArtifactName)
}

func (h *DeploymentHandler) artifactURL(c *gin.Context, taskID, token string) string {
	base := h.externalURL
	if base == "" {
		scheme := "http"
		if c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") {
			scheme = "https"
		}
		base = scheme + "://" + c.Request.Host
	}
	return fmt.Sprintf("%s/api/deployment-artifacts/%s?%s", strings.TrimRight(base, "/"), url.PathEscape(taskID), url.Values{"token": []string{token}}.Encode())
}

func (h *DeploymentHandler) safeStoredArtifact(raw string) (string, error) {
	abs, err := filepath.Abs(raw)
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(h.storageRoot, abs)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", errors.New("artifact escapes storage root")
	}
	return abs, nil
}

// ImportBuildArtifact promotes a verified build output into Deployment Center.
// It creates an immutable copy (or same-filesystem hard link) below the
// deployment storage root, so the existing short-lived download-token boundary
// and path-containment checks continue to apply unchanged.
func (h *DeploymentHandler) ImportBuildArtifact(projectID uint, version, notes, sourcePath, artifactName string, size int64, digest string, userID uint) (*database.DeploymentRelease, error) {
	var project database.DeploymentProject
	if err := h.db.First(&project, projectID).Error; err != nil {
		return nil, fmt.Errorf("load deployment project: %w", err)
	}
	suffix, err := deploymentArtifactSuffix(project.Type, artifactName)
	if err != nil {
		return nil, err
	}
	if !releaseVersionPattern.MatchString(version) {
		return nil, errors.New("build version is not a valid deployment version")
	}
	input, err := os.Open(sourcePath)
	if err != nil {
		return nil, fmt.Errorf("open build artifact: %w", err)
	}
	defer input.Close()
	id := uuid.NewString()
	projectDir := filepath.Join(h.storageRoot, strconv.FormatUint(uint64(projectID), 10))
	if err := os.MkdirAll(projectDir, 0o750); err != nil {
		return nil, fmt.Errorf("prepare deployment artifact storage: %w", err)
	}
	finalPath := filepath.Join(projectDir, id+suffix)
	if err := os.Link(sourcePath, finalPath); err != nil {
		output, openErr := os.OpenFile(finalPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
		if openErr != nil {
			return nil, fmt.Errorf("create deployment artifact: %w", openErr)
		}
		written, copyErr := io.Copy(output, input)
		closeErr := output.Close()
		if copyErr != nil || closeErr != nil || written != size {
			_ = os.Remove(finalPath)
			return nil, errors.New("copy build artifact into deployment storage failed")
		}
	}
	release := database.DeploymentRelease{
		ID: id, ProjectID: projectID, Version: version, ArtifactName: artifactName,
		ArtifactPath: finalPath, ArtifactSize: size, SHA256: digest,
		Notes: strings.TrimSpace(notes), CreatedBy: userID,
	}
	if err := h.db.Create(&release).Error; err != nil {
		_ = os.Remove(finalPath)
		return nil, errors.New("deployment version already exists or could not be created")
	}
	return &release, nil
}

func validateDeploymentProjectRequest(req *deploymentProjectRequest) error {
	req.Name = strings.TrimSpace(req.Name)
	req.Type = strings.ToLower(strings.TrimSpace(req.Type))
	req.AgentID = strings.TrimSpace(req.AgentID)
	req.DeployPath = strings.TrimSpace(req.DeployPath)
	if req.Name == "" || len(req.Name) > 100 {
		return errors.New("project name is required and must be at most 100 characters")
	}
	if req.Type != database.DeploymentProjectJava && req.Type != database.DeploymentProjectStatic {
		return errors.New("project type must be java or static")
	}
	if req.AgentID == "" {
		return errors.New("agent is required")
	}
	clean := path.Clean(req.DeployPath)
	if !strings.HasPrefix(clean, "/") || clean == "/" || clean != req.DeployPath || strings.Contains(req.DeployPath, "..") {
		return errors.New("deployPath must be a normalized absolute Linux path")
	}
	if req.Type == database.DeploymentProjectJava && strings.TrimSpace(req.ServiceName) == "" {
		return errors.New("serviceName is required for Java projects")
	}
	if service := strings.TrimSpace(req.ServiceName); service != "" && !serviceNamePattern.MatchString(service) {
		return errors.New("serviceName contains unsupported characters")
	}
	if req.KeepReleases == 0 {
		req.KeepReleases = 5
	}
	if req.KeepReleases < 2 || req.KeepReleases > 50 {
		return errors.New("keepReleases must be between 2 and 50")
	}
	if health := strings.TrimSpace(req.HealthURL); health != "" {
		u, err := url.Parse(health)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.User != nil {
			return errors.New("healthUrl must be an absolute http or https URL")
		}
	}
	return nil
}

func deploymentArtifactSuffix(projectType, name string) (string, error) {
	lower := strings.ToLower(name)
	if projectType == database.DeploymentProjectJava {
		if !strings.HasSuffix(lower, ".jar") {
			return "", errors.New("Java projects require a .jar artifact")
		}
		return ".jar", nil
	}
	for _, suffix := range []string{".tar.gz", ".tgz", ".zip"} {
		if strings.HasSuffix(lower, suffix) {
			return suffix, nil
		}
	}
	return "", errors.New("static projects require a .zip, .tar.gz, or .tgz artifact")
}

func newArtifactToken() (plain, hash string, err error) {
	raw := make([]byte, 32)
	if _, err = rand.Read(raw); err != nil {
		return "", "", err
	}
	plain = hex.EncodeToString(raw)
	digest := sha256.Sum256([]byte(plain))
	return plain, hex.EncodeToString(digest[:]), nil
}

func parseUintParam(c *gin.Context, name string) (uint, bool) {
	id, err := strconv.ParseUint(c.Param(name), 10, 64)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid " + name})
		return 0, false
	}
	return uint(id), true
}

func respondDeploymentDBError(c *gin.Context, err error, entity string) {
	if errors.Is(err, gorm.ErrRecordNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": entity + " not found"})
		return
	}
	c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load " + entity})
}
