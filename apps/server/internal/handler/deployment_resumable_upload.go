package handler

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

const (
	deploymentUploadChunkBytes = int64(4 * 1024 * 1024)
	deploymentUploadTTL        = 24 * time.Hour
)

type createDeploymentUploadRequest struct {
	Version       string `json:"version" binding:"required"`
	ArtifactName  string `json:"artifactName" binding:"required"`
	ArtifactSize  int64  `json:"artifactSize" binding:"required"`
	Extract       *bool  `json:"extract"`
	StripTopLevel bool   `json:"stripTopLevel"`
	Notes         string `json:"notes"`
}

type deploymentUploadSessionView struct {
	ID           string    `json:"id"`
	ProjectID    uint      `json:"projectId"`
	Version      string    `json:"version"`
	ArtifactName string    `json:"artifactName"`
	ArtifactSize int64     `json:"artifactSize"`
	UploadOffset int64     `json:"uploadOffset"`
	ChunkSize    int64     `json:"chunkSize"`
	ExpiresAt    time.Time `json:"expiresAt"`
}

func deploymentUploadView(session database.DeploymentUploadSession) deploymentUploadSessionView {
	return deploymentUploadSessionView{
		ID: session.ID, ProjectID: session.ProjectID, Version: session.Version,
		ArtifactName: session.ArtifactName, ArtifactSize: session.ArtifactSize,
		UploadOffset: session.UploadedSize, ChunkSize: deploymentUploadChunkBytes,
		ExpiresAt: session.ExpiresAt,
	}
}

func (h *DeploymentHandler) CreateUploadSession(c *gin.Context) {
	projectID, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var project database.DeploymentProject
	if err := h.db.First(&project, projectID).Error; err != nil {
		respondDeploymentDBError(c, err, "project")
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64*1024)
	var req createDeploymentUploadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Version = strings.TrimSpace(req.Version)
	req.ArtifactName = filepath.Base(strings.TrimSpace(req.ArtifactName))
	req.Notes = strings.TrimSpace(req.Notes)
	if !releaseVersionPattern.MatchString(req.Version) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "version must contain only letters, numbers, dot, dash, or underscore"})
		return
	}
	if req.ArtifactSize <= 0 || req.ArtifactSize > h.maxArtifact {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": fmt.Sprintf("artifact must be between 1 byte and %d bytes", h.maxArtifact)})
		return
	}
	if _, err := deploymentArtifactSuffix(project.Type, req.ArtifactName); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	extract := project.Type == database.DeploymentProjectStatic && project.ExtractArchive
	if req.Extract != nil {
		extract = *req.Extract
	}
	if project.Type == database.DeploymentProjectJava && (extract || req.StripTopLevel) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Java releases must publish one JAR without extraction"})
		return
	}
	if req.StripTopLevel && (!extract || project.Type != database.DeploymentProjectStatic) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "stripTopLevel requires an extracted static archive"})
		return
	}
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	h.uploadMu.Lock()
	defer h.uploadMu.Unlock()
	h.removeExpiredUploadSessions()
	var releaseCount int64
	if err := h.db.Model(&database.DeploymentRelease{}).
		Where("project_id = ? AND version = ?", projectID, req.Version).Count(&releaseCount).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check release version"})
		return
	}
	if releaseCount > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "this version already exists"})
		return
	}
	var existing database.DeploymentUploadSession
	err := h.db.Where("project_id = ? AND version = ?", projectID, req.Version).First(&existing).Error
	if err == nil {
		if existing.CreatedBy != user.ID || existing.ArtifactName != req.ArtifactName || existing.ArtifactSize != req.ArtifactSize ||
			existing.StripTopLevel != req.StripTopLevel || existing.Extract == nil || *existing.Extract != extract {
			c.JSON(http.StatusConflict, gin.H{"error": "this version already has a different upload in progress"})
			return
		}
		if _, err := h.reconcileUploadOffset(&existing); err != nil {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, deploymentUploadView(existing))
		return
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check upload session"})
		return
	}
	session := database.DeploymentUploadSession{
		ID: uuid.NewString(), ProjectID: projectID, Version: req.Version,
		ArtifactName: req.ArtifactName, ArtifactSize: req.ArtifactSize,
		Extract: &extract, StripTopLevel: req.StripTopLevel, Notes: req.Notes,
		CreatedBy: user.ID, ExpiresAt: time.Now().Add(deploymentUploadTTL),
	}
	if err := h.db.Create(&session).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "failed to create upload session"})
		return
	}
	c.JSON(http.StatusCreated, deploymentUploadView(session))
}

