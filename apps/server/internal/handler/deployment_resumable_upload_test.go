package handler

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestDeploymentUploadResumesFromPersistedOffset(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:resumable-deployment-upload?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(
		&database.DeploymentProject{},
		&database.DeploymentRelease{},
		&database.DeploymentUploadSession{},
	); err != nil {
		t.Fatal(err)
	}
	project := database.DeploymentProject{
		Name: "resumable-java", Type: database.DeploymentProjectJava, AgentID: "agent-1",
		DeployPath: "/opt/nanolink/apps/resumable-java", ServiceName: "resumable-java.service",
		KeepReleases: 5, CreatedBy: 1,
	}
	if err := db.Create(&project).Error; err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".uploads"), 0o750); err != nil {
		t.Fatal(err)
	}
	newHandler := func() *DeploymentHandler {
		return &DeploymentHandler{db: db, storageRoot: root, maxArtifact: 1024, logger: zap.NewNop().Sugar()}
	}
	register := func(handler *DeploymentHandler) *gin.Engine {
		router := gin.New()
		router.Use(func(c *gin.Context) {
			c.Set(ContextKeyUser, &database.User{ID: 1, Username: "admin", IsSuperAdmin: true})
			c.Next()
		})
		router.POST("/projects/:id/uploads", handler.CreateUploadSession)
		router.GET("/uploads/:sessionId", handler.GetUploadSession)
		router.PATCH("/uploads/:sessionId", handler.AppendUploadChunk)
		router.POST("/uploads/:sessionId/complete", handler.CompleteUploadSession)
		return router
	}

	artifact := []byte("0123456789abcdef")
	createBody := []byte(`{"version":"1.0.0","artifactName":"app.jar","artifactSize":16}`)
	create := httptest.NewRequest(http.MethodPost, "/projects/"+strconv.FormatUint(uint64(project.ID), 10)+"/uploads", bytes.NewReader(createBody))
	create.Header.Set("Content-Type", "application/json")
	created := httptest.NewRecorder()
	router := register(newHandler())
	router.ServeHTTP(created, create)
	if created.Code != http.StatusCreated {
		t.Fatalf("create status = %d; body=%s", created.Code, created.Body.String())
	}
	var session deploymentUploadSessionView
	if err := json.Unmarshal(created.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}

	first := httptest.NewRequest(http.MethodPatch, "/uploads/"+session.ID, bytes.NewReader(artifact[:6]))
	first.Header.Set("Upload-Offset", "0")
	firstResult := httptest.NewRecorder()
	router.ServeHTTP(firstResult, first)
	if firstResult.Code != http.StatusOK {
		t.Fatalf("first chunk status = %d; body=%s", firstResult.Code, firstResult.Body.String())
	}

	// Constructing a new handler simulates a Server process restart. The offset
	// remains available because both metadata and the .part file are persistent.
	router = register(newHandler())
	statusRequest := httptest.NewRequest(http.MethodGet, "/uploads/"+session.ID, nil)
	statusResult := httptest.NewRecorder()
	router.ServeHTTP(statusResult, statusRequest)
	if statusResult.Code != http.StatusOK {
		t.Fatalf("status after restart = %d; body=%s", statusResult.Code, statusResult.Body.String())
	}
	var resumed deploymentUploadSessionView
	if err := json.Unmarshal(statusResult.Body.Bytes(), &resumed); err != nil {
		t.Fatal(err)
	}
	if resumed.UploadOffset != 6 {
		t.Fatalf("persisted offset = %d, want 6", resumed.UploadOffset)
	}

	wrong := httptest.NewRequest(http.MethodPatch, "/uploads/"+session.ID, bytes.NewReader([]byte("duplicate")))
	wrong.Header.Set("Upload-Offset", "0")
	wrongResult := httptest.NewRecorder()
	router.ServeHTTP(wrongResult, wrong)
	if wrongResult.Code != http.StatusConflict {
		t.Fatalf("wrong offset status = %d, want %d", wrongResult.Code, http.StatusConflict)
	}

	second := httptest.NewRequest(http.MethodPatch, "/uploads/"+session.ID, bytes.NewReader(artifact[6:]))
	second.Header.Set("Upload-Offset", "6")
	secondResult := httptest.NewRecorder()
	router.ServeHTTP(secondResult, second)
	if secondResult.Code != http.StatusOK {
		t.Fatalf("second chunk status = %d; body=%s", secondResult.Code, secondResult.Body.String())
	}
	complete := httptest.NewRequest(http.MethodPost, "/uploads/"+session.ID+"/complete", nil)
	completeResult := httptest.NewRecorder()
	router.ServeHTTP(completeResult, complete)
	if completeResult.Code != http.StatusCreated {
		t.Fatalf("complete status = %d; body=%s", completeResult.Code, completeResult.Body.String())
	}
	var release database.DeploymentRelease
	if err := json.Unmarshal(completeResult.Body.Bytes(), &release); err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(artifact)
	if release.SHA256 != hex.EncodeToString(digest[:]) {
		t.Fatalf("release digest = %s", release.SHA256)
	}
	if err := db.First(&release, "id = ?", release.ID).Error; err != nil {
		t.Fatal(err)
	}
	stored, err := os.ReadFile(release.ArtifactPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(stored, artifact) {
		t.Fatalf("stored artifact = %q", stored)
	}
	var sessionCount int64
	if err := db.Model(&database.DeploymentUploadSession{}).Where("id = ?", session.ID).Count(&sessionCount).Error; err != nil {
		t.Fatal(err)
	}
	if sessionCount != 0 {
		t.Fatal("completed upload session was not removed")
	}
}
