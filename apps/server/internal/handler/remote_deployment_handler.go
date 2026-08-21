package handler

import (
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

const maxEnvironmentScriptBytes = 256 * 1024

var (
	deploymentTargetHostPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,253}$`)
	sshUsernamePattern          = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.@-]{0,254}$`)
)

type deploymentTargetRequest struct {
	Name             string `json:"name" binding:"required"`
	AgentID          string `json:"agentId" binding:"required"`
	Host             string `json:"host" binding:"required"`
	Port             int    `json:"port"`
	Username         string `json:"username" binding:"required"`
	AuthType         string `json:"authType" binding:"required"`
	Credential       string `json:"credential"`
	SSHKnownHosts    string `json:"sshKnownHosts"`
	AllowUnknownHost bool   `json:"allowUnknownHost"`
	UseSudo          bool   `json:"useSudo"`
}

type deploymentTargetView struct {
	database.DeploymentTarget
	CredentialConfigured bool `json:"credentialConfigured"`
}

type environmentScriptRequest struct {
	Name           string `json:"name" binding:"required"`
	Description    string `json:"description"`
	TargetID       uint   `json:"targetId" binding:"required"`
	Content        string `json:"content"`
	TimeoutSeconds int    `json:"timeoutSeconds"`
}

type environmentScriptView struct {
	database.EnvironmentScript
	Content string `json:"content,omitempty"`
}

func deploymentTargetResponse(target database.DeploymentTarget) deploymentTargetView {
	return deploymentTargetView{DeploymentTarget: target, CredentialConfigured: target.Credential != ""}
}

func (h *DeploymentHandler) ListTargets(c *gin.Context) {
	var targets []database.DeploymentTarget
	if err := h.db.Order("updated_at DESC").Find(&targets).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list deployment targets"})
		return
	}
	views := make([]deploymentTargetView, 0, len(targets))
	for _, target := range targets {
		views = append(views, deploymentTargetResponse(target))
	}
	c.JSON(http.StatusOK, views)
}

func (h *DeploymentHandler) CreateTarget(c *gin.Context) {
	var req deploymentTargetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateDeploymentTargetRequest(&req, true); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	sealed, err := h.encryptDeploymentSecret(req.Credential)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	user := GetCurrentUser(c)
	target := database.DeploymentTarget{
		Name: req.Name, AgentID: req.AgentID, Host: req.Host, Port: req.Port,
		Username: req.Username, AuthType: req.AuthType, Credential: sealed,
		SSHKnownHosts: req.SSHKnownHosts, AllowUnknownHost: req.AllowUnknownHost,
		UseSudo: req.UseSudo, CreatedBy: user.ID,
	}
	if err := h.db.Create(&target).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "deployment target name already exists or target is invalid"})
		return
	}
	c.JSON(http.StatusCreated, deploymentTargetResponse(target))
}

func (h *DeploymentHandler) UpdateTarget(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var target database.DeploymentTarget
	if err := h.db.First(&target, id).Error; err != nil {
		respondDeploymentDBError(c, err, "deployment target")
		return
	}
	var req deploymentTargetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateDeploymentTargetRequest(&req, false); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.AuthType != target.AuthType && req.Credential == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "a new SSH credential is required when authType changes"})
		return
	}
	credential := target.Credential
	if req.Credential != "" {
		sealed, err := h.encryptDeploymentSecret(req.Credential)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		credential = sealed
	}
	target.Name, target.AgentID, target.Host, target.Port = req.Name, req.AgentID, req.Host, req.Port
	target.Username, target.AuthType, target.Credential = req.Username, req.AuthType, credential
	target.SSHKnownHosts, target.AllowUnknownHost, target.UseSudo = req.SSHKnownHosts, req.AllowUnknownHost, req.UseSudo
	if err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Save(&target).Error; err != nil {
			return err
		}
		// Projects follow the target's relay Agent so a later target edit cannot
		// dispatch credentials to one Agent and the command to another.
		return tx.Model(&database.DeploymentProject{}).Where("target_id = ?", target.ID).Update("agent_id", target.AgentID).Error
	}).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "failed to update deployment target"})
		return
	}
	c.JSON(http.StatusOK, deploymentTargetResponse(target))
}

