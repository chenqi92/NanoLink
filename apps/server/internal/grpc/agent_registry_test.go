package grpc

import (
	"testing"
	"time"

	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"go.uber.org/zap"
)

func TestAgentRegistryPromotesNewestConnectionAndPreservesItFromStaleCleanup(t *testing.T) {
	s := &Server{agents: make(map[string]*GrpcAgent)}
	first := &GrpcAgent{commandChan: make(chan *pb.Command, 1)}
	replacement := &GrpcAgent{commandChan: make(chan *pb.Command, 1)}

	if previous := s.replaceAgent("agent-1", first); previous != nil {
		t.Fatal("first connection should not replace an existing stream")
	}
	if previous := s.replaceAgent("agent-1", replacement); previous != first {
		t.Fatal("replacement should return the previous stream")
	}
	if got := s.GetAgent("agent-1"); got != replacement {
		t.Fatal("newest authenticated stream was not promoted")
	}
	if s.removeAgentIfCurrent("agent-1", first) {
		t.Fatal("stale connection must not remove the current connection")
	}
	if got := s.GetAgent("agent-1"); got != replacement {
		t.Fatal("stale cleanup removed the current connection")
	}
	if !s.removeAgentIfCurrent("agent-1", replacement) {
		t.Fatal("current connection should be removable")
	}
	if got := s.GetAgent("agent-1"); got != nil {
		t.Fatal("current connection was not removed")
	}
}

func TestDisconnectGraceDoesNotRemoveReplacement(t *testing.T) {
	logger := zap.NewNop().Sugar()
	metrics := service.NewMetricsService(logger)
	agents := service.NewAgentService(logger, metrics)
	s := NewServer(nil, agents, nil, metrics, logger)
	s.disconnectGrace = 10 * time.Millisecond

	first := &GrpcAgent{
		AgentID:     "agent-1",
		Hostname:    "first",
		commandChan: make(chan *pb.Command, 1),
	}
	replacement := &GrpcAgent{
		AgentID:     "agent-1",
		Hostname:    "replacement",
		commandChan: make(chan *pb.Command, 1),
	}
	s.replaceAgent("agent-1", first)
	agents.RegisterGrpcAgent("agent-1", service.AgentInfo{Hostname: "first"}, 0)
	s.scheduleAgentDisconnect("agent-1", first)
	s.replaceAgent("agent-1", replacement)
	agents.RegisterGrpcAgent("agent-1", service.AgentInfo{Hostname: "replacement"}, 0)

	time.Sleep(50 * time.Millisecond)
	if got := s.GetAgent("agent-1"); got != replacement {
		t.Fatal("stale grace timer removed the replacement stream")
	}
	if got := agents.GetAgent("agent-1"); got == nil || got.Hostname != "replacement" {
		t.Fatal("stale grace timer removed the replacement dashboard agent")
	}
}
