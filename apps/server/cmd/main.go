package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	server "github.com/chenqi92/NanoLink/apps/server"
	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	"github.com/chenqi92/NanoLink/apps/server/internal/handler"
	"github.com/chenqi92/NanoLink/apps/server/internal/mcp"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	buildinfo "github.com/chenqi92/NanoLink/apps/server/internal/version"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

var (
	configFile  = flag.String("config", "config.yaml", "Configuration file path")
	showVersion = flag.Bool("version", false, "Print version information and exit")
)

// version is the single source of truth for the running build, injected at link
// time from the repository VERSION file.
var version = buildinfo.Version

func main() {
	flag.Parse()

	// -version must work before any config or database work: the self-update
	// smoke test runs a freshly downloaded binary with this flag to confirm it
	// is the build it claims to be.
	if *showVersion {
		info := buildinfo.Current()
		fmt.Printf("nanoops-server %s\ncommit: %s\nbuilt: %s\ngo: %s\nplatform: %s (%s)\n",
			info.Version, info.Commit, info.BuildTime, info.GoVersion, info.GoPlatform, info.AssetPlatform)
		return
	}

	// Initialize logger
	logger, _ := zap.NewProduction()
	defer logger.Sync()
	sugar := logger.Sugar()

	sugar.Infof("NanoOps Server v%s starting...", version)

	// Load configuration
	cfg, err := config.Load(*configFile)
	if err != nil {
		sugar.Warnf("Failed to load config file, using defaults: %v", err)
		// Note: Do NOT use config.Default() here as Load() already populated cfg with environment variables
	}

	// Perform security validations
	cfg.ValidateAndSecure()

	// Initialize database
	dbCfg := database.Config{
		Type:     cfg.Database.Type,
		Path:     cfg.Database.Path,
		Host:     cfg.Database.Host,
		Port:     cfg.Database.Port,
		Database: cfg.Database.Database,
		Username: cfg.Database.Username,
		Password: cfg.Database.Password,
	}
	if err := database.Initialize(dbCfg, sugar); err != nil {
		sugar.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.Close()

	// Initialize services
	metricsService := service.NewMetricsService(sugar)
	agentService := service.NewAgentService(sugar, metricsService)

	// Initialize metrics persistence if enabled
	// Default to true if not explicitly set
	var metricsPersistence *service.MetricsPersistence
	persistEnabled := cfg.Metrics.PersistToDB
	// If config file was not loaded, default to enabled
	if cfg.Metrics.RetentionDays == 0 {
		persistEnabled = true
		cfg.Metrics.RetentionDays = 7
		cfg.Metrics.HourlyRetentionDays = 30
		cfg.Metrics.DailyRetentionDays = 365
	}
	sugar.Infof("Metrics persistence config: enabled=%v, retention=%d days", persistEnabled, cfg.Metrics.RetentionDays)
	if persistEnabled {
		metricsPersistence = service.NewMetricsPersistence(database.GetDB(), cfg.Metrics, sugar)
		metricsService.SetPersistence(metricsPersistence)
		metricsPersistence.Start()
		defer metricsPersistence.Stop()
		sugar.Info("Metrics persistence enabled")
	}

	// Initialize auth services
	jwtExpire := time.Duration(cfg.JWT.ExpireHour) * time.Hour
	if jwtExpire == 0 {
		jwtExpire = 24 * time.Hour
	}
	authConfig := service.AuthConfig{
		JWTSecret:               cfg.JWT.Secret,
		JWTExpire:               jwtExpire,
		AdminUser:               cfg.SuperAdmin.Username,
		AdminPass:               cfg.SuperAdmin.Password,
		AllowPublicRegistration: cfg.Auth.AllowPublicRegistration,
	}
	// Debug log for super admin configuration
	if cfg.SuperAdmin.Username != "" {
		sugar.Infof("Super admin configured: username=%s, password_len=%d", cfg.SuperAdmin.Username, len(cfg.SuperAdmin.Password))
	} else {
		sugar.Warn("No super admin username configured from NANOLINK_ADMIN_USERNAME")
	}
	authService := service.NewAuthService(database.GetDB(), authConfig, sugar)

	// Bootstrap safety: if there is no admin to log in as and self-registration is
	// off, the server is unreachable. Warn loudly with the remediation instead of
	// silently leaving an unusable (or, if registration were on, hijackable) state.
	if cfg.SuperAdmin.Username == "" && !cfg.Auth.AllowPublicRegistration {
		var userCount int64
		database.GetDB().Model(&database.User{}).Count(&userCount)
		if userCount == 0 {
			sugar.Warn("[SECURITY] No users exist and public registration is disabled. " +
				"Bootstrap an admin with NANOLINK_ADMIN_USERNAME/NANOLINK_ADMIN_PASSWORD, " +
				"or set NANOLINK_ALLOW_PUBLIC_REGISTRATION=true to allow one-time first-admin signup.")
		}
	}

	groupService := service.NewGroupService(database.GetDB(), sugar)
	permService := service.NewPermissionService(database.GetDB(), sugar)
	auditService := service.NewAuditService(database.GetDB(), sugar)
	agentTokenService := service.NewAgentTokenService(database.GetDB(), sugar)
	agentTokenService.StartCleanupJob() // Auto-cleanup expired tokens

	// Alert evaluation against live metrics
	alertService := service.NewAlertService(database.GetDB(), metricsService, agentService, sugar)
	alertService.Start()
	defer alertService.Stop()

	// Upstream release checking. Start() only schedules background checks and
	// never blocks startup, so an unreachable update feed cannot delay boot.
	selfUpdateService := service.NewSelfUpdateService(cfg.Update, sugar)
	selfUpdateService.Start()
	defer selfUpdateService.Stop()

	// Initialize device service for mobile/desktop client pairing
	// Use ExternalURL from config for QR codes, fallback to localhost for development
	serverURL := cfg.Server.ExternalURL
	if serverURL == "" {
		serverURL = fmt.Sprintf("http://localhost:%d", cfg.Server.HTTPPort)
		sugar.Warn("NANOLINK_EXTERNAL_URL not set, using localhost for device pairing QR codes. Set this for production deployments.")
	}
	deviceService := service.NewDeviceService(database.GetDB(), sugar, serverURL)

	// Setup Gin router
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	if err := router.SetTrustedProxies(cfg.Server.TrustedProxies); err != nil {
		sugar.Fatalf("Invalid server.trusted_proxies configuration: %v", err)
	}
	forwardedHeaders, err := handler.NewForwardedHeadersMiddleware(cfg.Server.TrustedProxies)
	if err != nil {
		sugar.Fatalf("Invalid server.trusted_proxies configuration: %v", err)
	}
	router.Use(gin.Recovery())
	router.Use(forwardedHeaders)
	router.Use(handler.SecurityHeaders())
	router.Use(corsMiddleware(cfg.Server.AllowedOrigins))

	// API routes
	api := router.Group("/api")
	api.Use(handler.LimitRequestBody(cfg.Server.MaxRequestBodyBytes))
	// h is declared at outer scope so it can be wired with grpcServer/auditService
	// after the gRPC server is constructed below
	h := handler.NewHandlerWithPermissions(agentService, metricsService, permService, sugar)
	{
		// Public routes (no auth required)
		authHandler := handler.NewAuthHandler(authService, sugar)
		api.POST("/auth/register", authHandler.Register)
		api.POST("/auth/login", authHandler.Login)

		// Device token authentication (public, uses X-Device-Token header)
		deviceHandler := handler.NewDeviceHandler(deviceService, sugar, "NanoOps")
		api.POST("/auth/device", deviceHandler.AuthenticateDevice)
		// Pairing-code redemption (public): exchange a manual 6-digit code for a token
		api.POST("/auth/pairing", deviceHandler.RedeemPairingCode)

		// Health check (public)
		if metricsPersistence != nil {
			h.SetMetricsPersistence(metricsPersistence)
		}
		api.GET("/health", h.Health)

		// Protected routes (require authentication)
		protected := api.Group("")
		protected.Use(handler.AuthMiddleware(authService))
		{
			// Current user
			protected.GET("/auth/me", authHandler.GetMe)
			protected.POST("/auth/logout", authHandler.Logout)
			protected.PUT("/auth/password", authHandler.UpdatePassword)

			// Agent routes (with permission filtering)
			protected.GET("/agents", h.GetAgents)
			protected.GET("/agents/:id", h.GetAgent)
			protected.GET("/agents/:id/metrics", h.GetAgentMetrics)
			protected.GET("/metrics", h.GetAllMetrics)
			protected.GET("/metrics/history", h.GetMetricsHistory)
			protected.GET("/summary", h.GetSummary)

			// Command execution (requires permission check)
			protected.POST("/agents/:id/command",
				handler.RequireAgentPermission(permService, database.PermissionReadOnly),
				h.SendCommand)
			// Poll for a dispatched command's structured result
			protected.GET("/agents/:id/command/:commandId/result",
				handler.RequireAgentPermission(permService, database.PermissionReadOnly),
				h.GetCommandResult)

			// Group routes
			groupHandler := handler.NewGroupHandler(groupService, sugar)
			protected.GET("/groups", groupHandler.ListGroups)
			protected.GET("/groups/:id", groupHandler.GetGroup)

			// Editable server settings (read + write are super-admin only; routes
			// registered under the admin group below, since values include secrets).
			settingHandler := handler.NewSettingHandler(database.GetDB(), sugar)

			// Permission check route
			permHandler := handler.NewPermissionHandler(permService, auditService, sugar)
			protected.POST("/permissions/check", permHandler.CheckPermission)
			protected.GET("/agents/:id/groups", permHandler.GetAgentGroups)

			// Device management routes (logged-in users can manage their own devices)
			deviceHandler := handler.NewDeviceHandler(deviceService, sugar, "NanoOps")
			protected.POST("/devices/token", deviceHandler.GenerateToken)
			protected.GET("/devices", deviceHandler.ListDevices)
			protected.GET("/devices/:id", deviceHandler.GetDevice)
			protected.PATCH("/devices/:id", deviceHandler.UpdateDevice)
			protected.DELETE("/devices/:id", deviceHandler.DeleteDevice)

			// Configuration generator routes are registered under the super-admin group below.
			configGen := handler.NewConfigGenHandler(cfg, sugar, agentTokenService)

			// Alerts are filtered to the current user's visible agents. Rule,
			// channel and silence configuration is super-admin-only below.
			alertHandler := handler.NewAlertHandler(alertService, permService, sugar)
			protected.GET("/alerts", alertHandler.ListAlerts)
			protected.POST("/alerts/ack/:id", alertHandler.AckAlert)
			protected.POST("/alerts/ack-all", alertHandler.AckAll)

			// Audit log (read-only) for authenticated users. Mobile device
			// sessions need the recent activity feed without super-admin rights;
			// mutating/management audit queries stay under the super-admin group.
			auditHandler := handler.NewAuditHandler(auditService, sugar)
			protected.GET("/audit/recent", auditHandler.GetRecentLogs)

			// AI assistant (metric-derived findings + optional external-LLM chat)
			llmClient := service.NewLLMClient(service.LLMConfig{
				Enabled:   cfg.LLM.Enabled,
				Provider:  cfg.LLM.Provider,
				Model:     cfg.LLM.Model,
				BaseURL:   cfg.LLM.BaseURL,
				APIKey:    cfg.LLM.APIKey,
				MaxTokens: cfg.LLM.MaxTokens,
			})
			llmSettingsManager, err := service.NewLLMSettingsManager(database.GetDB(), llmClient, service.LLMConfig{
				Enabled:   cfg.LLM.Enabled,
				Provider:  cfg.LLM.Provider,
				Model:     cfg.LLM.Model,
				BaseURL:   cfg.LLM.BaseURL,
				APIKey:    cfg.LLM.APIKey,
				MaxTokens: cfg.LLM.MaxTokens,
			}, cfg.JWT.Secret)
			if err != nil {
				sugar.Fatalf("initialize AI provider settings: %v", err)
			}
			if _, err := llmSettingsManager.Reload(context.Background()); err != nil {
				sugar.Errorf("load persisted AI provider settings failed; using startup configuration: %v", err)
			}
			llmSettingHandler := handler.NewLLMSettingHandler(llmSettingsManager, sugar)

			// Saved provider/model profiles, switchable from the assistant.
			llmProfileService := service.NewLLMProfileService(database.GetDB(), llmSettingsManager)
			llmProfileHandler := handler.NewLLMProfileHandler(llmProfileService, sugar)

			assistantHandler := handler.NewAssistantHandler(metricsService, agentService, database.GetDB(), permService, llmClient, sugar)
			assistantHandler.SetProfileService(llmProfileService)
			protected.GET("/assistant/findings", assistantHandler.Findings)
			protected.GET("/assistant/status", assistantHandler.Status)
			protected.POST("/assistant/chat", assistantHandler.Chat)
			// Read-only profile list so any authenticated user can pick a model
			// in the assistant. Secrets are never included in the response.
			protected.GET("/assistant/profiles", llmProfileHandler.ListProfiles)

			// Build identity and update state. The read is available to any
			// authenticated user; checking and applying are admin-only below.
			versionHandler := handler.NewVersionHandler(selfUpdateService, auditService, sugar)
			protected.GET("/version", versionHandler.GetVersion)

			// Super admin only routes
			admin := protected.Group("")
			admin.Use(handler.RequireSuperAdmin())
			{
				// Version check reaches out to the network on request; apply
				// replaces the running binary. Both are super-admin only.
				admin.GET("/version/check", versionHandler.CheckUpdate)
				admin.POST("/version/apply", versionHandler.ApplyUpdate)

				// User management (full CRUD)
				userHandler := handler.NewUserHandler(database.GetDB(), sugar, authService, groupService)
				admin.GET("/users", userHandler.ListUsers)
				admin.GET("/users/:id", userHandler.GetUser)
				admin.POST("/users", userHandler.CreateUser)
				admin.PUT("/users/:id", userHandler.UpdateUser)
				admin.DELETE("/users/:id", userHandler.DeleteUser)
				admin.PUT("/users/:id/password", userHandler.ChangePassword)

				// Group management
				admin.POST("/groups", groupHandler.CreateGroup)
				admin.PUT("/groups/:id", groupHandler.UpdateGroup)
				admin.DELETE("/groups/:id", groupHandler.DeleteGroup)
				admin.POST("/groups/:id/users", groupHandler.AddUserToGroup)
				admin.DELETE("/groups/:id/users/:userId", groupHandler.RemoveUserFromGroup)

				// Permission management
				admin.POST("/agents/groups", permHandler.AssignAgentToGroup)
				admin.DELETE("/agents/:agentId/groups/:groupId", permHandler.RemoveAgentFromGroup)
				admin.POST("/permissions", permHandler.SetUserPermission)
				admin.DELETE("/permissions/:userId/:agentId", permHandler.RemoveUserPermission)
				admin.GET("/permissions/:userId", permHandler.GetUserPermissions)

				// Audit log routes (super admin only). The read-only
				// /audit/recent feed is registered under the plain protected
				// group above; the detailed/filtered queries stay here.
				admin.GET("/audit/logs", auditHandler.QueryAuditLogs)
				admin.GET("/audit/logs/user/:userId", auditHandler.GetUserAuditLogs)
				admin.GET("/audit/logs/agent/:agentId", auditHandler.GetAgentAuditLogs)
				admin.GET("/audit/stats", auditHandler.GetAuditStats)

				// Agent token management (super admin only)
				agentTokenHandler := handler.NewAgentTokenHandler(agentTokenService, agentService, sugar)
				admin.GET("/agent-tokens", agentTokenHandler.ListAgentTokens)
				admin.POST("/agent-tokens", agentTokenHandler.CreateAgentToken)
				admin.PUT("/agent-tokens/:id", agentTokenHandler.UpdateAgentToken)
				admin.DELETE("/agent-tokens/:id", agentTokenHandler.DeleteAgentToken)
				admin.POST("/agent-tokens/:id/regenerate", agentTokenHandler.RegenerateAgentToken)
				admin.PUT("/agent-tokens/reorder", agentTokenHandler.ReorderAgentTokens)

				admin.GET("/settings", settingHandler.GetSettings)
				admin.PUT("/settings", settingHandler.UpdateSettings)
				admin.GET("/settings/llm", llmSettingHandler.Get)
				admin.PUT("/settings/llm", llmSettingHandler.Update)
				admin.POST("/settings/llm/test", llmSettingHandler.Test)

				// Provider/model profile management (secrets stay server-side)
				admin.GET("/settings/llm/providers", llmProfileHandler.ListProviders)
				admin.GET("/settings/llm/profiles", llmProfileHandler.ListProfiles)
				admin.GET("/settings/llm/profiles/:id", llmProfileHandler.GetProfile)
				admin.POST("/settings/llm/profiles", llmProfileHandler.CreateProfile)
				admin.PUT("/settings/llm/profiles/:id", llmProfileHandler.UpdateProfile)
				admin.DELETE("/settings/llm/profiles/:id", llmProfileHandler.DeleteProfile)
				admin.POST("/settings/llm/profiles/:id/activate", llmProfileHandler.SetActiveProfile)
				admin.POST("/settings/llm/models", llmProfileHandler.ListModels)

				admin.POST("/config/generate", configGen.GenerateConfig)
				admin.POST("/config/add-server", configGen.GenerateAddServerCommand)
				admin.POST("/config/remove-server", configGen.GenerateRemoveServerCommand)
				admin.GET("/config/tokens", configGen.ListTokens)
				admin.POST("/config/generate-token", configGen.GenerateToken)

				// Alert rule & channel management (super admin only)
				admin.GET("/alerts/rules", alertHandler.ListRules)
				admin.GET("/alerts/channels", alertHandler.ListChannels)
				admin.GET("/alerts/silences", alertHandler.ListSilences)
				admin.POST("/alerts/rules", alertHandler.CreateRule)
				admin.PUT("/alerts/rules/:id", alertHandler.UpdateRule)
				admin.DELETE("/alerts/rules/:id", alertHandler.DeleteRule)
				admin.POST("/alerts/channels", alertHandler.CreateChannel)
				admin.DELETE("/alerts/channels/:id", alertHandler.DeleteChannel)
				admin.POST("/alerts/channels/:id/test", alertHandler.TestChannel)
				admin.POST("/alerts/silences", alertHandler.CreateSilence)
				admin.DELETE("/alerts/silences/:id", alertHandler.DeleteSilence)
			}
		}

		// Public server discovery
		configGen := handler.NewConfigGenHandler(cfg, sugar)
		api.GET("/server-info", configGen.GetServerURLInfo)
	}

	// Prometheus is disabled by default. When enabled it requires a dedicated
	// bearer token; browser sessions and query-string credentials are rejected.
	if cfg.Metrics.PrometheusEnabled {
		prometheus := router.Group("/metrics")
		prometheus.Use(handler.RequireBearerToken(cfg.Metrics.PrometheusToken))
		prometheus.GET("", gin.WrapH(handler.NewMetricsPromHandler(metricsService)))
	}

	// Serve embedded web UI
	webDist, err := fs.Sub(server.WebFS, "web/dist")
	if err == nil {
		router.StaticFS("/dashboard", http.FS(webDist))
		router.GET("/", func(c *gin.Context) {
			c.Redirect(http.StatusMovedPermanently, "/dashboard")
		})
	}

	// Shell WebSocket endpoint (needs gRPC server reference, so created after)
	// Will be registered after gRPC server is created

	// Start gRPC server with auth interceptor
	grpcAuthInterceptor := grpcserver.NewAuthInterceptor(authService, permService, sugar)
	grpcServer := grpcserver.NewServerWithAuth(cfg, agentService, agentTokenService, metricsService, grpcAuthInterceptor, sugar)

	// Build the canonical MCP registry regardless of whether serving is enabled so
	// authenticated dashboard users can inspect the capabilities in this build.
	mcpOptions := []mcp.Option{mcp.WithAuditService(auditService), mcp.WithGRPCServer(grpcServer)}
	var mcpSSETransport *mcp.SSETransport
	if cfg.MCP.Enabled {
		switch cfg.MCP.Transport {
		case "sse":
			addr := net.JoinHostPort(cfg.MCP.SSEBindAddress, fmt.Sprintf("%d", cfg.MCP.SSEPort))
			mcpSSETransport = mcp.NewSSETransport(addr, cfg.MCP.SSEAuthToken, sugar)
			mcpOptions = append(mcpOptions, mcp.WithTransport(mcpSSETransport), mcp.WithTransportName("sse"))
		default:
			mcpOptions = append(mcpOptions, mcp.WithTransport(mcp.NewStdioTransport(sugar)), mcp.WithTransportName("stdio"))
		}
	}
	mcpServer := mcp.NewServer(agentService, metricsService, sugar, mcpOptions...)
	mcpOverviewAPI := router.Group("/api")
	mcpOverviewAPI.Use(handler.LimitRequestBody(cfg.Server.MaxRequestBodyBytes), handler.AuthMiddleware(authService))
	mcpOverviewAPI.GET("/mcp/overview", handler.NewMCPStatusHandler(mcpServer).Overview)

	// Wire gRPC server and audit service into the main handler so /api/agents/:id/command
	// dispatches commands to agents (with audit) instead of returning a placeholder
	h.SetGRPCServer(grpcServer)
	h.SetAuditService(auditService)

	deploymentHandler, err := handler.NewDeploymentHandler(
		database.GetDB(), grpcServer, cfg.Deployment, cfg.Server.ExternalURL, sugar,
	)
	if err != nil {
		sugar.Fatalf("Failed to initialize deployment service: %v", err)
	}
	// Agents authenticate artifact downloads with a short-lived task token, not
	// a browser cookie. All management and upload routes remain super-admin only.
	router.GET("/api/deployment-artifacts/:taskId", deploymentHandler.DownloadArtifact)
	deploymentAPI := router.Group("/api")
	deploymentAPI.Use(handler.LimitRequestBody(cfg.Server.MaxRequestBodyBytes))
	deploymentAPI.Use(handler.AuthMiddleware(authService), handler.RequireSuperAdmin())
	{
		deploymentAPI.GET("/deployment-projects", deploymentHandler.ListProjects)
		deploymentAPI.GET("/deployment-projects/:id", deploymentHandler.GetProject)
		deploymentAPI.POST("/deployment-projects", deploymentHandler.CreateProject)
		deploymentAPI.PUT("/deployment-projects/:id", deploymentHandler.UpdateProject)
		deploymentAPI.POST("/deployment-projects/:id/releases/:releaseId/deploy", deploymentHandler.DeployRelease)
		deploymentAPI.POST("/deployment-projects/:id/releases/:releaseId/rollback", deploymentHandler.RollbackRelease)
		deploymentAPI.GET("/deployment-tasks/:taskId", deploymentHandler.GetTask)
	}
	deploymentUploadAPI := router.Group("/api")
	deploymentUploadAPI.Use(handler.AuthMiddleware(authService), handler.RequireSuperAdmin())
	deploymentUploadAPI.POST("/deployment-projects/:id/releases", deploymentHandler.UploadRelease)

	// Register protected dashboard and shell WebSocket handlers (after gRPC server is available)
	dashboardWSHandler := handler.NewDashboardWSHandler(sugar, permService, agentService, metricsService, cfg.Server.AllowedOrigins)
	shellHandler := handler.NewShellHandler(sugar, grpcServer, cfg.Server.AllowedOrigins)

	// Wire agent lifecycle events to the dashboard hub so register/reconnect and
	// disconnect events reach connected dashboard clients in real time. The
	// service package cannot import the handler package, so the hooks are set here.
	agentService.SetOnAgentUpdate(dashboardWSHandler.BroadcastAgentRegistered)
	agentService.SetOnAgentOffline(dashboardWSHandler.BroadcastAgentOffline)
	// Feed the live firing-alert count into the dashboard summary.
	dashboardWSHandler.SetActiveAlertCountFn(func() int {
		instances, err := alertService.ListInstances("firing")
		if err != nil {
			return 0
		}
		return len(instances)
	})
	wsProtected := router.Group("/ws")
	wsProtected.Use(handler.AuthMiddleware(authService))
	{
		wsProtected.GET("/dashboard", dashboardWSHandler.HandleDashboardWS)
		wsProtected.GET("/shell/:id",
			handler.RequireAgentPermission(permService, database.PermissionSystemAdmin),
			shellHandler.HandleShellWS)
	}

	// Register data request API (after gRPC server is available)
	dataRequestHandler := handler.NewDataRequestHandler(grpcServer, sugar)
	dataRequestApi := router.Group("/api")
	dataRequestApi.Use(handler.AuthMiddleware(authService))
	{
		// Data request endpoints - request specific data from agents on demand
		dataRequestApi.POST("/agents/:id/data-request",
			handler.RequireAgentPermission(permService, database.PermissionReadOnly),
			dataRequestHandler.RequestData)
		dataRequestApi.POST("/agents/data-request",
			handler.RequireSuperAdmin(),
			dataRequestHandler.RequestDataFromAll)
	}

	// Register log query API (after gRPC server is available)
	logQueryHandler := handler.NewLogQueryHandler(grpcServer, auditService, sugar)
	logQueryApi := router.Group("/api")
	logQueryApi.Use(handler.AuthMiddleware(authService))
	{
		// Log query endpoints - query logs from agents
		// SERVICE_LOGS: Level 0+ (all users can query, output sanitized)
		logQueryApi.POST("/agents/:id/logs/service",
			handler.RequireAgentPermission(permService, database.PermissionReadOnly),
			logQueryHandler.QueryServiceLogs)
		// SYSTEM_LOGS: Level 1+ (BASIC_WRITE required)
		logQueryApi.POST("/agents/:id/logs/system",
			handler.RequireAgentPermission(permService, database.PermissionBasicWrite),
			logQueryHandler.QuerySystemLogs)
		// AUDIT_LOGS: Level 2+ (SERVICE_CONTROL required)
		logQueryApi.POST("/agents/:id/logs/audit",
			handler.RequireAgentPermission(permService, database.PermissionServiceControl),
			logQueryHandler.QueryAuditLogs)
	}

	// Fan command results out to both interactive shell sessions and persistent
	// deployment tasks.
	grpcServer.SetCommandResultHandler(func(agentID, commandID, output string, success bool) {
		shellHandler.SendOutputToSession(agentID, commandID, output, success)
		deploymentHandler.HandleCommandResult(agentID, commandID, output, success)
	})

	// Set broadcast callback in metrics service for real-time push
	metricsService.SetBroadcastCallback(func(agentID string, metrics interface{}) {
		dashboardWSHandler.BroadcastMetrics(agentID, metrics)
	})

	// Start HTTP server after all routes are registered.
	httpServer := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Server.HTTPPort),
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      90 * time.Second,
		IdleTimeout:       2 * time.Minute,
		MaxHeaderBytes:    1 << 20,
		TLSConfig:         &tls.Config{MinVersion: tls.VersionTLS12},
	}

	go func() {
		sugar.Infof("HTTP server starting on port %d (TLS=%v)", cfg.Server.HTTPPort, cfg.Server.TLSCert != "")
		var serveErr error
		if cfg.Server.TLSCert != "" {
			serveErr = httpServer.ListenAndServeTLS(cfg.Server.TLSCert, cfg.Server.TLSKey)
		} else {
			serveErr = httpServer.ListenAndServe()
		}
		if serveErr != nil && serveErr != http.ErrServerClosed {
			sugar.Fatalf("HTTP server error: %v", serveErr)
		}
	}()

	// Start WebSocket server after handlers are fully initialized.
	wsHandler := handler.NewWebSocketHandler(agentService, agentTokenService, metricsService, cfg, sugar)
	wsServer := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Server.WSPort),
		Handler:           wsHandler,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       2 * time.Minute,
		MaxHeaderBytes:    1 << 20,
		TLSConfig:         &tls.Config{MinVersion: tls.VersionTLS12},
	}

	go func() {
		sugar.Infof("WebSocket server starting on port %d (TLS=%v)", cfg.Server.WSPort, cfg.Server.TLSCert != "")
		var serveErr error
		if cfg.Server.TLSCert != "" {
			serveErr = wsServer.ListenAndServeTLS(cfg.Server.TLSCert, cfg.Server.TLSKey)
		} else {
			serveErr = wsServer.ListenAndServe()
		}
		if serveErr != nil && serveErr != http.ErrServerClosed {
			sugar.Fatalf("WebSocket server error: %v", serveErr)
		}
	}()

	go func() {
		sugar.Infof("gRPC server starting on port %d", cfg.Server.GRPCPort)
		if err := grpcServer.Start(cfg.Server.GRPCPort, cfg.Server.TLSCert, cfg.Server.TLSKey, cfg.Server.GRPCClientCA); err != nil {
			sugar.Fatalf("gRPC server error: %v", err)
		}
	}()

	// Start the configured MCP transport and serve loop after the HTTP routes are live.
	if cfg.MCP.Enabled {
		sugar.Info("MCP server enabled, starting...")
		if mcpSSETransport != nil {
			go func() {
				if err := mcpSSETransport.Serve(); err != nil && err != http.ErrServerClosed {
					sugar.Errorf("MCP SSE server error: %v", err)
				}
			}()
			sugar.Infof("MCP server using SSE transport on %s:%d", cfg.MCP.SSEBindAddress, cfg.MCP.SSEPort)
		} else {
			sugar.Info("MCP server using stdio transport")
		}
		go func() {
			if err := mcpServer.Serve(context.Background()); err != nil {
				sugar.Errorf("MCP server error: %v", err)
			}
		}()
	}

	sugar.Infof("NanoLink Server started successfully")
	httpScheme, wsScheme, grpcScheme := "http", "ws", "grpc"
	if cfg.Server.TLSCert != "" {
		httpScheme, wsScheme, grpcScheme = "https", "wss", "grpcs"
	}
	sugar.Infof("  Dashboard: %s://localhost:%d/dashboard", httpScheme, cfg.Server.HTTPPort)
	sugar.Infof("  API: %s://localhost:%d/api", httpScheme, cfg.Server.HTTPPort)
	sugar.Infof("  Dashboard WS: %s://localhost:%d/ws/dashboard", wsScheme, cfg.Server.HTTPPort)
	sugar.Infof("  Agent WS: %s://localhost:%d", wsScheme, cfg.Server.WSPort)
	sugar.Infof("  gRPC: %s://localhost:%d", grpcScheme, cfg.Server.GRPCPort)
	if cfg.MCP.Enabled {
		if cfg.MCP.Transport == "sse" {
			sugar.Infof("  MCP (SSE): http://%s:%d/sse", cfg.MCP.SSEBindAddress, cfg.MCP.SSEPort)
		} else {
			sugar.Infof("  MCP: stdio (use with Claude Desktop or other MCP clients)")
		}
	}

	// Wait for shutdown signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	sugar.Info("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(ctx); err != nil {
		sugar.Errorf("HTTP server shutdown error: %v", err)
	}

	if err := wsServer.Shutdown(ctx); err != nil {
		sugar.Errorf("WebSocket server shutdown error: %v", err)
	}

	// Stop MCP only when its serve loop was started.
	if cfg.MCP.Enabled {
		mcpServer.Stop()
		if mcpSSETransport != nil {
			_ = mcpSSETransport.Close()
		}
		sugar.Info("MCP server stopped")
	}

	grpcServer.Stop()
	sugar.Info("gRPC server stopped")

	sugar.Info("Server stopped")
}

func corsMiddleware(allowedOrigins []string) gin.HandlerFunc {
	return func(c *gin.Context) {
		handler.ApplyCORSHeaders(c, allowedOrigins)
		if c.IsAborted() {
			return
		}

		c.Next()
	}
}
