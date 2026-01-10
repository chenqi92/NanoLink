package nanolink

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"sync"
	"time"
)

// MaxMCPMessageSize is the maximum allowed size of a single MCP message (1MB)
const MaxMCPMessageSize = 1024 * 1024

// DefaultToolTimeout is the default timeout for tool execution
const DefaultToolTimeout = 30 * time.Second

// MCPServer wraps NanoLinkServer with MCP (Model Context Protocol) capabilities.
// This allows AI/LLM applications like Claude Desktop to interact with NanoLink.
type MCPServer struct {
	nano      *Server
	transport MCPTransport
	tools     map[string]*MCPTool
	resources map[string]*MCPResource
	prompts   map[string]*MCPPrompt
	mu        sync.RWMutex
	started   bool
	shutdown  chan struct{}
}

// MCPOption configures the MCP server
type MCPOption func(*MCPServer)

// WithDefaultTools registers the default NanoLink tools
func WithDefaultTools() MCPOption {
	return func(m *MCPServer) {
		m.registerDefaultTools()
	}
}

// WithDefaultResources registers the default NanoLink resources
func WithDefaultResources() MCPOption {
	return func(m *MCPServer) {
		m.registerDefaultResources()
	}
}

// WithDefaultPrompts registers the default troubleshooting prompts
func WithDefaultPrompts() MCPOption {
	return func(m *MCPServer) {
		m.registerDefaultPrompts()
	}
}

// NewMCPServer creates a new MCP server wrapping an existing NanoLink server
func NewMCPServer(nano *Server, opts ...MCPOption) *MCPServer {
	m := &MCPServer{
		nano:      nano,
		transport: NewStdioMCPTransport(),
		tools:     make(map[string]*MCPTool),
		resources: make(map[string]*MCPResource),
		prompts:   make(map[string]*MCPPrompt),
		shutdown:  make(chan struct{}),
	}

	for _, opt := range opts {
		opt(m)
	}

	return m
}

// RegisterTool adds a custom tool to the MCP server
func (m *MCPServer) RegisterTool(tool *MCPTool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.tools[tool.Name] = tool
}

// RegisterResource adds a custom resource to the MCP server
func (m *MCPServer) RegisterResource(resource *MCPResource) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.resources[resource.URI] = resource
}

// RegisterPrompt adds a custom prompt to the MCP server
func (m *MCPServer) RegisterPrompt(prompt *MCPPrompt) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.prompts[prompt.Name] = prompt
}

// ServeStdio runs the MCP server using stdio transport (for Claude Desktop)
func (m *MCPServer) ServeStdio(ctx context.Context) error {
	m.transport = NewStdioMCPTransport()
	return m.serve(ctx)
}

// serve is the main message processing loop
func (m *MCPServer) serve(ctx context.Context) error {
	m.mu.Lock()
	if m.started {
		m.mu.Unlock()
		return fmt.Errorf("MCP server already started")
	}
	m.started = true
	m.mu.Unlock()

	log.Println("MCP server starting...")

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-m.shutdown:
			return nil
		default:
			// Wrap ReadMessage in goroutine for cancellation support
			msgChan := make(chan []byte, 1)
			errChan := make(chan error, 1)
			go func() {
				msg, err := m.transport.ReadMessage()
				if err != nil {
					errChan <- err
					return
				}
				msgChan <- msg
			}()

			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-m.shutdown:
				return nil
			case err := <-errChan:
				if err == io.EOF {
					return nil
				}
				log.Printf("MCP read error: %v", err)
				continue
			case msg := <-msgChan:
				response, err := m.handleMessage(ctx, msg)
				if err != nil {
					log.Printf("MCP handle error: %v", err)
					continue
				}

				if response != nil {
					if err := m.transport.WriteMessage(response); err != nil {
						log.Printf("MCP write error: %v", err)
					}
				}
			}
		}
	}
}

// Stop stops the MCP server
func (m *MCPServer) Stop() {
	close(m.shutdown)
}

// handleMessage processes incoming JSON-RPC messages
func (m *MCPServer) handleMessage(ctx context.Context, data []byte) ([]byte, error) {
	var msg jsonRPCMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return m.errorResponse(nil, -32700, "Parse error", nil)
	}

	if msg.JSONRPC != "2.0" {
		return m.errorResponse(msg.ID, -32600, "Invalid JSON-RPC version", nil)
	}

	switch msg.Method {
	case "initialize":
		return m.handleInitialize(msg)
	case "initialized":
		return nil, nil
	case "tools/list":
		return m.handleToolsList(msg)
	case "tools/call":
		return m.handleToolsCall(ctx, msg)
	case "resources/list":
		return m.handleResourcesList(msg)
	case "resources/read":
		return m.handleResourcesRead(ctx, msg)
	case "prompts/list":
		return m.handlePromptsList(msg)
	case "prompts/get":
		return m.handlePromptsGet(msg)
	case "ping":
		return m.successResponse(msg.ID, map[string]string{})
	default:
		return m.errorResponse(msg.ID, -32601, fmt.Sprintf("Method not found: %s", msg.Method), nil)
	}
}

