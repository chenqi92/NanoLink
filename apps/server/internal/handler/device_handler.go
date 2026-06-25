package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// DeviceHandler handles device management API requests
type DeviceHandler struct {
	deviceService  *service.DeviceService
	logger         *zap.SugaredLogger
	serverName     string
	pairingLimiter *service.LoginRateLimiter
}

// NewDeviceHandler creates a new device handler
func NewDeviceHandler(deviceService *service.DeviceService, logger *zap.SugaredLogger, serverName string) *DeviceHandler {
	return &DeviceHandler{
		deviceService:  deviceService,
		logger:         logger,
		serverName:     serverName,
		pairingLimiter: service.NewLoginRateLimiter(5, 5*time.Minute), // 5 attempts / 5 min lockout per IP
	}
}

// GenerateTokenRequest represents the request to generate a new device token.
// PermissionLevel is optional (0-3); when omitted the device defaults to
// read-only (least privilege).
type GenerateTokenRequest struct {
	ServerName      string `json:"serverName"`
	PermissionLevel *int   `json:"permissionLevel"`
}

// GenerateToken creates a new device token with QR code data
func (h *DeviceHandler) GenerateToken(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	var req GenerateTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Use default server name if not provided
		req.ServerName = h.serverName
	}
	if req.ServerName == "" {
		req.ServerName = h.serverName
	}

	// Default to least privilege; a granted level above read-only requires the
	// caller to be a super admin (mirrors UpdateDevice's permission gate).
	permissionLevel := database.PermissionReadOnly
	if req.PermissionLevel != nil {
		if *req.PermissionLevel < database.PermissionReadOnly || *req.PermissionLevel > database.PermissionSystemAdmin {
			c.JSON(http.StatusBadRequest, gin.H{"error": "permission level must be 0-3"})
			return
		}
		if *req.PermissionLevel > database.PermissionReadOnly && !user.IsSuperAdmin {
			c.JSON(http.StatusForbidden, gin.H{"error": "only super admin can grant elevated permission level"})
			return
		}
		permissionLevel = *req.PermissionLevel
	}

	result, device, err := h.deviceService.CreateDeviceToken(user.ID, req.ServerName, permissionLevel)
	if err != nil {
		h.logger.Errorf("Failed to generate device token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"qrData":          result.QRData,
		"pairingCode":     result.PairingCode,
		"permissionLevel": device.PermissionLevel,
		"device":          device.ToResponse(),
	})
}

// ListDevices returns all devices for the current user (or all for super admin)
func (h *DeviceHandler) ListDevices(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	devices, err := h.deviceService.ListDevices(user.ID, user.IsSuperAdmin)
	if err != nil {
		h.logger.Errorf("Failed to list devices: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list devices"})
		return
	}

	// Convert to response format
	result := make([]database.DeviceTokenResponse, len(devices))
	for i, d := range devices {
		result[i] = d.ToResponse()
	}

	c.JSON(http.StatusOK, result)
}

// GetDevice returns a single device by ID
func (h *DeviceHandler) GetDevice(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device id"})
		return
	}

	// Check ownership
	if err := h.deviceService.CheckDeviceOwnership(uint(id), user.ID, user.IsSuperAdmin); err != nil {
		if err == service.ErrDeviceNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "device not found"})
		} else if err == service.ErrUnauthorized {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch device"})
		}
		return
	}

	device, err := h.deviceService.GetDevice(uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get device: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch device"})
		return
	}

	c.JSON(http.StatusOK, device.ToResponse())
}

// UpdateDeviceRequest represents the request to update a device
type UpdateDeviceRequest struct {
	DeviceName      *string `json:"deviceName"`
	PermissionLevel *int    `json:"permissionLevel"`
	IsActive        *bool   `json:"isActive"`
}