func (h *DeploymentHandler) DeleteTarget(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var references int64
	if err := h.db.Model(&database.DeploymentProject{}).Where("target_id = ?", id).Count(&references).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to inspect deployment target"})
		return
	}
	var scripts int64
	if err := h.db.Model(&database.EnvironmentScript{}).Where("target_id = ?", id).Count(&scripts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to inspect deployment target"})
		return
	}
	if references+scripts > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "deployment target is still used by a project or environment script"})
		return
	}
	result := h.db.Delete(&database.DeploymentTarget{}, id)
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete deployment target"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "deployment target not found"})
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *DeploymentHandler) ListEnvironmentScripts(c *gin.Context) {
	var scripts []database.EnvironmentScript
	if err := h.db.Preload("Target").Order("updated_at DESC").Find(&scripts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list environment scripts"})
		return
	}
	views := make([]environmentScriptView, 0, len(scripts))
	for _, script := range scripts {
		views = append(views, environmentScriptView{EnvironmentScript: script})
	}
	c.JSON(http.StatusOK, views)
}

func (h *DeploymentHandler) GetEnvironmentScript(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var script database.EnvironmentScript
	if err := h.db.Preload("Target").First(&script, id).Error; err != nil {
		respondDeploymentDBError(c, err, "environment script")
		return
	}
	content, err := h.decryptDeploymentSecret(script.Content)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to decrypt environment script"})
		return
	}
	c.JSON(http.StatusOK, environmentScriptView{EnvironmentScript: script, Content: content})
}

func (h *DeploymentHandler) CreateEnvironmentScript(c *gin.Context) {
	var req environmentScriptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.validateEnvironmentScriptRequest(&req, true); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	sealed, err := h.encryptDeploymentSecret(req.Content)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	user := GetCurrentUser(c)
	script := database.EnvironmentScript{
		Name: req.Name, Description: req.Description, TargetID: req.TargetID,
		Content: sealed, TimeoutSeconds: req.TimeoutSeconds, CreatedBy: user.ID,
	}
	if err := h.db.Create(&script).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "environment script name already exists or script is invalid"})
		return
	}
	c.JSON(http.StatusCreated, environmentScriptView{EnvironmentScript: script})
}

func (h *DeploymentHandler) UpdateEnvironmentScript(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var script database.EnvironmentScript
	if err := h.db.First(&script, id).Error; err != nil {
		respondDeploymentDBError(c, err, "environment script")
		return
	}
	var req environmentScriptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.validateEnvironmentScriptRequest(&req, false); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	content := script.Content
	if req.Content != "" {
		sealed, err := h.encryptDeploymentSecret(req.Content)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		content = sealed
	}
	script.Name, script.Description, script.TargetID = req.Name, req.Description, req.TargetID
	script.Content, script.TimeoutSeconds = content, req.TimeoutSeconds
	if err := h.db.Save(&script).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "failed to update environment script"})
		return
	}
	c.JSON(http.StatusOK, environmentScriptView{EnvironmentScript: script})
}

