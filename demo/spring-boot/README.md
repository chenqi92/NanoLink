# NanoLink Spring Boot Demo

This demo shows how to integrate NanoLink SDK with Spring Boot to create a monitoring server that receives metrics from agents.

## Features

- Receives real-time metrics from NanoLink agents
- REST API for querying agents and metrics
- Built-in NanoLink dashboard
- Alert logging for high resource usage
- Command execution on remote agents

## Prerequisites

- Java 17+
- Maven 3.8+
- NanoLink SDK (built from parent project)

## Quick Start

### 1. Build the SDK first

```bash
cd ../../sdk/java
mvn clean install
```

### 2. Run the demo

```bash
cd ../../demo/spring-boot
mvn spring-boot:run
```

### 3. Access the services

- **REST API**: http://localhost:8080
- **NanoLink Dashboard**: http://localhost:9100
- **Actuator**: http://localhost:8080/actuator

## Configuration

Edit `src/main/resources/application.yml`:

```yaml
nanolink:
  server:
    port: 9100           # Agent connection port
    dashboard:
      enabled: true      # Enable built-in dashboard
    token: "your-token"  # Authentication token (empty = accept all)
```

## API Endpoints

### Agents

```bash
# List all connected agents
curl http://localhost:8080/api/agents

# Get metrics for specific agent
curl http://localhost:8080/api/agents/{agentId}/metrics
```

### Metrics

```bash
# Get all latest metrics
curl http://localhost:8080/api/metrics

# Get cluster summary
curl http://localhost:8080/api/summary
```

### Commands

```bash
# Restart a service
curl -X POST http://localhost:8080/api/commands/agents/{hostname}/service/restart \
  -H "Content-Type: application/json" \
  -d '{"serviceName": "nginx"}'

# Kill a process
curl -X POST http://localhost:8080/api/commands/agents/{hostname}/process/kill \
  -H "Content-Type: application/json" \
  -d '{"pid": 1234}'

# Restart Docker container
curl -X POST http://localhost:8080/api/commands/agents/{hostname}/docker/restart \
  -H "Content-Type: application/json" \
  -d '{"containerName": "my-app"}'
```

## Project Structure

```
spring-boot/
├── src/main/java/io/nanolink/demo/
│   ├── NanoLinkDemoApplication.java    # Main application
│   ├── config/
│   │   └── NanoLinkConfig.java         # NanoLink server configuration
│   ├── controller/
│   │   ├── MetricsController.java      # Metrics REST API
│   │   └── CommandController.java      # Command REST API
│   ├── model/
│   │   ├── AgentInfo.java              # Agent information record
│   │   └── AgentMetrics.java           # Metrics data record
│   └── service/
│       └── MetricsService.java         # Metrics processing service
├── src/main/resources/
│   └── application.yml                 # Configuration
└── pom.xml                             # Maven configuration
```

## How It Works

1. **NanoLinkConfig** creates and starts a NanoLink server on the configured port
2. When agents connect, **MetricsService** registers them and stores their info
3. Incoming metrics are processed and stored in memory
4. **MetricsController** exposes REST endpoints to query the data
5. **CommandController** allows sending commands to agents

## Extending the Demo

### Add Prometheus Metrics

```java
@Bean
MeterRegistryCustomizer<MeterRegistry> metricsCommonTags() {
    return registry -> {
        metricsService.getAllLatestMetrics().forEach((agentId, metrics) -> {
            Gauge.builder("agent.cpu.usage", () -> metrics.cpuUsage())
                .tag("agent", agentId)
                .register(registry);
        });
    };
}
```

### Add WebSocket for Real-time Updates

```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {
    // Add STOMP messaging for real-time metric updates
}
```

### Store Metrics in Database

```java
@Entity
public class MetricsRecord {
    @Id
    private Long id;
    private String agentId;
    private Instant timestamp;
    private double cpuUsage;
    private double memoryUsage;
    // ...
}
```

## Production Considerations

1. **Authentication**: Configure a proper token in production
2. **TLS**: Enable TLS for secure agent connections
3. **Persistence**: Store metrics in a time-series database
4. **Scaling**: Use Redis for shared state across instances
5. **Monitoring**: Export metrics to Prometheus/Grafana

## Troubleshooting

### Agent can't connect

1. Check if NanoLink server is running on port 9100
2. Verify the agent's server URL configuration
3. Check firewall rules

### No metrics received

1. Verify agent is connected (check logs or dashboard)
2. Ensure agent has correct permission level
3. Check for errors in agent logs

## License

MIT License - see [LICENSE](../../LICENSE) for details.
