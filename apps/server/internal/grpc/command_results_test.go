package grpc

import (
	"errors"
	"testing"
	"time"

	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"go.uber.org/zap"
)

func TestCommandResultRequiresOwningUser(t *testing.T) {
	s := NewServer(nil, nil, nil, nil, zap.NewNop().Sugar())

	s.RegisterDispatchedCommand("cmd-1", "agent-1", 7, "alice", "SYSTEM_LOGS")
	s.storeCommandResult("agent-1", &pb.CommandResult{
		CommandId: "cmd-1",
		Success:   true,
		Output:    "sensitive output",
	})

	result, ok, err := s.GetCommandResultForUser("cmd-1", "agent-1", 7, false)
	if err != nil || !ok {
		t.Fatalf("owner should read result: ok=%v err=%v", ok, err)
	}
	if result.Output != "sensitive output" {
		t.Fatalf("got output %q", result.Output)
	}

	_, ok, err = s.GetCommandResultForUser("cmd-1", "agent-1", 8, false)
	if !ok || !errors.Is(err, ErrCommandResultAccessDenied) {
		t.Fatalf("other user should be denied: ok=%v err=%v", ok, err)
	}

	_, ok, err = s.GetCommandResultForUser("cmd-1", "agent-2", 7, false)
	if !ok || !errors.Is(err, ErrCommandResultAccessDenied) {
		t.Fatalf("wrong agent should be denied: ok=%v err=%v", ok, err)
	}
}

func TestCommandResultReplayIsDetectedPerAgent(t *testing.T) {
	s := NewServer(nil, nil, nil, nil, zap.NewNop().Sugar())
	s.commandResults.Store("cmd-replay", &commandResultEntry{
		result:  &pb.CommandResult{CommandId: "cmd-replay", Success: true},
		at:      time.Now(),
		agentID: "agent-a",
	})

	if !s.commandResultAlreadyStored("agent-a", "cmd-replay") {
		t.Fatal("same-agent replay should be detected")
	}
	if s.commandResultAlreadyStored("agent-b", "cmd-replay") {
		t.Fatal("result from another agent must not be treated as a replay")
	}
}

func TestCommandResultAllowsSuperAdmin(t *testing.T) {
	s := NewServer(nil, nil, nil, nil, zap.NewNop().Sugar())

	s.RegisterDispatchedCommand("cmd-1", "agent-1", 7, "alice", "SYSTEM_LOGS")
	s.storeCommandResult("agent-1", &pb.CommandResult{
		CommandId: "cmd-1",
		Success:   true,
		Output:    "sensitive output",
	})

	_, ok, err := s.GetCommandResultForUser("cmd-1", "agent-1", 99, true)
	if err != nil || !ok {
		t.Fatalf("super admin should read result: ok=%v err=%v", ok, err)
	}
}

func TestUnregisteredCommandResultIsDenied(t *testing.T) {
	s := NewServer(nil, nil, nil, nil, zap.NewNop().Sugar())

	s.storeCommandResult("agent-1", &pb.CommandResult{
		CommandId: "cmd-1",
		Success:   true,
		Output:    "unexpected output",
	})

	_, ok, err := s.GetCommandResultForUser("cmd-1", "agent-1", 7, true)
	if !ok || !errors.Is(err, ErrCommandResultAccessDenied) {
		t.Fatalf("unregistered result should be denied: ok=%v err=%v", ok, err)
	}
}
