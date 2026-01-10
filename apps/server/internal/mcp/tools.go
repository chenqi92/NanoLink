package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
)

// Tool represents an MCP tool that AI can execute
type Tool struct {
	Name        string
	Description string
	InputSchema map[string]interface{}
	Handler     func(ctx context.Context, args map[string]interface{}) (interface{}, error)
}

// registerDefaultTools registers the default NanoLink tools
func (s *Server) registerDefaultTools() {
	// list_agents - List all connected agents
	s.RegisterTool(&Tool{
		Name:        "list_agents",
		Description: "List all connected monitoring agents with their basic information including hostname, OS, architecture, and connection status.",
		InputSchema: map[string]interface{}{
			"type":       "object",
			"properties": map[string]interface{}{},
			"required":   []string{},
		},
		Handler: s.toolListAgents,
	})

	// get_agent_metrics - Get metrics for a specific agent
	s.RegisterTool(&Tool{
		Name:        "get_agent_metrics",
		Description: "Get current metrics for a specific agent including CPU, memory, disk, and network usage.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"agent_id": map[string]interface{}{
					"type":        "string",
					"description": "The unique identifier or hostname of the agent",
				},
			},
			"required": []string{"agent_id"},
		},
		Handler: s.toolGetAgentMetrics,
	})

	// get_system_summary - Get cluster summary
	s.RegisterTool(&Tool{
		Name:        "get_system_summary",
		Description: "Get a summary of the entire monitored cluster including total agents, average resource usage, and alerts.",
		InputSchema: map[string]interface{}{
			"type":       "object",
			"properties": map[string]interface{}{},
			"required":   []string{},
		},
		Handler: s.toolGetSystemSummary,
	})

	// find_high_cpu_agents - Find agents with high CPU usage
	s.RegisterTool(&Tool{
		Name:        "find_high_cpu_agents",
		Description: "Find agents with CPU usage above a specified threshold percentage.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"threshold": map[string]interface{}{
					"type":        "number",
					"description": "CPU usage threshold percentage (default: 80)",
					"default":     80,
				},
			},
			"required": []string{},
		},
		Handler: s.toolFindHighCpuAgents,
	})

	// find_low_disk_agents - Find agents with low disk space
	s.RegisterTool(&Tool{
		Name:        "find_low_disk_agents",
		Description: "Find agents with disk usage above a specified threshold percentage.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"threshold": map[string]interface{}{
					"type":        "number",
					"description": "Disk usage threshold percentage (default: 90)",
					"default":     90,
				},
			},
			"required": []string{},
		},
		Handler: s.toolFindLowDiskAgents,
	})

	// get_agent_processes - Get process list for an agent
	s.RegisterTool(&Tool{
		Name:        "get_agent_processes",
		Description: "Get the list of running processes on a specific agent, sorted by CPU or memory usage.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"agent_id": map[string]interface{}{
					"type":        "string",
					"description": "The unique identifier or hostname of the agent",
				},
				"sort_by": map[string]interface{}{
					"type":        "string",
					"description": "Sort processes by 'cpu' or 'memory' (default: cpu)",
					"enum":        []string{"cpu", "memory"},
					"default":     "cpu",
				},
				"limit": map[string]interface{}{
					"type":        "integer",
					"description": "Maximum number of processes to return (default: 10)",
					"default":     10,
				},
			},
			"required": []string{"agent_id"},
		},
		Handler: s.toolGetAgentProcesses,
	})
}

// Tool handlers

func (s *Server) toolListAgents(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	agents := s.agentService.GetAllAgents()
	if len(agents) == 0 {
		return map[string]interface{}{
			"message": "No agents currently connected",
			"count":   0,
			"agents":  []interface{}{},
		}, nil
	}

	agentList := make([]map[string]interface{}, 0, len(agents))
	for _, agent := range agents {
		agentList = append(agentList, map[string]interface{}{
			"id":           agent.ID,
			"hostname":     agent.Hostname,
			"os":           agent.OS,
			"arch":         agent.Arch,
			"version":      agent.Version,
			"connected_at": agent.ConnectedAt,
		})
	}

	return map[string]interface{}{
		"count":  len(agentList),
		"agents": agentList,
	}, nil
}

func (s *Server) toolGetAgentMetrics(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	agentID, ok := args["agent_id"].(string)
	if !ok || agentID == "" {
		return nil, fmt.Errorf("agent_id is required")
	}

	metrics := s.metricsService.GetCurrentMetrics(agentID)
	if metrics == nil {
		// Try to find by hostname
		agent := s.agentService.GetAgentByHostname(agentID)
		if agent != nil {
			metrics = s.metricsService.GetCurrentMetrics(agent.ID)
		}
	}

	if metrics == nil {
		return nil, fmt.Errorf("agent not found or no metrics available: %s", agentID)
	}

	return metrics, nil
}

func (s *Server) toolGetSystemSummary(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	// Use the built-in GetSummary method
	summary := s.metricsService.GetSummary()
	return summary, nil
}

