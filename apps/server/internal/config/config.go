package config

import (
	"github.com/spf13/viper"
)

// Config holds all configuration
type Config struct {
	Server   ServerConfig   `mapstructure:"server"`
	Auth     AuthConfig     `mapstructure:"auth"`
	Storage  StorageConfig  `mapstructure:"storage"`
	Metrics  MetricsConfig  `mapstructure:"metrics"`
}

// ServerConfig holds server configuration
type ServerConfig struct {
	HTTPPort int    `mapstructure:"http_port"`
	WSPort   int    `mapstructure:"ws_port"`
	GRPCPort int    `mapstructure:"grpc_port"`
	Mode     string `mapstructure:"mode"`
	TLSCert  string `mapstructure:"tls_cert"`
	TLSKey   string `mapstructure:"tls_key"`
}

// AuthConfig holds authentication configuration
type AuthConfig struct {
	Enabled bool        `mapstructure:"enabled"`
	Tokens  []TokenConfig `mapstructure:"tokens"`
}

// TokenConfig holds token configuration
type TokenConfig struct {
	Token      string `mapstructure:"token"`
	Permission int    `mapstructure:"permission"`
	Name       string `mapstructure:"name"`
}

// StorageConfig holds storage configuration
type StorageConfig struct {
	Type     string `mapstructure:"type"`
	Path     string `mapstructure:"path"`
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Database string `mapstructure:"database"`
	Username string `mapstructure:"username"`
	Password string `mapstructure:"password"`
}

// MetricsConfig holds metrics configuration
type MetricsConfig struct {
	RetentionDays int `mapstructure:"retention_days"`
	MaxAgents     int `mapstructure:"max_agents"`
}

// Default returns default configuration
func Default() *Config {
	return &Config{
		Server: ServerConfig{
			HTTPPort: 8080,
			WSPort:   9100,
			GRPCPort: 9200,
			Mode:     "release",
		},
		Auth: AuthConfig{
			Enabled: false,
			Tokens:  []TokenConfig{},
		},
		Storage: StorageConfig{
			Type: "memory",
			Path: "./data/nanolink.db",
		},
		Metrics: MetricsConfig{
			RetentionDays: 7,
			MaxAgents:     100,
		},
	}
}

// Load loads configuration from file
func Load(path string) (*Config, error) {
	viper.SetConfigFile(path)
	viper.SetConfigType("yaml")

	// Set defaults
	viper.SetDefault("server.http_port", 8080)
	viper.SetDefault("server.ws_port", 9100)
	viper.SetDefault("server.grpc_port", 9200)
	viper.SetDefault("server.mode", "release")
	viper.SetDefault("auth.enabled", false)
	viper.SetDefault("storage.type", "memory")
	viper.SetDefault("storage.path", "./data/nanolink.db")
	viper.SetDefault("metrics.retention_days", 7)
	viper.SetDefault("metrics.max_agents", 100)

	// Environment variable support
	viper.SetEnvPrefix("NANOLINK")
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err != nil {
		return Default(), err
	}

	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return Default(), err
	}

	return &cfg, nil
}

// ValidateToken validates a token and returns permission level
func (c *Config) ValidateToken(token string) (bool, int) {
	if !c.Auth.Enabled {
		return true, 3 // Full access when auth disabled
	}

	for _, t := range c.Auth.Tokens {
		if t.Token == token {
			return true, t.Permission
		}
	}

	return false, 0
}
