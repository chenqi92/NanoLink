package handler

import (
	"errors"
	"net/http"
	"strings"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// AuthHandler handles authentication API requests
type AuthHandler struct {
	authService *service.AuthService
	logger      *zap.SugaredLogger
}

// NewAuthHandler creates a new auth handler
func NewAuthHandler(authService *service.AuthService, logger *zap.SugaredLogger) *AuthHandler {
	return &AuthHandler{
		authService: authService,
		logger:      logger,
	}
}

// RegisterRequest represents a user registration request
type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=50"`
	Password string `json:"password" binding:"required,min=8"`
	Email    string `json:"email" binding:"omitempty,email"`
}

// LoginRequest represents a user login request
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// AuthResponse represents an authentication response.
//
// Browser clients receive the JWT only in an HttpOnly cookie. Native clients
// explicitly opt into a body token with X-NanoLink-Client: native and must not
// send a browser Origin header. Origin is a forbidden browser-controlled header,
// so injected JavaScript cannot suppress it to extract a reusable bearer token.
type AuthResponse struct {
	User  UserResponse `json:"user"`
	Token string       `json:"token,omitempty"`
}

const NativeClientHeader = "X-NanoLink-Client"

func responseToken(c *gin.Context, token string) string {
	if strings.TrimSpace(c.GetHeader("Origin")) != "" {
		return ""
	}
	clientKind := strings.TrimSpace(c.GetHeader(NativeClientHeader))
	if strings.EqualFold(clientKind, "native") || strings.EqualFold(clientKind, "cli") || strings.EqualFold(clientKind, "sdk") {
		return token
	}
	return ""
}

// UserResponse represents a user in API responses
type UserResponse struct {
	ID           uint   `json:"id"`
	Username     string `json:"username"`
	Email        string `json:"email"`
	IsSuperAdmin bool   `json:"isSuperAdmin"`
}

// BootstrapStatus lets the login screen render the only setup path that is
// actually available on this server.
func (h *AuthHandler) BootstrapStatus(c *gin.Context) {
	hasUsers, registrationEnabled, err := h.authService.BootstrapStatus()
	if err != nil {
		h.logger.Errorf("Read bootstrap status failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read setup status"})
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{
		"hasUsers":            hasUsers,
		"registrationEnabled": registrationEnabled,
	})
}

// Register handles user registration
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.authService.RegisterPublicUser(req.Username, req.Password, req.Email)
	if err != nil {
		if errors.Is(err, service.ErrRegistrationDisabled) {
			c.JSON(http.StatusForbidden, gin.H{"error": "public registration is disabled; ask an administrator to enable it, or bootstrap the first admin via NANOLINK_ADMIN_USERNAME/PASSWORD"})
			return
		}
		if errors.Is(err, service.ErrRegistrationClosed) {
			c.JSON(http.StatusForbidden, gin.H{"error": "registration is closed; ask a super admin to create new users"})
			return
		}
		if errors.Is(err, service.ErrUserExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "username already exists"})
			return
		}
		h.logger.Errorf("Registration failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "registration failed"})
		return
	}

	// Generate token for the new user
	token, err := h.authService.GenerateToken(user)
	if err != nil {
		h.logger.Errorf("Token generation failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token generation failed"})
		return
	}

	SetAuthCookie(c, token, h.authService.TokenTTL())
	c.Header("Cache-Control", "no-store")

	c.JSON(http.StatusCreated, AuthResponse{
		User: UserResponse{
			ID:           user.ID,
			Username:     user.Username,
			Email:        user.EmailString(),
			IsSuperAdmin: user.IsSuperAdmin,
		},
		Token: responseToken(c, token),
	})
}

// Login handles user login
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	token, user, err := h.authService.LoginUser(req.Username, req.Password, c.ClientIP())
	if err != nil {
		if errors.Is(err, service.ErrUserNotFound) || errors.Is(err, service.ErrInvalidPassword) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
			return
		}
		if errors.Is(err, service.ErrTooManyAttempts) {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": err.Error()})
			return
		}
		h.logger.Errorf("Login failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "login failed"})
		return
	}

	SetAuthCookie(c, token, h.authService.TokenTTL())
	c.Header("Cache-Control", "no-store")

	c.JSON(http.StatusOK, AuthResponse{
		User: UserResponse{
			ID:           user.ID,
			Username:     user.Username,
			Email:        user.EmailString(),
			IsSuperAdmin: user.IsSuperAdmin,
		},
		Token: responseToken(c, token),
	})
}

// Logout clears the current session cookie.
func (h *AuthHandler) Logout(c *gin.Context) {
	ClearAuthCookie(c)
	c.JSON(http.StatusOK, gin.H{"message": "logged out"})
}

// GetMe returns the current authenticated user
func (h *AuthHandler) GetMe(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	c.JSON(http.StatusOK, UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.EmailString(),
		IsSuperAdmin: user.IsSuperAdmin && !IsDeviceSession(c),
	})
}

// ListUsers returns all users (super admin only)
func (h *AuthHandler) ListUsers(c *gin.Context) {
	users, err := h.authService.ListUsers()
	if err != nil {
		h.logger.Errorf("List users failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list users"})
		return
	}

	result := make([]UserResponse, len(users))
	for i, u := range users {
		result[i] = UserResponse{
			ID:           u.ID,
			Username:     u.Username,
			Email:        u.EmailString(),
			IsSuperAdmin: u.IsSuperAdmin,
		}
	}

	c.JSON(http.StatusOK, result)
}

// DeleteUserRequest represents a delete user request
type DeleteUserRequest struct {
	UserID uint `uri:"id" binding:"required"`
}

// DeleteUser deletes a user (super admin only)
func (h *AuthHandler) DeleteUser(c *gin.Context) {
	var req DeleteUserRequest
	if err := c.ShouldBindUri(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Prevent self-deletion
	currentUser := GetCurrentUser(c)
	if currentUser != nil && currentUser.ID == req.UserID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot delete yourself"})
		return
	}

	if err := h.authService.DeleteUser(req.UserID); err != nil {
		if err == service.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		h.logger.Errorf("Delete user failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user deleted"})
}

// UpdatePasswordRequest represents a password update request
type UpdatePasswordRequest struct {
	CurrentPassword string `json:"currentPassword" binding:"required"`
	NewPassword     string `json:"newPassword" binding:"required,min=8"`
}

// UpdatePassword updates user's password
func (h *AuthHandler) UpdatePassword(c *gin.Context) {
	var req UpdatePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	if err := h.authService.VerifyPassword(user.ID, req.CurrentPassword); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "current password is incorrect"})
		return
	}

	if err := h.authService.UpdatePassword(user.ID, req.NewPassword); err != nil {
		if errors.Is(err, service.ErrWeakPassword) {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		h.logger.Errorf("Password update failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update password"})
		return
	}

	// Self-change just bumped the user's token_version, which would otherwise log them
	// out of this session immediately. Reissue a cookie with a fresh token (carrying the
	// new version) so the caller stays signed in. Old tokens on other devices/tabs remain
	// invalidated, which is the whole point of the version bump.
	if refreshed, refErr := h.authService.GetUserByID(user.ID); refErr == nil {
		if newToken, tokErr := h.authService.GenerateToken(refreshed); tokErr == nil {
			SetAuthCookie(c, newToken, h.authService.TokenTTL())
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": "password updated"})
}
