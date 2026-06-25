package service

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
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

// generatePairingCode creates a 6-digit numeric pairing code
func generatePairingCode() string {
	bytes := make([]byte, 3)
	_, _ = rand.Read(bytes)
	// Convert to 6-digit number (0-999999)
	num := (int(bytes[0])<<16 | int(bytes[1])<<8 | int(bytes[2])) % 1000000
	return fmt.Sprintf("%06d", num)
}

// trimPairingCode normalizes a user-supplied pairing code (strips surrounding
// whitespace) so lookups match the stored value.
func trimPairingCode(code string) string {
	return strings.TrimSpace(code)
}

// pairingCodeTTL is how long a generated pairing code remains redeemable.
const pairingCodeTTL = 15 * time.Minute

// qrTokenTTL is how long a generated QR/pairing offer is advertised as valid to
// the client. It mirrors pairingCodeTTL so the QR and the manual code expire in
// lockstep.
const qrTokenTTL = pairingCodeTTL

// normalizePermissionLevel clamps a requested permission level into the valid
// range, falling back to read-only for out-of-range values.
func normalizePermissionLevel(level int) int {
	if level < database.PermissionReadOnly || level > database.PermissionSystemAdmin {
		return database.PermissionReadOnly
	}
	return level
}

// CreateDeviceToken generates a new device token. permissionLevel is the maximum
// permission the paired client will be granted; pass database.PermissionReadOnly
// for the default least-privilege behavior. Out-of-range values are clamped to
// read-only.
func (s *DeviceService) CreateDeviceToken(createdBy uint, serverName string, permissionLevel int) (*GenerateTokenResult, *database.DeviceToken, error) {
	token, err := generateSecureToken()
	if err != nil {
		return nil, nil, err
	}

	// Generate the manual pairing code before persisting so it can be stored
	// alongside the token and later redeemed by a client.
	pairingCode := generatePairingCode()
	now := time.Now()
	pairingExpires := now.Add(pairingCodeTTL)

	deviceToken := &database.DeviceToken{
		Token:              database.HashToken(token),
		DeviceName:         "Pending Connection",
		DeviceType:         "unknown",
		DeviceOS:           "unknown",
		PermissionLevel:    normalizePermissionLevel(permissionLevel),
		IsActive:           true,
		CreatedBy:          createdBy,
		PairingCode:        pairingCode,
		PairingCodeExpires: &pairingExpires,
		PairingRedeemed:    false,
	}

	if err := s.db.Create(deviceToken).Error; err != nil {
		return nil, nil, err
	}

	// Generate QR code data. ExpiresAt advertises how long the offer is valid so
	// a client can reject a stale QR before attempting to pair.
	qrData := QRCodeData{
		Version:    1,
		ServerURL:  s.serverURL,
		Token:      token,
		ServerName: serverName,
		ExpiresAt:  now.Add(qrTokenTTL).Unix(),
	}

	jsonData, err := json.Marshal(qrData)
	if err != nil {
		return nil, nil, err
	}

	result := &GenerateTokenResult{
		Token:       token,
		QRData:      base64.StdEncoding.EncodeToString(jsonData),
		PairingCode: pairingCode,
	}

	return result, deviceToken, nil
}

// RedeemPairingResult is returned to a client that successfully redeems a code.
type RedeemPairingResult struct {
	Token      string
	ServerURL  string
	ServerName string
}

// RedeemPairingCode exchanges a one-time pairing code for a fresh device token.
//
// The stored Token is hashed-at-rest, so the original plaintext cannot be
// recovered. Instead this rotates the token: a new secure token is generated,
// its hash replaces the stored value, the pairing code is consumed (marked
// redeemed and cleared), and the new plaintext token is returned. Codes are
// single-use and expire after pairingCodeTTL.
func (s *DeviceService) RedeemPairingCode(code, serverName string) (*RedeemPairingResult, error) {
	code = trimPairingCode(code)
	if code == "" {
		return nil, ErrInvalidDeviceToken
	}

	var deviceToken database.DeviceToken
	err := s.db.Where(
		"pairing_code = ? AND pairing_redeemed = ? AND is_active = ?",
		code, false, true,
	).First(&deviceToken).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrInvalidDeviceToken
		}
		return nil, err
	}

	// Reject expired codes.
	if deviceToken.PairingCodeExpires == nil || time.Now().After(*deviceToken.PairingCodeExpires) {
		return nil, ErrInvalidDeviceToken
	}

	// Rotate the token so the client receives a usable plaintext credential.
	newToken, err := generateSecureToken()
	if err != nil {
		return nil, err
	}

	updates := map[string]interface{}{
		"token":            database.HashToken(newToken),
		"pairing_redeemed": true,
		"pairing_code":     "",
	}
	if err := s.db.Model(&database.DeviceToken{}).Where("id = ?", deviceToken.ID).Updates(updates).Error; err != nil {
		return nil, err
	}

	return &RedeemPairingResult{
		Token:      newToken,
		ServerURL:  s.serverURL,
		ServerName: serverName,
	}, nil
}

// ValidateDeviceToken validates a device token and returns the device info
func (s *DeviceService) ValidateDeviceToken(token string) (*database.DeviceToken, error) {
	var deviceToken database.DeviceToken
	if err := s.db.Preload("Creator").Where("token = ?", database.HashToken(token)).First(&deviceToken).Error; err != nil {
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
