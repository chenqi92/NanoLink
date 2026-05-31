package service

import (
	"errors"
	"fmt"
	"sync"
	"time"
	"unicode"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/golang-jwt/jwt/v5"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// AuthService handles user authentication
type AuthService struct {
	db           *gorm.DB
	logger       *zap.SugaredLogger
	jwtSecret    []byte
	jwtExpire    time.Duration
	loginLimiter *LoginRateLimiter
	bootstrapMu  sync.Mutex
}

// JWTClaims represents JWT claims
type JWTClaims struct {
	UserID       uint   `json:"userId"`
	Username     string `json:"username"`
	IsSuperAdmin bool   `json:"isSuperAdmin"`
	// TokenVersion mirrors User.TokenVersion at issue time. The auth middleware rejects
	// the token if the user's row has since been bumped (e.g. by a password change),
	// invalidating every previously issued token for that user.
	TokenVersion uint `json:"tv"`
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
		// No more fallback default - must be configured
		logger.Error("[SECURITY CRITICAL] JWT secret is not set! Please set NANOLINK_JWT_SECRET environment variable.")
		logger.Error("[SECURITY CRITICAL] JWT secret will be auto-generated, but this is NOT recommended for production.")
	}

	svc := &AuthService{
		db:           db,
		logger:       logger,
		jwtSecret:    []byte(cfg.JWTSecret),
		jwtExpire:    cfg.JWTExpire,
		loginLimiter: NewLoginRateLimiter(5, 5*time.Minute), // 5 attempts, 5 min lockout
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
	ErrUserNotFound       = errors.New("user not found")
	ErrInvalidPassword    = errors.New("invalid password")
	ErrUserExists         = errors.New("user already exists")
	ErrInvalidToken       = errors.New("invalid token")
	ErrTokenExpired       = errors.New("token expired")
	ErrPermissionDenied   = errors.New("permission denied")
	ErrWeakPassword       = errors.New("password does not meet strength requirements")
	ErrTooManyAttempts    = errors.New("too many login attempts, please try again later")
	ErrRegistrationClosed = errors.New("registration is closed")
)

// LoginRateLimiter is an in-memory per-key counter that locks out a key after
// too many failed attempts within a window.
//
// Why a single mutex instead of RWMutex split between Check and Record:
// the previous design had Check under RLock and RecordFailure under Lock, but
// the read-decide-write sequence wasn't atomic, so concurrent failed logins
// could each pass Check before any of them bumped the counter, letting the
// total exceed maxAttempts. Collapsing the read+decide+write into one Lock
// closes that race. Login throughput is low enough that contention doesn't
// matter.
type LoginRateLimiter struct {
	mu          sync.Mutex
	attempts    map[string]*loginAttempt
	maxAttempts int
	lockoutTime time.Duration
	stopCh      chan struct{}
}

type loginAttempt struct {
	count     int
	lastReset time.Time
	lockedAt  *time.Time
}

// NewLoginRateLimiter constructs the limiter and starts a background sweeper
// that drops entries older than 2x lockoutTime, so the map cannot grow
// unboundedly under sustained credential-stuffing attacks.
func NewLoginRateLimiter(maxAttempts int, lockoutTime time.Duration) *LoginRateLimiter {
	l := &LoginRateLimiter{
		attempts:    make(map[string]*loginAttempt),
		maxAttempts: maxAttempts,
		lockoutTime: lockoutTime,
		stopCh:      make(chan struct{}),
	}
	go l.sweepLoop()
	return l
}

// Stop terminates the background sweeper. Safe to call multiple times.
func (l *LoginRateLimiter) Stop() {
	select {
	case <-l.stopCh:
	default:
		close(l.stopCh)
	}
}

// Check reports whether the key is currently locked out. Read-only; uses
// the same mutex as the writers since the cost is negligible.
func (l *LoginRateLimiter) Check(key string) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.checkLocked(key)
}

func (l *LoginRateLimiter) checkLocked(key string) error {
	attempt, exists := l.attempts[key]
	if !exists {
		return nil
	}
	if attempt.lockedAt != nil && time.Since(*attempt.lockedAt) < l.lockoutTime {
		return ErrTooManyAttempts
	}
	return nil
}

