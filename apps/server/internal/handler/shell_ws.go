package handler

import (
	"encoding/json"
	"net/http"
	"os"
	pathpkg "path"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"

	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
)

// shellCommandRouteTTL bounds how long a pending command->session route is kept
// when no result ever comes back (e.g. the agent disconnects mid-command).
const shellCommandRouteTTL = 10 * time.Minute

// ShellHandler handles WebSocket shell connections.
type ShellHandler struct {
	logger     *zap.SugaredLogger
	grpcServer interface {
		SendCommandToAgent(agentID string, cmd *pb.Command) error
	}
	upgrader        websocket.Upgrader
	shellSuperToken string

	// cmdRoutes maps a command ID to the session that issued it, so command
	// output is delivered only to the originating session instead of being
	// broadcast to every session attached to the agent.
	mu        sync.Mutex
	cmdRoutes map[string]*cmdRoute
}

type cmdRoute struct {
	session *shellSession
	at      time.Time
	nextCwd string
}

type shellSession struct {
	conn      *websocket.Conn
	agentID   string
	userID    uint
	username  string
	createdAt time.Time

	// cols/rows track the latest terminal size from resize messages, forwarded
	// with each command so width-aware tools (ls, ps, top) render correctly.
	cols int
	rows int
	cwd  string

	stateMu sync.Mutex

	// writeMu serializes writes to conn. gorilla/websocket forbids concurrent
	// writers, and output arrives from the gRPC stream goroutine while the read
	// loop may also write errors.
	writeMu sync.Mutex
}

type shellMessage struct {
	Type string `json:"type"`
	Data string `json:"data,omitempty"`
	Cols int    `json:"cols,omitempty"`
	Rows int    `json:"rows,omitempty"`
	Cwd  string `json:"cwd,omitempty"`
	// Success reports whether the command that produced this output frame exited
	// successfully. It is only meaningful on "output" frames and lets the client
	// style failed commands distinctly. Pointer so it is omitted (not sent as
	// false) for input echoes and non-command frames.
	Success *bool `json:"success,omitempty"`
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
		cmdRoutes:       make(map[string]*cmdRoute),
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
		cwd:       "/",
	}

	defer h.dropRoutesForSession(session)

	h.logger.Infof("Shell session started: user=%s agent=%s", user.Username, agentID)

	if h.shellSuperToken == "" {
		h.sendError(session, "Remote shell is disabled. Configure NANOLINK_SHELL_SUPER_TOKEN on the server and use the same super_token in agent configs.")
		_ = session.conn.WriteControl(
			websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "shell disabled"),
			time.Now().Add(5*time.Second),
		)
		return
	}

	h.handleSession(session)
}

func (s *shellSession) currentCwd() string {
	s.stateMu.Lock()
	defer s.stateMu.Unlock()
	if s.cwd == "" {
		return "/"
	}
	return s.cwd
}

func (s *shellSession) setCwd(cwd string) {
	s.stateMu.Lock()
	s.cwd = cwd
	s.stateMu.Unlock()
}

