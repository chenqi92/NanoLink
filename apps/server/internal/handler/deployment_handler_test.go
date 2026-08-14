package handler

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestValidateDeploymentProjectRequest(t *testing.T) {
	req := deploymentProjectRequest{
		Name: "orders", Type: "java", AgentID: "agent-1",
		DeployPath: "/opt/nanolink/apps/orders", ServiceName: "orders.service", KeepReleases: 5,
	}
	if err := validateDeploymentProjectRequest(&req); err != nil {
		t.Fatalf("valid request rejected: %v", err)
	}

	req.DeployPath = "/opt/nanolink/apps/../other"
	if err := validateDeploymentProjectRequest(&req); err == nil {
		t.Fatal("traversal path was accepted")
	}

	req.DeployPath = "/opt/nanolink/apps/orders"
	req.ServiceName = "--no-block"
	if err := validateDeploymentProjectRequest(&req); err == nil {
		t.Fatal("option-like service name was accepted")
	}

	req.ServiceName = "orders.service"
	req.HealthURL = "https://user:secret@example.com/health"
	if err := validateDeploymentProjectRequest(&req); err == nil {
		t.Fatal("health URL with embedded credentials was accepted")
	}
}

func TestDeploymentExtractArchivePersistsExplicitValues(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:deployment-extract-default?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.DeploymentProject{}); err != nil {
		t.Fatal(err)
	}
	project := database.DeploymentProject{Name: "site", Type: database.DeploymentProjectStatic, AgentID: "agent-1", DeployPath: "/var/www/nanolink/site", ExtractArchive: true, CreatedBy: 1}
	if err := db.Create(&project).Error; err != nil {
		t.Fatal(err)
	}
	if !project.ExtractArchive {
		t.Fatal("explicit extraction setting was not persisted")
	}
	plain := database.DeploymentProject{Name: "plain", Type: database.DeploymentProjectStatic, AgentID: "agent-1", DeployPath: "/var/www/nanolink/plain", ExtractArchive: false, CreatedBy: 1}
	if err := db.Create(&plain).Error; err != nil {
		t.Fatal(err)
	}
	if plain.ExtractArchive {
		t.Fatal("explicit non-extraction setting was overwritten by a database default")
	}
}

func TestDeploymentArtifactSuffix(t *testing.T) {
	if suffix, err := deploymentArtifactSuffix("java", "orders.jar"); err != nil || suffix != ".jar" {
		t.Fatalf("valid jar rejected: suffix=%q err=%v", suffix, err)
	}
	if _, err := deploymentArtifactSuffix("java", "orders.zip"); err == nil {
		t.Fatal("zip accepted for java project")
	}
	if suffix, err := deploymentArtifactSuffix("static", "site.tar.gz"); err != nil || suffix != ".tar.gz" {
		t.Fatalf("valid tarball rejected: suffix=%q err=%v", suffix, err)
	}
	if suffix, err := deploymentArtifactSuffix("static", "site.tar"); err != nil || suffix != ".tar" {
		t.Fatalf("valid tar rejected: suffix=%q err=%v", suffix, err)
	}
}

func TestDeploymentCommandUsesCanonicalExtractionParameters(t *testing.T) {
	project := database.DeploymentProject{Type: database.DeploymentProjectStatic, DeployPath: "/var/www/nanolink/site", ExtractArchive: true, KeepReleases: 5}
	release := database.DeploymentRelease{Version: "1.0.0", ArtifactName: "site.tar.gz", ArtifactSize: 12, SHA256: "digest", StripTopLevel: true}
	params := deploymentCommandParams(project, release, true)
	if params["extract_artifact"] != "true" || params["strip_top_level"] != "true" {
		t.Fatalf("unexpected extraction params: %#v", params)
	}
	if params["extract_archive"] != "true" {
		t.Fatalf("rolling-upgrade extraction key missing: %#v", params)
	}
	if _, legacy := params["extract"]; legacy {
		t.Fatalf("legacy extraction key must not be emitted: %#v", params)
	}

	project.ExtractArchive = false
	params = deploymentCommandParams(project, release, true)
	if params["extract_artifact"] != "false" || params["extract_archive"] != "false" {
		t.Fatalf("project non-extract default ignored: %#v", params)
	}
	extract := true
	release.Extract = &extract
	params = deploymentCommandParams(project, release, true)
	if params["extract_artifact"] != "true" || params["extract_archive"] != "true" {
		t.Fatalf("explicit extraction release ignored: %#v", params)
	}

	project.ExtractArchive = true
	noExtract := false
	release.Extract = &noExtract
	params = deploymentCommandParams(project, release, true)
	if params["extract_artifact"] != "false" || params["extract_archive"] != "false" {
		t.Fatalf("explicit non-extract release ignored: %#v", params)
	}
}

