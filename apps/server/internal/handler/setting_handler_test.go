package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestGetSettingsDoesNotExposeLLMSecretRows(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.Setting{}); err != nil {
		t.Fatal(err)
	}
	for _, setting := range []database.Setting{
		{Key: "serverName", Value: "NanoOps"},
		{Key: "llm.api_key", Value: "enc:v1:must-not-leak"},
		{Key: "llm.provider", Value: "openai-compatible"},
	} {
		if err := db.Save(&setting).Error; err != nil {
			t.Fatal(err)
		}
	}

	handler := NewSettingHandler(db, nil, zap.NewNop().Sugar())
	router := gin.New()
	router.GET("/settings", handler.GetSettings)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/settings", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	var body map[string]string
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["serverName"] != "NanoOps" {
		t.Fatalf("allowed setting missing: %#v", body)
	}
	if _, exists := body["llm.api_key"]; exists {
		t.Fatal("encrypted LLM API key leaked through generic settings endpoint")
	}
	if _, exists := body["llm.provider"]; exists {
		t.Fatal("dedicated LLM settings leaked through generic settings endpoint")
	}
}

func TestUpdateSettingsTogglesPublicRegistrationAtRuntime(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.User{}, &database.Setting{}); err != nil {
		t.Fatal(err)
	}
	auth := service.NewAuthService(db, service.AuthConfig{
		JWTSecret: "0123456789abcdef0123456789abcdef",
	}, zap.NewNop().Sugar())

	handler := NewSettingHandler(db, auth, zap.NewNop().Sugar())
	router := gin.New()
	router.PUT("/settings", handler.UpdateSettings)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPut, "/settings", bytes.NewBufferString(`{"registrationEnabled":"true"}`))
	request.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	enabled, err := auth.PublicRegistrationEnabled()
	if err != nil || !enabled {
		t.Fatalf("registration enabled = %v, err = %v", enabled, err)
	}
}
