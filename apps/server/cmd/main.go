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
	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	"github.com/chenqi92/NanoLink/apps/server/internal/handler"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

var (
	configFile = flag.String("config", "config.yaml", "Configuration file path")
	version    = "0.1.0"
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

	// Initialize services
	metricsService := service.NewMetricsService(sugar)
	agentService := service.NewAgentService(sugar, metricsService)

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
		h := handler.NewHandler(agentService, metricsService, sugar)
		api.GET("/health", h.Health)
		api.GET("/agents", h.GetAgents)
		api.GET("/agents/:id", h.GetAgent)
		api.GET("/agents/:id/metrics", h.GetAgentMetrics)
		api.GET("/metrics", h.GetAllMetrics)
		api.GET("/metrics/history", h.GetMetricsHistory)
		api.GET("/summary", h.GetSummary)
		api.POST("/agents/:id/command", h.SendCommand)

		// Configuration generator routes
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

	// Start gRPC server
	grpcServer := grpcserver.NewServer(cfg, agentService, metricsService, sugar)
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
