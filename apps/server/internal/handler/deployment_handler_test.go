package handler

import (
	"reflect"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
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
	project := database.DeploymentProject{Type: database.DeploymentProjectStatic, DeployPath: "/var/www/nanolink/site", KeepReleases: 5}
	release := database.DeploymentRelease{Version: "1.0.0", ArtifactName: "site.tar.gz", ArtifactSize: 12, SHA256: "digest", StripTopLevel: true}
	params := deploymentCommandParams(project, release, true)
	if params["extract_artifact"] != "true" || params["strip_top_level"] != "true" {
		t.Fatalf("unexpected extraction params: %#v", params)
	}
	if _, legacy := params["extract"]; legacy {
		t.Fatalf("legacy extraction key must not be emitted: %#v", params)
	}

	noExtract := false
	release.Extract = &noExtract
	params = deploymentCommandParams(project, release, true)
	if params["extract_artifact"] != "false" {
		t.Fatalf("explicit non-extract release ignored: %#v", params)
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
