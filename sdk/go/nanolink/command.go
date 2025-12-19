package nanolink

import "fmt"

// CommandType represents the type of command
type CommandType int

const (
	// Process Management
	CommandProcessList CommandType = 1
	CommandProcessKill CommandType = 2

	// Service Management
	CommandServiceStart   CommandType = 10
	CommandServiceStop    CommandType = 11
	CommandServiceRestart CommandType = 12
	CommandServiceStatus  CommandType = 13

	// File Operations
	CommandFileTail     CommandType = 20
	CommandFileDownload CommandType = 21
	CommandFileUpload   CommandType = 22
	CommandFileTruncate CommandType = 23

	// Docker Operations
	CommandDockerList    CommandType = 30
	CommandDockerStart   CommandType = 31
	CommandDockerStop    CommandType = 32
	CommandDockerRestart CommandType = 33
	CommandDockerLogs    CommandType = 34

	// System Operations
	CommandSystemReboot CommandType = 40

	// Shell Command (requires SuperToken)
	CommandShellExecute CommandType = 50
)

// Command represents a command to be sent to an agent
type Command struct {
	CommandID  string            `json:"commandId"`
	Type       CommandType       `json:"type"`
	Target     string            `json:"target"`
	Params     map[string]string `json:"params"`
	SuperToken string            `json:"superToken,omitempty"`
}

// RequiredPermission returns the required permission level for this command
func (c *Command) RequiredPermission() int {
	switch c.Type {
	case CommandProcessList, CommandServiceStatus, CommandDockerList, CommandFileTail:
		return PermissionReadOnly
	case CommandFileDownload, CommandFileTruncate, CommandDockerLogs:
		return PermissionBasicWrite
	case CommandProcessKill, CommandServiceStart, CommandServiceStop, CommandServiceRestart,
		CommandDockerStart, CommandDockerStop, CommandDockerRestart, CommandFileUpload:
		return PermissionServiceControl
	case CommandSystemReboot, CommandShellExecute:
		return PermissionSystemAdmin
	default:
		return PermissionSystemAdmin
	}
}

// ToProtobuf converts the command to protobuf bytes
func (c *Command) ToProtobuf() []byte {
	// Simplified - in production use generated protobuf
	return []byte{}
}

// CommandResult represents the result of a command execution
type CommandResult struct {
	CommandID   string          `json:"commandId"`
	Success     bool            `json:"success"`
	Output      string          `json:"output"`
	Error       string          `json:"error"`
	FileContent []byte          `json:"fileContent,omitempty"`
	Processes   []ProcessInfo   `json:"processes,omitempty"`
	Containers  []ContainerInfo `json:"containers,omitempty"`
}

// Factory functions for creating commands

// NewProcessListCommand creates a process list command
func NewProcessListCommand() *Command {
	return &Command{Type: CommandProcessList}
}

// NewProcessKillCommand creates a process kill command
func NewProcessKillCommand(target string) *Command {
	return &Command{Type: CommandProcessKill, Target: target}
}

// NewServiceStartCommand creates a service start command
func NewServiceStartCommand(serviceName string) *Command {
	return &Command{Type: CommandServiceStart, Target: serviceName}
}

// NewServiceStopCommand creates a service stop command
func NewServiceStopCommand(serviceName string) *Command {
	return &Command{Type: CommandServiceStop, Target: serviceName}
}

// NewServiceRestartCommand creates a service restart command
func NewServiceRestartCommand(serviceName string) *Command {
	return &Command{Type: CommandServiceRestart, Target: serviceName}
}

// NewServiceStatusCommand creates a service status command
func NewServiceStatusCommand(serviceName string) *Command {
	return &Command{Type: CommandServiceStatus, Target: serviceName}
}

// NewFileTailCommand creates a file tail command
func NewFileTailCommand(path string, lines int) *Command {
	return &Command{
		Type:   CommandFileTail,
		Target: path,
		Params: map[string]string{"lines": fmt.Sprintf("%d", lines)},
	}
}

// NewFileDownloadCommand creates a file download command
func NewFileDownloadCommand(path string) *Command {
	return &Command{Type: CommandFileDownload, Target: path}
}

// NewFileTruncateCommand creates a file truncate command
func NewFileTruncateCommand(path string) *Command {
	return &Command{Type: CommandFileTruncate, Target: path}
}

// NewDockerListCommand creates a Docker list command
func NewDockerListCommand() *Command {
	return &Command{Type: CommandDockerList}
}

// NewDockerStartCommand creates a Docker start command
func NewDockerStartCommand(containerName string) *Command {
	return &Command{Type: CommandDockerStart, Target: containerName}
}

// NewDockerStopCommand creates a Docker stop command
func NewDockerStopCommand(containerName string) *Command {
	return &Command{Type: CommandDockerStop, Target: containerName}
}

// NewDockerRestartCommand creates a Docker restart command
func NewDockerRestartCommand(containerName string) *Command {
	return &Command{Type: CommandDockerRestart, Target: containerName}
}

// NewDockerLogsCommand creates a Docker logs command
func NewDockerLogsCommand(containerName string, lines int) *Command {
	return &Command{
		Type:   CommandDockerLogs,
		Target: containerName,
		Params: map[string]string{"lines": fmt.Sprintf("%d", lines)},
	}
}

// NewSystemRebootCommand creates a system reboot command
func NewSystemRebootCommand() *Command {
	return &Command{Type: CommandSystemReboot}
}

// NewShellExecuteCommand creates a shell execute command
func NewShellExecuteCommand(command string, superToken string) *Command {
	return &Command{
		Type:       CommandShellExecute,
		Target:     command,
		SuperToken: superToken,
	}
}