// parseShellCD recognizes only the shell built-in form `cd [directory]`.
// Metacharacters or extra arguments deliberately fall through to the Agent's
// normal injection validator instead of being interpreted here.
func parseShellCD(command string) (string, bool) {
	fields := strings.Fields(command)
	if len(fields) == 1 && fields[0] == "cd" {
		return "/", true
	}
	if len(fields) != 2 || fields[0] != "cd" {
		return "", false
	}
	target := fields[1]
	if target == "" || strings.ContainsAny(target, ";&|<>$`\r\n\x00") {
		return "", false
	}
	return target, true
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
			h.sendError(session, "invalid message format")
			continue
		}

		switch msg.Type {
		case "input":
			requestedCommand := strings.TrimSpace(msg.Data)
			commandTarget := requestedCommand
			commandCwd := session.currentCwd()
			nextCwd := ""
			if requested, ok := parseShellCD(requestedCommand); ok {
				if strings.HasPrefix(requested, "/") {
					nextCwd = pathpkg.Clean(requested)
				} else {
					nextCwd = pathpkg.Clean(pathpkg.Join(commandCwd, requested))
				}
				if !strings.HasPrefix(nextCwd, "/") {
					h.sendError(session, "invalid working directory")
					continue
				}
				commandTarget = "pwd"
				commandCwd = nextCwd
			}
			commandID := uuid.New().String()
			cmd := &pb.Command{
				CommandId:  commandID,
				Type:       pb.CommandType_SHELL_EXECUTE,
				Target:     commandTarget,
				SuperToken: h.shellSuperToken,
				Params:     map[string]string{"cwd": commandCwd},
			}
			// Forward the current terminal size so the agent can export
			// COLUMNS/LINES for width-aware commands.
			if session.cols > 0 || session.rows > 0 {
				cmd.Params["cols"] = strconv.Itoa(session.cols)
				cmd.Params["rows"] = strconv.Itoa(session.rows)
			}

			h.registerRoute(commandID, session, nextCwd)
			if err := h.grpcServer.SendCommandToAgent(session.agentID, cmd); err != nil {
				h.dropRoute(commandID)
				h.sendError(session, "failed to send command: "+err.Error())
				continue
			}

		case "resize":
			if msg.Cols > 0 {
				session.cols = msg.Cols
			}
			if msg.Rows > 0 {
				session.rows = msg.Rows
			}
			h.logger.Debugf("Terminal resize: %dx%d", msg.Cols, msg.Rows)

		default:
			h.sendError(session, "unknown message type: "+msg.Type)
		}
	}
}

func (h *ShellHandler) sendOutput(session *shellSession, data string, success bool) {
	ok := success
	msg := shellMessage{Type: "output", Data: data, Success: &ok, Cwd: session.currentCwd()}
	if jsonData, err := json.Marshal(msg); err == nil {
		session.writeMu.Lock()
		_ = session.conn.WriteMessage(websocket.TextMessage, jsonData)
		session.writeMu.Unlock()
	}
}

func (h *ShellHandler) sendError(session *shellSession, errMsg string) {
	msg := shellMessage{Type: "error", Data: errMsg}
	if jsonData, err := json.Marshal(msg); err == nil {
		session.writeMu.Lock()
		_ = session.conn.WriteMessage(websocket.TextMessage, jsonData)
		session.writeMu.Unlock()
	}
}

// SendOutputToSession delivers command output to the session that issued the
// command identified by commandID. Output for commands the server did not route
// through a shell session (e.g. data-request results) is silently dropped.
//
// success carries the command's exit disposition so the client can style failed
// commands distinctly; the agent annotates the output text itself with the
// numeric exit status (the proto CommandResult has no dedicated exit-code field).
func (h *ShellHandler) SendOutputToSession(agentID, commandID, output string, success bool) {
	h.mu.Lock()
	route, ok := h.cmdRoutes[commandID]
	if ok {
		delete(h.cmdRoutes, commandID)
	}
	h.mu.Unlock()

	if !ok || route.session.agentID != agentID {
		return
	}
	if success && route.nextCwd != "" {
		route.session.setCwd(route.nextCwd)
		output = ""
	}

	h.sendOutput(route.session, output, success)
}

// registerRoute records the session that issued commandID and opportunistically
// sweeps stale routes whose results never arrived.
func (h *ShellHandler) registerRoute(commandID string, session *shellSession, nextCwd string) {
	now := time.Now()
	h.mu.Lock()
	defer h.mu.Unlock()
	for id, r := range h.cmdRoutes {
		if now.Sub(r.at) > shellCommandRouteTTL {
			delete(h.cmdRoutes, id)
		}
	}
	h.cmdRoutes[commandID] = &cmdRoute{session: session, at: now, nextCwd: nextCwd}
}

func (h *ShellHandler) dropRoute(commandID string) {
	h.mu.Lock()
	delete(h.cmdRoutes, commandID)
	h.mu.Unlock()
}

func (h *ShellHandler) dropRoutesForSession(session *shellSession) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for id, r := range h.cmdRoutes {
		if r.session == session {
			delete(h.cmdRoutes, id)
		}
	}
}
