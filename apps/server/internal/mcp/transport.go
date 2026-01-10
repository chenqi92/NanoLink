package mcp

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sync"

	"go.uber.org/zap"
)

// MaxMessageSize is the maximum allowed size of a single MCP message (1MB)
const MaxMessageSize = 1024 * 1024

// Transport defines the interface for MCP message transport
type Transport interface {
	// ReadMessage reads a JSON-RPC message from the transport
	ReadMessage() ([]byte, error)
	// WriteMessage writes a JSON-RPC message to the transport
	WriteMessage(data []byte) error
	// Close closes the transport
	Close() error
}

// StdioTransport implements Transport using stdin/stdout
type StdioTransport struct {
	reader *bufio.Reader
	writer io.Writer
	mu     sync.Mutex
	logger *zap.SugaredLogger
}

// NewStdioTransport creates a new stdio transport
func NewStdioTransport(logger *zap.SugaredLogger) *StdioTransport {
	return &StdioTransport{
		reader: bufio.NewReader(os.Stdin),
		writer: os.Stdout,
		logger: logger,
	}
}

// ReadMessage reads a JSON-RPC message from stdin
// MCP uses newline-delimited JSON
// Limits message size to MaxMessageSize to prevent OOM
func (t *StdioTransport) ReadMessage() ([]byte, error) {
	line, err := t.reader.ReadBytes('\n')
	if err != nil {
		return nil, err
	}
	if len(line) > MaxMessageSize {
		return nil, fmt.Errorf("message too large: %d bytes (max: %d)", len(line), MaxMessageSize)
	}
	return line, nil
}

// WriteMessage writes a JSON-RPC message to stdout
func (t *StdioTransport) WriteMessage(data []byte) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	// Ensure message ends with newline
	if len(data) == 0 || data[len(data)-1] != '\n' {
		data = append(data, '\n')
	}

	_, err := t.writer.Write(data)
	return err
}

// Close closes the stdio transport
func (t *StdioTransport) Close() error {
	return nil
}

// SSETransport implements Transport using HTTP Server-Sent Events
type SSETransport struct {
	addr      string
	messages  chan []byte
	responses chan []byte
	ctx       context.Context
	cancel    context.CancelFunc
	logger    *zap.SugaredLogger
	mu        sync.Mutex
}

// NewSSETransport creates a new SSE transport
func NewSSETransport(addr string, logger *zap.SugaredLogger) *SSETransport {
	ctx, cancel := context.WithCancel(context.Background())
	return &SSETransport{
		addr:      addr,
		messages:  make(chan []byte, 100),
		responses: make(chan []byte, 100),
		ctx:       ctx,
		cancel:    cancel,
		logger:    logger,
	}
}

// ReadMessage reads a message from the SSE message queue
func (t *SSETransport) ReadMessage() ([]byte, error) {
	select {
	case msg := <-t.messages:
		return msg, nil
	case <-t.ctx.Done():
		return nil, t.ctx.Err()
	}
}

// WriteMessage writes a message to the SSE response queue
func (t *SSETransport) WriteMessage(data []byte) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	select {
	case t.responses <- data:
		return nil
	case <-t.ctx.Done():
		return t.ctx.Err()
	default:
		return fmt.Errorf("response queue full")
	}
}

// Close closes the SSE transport
func (t *SSETransport) Close() error {
	t.cancel()
	return nil
}

// EnqueueMessage adds a message to be processed (called from HTTP handler)
func (t *SSETransport) EnqueueMessage(data []byte) error {
	select {
	case t.messages <- data:
		return nil
	case <-t.ctx.Done():
		return t.ctx.Err()
	default:
		return fmt.Errorf("message queue full")
	}
}

// GetResponse gets a response to send via SSE (called from HTTP handler)
func (t *SSETransport) GetResponse(ctx context.Context) ([]byte, error) {
	select {
	case resp := <-t.responses:
		return resp, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-t.ctx.Done():
		return nil, t.ctx.Err()
	}
}

// JSONRPCMessage represents a JSON-RPC 2.0 message
type JSONRPCMessage struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  interface{}     `json:"result,omitempty"`
	Error   *JSONRPCError   `json:"error,omitempty"`
}

// JSONRPCError represents a JSON-RPC error
type JSONRPCError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// Standard JSON-RPC error codes
const (
	ParseError     = -32700
	InvalidRequest = -32600
	MethodNotFound = -32601
	InvalidParams  = -32602
	InternalError  = -32603
)
