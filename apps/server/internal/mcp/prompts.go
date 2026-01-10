package mcp

import (
	"fmt"
)

// Prompt represents an MCP prompt template
type Prompt struct {
	Name        string
	Description string
	Arguments   []PromptArgument
	Generator   func(args map[string]interface{}) []PromptMessage
}

// PromptArgument describes an argument for a prompt
type PromptArgument struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Required    bool   `json:"required"`
}

// PromptMessage represents a message in the prompt
type PromptMessage struct {
	Role    string        `json:"role"`
	Content PromptContent `json:"content"`
}

// PromptContent represents the content of a prompt message
type PromptContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// registerDefaultPrompts registers the default NanoLink prompts
func (s *Server) registerDefaultPrompts() {
	// diagnose_high_cpu - Diagnose high CPU usage
	s.RegisterPrompt(&Prompt{
		Name:        "diagnose_high_cpu",
		Description: "Guide for diagnosing agents with high CPU usage. Provides step-by-step instructions to identify and resolve CPU-related issues.",
		Arguments: []PromptArgument{
			{
				Name:        "agent_id",
				Description: "Optional: Specific agent ID to diagnose. If not provided, will check all agents.",
				Required:    false,
			},
			{
				Name:        "threshold",
				Description: "CPU usage threshold percentage to consider as 'high' (default: 80)",
				Required:    false,
			},
		},
		Generator: s.promptDiagnoseHighCPU,
	})

	// diagnose_disk_full - Diagnose low disk space
	s.RegisterPrompt(&Prompt{
		Name:        "diagnose_disk_full",
		Description: "Guide for diagnosing agents with low disk space. Provides recommendations for freeing up disk space.",
		Arguments: []PromptArgument{
			{
				Name:        "agent_id",
				Description: "Optional: Specific agent ID to diagnose.",
				Required:    false,
			},
		},
		Generator: s.promptDiagnoseDiskFull,
	})

	// troubleshoot_agent - General agent troubleshooting
	s.RegisterPrompt(&Prompt{
		Name:        "troubleshoot_agent",
		Description: "General troubleshooting guide for a specific agent. Collects system information and suggests potential issues.",
		Arguments: []PromptArgument{
			{
				Name:        "agent_id",
				Description: "The agent ID to troubleshoot",
				Required:    true,
			},
		},
		Generator: s.promptTroubleshootAgent,
	})

	// cluster_health_report - Generate cluster health report
	s.RegisterPrompt(&Prompt{
		Name:        "cluster_health_report",
		Description: "Generate a comprehensive health report for the entire monitored cluster.",
		Arguments:   []PromptArgument{},
		Generator:   s.promptClusterHealthReport,
	})
}

// Prompt generators

func (s *Server) promptDiagnoseHighCPU(args map[string]interface{}) []PromptMessage {
	agentID := ""
	if id, ok := args["agent_id"].(string); ok {
		agentID = id
	}

	threshold := 80.0
	if t, ok := args["threshold"].(float64); ok {
		threshold = t
	}

	var instructions string
	if agentID != "" {
		instructions = fmt.Sprintf(`You are helping diagnose high CPU usage for agent: %s

Please follow these steps:

1. First, use the 'get_agent_metrics' tool to get current metrics for this agent
2. Check if CPU usage is above %.0f%%
3. If high, use the 'get_agent_processes' tool to identify top CPU-consuming processes
4. Analyze the process list and provide recommendations:
   - Are there any runaway processes?
   - Is the load expected (build tasks, data processing)?
   - Are there zombie processes?
5. Suggest remediation steps based on findings

Start by getting the current metrics for agent '%s'.`, agentID, threshold, agentID)
	} else {
		instructions = fmt.Sprintf(`You are helping diagnose high CPU usage across the cluster.

Please follow these steps:

1. Use the 'find_high_cpu_agents' tool with threshold %.0f%% to find affected agents
2. For each affected agent:
   a. Get detailed metrics using 'get_agent_metrics'
   b. Analyze CPU patterns (steady high vs spikes)
3. Identify common patterns across agents
4. Provide prioritized recommendations for each affected agent

Start by finding agents with high CPU usage.`, threshold)
	}

	return []PromptMessage{
		{
			Role: "user",
			Content: PromptContent{
				Type: "text",
				Text: instructions,
			},
		},
	}
}

