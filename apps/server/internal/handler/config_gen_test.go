package handler

import (
	"strings"
	"testing"
)

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
			defaultPort: 39100,
			wantHost:    "example.com",
			wantPort:    39100,
		},
		{
			name:        "host port",
			input:       "example.com:39100",
			defaultPort: 39100,
			wantHost:    "example.com",
			wantPort:    39100,
		},
		{
			name:        "legacy websocket url",
			input:       "wss://example.com:39100",
			defaultPort: 39100,
			wantHost:    "example.com",
			wantPort:    39100,
		},
		{
			name:        "bracketed ipv6",
			input:       "[2001:db8::1]:39100",
			defaultPort: 39100,
			wantHost:    "2001:db8::1",
			wantPort:    39100,
		},
		{
			name:        "reject unsupported url scheme",
			input:       "https://example.com:39100",
			defaultPort: 39100,
			wantErr:     true,
		},
		{
			name:        "reject shell metacharacters",
			input:       "example.com;rm",
			defaultPort: 39100,
			wantErr:     true,
		},
		{
			name:        "reject invalid port",
			input:       "example.com:0",
			defaultPort: 39100,
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

func TestGenerateTLSConfigIncludesPrivateCAAndMTLS(t *testing.T) {
	req := GenerateConfigRequest{
		Permission:    2,
		TLSVerify:     true,
		TLSCACert:     "/etc/nanolink/tls/ca.crt",
		TLSServerName: "monitor.example.com",
		TLSClientCert: "/etc/nanolink/tls/agent.crt",
		TLSClientKey:  "/etc/nanolink/tls/agent.key",
	}

	yaml := generateYAMLConfig(req, "token", "127.0.0.1", 39100)
	for _, expected := range []string{
		"tls_enabled: true",
		"tls_verify: true",
		"tls_ca_cert: \"/etc/nanolink/tls/ca.crt\"",
		"tls_server_name: \"monitor.example.com\"",
		"tls_client_cert: \"/etc/nanolink/tls/agent.crt\"",
		"tls_client_key: \"/etc/nanolink/tls/agent.key\"",
	} {
		if !strings.Contains(yaml, expected) {
			t.Fatalf("generated YAML does not contain %q:\n%s", expected, yaml)
		}
	}

	command := generateUnixInstallCommand(req, "token", "127.0.0.1:39100")
	for _, flag := range []string{"--tls-ca-cert", "--tls-server-name", "--tls-client-cert", "--tls-client-key"} {
		if !strings.Contains(command, flag) {
			t.Fatalf("generated command does not contain %q: %s", flag, command)
		}
	}
}

func TestGeneratePlaintextInstallUsesNoTLSInsteadOfDisablingVerification(t *testing.T) {
	req := GenerateConfigRequest{TLSVerify: false}
	command := generateUnixInstallCommand(req, "token", "example.com:39100")
	if !strings.Contains(command, "--no-tls") {
		t.Fatalf("generated command does not disable TLS explicitly: %s", command)
	}
	if strings.Contains(command, "--no-tls-verify") {
		t.Fatalf("generated command disables certificate verification: %s", command)
	}
}