func (m *MCPServer) handleInitialize(msg jsonRPCMessage) ([]byte, error) {
	result := map[string]interface{}{
		"protocolVersion": "2024-11-05",
		"serverInfo": map[string]string{
			"name":    "nanolink-sdk",
			"version": Version,
		},
		"capabilities": map[string]interface{}{
			"tools":     map[string]interface{}{"listChanged": false},
			"resources": map[string]interface{}{"subscribe": false, "listChanged": false},
			"prompts":   map[string]interface{}{"listChanged": false},
		},
	}
	return m.successResponse(msg.ID, result)
}

func (m *MCPServer) handleToolsList(msg jsonRPCMessage) ([]byte, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	tools := make([]map[string]interface{}, 0, len(m.tools))
	for _, tool := range m.tools {
		tools = append(tools, map[string]interface{}{
			"name":        tool.Name,
			"description": tool.Description,
			"inputSchema": tool.InputSchema,
		})
	}

	return m.successResponse(msg.ID, map[string]interface{}{"tools": tools})
}

func (m *MCPServer) handleToolsCall(ctx context.Context, msg jsonRPCMessage) ([]byte, error) {
	var params struct {
		Name      string                 `json:"name"`
		Arguments map[string]interface{} `json:"arguments"`
	}
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		return m.errorResponse(msg.ID, -32602, "Invalid parameters", nil)
	}

	m.mu.RLock()
	tool, exists := m.tools[params.Name]
	m.mu.RUnlock()

	if !exists {
		return m.errorResponse(msg.ID, -32602, fmt.Sprintf("Unknown tool: %s", params.Name), nil)
	}

	// Execute tool with timeout and panic recovery
	toolCtx, cancel := context.WithTimeout(ctx, DefaultToolTimeout)
	defer cancel()

	var result interface{}
	var toolErr error
	func() {
		defer func() {
			if r := recover(); r != nil {
				toolErr = fmt.Errorf("tool panic: %v", r)
			}
		}()
		result, toolErr = tool.Handler(toolCtx, params.Arguments)
	}()

	if toolErr != nil {
		return m.successResponse(msg.ID, map[string]interface{}{
			"content": []map[string]interface{}{{"type": "text", "text": fmt.Sprintf("Error: %v", toolErr)}},
			"isError": true,
		})
	}

	return m.successResponse(msg.ID, map[string]interface{}{
		"content": formatMCPResult(result),
	})
}

func (m *MCPServer) handleResourcesList(msg jsonRPCMessage) ([]byte, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	resources := make([]map[string]interface{}, 0, len(m.resources))
	for _, res := range m.resources {
		resources = append(resources, map[string]interface{}{
			"uri":         res.URI,
			"name":        res.Name,
			"description": res.Description,
			"mimeType":    res.MimeType,
		})
	}

	return m.successResponse(msg.ID, map[string]interface{}{"resources": resources})
}

func (m *MCPServer) handleResourcesRead(ctx context.Context, msg jsonRPCMessage) ([]byte, error) {
	var params struct {
		URI string `json:"uri"`
	}
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		return m.errorResponse(msg.ID, -32602, "Invalid parameters", nil)
	}

	m.mu.RLock()
	resource, exists := m.resources[params.URI]
	m.mu.RUnlock()

	if !exists {
		return m.errorResponse(msg.ID, -32602, fmt.Sprintf("Unknown resource: %s", params.URI), nil)
	}

	content, err := resource.Handler(ctx, params.URI)
	if err != nil {
		return m.errorResponse(msg.ID, -32603, err.Error(), nil)
	}

	return m.successResponse(msg.ID, map[string]interface{}{
		"contents": []map[string]interface{}{
			{"uri": params.URI, "mimeType": resource.MimeType, "text": string(content)},
		},
	})
}

func (m *MCPServer) handlePromptsList(msg jsonRPCMessage) ([]byte, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	prompts := make([]map[string]interface{}, 0, len(m.prompts))
	for _, prompt := range m.prompts {
		prompts = append(prompts, map[string]interface{}{
			"name":        prompt.Name,
			"description": prompt.Description,
			"arguments":   prompt.Arguments,
		})
	}

	return m.successResponse(msg.ID, map[string]interface{}{"prompts": prompts})
}