func (h *DeploymentHandler) DeleteEnvironmentScript(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	result := h.db.Delete(&database.EnvironmentScript{}, id)
	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete environment script"})
		return
	}
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "environment script not found"})
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *DeploymentHandler) RunEnvironmentScript(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var script database.EnvironmentScript
	if err := h.db.Preload("Target").First(&script, id).Error; err != nil {
		respondDeploymentDBError(c, err, "environment script")
		return
	}
	content, err := h.decryptDeploymentSecret(script.Content)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to decrypt environment script"})
		return
	}
	params, relayAgentID, err := h.deploymentTargetCommandParams(script.TargetID)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	params["operation"] = "remote_script"
	params["script_content"] = content
	params["script_timeout_seconds"] = strconv.Itoa(script.TimeoutSeconds)
	commandID := uuid.NewString()
	now := time.Now()
	user := GetCurrentUser(c)
	run := database.EnvironmentScriptRun{
		ID: uuid.NewString(), ScriptID: script.ID, TargetID: script.TargetID,
		AgentID: relayAgentID, CommandID: commandID,
		Status: database.DeploymentStatusQueued, CreatedBy: user.ID,
		CreatedByName: user.Username, StartedAt: &now,
	}
	if err := h.db.Create(&run).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create environment script run"})
		return
	}
	h.grpc.RegisterDispatchedCommand(commandID, run.AgentID, user.ID, user.Username, pb.CommandType_DEPLOY_EXECUTE.String())
	cmd := &pb.Command{
		CommandId: commandID, Type: pb.CommandType_DEPLOY_EXECUTE,
		Target: fmt.Sprintf("ssh://%s:%d/%s", script.Target.Host, script.Target.Port, script.Name),
		Params: params,
	}
	if err := h.grpc.SendCommandToAgent(run.AgentID, cmd); err != nil {
		finished := time.Now()
		run.Status, run.Error, run.FinishedAt = database.DeploymentStatusFailed, err.Error(), &finished
		_ = h.db.Model(&run).Updates(map[string]any{"status": run.Status, "error": run.Error, "finished_at": &finished}).Error
		c.JSON(http.StatusConflict, gin.H{"error": "agent is offline or cannot execute the environment script", "details": err.Error(), "run": run})
		return
	}
	run.Status = database.DeploymentStatusRunning
	_ = h.db.Model(&run).Update("status", run.Status).Error
	c.JSON(http.StatusAccepted, run)
}

func (h *DeploymentHandler) GetEnvironmentScriptRun(c *gin.Context) {
	var run database.EnvironmentScriptRun
	if err := h.db.Preload("Script").Preload("Target").First(&run, "id = ?", c.Param("runId")).Error; err != nil {
		respondDeploymentDBError(c, err, "environment script run")
		return
	}
	c.JSON(http.StatusOK, run)
}

func (h *DeploymentHandler) handleEnvironmentScriptResult(agentID, commandID, output string, success bool) {
	var run database.EnvironmentScriptRun
	if err := h.db.Where("command_id = ? AND agent_id = ?", commandID, agentID).First(&run).Error; err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			h.logger.Warnf("environment script result lookup failed: %v", err)
		}
		return
	}
	if run.Status != database.DeploymentStatusQueued && run.Status != database.DeploymentStatusRunning {
		return
	}
	finished := time.Now()
	output = truncateUTF8(output, maxDeploymentLogBytes)
	updates := map[string]any{"output": output, "finished_at": &finished}
	if success {
		updates["status"] = database.DeploymentStatusSuccess
	} else {
		updates["status"] = database.DeploymentStatusFailed
		updates["error"] = output
	}
	if err := h.db.Model(&run).Updates(updates).Error; err != nil {
		h.logger.Warnf("failed to persist environment script result: %v", err)
	}
}

func (h *DeploymentHandler) resolveDeploymentProjectTarget(req *deploymentProjectRequest) error {
	if req.TargetID == nil {
		return nil
	}
	if *req.TargetID == 0 {
		return errors.New("targetId is invalid")
	}
	var target database.DeploymentTarget
	if err := h.db.First(&target, *req.TargetID).Error; err != nil {
		return errors.New("deployment target not found")
	}
	req.AgentID = target.AgentID
	return nil
}

func (h *DeploymentHandler) deploymentTargetCommandParams(targetID uint) (map[string]string, string, error) {
	var target database.DeploymentTarget
	if err := h.db.First(&target, targetID).Error; err != nil {
		return nil, "", errors.New("deployment target not found")
	}
	credential, err := h.decryptDeploymentSecret(target.Credential)
	if err != nil {
		return nil, "", errors.New("deployment target credential cannot be decrypted")
	}
	return map[string]string{
		"deployment_mode":        "ssh",
		"ssh_host":               target.Host,
		"ssh_port":               strconv.Itoa(target.Port),
		"ssh_username":           target.Username,
		"ssh_auth_type":          target.AuthType,
		"ssh_credential":         credential,
		"ssh_known_hosts":        target.SSHKnownHosts,
		"ssh_allow_unknown_host": strconv.FormatBool(target.AllowUnknownHost),
		"ssh_use_sudo":           strconv.FormatBool(target.UseSudo),
	}, target.AgentID, nil
}

