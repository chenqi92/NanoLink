package handler

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/ssh"
)

type buildSourceAuthRequest struct {
	Type          string `json:"type"`
	Username      string `json:"username"`
	Password      string `json:"password,omitempty"`
	SSHKnownHosts string `json:"sshKnownHosts,omitempty"`
}

type buildSourceAuthView struct {
	Type                 string `json:"type"`
	Username             string `json:"username,omitempty"`
	CredentialConfigured bool   `json:"credentialConfigured"`
	SSHPublicKey         string `json:"sshPublicKey,omitempty"`
	SSHKnownHosts        string `json:"sshKnownHosts,omitempty"`
}

func (h *BuildHandler) prepareSourceAuth(req buildPipelineRequest, existing *database.BuildPipeline) (buildSourceAuthView, string, error) {
	auth := req.SourceAuth
	auth.Type = strings.ToLower(strings.TrimSpace(auth.Type))
	auth.Username = strings.TrimSpace(auth.Username)
	auth.SSHKnownHosts = strings.TrimSpace(auth.SSHKnownHosts)
	if req.SourceType != database.BuildSourceGit {
		if auth.Type == "" {
			auth.Type = database.BuildSourceAuthNone
		}
		view := buildSourceAuthView{Type: auth.Type, Username: auth.Username, SSHKnownHosts: auth.SSHKnownHosts}
		if auth.Type != database.BuildSourceAuthNone {
			return view, "", errors.New("source authentication is only available for Git sources")
		}
		return view, "", nil
	}
	if auth.Type == "" && existing != nil {
		auth.Type = existing.SourceAuthType
		if auth.Type == "" {
			auth.Type = database.BuildSourceAuthNone
		}
		auth.Username = existing.SourceUsername
		auth.SSHKnownHosts = existing.SourceSSHKnownHosts
	}
	if auth.Type == "" {
		auth.Type = database.BuildSourceAuthNone
	}
	view := buildSourceAuthView{Type: auth.Type, Username: auth.Username, SSHKnownHosts: auth.SSHKnownHosts}
	parsed, err := url.Parse(strings.TrimSpace(req.SourceURL))
	if err != nil {
		return view, "", errors.New("Git source URL is invalid")
	}
	switch auth.Type {
	case database.BuildSourceAuthNone:
		return view, "", nil
	case database.BuildSourceAuthBasic:
		if parsed.Scheme != "https" {
			return view, "", errors.New("basic Git authentication requires an HTTPS repository URL")
		}
		if auth.Username == "" || len(auth.Username) > 255 || strings.ContainsAny(auth.Username, "\r\n") {
			return view, "", errors.New("basic Git authentication requires a valid username")
		}
		credential := auth.Password
		if credential == "" && existing != nil && existing.SourceAuthType == database.BuildSourceAuthBasic {
			credential = existing.SourceCredential
			view.CredentialConfigured = credential != ""
			return view, credential, nil
		}
		if credential == "" {
			return view, "", errors.New("basic Git authentication requires a password or access token")
		}
		if len(credential) > 16*1024 || strings.ContainsAny(credential, "\r\n") {
			return view, "", errors.New("Git password or access token is invalid")
		}
		sealed, err := h.encryptBuildCredential(credential)
		if err != nil {
			return view, "", err
		}
		view.CredentialConfigured = true
		return view, sealed, nil
	case database.BuildSourceAuthSSH:
		if parsed.Scheme != "ssh" {
			return view, "", errors.New("SSH Git authentication requires an ssh:// repository URL")
		}
		if len(auth.SSHKnownHosts) > 64*1024 || strings.ContainsRune(auth.SSHKnownHosts, '\x00') {
			return view, "", errors.New("SSH known_hosts data is invalid")
		}
		if existing != nil && existing.SourceAuthType == database.BuildSourceAuthSSH && existing.SourceCredential != "" {
			view.CredentialConfigured = true
			view.SSHPublicKey = existing.SourceSSHPublicKey
			return view, existing.SourceCredential, nil
		}
		privateKey, publicKey, err := generateBuildSSHKey()
		if err != nil {
			return view, "", fmt.Errorf("generate SSH deploy key: %w", err)
		}
		sealed, err := h.encryptBuildCredential(privateKey)
		if err != nil {
			return view, "", err
		}
		view.CredentialConfigured = true
		view.SSHPublicKey = publicKey
		return view, sealed, nil
	default:
		return view, "", errors.New("source auth type must be none, basic, or ssh")
	}
}

func (h *BuildHandler) encryptBuildCredential(value string) (string, error) {
	if h.codec == nil {
		return "", errors.New("build credential encryption is unavailable")
	}
	sealed, err := h.codec.EncryptSecret(value)
	if err != nil {
		return "", fmt.Errorf("encrypt build credential: %w", err)
	}
	return sealed, nil
}

func (h *BuildHandler) decryptBuildCredential(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	if h.codec == nil {
		return "", errors.New("build credential decryption is unavailable")
	}
	plain, err := h.codec.DecryptSecret(value)
	if err != nil {
		return "", fmt.Errorf("decrypt build credential: %w", err)
	}
	return plain, nil
}

func generateBuildSSHKey() (privateKey, publicKey string, err error) {
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", "", err
	}
	block, err := ssh.MarshalPrivateKey(private, "NanoOps build deploy key")
	if err != nil {
		return "", "", err
	}
	sshPublic, err := ssh.NewPublicKey(public)
	if err != nil {
		return "", "", err
	}
	return string(pem.EncodeToMemory(block)), strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPublic))), nil
}

func (h *BuildHandler) RotateSSHKey(c *gin.Context) {
	id, ok := parseUintParam(c, "id")
	if !ok {
		return
	}
	var pipeline database.BuildPipeline
	if err := h.db.First(&pipeline, id).Error; err != nil {
		respondDeploymentDBError(c, err, "build pipeline")
		return
	}
	if pipeline.SourceType != database.BuildSourceGit || pipeline.SourceAuthType != database.BuildSourceAuthSSH {
		c.JSON(http.StatusConflict, gin.H{"error": "pipeline does not use a server-managed SSH deploy key"})
		return
	}
	privateKey, publicKey, err := generateBuildSSHKey()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate SSH deploy key"})
		return
	}
	sealed, err := h.encryptBuildCredential(privateKey)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := h.db.Model(&pipeline).Updates(map[string]any{
		"source_credential": sealed, "source_ssh_public_key": publicKey,
	}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist SSH deploy key"})
		return
	}
	c.JSON(http.StatusOK, buildSourceAuthView{
		Type: database.BuildSourceAuthSSH, CredentialConfigured: true,
		SSHPublicKey: publicKey, SSHKnownHosts: pipeline.SourceSSHKnownHosts,
	})
}
