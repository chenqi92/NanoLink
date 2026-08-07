package mcp

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"go.uber.org/zap"
)

func TestSSETransportRequiresBearerToken(t *testing.T) {
	transport := NewSSETransport(
		"127.0.0.1:0",
		"0123456789abcdef0123456789abcdef",
		zap.NewNop().Sugar(),
	)
	handler := transport.requireBearer(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})

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
			req := httptest.NewRequest(http.MethodGet, "/sse", nil)
			req.Header.Set("Authorization", tc.header)
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != tc.want {
				t.Fatalf("status = %d, want %d", res.Code, tc.want)
			}
		})
	}
}