func (h *DeploymentHandler) GetUploadSession(c *gin.Context) {
	h.uploadMu.Lock()
	defer h.uploadMu.Unlock()
	session, ok := h.authorizedUploadSession(c)
	if !ok {
		return
	}
	if _, err := h.reconcileUploadOffset(&session); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, deploymentUploadView(session))
}

func (h *DeploymentHandler) AppendUploadChunk(c *gin.Context) {
	offset, err := strconv.ParseInt(strings.TrimSpace(c.GetHeader("Upload-Offset")), 10, 64)
	if err != nil || offset < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Upload-Offset must be a non-negative integer"})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, deploymentUploadChunkBytes+1)
	chunk, err := io.ReadAll(c.Request.Body)
	if err != nil || int64(len(chunk)) > deploymentUploadChunkBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": fmt.Sprintf("upload chunk must be at most %d bytes", deploymentUploadChunkBytes)})
		return
	}
	if len(chunk) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "upload chunk is empty"})
		return
	}

	h.uploadMu.Lock()
	defer h.uploadMu.Unlock()
	session, ok := h.authorizedUploadSession(c)
	if !ok {
		return
	}
	actual, err := h.reconcileUploadOffset(&session)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if offset != actual {
		c.JSON(http.StatusConflict, gin.H{"error": "upload offset does not match the Server", "uploadOffset": actual})
		return
	}
	if int64(len(chunk)) > session.ArtifactSize-actual {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "chunk exceeds the declared artifact size"})
		return
	}
	partPath := h.uploadPartPath(session.ID)
	if metadata, statErr := os.Lstat(partPath); statErr == nil && (!metadata.Mode().IsRegular() || metadata.Mode()&os.ModeSymlink != 0) {
		c.JSON(http.StatusConflict, gin.H{"error": "upload path is not a regular file"})
		return
	} else if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to inspect upload file"})
		return
	}
	file, err := os.OpenFile(partPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o640)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open upload file"})
		return
	}
	written, writeErr := file.Write(chunk)
	if writeErr == nil && written == len(chunk) {
		writeErr = file.Sync()
	}
	closeErr := file.Close()
	if writeErr != nil || closeErr != nil || written != len(chunk) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist upload chunk"})
		return
	}
	session.UploadedSize = actual + int64(written)
	session.ExpiresAt = time.Now().Add(deploymentUploadTTL)
	if err := h.db.Model(&session).Updates(map[string]any{"uploaded_size": session.UploadedSize, "expires_at": session.ExpiresAt}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist upload offset"})
		return
	}
	c.Header("Upload-Offset", strconv.FormatInt(session.UploadedSize, 10))
	c.JSON(http.StatusOK, deploymentUploadView(session))
}

