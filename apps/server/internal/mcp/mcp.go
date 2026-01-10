// Package mcp implements the Model Context Protocol (MCP) server for NanoLink.
// MCP enables AI/LLM applications to interact with NanoLink for intelligent operations.
package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"go.uber.org/zap"
)

// Server represents the MCP server
type Server struct {
	agentService   *service.AgentService
	metricsService *service.MetricsService
	auditService   *service.AuditService
	grpcServer     *grpcserver.Server
	transport      Transport
	logger         *zap.SugaredLogger

	tools     map[string]*Tool
	resources map[string]*Resource
	prompts   map[string]*Prompt

	mu       sync.RWMutex
	started  bool
	shutdown chan struct{}
}

// ServerInfo contains MCP server metadata
type ServerInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

// Capabilities describes what the MCP server supports
type Capabilities struct {
	Tools     *ToolsCapability     `json:"tools,omitempty"`
	Resources *ResourcesCapability `json:"resources,omitempty"`
	Prompts   *PromptsCapability   `json:"prompts,omitempty"`
}

// ToolsCapability describes tools support
type ToolsCapability struct {
	ListChanged bool `json:"listChanged,omitempty"`
}

// ResourcesCapability describes resources support
type ResourcesCapability struct {
	Subscribe   bool `json:"subscribe,omitempty"`
	ListChanged bool `json:"listChanged,omitempty"`
}

// PromptsCapability describes prompts support
type PromptsCapability struct {
	ListChanged bool `json:"listChanged,omitempty"`
}

// Option configures the MCP server
type Option func(*Server)

// WithTransport sets the transport for the MCP server
func WithTransport(t Transport) Option {
	return func(s *Server) {
		s.transport = t
	}
}

// WithAuditService sets the audit service for the MCP server
func WithAuditService(as *service.AuditService) Option {
	return func(s *Server) {
		s.auditService = as
	}
}

// WithGRPCServer sets the gRPC server for the MCP server
func WithGRPCServer(gs *grpcserver.Server) Option {
	return func(s *Server) {
		s.grpcServer = gs
	}
}

// NewServer creates a new MCP server
func NewServer(
	agentService *service.AgentService,
	metricsService *service.MetricsService,
	logger *zap.SugaredLogger,
	opts ...Option,
) *Server {
	s := &Server{
		agentService:   agentService,
		metricsService: metricsService,
		logger:         logger,
		tools:          make(map[string]*Tool),
		resources:      make(map[string]*Resource),
		prompts:        make(map[string]*Prompt),
		shutdown:       make(chan struct{}),
	}

	for _, opt := range opts {
		opt(s)
	}

	// Register default tools, resources, and prompts
	s.registerDefaultTools()
	s.registerDefaultResources()
	s.registerDefaultPrompts()

	// Register optional tools based on available services
	s.registerAuditTools()
	s.registerDataRequestTools()

	return s
}

// RegisterTool registers a tool with the MCP server
func (s *Server) RegisterTool(tool *Tool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tools[tool.Name] = tool
}

// RegisterResource registers a resource with the MCP server
func (s *Server) RegisterResource(resource *Resource) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.resources[resource.URI] = resource
}

// RegisterPrompt registers a prompt with the MCP server
func (s *Server) RegisterPrompt(prompt *Prompt) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.prompts[prompt.Name] = prompt
}

// Serve starts the MCP server and processes messages
func (s *Server) Serve(ctx context.Context) error {
	if s.transport == nil {
		return fmt.Errorf("no transport configured")
	}

	s.mu.Lock()
	if s.started {
		s.mu.Unlock()
		return fmt.Errorf("server already started")
	}
	s.started = true
	s.mu.Unlock()

	s.logger.Info("MCP server starting...")

	for {
		select {
		case <-ctx.Done():
			s.logger.Info("MCP server shutting down (context cancelled)")
			return ctx.Err()
		case <-s.shutdown:
			s.logger.Info("MCP server shutting down")
			return nil
		default:
			// ReadMessage should be blocking, but we wrap in goroutine for cancellation
			msgChan := make(chan []byte, 1)
			errChan := make(chan error, 1)
			go func() {
				msg, err := s.transport.ReadMessage()
				if err != nil {
					errChan <- err
					return
				}
				msgChan <- msg
			}()

			select {
			case <-ctx.Done():
				s.logger.Info("MCP server shutting down (context cancelled)")
				return ctx.Err()
			case <-s.shutdown:
				s.logger.Info("MCP server shutting down")
				return nil
			case err := <-errChan:
				s.logger.Debugf("Failed to read message: %v", err)
				continue
			case msg := <-msgChan:
				response, err := s.handleMessage(ctx, msg)
				if err != nil {
					s.logger.Errorf("Failed to handle message: %v", err)
					continue
				}

				if response != nil {
					if err := s.transport.WriteMessage(response); err != nil {
						s.logger.Errorf("Failed to write response: %v", err)
					}
				}
			}
		}
	}
}

