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
	got := sanitizeEmailHeaderValue("NanoOps Alert")
	if got != "NanoOps Alert" {
		t.Fatalf("got %q", got)
	}
}

func TestParseMailboxAddressRejectsHeaderAndSMTPInjection(t *testing.T) {
	for _, value := range []string{
		"ops@example.com\r\nBcc: attacker@example.com",
		"ops@example.com> SMTPUTF8",
		"",
	} {
		if address, err := parseMailboxAddress(value); err == nil {
			t.Fatalf("parseMailboxAddress(%q) unexpectedly returned %#v", value, address)
		}
	}
}

func TestParseMailboxAddressAcceptsDisplayName(t *testing.T) {
	address, err := parseMailboxAddress("NanoOps Alerts <ops@example.com>")
	if err != nil {
		t.Fatalf("parseMailboxAddress returned error: %v", err)
	}
	if address.Address != "ops@example.com" {
		t.Fatalf("envelope address = %q", address.Address)
	}
}
