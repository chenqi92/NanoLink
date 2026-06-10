package handler

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"

	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
)

// ShellHandler handles WebSocket shell connections.
type ShellHandler struct {
	logger     *zap.SugaredLogger
	grpcServer interface {
		SendCommandToAgent(agentID string, cmd *pb.Command) error
	}
	// auditService records every shell command dispatch. The shell channel runs at
	// the highest permission (PermissionSystemAdmin) and previously had no audit
	// trail, unlike the HTTP SendCommand path.
	auditService *service.AuditService
	upgrader     websocket.Upgrader
	sessionsMu   sync.Mutex // guards the []*shellSession slices stored in sessions
	sessions     sync.Map   // agentID -> []*shellSession
	// commandSessions maps a dispatched commandID to the session that issued it,
	// so agent output is routed only back to its originator instead of being
	// broadcast to every session on the agent (which leaks output across users).
	commandSessions sync.Map // commandID -> *shellSession
	shellSuperToken string
}

type shellSession struct {
	conn      *websocket.Conn
	agentID   string
	userID    uint
	username  string
	remoteIP  string
	createdAt time.Time
	// writeMu serializes all writes to conn. gorilla/websocket forbids concurrent
	// writes, and the agent-result goroutine and the read loop both write here.
	writeMu sync.Mutex
}

// send writes one framed message to the session's conn under the write lock.
func (s *shellSession) send(msgType, data string) {
	msg := shellMessage{Type: msgType, Data: data}
	jsonData, err := json.Marshal(msg)
	if err != nil {
		return
	}
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	_ = s.conn.WriteMessage(websocket.TextMessage, jsonData)
}

type shellMessage struct {
	Type string `json:"type"`
	Data string `json:"data,omitempty"`
	Cols int    `json:"cols,omitempty"`
	Rows int    `json:"rows,omitempty"`
}

// NewShellHandler creates a new shell handler.
func NewShellHandler(
	logger *zap.SugaredLogger,
	grpcServer interface {
		SendCommandToAgent(agentID string, cmd *pb.Command) error
	},
	auditService *service.AuditService,
	allowedOrigins []string,
) *ShellHandler {
	return &ShellHandler{
		logger:          logger,
		grpcServer:      grpcServer,
		auditService:    auditService,
		shellSuperToken: strings.TrimSpace(os.Getenv("NANOLINK_SHELL_SUPER_TOKEN")),
		upgrader: websocket.Upgrader{
			ReadBufferSize:  4096,
			WriteBufferSize: 4096,
			CheckOrigin: func(r *http.Request) bool {
				return IsOriginAllowed(r, allowedOrigins)
			},
		},
	}
}

// HandleShellWS handles WebSocket shell connections.
func (h *ShellHandler) HandleShellWS(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	agentID := c.Param("id")
	if agentID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "agent ID required"})
		return
	}

	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		h.logger.Errorf("Shell WebSocket upgrade failed: %v", err)
		return
	}

	session := &shellSession{
		conn:      conn,
		agentID:   agentID,
		userID:    user.ID,
		username:  user.Username,
		remoteIP:  c.ClientIP(),
		createdAt: time.Now(),
	}

	h.addSession(agentID, session)
	defer h.removeSession(agentID, session)

	h.logger.Infof("Shell session started: user=%s agent=%s", user.Username, agentID)

	if h.shellSuperToken == "" {
		session.send("error", "Remote shell is disabled. Configure NANOLINK_SHELL_SUPER_TOKEN on the server and use the same super_token in agent configs.")
		_ = session.conn.WriteControl(
			websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "shell disabled"),
			time.Now().Add(5*time.Second),
		)
		return
	}

	h.handleSession(session)
}

