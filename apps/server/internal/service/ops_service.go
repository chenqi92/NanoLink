package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// IncidentService handles incident management
type IncidentService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewIncidentService creates a new incident service
func NewIncidentService(db *gorm.DB, logger *zap.SugaredLogger) *IncidentService {
	return &IncidentService{
		db:     db,
		logger: logger,
	}
}

// CreateIncident creates a new incident
func (s *IncidentService) CreateIncident(ctx context.Context, incident *database.Incident) error {
	return s.db.Create(incident).Error
}

// UpdateIncident updates an incident
func (s *IncidentService) UpdateIncident(ctx context.Context, incidentID uint, updates map[string]interface{}) error {
	return s.db.Model(&database.Incident{}).Where("id = ?", incidentID).Updates(updates).Error
}

// ResolveIncident marks an incident as resolved
func (s *IncidentService) ResolveIncident(ctx context.Context, incidentID uint, rootCause string, resolution string) error {
	now := time.Now()
	return s.db.Model(&database.Incident{}).Where("id = ?", incidentID).Updates(map[string]interface{}{
		"status":      "resolved",
		"resolved_at": now,
		"root_cause":  rootCause,
		"resolution":  resolution,
		"updated_at":  now,
	}).Error
}

// CloseIncident marks an incident as closed
func (s *IncidentService) CloseIncident(ctx context.Context, incidentID uint) error {
	now := time.Now()
	return s.db.Model(&database.Incident{}).Where("id = ?", incidentID).Updates(map[string]interface{}{
		"status":     "closed",
		"closed_at":  now,
		"updated_at": now,
	}).Error
}

// AssignIncident assigns an incident to a user
func (s *IncidentService) AssignIncident(ctx context.Context, incidentID uint, userID uint) error {
	return s.db.Model(&database.Incident{}).Where("id = ?", incidentID).Updates(map[string]interface{}{
		"assigned_to": userID,
		"updated_at":  time.Now(),
	}).Error
}

// GetIncident returns an incident by ID
func (s *IncidentService) GetIncident(ctx context.Context, incidentID uint) (*database.Incident, error) {
	var incident database.Incident
	if err := s.db.Preload("Creator").Preload("Assignee").First(&incident, incidentID).Error; err != nil {
		return nil, err
	}
	return &incident, nil
}

// ListIncidents returns incidents with filters
func (s *IncidentService) ListIncidents(ctx context.Context, filters map[string]interface{}, limit int) ([]database.Incident, error) {
	var incidents []database.Incident
	query := s.db.Preload("Creator").Preload("Assignee")

	if status, ok := filters["status"].(string); ok && status != "" {
		query = query.Where("status = ?", status)
	}
	if severity, ok := filters["severity"].(string); ok && severity != "" {
		query = query.Where("severity = ?", severity)
	}
	if assignedTo, ok := filters["assigned_to"].(uint); ok && assignedTo > 0 {
		query = query.Where("assigned_to = ?", assignedTo)
	}

	if limit > 0 {
		query = query.Limit(limit)
	}

	if err := query.Order("started_at DESC").Find(&incidents).Error; err != nil {
		return nil, err
	}
	return incidents, nil
}

// LinkIncidentToAlert links an incident to an alert
func (s *IncidentService) LinkIncidentToAlert(ctx context.Context, incidentID uint, alertID uint) error {
	var incident database.Incident
	if err := s.db.First(&incident, incidentID).Error; err != nil {
		return fmt.Errorf("incident not found: %w", err)
	}

	var relatedAlerts []uint
	if incident.RelatedAlerts != "" {
		if err := json.Unmarshal([]byte(incident.RelatedAlerts), &relatedAlerts); err != nil {
			relatedAlerts = []uint{}
		}
	}

	// Check if already linked
	for _, id := range relatedAlerts {
		if id == alertID {
			return nil // Already linked
		}
	}

	relatedAlerts = append(relatedAlerts, alertID)
	alertsJSON, _ := json.Marshal(relatedAlerts)

	return s.db.Model(&incident).Update("related_alerts", string(alertsJSON)).Error
}

// PackageService handles package management
type PackageService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewPackageService creates a new package service
func NewPackageService(db *gorm.DB, logger *zap.SugaredLogger) *PackageService {
	return &PackageService{
		db:     db,
		logger: logger,
	}
}

