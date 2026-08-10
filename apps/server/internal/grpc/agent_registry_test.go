package grpc

import "testing"

func TestAgentRegistryRejectsDuplicateAndPreservesCurrent(t *testing.T) {
	s := &Server{agents: make(map[string]*GrpcAgent)}
	first := &GrpcAgent{}
	duplicate := &GrpcAgent{}

	if !s.registerAgentIfAbsent("agent-1", first) {
		t.Fatal("first connection should be registered")
	}
	if s.registerAgentIfAbsent("agent-1", duplicate) {
		t.Fatal("duplicate connection should be rejected")
	}
	if got := s.GetAgent("agent-1"); got != first {
		t.Fatal("duplicate registration replaced the current connection")
	}
	if s.removeAgentIfCurrent("agent-1", duplicate) {
		t.Fatal("stale connection must not remove the current connection")
	}
	if got := s.GetAgent("agent-1"); got != first {
		t.Fatal("stale cleanup removed the current connection")
	}
	if !s.removeAgentIfCurrent("agent-1", first) {
		t.Fatal("current connection should be removable")
	}
	if got := s.GetAgent("agent-1"); got != nil {
		t.Fatal("current connection was not removed")
	}
}
