package handler

import "testing"

func TestParseServerEndpoint(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		defaultPort int
		wantHost    string
		wantPort    int
		wantErr     bool
	}{
		{
			name:        "host uses configured default port",
			input:       "example.com",
			defaultPort: 9200,
			wantHost:    "example.com",
			wantPort:    9200,
		},
		{
			name:        "host port",
			input:       "example.com:39100",
			defaultPort: 9200,
			wantHost:    "example.com",
			wantPort:    39100,
		},
		{
			name:        "legacy websocket url",
			input:       "wss://example.com:39100",
			defaultPort: 9200,
			wantHost:    "example.com",
			wantPort:    39100,
		},
		{
			name:        "bracketed ipv6",
			input:       "[2001:db8::1]:39100",
			defaultPort: 9200,
			wantHost:    "2001:db8::1",
			wantPort:    39100,
		},
		{
			name:        "reject unsupported url scheme",
			input:       "https://example.com:39100",
			defaultPort: 9200,
			wantErr:     true,
		},
		{
			name:        "reject shell metacharacters",
			input:       "example.com;rm",
			defaultPort: 9200,
			wantErr:     true,
		},
		{
			name:        "reject invalid port",
			input:       "example.com:0",
			defaultPort: 9200,
			wantErr:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			host, port, err := parseServerEndpoint(tt.input, tt.defaultPort)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if host != tt.wantHost || port != tt.wantPort {
				t.Fatalf("got %s:%d, want %s:%d", host, port, tt.wantHost, tt.wantPort)
			}
		})
	}
}

func TestShellQuoteEscapesSingleQuotes(t *testing.T) {
	got := shellQuote("agent'one")
	want := "'agent'\\''one'"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestHostForCLIWrapsIPv6(t *testing.T) {
	if got := hostForCLI("2001:db8::1"); got != "[2001:db8::1]" {
		t.Fatalf("got %q", got)
	}
	if got := hostForCLI("example.com"); got != "example.com" {
		t.Fatalf("got %q", got)
	}
}
