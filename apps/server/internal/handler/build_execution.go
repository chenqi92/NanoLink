package handler

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

var errInvalidBuildInput = errors.New("invalid build input")

type buildDispatchInput struct {
	Version      string
	Trigger      string
	UserID       uint
	Username     string
	BaseURL      string
	SourcePath   string
	SourceName   string
	SourceSize   int64
	SourceSHA256 string
}

func (h *BuildHandler) dispatchPipeline(pipeline database.BuildPipeline, input buildDispatchInput) (*database.BuildRun, error) {
	if !pipeline.Enabled {
		return nil, fmt.Errorf("%w: pipeline is disabled", errInvalidBuildInput)
	}
	version := strings.TrimSpace(input.Version)
	if version == "" {
		version = time.Now().Format("2006.01.02-150405")
	}
	if !releaseVersionPattern.MatchString(version) {
		return nil, fmt.Errorf("%w: version contains unsupported characters", errInvalidBuildInput)
	}
	if input.Trigger == "" {
		input.Trigger = database.BuildTriggerManual
	}
	if input.Username == "" {
		input.Username = input.Trigger
	}

	now := time.Now()
	cutoff := now.Add(-time.Duration(pipeline.TimeoutSeconds+300) * time.Second)
	_ = h.db.Model(&database.BuildRun{}).
		Where("pipeline_id = ? AND status IN ? AND started_at < ?", pipeline.ID, []string{database.BuildStatusQueued, database.BuildStatusRunning}, cutoff).
		Updates(map[string]any{"status": database.BuildStatusFailed, "error": "build timed out before a new run was requested", "finished_at": &now}).Error
	fetchedRemote := false
	if pipeline.SourceType == database.BuildSourceURL && input.SourcePath == "" {
		path, name, size, digest, err := h.fetchRemoteSource(pipeline.ID, pipeline.SourceURL)
		if err != nil {
			return nil, fmt.Errorf("fetch source: %w", err)
		}
		input.SourcePath, input.SourceName, input.SourceSize, input.SourceSHA256 = path, name, size, digest
		fetchedRemote = true
	}
	keepFetchedSource := false
	defer func() {
		if fetchedRemote && !keepFetchedSource {
			_ = os.Remove(input.SourcePath)
		}
	}()
	if pipeline.SourceType == database.BuildSourceUpload && input.SourcePath == "" {
		return nil, fmt.Errorf("%w: source archive is required", errInvalidBuildInput)
	}
	if pipeline.SourceType != database.BuildSourceGit {
		if _, err := h.safeStoredPath(input.SourcePath, "sources"); err != nil {
			return nil, fmt.Errorf("%w: invalid stored source", errInvalidBuildInput)
		}
	}

	// Only the short state-allocation section is serialized. Remote downloads
	// happen above so a slow source cannot block unrelated pipelines.
	h.dispatchMu.Lock()
	defer h.dispatchMu.Unlock()

	var active int64
	if err := h.db.Model(&database.BuildRun{}).Where("pipeline_id = ? AND status IN ?", pipeline.ID, []string{database.BuildStatusQueued, database.BuildStatusRunning}).Count(&active).Error; err != nil {
		return nil, errors.New("failed to check active builds")
	}
	if active > 0 {
		return nil, errors.New("this pipeline already has a build in progress")
	}

	variables, err := h.runtimeVariables(pipeline.VariablesJSON)
	if err != nil {
		return nil, err
	}
	variablesJSON, err := json.Marshal(variables)
	if err != nil {
		return nil, err
	}
	var runNumber int
	if err := h.db.Model(&database.BuildRun{}).Where("pipeline_id = ?", pipeline.ID).Select("COALESCE(MAX(run_number), 0)").Scan(&runNumber).Error; err != nil {
		return nil, errors.New("failed to allocate build number")
	}
	runNumber++

	commandID := uuid.NewString()
	run := &database.BuildRun{
		ID: uuid.NewString(), PipelineID: pipeline.ID, RunNumber: runNumber, AgentID: pipeline.AgentID, CommandID: commandID,
		Status: database.BuildStatusQueued, Trigger: input.Trigger, Version: version,
		SourceType: pipeline.SourceType, SourceURL: pipeline.SourceURL, SourceRef: pipeline.SourceRef,
		SourceName: input.SourceName, SourcePath: input.SourcePath, SourceSize: input.SourceSize, SourceSHA256: input.SourceSHA256,
		RunnerType: pipeline.RunnerType, ContainerImage: pipeline.ContainerImage, StagesJSON: pipeline.StagesJSON, VariablesJSON: pipeline.VariablesJSON,
		ArtifactPattern: pipeline.ArtifactPattern, ArtifactName: pipeline.ArtifactName, PublishProjectID: pipeline.PublishProjectID,
		TimeoutSeconds: pipeline.TimeoutSeconds, CreatedBy: input.UserID, CreatedByName: input.Username, StartedAt: &now,
	}
	sourcePlain := ""
	if run.SourcePath != "" {
		sourcePlain, run.SourceTokenHash, err = newArtifactToken()
		if err != nil {
			return nil, errors.New("failed to create source token")
		}
		expires := now.Add(h.tokenTTL)
		run.SourceTokenExpires = &expires
	}
	artifactPlain, artifactHash, err := newArtifactToken()
	if err != nil {
		return nil, errors.New("failed to create artifact token")
	}
	run.ArtifactTokenHash = artifactHash
	artifactExpires := now.Add(time.Duration(run.TimeoutSeconds)*time.Second + h.tokenTTL)
	run.ArtifactTokenExpires = &artifactExpires
	if err := h.db.Create(run).Error; err != nil {
		return nil, errors.New("failed to create build run")
	}
	keepFetchedSource = true

	params := map[string]string{
		"run_id": run.ID, "source_type": run.SourceType, "source_url": run.SourceURL, "source_ref": run.SourceRef,
		"source_name": run.SourceName, "source_sha256": run.SourceSHA256,
		"runner_type": run.RunnerType, "container_image": run.ContainerImage,
		"stages_json": run.StagesJSON, "variables_json": string(variablesJSON),
		"artifact_pattern": run.ArtifactPattern, "artifact_name": run.ArtifactName,
		"timeout_seconds": strconv.Itoa(run.TimeoutSeconds),
	}
	if sourcePlain != "" {
		params["source_download_url"], err = h.callbackURL(input.BaseURL, "/api/build-source-downloads/"+run.ID, sourcePlain)
		if err != nil {
			h.failUndispatchedRun(run, err)
			return nil, err
		}
	}
	params["artifact_upload_url"], err = h.callbackURL(input.BaseURL, "/api/build-artifact-uploads/"+run.ID, artifactPlain)
	if err != nil {
		h.failUndispatchedRun(run, err)
		return nil, err
	}
	params["log_update_url"], err = h.callbackURL(input.BaseURL, "/api/build-log-updates/"+run.ID, artifactPlain)
	if err != nil {
		h.failUndispatchedRun(run, err)
		return nil, err
	}

	h.grpc.RegisterDispatchedCommand(commandID, run.AgentID, input.UserID, input.Username, pb.CommandType_BUILD_EXECUTE.String())
	command := &pb.Command{CommandId: commandID, Type: pb.CommandType_BUILD_EXECUTE, Target: pipeline.Name, Params: params}
	if err := h.grpc.SendCommandToAgent(run.AgentID, command); err != nil {
		h.failUndispatchedRun(run, err)
		return nil, fmt.Errorf("build agent is offline or cannot accept the run: %w", err)
	}
	_ = h.db.Model(run).Update("status", database.BuildStatusRunning).Error
	_ = h.db.Model(&database.BuildPipeline{}).Where("id = ?", pipeline.ID).Update("last_run_at", &now).Error
	run.Status = database.BuildStatusRunning
	return run, nil
}