func (s *Server) promptDiagnoseDiskFull(args map[string]interface{}) []PromptMessage {
	agentID := ""
	if id, ok := args["agent_id"].(string); ok {
		agentID = id
	}

	var instructions string
	if agentID != "" {
		instructions = fmt.Sprintf(`You are helping diagnose low disk space for agent: %s

Please follow these steps:

1. Use 'get_agent_metrics' to get current disk metrics for this agent
2. Identify which mount points are running low on space
3. Provide recommendations:
   - Common directories to clean (logs, caches, temp files)
   - Files to check for large sizes
   - Whether disk expansion might be needed
4. Suggest safe cleanup commands if applicable

Start by getting the current metrics for agent '%s'.`, agentID, agentID)
	} else {
		instructions = `You are helping diagnose low disk space across the cluster.

Please follow these steps:

1. Use 'find_low_disk_agents' tool to find agents with disk usage above 90%
2. For each affected agent:
   a. Get detailed disk metrics
   b. Identify specific mount points that are full
3. Prioritize agents by severity (closest to 100%)
4. Provide recommendations for each affected agent

Start by finding agents with low disk space.`
	}

	return []PromptMessage{
		{
			Role: "user",
			Content: PromptContent{
				Type: "text",
				Text: instructions,
			},
		},
	}
}

func (s *Server) promptTroubleshootAgent(args map[string]interface{}) []PromptMessage {
	agentID := ""
	if id, ok := args["agent_id"].(string); ok {
		agentID = id
	}

	if agentID == "" {
		return []PromptMessage{
			{
				Role: "user",
				Content: PromptContent{
					Type: "text",
					Text: "Please provide an agent_id to troubleshoot. You can use 'list_agents' tool to see available agents.",
				},
			},
		}
	}

	instructions := fmt.Sprintf(`You are troubleshooting agent: %s

Please perform a comprehensive health check:

1. **Basic Connectivity**
   - Use 'list_agents' to verify the agent is connected
   - Note connection time and version

2. **Resource Usage**
   - Use 'get_agent_metrics' to get current metrics
   - Check CPU, memory, disk, and network status
   - Flag any resources above 80%% utilization

3. **Analysis**
   Based on the collected data, identify:
   - Any immediate issues requiring attention
   - Potential problems that may develop
   - Overall health status

4. **Recommendations**
   Provide actionable recommendations prioritized by severity

Start by verifying the agent is connected and then get its current metrics.`, agentID)

	return []PromptMessage{
		{
			Role: "user",
			Content: PromptContent{
				Type: "text",
				Text: instructions,
			},
		},
	}
}

func (s *Server) promptClusterHealthReport(args map[string]interface{}) []PromptMessage {
	instructions := `Generate a comprehensive health report for the monitored cluster.

Please follow these steps:

1. **Cluster Overview**
   - Use 'list_agents' to get all connected agents
   - Use 'get_system_summary' to get cluster-wide statistics

2. **Resource Analysis**
   - Check for high CPU usage agents (threshold: 80%)
   - Check for low disk space agents (threshold: 85%)
   - Identify any memory pressure

3. **Agent Status**
   For each agent, briefly note:
   - Connection status
   - Key metrics (CPU, memory, disk)
   - Any alerts or concerns

4. **Summary Report**
   Provide:
   - Executive summary (1-2 sentences)
   - Number of healthy/warning/critical agents
   - Top 3 issues requiring attention
   - Recommended actions

Format the report in a clear, structured manner suitable for stakeholder review.

Start by getting the cluster overview.`

	return []PromptMessage{
		{
			Role: "user",
			Content: PromptContent{
				Type: "text",
				Text: instructions,
			},
		},
	}
}
