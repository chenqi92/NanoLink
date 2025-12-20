package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// PermissionHandler handles permission management API requests
type PermissionHandler struct {
	permService *service.PermissionService
	logger      *zap.SugaredLogger
}

// NewPermissionHandler creates a new permission handler
func NewPermissionHandler(permService *service.PermissionService, logger *zap.SugaredLogger) *PermissionHandler {
	return &PermissionHandler{
		permService: permService,
		logger:      logger,
	}
}

// AssignAgentToGroupRequest represents an assign agent to group request
type AssignAgentToGroupRequest struct {
	AgentID         string `json:"agentId" binding:"required"`
	GroupID         uint   `json:"groupId" binding:"required"`
	PermissionLevel int    `json:"permissionLevel" binding:"min=0,max=3"`
}

// SetUserPermissionRequest represents a set user permission request
type SetUserPermissionRequest struct {
	UserID          uint   `json:"userId" binding:"required"`
	AgentID         string `json:"agentId" binding:"required"`
	PermissionLevel int    `json:"permissionLevel" binding:"min=0,max=3"`
}

// AgentGroupResponse represents an agent-group assignment in API responses
type AgentGroupResponse struct {
	ID              uint   `json:"id"`
	AgentID         string `json:"agentId"`
	GroupID         uint   `json:"groupId"`
	GroupName       string `json:"groupName,omitempty"`
	PermissionLevel int    `json:"permissionLevel"`
	PermissionName  string `json:"permissionName"`
}

// UserPermissionResponse represents a user permission in API responses
type UserPermissionResponse struct {
	ID              uint   `json:"id"`
	UserID          uint   `json:"userId"`
	Username        string `json:"username,omitempty"`
	AgentID         string `json:"agentId"`
	PermissionLevel int    `json:"permissionLevel"`
	PermissionName  string `json:"permissionName"`
}

// AssignAgentToGroup assigns an agent to a group
func (h *PermissionHandler) AssignAgentToGroup(c *gin.Context) {
	var req AssignAgentToGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.permService.AssignAgentToGroup(req.AgentID, req.GroupID, req.PermissionLevel); err != nil {
		if err == service.ErrGroupNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		if err == service.ErrInvalidPermissionLevel {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid permission level (must be 0-3)"})
			return
		}
		h.logger.Errorf("Assign agent to group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to assign agent to group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":         "agent assigned to group",
		"agentId":         req.AgentID,
		"groupId":         req.GroupID,
		"permissionLevel": req.PermissionLevel,
		"permissionName":  database.PermissionLevelName(req.PermissionLevel),
	})
}

// RemoveAgentFromGroup removes an agent from a group
func (h *PermissionHandler) RemoveAgentFromGroup(c *gin.Context) {
	agentID := c.Param("agentId")
	groupIDStr := c.Param("groupId")

	groupID, err := strconv.ParseUint(groupIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	if err := h.permService.RemoveAgentFromGroup(agentID, uint(groupID)); err != nil {
		if err == service.ErrAgentNotAssigned {
			c.JSON(http.StatusNotFound, gin.H{"error": "agent not assigned to this group"})
			return
		}
		h.logger.Errorf("Remove agent from group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove agent from group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "agent removed from group"})
}

// SetUserPermission sets a user's permission for an agent
func (h *PermissionHandler) SetUserPermission(c *gin.Context) {
	var req SetUserPermissionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get current user (superadmin) to record who granted the permission
	currentUser := GetCurrentUser(c)
	if currentUser == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	// Check if the permission level is within the agent's max level
	maxLevel, err := h.permService.GetAgentMaxPermissionLevel(req.AgentID)
	if err != nil {
		h.logger.Errorf("Get agent max permission failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check permission level"})
		return
	}

	if req.PermissionLevel > maxLevel {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":    "permission level exceeds agent's maximum",
			"maxLevel": maxLevel,
			"maxName":  database.PermissionLevelName(maxLevel),
		})
		return
	}

	if err := h.permService.SetUserAgentPermission(req.UserID, req.AgentID, req.PermissionLevel, currentUser.ID); err != nil {
		if err == service.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		if err == service.ErrInvalidPermissionLevel {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid permission level"})
			return
		}
		h.logger.Errorf("Set user permission failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to set permission"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":         "permission set",
		"userId":          req.UserID,
		"agentId":         req.AgentID,
		"permissionLevel": req.PermissionLevel,
		"permissionName":  database.PermissionLevelName(req.PermissionLevel),
	})
}

// RemoveUserPermission removes a user's permission for an agent
func (h *PermissionHandler) RemoveUserPermission(c *gin.Context) {
	userIDStr := c.Param("userId")
	agentID := c.Param("agentId")

	userID, err := strconv.ParseUint(userIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	if err := h.permService.RemoveUserAgentPermission(uint(userID), agentID); err != nil {
		h.logger.Errorf("Remove user permission failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove permission"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "permission removed"})
}

// GetUserPermissions returns all permissions for a user
func (h *PermissionHandler) GetUserPermissions(c *gin.Context) {
	userIDStr := c.Param("userId")

	userID, err := strconv.ParseUint(userIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	perms, err := h.permService.GetUserPermissions(uint(userID))
	if err != nil {
		h.logger.Errorf("Get user permissions failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get permissions"})
		return
	}

	result := make([]UserPermissionResponse, len(perms))
	for i, p := range perms {
		result[i] = UserPermissionResponse{
			ID:              p.ID,
			UserID:          p.UserID,
			AgentID:         p.AgentID,
			PermissionLevel: p.PermissionLevel,
			PermissionName:  database.PermissionLevelName(p.PermissionLevel),
		}
	}

	c.JSON(http.StatusOK, result)
}

// GetAgentGroups returns all groups an agent is assigned to
func (h *PermissionHandler) GetAgentGroups(c *gin.Context) {
	agentID := c.Param("id")

	groups, err := h.permService.GetAgentGroups(agentID)
	if err != nil {
		h.logger.Errorf("Get agent groups failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get agent groups"})
		return
	}

	result := make([]AgentGroupResponse, len(groups))
	for i, g := range groups {
		result[i] = AgentGroupResponse{
			ID:              g.ID,
			AgentID:         g.AgentID,
			GroupID:         g.GroupID,
			GroupName:       g.Group.Name,
			PermissionLevel: g.PermissionLevel,
			PermissionName:  database.PermissionLevelName(g.PermissionLevel),
		}
	}

	c.JSON(http.StatusOK, result)
}

// CheckPermissionRequest represents a permission check request
type CheckPermissionRequest struct {
	AgentID       string `json:"agentId" binding:"required"`
	RequiredLevel int    `json:"requiredLevel" binding:"min=0,max=3"`
}

// CheckPermission checks if current user has required permission for an agent
func (h *PermissionHandler) CheckPermission(c *gin.Context) {
	var req CheckPermissionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	canExecute, err := h.permService.CanUserExecuteCommand(user.ID, req.AgentID, req.RequiredLevel)
	if err != nil && err != service.ErrPermissionDenied {
		h.logger.Errorf("Permission check failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "permission check failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"hasPermission": canExecute,
		"requiredLevel": req.RequiredLevel,
		"requiredName":  database.PermissionLevelName(req.RequiredLevel),
	})
}