func (h *BuildHandler) failUndispatchedRun(run *database.BuildRun, cause error) {
	finished := time.Now()
	run.Status, run.Error, run.FinishedAt = database.BuildStatusFailed, cause.Error(), &finished
	_ = h.db.Model(run).Updates(map[string]any{
		"status": run.Status, "error": run.Error, "finished_at": run.FinishedAt,
		"source_token_hash": "", "source_token_expires": nil, "artifact_token_hash": "", "artifact_token_expires": nil,
	}).Error
	h.cleanupRunSource(run)
}

func (h *BuildHandler) DownloadSource(c *gin.Context) {
	var run database.BuildRun
	if err := h.db.First(&run, "id = ?", c.Param("runId")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "source token not found"})
		return
	}
	if !tokenMatches(c.Query("token"), run.SourceTokenHash) || run.SourceTokenExpires == nil || time.Now().After(*run.SourceTokenExpires) || (run.Status != database.BuildStatusQueued && run.Status != database.BuildStatusRunning) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "source token is invalid or expired"})
		return
	}
	path, err := h.safeStoredPath(run.SourcePath, "sources")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid source path"})
		return
	}
	c.Header("X-Source-SHA256", run.SourceSHA256)
	c.FileAttachment(path, run.SourceName)
}

func (h *BuildHandler) UploadArtifact(c *gin.Context) {
	var run database.BuildRun
	if err := h.db.First(&run, "id = ?", c.Param("runId")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "artifact token not found"})
		return
	}
	if !tokenMatches(c.Query("token"), run.ArtifactTokenHash) || run.ArtifactTokenExpires == nil || time.Now().After(*run.ArtifactTokenExpires) || (run.Status != database.BuildStatusQueued && run.Status != database.BuildStatusRunning) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "artifact token is invalid or expired"})
		return
	}
	if strings.TrimSpace(c.GetHeader("X-Artifact-Name")) != run.ArtifactName {
		c.JSON(http.StatusBadRequest, gin.H{"error": "artifact name does not match the pipeline definition"})
		return
	}
	expectedSize, err := strconv.ParseInt(c.GetHeader("X-Artifact-Size"), 10, 64)
	if err != nil || expectedSize <= 0 || expectedSize > h.maxArtifact {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "artifact size is invalid or exceeds the configured limit"})
		return
	}
	expectedHash := strings.ToLower(strings.TrimSpace(c.GetHeader("X-Artifact-SHA256")))
	if len(expectedHash) != 64 || !isHex(expectedHash) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "artifact SHA-256 is invalid"})
		return
	}
	var existing int64
	if err := h.db.Model(&database.BuildArtifact{}).Where("run_id = ?", run.ID).Count(&existing).Error; err != nil || existing > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "this run already has an artifact"})
		return
	}

	dir := filepath.Join(h.storageRoot, "artifacts", strconv.FormatUint(uint64(run.PipelineID), 10))
	if err := os.MkdirAll(dir, 0o750); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to prepare artifact storage"})
		return
	}
	suffix := filepath.Ext(run.ArtifactName)
	finalPath := filepath.Join(dir, uuid.NewString()+suffix)
	tmpPath := finalPath + ".upload"
	output, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create artifact"})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, h.maxArtifact+1)
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(output, hash), io.LimitReader(c.Request.Body, h.maxArtifact+1))
	closeErr := output.Close()
	actualHash := hex.EncodeToString(hash.Sum(nil))
	if copyErr != nil || closeErr != nil || written != expectedSize || written > h.maxArtifact || actualHash != expectedHash {
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusBadRequest, gin.H{"error": "artifact body does not match the declared size or SHA-256"})
		return
	}
	// Cancellation can race a large upload. Re-check the mutable run state after
	// the body is verified and before the file becomes an immutable artifact.
	var current database.BuildRun
	if err := h.db.Select("status", "artifact_token_hash", "artifact_token_expires").First(&current, "id = ?", run.ID).Error; err != nil ||
		!tokenMatches(c.Query("token"), current.ArtifactTokenHash) ||
		current.ArtifactTokenExpires == nil || time.Now().After(*current.ArtifactTokenExpires) ||
		(current.Status != database.BuildStatusQueued && current.Status != database.BuildStatusRunning) {
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusConflict, gin.H{"error": "build finished or was canceled during artifact upload"})
		return
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to finalize artifact"})
		return
	}
	artifact := database.BuildArtifact{ID: uuid.NewString(), RunID: run.ID, Name: run.ArtifactName, Path: finalPath, Size: written, SHA256: actualHash}
	if err := h.db.Create(&artifact).Error; err != nil {
		_ = os.Remove(finalPath)
		c.JSON(http.StatusConflict, gin.H{"error": "failed to register artifact"})
		return
	}
	c.JSON(http.StatusCreated, artifact)
}

