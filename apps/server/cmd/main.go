package main

import (
	"context"
	"flag"
	"fmt"
	"io/fs"
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
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

var (
	configFile = flag.String("config", "config.yaml", "Configuration file path")
	version    = "0.1.2"
)

func main() {
	flag.Parse()

	// Initialize logger
	logger, _ := zap.NewProduction()
	defer logger.Sync()
	sugar := logger.Sugar()

	sugar.Infof("NanoLink Server v%s starting...", version)

	// Load configuration
	cfg, err := config.Load(*configFile)
	if err != nil {
		sugar.Warnf("Failed to load config file, using defaults: %v", err)
		cfg = config.Default()
	}

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

	// Initialize auth services
	jwtExpire := time.Duration(cfg.JWT.ExpireHour) * time.Hour
	if jwtExpire == 0 {
		jwtExpire = 24 * time.Hour
	}
	authConfig := service.AuthConfig{
		JWTSecret: cfg.JWT.Secret,
		JWTExpire: jwtExpire,
		AdminUser: cfg.SuperAdmin.Username,
		AdminPass: cfg.SuperAdmin.Password,
	}
	authService := service.NewAuthService(database.GetDB(), authConfig, sugar)
	groupService := service.NewGroupService(database.GetDB(), sugar)
	permService := service.NewPermissionService(database.GetDB(), sugar)

	// Setup Gin router
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(corsMiddleware())

	// API routes
	api := router.Group("/api")
	{
		// Public routes (no auth required)
		authHandler := handler.NewAuthHandler(authService, sugar)
		api.POST("/auth/register", authHandler.Register)
		api.POST("/auth/login", authHandler.Login)

		// Health check (public)
		h := handler.NewHandlerWithPermissions(agentService, metricsService, permService, sugar)
		api.GET("/health", h.Health)

		// Protected routes (require authentication)
		protected := api.Group("")
		protected.Use(handler.AuthMiddleware(authService))
		{
			// Current user
			protected.GET("/auth/me", authHandler.GetMe)
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
				handler.RequireAgentPermission(permService, database.PermissionBasicWrite),
				h.SendCommand)

			// Group routes
			groupHandler := handler.NewGroupHandler(groupService, sugar)
			protected.GET("/groups", groupHandler.ListGroups)
			protected.GET("/groups/:id", groupHandler.GetGroup)

			// Permission check route
			permHandler := handler.NewPermissionHandler(permService, sugar)
			protected.POST("/permissions/check", permHandler.CheckPermission)
			protected.GET("/agents/:id/groups", permHandler.GetAgentGroups)

			// Super admin only routes
			admin := protected.Group("")
			admin.Use(handler.RequireSuperAdmin())
			{
				// User management
				admin.GET("/users", authHandler.ListUsers)
				admin.DELETE("/users/:id", authHandler.DeleteUser)

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
			}
		}

		// Configuration generator routes (protected)
		configGen := handler.NewConfigGenHandler(cfg, sugar)
		api.GET("/server-info", configGen.GetServerURLInfo)
		api.POST("/config/generate", configGen.GenerateConfig)
		api.POST("/config/add-server", configGen.GenerateAddServerCommand)
		api.POST("/config/remove-server", configGen.GenerateRemoveServerCommand)
		api.GET("/config/tokens", configGen.ListTokens)
		api.POST("/config/generate-token", configGen.GenerateToken)
	}

	// Serve embedded web UI
	webDist, err := fs.Sub(server.WebFS, "web/dist")
	if err == nil {
		router.StaticFS("/dashboard", http.FS(webDist))
		router.GET("/", func(c *gin.Context) {
			c.Redirect(http.StatusMovedPermanently, "/dashboard")
		})
	}

	// Start HTTP server
	httpServer := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.Server.HTTPPort),
		Handler: router,
	}

	go func() {
		sugar.Infof("HTTP server starting on port %d", cfg.Server.HTTPPort)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			sugar.Fatalf("HTTP server error: %v", err)
		}
	}()

	// Start WebSocket server
	wsHandler := handler.NewWebSocketHandler(agentService, metricsService, cfg, sugar)
	wsServer := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.Server.WSPort),
		Handler: wsHandler,
	}

	go func() {
		sugar.Infof("WebSocket server starting on port %d", cfg.Server.WSPort)
		if err := wsServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			sugar.Fatalf("WebSocket server error: %v", err)
		}
	}()

	// Start gRPC server with auth interceptor
	grpcAuthInterceptor := grpcserver.NewAuthInterceptor(authService, permService, sugar)
	grpcServer := grpcserver.NewServerWithAuth(cfg, agentService, metricsService, grpcAuthInterceptor, sugar)
	go func() {
		sugar.Infof("gRPC server starting on port %d", cfg.Server.GRPCPort)
		if err := grpcServer.Start(cfg.Server.GRPCPort, cfg.Server.TLSCert, cfg.Server.TLSKey); err != nil {
			sugar.Fatalf("gRPC server error: %v", err)
		}
	}()

	sugar.Infof("NanoLink Server started successfully")
	sugar.Infof("  Dashboard: http://localhost:%d/dashboard", cfg.Server.HTTPPort)
	sugar.Infof("  API: http://localhost:%d/api", cfg.Server.HTTPPort)
	sugar.Infof("  WebSocket: ws://localhost:%d", cfg.Server.WSPort)
	sugar.Infof("  gRPC: grpc://localhost:%d", cfg.Server.GRPCPort)

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

	grpcServer.Stop()
	sugar.Info("gRPC server stopped")

	sugar.Info("Server stopped")
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}
