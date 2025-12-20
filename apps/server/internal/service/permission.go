package service

import (
	"errors"
	"fmt"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// PermissionService handles agent permissions and visibility
type PermissionService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewPermissionService creates a new permission service
func NewPermissionService(db *gorm.DB, logger *zap.SugaredLogger) *PermissionService {
	return &PermissionService{
		db:     db,
		logger: logger,
	}
}

// Permission errors
var (
	ErrAgentNotAssigned       = errors.New("agent not assigned to any group")
	ErrPermissionNotFound     = errors.New("permission not found")
	ErrInvalidPermissionLevel = errors.New("invalid permission level")
)

// AssignAgentToGroup assigns an agent to a group with a permission level
func (s *PermissionService) AssignAgentToGroup(agentID string, groupID uint, permissionLevel int) error {
	if permissionLevel < 0 || permissionLevel > 3 {
		return ErrInvalidPermissionLevel
	}

	// Check if group exists
	var group database.Group
	if err := s.db.First(&group, groupID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrGroupNotFound
		}
		return fmt.Errorf("database error: %w", err)
	}

	// Check if assignment already exists
	var existing database.AgentGroup
	err := s.db.Where("agent_id = ? AND group_id = ?", agentID, groupID).First(&existing).Error

	if err == nil {
		// Update existing assignment
		existing.PermissionLevel = permissionLevel
		if updateErr := s.db.Save(&existing).Error; updateErr != nil {
			return fmt.Errorf("failed to update agent-group assignment: %w", updateErr)
		}
	} else if errors.Is(err, gorm.ErrRecordNotFound) {
		// Create new assignment
		assignment := &database.AgentGroup{
			AgentID:         agentID,
			GroupID:         groupID,
			PermissionLevel: permissionLevel,
		}
		if createErr := s.db.Create(assignment).Error; createErr != nil {
			return fmt.Errorf("failed to create agent-group assignment: %w", createErr)
		}
	} else {
		return fmt.Errorf("database error: %w", err)
	}

	s.logger.Infof("Agent '%s' assigned to group '%s' with permission level %d", agentID, group.Name, permissionLevel)
	return nil
}

// RemoveAgentFromGroup removes an agent from a group
func (s *PermissionService) RemoveAgentFromGroup(agentID string, groupID uint) error {
	result := s.db.Where("agent_id = ? AND group_id = ?", agentID, groupID).Delete(&database.AgentGroup{})
	if result.Error != nil {
		return fmt.Errorf("failed to remove agent from group: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return ErrAgentNotAssigned
	}
	s.logger.Infof("Agent '%s' removed from group ID %d", agentID, groupID)
	return nil
}

// SetUserAgentPermission sets a user's permission for a specific agent
func (s *PermissionService) SetUserAgentPermission(userID uint, agentID string, permissionLevel int, grantedBy uint) error {
	if permissionLevel < 0 || permissionLevel > 3 {
		return ErrInvalidPermissionLevel
	}

	// Check if user exists
	var user database.User
	if err := s.db.First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return fmt.Errorf("database error: %w", err)
	}

	// Check if permission already exists
	var existing database.UserAgentPermission
	err := s.db.Where("user_id = ? AND agent_id = ?", userID, agentID).First(&existing).Error

	if err == nil {
		// Update existing permission
		existing.PermissionLevel = permissionLevel
		existing.GrantedBy = grantedBy
		if updateErr := s.db.Save(&existing).Error; updateErr != nil {
			return fmt.Errorf("failed to update permission: %w", updateErr)
		}
	} else if errors.Is(err, gorm.ErrRecordNotFound) {
		// Create new permission
		perm := &database.UserAgentPermission{
			UserID:          userID,
			AgentID:         agentID,
			PermissionLevel: permissionLevel,
			GrantedBy:       grantedBy,
		}
		if createErr := s.db.Create(perm).Error; createErr != nil {
			return fmt.Errorf("failed to create permission: %w", createErr)
		}
	} else {
		return fmt.Errorf("database error: %w", err)
	}

	s.logger.Infof("User ID %d granted permission level %d for agent '%s'", userID, permissionLevel, agentID)
	return nil
}

// RemoveUserAgentPermission removes a user's permission for an agent
func (s *PermissionService) RemoveUserAgentPermission(userID uint, agentID string) error {
	result := s.db.Where("user_id = ? AND agent_id = ?", userID, agentID).Delete(&database.UserAgentPermission{})
	if result.Error != nil {
		return fmt.Errorf("failed to remove permission: %w", result.Error)
	}
	return nil
}

