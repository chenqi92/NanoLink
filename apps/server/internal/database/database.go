package database

import (
	"fmt"
	"os"
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
		dsn := fmt.Sprintf(
			"host=%s user=%s password=%s dbname=%s port=%d sslmode=disable TimeZone=Asia/Shanghai",
			cfg.Host, cfg.Username, cfg.Password, cfg.Database, cfg.Port,
		)
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

	// Auto migrate schema
	if err := db.AutoMigrate(
		&User{},
		&Group{},
		&AgentGroup{},
		&UserAgentPermission{},
	); err != nil {
		return fmt.Errorf("failed to migrate database: %w", err)
	}

	DB = db
	log.Info("Database initialized successfully")
	return nil
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
