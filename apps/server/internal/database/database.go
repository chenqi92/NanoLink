package database

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"go.uber.org/zap"
	"gorm.io/driver/mysql"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// DB is the global database instance
var DB *gorm.DB

// Config holds database configuration
type Config struct {
	Type     string // "sqlite", "mysql", or "postgres"
	Path     string // SQLite file path
	Host     string // MySQL/PostgreSQL host
	Port     int    // MySQL/PostgreSQL port
	Database string // MySQL/PostgreSQL database name
	Username string // MySQL/PostgreSQL username
	Password string // MySQL/PostgreSQL password
	SSLMode  string // PostgreSQL TLS mode
}

// Initialize initializes the database connection
func Initialize(cfg Config, log *zap.SugaredLogger) error {
	var dialector gorm.Dialector

	switch cfg.Type {
	case "mysql":
		dsn := fmt.Sprintf(
			"%s:%s@tcp(%s:%d)/%s?charset=utf8mb4&parseTime=True&loc=Local",
			cfg.Username, cfg.Password, cfg.Host, cfg.Port, cfg.Database,
		)
		dialector = mysql.Open(dsn)
	case "postgres":
		dsn, err := postgresDSN(cfg)
		if err != nil {
			return err
		}
		dialector = postgres.Open(dsn)
	case "sqlite", "":
		// Default to SQLite
		if cfg.Path == "" {
			cfg.Path = "./data/nanolink.db"
		}
		// Ensure directory exists
		if err := os.MkdirAll("./data", 0755); err != nil {
			return fmt.Errorf("failed to create data directory: %w", err)
		}
		dialector = sqlite.Open(cfg.Path)
	default:
		return fmt.Errorf("unsupported database type: %s (supported: sqlite, mysql, postgres)", cfg.Type)
	}

	// Configure GORM logger
	gormLogger := logger.New(
		&zapWriter{log},
		logger.Config{
			SlowThreshold:             time.Second,
			LogLevel:                  logger.Warn,
			IgnoreRecordNotFoundError: true,
			Colorful:                  false,
		},
	)

	db, err := gorm.Open(dialector, &gorm.Config{
		Logger: gormLogger,
	})
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}

	// Keep the connection pool bounded. PostgreSQL benefits from a small pool,
	// while SQLite must use a single writer connection to avoid lock storms.
	if sqlDB, poolErr := db.DB(); poolErr == nil {
		switch cfg.Type {
		case "postgres":
			sqlDB.SetMaxOpenConns(25)
			sqlDB.SetMaxIdleConns(10)
			sqlDB.SetConnMaxLifetime(30 * time.Minute)
			sqlDB.SetConnMaxIdleTime(5 * time.Minute)
		case "sqlite", "":
			sqlDB.SetMaxOpenConns(1)
		}
	}

	// Auto migrate schema
	if err := db.AutoMigrate(
		&User{},
		&Group{},
		&Setting{},
		&AgentGroup{},
		&UserAgentPermission{},
		&AuditLog{},
		&AgentToken{},
		&DeviceToken{},
		&AlertRule{},
		&AlertInstance{},
		&NotifyChannel{},
		&Silence{},
		&DeploymentProject{},
		&DeploymentRelease{},
		&DeploymentUploadSession{},
		&DeploymentTask{},
		&BuildPipeline{},
		&BuildRun{},
		&BuildArtifact{},
		&LLMProfile{},
	); err != nil {
		return fmt.Errorf("failed to migrate database: %w", err)
	}

	// Hash any tokens still stored in plaintext from an older schema version.
	if err := MigratePlaintextTokens(db, log); err != nil {
		return fmt.Errorf("failed to migrate tokens to hashed storage: %w", err)
	}

	DB = db
	log.Info("Database initialized successfully")
	return nil
}

func postgresDSN(cfg Config) (string, error) {
	if strings.TrimSpace(cfg.Host) == "" {
		return "", fmt.Errorf("postgres database host is required")
	}
	if cfg.Port <= 0 || cfg.Port > 65535 {
		return "", fmt.Errorf("postgres database port must be between 1 and 65535")
	}
	if strings.TrimSpace(cfg.Database) == "" {
		return "", fmt.Errorf("postgres database name is required")
	}
	if strings.TrimSpace(cfg.Username) == "" {
		return "", fmt.Errorf("postgres database username is required")
	}

	sslMode := strings.ToLower(strings.TrimSpace(cfg.SSLMode))
	if sslMode == "" {
		sslMode = "disable"
	}
	switch sslMode {
	case "disable", "allow", "prefer", "require", "verify-ca", "verify-full":
	default:
		return "", fmt.Errorf("unsupported postgres sslmode %q", cfg.SSLMode)
	}

	u := &url.URL{
		Scheme: "postgresql",
		User:   url.UserPassword(cfg.Username, cfg.Password),
		Host:   net.JoinHostPort(cfg.Host, strconv.Itoa(cfg.Port)),
		Path:   "/" + cfg.Database,
	}
	query := u.Query()
	query.Set("sslmode", sslMode)
	u.RawQuery = query.Encode()
	return u.String(), nil
}

// Close closes the database connection
func Close() error {
	if DB == nil {
		return nil
	}
	sqlDB, err := DB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}

// GetDB returns the database instance
func GetDB() *gorm.DB {
	return DB
}

// zapWriter wraps zap logger for GORM
type zapWriter struct {
	log *zap.SugaredLogger
}

func (w *zapWriter) Printf(format string, args ...interface{}) {
	w.log.Infof(format, args...)
}
