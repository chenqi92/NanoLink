package handler

import (
	"errors"
	"net/http"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
)

const (
	// Context keys
	ContextKeyUser         = "user"
	ContextKeyClaims       = "claims"
	ContextKeyUserID       = "userID"
	ContextKeyUsername     = "username"
	ContextKeyIsSuperAdmin = "isSuperAdmin"
	ContextKeyDeviceID     = "deviceID"
	ContextKeyDeviceLevel  = "devicePermissionLevel"
)

// AuthMiddleware creates a JWT authentication middleware
func AuthMiddleware(authService *service.AuthService) gin.HandlerFunc {
	return AuthMiddlewareWithDevices(authService, nil)
}

// AuthMiddlewareWithDevices accepts both account JWTs and persistent device
// tokens. Device tokens are mapped to their creator for visibility checks, but
// their own permission level is stored in the request context and must cap every
// agent operation. Account-only/admin middleware below explicitly rejects device
// sessions, even when the token was created by a super admin.
func AuthMiddlewareWithDevices(authService *service.AuthService, deviceService *service.DeviceService) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString, ok := ExtractRequestToken(c)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			c.Abort()
			return
		}

		// Prefer an account JWT. A raw device token is deliberately opaque and will
		// fail JWT verification before being checked against its hashed DB record.
		claims, err := authService.VerifyToken(tokenString)
		if err == nil {
			user, userErr := authService.GetUserByID(claims.UserID)
			if userErr != nil {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
				c.Abort()
				return
			}

			// Reject tokens whose version is older than the user's current version.
			if claims.TokenVersion != user.TokenVersion {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "token revoked, please log in again"})
				c.Abort()
				return
			}

			setAuthenticatedUser(c, user, claims)
			c.Next()
			return
		}

		if deviceService != nil {
			device, deviceErr := deviceService.ValidateDeviceToken(tokenString)
			if deviceErr == nil {
				user, userErr := authService.GetUserByID(device.CreatedBy)
				if userErr != nil {
					c.JSON(http.StatusUnauthorized, gin.H{"error": "device owner not found"})
					c.Abort()
					return
				}
				setAuthenticatedUser(c, user, nil)
				c.Set(ContextKeyDeviceID, device.ID)
				c.Set(ContextKeyDeviceLevel, device.PermissionLevel)
				// A device session is never itself a super-admin session.
				c.Set(ContextKeyIsSuperAdmin, false)
				c.Next()
				return
			}
			if errors.Is(deviceErr, service.ErrDeviceDisabled) {
				c.JSON(http.StatusForbidden, gin.H{"error": "device is disabled"})
				c.Abort()
				return
			}
		}

		errMsg := "invalid token"
		if errors.Is(err, service.ErrTokenExpired) {
			errMsg = "token expired"
		}
		c.JSON(http.StatusUnauthorized, gin.H{"error": errMsg})
		c.Abort()
	}
}

func setAuthenticatedUser(c *gin.Context, user *database.User, claims *service.JWTClaims) {
	c.Set(ContextKeyUser, user)
	if claims != nil {
		c.Set(ContextKeyClaims, claims)
	}
	c.Set(ContextKeyUserID, user.ID)
	c.Set(ContextKeyUsername, user.Username)
	c.Set(ContextKeyIsSuperAdmin, user.IsSuperAdmin)
}

// OptionalAuthMiddleware creates an optional JWT authentication middleware
// This allows both authenticated and unauthenticated access.
//
// Distinction: a missing token means "anonymous" and is allowed through. But a
// token that is *present yet invalid/expired/revoked* is rejected with 401 rather
// than being silently downgraded to anonymous — a tampered or stale credential is a
// signal, not an absence of credentials.
func OptionalAuthMiddleware(authService *service.AuthService) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString, ok := ExtractRequestToken(c)
		if !ok {
			// No credential presented: proceed as anonymous.
			c.Next()
			return
		}

		claims, err := authService.VerifyToken(tokenString)
		if err != nil {
			errMsg := "invalid token"
			if err == service.ErrTokenExpired {
				errMsg = "token expired"
			}
			c.JSON(http.StatusUnauthorized, gin.H{"error": errMsg})
			c.Abort()
			return
		}

		user, err := authService.GetUserByID(claims.UserID)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			c.Abort()
			return
		}

		// Same revocation check as AuthMiddleware: a presented-but-revoked token is
		// rejected rather than downgraded to anonymous.
		if claims.TokenVersion != user.TokenVersion {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "token revoked, please log in again"})
			c.Abort()
			return
		}

		c.Set(ContextKeyUser, user)
		c.Set(ContextKeyClaims, claims)
		c.Set(ContextKeyUserID, user.ID)
		c.Set(ContextKeyUsername, user.Username)
		c.Set(ContextKeyIsSuperAdmin, user.IsSuperAdmin)
		c.Next()
	}
}

