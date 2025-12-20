package com.kkape.demo.controller;

import com.kkape.sdk.AgentConnection;
import com.kkape.sdk.NanoLinkServer;
import com.kkape.sdk.model.Command;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * REST API for executing commands on agents
 *
 * Provides endpoints to send commands to connected agents.
 */
@RestController
@RequestMapping("/api/commands")
@CrossOrigin(origins = "*")
public class CommandController {

    private static final Logger log = LoggerFactory.getLogger(CommandController.class);

    private final NanoLinkServer nanoLinkServer;

    public CommandController(NanoLinkServer nanoLinkServer) {
        this.nanoLinkServer = nanoLinkServer;
    }

    /**
     * Restart a service on an agent
     */
    @PostMapping("/agents/{hostname}/service/restart")
    public ResponseEntity<CommandResponse> restartService(
            @PathVariable String hostname,
            @RequestBody ServiceRequest request) {

        AgentConnection agent = nanoLinkServer.getAgentByHostname(hostname);
        if (agent == null) {
            return ResponseEntity.notFound().build();
        }

        try {
            log.info("Restarting service {} on {}", request.serviceName(), hostname);
            agent.sendCommand(Command.serviceRestart(request.serviceName()));
            return ResponseEntity.ok(new CommandResponse(true, "Service restart command sent"));
        } catch (Exception e) {
            log.error("Failed to restart service on {}", hostname, e);
            return ResponseEntity.internalServerError()
                    .body(new CommandResponse(false, "Failed: " + e.getMessage()));
        }
    }

    /**
     * Kill a process on an agent
     */
    @PostMapping("/agents/{hostname}/process/kill")
    public ResponseEntity<CommandResponse> killProcess(
            @PathVariable String hostname,
            @RequestBody ProcessRequest request) {

        AgentConnection agent = nanoLinkServer.getAgentByHostname(hostname);
        if (agent == null) {
            return ResponseEntity.notFound().build();
        }

        try {
            log.info("Killing process {} on {}", request.pid(), hostname);
            agent.sendCommand(Command.processKill(String.valueOf(request.pid())));
            return ResponseEntity.ok(new CommandResponse(true, "Process kill command sent"));
        } catch (Exception e) {
            log.error("Failed to kill process on {}", hostname, e);
            return ResponseEntity.internalServerError()
                    .body(new CommandResponse(false, "Failed: " + e.getMessage()));
        }
    }

    /**
     * Get service status on an agent
     */
    @GetMapping("/agents/{hostname}/service/{serviceName}/status")
    public ResponseEntity<CommandResponse> getServiceStatus(
            @PathVariable String hostname,
            @PathVariable String serviceName) {

        AgentConnection agent = nanoLinkServer.getAgentByHostname(hostname);
        if (agent == null) {
            return ResponseEntity.notFound().build();
        }

        try {
            log.info("Getting service status {} on {}", serviceName, hostname);
            agent.sendCommand(Command.serviceStatus(serviceName));
            return ResponseEntity.ok(new CommandResponse(true, "Service status command sent"));
        } catch (Exception e) {
            log.error("Failed to get service status on {}", hostname, e);
            return ResponseEntity.internalServerError()
                    .body(new CommandResponse(false, "Failed: " + e.getMessage()));
        }
    }

    /**
     * Restart Docker container on an agent
     */
    @PostMapping("/agents/{hostname}/docker/restart")
    public ResponseEntity<CommandResponse> restartContainer(
            @PathVariable String hostname,
            @RequestBody DockerRequest request) {

        AgentConnection agent = nanoLinkServer.getAgentByHostname(hostname);
        if (agent == null) {
            return ResponseEntity.notFound().build();
        }

        try {
            log.info("Restarting container {} on {}", request.containerName(), hostname);
            agent.sendCommand(Command.dockerRestart(request.containerName()));
            return ResponseEntity.ok(new CommandResponse(true, "Container restart command sent"));
        } catch (Exception e) {
            log.error("Failed to restart container on {}", hostname, e);
            return ResponseEntity.internalServerError()
                    .body(new CommandResponse(false, "Failed: " + e.getMessage()));
        }
    }

    // Request/Response DTOs

    record ServiceRequest(String serviceName) {
    }

    record ProcessRequest(int pid) {
    }

    record DockerRequest(String containerName) {
    }

    record CommandResponse(boolean success, String message) {
    }
}