func TestJavaDeploymentOmitsStaticExtractionParameters(t *testing.T) {
	project := database.DeploymentProject{Type: database.DeploymentProjectJava, DeployPath: "/opt/nanolink/apps/orders", ServiceName: "orders.service", KeepReleases: 5}
	release := database.DeploymentRelease{Version: "1.0.0", ArtifactName: "orders.jar", ArtifactSize: 12, SHA256: "digest"}
	params := deploymentCommandParams(project, release, true)
	for _, key := range []string{"extract_artifact", "extract_archive", "strip_top_level"} {
		if _, exists := params[key]; exists {
			t.Fatalf("Java deployment unexpectedly emitted %s: %#v", key, params)
		}
	}
}

func TestNormalizeDeploymentDirectoryPaths(t *testing.T) {
	paths, err := normalizeDeploymentDirectoryPaths([]string{"dist/index.html", "dist/assets/app.js"})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"index.html", "assets/app.js"}
	if !reflect.DeepEqual(paths, want) {
		t.Fatalf("unexpected paths: got %v want %v", paths, want)
	}
	for _, invalid := range [][]string{{"index.html"}, {"dist/../secret"}, {"a/index.html", "b/app.js"}, {"dist/a", "dist/a"}} {
		if _, err := normalizeDeploymentDirectoryPaths(invalid); err == nil {
			t.Fatalf("unsafe directory paths accepted: %v", invalid)
		}
	}
}

func TestArtifactTokensAreRandomAndHashed(t *testing.T) {
	plainA, hashA, err := newArtifactToken()
	if err != nil {
		t.Fatal(err)
	}
	plainB, hashB, err := newArtifactToken()
	if err != nil {
		t.Fatal(err)
	}
	if plainA == plainB || hashA == hashB {
		t.Fatal("artifact tokens must be unique")
	}
	if plainA == hashA || len(plainA) != 64 || len(hashA) != 64 {
		t.Fatal("artifact token must be 32 random bytes and stored only as a SHA-256 digest")
	}
}

func TestDeploymentTaskTokenExpires(t *testing.T) {
	plain, hash, err := newArtifactToken()
	if err != nil {
		t.Fatal(err)
	}
	expires := time.Now().Add(time.Minute)
	task := database.DeploymentTask{ArtifactTokenHash: hash, ArtifactTokenExpires: &expires}
	if !validDeploymentTaskToken(&task, plain) {
		t.Fatal("valid deployment task token was rejected")
	}
	if validDeploymentTaskToken(&task, "wrong") {
		t.Fatal("incorrect deployment task token was accepted")
	}
	expired := time.Now().Add(-time.Minute)
	task.ArtifactTokenExpires = &expired
	if validDeploymentTaskToken(&task, plain) {
		t.Fatal("expired deployment task token was accepted")
	}
}