func (s *Server) toolFindHighCpuAgents(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	threshold := 80.0
	if t, ok := args["threshold"].(float64); ok {
		threshold = t
	}

	// Validate threshold
	if threshold < 0 || threshold > 100 {
		return nil, fmt.Errorf("threshold must be between 0 and 100, got: %.1f", threshold)
	}

	allMetrics := s.metricsService.GetAllCurrentMetrics()
	highCpuAgents := make([]map[string]interface{}, 0)

	for agentID, m := range allMetrics {
		if m.CPU.UsagePercent >= threshold {
			// Get hostname from agent service
			hostname := agentID
			if agent := s.agentService.GetAgent(agentID); agent != nil {
				hostname = agent.Hostname
			}
			highCpuAgents = append(highCpuAgents, map[string]interface{}{
				"agent_id":  agentID,
				"hostname":  hostname,
				"cpu_usage": fmt.Sprintf("%.1f%%", m.CPU.UsagePercent),
			})
		}
	}

	if len(highCpuAgents) == 0 {
		return map[string]interface{}{
			"message":   fmt.Sprintf("No agents found with CPU usage above %.0f%%", threshold),
			"threshold": threshold,
			"agents":    []interface{}{},
		}, nil
	}

	return map[string]interface{}{
		"message":   fmt.Sprintf("Found %d agents with CPU usage above %.0f%%", len(highCpuAgents), threshold),
		"threshold": threshold,
		"count":     len(highCpuAgents),
		"agents":    highCpuAgents,
	}, nil
}

func (s *Server) toolFindLowDiskAgents(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	threshold := 90.0
	if t, ok := args["threshold"].(float64); ok {
		threshold = t
	}

	// Validate threshold
	if threshold < 0 || threshold > 100 {
		return nil, fmt.Errorf("threshold must be between 0 and 100, got: %.1f", threshold)
	}

	allMetrics := s.metricsService.GetAllCurrentMetrics()
	lowDiskAgents := make([]map[string]interface{}, 0)

	for agentID, m := range allMetrics {
		for _, disk := range m.Disks {
			if disk.Total > 0 {
				usage := float64(disk.Used) / float64(disk.Total) * 100
				if usage >= threshold {
					lowDiskAgents = append(lowDiskAgents, map[string]interface{}{
						"agent_id":    agentID,
						"mount_point": disk.MountPoint,
						"disk_usage":  fmt.Sprintf("%.1f%%", usage),
						"total_gb":    fmt.Sprintf("%.1f GB", float64(disk.Total)/1024/1024/1024),
						"used_gb":     fmt.Sprintf("%.1f GB", float64(disk.Used)/1024/1024/1024),
					})
				}
			}
		}
	}

	if len(lowDiskAgents) == 0 {
		return map[string]interface{}{
			"message":   fmt.Sprintf("No agents found with disk usage above %.0f%%", threshold),
			"threshold": threshold,
			"agents":    []interface{}{},
		}, nil
	}

	return map[string]interface{}{
		"message":   fmt.Sprintf("Found %d disk(s) with usage above %.0f%%", len(lowDiskAgents), threshold),
		"threshold": threshold,
		"count":     len(lowDiskAgents),
		"agents":    lowDiskAgents,
	}, nil
}

func (s *Server) toolGetAgentProcesses(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	agentID, ok := args["agent_id"].(string)
	if !ok || agentID == "" {
		return nil, fmt.Errorf("agent_id is required")
	}

	// Note: This would require sending a command to the agent
	// For now, return a placeholder indicating this needs gRPC command execution
	return map[string]interface{}{
		"message":  "Process listing requires sending a command to the agent",
		"agent_id": agentID,
		"note":     "Use the execute_command tool with PROCESS_LIST command type",
	}, nil
}

// SchemaToJSON converts the tool's InputSchema to JSON bytes
func (t *Tool) SchemaToJSON() json.RawMessage {
	data, _ := json.Marshal(t.InputSchema)
	return data
}

// ========================
// NEW TOOLS: Audit, DataRequest
// ========================

// registerAuditTools registers audit-related tools (only if AuditService is available)
func (s *Server) registerAuditTools() {
	if s.auditService == nil {
		return
	}

	// query_audit_logs - Query audit logs
	s.RegisterTool(&Tool{
		Name:        "query_audit_logs",
		Description: "Query audit logs with optional filtering by user, agent, command type, or time range.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"agent_id": map[string]interface{}{
					"type":        "string",
					"description": "Filter by agent ID (optional)",
				},
				"command_type": map[string]interface{}{
					"type":        "string",
					"description": "Filter by command type (optional)",
				},
				"limit": map[string]interface{}{
					"type":        "number",
					"description": "Maximum number of logs to return (default: 50)",
					"default":     50,
				},
			},
			"required": []string{},
		},
		Handler: s.toolQueryAuditLogs,
	})

	// get_audit_stats - Get audit statistics
	s.RegisterTool(&Tool{
		Name:        "get_audit_stats",
		Description: "Get audit log statistics including total commands, success/failure counts, and top command types.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"hours": map[string]interface{}{
					"type":        "number",
					"description": "Number of hours to look back (default: 24)",
					"default":     24,
				},
			},
			"required": []string{},
		},
		Handler: s.toolGetAuditStats,
	})
}

