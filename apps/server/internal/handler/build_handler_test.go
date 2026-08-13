package handler

import (
	"net"
	"reflect"
	"testing"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
)

func validBuildPipelineRequest() buildPipelineRequest {
	return buildPipelineRequest{
		Name: "web-release", AgentID: "agent-1",
		SourceType: database.BuildSourceGit, SourceURL: "ssh://git@example.com/team/web.git", SourceRef: "main",
		RunnerType: database.BuildRunnerDocker, ContainerImage: "node:22-alpine",
		Stages: []buildStage{
			{ID: "package", Name: "Package", Command: "tar -czf app.tar.gz dist", Needs: []string{"test"}},
			{ID: "install", Name: "Install", Command: "npm ci"},
			{ID: "test", Name: "Test", Command: "npm test", Needs: []string{"install"}},
		},
		Variables:       []buildVariable{{Name: "NODE_ENV", Value: "production"}},
		ArtifactPattern: "app.tar.gz", ArtifactName: "app.tar.gz",
		Schedule: "*/15 * * * *",
	}
}

func TestValidateBuildPipelineAndTopologicalOrder(t *testing.T) {
	req := validBuildPipelineRequest()
	if err := validateBuildPipelineRequest(&req); err != nil {
		t.Fatalf("valid build pipeline rejected: %v", err)
	}
	if req.TimeoutSeconds != 1800 || req.KeepArtifacts != 20 {
		t.Fatalf("defaults were not applied: timeout=%d keep=%d", req.TimeoutSeconds, req.KeepArtifacts)
	}
	ordered := topologicalBuildStages(req.Stages)
	got := []string{ordered[0].ID, ordered[1].ID, ordered[2].ID}
	want := []string{"install", "test", "package"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected stage order: got %v want %v", got, want)
	}
}

func TestBuildPipelineRejectsCyclesAndUnsafeArtifacts(t *testing.T) {
	req := validBuildPipelineRequest()
	req.Stages = []buildStage{
		{ID: "a", Name: "A", Command: "true", Needs: []string{"b"}},
		{ID: "b", Name: "B", Command: "true", Needs: []string{"a"}},
	}
	if err := validateBuildPipelineRequest(&req); err == nil {
		t.Fatal("cyclic stage graph was accepted")
	}

	req = validBuildPipelineRequest()
	req.ArtifactPattern = "../secrets/*"
	if err := validateBuildPipelineRequest(&req); err == nil {
		t.Fatal("artifact traversal pattern was accepted")
	}
}

func TestBuildCronParser(t *testing.T) {
	if err := validateCronExpression("*/15 8-18 * * 1-5"); err != nil {
		t.Fatalf("valid cron rejected: %v", err)
	}
	mondayMorning := time.Date(2026, 8, 10, 9, 30, 0, 0, time.Local)
	if !cronMatches("*/15 8-18 * * 1-5", mondayMorning) {
		t.Fatal("valid cron did not match")
	}
	if cronMatches("*/15 8-18 * * 1-5", mondayMorning.Add(2*time.Minute)) {
		t.Fatal("cron matched an invalid minute")
	}
	if err := validateCronExpression("0 0 * *"); err == nil {
		t.Fatal("four-field cron was accepted")
	}
}

func TestBuildSourceNetworkBoundary(t *testing.T) {
	privateAndReserved := []string{"127.0.0.1", "10.0.0.1", "100.64.0.1", "169.254.169.254", "192.0.2.1", "2001:db8::1", "::1"}
	for _, raw := range privateAndReserved {
		if isPublicBuildSourceIP(net.ParseIP(raw)) {
			t.Fatalf("private/reserved source address accepted: %s", raw)
		}
	}
	if !isPublicBuildSourceIP(net.ParseIP("1.1.1.1")) {
		t.Fatal("public source address was rejected")
	}
}

func TestBuildURLValidation(t *testing.T) {
	if err := validateGitSourceURL("ssh://git@example.com/team/repo.git"); err != nil {
		t.Fatalf("SSH Git URL rejected: %v", err)
	}
	if err := validateGitSourceURL("https://user:secret@example.com/repo.git"); err == nil {
		t.Fatal("Git URL with embedded credentials was accepted")
	}
	if err := validateRemoteSourceURL("https://example.com/source.tar.gz"); err != nil {
		t.Fatalf("remote archive URL rejected: %v", err)
	}
	if err := validateRemoteSourceURL("file:///etc/passwd"); err == nil {
		t.Fatal("non-HTTP source URL was accepted")
	}
}