func TestDeploymentArtifactSupportsRangeResume(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:deployment-range-resume?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.DeploymentProject{}, &database.DeploymentRelease{}, &database.DeploymentTask{}); err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	projectDir := filepath.Join(root, "1")
	if err := os.MkdirAll(projectDir, 0o750); err != nil {
		t.Fatal(err)
	}
	artifact := []byte("0123456789abcdef")
	artifactPath := filepath.Join(projectDir, "release.jar")
	if err := os.WriteFile(artifactPath, artifact, 0o640); err != nil {
		t.Fatal(err)
	}
	project := database.DeploymentProject{
		Name: "range-test", Type: database.DeploymentProjectJava, AgentID: "agent-1",
		DeployPath: "/opt/nanolink/apps/range-test", ServiceName: "range-test.service",
		KeepReleases: 5, CreatedBy: 1,
	}
	if err := db.Create(&project).Error; err != nil {
		t.Fatal(err)
	}
	release := database.DeploymentRelease{
		ID: "release-range", ProjectID: project.ID, Version: "1.0.0", ArtifactName: "release.jar",
		ArtifactPath: artifactPath, ArtifactSize: int64(len(artifact)), SHA256: strings.Repeat("a", 64), CreatedBy: 1,
	}
	if err := db.Create(&release).Error; err != nil {
		t.Fatal(err)
	}
	plain, hash, err := newArtifactToken()
	if err != nil {
		t.Fatal(err)
	}
	expires := time.Now().Add(time.Minute)
	task := database.DeploymentTask{
		ID: "task-range", ProjectID: project.ID, ReleaseID: release.ID, AgentID: "agent-1",
		CommandID: "command-range", Action: database.DeploymentActionDeploy,
		Status: database.DeploymentStatusRunning, ArtifactTokenHash: hash, ArtifactTokenExpires: &expires, CreatedBy: 1,
	}
	if err := db.Create(&task).Error; err != nil {
		t.Fatal(err)
	}

	h := &DeploymentHandler{db: db, storageRoot: root, logger: zap.NewNop().Sugar()}
	router := gin.New()
	router.GET("/artifact/:taskId", h.DownloadArtifact)
	req := httptest.NewRequest(http.MethodGet, "/artifact/task-range?token="+plain, nil)
	req.Header.Set("Range", "bytes=4-9")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)

	if response.Code != http.StatusPartialContent {
		t.Fatalf("range request status = %d, want %d; body=%s", response.Code, http.StatusPartialContent, response.Body.String())
	}
	if got := response.Body.String(); got != "456789" {
		t.Fatalf("range response body = %q, want %q", got, "456789")
	}
	if got := response.Header().Get("Content-Range"); got != "bytes 4-9/16" {
		t.Fatalf("Content-Range = %q", got)
	}
	if got := response.Header().Get("Accept-Ranges"); got != "bytes" {
		t.Fatalf("Accept-Ranges = %q", got)
	}
	if got := response.Header().Get("ETag"); got != "\"sha256-"+release.SHA256+"\"" {
		t.Fatalf("ETag = %q", got)
	}
}

func TestLateDeploymentResultCannotReplaceCurrentRelease(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:late-deployment-result?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.DeploymentProject{}, &database.DeploymentRelease{}, &database.DeploymentTask{}); err != nil {
		t.Fatal(err)
	}
	current := "release-new"
	project := database.DeploymentProject{
		Name: "orders", Type: database.DeploymentProjectJava, AgentID: "agent-1",
		DeployPath: "/opt/nanolink/apps/orders", ServiceName: "orders.service",
		KeepReleases: 5, CurrentReleaseID: &current, CreatedBy: 1,
	}
	if err := db.Create(&project).Error; err != nil {
		t.Fatal(err)
	}
	task := database.DeploymentTask{
		ID: "task-old", ProjectID: project.ID, ReleaseID: "release-old", AgentID: "agent-1",
		CommandID: "command-old", Action: database.DeploymentActionDeploy,
		Status: database.DeploymentStatusFailed, CreatedBy: 1,
	}
	if err := db.Create(&task).Error; err != nil {
		t.Fatal(err)
	}

	h := &DeploymentHandler{db: db, logger: zap.NewNop().Sugar()}
	h.HandleCommandResult("agent-1", "command-old", "late success", true)

	var stored database.DeploymentProject
	if err := db.First(&stored, project.ID).Error; err != nil {
		t.Fatal(err)
	}
	if stored.CurrentReleaseID == nil || *stored.CurrentReleaseID != current {
		t.Fatalf("late result replaced current release: %#v", stored.CurrentReleaseID)
	}
}