func (h *BuildHandler) UpdateLogs(c *gin.Context) {
	var run database.BuildRun
	if err := h.db.First(&run, "id = ?", c.Param("runId")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "log token not found"})
		return
	}
	if !tokenMatches(c.Query("token"), run.ArtifactTokenHash) || run.ArtifactTokenExpires == nil || time.Now().After(*run.ArtifactTokenExpires) || (run.Status != database.BuildStatusQueued && run.Status != database.BuildStatusRunning) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "log token is invalid or expired"})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, int64(h.maxLog)+1)
	body, err := io.ReadAll(c.Request.Body)
	if err != nil || len(body) > h.maxLog {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "build log exceeds the configured limit"})
		return
	}
	masked := h.maskSecrets(run.VariablesJSON, string(body))
	if err := h.db.Model(&run).Update("output", truncateUTF8(masked, h.maxLog)).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist build log"})
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *BuildHandler) CancelRun(c *gin.Context) {
	var run database.BuildRun
	if err := h.db.First(&run, "id = ?", c.Param("runId")).Error; err != nil {
		respondDeploymentDBError(c, err, "build run")
		return
	}
	if run.Status != database.BuildStatusQueued && run.Status != database.BuildStatusRunning {
		c.JSON(http.StatusConflict, gin.H{"error": "only queued or running builds can be canceled"})
		return
	}

	user := GetCurrentUser(c)
	commandID := uuid.NewString()
	h.grpc.RegisterDispatchedCommand(commandID, run.AgentID, user.ID, user.Username, pb.CommandType_BUILD_CANCEL.String())
	command := &pb.Command{
		CommandId: commandID,
		Type:      pb.CommandType_BUILD_CANCEL,
		Target:    run.ID,
		Params:    map[string]string{"run_id": run.ID},
	}
	if err := h.grpc.SendCommandToAgent(run.AgentID, command); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "build agent is offline or cannot accept cancellation"})
		return
	}

	finished := time.Now()
	result := h.db.Model(&database.BuildRun{}).
		Where("id = ? AND status IN ?", run.ID, []string{database.BuildStatusQueued, database.BuildStatusRunning}).
		Updates(map[string]any{
			"status": database.BuildStatusCanceled, "error": "canceled by " + user.Username,
			"finished_at": &finished, "source_token_hash": "", "source_token_expires": nil,
			"artifact_token_hash": "", "artifact_token_expires": nil,
		})
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist build cancellation"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "build already finished"})
		return
	}
	run.Status = database.BuildStatusCanceled
	run.Error = "canceled by " + user.Username
	run.FinishedAt = &finished
	h.cleanupRunSource(&run)
	c.JSON(http.StatusOK, run)
}