// RecordFailure atomically increments the failure counter for the key, rolling
// over the window if it has elapsed and engaging the lockout when the threshold
// is reached.
func (l *LoginRateLimiter) RecordFailure(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	attempt, exists := l.attempts[key]
	if !exists {
		attempt = &loginAttempt{lastReset: time.Now()}
		l.attempts[key] = attempt
	}

	if time.Since(attempt.lastReset) > l.lockoutTime {
		attempt.count = 0
		attempt.lockedAt = nil
		attempt.lastReset = time.Now()
	}

	attempt.count++
	if attempt.count >= l.maxAttempts {
		now := time.Now()
		attempt.lockedAt = &now
	}
}

// RecordSuccess clears the key's counter after a verified successful login.
func (l *LoginRateLimiter) RecordSuccess(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.attempts, key)
}

// sweepLoop periodically purges entries whose last activity is well past the
// lockout window, preventing unbounded map growth.
func (l *LoginRateLimiter) sweepLoop() {
	ticker := time.NewTicker(l.lockoutTime)
	defer ticker.Stop()

	for {
		select {
		case <-l.stopCh:
			return
		case <-ticker.C:
			l.sweep()
		}
	}
}

func (l *LoginRateLimiter) sweep() {
	cutoff := time.Now().Add(-2 * l.lockoutTime)
	l.mu.Lock()
	defer l.mu.Unlock()
	for key, a := range l.attempts {
		// Latest activity timestamp: prefer lockedAt, fall back to lastReset.
		last := a.lastReset
		if a.lockedAt != nil && a.lockedAt.After(last) {
			last = *a.lockedAt
		}
		if last.Before(cutoff) {
			delete(l.attempts, key)
		}
	}
}

// ValidatePasswordStrength checks if a password meets minimum requirements
func ValidatePasswordStrength(password string) error {
	if len(password) < 8 {
		return fmt.Errorf("%w: password must be at least 8 characters", ErrWeakPassword)
	}

	var hasNumber, hasLetter bool
	for _, c := range password {
		if unicode.IsDigit(c) {
			hasNumber = true
		}
		if unicode.IsLetter(c) {
			hasLetter = true
		}
	}

	if !hasNumber {
		return fmt.Errorf("%w: password must contain at least one number", ErrWeakPassword)
	}
	if !hasLetter {
		return fmt.Errorf("%w: password must contain at least one letter", ErrWeakPassword)
	}

	return nil
}

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
	return s.registerUser(s.db, username, password, email, false)
}

// RegisterFirstSuperAdmin creates the first user as a super admin and then closes public registration.
func (s *AuthService) RegisterFirstSuperAdmin(username, password, email string) (*database.User, error) {
	s.bootstrapMu.Lock()
	defer s.bootstrapMu.Unlock()

	var created *database.User
	err := s.db.Transaction(func(tx *gorm.DB) error {
		var count int64
		if err := tx.Model(&database.User{}).Count(&count).Error; err != nil {
			return fmt.Errorf("database error: %w", err)
		}
		if count > 0 {
			return ErrRegistrationClosed
		}

		user, err := s.registerUser(tx, username, password, email, true)
		if err != nil {
			return err
		}
		if err := tx.Model(&database.User{}).Count(&count).Error; err != nil {
			return fmt.Errorf("database error: %w", err)
		}
		if count != 1 {
			return ErrRegistrationClosed
		}
		created = user
		return nil
	})
	if err != nil {
		return nil, err
	}
	return created, nil
}