// RequireSuperAdmin creates a middleware that requires super admin access
func RequireSuperAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		if IsDeviceSession(c) {
			c.JSON(http.StatusForbidden, gin.H{"error": "account session required"})
			c.Abort()
			return
		}
		user, exists := c.Get(ContextKeyUser)
		if !exists {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			c.Abort()
			return
		}

		u, ok := user.(*database.User)
		if !ok || !u.IsSuperAdmin {
			c.JSON(http.StatusForbidden, gin.H{"error": "super admin access required"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// RequireAgentPermission creates a middleware that checks if user has required permission for an agent
func RequireAgentPermission(permService *service.PermissionService, minLevel int) gin.HandlerFunc {
	return func(c *gin.Context) {
		user, exists := c.Get(ContextKeyUser)
		if !exists {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			c.Abort()
			return
		}

		u, ok := user.(*database.User)
		if !ok {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid user context"})
			c.Abort()
			return
		}

		if level, isDevice := GetCurrentDevicePermission(c); isDevice && level < minLevel {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "insufficient device permissions",
				"requiredLevel": database.PermissionLevelName(minLevel),
			})
			c.Abort()
			return
		}

		// Super admin bypasses permission check
		if u.IsSuperAdmin {
			c.Next()
			return
		}

		// Get agent ID from path parameter
		agentID := c.Param("id")
		if agentID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "agent ID required"})
			c.Abort()
			return
		}

		// Check permission
		canExecute, err := permService.CanUserExecuteCommand(u.ID, agentID, minLevel)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "permission check failed"})
			c.Abort()
			return
		}

		if !canExecute {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "insufficient permissions",
				"requiredLevel": database.PermissionLevelName(minLevel),
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// RequireAccountSession blocks persistent device credentials from account and
// credential-management endpoints. Normal JWT sessions pass through unchanged.
func RequireAccountSession() gin.HandlerFunc {
	return func(c *gin.Context) {
		if IsDeviceSession(c) {
			c.JSON(http.StatusForbidden, gin.H{"error": "account session required"})
			c.Abort()
			return
		}
		c.Next()
	}
}

// RequireSessionPermission applies only to device sessions. Account sessions
// retain their existing route authorization, while device sessions must meet
// the configured device-level cap.
func RequireSessionPermission(minLevel int) gin.HandlerFunc {
	return func(c *gin.Context) {
		if level, isDevice := GetCurrentDevicePermission(c); isDevice && level < minLevel {
			c.JSON(http.StatusForbidden, gin.H{
				"error":         "insufficient device permissions",
				"requiredLevel": database.PermissionLevelName(minLevel),
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

func IsDeviceSession(c *gin.Context) bool {
	_, exists := c.Get(ContextKeyDeviceID)
	return exists
}

func GetCurrentDevicePermission(c *gin.Context) (int, bool) {
	level, exists := c.Get(ContextKeyDeviceLevel)
	if !exists {
		return 0, false
	}
	value, ok := level.(int)
	return value, ok
}

func capPermissionForRequest(c *gin.Context, permission int) int {
	if deviceLevel, isDevice := GetCurrentDevicePermission(c); isDevice && permission > deviceLevel {
		return deviceLevel
	}
	return permission
}

// GetCurrentUser returns the current authenticated user from context
func GetCurrentUser(c *gin.Context) *database.User {
	user, exists := c.Get(ContextKeyUser)
	if !exists {
		return nil
	}
	u, ok := user.(*database.User)
	if !ok {
		return nil
	}
	return u
}

// GetCurrentClaims returns the current JWT claims from context
func GetCurrentClaims(c *gin.Context) *service.JWTClaims {
	claims, exists := c.Get(ContextKeyClaims)
	if !exists {
		return nil
	}
	c_, ok := claims.(*service.JWTClaims)
	if !ok {
		return nil
	}
	return c_
}