func (h *DeploymentHandler) CompleteUploadSession(c *gin.Context) {
	h.uploadMu.Lock()
	defer h.uploadMu.Unlock()
	session, ok := h.authorizedUploadSession(c)
	if !ok {
		return
	}
	actual, err := h.reconcileUploadOffset(&session)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if actual != session.ArtifactSize {
		c.JSON(http.StatusConflict, gin.H{"error": "upload is incomplete", "uploadOffset": actual})
		return
	}
	partPath := h.uploadPartPath(session.ID)
	digest, err := hashDeploymentUpload(partPath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify uploaded artifact"})
		return
	}
	var project database.DeploymentProject
	if err := h.db.First(&project, session.ProjectID).Error; err != nil {
		respondDeploymentDBError(c, err, "project")
		return
	}
	suffix, err := deploymentArtifactSuffix(project.Type, session.ArtifactName)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	projectDir := filepath.Join(h.storageRoot, strconv.FormatUint(uint64(session.ProjectID), 10))
	if err := os.MkdirAll(projectDir, 0o750); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to prepare artifact storage"})
		return
	}
	finalPath := filepath.Join(projectDir, session.ID+suffix)
	if err := os.Rename(partPath, finalPath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to finalize uploaded artifact"})
		return
	}
	release := database.DeploymentRelease{
		ID: session.ID, ProjectID: session.ProjectID, Version: session.Version,
		ArtifactName: session.ArtifactName, ArtifactPath: finalPath,
		ArtifactSize: session.ArtifactSize, SHA256: digest, Extract: session.Extract,
		StripTopLevel: session.StripTopLevel, Notes: session.Notes, CreatedBy: session.CreatedBy,
	}
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&release).Error; err != nil {
			return err
		}
		return tx.Delete(&session).Error
	}); err != nil {
		_ = os.Rename(finalPath, partPath)
		c.JSON(http.StatusConflict, gin.H{"error": "this version already exists or could not be finalized"})
		return
	}
	c.JSON(http.StatusCreated, release)
}

func (h *DeploymentHandler) AbortUploadSession(c *gin.Context) {
	h.uploadMu.Lock()
	defer h.uploadMu.Unlock()
	session, ok := h.authorizedUploadSession(c)
	if !ok {
		return
	}
	_ = os.Remove(h.uploadPartPath(session.ID))
	if err := h.db.Delete(&session).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to abort upload session"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

func (h *DeploymentHandler) authorizedUploadSession(c *gin.Context) (database.DeploymentUploadSession, bool) {
	var session database.DeploymentUploadSession
	if err := h.db.First(&session, "id = ?", strings.TrimSpace(c.Param("sessionId"))).Error; err != nil {
		respondDeploymentDBError(c, err, "upload session")
		return session, false
	}
	user := GetCurrentUser(c)
	if user == nil || session.CreatedBy != user.ID {
		c.JSON(http.StatusForbidden, gin.H{"error": "upload session belongs to another user"})
		return session, false
	}
	if !time.Now().Before(session.ExpiresAt) {
		_ = os.Remove(h.uploadPartPath(session.ID))
		_ = h.db.Delete(&session).Error
		c.JSON(http.StatusGone, gin.H{"error": "upload session expired"})
		return session, false
	}
	return session, true
}

func (h *DeploymentHandler) reconcileUploadOffset(session *database.DeploymentUploadSession) (int64, error) {
	metadata, err := os.Lstat(h.uploadPartPath(session.ID))
	actual := int64(0)
	if err == nil {
		if !metadata.Mode().IsRegular() || metadata.Mode()&os.ModeSymlink != 0 {
			return 0, errors.New("upload path is not a regular file")
		}
		actual = metadata.Size()
	} else if !errors.Is(err, os.ErrNotExist) {
		return 0, errors.New("failed to inspect upload file")
	}
	if actual > session.ArtifactSize {
		return actual, errors.New("upload file exceeds its declared size")
	}
	if actual != session.UploadedSize {
		session.UploadedSize = actual
		if err := h.db.Model(session).Update("uploaded_size", actual).Error; err != nil {
			return actual, errors.New("failed to reconcile upload offset")
		}
	}
	return actual, nil
}

func (h *DeploymentHandler) removeExpiredUploadSessions() {
	var sessions []database.DeploymentUploadSession
	if err := h.db.Where("expires_at <= ?", time.Now()).Find(&sessions).Error; err != nil {
		return
	}
	for _, session := range sessions {
		_ = os.Remove(h.uploadPartPath(session.ID))
		_ = h.db.Delete(&session).Error
	}
}

func (h *DeploymentHandler) uploadPartPath(id string) string {
	return filepath.Join(h.storageRoot, ".uploads", id+".part")
}

func hashDeploymentUpload(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}