// GetUserAgentPermission returns a user's permission level for an agent
// Returns the highest permission level from: direct assignment, or group membership
func (s *PermissionService) GetUserAgentPermission(userID uint, agentID string) (int, error) {
	var user database.User
	if err := s.db.Preload("Groups").First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return -1, ErrUserNotFound
		}
		return -1, fmt.Errorf("database error: %w", err)
	}

	// Super admin has max permission
	if user.IsSuperAdmin {
		// Get the agent's max granted permission from any group
		var maxPerm int
		err := s.db.Model(&database.AgentGroup{}).
			Where("agent_id = ?", agentID).
			Select("COALESCE(MAX(permission_level), 3)").
			Scan(&maxPerm).Error
		if err != nil {
			return 3, nil // Default to system admin for superadmin
		}
		return maxPerm, nil
	}

	maxPermission := -1

	// Check direct user-agent permission
	var directPerm database.UserAgentPermission
	if err := s.db.Where("user_id = ? AND agent_id = ?", userID, agentID).First(&directPerm).Error; err == nil {
		maxPermission = directPerm.PermissionLevel
	}

	// Check group-based permissions
	for _, group := range user.Groups {
		var agentGroup database.AgentGroup
		if err := s.db.Where("agent_id = ? AND group_id = ?", agentID, group.ID).First(&agentGroup).Error; err == nil {
			if agentGroup.PermissionLevel > maxPermission {
				maxPermission = agentGroup.PermissionLevel
			}
		}
	}

	if maxPermission == -1 {
		return -1, ErrPermissionDenied
	}

	return maxPermission, nil
}

// GetVisibleAgents returns a list of agent IDs that a user can see
func (s *PermissionService) GetVisibleAgents(userID uint) ([]string, error) {
	var user database.User
	if err := s.db.Preload("Groups").First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("database error: %w", err)
	}

	// Super admin can see all agents
	if user.IsSuperAdmin {
		return nil, nil // nil means "all agents"
	}

	agentMap := make(map[string]bool)

	// Get agents from user's groups
	for _, group := range user.Groups {
		var agentGroups []database.AgentGroup
		if err := s.db.Where("group_id = ?", group.ID).Find(&agentGroups).Error; err == nil {
			for _, ag := range agentGroups {
				agentMap[ag.AgentID] = true
			}
		}
	}

	// Get agents from direct permissions
	var directPerms []database.UserAgentPermission
	if err := s.db.Where("user_id = ?", userID).Find(&directPerms).Error; err == nil {
		for _, perm := range directPerms {
			agentMap[perm.AgentID] = true
		}
	}

	agents := make([]string, 0, len(agentMap))
	for agentID := range agentMap {
		agents = append(agents, agentID)
	}

	return agents, nil
}

// CanUserAccessAgent checks if a user can access a specific agent
func (s *PermissionService) CanUserAccessAgent(userID uint, agentID string) (bool, error) {
	perm, err := s.GetUserAgentPermission(userID, agentID)
	if err != nil {
		if errors.Is(err, ErrPermissionDenied) {
			return false, nil
		}
		return false, err
	}
	return perm >= 0, nil
}

// CanUserExecuteCommand checks if a user has sufficient permission to execute a command
func (s *PermissionService) CanUserExecuteCommand(userID uint, agentID string, requiredLevel int) (bool, error) {
	perm, err := s.GetUserAgentPermission(userID, agentID)
	if err != nil {
		if errors.Is(err, ErrPermissionDenied) {
			return false, nil
		}
		return false, err
	}
	return perm >= requiredLevel, nil
}

// GetAgentGroups returns all groups an agent is assigned to
func (s *PermissionService) GetAgentGroups(agentID string) ([]database.AgentGroup, error) {
	var agentGroups []database.AgentGroup
	if err := s.db.Preload("Group").Where("agent_id = ?", agentID).Find(&agentGroups).Error; err != nil {
		return nil, fmt.Errorf("database error: %w", err)
	}
	return agentGroups, nil
}

// GetUserPermissions returns all direct permissions assigned to a user
func (s *PermissionService) GetUserPermissions(userID uint) ([]database.UserAgentPermission, error) {
	var perms []database.UserAgentPermission
	if err := s.db.Preload("User").Where("user_id = ?", userID).Find(&perms).Error; err != nil {
		return nil, fmt.Errorf("database error: %w", err)
	}
	return perms, nil
}

// GetAgentMaxPermissionLevel returns the maximum permission level granted to any group for an agent
// This determines the max permission a superadmin can delegate
func (s *PermissionService) GetAgentMaxPermissionLevel(agentID string) (int, error) {
	var maxPerm int
	err := s.db.Model(&database.AgentGroup{}).
		Where("agent_id = ?", agentID).
		Select("COALESCE(MAX(permission_level), 0)").
		Scan(&maxPerm).Error
	if err != nil {
		return 0, fmt.Errorf("database error: %w", err)
	}
	return maxPerm, nil
}
