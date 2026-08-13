package grpc

import (
	"sync"
	"testing"
	"time"
)

type testGRPCStopper struct {
	gracefulDone chan struct{}
	stopCalled   chan struct{}
	stopOnce     sync.Once
}

func (s *testGRPCStopper) GracefulStop() {
	<-s.gracefulDone
}

func (s *testGRPCStopper) Stop() {
	s.stopOnce.Do(func() {
		close(s.stopCalled)
		close(s.gracefulDone)
	})
}

func TestStopGRPCServerReturnsAfterGracefulCompletion(t *testing.T) {
	done := make(chan struct{})
	close(done)
	server := &testGRPCStopper{gracefulDone: done, stopCalled: make(chan struct{})}
	if !stopGRPCServer(server, time.Second) {
		t.Fatal("completed graceful shutdown was reported as forced")
	}
	select {
	case <-server.stopCalled:
		t.Fatal("force stop was called after graceful completion")
	default:
	}
}

func TestStopGRPCServerForceClosesLongLivedStreams(t *testing.T) {
	server := &testGRPCStopper{gracefulDone: make(chan struct{}), stopCalled: make(chan struct{})}
	started := time.Now()
	if stopGRPCServer(server, 20*time.Millisecond) {
		t.Fatal("blocked graceful shutdown unexpectedly completed")
	}
	if time.Since(started) > time.Second {
		t.Fatal("forced shutdown did not respect its timeout")
	}
	select {
	case <-server.stopCalled:
	default:
		t.Fatal("force stop was not called")
	}
}
