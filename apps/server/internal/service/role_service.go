package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// RoleService handles role and permission operations
type RoleService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewRoleService creates a new role service
func NewRoleService(db *gorm.DB, logger *zap.SugaredLogger) *RoleService {
	return &RoleService{
		db:     db,
		logger: logger,
	}
}

// CreateRole creates a new role with permissions
func (s *RoleService) CreateRole(ctx context.Context, role *database.Role, permissions []string, actorID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Create role
		if err := tx.Create(role).Error; err != nil {
			return fmt.Errorf("create role: %w", err)
		}

		// Add permissions
		for _, perm := range permissions {
			rp := &database.RolePermission{
				RoleID:     role.ID,
				Permission: perm,
				Effect:     "allow",
			}
			if err := tx.Create(rp).Error; err != nil {
				return fmt.Errorf("add permission %s: %w", perm, err)
			}
		}

		// Record history
		changes, _ := json.Marshal(map[string]interface{}{
			"name":        role.Name,
			"displayName": role.DisplayName,
			"permissions": permissions,
		})
		history := &database.PermissionHistory{
			Timestamp:  time.Now(),
			ActorID:    actorID,
			Action:     "role.create",
			TargetType: "role",
			TargetID:   role.ID,
			TargetName: role.Name,
			Changes:    string(changes),
		}
		return tx.Create(history).Error
	})
}

// UpdateRole updates a role and its permissions
func (s *RoleService) UpdateRole(ctx context.Context, roleID uint, updates map[string]interface{}, permissions []string, actorID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var role database.Role
		if err := tx.First(&role, roleID).Error; err != nil {
			return fmt.Errorf("find role: %w", err)
		}

		if role.IsBuiltin {
			return errors.New("cannot modify builtin role")
		}

		// Update role fields
		if err := tx.Model(&role).Updates(updates).Error; err != nil {
			return fmt.Errorf("update role: %w", err)
		}

		// Update permissions if provided
		if permissions != nil {
			// Delete existing permissions
			if err := tx.Where("role_id = ?", roleID).Delete(&database.RolePermission{}).Error; err != nil {
				return fmt.Errorf("delete old permissions: %w", err)
			}

			// Add new permissions
			for _, perm := range permissions {
				rp := &database.RolePermission{
					RoleID:     roleID,
					Permission: perm,
					Effect:     "allow",
				}
				if err := tx.Create(rp).Error; err != nil {
					return fmt.Errorf("add permission %s: %w", perm, err)
				}
			}
		}

		// Record history
		changes, _ := json.Marshal(map[string]interface{}{
			"updates":     updates,
			"permissions": permissions,
		})
		history := &database.PermissionHistory{
			Timestamp:  time.Now(),
			ActorID:    actorID,
			Action:     "role.update",
			TargetType: "role",
			TargetID:   roleID,
			TargetName: role.Name,
			Changes:    string(changes),
		}
		return tx.Create(history).Error
	})
}

// DeleteRole deletes a role
func (s *RoleService) DeleteRole(ctx context.Context, roleID uint, actorID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var role database.Role
		if err := tx.First(&role, roleID).Error; err != nil {
			return fmt.Errorf("find role: %w", err)
		}

		if role.IsBuiltin {
			return errors.New("cannot delete builtin role")
		}

		// Check if role is in use
		var bindingCount int64
		if err := tx.Model(&database.RoleBinding{}).Where("role_id = ?", roleID).Count(&bindingCount).Error; err != nil {
			return fmt.Errorf("count bindings: %w", err)
		}
		if bindingCount > 0 {
			return fmt.Errorf("role is still bound to %d principals", bindingCount)
		}

		// Delete permissions first
		if err := tx.Where("role_id = ?", roleID).Delete(&database.RolePermission{}).Error; err != nil {
			return fmt.Errorf("delete permissions: %w", err)
		}

		// Delete role
		if err := tx.Delete(&role).Error; err != nil {
			return fmt.Errorf("delete role: %w", err)
		}

		// Record history
		changes, _ := json.Marshal(map[string]interface{}{
			"name": role.Name,
		})
		history := &database.PermissionHistory{
			Timestamp:  time.Now(),
			ActorID:    actorID,
			Action:     "role.delete",
			TargetType: "role",
			TargetID:   roleID,
			TargetName: role.Name,
			Changes:    string(changes),
		}
		return tx.Create(history).Error
	})
}

// ListRoles returns all roles
func (s *RoleService) ListRoles(ctx context.Context) ([]database.Role, error) {
	var roles []database.Role
	if err := s.db.Preload("Permissions").Order("is_builtin DESC, name ASC").Find(&roles).Error; err != nil {
		return nil, fmt.Errorf("list roles: %w", err)
	}
	return roles, nil
}

// GetRole returns a role by ID with its permissions
func (s *RoleService) GetRole(ctx context.Context, roleID uint) (*database.Role, error) {
	var role database.Role
	if err := s.db.Preload("Permissions").First(&role, roleID).Error; err != nil {
		return nil, fmt.Errorf("get role: %w", err)
	}
	return &role, nil
}

