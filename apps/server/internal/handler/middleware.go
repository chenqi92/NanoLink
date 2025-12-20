package handler

import (
	"net/http"
	"strings"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
)

const (
	// Context keys
	ContextKeyUser   = "user"
	ContextKeyClaims = "claims"
)

// AuthMiddleware creates a JWT authentication middleware
func AuthMiddleware(authService *service.AuthService) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get token from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "missing authorization header"})
			c.Abort()
			return
		}

		// Check Bearer token format
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid authorization header format"})
			c.Abort()
			return
		}

		tokenString := parts[1]

		// Verify token
		claims, err := authService.VerifyToken(tokenString)
		if err != nil {
			statusCode := http.StatusUnauthorized
			errMsg := "invalid token"
			if err == service.ErrTokenExpired {
				errMsg = "token expired"
			}
			c.JSON(statusCode, gin.H{"error": errMsg})
			c.Abort()
			return
		}

		// Get user from database
		user, err := authService.GetUserByID(claims.UserID)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			c.Abort()
			return
		}

		// Store user and claims in context
		c.Set(ContextKeyUser, user)
		c.Set(ContextKeyClaims, claims)
		c.Next()
	}
}

// OptionalAuthMiddleware creates an optional JWT authentication middleware
// This allows both authenticated and unauthenticated access
func OptionalAuthMiddleware(authService *service.AuthService) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.Next()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.Next()
			return
		}

		claims, err := authService.VerifyToken(parts[1])
		if err != nil {
			c.Next()
			return
		}

		user, err := authService.GetUserByID(claims.UserID)
		if err != nil {
			c.Next()
			return
		}

		c.Set(ContextKeyUser, user)
		c.Set(ContextKeyClaims, claims)
		c.Next()
	}
}

// RequireSuperAdmin creates a middleware that requires super admin access
func RequireSuperAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
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