func (h *DeploymentHandler) encryptDeploymentSecret(value string) (string, error) {
	if h.codec == nil {
		return "", errors.New("deployment secret encryption is unavailable")
	}
	sealed, err := h.codec.EncryptSecret(value)
	if err != nil {
		return "", fmt.Errorf("encrypt deployment secret: %w", err)
	}
	return sealed, nil
}

func (h *DeploymentHandler) decryptDeploymentSecret(value string) (string, error) {
	if h.codec == nil {
		return "", errors.New("deployment secret decryption is unavailable")
	}
	return h.codec.DecryptSecret(value)
}

func validateDeploymentTargetRequest(req *deploymentTargetRequest, requireCredential bool) error {
	req.Name = strings.TrimSpace(req.Name)
	req.AgentID = strings.TrimSpace(req.AgentID)
	req.Host = strings.Trim(strings.TrimSpace(req.Host), "[]")
	req.Username = strings.TrimSpace(req.Username)
	req.AuthType = strings.ToLower(strings.TrimSpace(req.AuthType))
	req.SSHKnownHosts = strings.TrimSpace(req.SSHKnownHosts)
	if req.Port == 0 {
		req.Port = 22
	}
	if req.Name == "" || len(req.Name) > 100 {
		return errors.New("target name is required and must be at most 100 characters")
	}
	if req.AgentID == "" {
		return errors.New("relay agent is required")
	}
	if !deploymentTargetHostPattern.MatchString(req.Host) || strings.Contains(req.Host, "..") {
		return errors.New("SSH host is invalid")
	}
	if req.Port < 1 || req.Port > 65535 {
		return errors.New("SSH port must be between 1 and 65535")
	}
	if !sshUsernamePattern.MatchString(req.Username) {
		return errors.New("SSH username is invalid")
	}
	if req.AuthType != database.DeploymentTargetAuthPassword && req.AuthType != database.DeploymentTargetAuthPrivateKey {
		return errors.New("authType must be password or private_key")
	}
	if requireCredential && req.Credential == "" {
		return errors.New("SSH credential is required")
	}
	if len(req.Credential) > 128*1024 || strings.ContainsRune(req.Credential, '\x00') {
		return errors.New("SSH credential is invalid")
	}
	if len(req.SSHKnownHosts) > 128*1024 || strings.ContainsRune(req.SSHKnownHosts, '\x00') {
		return errors.New("SSH known_hosts data is invalid")
	}
	if !req.AllowUnknownHost && req.SSHKnownHosts == "" {
		return errors.New("SSH known_hosts data is required unless unknown hosts are explicitly allowed")
	}
	return nil
}

func (h *DeploymentHandler) validateEnvironmentScriptRequest(req *environmentScriptRequest, requireContent bool) error {
	req.Name = strings.TrimSpace(req.Name)
	req.Description = strings.TrimSpace(req.Description)
	if req.TimeoutSeconds == 0 {
		req.TimeoutSeconds = 600
	}
	if req.Name == "" || len(req.Name) > 100 {
		return errors.New("script name is required and must be at most 100 characters")
	}
	if len(req.Description) > 500 {
		return errors.New("script description must be at most 500 characters")
	}
	if req.TargetID == 0 {
		return errors.New("deployment target is required")
	}
	if requireContent && strings.TrimSpace(req.Content) == "" {
		return errors.New("script content is required")
	}
	if len(req.Content) > maxEnvironmentScriptBytes || strings.ContainsRune(req.Content, '\x00') {
		return errors.New("script content is invalid or too large")
	}
	if req.TimeoutSeconds < 1 || req.TimeoutSeconds > 3600 {
		return errors.New("script timeout must be between 1 and 3600 seconds")
	}
	var target database.DeploymentTarget
	if err := h.db.First(&target, req.TargetID).Error; err != nil {
		return errors.New("deployment target not found")
	}
	return nil
}