// Stop stops the MCP server
func (s *Server) Stop() {
	close(s.shutdown)
}

// handleMessage processes an incoming JSON-RPC message
func (s *Server) handleMessage(ctx context.Context, data []byte) ([]byte, error) {
	var msg JSONRPCMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return s.errorResponse(nil, ParseError, "Parse error", nil)
	}

	if msg.JSONRPC != "2.0" {
		return s.errorResponse(msg.ID, InvalidRequest, "Invalid JSON-RPC version", nil)
	}

	s.logger.Debugf("Received MCP request: %s", msg.Method)

	switch msg.Method {
	case "initialize":
		return s.handleInitialize(msg)
	case "initialized":
		// Notification, no response needed
		return nil, nil
	case "tools/list":
		return s.handleToolsList(msg)
	case "tools/call":
		return s.handleToolsCall(ctx, msg)
	case "resources/list":
		return s.handleResourcesList(msg)
	case "resources/read":
		return s.handleResourcesRead(ctx, msg)
	case "prompts/list":
		return s.handlePromptsList(msg)
	case "prompts/get":
		return s.handlePromptsGet(msg)
	case "ping":
		return s.successResponse(msg.ID, map[string]string{})
	default:
		return s.errorResponse(msg.ID, MethodNotFound, fmt.Sprintf("Method not found: %s", msg.Method), nil)
	}
}

// handleInitialize handles the initialize request
func (s *Server) handleInitialize(msg JSONRPCMessage) ([]byte, error) {
	result := map[string]interface{}{
		"protocolVersion": "2024-11-05",
		"serverInfo": ServerInfo{
			Name:    "nanolink",
			Version: "0.3.1",
		},
		"capabilities": Capabilities{
			Tools: &ToolsCapability{
				ListChanged: false,
			},
			Resources: &ResourcesCapability{
				Subscribe:   false,
				ListChanged: false,
			},
			Prompts: &PromptsCapability{
				ListChanged: false,
			},
		},
	}
	return s.successResponse(msg.ID, result)
}

// handleToolsList returns the list of available tools
func (s *Server) handleToolsList(msg JSONRPCMessage) ([]byte, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	tools := make([]map[string]interface{}, 0, len(s.tools))
	for _, tool := range s.tools {
		tools = append(tools, map[string]interface{}{
			"name":        tool.Name,
			"description": tool.Description,
			"inputSchema": tool.InputSchema,
		})
	}

	return s.successResponse(msg.ID, map[string]interface{}{
		"tools": tools,
	})
}

// handleToolsCall executes a tool with timeout
func (s *Server) handleToolsCall(ctx context.Context, msg JSONRPCMessage) ([]byte, error) {
	var params struct {
		Name      string                 `json:"name"`
		Arguments map[string]interface{} `json:"arguments"`
	}
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		return s.errorResponse(msg.ID, InvalidParams, "Invalid parameters", nil)
	}

	s.mu.RLock()
	tool, exists := s.tools[params.Name]
	s.mu.RUnlock()

	if !exists {
		return s.errorResponse(msg.ID, InvalidParams, fmt.Sprintf("Unknown tool: %s", params.Name), nil)
	}

	// Execute tool with timeout (30 seconds)
	toolCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	result, err := tool.Handler(toolCtx, params.Arguments)
	if err != nil {
		return s.successResponse(msg.ID, map[string]interface{}{
			"content": []map[string]interface{}{
				{
					"type": "text",
					"text": fmt.Sprintf("Error: %v", err),
				},
			},
			"isError": true,
		})
	}

	// Format result as MCP content
	content := formatToolResult(result)
	return s.successResponse(msg.ID, map[string]interface{}{
		"content": content,
	})
}

