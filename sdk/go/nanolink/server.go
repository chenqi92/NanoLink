package nanolink

import (
	"crypto/tls"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Server configuration
type Config struct {
	Port            int
	TLSCert         string
	TLSKey          string
	DashboardEnabled bool
	DashboardPath   string
	TokenValidator  TokenValidator
}

// Token validation result
type ValidationResult struct {
	Valid           bool
	PermissionLevel int
	ErrorMessage    string
}

// Token validator function type
type TokenValidator func(token string) ValidationResult

// Default token validator (accepts all)
func DefaultTokenValidator(token string) ValidationResult {
	return ValidationResult{Valid: true, PermissionLevel: 0}
}

// Permission levels
const (
	PermissionReadOnly       = 0
	PermissionBasicWrite     = 1
	PermissionServiceControl = 2
	PermissionSystemAdmin    = 3
)

// Server is the NanoLink server
type Server struct {
	config          Config
	agents          map[string]*AgentConnection
	agentsMu        sync.RWMutex
	upgrader        websocket.Upgrader
	onAgentConnect  func(*AgentConnection)
	onAgentDisconnect func(*AgentConnection)
	onMetrics       func(*Metrics)
	httpServer      *http.Server
}

// NewServer creates a new NanoLink server
func NewServer(config Config) *Server {
	if config.Port == 0 {
		config.Port = 9100
	}
	if config.TokenValidator == nil {
		config.TokenValidator = DefaultTokenValidator
	}
	if config.DashboardEnabled == false {
		config.DashboardEnabled = true
	}

	return &Server{
		config: config,
		agents: make(map[string]*AgentConnection),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for dashboard
			},
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
	}
}

// OnAgentConnect sets the callback for when an agent connects
func (s *Server) OnAgentConnect(callback func(*AgentConnection)) {
	s.onAgentConnect = callback
}

// OnAgentDisconnect sets the callback for when an agent disconnects
func (s *Server) OnAgentDisconnect(callback func(*AgentConnection)) {
	s.onAgentDisconnect = callback
}

// OnMetrics sets the callback for receiving metrics
func (s *Server) OnMetrics(callback func(*Metrics)) {
	s.onMetrics = callback
}

// Start starts the server
func (s *Server) Start() error {
	mux := http.NewServeMux()

	// WebSocket endpoint
	mux.HandleFunc("/ws", s.handleWebSocket)

	// API endpoints
	mux.HandleFunc("/api/agents", s.handleAPIAgents)
	mux.HandleFunc("/api/health", s.handleAPIHealth)

	// Dashboard (if enabled)
	if s.config.DashboardEnabled {
		mux.HandleFunc("/", s.handleDashboard)
	}

	addr := fmt.Sprintf(":%d", s.config.Port)
	s.httpServer = &http.Server{
		Addr:    addr,
		Handler: mux,
	}

	log.Printf("NanoLink Server starting on port %d", s.config.Port)
	if s.config.DashboardEnabled {
		log.Printf("Dashboard available at http://localhost:%d/", s.config.Port)
	}

	if s.config.TLSCert != "" && s.config.TLSKey != "" {
		return s.httpServer.ListenAndServeTLS(s.config.TLSCert, s.config.TLSKey)
	}
	return s.httpServer.ListenAndServe()
}

// Stop stops the server
func (s *Server) Stop() error {
	// Close all agent connections
	s.agentsMu.Lock()
	for _, agent := range s.agents {
		agent.Close()
	}
	s.agents = make(map[string]*AgentConnection)
	s.agentsMu.Unlock()

	if s.httpServer != nil {
		return s.httpServer.Close()
	}
	return nil
}

// GetAgent returns an agent by ID
func (s *Server) GetAgent(agentID string) *AgentConnection {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()
	return s.agents[agentID]
}

// GetAgentByHostname returns an agent by hostname
func (s *Server) GetAgentByHostname(hostname string) *AgentConnection {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()
	for _, agent := range s.agents {
		if agent.Hostname == hostname {
			return agent
		}
	}
	return nil
}

// GetAgents returns all connected agents
func (s *Server) GetAgents() map[string]*AgentConnection {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()
	result := make(map[string]*AgentConnection)
	for k, v := range s.agents {
		result[k] = v
	}
	return result
}

// registerAgent registers a new agent
func (s *Server) registerAgent(agent *AgentConnection) {
	s.agentsMu.Lock()
	s.agents[agent.AgentID] = agent
	s.agentsMu.Unlock()

	log.Printf("Agent registered: %s (%s)", agent.Hostname, agent.AgentID)

	if s.onAgentConnect != nil {
		s.onAgentConnect(agent)
	}
}

// unregisterAgent unregisters an agent
func (s *Server) unregisterAgent(agent *AgentConnection) {
	s.agentsMu.Lock()
	delete(s.agents, agent.AgentID)
	s.agentsMu.Unlock()

	log.Printf("Agent unregistered: %s (%s)", agent.Hostname, agent.AgentID)

	if s.onAgentDisconnect != nil {
		s.onAgentDisconnect(agent)
	}
}

