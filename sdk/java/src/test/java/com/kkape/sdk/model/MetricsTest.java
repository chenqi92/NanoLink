package com.kkape.sdk.model;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for Metrics model classes
 */
class MetricsTest {

    @Test
    @DisplayName("Metrics getters and setters work correctly")
    void testMetricsGettersSetters() {
        Metrics metrics = new Metrics();
        metrics.setTimestamp(1234567890L);
        metrics.setHostname("test-host");

        assertEquals(1234567890L, metrics.getTimestamp());
        assertEquals("test-host", metrics.getHostname());
    }

    @Test
    @DisplayName("CpuMetrics holds CPU data correctly")
    void testCpuMetrics() {
        Metrics.CpuMetrics cpu = new Metrics.CpuMetrics();
        cpu.setUsagePercent(75.5);
        cpu.setCoreCount(8);
        cpu.setPerCoreUsage(new double[]{70.0, 80.0, 75.0, 77.0, 72.0, 78.0, 74.0, 76.0});

        assertEquals(75.5, cpu.getUsagePercent(), 0.01);
        assertEquals(8, cpu.getCoreCount());
        assertEquals(8, cpu.getPerCoreUsage().length);
        assertEquals(70.0, cpu.getPerCoreUsage()[0], 0.01);
    }

    @Test
    @DisplayName("MemoryMetrics calculates usage percent correctly")
    void testMemoryMetricsUsagePercent() {
        Metrics.MemoryMetrics memory = new Metrics.MemoryMetrics();
        memory.setTotal(16000000000L);
        memory.setUsed(8000000000L);
        memory.setAvailable(8000000000L);

        assertEquals(50.0, memory.getUsagePercent(), 0.01);
    }

    @Test
    @DisplayName("MemoryMetrics handles zero total")
    void testMemoryMetricsZeroTotal() {
        Metrics.MemoryMetrics memory = new Metrics.MemoryMetrics();
        memory.setTotal(0);
        memory.setUsed(100);

        assertEquals(0.0, memory.getUsagePercent(), 0.01);
    }

    @Test
    @DisplayName("MemoryMetrics swap getters and setters work")
    void testMemoryMetricsSwap() {
        Metrics.MemoryMetrics memory = new Metrics.MemoryMetrics();
        memory.setSwapTotal(8000000000L);
        memory.setSwapUsed(1000000000L);

        assertEquals(8000000000L, memory.getSwapTotal());
        assertEquals(1000000000L, memory.getSwapUsed());
    }

    @Test
    @DisplayName("DiskMetrics calculates usage percent correctly")
    void testDiskMetricsUsagePercent() {
        Metrics.DiskMetrics disk = new Metrics.DiskMetrics();
        disk.setTotal(500000000000L);
        disk.setUsed(250000000000L);
        disk.setAvailable(250000000000L);

        assertEquals(50.0, disk.getUsagePercent(), 0.01);
    }

    @Test
    @DisplayName("DiskMetrics handles zero total")
    void testDiskMetricsZeroTotal() {
        Metrics.DiskMetrics disk = new Metrics.DiskMetrics();
        disk.setTotal(0);
        disk.setUsed(100);

        assertEquals(0.0, disk.getUsagePercent(), 0.01);
    }

    @Test
    @DisplayName("DiskMetrics holds all properties correctly")
    void testDiskMetricsProperties() {
        Metrics.DiskMetrics disk = new Metrics.DiskMetrics();
        disk.setMountPoint("/");
        disk.setDevice("/dev/sda1");
        disk.setFsType("ext4");
        disk.setReadBytesPerSec(1048576L);
        disk.setWriteBytesPerSec(524288L);

        assertEquals("/", disk.getMountPoint());
        assertEquals("/dev/sda1", disk.getDevice());
        assertEquals("ext4", disk.getFsType());
        assertEquals(1048576L, disk.getReadBytesPerSec());
        assertEquals(524288L, disk.getWriteBytesPerSec());
    }

    @Test
    @DisplayName("NetworkMetrics holds all properties correctly")
    void testNetworkMetrics() {
        Metrics.NetworkMetrics network = new Metrics.NetworkMetrics();
        network.setInterfaceName("eth0");
        network.setRxBytesPerSec(1000000L);
        network.setTxBytesPerSec(500000L);
        network.setRxPacketsPerSec(1000L);
        network.setTxPacketsPerSec(500L);
        network.setUp(true);

        assertEquals("eth0", network.getInterfaceName());
        assertEquals(1000000L, network.getRxBytesPerSec());
        assertEquals(500000L, network.getTxBytesPerSec());
        assertEquals(1000L, network.getRxPacketsPerSec());
        assertEquals(500L, network.getTxPacketsPerSec());
        assertTrue(network.isUp());
    }

    @Test
    @DisplayName("Metrics with full data structure")
    void testMetricsFullStructure() {
        Metrics metrics = new Metrics();
        metrics.setTimestamp(System.currentTimeMillis());
        metrics.setHostname("test-server");

        Metrics.CpuMetrics cpu = new Metrics.CpuMetrics();
        cpu.setUsagePercent(45.0);
        cpu.setCoreCount(4);
        metrics.setCpu(cpu);

        Metrics.MemoryMetrics memory = new Metrics.MemoryMetrics();
        memory.setTotal(16000000000L);
        memory.setUsed(8000000000L);
        metrics.setMemory(memory);

        Metrics.DiskMetrics disk = new Metrics.DiskMetrics();
        disk.setMountPoint("/");
        disk.setTotal(500000000000L);
        disk.setUsed(100000000000L);
        metrics.setDisks(Arrays.asList(disk));

        Metrics.NetworkMetrics network = new Metrics.NetworkMetrics();
        network.setInterfaceName("eth0");
        network.setUp(true);
        metrics.setNetworks(Arrays.asList(network));

        metrics.setLoadAverage(new double[]{1.5, 2.0, 1.8});

        assertNotNull(metrics.getCpu());
        assertNotNull(metrics.getMemory());
        assertNotNull(metrics.getDisks());
        assertNotNull(metrics.getNetworks());
        assertEquals(1, metrics.getDisks().size());
        assertEquals(1, metrics.getNetworks().size());
        assertEquals(3, metrics.getLoadAverage().length);
    }

    @Test
    @DisplayName("NetworkMetrics isUp flag works correctly")
    void testNetworkMetricsIsUp() {
        Metrics.NetworkMetrics network = new Metrics.NetworkMetrics();

        network.setUp(true);
        assertTrue(network.isUp());

        network.setUp(false);
        assertFalse(network.isUp());
    }
}
