package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/mcp"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

func TestMCPOverviewIsSanitized(t *testing.T) {
	gin.SetMode(gin.TestMode)
	server := mcp.NewServer(nil, nil, zap.NewNop().Sugar())
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	context.Request = httptest.NewRequest(http.MethodGet, "/api/mcp/overview", nil)

	NewMCPStatusHandler(server).Overview(context)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var overview mcp.Overview
	if err := json.Unmarshal(recorder.Body.Bytes(), &overview); err != nil {
		t.Fatal(err)
	}
	if overview.State != "disabled" || len(overview.Tools) == 0 {
		t.Fatalf("overview = %#v", overview)
	}
	if overview.Activity == nil || !strings.Contains(recorder.Body.String(), `"activity":[]`) {
		t.Fatalf("empty activity must be encoded as an array: %s", recorder.Body.String())
	}
	for _, forbidden := range []string{"authToken", "apiKey", "arguments", "results"} {
		if strings.Contains(recorder.Body.String(), forbidden) {
			t.Fatalf("overview contains %q: %s", forbidden, recorder.Body.String())
		}
	}
}
