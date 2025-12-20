package handler

import (
	"net/http"

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
	Password string `json:"password" binding:"required,min=6"`
	Email    string `json:"email" binding:"omitempty,email"`
}

// LoginRequest represents a user login request
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// AuthResponse represents an authentication response
type AuthResponse struct {
	Token string       `json:"token"`
	User  UserResponse `json:"user"`
}

// UserResponse represents a user in API responses
type UserResponse struct {
	ID           uint   `json:"id"`
	Username     string `json:"username"`
	Email        string `json:"email"`
	IsSuperAdmin bool   `json:"isSuperAdmin"`
}

// Register handles user registration
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.authService.RegisterUser(req.Username, req.Password, req.Email)
	if err != nil {
		if err == service.ErrUserExists {
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

	c.JSON(http.StatusCreated, AuthResponse{
		Token: token,
		User: UserResponse{
			ID:           user.ID,
			Username:     user.Username,
			Email:        user.Email,
			IsSuperAdmin: user.IsSuperAdmin,
		},
	})
}

// Login handles user login
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	token, user, err := h.authService.LoginUser(req.Username, req.Password)
	if err != nil {
		if err == service.ErrUserNotFound || err == service.ErrInvalidPassword {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
			return
		}
		h.logger.Errorf("Login failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "login failed"})
		return
	}

	c.JSON(http.StatusOK, AuthResponse{
		Token: token,
		User: UserResponse{
			ID:           user.ID,
			Username:     user.Username,
			Email:        user.Email,
			IsSuperAdmin: user.IsSuperAdmin,
		},
	})
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
		Email:        user.Email,
		IsSuperAdmin: user.IsSuperAdmin,
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
			Email:        u.Email,
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
	NewPassword string `json:"newPassword" binding:"required,min=6"`
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

	if err := h.authService.UpdatePassword(user.ID, req.NewPassword); err != nil {
		h.logger.Errorf("Password update failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update password"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "password updated"})
}
