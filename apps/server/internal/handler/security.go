package handler

import (
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const AuthCookieName = "nanolink_session"

// ExtractRequestToken returns the bearer token from the Authorization header or auth cookie.
func ExtractRequestToken(c *gin.Context) (string, bool) {
	return ExtractTokenFromHTTPRequest(c.Request)
}

// ExtractTokenFromHTTPRequest returns the bearer token from the Authorization header or auth cookie.
func ExtractTokenFromHTTPRequest(r *http.Request) (string, bool) {
	if token, ok := extractBearerToken(r.Header.Get("Authorization")); ok {
		return token, true
	}

	cookie, err := r.Cookie(AuthCookieName)
	if err != nil || cookie.Value == "" {
		return "", false
	}

	return cookie.Value, true
}

// SetAuthCookie stores the current session token in a secure HttpOnly cookie.
func SetAuthCookie(c *gin.Context, token string, ttl time.Duration) {
	http.SetCookie(c.Writer, &http.Cookie{
		Name:     AuthCookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   isSecureRequest(c.Request),
		SameSite: http.SameSiteLaxMode,
		MaxAge:   int(ttl.Seconds()),
	})
}

// ClearAuthCookie removes the current auth cookie.
func ClearAuthCookie(c *gin.Context) {
	http.SetCookie(c.Writer, &http.Cookie{
		Name:     AuthCookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Secure:   isSecureRequest(c.Request),
		SameSite: http.SameSiteLaxMode,
		MaxAge:   -1,
		Expires:  time.Unix(0, 0),
	})
}

// ApplyCORSHeaders applies strict CORS rules based on the configured origin allowlist.
func ApplyCORSHeaders(c *gin.Context, allowedOrigins []string) {
	origin := c.GetHeader("Origin")
	if origin == "" {
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
		}
		return
	}

	if !IsOriginAllowed(c.Request, allowedOrigins) {
		c.AbortWithStatus(http.StatusForbidden)
		return
	}

	c.Header("Vary", "Origin")
	c.Header("Access-Control-Allow-Origin", origin)
	c.Header("Access-Control-Allow-Credentials", "true")
	c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
	c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")

	if c.Request.Method == http.MethodOptions {
		c.AbortWithStatus(http.StatusNoContent)
	}
}

// IsOriginAllowed checks whether the request Origin header is allowed.
func IsOriginAllowed(r *http.Request, allowedOrigins []string) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}

	normalizedOrigin := strings.TrimRight(origin, "/")
	if sameOrigin(normalizedOrigin, r) {
		return true
	}

	for _, allowedOrigin := range allowedOrigins {
		normalizedAllowed := strings.TrimRight(strings.TrimSpace(allowedOrigin), "/")
		if normalizedAllowed == "" {
			continue
		}
		if normalizedAllowed == "*" || strings.EqualFold(normalizedAllowed, normalizedOrigin) {
			return true
		}
	}

	return false
}

func extractBearerToken(header string) (string, bool) {
	parts := strings.SplitN(strings.TrimSpace(header), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") || parts[1] == "" {
		return "", false
	}
	return parts[1], true
}

func sameOrigin(origin string, r *http.Request) bool {
	parsedOrigin, err := url.Parse(origin)
	if err != nil {
		return false
	}

	return strings.EqualFold(parsedOrigin.Scheme, requestScheme(r)) &&
		strings.EqualFold(parsedOrigin.Host, r.Host)
}

func requestScheme(r *http.Request) string {
	switch {
	case r.TLS != nil:
		return "https"
	case strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https"):
		return "https"
	case strings.EqualFold(r.Header.Get("X-Forwarded-Ssl"), "on"):
		return "https"
	default:
		return "http"
	}
}

func isSecureRequest(r *http.Request) bool {
	return requestScheme(r) == "https"
}
