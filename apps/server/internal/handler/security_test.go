package handler

import (
	"crypto/tls"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestExtractTokenRejectsQueryParameter(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/ws?token=leaked", nil)
	if token, ok := ExtractTokenFromHTTPRequest(req); ok || token != "" {
		t.Fatalf("query credential was accepted: %q", token)
	}
}

func TestForwardedHeadersAreOnlyAcceptedFromTrustedPeers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	middleware, err := NewForwardedHeadersMiddleware([]string{"10.0.0.0/8"})
	if err != nil {
		t.Fatal(err)
	}

	for _, tc := range []struct {
		name       string
		remoteAddr string
		wantProto  string
	}{
		{name: "untrusted", remoteAddr: "203.0.113.7:1234", wantProto: ""},
		{name: "trusted", remoteAddr: "10.1.2.3:1234", wantProto: "https"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			router := gin.New()
			router.Use(middleware)
			router.GET("/", func(c *gin.Context) {
				c.String(http.StatusOK, c.GetHeader("X-Forwarded-Proto"))
			})
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.RemoteAddr = tc.remoteAddr
			req.Header.Set("X-Forwarded-Proto", "https")
			res := httptest.NewRecorder()
			router.ServeHTTP(res, req)
			if got := res.Body.String(); got != tc.wantProto {
				t.Fatalf("forwarded proto = %q, want %q", got, tc.wantProto)
			}
		})
	}
}

func TestRequireBearerToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(RequireBearerToken("0123456789abcdef0123456789abcdef"))
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	for _, tc := range []struct {
		name   string
		header string
		want   int
	}{
		{name: "missing", want: http.StatusUnauthorized},
		{name: "wrong", header: "Bearer wrong", want: http.StatusUnauthorized},
		{name: "valid", header: "Bearer 0123456789abcdef0123456789abcdef", want: http.StatusNoContent},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.Header.Set("Authorization", tc.header)
			res := httptest.NewRecorder()
			router.ServeHTTP(res, req)
			if res.Code != tc.want {
				t.Fatalf("status = %d, want %d", res.Code, tc.want)
			}
		})
	}
}

func TestSecurityHeadersEnableHSTSForTLS(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(SecurityHeaders())
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	req := httptest.NewRequest(http.MethodGet, "https://example.test/", nil)
	req.TLS = &tls.ConnectionState{}
	res := httptest.NewRecorder()
	router.ServeHTTP(res, req)
	if res.Header().Get("Strict-Transport-Security") == "" {
		t.Fatal("expected HSTS on a TLS request")
	}
	if res.Header().Get("Content-Security-Policy") == "" {
		t.Fatal("expected Content-Security-Policy")
	}
}

func TestResponseTokenIsUnavailableToBrowserOrigins(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, tc := range []struct {
		name   string
		origin string
		want   string
	}{
		{name: "native", want: "secret"},
		{name: "browser", origin: "https://example.test", want: ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
			ctx.Request = httptest.NewRequest(http.MethodPost, "/api/auth/login", nil)
			ctx.Request.Header.Set(NativeClientHeader, "native")
			ctx.Request.Header.Set("Origin", tc.origin)
			if got := responseToken(ctx, "secret"); got != tc.want {
				t.Fatalf("response token = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestAuthCookieUsesStrictSameSite(t *testing.T) {
	gin.SetMode(gin.TestMode)
	res := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(res)
	ctx.Request = httptest.NewRequest(http.MethodPost, "https://example.test/api/auth/login", nil)
	SetAuthCookie(ctx, "secret", time.Hour)

	cookies := res.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("cookie count = %d, want 1", len(cookies))
	}
	if cookies[0].SameSite != http.SameSiteStrictMode {
		t.Fatalf("SameSite = %v, want Strict", cookies[0].SameSite)
	}
	if !cookies[0].HttpOnly || !cookies[0].Secure {
		t.Fatal("auth cookie must be HttpOnly and Secure on HTTPS")
	}
}
