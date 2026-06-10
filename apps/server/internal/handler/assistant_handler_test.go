package handler

import (
	"errors"
	"strings"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
)

func TestSanitizeAssistantMessagesFiltersAndTrims(t *testing.T) {
	got, err := sanitizeAssistantMessages([]service.ChatMessage{
		{Role: "system", Content: "ignored"},
		{Role: "user", Content: "  hello  "},
		{Role: "assistant", Content: "\nworld\n"},
		{Role: "user", Content: "   "},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d messages, want 2", len(got))
	}
	if got[0].Content != "hello" || got[1].Content != "world" {
		t.Fatalf("messages were not trimmed/filtered: %#v", got)
	}
}

func TestSanitizeAssistantMessagesRejectsTooManyMessages(t *testing.T) {
	messages := make([]service.ChatMessage, maxAssistantMessages+1)
	for i := range messages {
		messages[i] = service.ChatMessage{Role: "user", Content: "hello"}
	}
	_, err := sanitizeAssistantMessages(messages)
	if !errors.Is(err, errAssistantTooManyMessages) {
		t.Fatalf("got %v, want %v", err, errAssistantTooManyMessages)
	}
}

func TestSanitizeAssistantMessagesRejectsLongMessage(t *testing.T) {
	_, err := sanitizeAssistantMessages([]service.ChatMessage{
		{Role: "user", Content: strings.Repeat("a", maxAssistantMessageBytes+1)},
	})
	if !errors.Is(err, errAssistantMessageTooLong) {
		t.Fatalf("got %v, want %v", err, errAssistantMessageTooLong)
	}
}