// UpdateDevice updates a device's settings
func (h *DeviceHandler) UpdateDevice(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device id"})
		return
	}

	var req UpdateDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check ownership (only owner can update name, only super admin can change permissions)
	if err := h.deviceService.CheckDeviceOwnership(uint(id), user.ID, user.IsSuperAdmin); err != nil {
		if err == service.ErrDeviceNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "device not found"})
		} else if err == service.ErrUnauthorized {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update device"})
		}
		return
	}

	// Only super admin can change permission level
	if req.PermissionLevel != nil && !user.IsSuperAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "only super admin can change permission level"})
		return
	}

	// Build updates map
	updates := make(map[string]interface{})
	if req.DeviceName != nil {
		updates["device_name"] = *req.DeviceName
	}
	if req.PermissionLevel != nil {
		if *req.PermissionLevel < 0 || *req.PermissionLevel > 3 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "permission level must be 0-3"})
			return
		}
		updates["permission_level"] = *req.PermissionLevel
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}

	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no fields to update"})
		return
	}

	if err := h.deviceService.UpdateDevice(uint(id), updates); err != nil {
		h.logger.Errorf("Failed to update device: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "device updated"})
}

// DeleteDevice removes a device token
func (h *DeviceHandler) DeleteDevice(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
		return
	}

	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device id"})
		return
	}

	// Check ownership
	if err := h.deviceService.CheckDeviceOwnership(uint(id), user.ID, user.IsSuperAdmin); err != nil {
		if err == service.ErrDeviceNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "device not found"})
		} else if err == service.ErrUnauthorized {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete device"})
		}
		return
	}

	if err := h.deviceService.DeleteDevice(uint(id)); err != nil {
		h.logger.Errorf("Failed to delete device: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "device deleted"})
}

// DeviceAuthRequest represents the request to authenticate with a device token
type DeviceAuthRequest struct {
	DeviceName string `json:"deviceName" binding:"required"`
	DeviceType string `json:"deviceType" binding:"required"`
	DeviceOS   string `json:"deviceOs" binding:"required"`
}

// AuthenticateDevice authenticates a device using its token
func (h *DeviceHandler) AuthenticateDevice(c *gin.Context) {
	token := c.GetHeader("X-Device-Token")
	if token == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "X-Device-Token header required"})
		return
	}

	var req DeviceAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	device, err := h.deviceService.ValidateDeviceToken(token)
	if err != nil {
		if err == service.ErrInvalidDeviceToken {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		} else if err == service.ErrDeviceDisabled {
			c.JSON(http.StatusForbidden, gin.H{"error": "device is disabled"})
		} else {
			h.logger.Errorf("Device auth failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "authentication failed"})
		}
		return
	}

	// Update device info
	clientIP := c.ClientIP()
	if err := h.deviceService.UpdateDeviceInfo(device.ID, req.DeviceName, req.DeviceType, req.DeviceOS, clientIP); err != nil {
		h.logger.Warnf("Failed to update device info: %v", err)
		// Continue anyway, auth was successful
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"device":  device.ToResponse(),
		"serverInfo": gin.H{
			"name":            h.serverName,
			"permissionLevel": device.PermissionLevel,
		},
	})
}

// RedeemPairingRequest is the body for exchanging a manual pairing code.
type RedeemPairingRequest struct {
	PairingCode string `json:"pairingCode" binding:"required"`
}

// RedeemPairingCode exchanges a one-time 6-digit pairing code for a device
// token. It mirrors the QR payload fields (token, serverUrl, serverName) so a
// client that cannot scan the QR can still finish pairing. Brute-force attempts
// are rate-limited per client IP.
func (h *DeviceHandler) RedeemPairingCode(c *gin.Context) {
	clientIP := c.ClientIP()

	// Per-IP brute-force protection: lock out after repeated failures.
	if h.pairingLimiter != nil {
		if err := h.pairingLimiter.Check(clientIP); err != nil {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many attempts, try again later"})
			return
		}
	}

	var req RedeemPairingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.deviceService.RedeemPairingCode(req.PairingCode, h.serverName)
	if err != nil {
		if h.pairingLimiter != nil {
			h.pairingLimiter.RecordFailure(clientIP)
		}
		if err == service.ErrInvalidDeviceToken {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired pairing code"})
			return
		}
		h.logger.Errorf("Failed to redeem pairing code: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to redeem pairing code"})
		return
	}

	if h.pairingLimiter != nil {
		h.pairingLimiter.RecordSuccess(clientIP)
	}

	c.JSON(http.StatusOK, gin.H{
		"token":      result.Token,
		"serverUrl":  result.ServerURL,
		"serverName": result.ServerName,
	})
}
