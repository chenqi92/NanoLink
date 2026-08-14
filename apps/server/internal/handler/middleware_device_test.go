package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type deviceAuthFixture struct {
	auth        *service.AuthService
	devices     *service.DeviceService
	owner       database.User
	deviceToken string
}

func newDeviceAuthFixture(t *testing.T, permission int) deviceAuthFixture {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	if err := db.AutoMigrate(&database.User{}, &database.DeviceToken{}); err != nil {
		t.Fatalf("migrate test database: %v", err)
	}

	owner := database.User{
		Username:     "device-owner",
		PasswordHash: "unused-test-hash",
		Email:        func() *string { value := "owner@example.test"; return &value }(),
		IsSuperAdmin: true,
		TokenVersion: 1,
	}
	if err := db.Create(&owner).Error; err != nil {
		t.Fatalf("create owner: %v", err)
	}

	logger := zap.NewNop().Sugar()
	auth := service.NewAuthService(db, service.AuthConfig{
		JWTSecret: "middleware-device-test-secret-at-least-32-bytes",
		JWTExpire: time.Hour,
	}, logger)
	devices := service.NewDeviceService(db, logger, "https://ops.example.test")
	result, _, err := devices.CreateDeviceToken(owner.ID, "Test server", permission)
	if err != nil {
		t.Fatalf("create device token: %v", err)
	}

	return deviceAuthFixture{auth: auth, devices: devices, owner: owner, deviceToken: result.Token}
}

func performBearerRequest(router http.Handler, path, token string) *httptest.ResponseRecorder {
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, path, nil)
	request.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(recorder, request)
	return recorder
}

func TestDeviceTokenAuthenticatesWithPermissionCap(t *testing.T) {
	gin.SetMode(gin.TestMode)
	fixture := newDeviceAuthFixture(t, database.PermissionReadOnly)
	router := gin.New()
	router.GET("/protected", AuthMiddlewareWithDevices(fixture.auth, fixture.devices), func(c *gin.Context) {
		level, isDevice := GetCurrentDevicePermission(c)
		c.JSON(http.StatusOK, gin.H{
			"userId":   GetCurrentUser(c).ID,
			"isDevice": isDevice,
			"level":    level,
		})
	})

	response := performBearerRequest(router, "/protected", fixture.deviceToken)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	var body struct {
		UserID   uint `json:"userId"`
		IsDevice bool `json:"isDevice"`
		Level    int  `json:"level"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.UserID != fixture.owner.ID || !body.IsDevice || body.Level != database.PermissionReadOnly {
		t.Fatalf("unexpected auth context: %+v", body)
	}
}

func TestDeviceOwnedBySuperAdminCannotUseAdminSession(t *testing.T) {
	gin.SetMode(gin.TestMode)
	fixture := newDeviceAuthFixture(t, database.PermissionSystemAdmin)
	router := gin.New()
	router.GET(
		"/admin",
		AuthMiddlewareWithDevices(fixture.auth, fixture.devices),
		RequireSuperAdmin(),
		func(c *gin.Context) { c.Status(http.StatusNoContent) },
	)

	response := performBearerRequest(router, "/admin", fixture.deviceToken)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d; body = %s", response.Code, http.StatusForbidden, response.Body.String())
	}
}

func TestDevicePermissionCapsSuperAdminAgentAccess(t *testing.T) {
	gin.SetMode(gin.TestMode)
	fixture := newDeviceAuthFixture(t, database.PermissionReadOnly)
	router := gin.New()
	router.GET(
		"/agents/:id/shell",
		AuthMiddlewareWithDevices(fixture.auth, fixture.devices),
		RequireAgentPermission(nil, database.PermissionSystemAdmin),
		func(c *gin.Context) { c.Status(http.StatusNoContent) },
	)

	response := performBearerRequest(router, "/agents/agent-1/shell", fixture.deviceToken)
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d; body = %s", response.Code, http.StatusForbidden, response.Body.String())
	}
}

func TestAccountJWTStillAuthenticatesNormally(t *testing.T) {
	gin.SetMode(gin.TestMode)
	fixture := newDeviceAuthFixture(t, database.PermissionReadOnly)
	token, err := fixture.auth.GenerateToken(&fixture.owner)
	if err != nil {
		t.Fatalf("generate account token: %v", err)
	}
	router := gin.New()
	router.GET(
		"/admin",
		AuthMiddlewareWithDevices(fixture.auth, fixture.devices),
		RequireSuperAdmin(),
		func(c *gin.Context) { c.Status(http.StatusNoContent) },
	)

	response := performBearerRequest(router, "/admin", token)
	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d; body = %s", response.Code, http.StatusNoContent, response.Body.String())
	}
}
