package service

import (
	"errors"
	"fmt"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/golang-jwt/jwt/v5"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// AuthService handles user authentication
type AuthService struct {
	db        *gorm.DB
	logger    *zap.SugaredLogger
	jwtSecret []byte
	jwtExpire time.Duration
}

// JWTClaims represents JWT claims
type JWTClaims struct {
	UserID       uint   `json:"userId"`
	Username     string `json:"username"`
	IsSuperAdmin bool   `json:"isSuperAdmin"`
	jwt.RegisteredClaims
}

// AuthConfig holds authentication configuration
type AuthConfig struct {
	JWTSecret string
	JWTExpire time.Duration
	AdminUser string
	AdminPass string
}

// NewAuthService creates a new authentication service
func NewAuthService(db *gorm.DB, cfg AuthConfig, logger *zap.SugaredLogger) *AuthService {
	if cfg.JWTExpire == 0 {
		cfg.JWTExpire = 24 * time.Hour
	}
	if cfg.JWTSecret == "" {
		cfg.JWTSecret = "nanolink-default-secret-change-me"
		logger.Warn("Using default JWT secret - please set NANOLINK_JWT_SECRET in production")
	}

	svc := &AuthService{
		db:        db,
		logger:    logger,
		jwtSecret: []byte(cfg.JWTSecret),
		jwtExpire: cfg.JWTExpire,
	}

	// Initialize super admin if configured
	if cfg.AdminUser != "" && cfg.AdminPass != "" {
		if err := svc.InitSuperAdmin(cfg.AdminUser, cfg.AdminPass); err != nil {
			logger.Errorf("Failed to initialize super admin: %v", err)
		}
	}

	return svc
}

// Auth errors
var (
	ErrUserNotFound     = errors.New("user not found")
	ErrInvalidPassword  = errors.New("invalid password")
	ErrUserExists       = errors.New("user already exists")
	ErrInvalidToken     = errors.New("invalid token")
	ErrTokenExpired     = errors.New("token expired")
	ErrPermissionDenied = errors.New("permission denied")
)

// InitSuperAdmin creates or updates the super admin account
func (s *AuthService) InitSuperAdmin(username, password string) error {
	var user database.User
	err := s.db.Where("username = ?", username).First(&user).Error

	hash, hashErr := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if hashErr != nil {
		return fmt.Errorf("failed to hash password: %w", hashErr)
	}

	if errors.Is(err, gorm.ErrRecordNotFound) {
		// Create new super admin
		user = database.User{
			Username:     username,
			PasswordHash: string(hash),
			IsSuperAdmin: true,
		}
		if createErr := s.db.Create(&user).Error; createErr != nil {
			return fmt.Errorf("failed to create super admin: %w", createErr)
		}
		s.logger.Infof("Super admin '%s' created successfully", username)
		return nil
	} else if err != nil {
		return fmt.Errorf("database error: %w", err)
	}

	// Update existing super admin password if needed
	if !user.IsSuperAdmin {
		user.IsSuperAdmin = true
		user.PasswordHash = string(hash)
		if updateErr := s.db.Save(&user).Error; updateErr != nil {
			return fmt.Errorf("failed to update super admin: %w", updateErr)
		}
		s.logger.Infof("User '%s' promoted to super admin", username)
	}

	return nil
}

// RegisterUser creates a new user account
func (s *AuthService) RegisterUser(username, password, email string) (*database.User, error) {
	// Check if user exists
	var existing database.User
	if err := s.db.Where("username = ?", username).First(&existing).Error; err == nil {
		return nil, ErrUserExists
	}
	if email != "" {
		if err := s.db.Where("email = ?", email).First(&existing).Error; err == nil {
			return nil, fmt.Errorf("email already registered")
		}
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	user := &database.User{
		Username:     username,
		PasswordHash: string(hash),
		Email:        email,
		IsSuperAdmin: false,
	}

	if err := s.db.Create(user).Error; err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	s.logger.Infof("User '%s' registered successfully", username)
	return user, nil
}

// LoginUser authenticates a user and returns a JWT token
func (s *AuthService) LoginUser(username, password string) (string, *database.User, error) {
	var user database.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return "", nil, ErrUserNotFound
		}
		return "", nil, fmt.Errorf("database error: %w", err)
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return "", nil, ErrInvalidPassword
	}

	// Generate JWT token
	token, err := s.GenerateToken(&user)
	if err != nil {
		return "", nil, fmt.Errorf("failed to generate token: %w", err)
	}

	s.logger.Infof("User '%s' logged in successfully", username)
	return token, &user, nil
}

// GenerateToken generates a JWT token for a user
func (s *AuthService) GenerateToken(user *database.User) (string, error) {
	now := time.Now()
	claims := JWTClaims{
		UserID:       user.ID,
		Username:     user.Username,
		IsSuperAdmin: user.IsSuperAdmin,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(s.jwtExpire)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			Issuer:    "nanolink-server",
			Subject:   fmt.Sprintf("%d", user.ID),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.jwtSecret)
}

// VerifyToken verifies a JWT token and returns the claims
func (s *AuthService) VerifyToken(tokenString string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return s.jwtSecret, nil
	})

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrTokenExpired
		}
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*JWTClaims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}

// GetUserByID retrieves a user by ID
func (s *AuthService) GetUserByID(userID uint) (*database.User, error) {
	var user database.User
	if err := s.db.First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("database error: %w", err)
	}
	return &user, nil
}

// GetUserByUsername retrieves a user by username
func (s *AuthService) GetUserByUsername(username string) (*database.User, error) {
	var user database.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("database error: %w", err)
	}
	return &user, nil
}

// ListUsers returns all users (for super admin)
func (s *AuthService) ListUsers() ([]database.User, error) {
	var users []database.User
	if err := s.db.Preload("Groups").Find(&users).Error; err != nil {
		return nil, fmt.Errorf("database error: %w", err)
	}
	return users, nil
}

// DeleteUser deletes a user by ID
func (s *AuthService) DeleteUser(userID uint) error {
	// First remove user from all groups
	if err := s.db.Exec("DELETE FROM user_groups WHERE user_id = ?", userID).Error; err != nil {
		return fmt.Errorf("failed to remove user from groups: %w", err)
	}

	// Delete user agent permissions
	if err := s.db.Where("user_id = ?", userID).Delete(&database.UserAgentPermission{}).Error; err != nil {
		return fmt.Errorf("failed to delete user permissions: %w", err)
	}

	// Delete user
	if err := s.db.Delete(&database.User{}, userID).Error; err != nil {
		return fmt.Errorf("failed to delete user: %w", err)
	}

	s.logger.Infof("User ID %d deleted", userID)
	return nil
}

// UpdatePassword updates a user's password
func (s *AuthService) UpdatePassword(userID uint, newPassword string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("failed to hash password: %w", err)
	}

	if err := s.db.Model(&database.User{}).Where("id = ?", userID).Update("password_hash", string(hash)).Error; err != nil {
		return fmt.Errorf("failed to update password: %w", err)
	}

	return nil
}