func (m *MCPServer) handlePromptsGet(msg jsonRPCMessage) ([]byte, error) {
	var params struct {
		Name      string                 `json:"name"`
		Arguments map[string]interface{} `json:"arguments"`
	}
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		return m.errorResponse(msg.ID, -32602, "Invalid parameters", nil)
	}

	m.mu.RLock()
	prompt, exists := m.prompts[params.Name]
	m.mu.RUnlock()

	if !exists {
		return m.errorResponse(msg.ID, -32602, fmt.Sprintf("Unknown prompt: %s", params.Name), nil)
	}

	messages := prompt.Generator(params.Arguments)
	return m.successResponse(msg.ID, map[string]interface{}{
		"description": prompt.Description,
		"messages":    messages,
	})
}

func (m *MCPServer) successResponse(id interface{}, result interface{}) ([]byte, error) {
	return json.Marshal(jsonRPCMessage{JSONRPC: "2.0", ID: id, Result: result})
}

func (m *MCPServer) errorResponse(id interface{}, code int, message string, data interface{}) ([]byte, error) {
	return json.Marshal(jsonRPCMessage{
		JSONRPC: "2.0",
		ID:      id,
		Error:   &jsonRPCError{Code: code, Message: message, Data: data},
	})
}

// ========================
// Transport
// ========================

// MCPTransport defines the interface for MCP message transport
type MCPTransport interface {
	ReadMessage() ([]byte, error)
	WriteMessage(data []byte) error
	Close() error
}

// StdioMCPTransport implements MCPTransport using stdin/stdout
type StdioMCPTransport struct {
	reader *bufio.Reader
	writer io.Writer
	mu     sync.Mutex
}

// NewStdioMCPTransport creates a new stdio transport
func NewStdioMCPTransport() *StdioMCPTransport {
	return &StdioMCPTransport{
		reader: bufio.NewReader(os.Stdin),
		writer: os.Stdout,
	}
}

func (t *StdioMCPTransport) ReadMessage() ([]byte, error) {
	line, err := t.reader.ReadBytes('\n')
	if err != nil {
		return nil, err
	}
	if len(line) > MaxMCPMessageSize {
		return nil, fmt.Errorf("message too large: %d bytes (max: %d)", len(line), MaxMCPMessageSize)
	}
	return line, nil
}

func (t *StdioMCPTransport) WriteMessage(data []byte) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if len(data) == 0 || data[len(data)-1] != '\n' {
		data = append(data, '\n')
	}
	_, err := t.writer.Write(data)
	return err
}

func (t *StdioMCPTransport) Close() error { return nil }

// ========================
// Types
// ========================

type jsonRPCMessage struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  interface{}     `json:"result,omitempty"`
	Error   *jsonRPCError   `json:"error,omitempty"`
}

type jsonRPCError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// MCPTool represents an MCP tool
type MCPTool struct {
	Name        string
	Description string
	InputSchema map[string]interface{}
	Handler     func(ctx context.Context, args map[string]interface{}) (interface{}, error)
}

// MCPResource represents an MCP resource
type MCPResource struct {
	URI         string
	Name        string
	Description string
	MimeType    string
	Handler     func(ctx context.Context, uri string) ([]byte, error)
}

// MCPPrompt represents an MCP prompt template
type MCPPrompt struct {
	Name        string
	Description string
	Arguments   []map[string]interface{}
	Generator   func(args map[string]interface{}) []map[string]interface{}
}

// ========================
// Default registrations
// ========================