func (h *ShellHandler) handleSession(session *shellSession) {
	defer func() {
		session.conn.Close()
		h.logger.Infof("Shell session ended: user=%s agent=%s", session.username, session.agentID)
	}()

	session.conn.SetReadLimit(64 * 1024)
	session.conn.SetReadDeadline(time.Now().Add(time.Hour))
	session.conn.SetPongHandler(func(string) error {
		session.conn.SetReadDeadline(time.Now().Add(time.Hour))
		return nil
	})

	for {
		_, message, err := session.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				h.logger.Warnf("Shell WebSocket error: %v", err)
			}
			return
		}

		var msg shellMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			session.send("error", "invalid message format")
			continue
		}

		switch msg.Type {
		case "input":
			cmd := &pb.Command{
				CommandId:  generateCommandID(),
				Type:       pb.CommandType_SHELL_EXECUTE,
				Target:     msg.Data,
				SuperToken: h.shellSuperToken,
			}

			// Remember which session issued this command so its output is routed
			// back only here, not broadcast to every session on the agent.
			h.commandSessions.Store(cmd.CommandId, session)

			dispatchErr := h.grpcServer.SendCommandToAgent(session.agentID, cmd)

			// Audit every shell dispatch (best-effort): this is the highest-privilege
			// command path and must leave a trail like the HTTP SendCommand path.
			h.auditCommand(session, cmd, dispatchErr)

			if dispatchErr != nil {
				h.commandSessions.Delete(cmd.CommandId)
				session.send("error", "failed to send command: "+dispatchErr.Error())
				continue
			}

		case "resize":
			h.logger.Debugf("Terminal resize: %dx%d", msg.Cols, msg.Rows)

		default:
			session.send("error", "unknown message type: "+msg.Type)
		}
	}
}

// SendOutputToSession routes agent command output back to the originating session.
func (h *ShellHandler) SendOutputToSession(agentID, commandID, output string) {
	if commandID != "" {
		if v, ok := h.commandSessions.Load(commandID); ok {
			if session, ok := v.(*shellSession); ok && session.agentID == agentID {
				session.send("output", output)
				return
			}
		}
	}
	// No matching command->session mapping: drop rather than broadcast to all of
	// the agent's sessions, which would leak one user's output to another user.
	h.logger.Debugf("Shell output for agent=%s command=%s has no matching session; dropping", agentID, commandID)
}

// auditCommand records a shell command dispatch to the audit trail (best-effort).
func (h *ShellHandler) auditCommand(session *shellSession, cmd *pb.Command, dispatchErr error) {
	if h.auditService == nil {
		return
	}
	entry := service.AuditEntry{
		UserID:      session.userID,
		Username:    session.username,
		AgentID:     session.agentID,
		CommandType: cmd.Type.String(),
		CommandID:   cmd.CommandId,
		Target:      cmd.Target,
		Success:     dispatchErr == nil,
		IPAddress:   session.remoteIP,
	}
	if dispatchErr != nil {
		entry.Error = dispatchErr.Error()
	}
	_ = h.auditService.LogCommand(entry)
}

func (h *ShellHandler) addSession(agentID string, session *shellSession) {
	h.sessionsMu.Lock()
	defer h.sessionsMu.Unlock()
	value, _ := h.sessions.LoadOrStore(agentID, []*shellSession{})
	sessions := value.([]*shellSession)
	sessions = append(sessions, session)
	h.sessions.Store(agentID, sessions)
}

func (h *ShellHandler) removeSession(agentID string, session *shellSession) {
	h.sessionsMu.Lock()
	value, ok := h.sessions.Load(agentID)
	if ok {
		sessions := value.([]*shellSession)
		filtered := make([]*shellSession, 0, len(sessions))
		for _, s := range sessions {
			if s != session {
				filtered = append(filtered, s)
			}
		}
		if len(filtered) > 0 {
			h.sessions.Store(agentID, filtered)
		} else {
			h.sessions.Delete(agentID)
		}
	}
	h.sessionsMu.Unlock()

	// Drop any command->session mappings still pointing at this session.
	h.commandSessions.Range(func(key, value interface{}) bool {
		if s, ok := value.(*shellSession); ok && s == session {
			h.commandSessions.Delete(key)
		}
		return true
	})
}

func generateCommandID() string {
	return time.Now().Format("20060102150405.000000")
}
