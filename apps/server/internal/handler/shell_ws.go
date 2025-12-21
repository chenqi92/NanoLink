package handler

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"

	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
)

// ShellHandler handles WebSocket shell connections
type ShellHandler struct {
	logger      *zap.SugaredLogger
	authService interface {
		VerifyToken(tokenString string) (*service.JWTClaims, error)
	}
	grpcServer interface {
		SendCommandToAgent(agentID string, cmd *pb.Command) error
	}
	upgrader websocket.Upgrader
	sessions sync.Map // agentID -> []*shellSession
}

type shellSession struct {
	conn      *websocket.Conn
	agentID   string
	userID    uint
	username  string
	createdAt time.Time
}

type shellMessage struct {
	Type string `json:"type"` // "input", "output", "error", "resize"
	Data string `json:"data,omitempty"`
	Cols int    `json:"cols,omitempty"`
	Rows int    `json:"rows,omitempty"`
}

// NewShellHandler creates a new shell handler
func NewShellHandler(
	logger *zap.SugaredLogger,
	authService interface {
		VerifyToken(tokenString string) (*service.JWTClaims, error)
	},
	grpcServer interface {
		SendCommandToAgent(agentID string, cmd *pb.Command) error
	},
) *ShellHandler {
	return &ShellHandler{
		logger:      logger,
		authService: authService,
		grpcServer:  grpcServer,
		upgrader: websocket.Upgrader{
			ReadBufferSize:  4096,
			WriteBufferSize: 4096,
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for now
			},
		},
	}
}

// HandleShellWS handles WebSocket shell connections
func (h *ShellHandler) HandleShellWS(c *gin.Context) {
	agentID := c.Param("id")
	token := c.Query("token")

	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "token required"})
		return
	}

	// Validate token
	claims, err := h.authService.VerifyToken(token)
	if err != nil {
		h.logger.Warnf("Shell auth failed: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}

	// Upgrade to WebSocket
	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		h.logger.Errorf("WebSocket upgrade failed: %v", err)
		return
	}

	session := &shellSession{
		conn:      conn,
		agentID:   agentID,
		userID:    claims.UserID,
		username:  claims.Username,
		createdAt: time.Now(),
	}

	// Register session for receiving agent output
	h.addSession(agentID, session)
	defer h.removeSession(agentID, session)

	h.logger.Infof("Shell session started: user=%s agent=%s", claims.Username, agentID)

	// Handle the session
	h.handleSession(session)
}

func (h *ShellHandler) handleSession(session *shellSession) {
	defer func() {
		session.conn.Close()
		h.logger.Infof("Shell session ended: user=%s agent=%s", session.username, session.agentID)
	}()

	// Set read deadline
	session.conn.SetReadDeadline(time.Now().Add(time.Hour))

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
			// Send command to agent via gRPC
			cmd := &pb.Command{
				CommandId: generateCommandID(),
				Type:      pb.CommandType_SHELL_EXECUTE,
				Target:    msg.Data, // Shell command to execute
			}

			if err := h.grpcServer.SendCommandToAgent(session.agentID, cmd); err != nil {
				h.sendError(session.conn, "failed to send command: "+err.Error())
				continue
			}

			// Echo command prompt (actual output will come from agent via gRPC callback)

		case "resize":
			// Handle terminal resize - could be forwarded to agent
			h.logger.Debugf("Terminal resize: %dx%d", msg.Cols, msg.Rows)

		default:
			h.sendError(session.conn, "unknown message type: "+msg.Type)
		}
	}
}

func (h *ShellHandler) sendOutput(conn *websocket.Conn, data string) {
	msg := shellMessage{Type: "output", Data: data}
	if jsonData, err := json.Marshal(msg); err == nil {
		conn.WriteMessage(websocket.TextMessage, jsonData)
	}
}

func (h *ShellHandler) sendError(conn *websocket.Conn, errMsg string) {
	msg := shellMessage{Type: "error", Data: errMsg}
	if jsonData, err := json.Marshal(msg); err == nil {
		conn.WriteMessage(websocket.TextMessage, jsonData)
	}
}

// SendOutputToSession sends output from agent to the shell session
// This would be called when receiving command results from the agent
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

// addSession adds a shell session to the sessions map
func (h *ShellHandler) addSession(agentID string, session *shellSession) {
	value, _ := h.sessions.LoadOrStore(agentID, []*shellSession{})
	sessions := value.([]*shellSession)
	sessions = append(sessions, session)
	h.sessions.Store(agentID, sessions)
}

// removeSession removes a shell session from the sessions map
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