func (m *MCPServer) registerDefaultTools() {
	m.RegisterTool(&MCPTool{
		Name:        "list_agents",
		Description: "List all connected monitoring agents",
		InputSchema: map[string]interface{}{"type": "object", "properties": map[string]interface{}{}},
		Handler: func(ctx context.Context, args map[string]interface{}) (interface{}, error) {
			agents := m.nano.GetAgents()
			result := make([]map[string]interface{}, 0, len(agents))
			for id, agent := range agents {
				result = append(result, map[string]interface{}{
					"id": id, "hostname": agent.Hostname, "os": agent.OS, "arch": agent.Arch,
				})
			}
			return map[string]interface{}{"count": len(result), "agents": result}, nil
		},
	})

	m.RegisterTool(&MCPTool{
		Name:        "get_agent_metrics",
		Description: "Get current metrics for a specific agent",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"agent_id": map[string]interface{}{"type": "string", "description": "Agent ID or hostname"},
			},
			"required": []string{"agent_id"},
		},
		Handler: func(ctx context.Context, args map[string]interface{}) (interface{}, error) {
			agentID, _ := args["agent_id"].(string)
			agent := m.nano.GetAgent(agentID)
			if agent == nil {
				agent = m.nano.GetAgentByHostname(agentID)
			}
			if agent == nil {
				return nil, fmt.Errorf("agent not found: %s", agentID)
			}
			return agent.LastMetrics, nil
		},
	})

	m.RegisterTool(&MCPTool{
		Name:        "get_system_summary",
		Description: "Get a summary of the entire monitored cluster including agent count and average resource usage",
		InputSchema: map[string]interface{}{"type": "object", "properties": map[string]interface{}{}},
		Handler: func(ctx context.Context, args map[string]interface{}) (interface{}, error) {
			agents := m.nano.GetAgents()
			totalCPU := 0.0
			totalMemUsed := uint64(0)
			totalMemTotal := uint64(0)
			count := 0

			for _, agent := range agents {
				if agent.LastMetrics != nil {
					if agent.LastMetrics.CPU != nil {
						totalCPU += agent.LastMetrics.CPU.UsagePercent
					}
					if agent.LastMetrics.Memory != nil {
						totalMemUsed += agent.LastMetrics.Memory.Used
						totalMemTotal += agent.LastMetrics.Memory.Total
					}
					count++
				}
			}

			avgCPU := 0.0
			memPercent := 0.0
			if count > 0 {
				avgCPU = totalCPU / float64(count)
			}
			if totalMemTotal > 0 {
				memPercent = float64(totalMemUsed) / float64(totalMemTotal) * 100
			}

			return map[string]interface{}{
				"agentCount":    len(agents),
				"avgCpuPercent": avgCPU,
				"totalMemory":   totalMemTotal,
				"usedMemory":    totalMemUsed,
				"memoryPercent": memPercent,
			}, nil
		},
	})

	m.RegisterTool(&MCPTool{
		Name:        "find_high_cpu_agents",
		Description: "Find agents with CPU usage above a specified threshold",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"threshold": map[string]interface{}{"type": "number", "description": "CPU threshold percentage (default: 80)", "default": 80},
			},
		},
		Handler: func(ctx context.Context, args map[string]interface{}) (interface{}, error) {
			threshold := 80.0
			if t, ok := args["threshold"].(float64); ok && t > 0 {
				threshold = t
			}
			if threshold < 0 || threshold > 100 {
				return nil, fmt.Errorf("threshold must be between 0 and 100")
			}

			agents := m.nano.GetAgents()
			highCPU := make([]map[string]interface{}, 0)

			for id, agent := range agents {
				if agent.LastMetrics != nil && agent.LastMetrics.CPU != nil && agent.LastMetrics.CPU.UsagePercent > threshold {
					highCPU = append(highCPU, map[string]interface{}{
						"id":       id,
						"hostname": agent.Hostname,
						"cpuUsage": agent.LastMetrics.CPU.UsagePercent,
					})
				}
			}

			return map[string]interface{}{
				"threshold": threshold,
				"count":     len(highCPU),
				"agents":    highCPU,
			}, nil
		},
	})
}

func (m *MCPServer) registerDefaultResources() {
	m.RegisterResource(&MCPResource{
		URI:         "nanolink://agents",
		Name:        "Connected Agents",
		Description: "List of all connected monitoring agents",
		MimeType:    "application/json",
		Handler: func(ctx context.Context, uri string) ([]byte, error) {
			agents := m.nano.GetAgents()
			result := make([]map[string]interface{}, 0, len(agents))
			for id, agent := range agents {
				result = append(result, map[string]interface{}{
					"id": id, "hostname": agent.Hostname, "os": agent.OS, "arch": agent.Arch,
				})
			}
			return json.MarshalIndent(map[string]interface{}{"count": len(result), "agents": result}, "", "  ")
		},
	})
}

func (m *MCPServer) registerDefaultPrompts() {
	m.RegisterPrompt(&MCPPrompt{
		Name:        "troubleshoot_agent",
		Description: "Troubleshoot a specific agent",
		Arguments: []map[string]interface{}{
			{"name": "agent_id", "description": "Agent ID to troubleshoot", "required": true},
		},
		Generator: func(args map[string]interface{}) []map[string]interface{} {
			agentID, _ := args["agent_id"].(string)
			return []map[string]interface{}{
				{"role": "user", "content": map[string]interface{}{
					"type": "text",
					"text": fmt.Sprintf("Please troubleshoot agent: %s\n\n1. Use list_agents to verify connection\n2. Use get_agent_metrics to check current status\n3. Analyze and provide recommendations", agentID),
				}},
			}
		},
	})
}

func formatMCPResult(result interface{}) []map[string]interface{} {
	switch v := result.(type) {
	case string:
		return []map[string]interface{}{{"type": "text", "text": v}}
	default:
		data, _ := json.MarshalIndent(v, "", "  ")
		return []map[string]interface{}{{"type": "text", "text": string(data)}}
	}
}