// BindRole binds a role to a principal (user or group)
func (s *RoleService) BindRole(ctx context.Context, roleID uint, principalType string, principalID uint, scope string, actorID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Verify role exists
		var role database.Role
		if err := tx.First(&role, roleID).Error; err != nil {
			return fmt.Errorf("find role: %w", err)
		}

		// Check for existing binding
		var existing database.RoleBinding
		err := tx.Where("role_id = ? AND principal_type = ? AND principal_id = ?", roleID, principalType, principalID).
			First(&existing).Error
		if err == nil {
			return errors.New("binding already exists")
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("check existing binding: %w", err)
		}

		// Create binding
		binding := &database.RoleBinding{
			RoleID:        roleID,
			PrincipalType: principalType,
			PrincipalID:   principalID,
			ResourceScope: scope,
			GrantedBy:     actorID,
		}
		if err := tx.Create(binding).Error; err != nil {
			return fmt.Errorf("create binding: %w", err)
		}

		// Record history
		changes, _ := json.Marshal(map[string]interface{}{
			"roleId":        roleID,
			"roleName":      role.Name,
			"principalType": principalType,
			"principalId":   principalID,
			"scope":         scope,
		})
		history := &database.PermissionHistory{
			Timestamp:  time.Now(),
			ActorID:    actorID,
			Action:     "binding.create",
			TargetType: "binding",
			TargetID:   binding.ID,
			Changes:    string(changes),
		}
		return tx.Create(history).Error
	})
}

// UnbindRole removes a role binding
func (s *RoleService) UnbindRole(ctx context.Context, bindingID uint, actorID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var binding database.RoleBinding
		if err := tx.Preload("Role").First(&binding, bindingID).Error; err != nil {
			return fmt.Errorf("find binding: %w", err)
		}

		if err := tx.Delete(&binding).Error; err != nil {
			return fmt.Errorf("delete binding: %w", err)
		}

		// Record history
		changes, _ := json.Marshal(map[string]interface{}{
			"roleId":        binding.RoleID,
			"roleName":      binding.Role.Name,
			"principalType": binding.PrincipalType,
			"principalId":   binding.PrincipalID,
		})
		history := &database.PermissionHistory{
			Timestamp:  time.Now(),
			ActorID:    actorID,
			Action:     "binding.delete",
			TargetType: "binding",
			TargetID:   bindingID,
			Changes:    string(changes),
		}
		return tx.Create(history).Error
	})
}

// GetUserRoles returns all roles bound to a user (directly or via groups)
func (s *RoleService) GetUserRoles(ctx context.Context, userID uint) ([]database.Role, error) {
	var roles []database.Role

	// Get direct bindings
	var directBindings []database.RoleBinding
	if err := s.db.Where("principal_type = ? AND principal_id = ?", "user", userID).
		Find(&directBindings).Error; err != nil {
		return nil, fmt.Errorf("get direct bindings: %w", err)
	}

	roleIDs := make(map[uint]bool)
	for _, b := range directBindings {
		roleIDs[b.RoleID] = true
	}

	// Get group bindings
	var user database.User
	if err := s.db.Preload("Groups").First(&user, userID).Error; err != nil {
		return nil, fmt.Errorf("get user groups: %w", err)
	}

	for _, group := range user.Groups {
		var groupBindings []database.RoleBinding
		if err := s.db.Where("principal_type = ? AND principal_id = ?", "group", group.ID).
			Find(&groupBindings).Error; err != nil {
			return nil, fmt.Errorf("get group bindings: %w", err)
		}
		for _, b := range groupBindings {
			roleIDs[b.RoleID] = true
		}
	}

	// Fetch all unique roles
	if len(roleIDs) > 0 {
		ids := make([]uint, 0, len(roleIDs))
		for id := range roleIDs {
			ids = append(ids, id)
		}
		if err := s.db.Preload("Permissions").Where("id IN ?", ids).Find(&roles).Error; err != nil {
			return nil, fmt.Errorf("get roles: %w", err)
		}
	}

	return roles, nil
}

// CheckPermission checks if a user has a specific permission
func (s *RoleService) CheckPermission(ctx context.Context, userID uint, permission string) (bool, error) {
	// Get user's roles
	roles, err := s.GetUserRoles(ctx, userID)
	if err != nil {
		return false, err
	}

	// Check for wildcard admin role
	for _, role := range roles {
		for _, perm := range role.Permissions {
			if perm.Permission == "*" && perm.Effect == "allow" {
				return true, nil
			}
		}
	}

	// Check for exact or wildcard match
	for _, role := range roles {
		for _, perm := range role.Permissions {
			if matchPermission(perm.Permission, permission) {
				if perm.Effect == "deny" {
					return false, nil
				}
				if perm.Effect == "allow" {
					return true, nil
				}
			}
		}
	}

	return false, nil
}

// matchPermission checks if a permission pattern matches a specific permission
// Supports wildcards: "node.*" matches "node.read", "node.write", etc.
func matchPermission(pattern, permission string) bool {
	if pattern == permission {
		return true
	}

	if strings.HasSuffix(pattern, ".*") {
		prefix := strings.TrimSuffix(pattern, ".*")
		return strings.HasPrefix(permission, prefix+".")
	}

	return false
}

// GetPermissionHistory returns permission change history
func (s *RoleService) GetPermissionHistory(ctx context.Context, targetType string, targetID uint, limit int) ([]database.PermissionHistory, error) {
	var history []database.PermissionHistory
	query := s.db.Order("timestamp DESC")

	if targetType != "" {
		query = query.Where("target_type = ?", targetType)
	}
	if targetID > 0 {
		query = query.Where("target_id = ?", targetID)
	}
	if limit > 0 {
		query = query.Limit(limit)
	}

	if err := query.Find(&history).Error; err != nil {
		return nil, fmt.Errorf("get history: %w", err)
	}

	return history, nil
}