// UpsertPackages updates or inserts package information for an agent
func (s *PackageService) UpsertPackages(ctx context.Context, agentID string, packages []database.Package) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Delete existing packages for this agent
		if err := tx.Where("agent_id = ?", agentID).Delete(&database.Package{}).Error; err != nil {
			return fmt.Errorf("delete old packages: %w", err)
		}

		// Insert new packages
		if len(packages) > 0 {
			for i := range packages {
				packages[i].AgentID = agentID
				packages[i].UpdatedAt = time.Now()
			}
			if err := tx.Create(&packages).Error; err != nil {
				return fmt.Errorf("insert packages: %w", err)
			}
		}

		return nil
	})
}

// GetAgentPackages returns all packages for an agent
func (s *PackageService) GetAgentPackages(ctx context.Context, agentID string) ([]database.Package, error) {
	var packages []database.Package
	if err := s.db.Where("agent_id = ?", agentID).
		Order("name ASC").
		Find(&packages).Error; err != nil {
		return nil, err
	}
	return packages, nil
}

// GetSecurityUpdates returns packages with security updates available
func (s *PackageService) GetSecurityUpdates(ctx context.Context, agentID string) ([]database.Package, error) {
	var packages []database.Package
	query := s.db.Where("is_security = ?", true)

	if agentID != "" {
		query = query.Where("agent_id = ?", agentID)
	}

	if err := query.Order("agent_id ASC, name ASC").Find(&packages).Error; err != nil {
		return nil, err
	}
	return packages, nil
}

// GetOutdatedPackages returns packages with updates available
func (s *PackageService) GetOutdatedPackages(ctx context.Context, agentID string) ([]database.Package, error) {
	var packages []database.Package
	query := s.db.Where("latest_version IS NOT NULL").
		Where("latest_version != current_version")

	if agentID != "" {
		query = query.Where("agent_id = ?", agentID)
	}

	if err := query.Order("agent_id ASC, name ASC").Find(&packages).Error; err != nil {
		return nil, err
	}
	return packages, nil
}

// PolicyService handles IAM policy operations
type PolicyService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewPolicyService creates a new policy service
func NewPolicyService(db *gorm.DB, logger *zap.SugaredLogger) *PolicyService {
	return &PolicyService{
		db:     db,
		logger: logger,
	}
}

// CreatePolicy creates a new policy
func (s *PolicyService) CreatePolicy(ctx context.Context, policy *database.Policy) error {
	return s.db.Create(policy).Error
}

// UpdatePolicy updates a policy
func (s *PolicyService) UpdatePolicy(ctx context.Context, policyID uint, updates map[string]interface{}) error {
	return s.db.Model(&database.Policy{}).Where("id = ?", policyID).Updates(updates).Error
}

// DeletePolicy deletes a policy
func (s *PolicyService) DeletePolicy(ctx context.Context, policyID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Delete bindings first
		if err := tx.Where("policy_id = ?", policyID).Delete(&database.PolicyBinding{}).Error; err != nil {
			return fmt.Errorf("delete bindings: %w", err)
		}
		// Delete policy
		if err := tx.Delete(&database.Policy{}, policyID).Error; err != nil {
			return fmt.Errorf("delete policy: %w", err)
		}
		return nil
	})
}

// GetPolicy returns a policy by ID
func (s *PolicyService) GetPolicy(ctx context.Context, policyID uint) (*database.Policy, error) {
	var policy database.Policy
	if err := s.db.First(&policy, policyID).Error; err != nil {
		return nil, err
	}
	return &policy, nil
}

// ListPolicies returns all policies
func (s *PolicyService) ListPolicies(ctx context.Context) ([]database.Policy, error) {
	var policies []database.Policy
	if err := s.db.Order("priority DESC, name ASC").Find(&policies).Error; err != nil {
		return nil, err
	}
	return policies, nil
}

// BindPolicy binds a policy to a principal
func (s *PolicyService) BindPolicy(ctx context.Context, policyID uint, principalType string, principalID uint, actorID uint) error {
	binding := &database.PolicyBinding{
		PolicyID:      policyID,
		PrincipalType: principalType,
		PrincipalID:   principalID,
		GrantedBy:     actorID,
	}
	return s.db.Create(binding).Error
}

