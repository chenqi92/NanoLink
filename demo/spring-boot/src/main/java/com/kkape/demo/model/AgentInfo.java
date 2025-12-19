package com.kkape.demo.model;

import java.time.Instant;

/**
 * Agent information record
 */
public record AgentInfo(
        String agentId,
        String hostname,
        String os,
        String arch,
        String version,
        Instant connectedAt
) {
}