// handleMetrics handles incoming metrics
func (s *Server) handleMetrics(metrics *Metrics) {
	if s.onMetrics != nil {
		s.onMetrics(metrics)
	}
}

// handleWebSocket handles WebSocket connections
func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	agent := NewAgentConnection(conn, s)
	go agent.readPump()
	go agent.writePump()
}

// handleAPIAgents handles the /api/agents endpoint
func (s *Server) handleAPIAgents(w http.ResponseWriter, r *http.Request) {
	agents := s.GetAgents()

	type AgentInfo struct {
		AgentID       string    `json:"agentId"`
		Hostname      string    `json:"hostname"`
		OS            string    `json:"os"`
		Arch          string    `json:"arch"`
		Version       string    `json:"version"`
		ConnectedAt   time.Time `json:"connectedAt"`
		LastHeartbeat time.Time `json:"lastHeartbeat"`
	}

	result := make([]AgentInfo, 0, len(agents))
	for _, agent := range agents {
		result = append(result, AgentInfo{
			AgentID:       agent.AgentID,
			Hostname:      agent.Hostname,
			OS:            agent.OS,
			Arch:          agent.Arch,
			Version:       agent.Version,
			ConnectedAt:   agent.ConnectedAt,
			LastHeartbeat: agent.LastHeartbeat,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"agents": result,
	})
}

// handleAPIHealth handles the /api/health endpoint
func (s *Server) handleAPIHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
	})
}

// handleDashboard serves the embedded dashboard
func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	// Serve embedded dashboard HTML
	w.Header().Set("Content-Type", "text/html")
	w.Write([]byte(embeddedDashboard))
}

// Embedded minimal dashboard
var embeddedDashboard = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NanoLink Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }
        h1 { font-size: 24px; font-weight: 600; }
        .status { display: flex; align-items: center; gap: 8px; }
        .status-dot { width: 10px; height: 10px; border-radius: 50%; background: #22c55e; }
        .status-dot.disconnected { background: #ef4444; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(350px, 1fr)); gap: 20px; }
        .card { background: #1e293b; border-radius: 12px; padding: 20px; border: 1px solid #334155; }
        .card-title { font-size: 14px; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 15px; }
        .card-value { font-size: 32px; font-weight: 700; }
        .card-subtitle { font-size: 12px; color: #64748b; margin-top: 5px; }
        .progress-bar { height: 6px; background: #334155; border-radius: 3px; margin-top: 10px; overflow: hidden; }
        .progress-fill { height: 100%; border-radius: 3px; transition: width 0.3s; }
        .progress-fill.cpu { background: linear-gradient(90deg, #3b82f6, #8b5cf6); }
        .progress-fill.memory { background: linear-gradient(90deg, #22c55e, #84cc16); }
        .agents { margin-top: 30px; }
        .agents h2 { font-size: 18px; margin-bottom: 15px; }
        .agent-list { display: flex; flex-direction: column; gap: 10px; }
        .agent-item { background: #1e293b; border-radius: 8px; padding: 15px; display: flex; justify-content: space-between; align-items: center; border: 1px solid #334155; }
        .no-agents { text-align: center; padding: 40px; color: #64748b; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>NanoLink Dashboard</h1>
            <div class="status">
                <div class="status-dot" id="statusDot"></div>
                <span id="statusText">Connecting...</span>
            </div>
        </header>
        <div class="grid">
            <div class="card">
                <div class="card-title">CPU Usage</div>
                <div class="card-value" id="cpuValue">--</div>
                <div class="card-subtitle" id="cpuCores">-- cores</div>
                <div class="progress-bar"><div class="progress-fill cpu" id="cpuBar" style="width: 0%"></div></div>
            </div>
            <div class="card">
                <div class="card-title">Memory</div>
                <div class="card-value" id="memValue">--</div>
                <div class="card-subtitle" id="memInfo">-- / --</div>
                <div class="progress-bar"><div class="progress-fill memory" id="memBar" style="width: 0%"></div></div>
            </div>
        </div>
        <div class="agents">
            <h2>Connected Agents</h2>
            <div class="agent-list" id="agentList">
                <div class="no-agents">No agents connected</div>
            </div>
        </div>
    </div>
    <script>
        const ws = new WebSocket("ws://" + window.location.host + "/ws");
        ws.onopen = () => {
            document.getElementById('statusDot').classList.remove('disconnected');
            document.getElementById('statusText').textContent = 'Connected';
        };
        ws.onclose = () => {
            document.getElementById('statusDot').classList.add('disconnected');
            document.getElementById('statusText').textContent = 'Disconnected';
        };
        // Fetch agents periodically
        setInterval(() => {
            fetch('/api/agents').then(r => r.json()).then(data => {
                const list = document.getElementById('agentList');
                if (data.agents && data.agents.length > 0) {
                    list.innerHTML = data.agents.map(a =>
                        '<div class="agent-item"><div>' + a.hostname + '</div><div>' + a.os + '/' + a.arch + '</div></div>'
                    ).join('');
                } else {
                    list.innerHTML = '<div class="no-agents">No agents connected</div>';
                }
            });
        }, 2000);
    </script>
</body>
</html>`