func (h *BuildHandler) HandleCommandResult(agentID, commandID, output string, success bool) {
	var run database.BuildRun
	if err := h.db.Where("command_id = ? AND agent_id = ?", commandID, agentID).First(&run).Error; err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			h.logger.Warnf("build result lookup failed: %v", err)
		}
		return
	}
	if run.Status != database.BuildStatusQueued && run.Status != database.BuildStatusRunning {
		return
	}
	finished := time.Now()
	output = h.maskSecrets(run.VariablesJSON, output)
	updates := map[string]any{
		"output": truncateUTF8(output, h.maxLog), "finished_at": &finished,
		"source_token_hash": "", "source_token_expires": nil, "artifact_token_hash": "", "artifact_token_expires": nil,
	}
	if success {
		var artifact database.BuildArtifact
		if err := h.db.First(&artifact, "run_id = ?", run.ID).Error; err != nil {
			success = false
			updates["error"] = "build agent reported success but did not upload an artifact"
		} else if run.PublishProjectID != nil {
			release, err := h.deployment.ImportBuildArtifact(*run.PublishProjectID, run.Version, fmt.Sprintf("Built by pipeline #%d", run.RunNumber), artifact.Path, artifact.Name, artifact.Size, artifact.SHA256, run.CreatedBy)
			if err != nil {
				success = false
				updates["error"] = "artifact built, but publishing to Deployment Center failed: " + err.Error()
			} else {
				_ = h.db.Model(&artifact).Update("deployment_release_id", release.ID).Error
			}
		}
	}
	if success {
		updates["status"] = database.BuildStatusSuccess
	} else {
		updates["status"] = database.BuildStatusFailed
		if _, ok := updates["error"]; !ok {
			updates["error"] = truncateUTF8(output, 4000)
		}
	}
	if err := h.db.Model(&run).Updates(updates).Error; err != nil {
		h.logger.Warnf("persist build result: %v", err)
	}
	h.cleanupRunSource(&run)
	h.pruneBuildArtifacts(run.PipelineID)
}

