package service

import (
	"strconv"
	"sync"
	"testing"
	"time"

	"go.uber.org/zap"
)

// TestCurrentMetricsSnapshotIsRaceFree exercises concurrent realtime merges
// (which mutate the stored *MetricsData in place under the write lock, including
// appending to Disks) against snapshot reads. Before GetAllCurrentMetrics /
// GetCurrentMetrics returned deep copies, readers received the live pointer and
// raced with MergeRealtimeMetrics on scalar fields and the Disks slice. Run with
// `go test -race` to catch a regression.
func TestCurrentMetricsSnapshotIsRaceFree(t *testing.T) {
	s := NewMetricsService(zap.NewNop().Sugar())
	const agent = "agent-1"
	s.StoreMetrics(agent, &MetricsData{Disks: []DiskData{{Device: "sda"}}})

	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(3)

	// Writer: realtime merges that mutate fields and append disks.
	go func() {
		defer wg.Done()
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
				s.MergeRealtimeMetrics(agent, &RealtimeUpdate{
					CPUUsage: float64(i % 100),
					DiskIO: []DiskData{
						{Device: "sda", ReadBytesPS: uint64(i)},
						{Device: "dev" + strconv.Itoa(i%64), WriteBytesPS: uint64(i)},
					},
				})
			}
		}
	}()

	reader := func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
				for _, m := range s.GetAllCurrentMetrics() {
					_ = m.CPU.UsagePercent
					for _, d := range m.Disks {
						_ = d.ReadBytesPS + d.WriteBytesPS
					}
				}
				if m := s.GetCurrentMetrics(agent); m != nil {
					_ = m.CPU.UsagePercent
				}
			}
		}
	}
	go reader()
	go reader()

	time.Sleep(150 * time.Millisecond)
	close(stop)
	wg.Wait()
}
