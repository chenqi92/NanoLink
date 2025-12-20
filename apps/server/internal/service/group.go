package service

import (
	"errors"
	"fmt"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// GroupService handles group management
type GroupService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewGroupService creates a new group service
func NewGroupService(db *gorm.DB, logger *zap.SugaredLogger) *GroupService {
	return &GroupService{
		db:     db,
		logger: logger,
	}
}

// Group errors
var (
	ErrGroupNotFound = errors.New("group not found")
	ErrGroupExists   = errors.New("group already exists")
)

// CreateGroup creates a new group
func (s *GroupService) CreateGroup(name, description string) (*database.Group, error) {
	// Check if group exists
	var existing database.Group
	if err := s.db.Where("name = ?", name).First(&existing).Error; err == nil {
		return nil, ErrGroupExists
	}

	group := &database.Group{
		Name:        name,
		Description: description,
	}

	if err := s.db.Create(group).Error; err != nil {
		return nil, fmt.Errorf("failed to create group: %w", err)
	}

	s.logger.Infof("Group '%s' created successfully", name)
	return group, nil
}

// GetGroup retrieves a group by ID
func (s *GroupService) GetGroup(groupID uint) (*database.Group, error) {
	var group database.Group
	if err := s.db.Preload("Users").First(&group, groupID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrGroupNotFound
		}
		return nil, fmt.Errorf("database error: %w", err)
	}
	return &group, nil
}

// ListGroups returns all groups
func (s *GroupService) ListGroups() ([]database.Group, error) {
	var groups []database.Group
	if err := s.db.Preload("Users").Find(&groups).Error; err != nil {
		return nil, fmt.Errorf("database error: %w", err)
	}
	return groups, nil
}

// UpdateGroup updates a group's information
func (s *GroupService) UpdateGroup(groupID uint, name, description string) (*database.Group, error) {
	var group database.Group
	if err := s.db.First(&group, groupID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrGroupNotFound
		}
		return nil, fmt.Errorf("database error: %w", err)
	}

	// Check if name conflicts with another group
	if name != "" && name != group.Name {
		var existing database.Group
		if err := s.db.Where("name = ? AND id != ?", name, groupID).First(&existing).Error; err == nil {
			return nil, ErrGroupExists
		}
		group.Name = name
	}

	if description != "" {
		group.Description = description
	}

	if err := s.db.Save(&group).Error; err != nil {
		return nil, fmt.Errorf("failed to update group: %w", err)
	}

	s.logger.Infof("Group '%s' (ID: %d) updated", group.Name, groupID)
	return &group, nil
}

// DeleteGroup deletes a group
func (s *GroupService) DeleteGroup(groupID uint) error {
	// Remove all users from group first
	if err := s.db.Exec("DELETE FROM user_groups WHERE group_id = ?", groupID).Error; err != nil {
		return fmt.Errorf("failed to remove users from group: %w", err)
	}

	// Remove agent-group associations
	if err := s.db.Where("group_id = ?", groupID).Delete(&database.AgentGroup{}).Error; err != nil {
		return fmt.Errorf("failed to remove agent associations: %w", err)
	}

	// Delete group
	if err := s.db.Delete(&database.Group{}, groupID).Error; err != nil {
		return fmt.Errorf("failed to delete group: %w", err)
	}

	s.logger.Infof("Group ID %d deleted", groupID)
	return nil
}

// AddUserToGroup adds a user to a group
func (s *GroupService) AddUserToGroup(userID, groupID uint) error {
	var user database.User
	if err := s.db.First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return fmt.Errorf("database error: %w", err)
	}

	var group database.Group
	if err := s.db.First(&group, groupID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrGroupNotFound
		}
		return fmt.Errorf("database error: %w", err)
	}

	// Use association to add user to group
	if err := s.db.Model(&group).Association("Users").Append(&user); err != nil {
		return fmt.Errorf("failed to add user to group: %w", err)
	}

	s.logger.Infof("User '%s' added to group '%s'", user.Username, group.Name)
	return nil
}

// RemoveUserFromGroup removes a user from a group
func (s *GroupService) RemoveUserFromGroup(userID, groupID uint) error {
	var user database.User
	if err := s.db.First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return fmt.Errorf("database error: %w", err)
	}

	var group database.Group
	if err := s.db.First(&group, groupID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrGroupNotFound
		}
		return fmt.Errorf("database error: %w", err)
	}

	if err := s.db.Model(&group).Association("Users").Delete(&user); err != nil {
		return fmt.Errorf("failed to remove user from group: %w", err)
	}

	s.logger.Infof("User '%s' removed from group '%s'", user.Username, group.Name)
	return nil
}

// GetUserGroups returns all groups a user belongs to
func (s *GroupService) GetUserGroups(userID uint) ([]database.Group, error) {
	var user database.User
	if err := s.db.Preload("Groups").First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("database error: %w", err)
	}
	return user.Groups, nil
}

// GetGroupMembers returns all users in a group
func (s *GroupService) GetGroupMembers(groupID uint) ([]database.User, error) {
	var group database.Group
	if err := s.db.Preload("Users").First(&group, groupID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrGroupNotFound
		}
		return nil, fmt.Errorf("database error: %w", err)
	}
	return group.Users, nil
}
