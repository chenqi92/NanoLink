package database

import (
	"encoding/json"
	"time"

	"go.uber.org/zap"
	"gorm.io/gorm"
)

// InitializeBuiltinRoles creates builtin roles and permissions if they don't exist
func InitializeBuiltinRoles(db *gorm.DB, logger *zap.SugaredLogger) error {
	logger.Info("Initializing builtin IAM roles...")

	roles := []struct {
		Name        string
		DisplayName string
		Description string
		IsBuiltin   bool
		IsReadOnly  bool
		IsDanger    bool
		Permissions []string
		Excludes    []string
		Conditions  []string
		Scope       string
	}{
		{
			Name:        "platform-owner",
			DisplayName: "Platform Owner",
			Description: "Full system access including IAM and platform configuration",
			IsBuiltin:   true,
			IsDanger:    true,
			Permissions: []string{"*"},
		},
		{
			Name:        "security-admin",
			DisplayName: "Security Admin",
			Description: "IAM, policy, credentials, audit — no node operations by default",
			IsBuiltin:   true,
			Permissions: []string{
				"cert.*",
				"user.*",
				"iam.*",
				"token.node.*",
				"session.*",
				"secret.*",
				"audit.*",
				"platform.security.manage",
				"service_account.manage",
				"api_token.manage",
				"node.list",
				"node.read",
			},
			Excludes: []string{
				"shell.*",
				"terminal.open",
				"deploy.run.execute",
			},
		},
		{
			Name:        "platform-admin",
			DisplayName: "Platform Admin",
			Description: "Platform config, alert policy, integrations, updates",
			IsBuiltin:   true,
			Permissions: []string{
				"platform.*",
				"alert.rule.*",
				"alert.route.manage",
				"alert.channel.*",
				"dashboard.read",
				"node.list",
				"node.read",
			},
		},
		{
			Name:        "ops-admin",
			DisplayName: "Ops Admin",
			Description: "All node and ops permissions — no IAM by default",
			IsBuiltin:   true,
			Permissions: []string{
				"cert.read",
				"cert.issue",
				"cert.deploy",
				"incident.*",
				"oncall.*",
				"runner.*",
				"host.*",
				"verify.read",
				"verify.run",
				"alert.silence",
				"node.*",
				"process.*",
				"service.*",
				"container.*",
				"file.*",
				"terminal.open",
				"shell.*",
				"job.*",
				"package.*",
				"script.*",
				"config.*",
				"health.*",
				"log.*",
				"alert.read",
				"alert.ack",
			},
			Excludes: []string{
				"iam.*",
				"platform.security.manage",
			},
		},
		{
			Name:        "oncall-operator",
			DisplayName: "On-call Operator",
			Description: "Read nodes/logs, ack alerts, control services — no shell, reboot or prod approval",
			IsBuiltin:   true,
			Permissions: []string{
				"cert.read",
				"incident.read",
				"incident.create",
				"incident.update",
				"incident.resolve",
				"oncall.read",
				"alert.silence",
				"job.execute",
				"verify.read",
				"node.list",
				"node.read",
				"node.metrics.read",
				"node.metrics.history",
				"log.read",
				"log.tail",
				"alert.read",
				"alert.ack",
				"alert.assign",
				"alert.comment",
				"service.read",
				"service.start",
				"service.stop",
				"service.restart",
				"process.read",
				"container.read",
				"container.logs",
				"health.read",
				"health.run",
			},
			Excludes: []string{
				"terminal.open",
				"shell.execute",
				"shell.batch_execute",
				"node.system.reboot",
				"deploy.approve",
			},
		},
		{
			Name:        "developer",
			DisplayName: "Developer",
			Description: "Build in project scope, read artifacts, deploy non-production",
			IsBuiltin:   true,
			Permissions: []string{
				"cert.read",
				"build.run.trigger",
				"artifact.upload",
				"verify.read",
				"runner.read",
				"incident.read",
				"build.pipeline.read",
				"build.pipeline.update",
				"build.run.read",
				"build.run.start",
				"build.run.retry",
				"build.log.read",
				"build.variable.manage",
				"artifact.read",
				"artifact.download",
				"deploy.application.read",
				"deploy.environment.read",
				"deploy.release.read",
				"deploy.release.create",
				"deploy.run.read",
				"deploy.run.dry_run",
				"deploy.run.execute",
				"log.read",
				"node.list",
				"node.read",
			},
			Scope: `environment != "production"`,
			Excludes: []string{
				"deploy.approve",
				"build.secret.manage",
				"iam.*",
			},
		},
		{
			Name:        "release-manager",
			DisplayName: "Release Manager",
			Description: "Manage releases, deployments and rollback — cannot change IAM",
			IsBuiltin:   true,
			Permissions: []string{
				"build.run.trigger",
				"verify.read",
				"verify.run",
				"runner.read",
				"host.read",
				"incident.read",
				"deploy.*",
				"artifact.*",
				"build.run.read",
				"build.log.read",
				"build.pipeline.read",
				"node.list",
				"node.read",
				"log.read",
			},
			Excludes: []string{
				"iam.*",
				"deploy.approve",
			},
		},
		{
			Name:        "prod-approver",
			DisplayName: "Production Approver",
			Description: "Approve production deploys — never your own by default",
			IsBuiltin:   true,
			Permissions: []string{
				"job.approve",
				"incident.read",
				"verify.read",
				"deploy.approve",
				"deploy.run.read",
				"deploy.release.read",
				"deploy.log.read",
				"audit.read",
				"node.list",
				"node.read",
			},
			Excludes: []string{
				"build.secret.manage",
				"deploy.run.execute",
				"iam.*",
			},
			Conditions: []string{"deploy.requester != self"},
		},
		{
			Name:        "auditor",
			DisplayName: "Auditor",
			Description: "Read-only with audit export",
			IsBuiltin:   true,
			IsReadOnly:  true,
			Permissions: []string{
				"cert.read",
				"audit.verify",
				"audit.read.trace",
				"incident.read",
				"oncall.read",
				"verify.read",
				"runner.read",
				"host.read",
				"audit.read",
				"audit.export",
				"node.list",
				"node.read",
				"deploy.run.read",
				"build.run.read",
				"iam.user.read",
				"iam.group.read",
				"iam.role.read",
				"iam.policy.read",
				"iam.binding.read",
				"secret.read_metadata",
			},
		},
		{
			Name:        "read-only-observer",
			DisplayName: "Read-only Observer",
			Description: "Read-only monitoring and release status",
			IsBuiltin:   true,
			IsReadOnly:  true,
			Permissions: []string{
				"incident.read",
				"dashboard.read",
				"node.list",
				"node.read",
				"node.metrics.read",
				"alert.read",
				"deploy.run.read",
				"build.run.read",
				"log.read",
			},
		},
	}

	return db.Transaction(func(tx *gorm.DB) error {
		for _, roleData := range roles {
			// Check if role already exists
			var existing Role
			err := tx.Where("name = ?", roleData.Name).First(&existing).Error
			if err == nil {
				logger.Debugf("Role %s already exists, skipping", roleData.Name)
				continue
			}
			if err != gorm.ErrRecordNotFound {
				return err
			}

			// Marshal conditions
			var conditionsJSON string
			if len(roleData.Conditions) > 0 {
				condBytes, _ := json.Marshal(roleData.Conditions)
				conditionsJSON = string(condBytes)
			}

			// Create role
			role := Role{
				Name:        roleData.Name,
				DisplayName: roleData.DisplayName,
				Description: roleData.Description,
				IsBuiltin:   roleData.IsBuiltin,
				IsReadOnly:  roleData.IsReadOnly,
				IsDanger:    roleData.IsDanger,
				Scope:       roleData.Scope,
				Conditions:  conditionsJSON,
				CreatedAt:   time.Now(),
				UpdatedAt:   time.Now(),
			}

			if err := tx.Create(&role).Error; err != nil {
				return err
			}

			// Add permissions
			for _, perm := range roleData.Permissions {
				rp := RolePermission{
					RoleID:     role.ID,
					Permission: perm,
					Effect:     "allow",
					CreatedAt:  time.Now(),
				}
				if err := tx.Create(&rp).Error; err != nil {
					return err
				}
			}

			// Add exclusions (deny permissions)
			for _, perm := range roleData.Excludes {
				rp := RolePermission{
					RoleID:     role.ID,
					Permission: perm,
					Effect:     "deny",
					CreatedAt:  time.Now(),
				}
				if err := tx.Create(&rp).Error; err != nil {
					return err
				}
			}

			logger.Infof("Created builtin role: %s", roleData.Name)
		}

		return nil
	})
}
