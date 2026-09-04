package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// RoleHandler handles role and permission API requests
type RoleHandler struct {
	roleService *service.RoleService
	logger      *zap.SugaredLogger
}

// NewRoleHandler creates a new role handler
func NewRoleHandler(roleService *service.RoleService, logger *zap.SugaredLogger) *RoleHandler {
	return &RoleHandler{
		roleService: roleService,
		logger:      logger,
	}
}

// ListRoles returns all roles
func (h *RoleHandler) ListRoles(c *gin.Context) {
	roles, err := h.roleService.ListRoles(c.Request.Context())
	if err != nil {
		h.logger.Errorf("Failed to list roles: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list roles"})
		return
	}

	c.JSON(http.StatusOK, roles)
}

// GetRole returns a role by ID
func (h *RoleHandler) GetRole(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid role ID"})
		return
	}

	role, err := h.roleService.GetRole(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get role: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "role not found"})
		return
	}

	c.JSON(http.StatusOK, role)
}

// CreateRole creates a new role
func (h *RoleHandler) CreateRole(c *gin.Context) {
	var req struct {
		Name        string   `json:"name" binding:"required"`
		DisplayName string   `json:"displayName" binding:"required"`
		Description string   `json:"description"`
		Scope       string   `json:"scope"`
		Permissions []string `json:"permissions"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	role := &database.Role{
		Name:        req.Name,
		DisplayName: req.DisplayName,
		Description: req.Description,
		Scope:       req.Scope,
		IsBuiltin:   false,
	}

	if err := h.roleService.CreateRole(c.Request.Context(), role, req.Permissions, user.ID); err != nil {
		h.logger.Errorf("Failed to create role: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create role"})
		return
	}

	c.JSON(http.StatusCreated, role)
}

// UpdateRole updates a role
func (h *RoleHandler) UpdateRole(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid role ID"})
		return
	}

	var req struct {
		DisplayName *string  `json:"displayName"`
		Description *string  `json:"description"`
		Scope       *string  `json:"scope"`
		Permissions []string `json:"permissions"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	updates := make(map[string]interface{})
	if req.DisplayName != nil {
		updates["display_name"] = *req.DisplayName
	}
	if req.Description != nil {
		updates["description"] = *req.Description
	}
	if req.Scope != nil {
		updates["scope"] = *req.Scope
	}
	updates["updated_by"] = user.ID

	if err := h.roleService.UpdateRole(c.Request.Context(), uint(id), updates, req.Permissions, user.ID); err != nil {
		h.logger.Errorf("Failed to update role: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "role updated"})
}

// DeleteRole deletes a role
func (h *RoleHandler) DeleteRole(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid role ID"})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	if err := h.roleService.DeleteRole(c.Request.Context(), uint(id), user.ID); err != nil {
		h.logger.Errorf("Failed to delete role: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "role deleted"})
}

// BindRole binds a role to a principal
func (h *RoleHandler) BindRole(c *gin.Context) {
	var req struct {
		RoleID        uint   `json:"roleId" binding:"required"`
		PrincipalType string `json:"principalType" binding:"required,oneof=user group"`
		PrincipalID   uint   `json:"principalId" binding:"required"`
		Scope         string `json:"scope"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	if err := h.roleService.BindRole(c.Request.Context(), req.RoleID, req.PrincipalType, req.PrincipalID, req.Scope, user.ID); err != nil {
		h.logger.Errorf("Failed to bind role: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "role bound successfully"})
}

// UnbindRole removes a role binding
func (h *RoleHandler) UnbindRole(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid binding ID"})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	if err := h.roleService.UnbindRole(c.Request.Context(), uint(id), user.ID); err != nil {
		h.logger.Errorf("Failed to unbind role: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "role unbound successfully"})
}

// GetUserRoles returns roles for a user
func (h *RoleHandler) GetUserRoles(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("userId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	roles, err := h.roleService.GetUserRoles(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get user roles: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get user roles"})
		return
	}

	c.JSON(http.StatusOK, roles)
}

// CheckPermission checks if a user has a specific permission
func (h *RoleHandler) CheckPermission(c *gin.Context) {
	var req struct {
		UserID     uint   `json:"userId" binding:"required"`
		Permission string `json:"permission" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	allowed, err := h.roleService.CheckPermission(c.Request.Context(), req.UserID, req.Permission)
	if err != nil {
		h.logger.Errorf("Failed to check permission: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check permission"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"allowed": allowed})
}

// GetPermissionHistory returns permission change history
func (h *RoleHandler) GetPermissionHistory(c *gin.Context) {
	targetType := c.Query("targetType")
	targetID, _ := strconv.ParseUint(c.Query("targetId"), 10, 32)
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))

	history, err := h.roleService.GetPermissionHistory(c.Request.Context(), targetType, uint(targetID), limit)
	if err != nil {
		h.logger.Errorf("Failed to get permission history: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get permission history"})
		return
	}

	c.JSON(http.StatusOK, history)
}
