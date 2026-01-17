package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// UserHandler handles user management endpoints
type UserHandler struct {
	db           *gorm.DB
	logger       *zap.SugaredLogger
	authService  *service.AuthService
	groupService *service.GroupService
}

// NewUserHandler creates a new user handler
func NewUserHandler(
	db *gorm.DB,
	logger *zap.SugaredLogger,
	authService *service.AuthService,
	groupService *service.GroupService,
) *UserHandler {
	return &UserHandler{
		db:           db,
		logger:       logger,
		authService:  authService,
		groupService: groupService,
	}
}

// UserDetailResponse is the detailed API response for a user (with groups)
type UserDetailResponse struct {
	ID           uint             `json:"id"`
	Username     string           `json:"username"`
	Email        string           `json:"email"`
	IsSuperAdmin bool             `json:"isSuperAdmin"`
	CreatedAt    string           `json:"createdAt"`
	Groups       []GroupBriefInfo `json:"groups,omitempty"`
}

// GroupBriefInfo is a brief group info for user response
type GroupBriefInfo struct {
	ID   uint   `json:"id"`
	Name string `json:"name"`
}

// CreateUserRequest is the request body for creating a user
type CreateUserRequest struct {
	Username string `json:"username" binding:"required,min=3,max=50"`
	Password string `json:"password" binding:"required,min=6"`
	Email    string `json:"email" binding:"omitempty,email"`
	GroupIDs []uint `json:"groupIds,omitempty"`
}

// UpdateUserRequest is the request body for updating a user
type UpdateUserRequest struct {
	Email    string `json:"email" binding:"omitempty,email"`
	GroupIDs []uint `json:"groupIds,omitempty"`
}

// ChangePasswordRequest is the request body for changing password
type ChangePasswordRequest struct {
	CurrentPassword string `json:"currentPassword" binding:"required_without=ForceChange"`
	NewPassword     string `json:"newPassword" binding:"required,min=6"`
	ForceChange     bool   `json:"forceChange"` // SuperAdmin can force change
}

// ListUsers returns all users (SuperAdmin only)
// GET /api/users
func (h *UserHandler) ListUsers(c *gin.Context) {
	var users []database.User
	if err := h.db.Preload("Groups").Find(&users).Error; err != nil {
		h.logger.Errorf("Failed to list users: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list users"})
		return
	}

	response := make([]UserDetailResponse, len(users))
	for i, user := range users {
		response[i] = h.toUserDetailResponse(user)
	}

	c.JSON(http.StatusOK, response)
}

// GetUser returns a single user
// GET /api/users/:id
func (h *UserHandler) GetUser(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var user database.User
	if err := h.db.Preload("Groups").First(&user, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		h.logger.Errorf("Failed to get user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	c.JSON(http.StatusOK, h.toUserDetailResponse(user))
}

// CreateUser creates a new user (SuperAdmin only)
// POST /api/users
func (h *UserHandler) CreateUser(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create user via auth service
	user, err := h.authService.Register(req.Username, req.Password, req.Email)
	if err != nil {
		if err == service.ErrUserExists {
			c.JSON(http.StatusConflict, gin.H{"error": "Username already exists"})
			return
		}
		h.logger.Errorf("Failed to create user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
		return
	}

	// Add user to groups if specified
	for _, groupID := range req.GroupIDs {
		if err := h.groupService.AddUserToGroup(user.ID, groupID); err != nil {
			h.logger.Warnf("Failed to add user to group %d: %v", groupID, err)
		}
	}

	// Reload user with groups
	h.db.Preload("Groups").First(&user, user.ID)

	h.logger.Infof("User '%s' created by admin", req.Username)
	c.JSON(http.StatusCreated, h.toUserDetailResponse(*user))
}

// UpdateUser updates a user (SuperAdmin only)
// PUT /api/users/:id
func (h *UserHandler) UpdateUser(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var req UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user database.User
	if err := h.db.First(&user, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// Update email if provided
	if req.Email != "" {
		user.Email = req.Email
	}

	if err := h.db.Save(&user).Error; err != nil {
		h.logger.Errorf("Failed to update user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update user"})
		return
	}

	// Update group memberships if specified
	if req.GroupIDs != nil {
		// Clear existing groups
		h.db.Model(&user).Association("Groups").Clear()

		// Add new groups
		for _, groupID := range req.GroupIDs {
			if err := h.groupService.AddUserToGroup(user.ID, groupID); err != nil {
				h.logger.Warnf("Failed to add user to group %d: %v", groupID, err)
			}
		}
	}

	// Reload user with groups
	h.db.Preload("Groups").First(&user, user.ID)

	h.logger.Infof("User '%s' updated", user.Username)
	c.JSON(http.StatusOK, h.toUserDetailResponse(user))
}

// DeleteUser deletes a user (SuperAdmin only)
// DELETE /api/users/:id
func (h *UserHandler) DeleteUser(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	// Get current user from context to prevent self-deletion
	currentUserID, exists := c.Get("userID")
	if exists && currentUserID.(uint) == uint(id) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Cannot delete yourself"})
		return
	}

	var user database.User
	if err := h.db.First(&user, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// Clear user groups first
	h.db.Model(&user).Association("Groups").Clear()

	// Delete user permissions
	h.db.Where("user_id = ?", user.ID).Delete(&database.UserAgentPermission{})

	// Delete user
	if err := h.db.Delete(&user).Error; err != nil {
		h.logger.Errorf("Failed to delete user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete user"})
		return
	}

	h.logger.Infof("User '%s' deleted", user.Username)
	c.JSON(http.StatusOK, gin.H{"message": "User deleted successfully"})
}

// ChangePassword changes a user's password
// PUT /api/users/:id/password
func (h *UserHandler) ChangePassword(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if current user is superadmin or changing own password
	// Safe type assertion to prevent panic when auth is disabled
	var currentUserIDVal uint
	var isSuperAdminVal bool

	if val, exists := c.Get("userID"); exists {
		if id, ok := val.(uint); ok {
			currentUserIDVal = id
		}
	}
	if val, exists := c.Get("isSuperAdmin"); exists {
		if isAdmin, ok := val.(bool); ok {
			isSuperAdminVal = isAdmin
		}
	}

	isOwnPassword := currentUserIDVal == uint(id)
	canForce := isSuperAdminVal && req.ForceChange

	if !isOwnPassword && !canForce {
		c.JSON(http.StatusForbidden, gin.H{"error": "Cannot change another user's password"})
		return
	}

	// If changing own password, verify current password
	if isOwnPassword && !req.ForceChange {
		if err := h.authService.VerifyPassword(uint(id), req.CurrentPassword); err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Current password is incorrect"})
			return
		}
	}

	// Change password
	if err := h.authService.ChangePassword(uint(id), req.NewPassword); err != nil {
		h.logger.Errorf("Failed to change password: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to change password"})
		return
	}

	h.logger.Infof("Password changed for user ID %d", id)
	c.JSON(http.StatusOK, gin.H{"message": "Password changed successfully"})
}

// toUserDetailResponse converts a database user to API response
func (h *UserHandler) toUserDetailResponse(user database.User) UserDetailResponse {
	groups := make([]GroupBriefInfo, len(user.Groups))
	for i, group := range user.Groups {
		groups[i] = GroupBriefInfo{
			ID:   group.ID,
			Name: group.Name,
		}
	}

	return UserDetailResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		IsSuperAdmin: user.IsSuperAdmin,
		CreatedAt:    user.CreatedAt.Format("2006-01-02T15:04:05Z"),
		Groups:       groups,
	}
}
