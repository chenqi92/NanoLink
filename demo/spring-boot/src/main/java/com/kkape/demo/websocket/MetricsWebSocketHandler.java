package com.kkape.demo.websocket;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.kkape.demo.model.AgentMetrics;
import com.kkape.demo.model.AgentInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.IOException;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * WebSocket handler for real-time metrics streaming to dashboard
 */
@Component
public class MetricsWebSocketHandler extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(MetricsWebSocketHandler.class);

    private final Set<WebSocketSession> sessions = ConcurrentHashMap.newKeySet();
    private final ObjectMapper objectMapper;

    public MetricsWebSocketHandler() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        sessions.add(session);
        log.info("WebSocket connected: {} (total: {})", session.getId(), sessions.size());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        sessions.remove(session);
        log.info("WebSocket disconnected: {} (total: {})", session.getId(), sessions.size());
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) {
        // Handle incoming messages if needed (e.g., commands)
        log.debug("Received message: {}", message.getPayload());
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        log.error("WebSocket error for session {}: {}", session.getId(), exception.getMessage());
        sessions.remove(session);
    }

    /**
     * Broadcast metrics update to all connected clients
     */
    public void broadcastMetrics(String agentId, AgentMetrics metrics) {
        if (sessions.isEmpty()) {
            return;
        }

        try {
            MetricsMessage message = new MetricsMessage("metrics", agentId, metrics);
            String json = objectMapper.writeValueAsString(message);
            TextMessage textMessage = new TextMessage(json);

            for (WebSocketSession session : sessions) {
                if (session.isOpen()) {
                    try {
                        session.sendMessage(textMessage);
                    } catch (IOException e) {
                        log.warn("Failed to send to session {}: {}", session.getId(), e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Failed to broadcast metrics: {}", e.getMessage());
        }
    }

    /**
     * Broadcast agent connect event
     */
    public void broadcastAgentConnect(AgentInfo agent) {
        broadcast(new AgentEventMessage("agent_connect", agent));
    }

    /**
     * Broadcast agent disconnect event
     */
    public void broadcastAgentDisconnect(AgentInfo agent) {
        broadcast(new AgentEventMessage("agent_disconnect", agent));
    }

    private void broadcast(Object message) {
        if (sessions.isEmpty()) {
            return;
        }

        try {
            String json = objectMapper.writeValueAsString(message);
            TextMessage textMessage = new TextMessage(json);

            for (WebSocketSession session : sessions) {
                if (session.isOpen()) {
                    try {
                        session.sendMessage(textMessage);
                    } catch (IOException e) {
                        log.warn("Failed to send to session {}: {}", session.getId(), e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Failed to broadcast message: {}", e.getMessage());
        }
    }

    public int getConnectedClients() {
        return sessions.size();
    }

    // Message DTOs
    record MetricsMessage(String type, String agentId, AgentMetrics metrics) {}
    record AgentEventMessage(String type, AgentInfo agent) {}
}
