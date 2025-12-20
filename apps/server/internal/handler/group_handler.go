package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// GroupHandler handles group management API requests
type GroupHandler struct {
	groupService *service.GroupService
	logger       *zap.SugaredLogger
}

// NewGroupHandler creates a new group handler
func NewGroupHandler(groupService *service.GroupService, logger *zap.SugaredLogger) *GroupHandler {
	return &GroupHandler{
		groupService: groupService,
		logger:       logger,
	}
}

// CreateGroupRequest represents a create group request
type CreateGroupRequest struct {
	Name        string `json:"name" binding:"required,min=1,max=100"`
	Description string `json:"description" binding:"max=500"`
}

// GroupResponse represents a group in API responses
type GroupResponse struct {
	ID          uint           `json:"id"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	UserCount   int            `json:"userCount,omitempty"`
	Users       []UserResponse `json:"users,omitempty"`
}

// CreateGroup creates a new group
func (h *GroupHandler) CreateGroup(c *gin.Context) {
	var req CreateGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	group, err := h.groupService.CreateGroup(req.Name, req.Description)
	if err != nil {
		if err == service.ErrGroupExists {
			c.JSON(http.StatusConflict, gin.H{"error": "group already exists"})
			return
		}
		h.logger.Errorf("Create group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create group"})
		return
	}

	c.JSON(http.StatusCreated, GroupResponse{
		ID:          group.ID,
		Name:        group.Name,
		Description: group.Description,
	})
}

// ListGroups returns all groups
func (h *GroupHandler) ListGroups(c *gin.Context) {
	groups, err := h.groupService.ListGroups()
	if err != nil {
		h.logger.Errorf("List groups failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list groups"})
		return
	}

	result := make([]GroupResponse, len(groups))
	for i, g := range groups {
		result[i] = GroupResponse{
			ID:          g.ID,
			Name:        g.Name,
			Description: g.Description,
			UserCount:   len(g.Users),
		}
	}

	c.JSON(http.StatusOK, result)
}

// GetGroup returns a specific group
func (h *GroupHandler) GetGroup(c *gin.Context) {
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	group, err := h.groupService.GetGroup(uint(groupID))
	if err != nil {
		if err == service.ErrGroupNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		h.logger.Errorf("Get group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get group"})
		return
	}

	users := make([]UserResponse, len(group.Users))
	for i, u := range group.Users {
		users[i] = UserResponse{
			ID:           u.ID,
			Username:     u.Username,
			Email:        u.Email,
			IsSuperAdmin: u.IsSuperAdmin,
		}
	}

	c.JSON(http.StatusOK, GroupResponse{
		ID:          group.ID,
		Name:        group.Name,
		Description: group.Description,
		Users:       users,
	})
}

// UpdateGroupRequest represents an update group request
type UpdateGroupRequest struct {
	Name        string `json:"name" binding:"omitempty,min=1,max=100"`
	Description string `json:"description" binding:"max=500"`
}

// UpdateGroup updates a group
func (h *GroupHandler) UpdateGroup(c *gin.Context) {
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	var req UpdateGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	group, err := h.groupService.UpdateGroup(uint(groupID), req.Name, req.Description)
	if err != nil {
		if err == service.ErrGroupNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		if err == service.ErrGroupExists {
			c.JSON(http.StatusConflict, gin.H{"error": "group name already exists"})
			return
		}
		h.logger.Errorf("Update group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update group"})
		return
	}

	c.JSON(http.StatusOK, GroupResponse{
		ID:          group.ID,
		Name:        group.Name,
		Description: group.Description,
	})
}

// DeleteGroup deletes a group
func (h *GroupHandler) DeleteGroup(c *gin.Context) {
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	if err := h.groupService.DeleteGroup(uint(groupID)); err != nil {
		if err == service.ErrGroupNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		h.logger.Errorf("Delete group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "group deleted"})
}

// AddUserToGroupRequest represents an add user to group request
type AddUserToGroupRequest struct {
	UserID uint `json:"userId" binding:"required"`
}

// AddUserToGroup adds a user to a group
func (h *GroupHandler) AddUserToGroup(c *gin.Context) {
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	var req AddUserToGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.groupService.AddUserToGroup(req.UserID, uint(groupID)); err != nil {
		if err == service.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		if err == service.ErrGroupNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		h.logger.Errorf("Add user to group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add user to group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user added to group"})
}

// RemoveUserFromGroup removes a user from a group
func (h *GroupHandler) RemoveUserFromGroup(c *gin.Context) {
	groupID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group ID"})
		return
	}

	userID, err := strconv.ParseUint(c.Param("userId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	if err := h.groupService.RemoveUserFromGroup(uint(userID), uint(groupID)); err != nil {
		if err == service.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		if err == service.ErrGroupNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		h.logger.Errorf("Remove user from group failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove user from group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user removed from group"})
}
