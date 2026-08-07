package handler

import (
	"crypto/subtle"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const AuthCookieName = "nanolink_session"

const defaultSecurityCSP = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"

// NewForwardedHeadersMiddleware removes proxy-supplied identity/scheme headers
// unless the direct peer belongs to the configured trusted proxy set. This
// protects code outside Gin's ClientIP implementation (cookie and origin
// handling in particular) from spoofed X-Forwarded-* headers.
func NewForwardedHeadersMiddleware(trustedProxies []string) (gin.HandlerFunc, error) {
	prefixes := make([]netip.Prefix, 0, len(trustedProxies))
	for _, raw := range trustedProxies {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		if strings.Contains(entry, "/") {
			prefix, err := netip.ParsePrefix(entry)
			if err != nil {
				return nil, fmt.Errorf("invalid trusted proxy %q: %w", entry, err)
			}
			prefixes = append(prefixes, prefix.Masked())
			continue
		}
		addr, err := netip.ParseAddr(entry)
		if err != nil {
			return nil, fmt.Errorf("invalid trusted proxy %q: %w", entry, err)
		}
		addr = addr.Unmap()
		prefixes = append(prefixes, netip.PrefixFrom(addr, addr.BitLen()))
	}

	return func(c *gin.Context) {
		peerHost, _, err := net.SplitHostPort(c.Request.RemoteAddr)
		if err != nil {
			peerHost = c.Request.RemoteAddr
		}
		peer, parseErr := netip.ParseAddr(strings.Trim(peerHost, "[]"))
		trusted := false
		if parseErr == nil {
			peer = peer.Unmap()
			for _, prefix := range prefixes {
				if prefix.Contains(peer) {
					trusted = true
					break
				}
			}
		}
		if !trusted {
			for _, header := range []string{
				"Forwarded",
				"X-Forwarded-For",
				"X-Forwarded-Host",
				"X-Forwarded-Proto",
				"X-Forwarded-Ssl",
				"X-Real-Ip",
			} {
				c.Request.Header.Del(header)
			}
		}
		c.Next()
	}, nil
}

// LimitRequestBody places a hard cap on API request bodies before a handler
// attempts JSON decoding. WebSocket handshakes and bodyless requests are
// unaffected.
func LimitRequestBody(maxBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if maxBytes > 0 && c.Request.Body != nil {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		}
		c.Next()
	}
}

// SecurityHeaders adds browser hardening headers to API and dashboard responses.
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Content-Security-Policy", defaultSecurityCSP)
		c.Header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		c.Header("Referrer-Policy", "no-referrer")
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		if isSecureRequest(c.Request) {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Next()
	}
}

// RequireBearerToken protects machine-consumed endpoints such as Prometheus
// without accepting browser cookies or query-string credentials.
func RequireBearerToken(expected string) gin.HandlerFunc {
	expectedBytes := []byte(expected)
	return func(c *gin.Context) {
		actual, ok := extractBearerToken(c.GetHeader("Authorization"))
		if !ok || len(actual) != len(expectedBytes) || subtle.ConstantTimeCompare([]byte(actual), expectedBytes) != 1 {
			c.Header("WWW-Authenticate", `Bearer realm="nanolink"`)
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Next()
	}
}

// ExtractRequestToken returns the bearer token from the Authorization header or auth cookie.
func ExtractRequestToken(c *gin.Context) (string, bool) {
	return ExtractTokenFromHTTPRequest(c.Request)
}

// ExtractTokenFromHTTPRequest returns the bearer token from the Authorization
// header or the HttpOnly auth cookie. Query-string credentials are deliberately
// rejected because URLs are routinely captured in access logs and telemetry.
func ExtractTokenFromHTTPRequest(r *http.Request) (string, bool) {
	if token, ok := extractBearerToken(r.Header.Get("Authorization")); ok {
		return token, true
	}

	if cookie, err := r.Cookie(AuthCookieName); err == nil && cookie.Value != "" {
		return cookie.Value, true
	}

	return "", false
}

// SetAuthCookie stores the current session token in a secure HttpOnly cookie.
func SetAuthCookie(c *gin.Context, token string, ttl time.Duration) {
	http.SetCookie(c.Writer, &http.Cookie{
		Name:     AuthCookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   isSecureRequest(c.Request),
		SameSite: http.SameSiteStrictMode,
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
		SameSite: http.SameSiteStrictMode,
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
//
// An empty Origin header is treated as "no browser context" (server-to-server,
// curl, native clients) and allowed: browser CSRF protection relies on the
// Origin header always being present in cross-origin browser requests, which
// it always is.
//
// Wildcard ("*") entries in allowedOrigins are deliberately NOT honored as a
// match: ApplyCORSHeaders sends Access-Control-Allow-Credentials: true, and
// per the CORS spec credentials must never be granted to an unbounded origin
// set. Allowing both together is the classic credentialed-wildcard CSRF
// amplification footgun. Operators get a startup warning (see config) and
// the wildcard becomes effectively inert here.
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
		if normalizedAllowed == "" || normalizedAllowed == "*" {
			continue
		}
		if strings.EqualFold(normalizedAllowed, normalizedOrigin) {
			return true
		}
	}

	return false
}

// hasControlChars reports whether s contains a NUL or other control character.
// These never appear in a legitimate service name, file path, device target, or
// log filter, but are a classic vector for log injection and argument smuggling
// once the value reaches the agent. Cheap defense-in-depth at the API boundary
// (the agent validates too).
func hasControlChars(s string) bool {
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return true
		}
	}
	return false
}

// validateForwardedParam rejects values that should never be relayed to an
// agent. isPath additionally rejects ".." path-traversal sequences. Returns a
// human-readable reason and false when the value must be rejected.
func validateForwardedParam(field, value string, isPath bool) (string, bool) {
	if hasControlChars(value) {
		return field + " contains invalid control characters", false
	}
	if isPath && strings.Contains(value, "..") {
		return field + " must not contain '..'", false
	}
	return "", true
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