// handleResourcesList returns the list of available resources
func (s *Server) handleResourcesList(msg JSONRPCMessage) ([]byte, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	resources := make([]map[string]interface{}, 0, len(s.resources))
	for _, res := range s.resources {
		resources = append(resources, map[string]interface{}{
			"uri":         res.URI,
			"name":        res.Name,
			"description": res.Description,
			"mimeType":    res.MimeType,
		})
	}

	return s.successResponse(msg.ID, map[string]interface{}{
		"resources": resources,
	})
}

// handleResourcesRead reads a resource
func (s *Server) handleResourcesRead(ctx context.Context, msg JSONRPCMessage) ([]byte, error) {
	var params struct {
		URI string `json:"uri"`
	}
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		return s.errorResponse(msg.ID, InvalidParams, "Invalid parameters", nil)
	}

	s.mu.RLock()
	resource, exists := s.resources[params.URI]
	s.mu.RUnlock()

	if !exists {
		return s.errorResponse(msg.ID, InvalidParams, fmt.Sprintf("Unknown resource: %s", params.URI), nil)
	}

	content, err := resource.Handler(ctx, params.URI)
	if err != nil {
		return s.errorResponse(msg.ID, InternalError, err.Error(), nil)
	}

	return s.successResponse(msg.ID, map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"uri":      params.URI,
				"mimeType": resource.MimeType,
				"text":     string(content),
			},
		},
	})
}

// handlePromptsList returns the list of available prompts
func (s *Server) handlePromptsList(msg JSONRPCMessage) ([]byte, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	prompts := make([]map[string]interface{}, 0, len(s.prompts))
	for _, prompt := range s.prompts {
		prompts = append(prompts, map[string]interface{}{
			"name":        prompt.Name,
			"description": prompt.Description,
			"arguments":   prompt.Arguments,
		})
	}

	return s.successResponse(msg.ID, map[string]interface{}{
		"prompts": prompts,
	})
}

// handlePromptsGet returns a specific prompt
func (s *Server) handlePromptsGet(msg JSONRPCMessage) ([]byte, error) {
	var params struct {
		Name      string                 `json:"name"`
		Arguments map[string]interface{} `json:"arguments"`
	}
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		return s.errorResponse(msg.ID, InvalidParams, "Invalid parameters", nil)
	}

	s.mu.RLock()
	prompt, exists := s.prompts[params.Name]
	s.mu.RUnlock()

	if !exists {
		return s.errorResponse(msg.ID, InvalidParams, fmt.Sprintf("Unknown prompt: %s", params.Name), nil)
	}

	messages := prompt.Generator(params.Arguments)
	return s.successResponse(msg.ID, map[string]interface{}{
		"description": prompt.Description,
		"messages":    messages,
	})
}

// successResponse creates a JSON-RPC success response
func (s *Server) successResponse(id interface{}, result interface{}) ([]byte, error) {
	response := JSONRPCMessage{
		JSONRPC: "2.0",
		ID:      id,
		Result:  result,
	}
	return json.Marshal(response)
}

// errorResponse creates a JSON-RPC error response
func (s *Server) errorResponse(id interface{}, code int, message string, data interface{}) ([]byte, error) {
	response := JSONRPCMessage{
		JSONRPC: "2.0",
		ID:      id,
		Error: &JSONRPCError{
			Code:    code,
			Message: message,
			Data:    data,
		},
	}
	return json.Marshal(response)
}

// formatToolResult formats a tool result for MCP response
func formatToolResult(result interface{}) []map[string]interface{} {
	switch v := result.(type) {
	case string:
		return []map[string]interface{}{
			{"type": "text", "text": v},
		}
	case []byte:
		return []map[string]interface{}{
			{"type": "text", "text": string(v)},
		}
	default:
		// JSON encode other types
		jsonBytes, err := json.MarshalIndent(v, "", "  ")
		if err != nil {
			return []map[string]interface{}{
				{"type": "text", "text": fmt.Sprintf("%v", v)},
			}
		}
		return []map[string]interface{}{
			{"type": "text", "text": string(jsonBytes)},
		}
	}
}