// registerDataRequestTools registers data request tools (only if gRPC server is available)
func (s *Server) registerDataRequestTools() {
	if s.grpcServer == nil {
		return
	}

	// request_agent_data - Request specific data from an agent
	s.RegisterTool(&Tool{
		Name:        "request_agent_data",
		Description: "Request specific data from an agent. Types: full, static, disk_usage, network_info, user_sessions, gpu_info, health.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"agent_id": map[string]interface{}{
					"type":        "string",
					"description": "The agent ID to request data from",
				},
				"request_type": map[string]interface{}{
					"type":        "string",
					"description": "Type of data to request: full, static, disk_usage, network_info, user_sessions, gpu_info, health",
					"enum":        []string{"full", "static", "disk_usage", "network_info", "user_sessions", "gpu_info", "health"},
				},
			},
			"required": []string{"agent_id", "request_type"},
		},
		Handler: s.toolRequestAgentData,
	})
}

func (s *Server) toolQueryAuditLogs(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	if s.auditService == nil {
		return nil, fmt.Errorf("audit service not available")
	}

	limit := 50
	if l, ok := args["limit"].(float64); ok && l > 0 {
		limit = int(l)
	}
	if limit > 200 {
		limit = 200
	}

	query := service.AuditQuery{
		Limit: limit,
	}

	if agentID, ok := args["agent_id"].(string); ok && agentID != "" {
		query.AgentID = agentID
	}
	if cmdType, ok := args["command_type"].(string); ok && cmdType != "" {
		query.CommandType = cmdType
	}

	result, err := s.auditService.QueryLogs(query)
	if err != nil {
		return nil, fmt.Errorf("failed to query audit logs: %v", err)
	}

	// Convert logs to simpler format for AI
	logs := make([]map[string]interface{}, 0, len(result.Logs))
	for _, log := range result.Logs {
		logs = append(logs, map[string]interface{}{
			"timestamp":    log.Timestamp.Format("2006-01-02 15:04:05"),
			"username":     log.Username,
			"agent_id":     log.AgentID,
			"command_type": log.CommandType,
			"target":       log.Target,
			"success":      log.Success,
			"error":        log.Error,
		})
	}

	return map[string]interface{}{
		"total":   result.Total,
		"limit":   result.Limit,
		"hasMore": result.HasMore,
		"logs":    logs,
	}, nil
}

func (s *Server) toolGetAuditStats(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	if s.auditService == nil {
		return nil, fmt.Errorf("audit service not available")
	}

	hours := 24.0
	if h, ok := args["hours"].(float64); ok && h > 0 {
		hours = h
	}

	since := time.Now().Add(-time.Duration(hours) * time.Hour)
	stats, err := s.auditService.GetAuditStats(since)
	if err != nil {
		return nil, fmt.Errorf("failed to get audit stats: %v", err)
	}

	return map[string]interface{}{
		"period_hours":        hours,
		"total_commands":      stats.TotalCommands,
		"successful_commands": stats.SuccessfulCommands,
		"failed_commands":     stats.FailedCommands,
		"unique_users":        stats.UniqueUsers,
		"unique_agents":       stats.UniqueAgents,
		"top_command_types":   stats.TopCommandTypes,
	}, nil
}

func (s *Server) toolRequestAgentData(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	if s.grpcServer == nil {
		return nil, fmt.Errorf("gRPC server not available")
	}

	agentID, ok := args["agent_id"].(string)
	if !ok || agentID == "" {
		return nil, fmt.Errorf("agent_id is required")
	}

	requestType, ok := args["request_type"].(string)
	if !ok || requestType == "" {
		return nil, fmt.Errorf("request_type is required")
	}

	// Map string to proto enum
	reqType := s.mapRequestType(requestType)

	err := s.grpcServer.RequestDataFromAgent(agentID, reqType, "")
	if err != nil {
		return nil, fmt.Errorf("failed to send data request: %v", err)
	}

	return map[string]interface{}{
		"success":      true,
		"agent_id":     agentID,
		"request_type": requestType,
		"message":      "Data request sent to agent. Results will be available shortly via get_agent_metrics.",
	}, nil
}

// mapRequestType maps string to proto DataRequestType
func (s *Server) mapRequestType(reqType string) pb.DataRequestType {
	switch reqType {
	case "full":
		return pb.DataRequestType_DATA_REQUEST_FULL
	case "static":
		return pb.DataRequestType_DATA_REQUEST_STATIC
	case "disk_usage":
		return pb.DataRequestType_DATA_REQUEST_DISK_USAGE
	case "network_info":
		return pb.DataRequestType_DATA_REQUEST_NETWORK_INFO
	case "user_sessions":
		return pb.DataRequestType_DATA_REQUEST_USER_SESSIONS
	case "gpu_info":
		return pb.DataRequestType_DATA_REQUEST_GPU_INFO
	case "health":
		return pb.DataRequestType_DATA_REQUEST_HEALTH
	default:
		return pb.DataRequestType_DATA_REQUEST_FULL
	}
}
