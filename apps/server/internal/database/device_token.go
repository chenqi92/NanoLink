package database

import (
	"time"

	"gorm.io/gorm"
)

// DeviceToken represents a device authentication token for mobile/desktop clients
type DeviceToken struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	Token           string         `gorm:"uniqueIndex;size:128;not null" json:"-"` // stored hashed-at-rest (see HashToken)
	DeviceName      string         `gorm:"size:100" json:"deviceName"`
	DeviceType      string         `gorm:"size:20" json:"deviceType"` // mobile/desktop/tablet
	DeviceOS        string         `gorm:"size:50" json:"deviceOs"`   // iOS/Android/macOS/Windows/Linux
	PermissionLevel int            `gorm:"default:0" json:"permissionLevel"`
	IsActive        bool           `gorm:"default:true" json:"isActive"`

	// Pairing code redemption: a short-lived 6-digit code that a client can
	// exchange for the real device token when QR scanning is not possible.
	PairingCode        string     `gorm:"index;size:16" json:"-"`
	PairingCodeExpires *time.Time `json:"-"`
	PairingRedeemed    bool       `gorm:"default:false" json:"-"`

	LastUsedAt *time.Time `json:"lastUsedAt"`
	LastIP          string         `gorm:"size:50" json:"lastIp"`
	CreatedBy       uint           `gorm:"index;not null" json:"createdBy"`
	CreatedAt       time.Time      `json:"createdAt"`
	UpdatedAt       time.Time      `json:"updatedAt"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Creator User `gorm:"foreignKey:CreatedBy" json:"creator,omitempty"`
}

// TableName returns the table name for DeviceToken
func (DeviceToken) TableName() string {
	return "device_tokens"
}

// DeviceTokenResponse is the API response format for device tokens
type DeviceTokenResponse struct {
	ID              uint       `json:"id"`
	DeviceName      string     `json:"deviceName"`
	DeviceType      string     `json:"deviceType"`
	DeviceOS        string     `json:"deviceOs"`
	PermissionLevel int        `json:"permissionLevel"`
	IsActive        bool       `json:"isActive"`
	LastUsedAt      *time.Time `json:"lastUsedAt"`
	LastIP          string     `json:"lastIp"`
	CreatedBy       uint       `json:"createdBy"`
	CreatorName     string     `json:"creatorName,omitempty"`
	CreatedAt       time.Time  `json:"createdAt"`
}

// ToResponse converts DeviceToken to API response format
func (d *DeviceToken) ToResponse() DeviceTokenResponse {
	resp := DeviceTokenResponse{
		ID:              d.ID,
		DeviceName:      d.DeviceName,
		DeviceType:      d.DeviceType,
		DeviceOS:        d.DeviceOS,
		PermissionLevel: d.PermissionLevel,
		IsActive:        d.IsActive,
		LastUsedAt:      d.LastUsedAt,
		LastIP:          d.LastIP,
		CreatedBy:       d.CreatedBy,
		CreatedAt:       d.CreatedAt,
	}
	if d.Creator.ID != 0 {
		resp.CreatorName = d.Creator.Username
	}
	return resp
}