func (s *AuthService) registerUser(db *gorm.DB, username, password, email string, isSuperAdmin bool) (*database.User, error) {
	// Validate password strength
	if err := ValidatePasswordStrength(password); err != nil {
		return nil, err
	}

	// Check if user exists
	var existing database.User
	if err := db.Where("username = ?", username).First(&existing).Error; err == nil {
		return nil, ErrUserExists
	}
	if email != "" {
		if err := db.Where("email = ?", email).First(&existing).Error; err == nil {
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
		IsSuperAdmin: isSuperAdmin,
	}

	if err := db.Create(user).Error; err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	s.logger.Infof("User '%s' registered successfully (super_admin=%v)", username, isSuperAdmin)
	return user, nil
}

// LoginUser authenticates a user and returns a JWT token.
//
// remoteIP is included in rate-limiting so that a single attacker cannot bypass
// per-username throttling by trying many usernames from the same host. Pass an
// empty string only when no IP context is available (tests, internal calls);
// production callers should always supply c.ClientIP().
func (s *AuthService) LoginUser(username, password, remoteIP string) (string, *database.User, error) {
	userKey := "user:" + username
	ipKey := ""
	if remoteIP != "" {
		ipKey = "ip:" + remoteIP
	}

	// Check both buckets up front. We use the same threshold for both — if you
	// burn 5 attempts on one username OR 5 from one IP across different
	// usernames, you get locked out.
	if err := s.loginLimiter.Check(userKey); err != nil {
		s.logger.Warnf("Login blocked for user '%s': too many attempts", username)
		return "", nil, err
	}
	if ipKey != "" {
		if err := s.loginLimiter.Check(ipKey); err != nil {
			s.logger.Warnf("Login blocked for IP %s (user='%s'): too many attempts", remoteIP, username)
			return "", nil, err
		}
	}

	recordFailure := func() {
		s.loginLimiter.RecordFailure(userKey)
		if ipKey != "" {
			s.loginLimiter.RecordFailure(ipKey)
		}
	}

	var user database.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			recordFailure()
			return "", nil, ErrUserNotFound
		}
		return "", nil, fmt.Errorf("database error: %w", err)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		recordFailure()
		return "", nil, ErrInvalidPassword
	}

	// Clear only the username bucket on success: we don't want a successful
	// login to wipe out evidence of credential stuffing from this IP across
	// other accounts.
	s.loginLimiter.RecordSuccess(userKey)

	token, err := s.GenerateToken(&user)
	if err != nil {
		return "", nil, fmt.Errorf("failed to generate token: %w", err)
	}

	s.logger.Infof("User '%s' logged in successfully from %s", username, remoteIP)
	return token, &user, nil
}

// GenerateToken generates a JWT token for a user
func (s *AuthService) GenerateToken(user *database.User) (string, error) {
	now := time.Now()
	claims := JWTClaims{
		UserID:       user.ID,
		Username:     user.Username,
		IsSuperAdmin: user.IsSuperAdmin,
		TokenVersion: user.TokenVersion,
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

// DeleteUser deletes a user by ID.
//
// Wrapped in a single transaction so that a partial failure (e.g. the user row
// deletes but the user_groups cleanup errors) cannot leave orphan rows in the
// join tables. Without this, callers could end up with permission grants
// pointing at a non-existent user, which would surface later as confusing
// authorization bugs.
func (s *AuthService) DeleteUser(userID uint) error {
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("DELETE FROM user_groups WHERE user_id = ?", userID).Error; err != nil {
			return fmt.Errorf("failed to remove user from groups: %w", err)
		}
		if err := tx.Where("user_id = ?", userID).Delete(&database.UserAgentPermission{}).Error; err != nil {
			return fmt.Errorf("failed to delete user permissions: %w", err)
		}
		if err := tx.Delete(&database.User{}, userID).Error; err != nil {
			return fmt.Errorf("failed to delete user: %w", err)
		}
		return nil
	})
	if err != nil {
		return err
	}

	s.logger.Infof("User ID %d deleted", userID)
	return nil
}

// UpdatePassword updates a user's password.
//
// Bumps token_version atomically so every JWT that was issued before this call is
// rejected by the auth middleware on its next request — see JWTClaims.TokenVersion.
// Also enforces password strength on every code path (admin reset, self-change, etc.)
// instead of trusting the handler layer.
func (s *AuthService) UpdatePassword(userID uint, newPassword string) error {
	if err := ValidatePasswordStrength(newPassword); err != nil {
		return err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("failed to hash password: %w", err)
	}

	updates := map[string]interface{}{
		"password_hash": string(hash),
		"token_version": gorm.Expr("token_version + ?", 1),
	}
	if err := s.db.Model(&database.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to update password: %w", err)
	}

	return nil
}

// Register is an alias for RegisterUser
func (s *AuthService) Register(username, password, email string) (*database.User, error) {
	return s.RegisterUser(username, password, email)
}

// VerifyPassword verifies a user's password
func (s *AuthService) VerifyPassword(userID uint, password string) error {
	var user database.User
	if err := s.db.First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return fmt.Errorf("database error: %w", err)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return ErrInvalidPassword
	}

	return nil
}

// ChangePassword is an alias for UpdatePassword
func (s *AuthService) ChangePassword(userID uint, newPassword string) error {
	return s.UpdatePassword(userID, newPassword)
}

// TokenTTL returns the configured JWT lifetime.
func (s *AuthService) TokenTTL() time.Duration {
	return s.jwtExpire
}