// UnbindPolicy removes a policy binding
func (s *PolicyService) UnbindPolicy(ctx context.Context, bindingID uint) error {
	return s.db.Delete(&database.PolicyBinding{}, bindingID).Error
}

// GetUserPolicies returns all policies bound to a user (directly or via groups)
func (s *PolicyService) GetUserPolicies(ctx context.Context, userID uint) ([]database.Policy, error) {
	var policies []database.Policy

	// Get direct bindings
	var directBindings []database.PolicyBinding
	if err := s.db.Where("principal_type = ? AND principal_id = ?", "user", userID).
		Find(&directBindings).Error; err != nil {
		return nil, fmt.Errorf("get direct bindings: %w", err)
	}

	policyIDs := make(map[uint]bool)
	for _, b := range directBindings {
		policyIDs[b.PolicyID] = true
	}

	// Get group bindings
	var user database.User
	if err := s.db.Preload("Groups").First(&user, userID).Error; err != nil {
		return nil, fmt.Errorf("get user groups: %w", err)
	}

	for _, group := range user.Groups {
		var groupBindings []database.PolicyBinding
		if err := s.db.Where("principal_type = ? AND principal_id = ?", "group", group.ID).
			Find(&groupBindings).Error; err != nil {
			return nil, fmt.Errorf("get group bindings: %w", err)
		}
		for _, b := range groupBindings {
			policyIDs[b.PolicyID] = true
		}
	}

	// Fetch all unique policies
	if len(policyIDs) > 0 {
		ids := make([]uint, 0, len(policyIDs))
		for id := range policyIDs {
			ids = append(ids, id)
		}
		if err := s.db.Where("id IN ?", ids).
			Where("enabled = ?", true).
			Order("priority DESC").
			Find(&policies).Error; err != nil {
			return nil, fmt.Errorf("get policies: %w", err)
		}
	}

	return policies, nil
}

// NodeCapabilityService handles node capability ceiling management
type NodeCapabilityService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewNodeCapabilityService creates a new node capability service
func NewNodeCapabilityService(db *gorm.DB, logger *zap.SugaredLogger) *NodeCapabilityService {
	return &NodeCapabilityService{
		db:     db,
		logger: logger,
	}
}

// SetNodeCapability sets or updates node capability ceiling
func (s *NodeCapabilityService) SetNodeCapability(ctx context.Context, cap *database.NodeCapability) error {
	// Upsert: update if exists, create if not
	var existing database.NodeCapability
	err := s.db.Where("agent_id = ?", cap.AgentID).First(&existing).Error

	if err == nil {
		// Update existing
		return s.db.Model(&existing).Updates(cap).Error
	}

	if err == gorm.ErrRecordNotFound {
		// Create new
		return s.db.Create(cap).Error
	}

	return fmt.Errorf("check existing capability: %w", err)
}

// GetNodeCapability returns node capability ceiling
func (s *NodeCapabilityService) GetNodeCapability(ctx context.Context, agentID string) (*database.NodeCapability, error) {
	var cap database.NodeCapability
	if err := s.db.Where("agent_id = ?", agentID).First(&cap).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			// Return default capability if not set
			return &database.NodeCapability{
				AgentID:          agentID,
				MaxPermission:    3,
				AllowShell:       true,
				AllowFileWrite:   true,
				AllowReboot:      true,
				AllowProcessKill: true,
			}, nil
		}
		return nil, err
	}
	return &cap, nil
}

// ListNodeCapabilities returns all node capabilities
func (s *NodeCapabilityService) ListNodeCapabilities(ctx context.Context) ([]database.NodeCapability, error) {
	var caps []database.NodeCapability
	if err := s.db.Preload("Updater").Order("agent_id ASC").Find(&caps).Error; err != nil {
		return nil, err
	}
	return caps, nil
}

// DeleteNodeCapability removes node capability (revert to default)
func (s *NodeCapabilityService) DeleteNodeCapability(ctx context.Context, agentID string) error {
	return s.db.Where("agent_id = ?", agentID).Delete(&database.NodeCapability{}).Error
}
