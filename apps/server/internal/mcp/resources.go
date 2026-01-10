package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// Resource represents an MCP resource that AI can read
type Resource struct {
	URI         string
	Name        string
	Description string
	MimeType    string
	Handler     func(ctx context.Context, uri string) ([]byte, error)
}

// registerDefaultResources registers the default NanoLink resources
func (s *Server) registerDefaultResources() {
	// nanolink://agents - List of all connected agents
	s.RegisterResource(&Resource{
		URI:         "nanolink://agents",
		Name:        "Connected Agents",
		Description: "List of all currently connected monitoring agents with their basic information.",
		MimeType:    "application/json",
		Handler:     s.resourceAgents,
	})

	// nanolink://summary - Cluster summary
	s.RegisterResource(&Resource{
		URI:         "nanolink://summary",
		Name:        "Cluster Summary",
		Description: "Aggregated summary of the monitored cluster including agent count and average resource usage.",
		MimeType:    "application/json",
		Handler:     s.resourceSummary,
	})

	// nanolink://metrics - All current metrics
	s.RegisterResource(&Resource{
		URI:         "nanolink://metrics",
		Name:        "All Metrics",
		Description: "Current metrics from all connected agents.",
		MimeType:    "application/json",
		Handler:     s.resourceAllMetrics,
	})
}

// Resource handlers

func (s *Server) resourceAgents(ctx context.Context, uri string) ([]byte, error) {
	agents := s.agentService.GetAllAgents()

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

	result := map[string]interface{}{
		"count":  len(agentList),
		"agents": agentList,
	}

	return json.MarshalIndent(result, "", "  ")
}

func (s *Server) resourceSummary(ctx context.Context, uri string) ([]byte, error) {
	summary := s.metricsService.GetSummary()
	return json.MarshalIndent(summary, "", "  ")
}

func (s *Server) resourceAllMetrics(ctx context.Context, uri string) ([]byte, error) {
	allMetrics := s.metricsService.GetAllCurrentMetrics()
	return json.MarshalIndent(allMetrics, "", "  ")
}

// parseAgentURI extracts agent ID from URIs like nanolink://agents/{id}/metrics
func parseAgentURI(uri string) (agentID string, subResource string, ok bool) {
	// Remove protocol prefix
	path := strings.TrimPrefix(uri, "nanolink://")

	// Split path
	parts := strings.Split(path, "/")
	if len(parts) < 2 || parts[0] != "agents" {
		return "", "", false
	}

	agentID = parts[1]
	if len(parts) > 2 {
		subResource = parts[2]
	}

	return agentID, subResource, true
}

// GetDynamicResource handles dynamic resource URIs
func (s *Server) GetDynamicResource(ctx context.Context, uri string) ([]byte, error) {
	agentID, subResource, ok := parseAgentURI(uri)
	if !ok {
		return nil, fmt.Errorf("invalid resource URI: %s", uri)
	}

	switch subResource {
	case "metrics":
		metrics := s.metricsService.GetCurrentMetrics(agentID)
		if metrics == nil {
			return nil, fmt.Errorf("no metrics found for agent: %s", agentID)
		}
		return json.MarshalIndent(metrics, "", "  ")

	case "static":
		// Static info would need to be retrieved from stored data
		agent := s.agentService.GetAgent(agentID)
		if agent == nil {
			return nil, fmt.Errorf("agent not found: %s", agentID)
		}
		staticInfo := map[string]interface{}{
			"hostname": agent.Hostname,
			"os":       agent.OS,
			"arch":     agent.Arch,
			"version":  agent.Version,
		}
		return json.MarshalIndent(staticInfo, "", "  ")

	default:
		return nil, fmt.Errorf("unknown sub-resource: %s", subResource)
	}
}
