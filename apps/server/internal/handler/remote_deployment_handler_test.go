package handler

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type deploymentTestCodec struct{}

func (deploymentTestCodec) EncryptSecret(plain string) (string, error) {
	if plain == "" {
		return "", errors.New("empty secret")
	}
	return "sealed:" + plain, nil
}

func (deploymentTestCodec) DecryptSecret(value string) (string, error) {
	if !strings.HasPrefix(value, "sealed:") {
		return "", errors.New("invalid sealed secret")
	}
	return strings.TrimPrefix(value, "sealed:"), nil
}

func TestDeploymentTargetValidationRequiresHostVerification(t *testing.T) {
	req := deploymentTargetRequest{
		Name: "prod", AgentID: "agent-1", Host: "deploy.example.com", Port: 22,
		Username: "deploy", AuthType: database.DeploymentTargetAuthPassword, Credential: "secret",
	}
	if err := validateDeploymentTargetRequest(&req, true); err == nil {
		t.Fatal("target without known_hosts or explicit opt-out was accepted")
	}
	req.SSHKnownHosts = "deploy.example.com ssh-ed25519 AAAATEST"
	if err := validateDeploymentTargetRequest(&req, true); err != nil {
		t.Fatalf("valid target rejected: %v", err)
	}
	req.Host = "https://deploy.example.com"
	if err := validateDeploymentTargetRequest(&req, true); err == nil {
		t.Fatal("URL was accepted as an SSH host")
	}
}

func TestDeploymentTargetParamsDecryptOnlyForTaskDispatch(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:deployment-target-params?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.DeploymentTarget{}, &database.DeploymentProject{}); err != nil {
		t.Fatal(err)
	}
	target := database.DeploymentTarget{
		Name: "prod", AgentID: "relay-1", Host: "prod.example.com", Port: 2222,
		Username: "deploy", AuthType: database.DeploymentTargetAuthPrivateKey,
		Credential: "sealed:PRIVATE", SSHKnownHosts: "prod.example.com ssh-ed25519 AAAATEST",
		UseSudo: true, CreatedBy: 1,
	}
	if err := db.Create(&target).Error; err != nil {
		t.Fatal(err)
	}
	h := &DeploymentHandler{db: db, codec: deploymentTestCodec{}}
	params, relayAgentID, err := h.deploymentTargetCommandParams(target.ID)
	if err != nil {
		t.Fatal(err)
	}
	if params["deployment_mode"] != "ssh" || params["ssh_credential"] != "PRIVATE" || params["ssh_use_sudo"] != "true" {
		t.Fatalf("unexpected remote params: %#v", params)
	}
	if relayAgentID != target.AgentID {
		t.Fatalf("relay Agent = %q, want %q", relayAgentID, target.AgentID)
	}

	serialized, err := json.Marshal(deploymentTargetResponse(target))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(serialized), "PRIVATE") || strings.Contains(string(serialized), "sealed:") {
		t.Fatalf("credential leaked in target response: %s", serialized)
	}
	if !strings.Contains(string(serialized), `"credentialConfigured":true`) {
		t.Fatalf("credential presence hint missing: %s", serialized)
	}
}

func TestDeploymentProjectUsesTargetsCurrentRelayAgent(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:deployment-target-agent?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.DeploymentTarget{}); err != nil {
		t.Fatal(err)
	}
	target := database.DeploymentTarget{
		Name: "prod", AgentID: "relay-current", Host: "prod.example.com", Port: 22,
		Username: "deploy", AuthType: database.DeploymentTargetAuthPassword,
		Credential: "sealed:secret", AllowUnknownHost: true, CreatedBy: 1,
	}
	if err := db.Create(&target).Error; err != nil {
		t.Fatal(err)
	}
	h := &DeploymentHandler{db: db, codec: deploymentTestCodec{}}
	req := deploymentProjectRequest{
		Name: "orders", Type: database.DeploymentProjectJava, AgentID: "stale-agent",
		TargetID: &target.ID, DeployPath: "/opt/apps/orders", ServiceName: "orders.service",
		KeepReleases: 5,
	}
	if err := h.resolveDeploymentProjectTarget(&req); err != nil {
		t.Fatal(err)
	}
	if req.AgentID != target.AgentID {
		t.Fatalf("project relay Agent = %q, want %q", req.AgentID, target.AgentID)
	}
}
