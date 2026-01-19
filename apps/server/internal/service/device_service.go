package service

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/google/uuid"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

var (
	ErrDeviceNotFound     = errors.New("device not found")
	ErrDeviceDisabled     = errors.New("device token is disabled")
	ErrInvalidDeviceToken = errors.New("invalid device token")
	ErrUnauthorized       = errors.New("unauthorized")
)

// DeviceService handles device token operations
type DeviceService struct {
	db        *gorm.DB
	logger    *zap.SugaredLogger
	serverURL string
}

// NewDeviceService creates a new device service
func NewDeviceService(db *gorm.DB, logger *zap.SugaredLogger, serverURL string) *DeviceService {
	return &DeviceService{
		db:        db,
		logger:    logger,
		serverURL: serverURL,
	}
}

// QRCodeData represents the data encoded in QR code
type QRCodeData struct {
	Version    int    `json:"v"`
	ServerURL  string `json:"s"`
	Token      string `json:"t"`
	ServerName string `json:"n,omitempty"`
	ExpiresAt  int64  `json:"e,omitempty"`
}

// GenerateTokenResult contains the generated token and QR data
type GenerateTokenResult struct {
	Token       string `json:"token"`
	QRData      string `json:"qrData"`      // Base64 encoded JSON
	PairingCode string `json:"pairingCode"` // 6-digit code for manual entry
}

// generateSecureToken creates a cryptographically secure token
func generateSecureToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

// generatePairingCode creates an 8-character pairing code
func generatePairingCode() string {
	return uuid.New().String()[:8] // Use first 8 chars of UUID
}

// CreateDeviceToken generates a new device token
func (s *DeviceService) CreateDeviceToken(createdBy uint, serverName string) (*GenerateTokenResult, *database.DeviceToken, error) {
	token, err := generateSecureToken()
	if err != nil {
		return nil, nil, err
	}

	deviceToken := &database.DeviceToken{
		Token:           token,
		DeviceName:      "Pending Connection",
		DeviceType:      "unknown",
		DeviceOS:        "unknown",
		PermissionLevel: database.PermissionReadOnly,
		IsActive:        true,
		CreatedBy:       createdBy,
	}

	if err := s.db.Create(deviceToken).Error; err != nil {
		return nil, nil, err
	}

	// Generate QR code data
	qrData := QRCodeData{
		Version:    1,
		ServerURL:  s.serverURL,
		Token:      token,
		ServerName: serverName,
	}

	jsonData, err := json.Marshal(qrData)
	if err != nil {
		return nil, nil, err
	}

	result := &GenerateTokenResult{
		Token:       token,
		QRData:      base64.StdEncoding.EncodeToString(jsonData),
		PairingCode: generatePairingCode(),
	}

	return result, deviceToken, nil
}

// ValidateDeviceToken validates a device token and returns the device info
func (s *DeviceService) ValidateDeviceToken(token string) (*database.DeviceToken, error) {
	var deviceToken database.DeviceToken
	if err := s.db.Preload("Creator").Where("token = ?", token).First(&deviceToken).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrInvalidDeviceToken
		}
		return nil, err
	}

	if !deviceToken.IsActive {
		return nil, ErrDeviceDisabled
	}

	// Update last used time
	now := time.Now()
	s.db.Model(&deviceToken).Updates(map[string]interface{}{
		"last_used_at": now,
	})

	return &deviceToken, nil
}

// UpdateDeviceInfo updates device information after successful auth
func (s *DeviceService) UpdateDeviceInfo(tokenID uint, deviceName, deviceType, deviceOS, ip string) error {
	updates := map[string]interface{}{
		"device_name":  deviceName,
		"device_type":  deviceType,
		"device_os":    deviceOS,
		"last_ip":      ip,
		"last_used_at": time.Now(),
	}
	return s.db.Model(&database.DeviceToken{}).Where("id = ?", tokenID).Updates(updates).Error
}

// ListDevices returns all devices for a user (or all for super admin)
func (s *DeviceService) ListDevices(userID uint, isSuperAdmin bool) ([]database.DeviceToken, error) {
	var devices []database.DeviceToken
	query := s.db.Preload("Creator")

	if !isSuperAdmin {
		query = query.Where("created_by = ?", userID)
	}

	if err := query.Order("created_at DESC").Find(&devices).Error; err != nil {
		return nil, err
	}
	return devices, nil
}

// GetDevice returns a single device by ID
func (s *DeviceService) GetDevice(id uint) (*database.DeviceToken, error) {
	var device database.DeviceToken
	if err := s.db.Preload("Creator").First(&device, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrDeviceNotFound
		}
		return nil, err
	}
	return &device, nil
}

// UpdateDevice updates device settings
func (s *DeviceService) UpdateDevice(id uint, updates map[string]interface{}) error {
	result := s.db.Model(&database.DeviceToken{}).Where("id = ?", id).Updates(updates)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrDeviceNotFound
	}
	return nil
}

// DeleteDevice soft-deletes a device token
func (s *DeviceService) DeleteDevice(id uint) error {
	result := s.db.Delete(&database.DeviceToken{}, id)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrDeviceNotFound
	}
	return nil
}

// CheckDeviceOwnership checks if user owns the device or is super admin
func (s *DeviceService) CheckDeviceOwnership(deviceID, userID uint, isSuperAdmin bool) error {
	if isSuperAdmin {
		return nil
	}

	var device database.DeviceToken
	if err := s.db.First(&device, deviceID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrDeviceNotFound
		}
		return err
	}

	if device.CreatedBy != userID {
		return ErrUnauthorized
	}
	return nil
}
