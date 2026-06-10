package service

import (
	"strings"
	"testing"
)

func TestSanitizeEmailHeaderValueRemovesCRLF(t *testing.T) {
	got := sanitizeEmailHeaderValue("ops@example.com\r\nBcc: attacker@example.com")
	if strings.ContainsAny(got, "\r\n") {
		t.Fatalf("header still contains CRLF: %q", got)
	}
	if got != "ops@example.com Bcc: attacker@example.com" {
		t.Fatalf("got %q", got)
	}
}

func TestSanitizeEmailHeaderValueKeepsNormalHeader(t *testing.T) {
	got := sanitizeEmailHeaderValue("NanoLink Alert")
	if got != "NanoLink Alert" {
		t.Fatalf("got %q", got)
	}
}
