package com.kkape.demo.config;

import com.kkape.demo.websocket.MetricsWebSocketHandler;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/**
 * WebSocket configuration for real-time metrics streaming
 */
@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    private final MetricsWebSocketHandler metricsWebSocketHandler;

    public WebSocketConfig(MetricsWebSocketHandler metricsWebSocketHandler) {
        this.metricsWebSocketHandler = metricsWebSocketHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(metricsWebSocketHandler, "/ws")
                .setAllowedOrigins("*");
    }
}