func (h *BuildHandler) pruneBuildArtifacts(pipelineID uint) {
	var pipeline database.BuildPipeline
	if err := h.db.Select("id", "keep_artifacts").First(&pipeline, pipelineID).Error; err != nil {
		return
	}
	keep := pipeline.KeepArtifacts
	if keep <= 0 {
		keep = 20
	}
	var artifacts []database.BuildArtifact
	if err := h.db.Table("build_artifacts").
		Select("build_artifacts.*").
		Joins("JOIN build_runs ON build_runs.id = build_artifacts.run_id").
		Where("build_runs.pipeline_id = ?", pipelineID).
		Order("build_artifacts.created_at DESC").
		Find(&artifacts).Error; err != nil {
		h.logger.Warnf("list stale build artifacts: %v", err)
		return
	}
	if len(artifacts) <= keep {
		return
	}
	for _, artifact := range artifacts[keep:] {
		if path, err := h.safeStoredPath(artifact.Path, "artifacts"); err == nil {
			_ = os.Remove(path)
		}
		_ = h.db.Delete(&artifact).Error
	}
}

func (h *BuildHandler) maskSecrets(rawVariables, output string) string {
	var variables []buildVariable
	if output == "" || json.Unmarshal([]byte(rawVariables), &variables) != nil {
		return output
	}
	for _, variable := range variables {
		if !variable.Secret || variable.Value == "" || h.codec == nil {
			continue
		}
		plain, err := h.codec.DecryptSecret(variable.Value)
		if err == nil && len(plain) >= 4 {
			output = strings.ReplaceAll(output, plain, "***")
		}
	}
	return output
}

func (h *BuildHandler) reconcileRunTimeout(run *database.BuildRun) {
	if (run.Status != database.BuildStatusQueued && run.Status != database.BuildStatusRunning) || run.StartedAt == nil || time.Since(*run.StartedAt) <= time.Duration(run.TimeoutSeconds+300)*time.Second {
		return
	}
	finished := time.Now()
	run.Status = database.BuildStatusFailed
	run.Error = "build timed out before the agent returned a result"
	run.FinishedAt = &finished
	_ = h.db.Model(run).Updates(map[string]any{"status": run.Status, "error": run.Error, "finished_at": run.FinishedAt, "source_token_hash": "", "artifact_token_hash": ""}).Error
	h.cleanupRunSource(run)
}

func (h *BuildHandler) cleanupRunSource(run *database.BuildRun) {
	if strings.TrimSpace(run.SourcePath) == "" {
		return
	}
	path, err := h.safeStoredPath(run.SourcePath, "sources")
	if err == nil {
		_ = os.Remove(path)
	}
}

func isHex(value string) bool { _, err := hex.DecodeString(value); return err == nil }

func truncateUTF8(value string, max int) string {
	if max <= 0 || len(value) <= max {
		return value
	}
	bytes := []byte(value)[:max]
	for len(bytes) > 0 && !utf8.Valid(bytes) {
		bytes = bytes[:len(bytes)-1]
	}
	return string(bytes) + "\n... output truncated"
}
