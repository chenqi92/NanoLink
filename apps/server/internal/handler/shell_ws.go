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
)

// ShellHandler handles WebSocket shell connections.
type ShellHandler struct {
	logger     *zap.SugaredLogger
	grpcServer interface {
		SendCommandToAgent(agentID string, cmd *pb.Command) error
	}
	upgrader        websocket.Upgrader
	sessions        sync.Map // agentID -> []*shellSession
	shellSuperToken string
}

type shellSession struct {
	conn      *websocket.Conn
	agentID   string
	userID    uint
	username  string
	createdAt time.Time
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
	allowedOrigins []string,
) *ShellHandler {
	return &ShellHandler{
		logger:          logger,
		grpcServer:      grpcServer,
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
		createdAt: time.Now(),
	}

	h.addSession(agentID, session)
	defer h.removeSession(agentID, session)

	h.logger.Infof("Shell session started: user=%s agent=%s", user.Username, agentID)

	if h.shellSuperToken == "" {
		h.sendError(session.conn, "Remote shell is disabled. Configure NANOLINK_SHELL_SUPER_TOKEN on the server and use the same super_token in agent configs.")
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
			h.sendError(session.conn, "invalid message format")
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

			if err := h.grpcServer.SendCommandToAgent(session.agentID, cmd); err != nil {
				h.sendError(session.conn, "failed to send command: "+err.Error())
				continue
			}

		case "resize":
			h.logger.Debugf("Terminal resize: %dx%d", msg.Cols, msg.Rows)

		default:
			h.sendError(session.conn, "unknown message type: "+msg.Type)
		}
	}
}

func (h *ShellHandler) sendOutput(conn *websocket.Conn, data string) {
	msg := shellMessage{Type: "output", Data: data}
	if jsonData, err := json.Marshal(msg); err == nil {
		_ = conn.WriteMessage(websocket.TextMessage, jsonData)
	}
}

func (h *ShellHandler) sendError(conn *websocket.Conn, errMsg string) {
	msg := shellMessage{Type: "error", Data: errMsg}
	if jsonData, err := json.Marshal(msg); err == nil {
		_ = conn.WriteMessage(websocket.TextMessage, jsonData)
	}
}

// SendOutputToSession sends output from agent to the shell session.
func (h *ShellHandler) SendOutputToSession(agentID, commandID, output string) {
	h.sessions.Range(func(key, value interface{}) bool {
		if sessions, ok := value.([]*shellSession); ok {
			for _, session := range sessions {
				if session.agentID == agentID {
					h.sendOutput(session.conn, output)
				}
			}
		}
		return true
	})
}

func (h *ShellHandler) addSession(agentID string, session *shellSession) {
	value, _ := h.sessions.LoadOrStore(agentID, []*shellSession{})
	sessions := value.([]*shellSession)
	sessions = append(sessions, session)
	h.sessions.Store(agentID, sessions)
}

func (h *ShellHandler) removeSession(agentID string, session *shellSession) {
	value, ok := h.sessions.Load(agentID)
	if !ok {
		return
	}

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

func generateCommandID() string {
	return time.Now().Format("20060102150405.000000")
}
