package com.kkape.sdk.model;

import com.kkape.sdk.TokenValidator;

import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Command to be sent to an agent
 */
public class Command {
    private String commandId;
    private Type type;
    private String target;
    private Map<String, String> params = new HashMap<>();
    private String superToken;

    public enum Type {
        PROCESS_LIST(1, TokenValidator.PermissionLevel.READ_ONLY),
        PROCESS_KILL(2, TokenValidator.PermissionLevel.SERVICE_CONTROL),

        SERVICE_START(10, TokenValidator.PermissionLevel.SERVICE_CONTROL),
        SERVICE_STOP(11, TokenValidator.PermissionLevel.SERVICE_CONTROL),
        SERVICE_RESTART(12, TokenValidator.PermissionLevel.SERVICE_CONTROL),
        SERVICE_STATUS(13, TokenValidator.PermissionLevel.READ_ONLY),

        FILE_TAIL(20, TokenValidator.PermissionLevel.READ_ONLY),
        FILE_DOWNLOAD(21, TokenValidator.PermissionLevel.BASIC_WRITE),
        FILE_UPLOAD(22, TokenValidator.PermissionLevel.SERVICE_CONTROL),
        FILE_TRUNCATE(23, TokenValidator.PermissionLevel.BASIC_WRITE),

        DOCKER_LIST(30, TokenValidator.PermissionLevel.READ_ONLY),
        DOCKER_START(31, TokenValidator.PermissionLevel.SERVICE_CONTROL),
        DOCKER_STOP(32, TokenValidator.PermissionLevel.SERVICE_CONTROL),
        DOCKER_RESTART(33, TokenValidator.PermissionLevel.SERVICE_CONTROL),
        DOCKER_LOGS(34, TokenValidator.PermissionLevel.BASIC_WRITE),

        SYSTEM_REBOOT(40, TokenValidator.PermissionLevel.SYSTEM_ADMIN),
        SHELL_EXECUTE(50, TokenValidator.PermissionLevel.SYSTEM_ADMIN);

        private final int code;
        private final int requiredPermission;

        Type(int code, int requiredPermission) {
            this.code = code;
            this.requiredPermission = requiredPermission;
        }

        public int getCode() {
            return code;
        }

        public int getRequiredPermission() {
            return requiredPermission;
        }
    }

    // Factory methods

    public static Command processList() {
        Command cmd = new Command();
        cmd.type = Type.PROCESS_LIST;
        return cmd;
    }

    public static Command processKill(String target) {
        Command cmd = new Command();
        cmd.type = Type.PROCESS_KILL;
        cmd.target = target;
        return cmd;
    }

    public static Command serviceStart(String serviceName) {
        Command cmd = new Command();
        cmd.type = Type.SERVICE_START;
        cmd.target = serviceName;
        return cmd;
    }

    public static Command serviceStop(String serviceName) {
        Command cmd = new Command();
        cmd.type = Type.SERVICE_STOP;
        cmd.target = serviceName;
        return cmd;
    }

    public static Command serviceRestart(String serviceName) {
        Command cmd = new Command();
        cmd.type = Type.SERVICE_RESTART;
        cmd.target = serviceName;
        return cmd;
    }

    public static Command serviceStatus(String serviceName) {
        Command cmd = new Command();
        cmd.type = Type.SERVICE_STATUS;
        cmd.target = serviceName;
        return cmd;
    }

    public static Command fileTail(String path, int lines) {
        Command cmd = new Command();
        cmd.type = Type.FILE_TAIL;
        cmd.target = path;
        cmd.params.put("lines", String.valueOf(lines));
        return cmd;
    }

    public static Command fileDownload(String path) {
        Command cmd = new Command();
        cmd.type = Type.FILE_DOWNLOAD;
        cmd.target = path;
        return cmd;
    }

    public static Command fileTruncate(String path) {
        Command cmd = new Command();
        cmd.type = Type.FILE_TRUNCATE;
        cmd.target = path;
        return cmd;
    }

    public static Command dockerList() {
        Command cmd = new Command();
        cmd.type = Type.DOCKER_LIST;
        return cmd;
    }

    public static Command dockerStart(String containerName) {
        Command cmd = new Command();
        cmd.type = Type.DOCKER_START;
        cmd.target = containerName;
        return cmd;
    }

    public static Command dockerStop(String containerName) {
        Command cmd = new Command();
        cmd.type = Type.DOCKER_STOP;
        cmd.target = containerName;
        return cmd;
    }

    public static Command dockerRestart(String containerName) {
        Command cmd = new Command();
        cmd.type = Type.DOCKER_RESTART;
        cmd.target = containerName;
        return cmd;
    }

    public static Command dockerLogs(String containerName, int lines) {
        Command cmd = new Command();
        cmd.type = Type.DOCKER_LOGS;
        cmd.target = containerName;
        cmd.params.put("lines", String.valueOf(lines));
        return cmd;
    }

    public static Command systemReboot() {
        Command cmd = new Command();
        cmd.type = Type.SYSTEM_REBOOT;
        return cmd;
    }

    public static Command shellExecute(String command, String superToken) {
        Command cmd = new Command();
        cmd.type = Type.SHELL_EXECUTE;
        cmd.target = command;
        cmd.superToken = superToken;
        return cmd;
    }

    /**
     * Convert to protobuf bytes
     */
    public byte[] toProtobuf() {
        // Simplified serialization - in real implementation use generated protobuf classes
        // This is a placeholder
        return new byte[0];
    }

    public int getRequiredPermission() {
        return type != null ? type.getRequiredPermission() : TokenValidator.PermissionLevel.SYSTEM_ADMIN;
    }

    // Getters and setters

    public String getCommandId() {
        return commandId;
    }

    public void setCommandId(String commandId) {
        this.commandId = commandId;
    }

    public Type getType() {
        return type;
    }

    public void setType(Type type) {
        this.type = type;
    }

    public String getTarget() {
        return target;
    }

    public void setTarget(String target) {
        this.target = target;
    }

    public Map<String, String> getParams() {
        return params;
    }

    public void setParams(Map<String, String> params) {
        this.params = params;
    }

    public String getSuperToken() {
        return superToken;
    }

    public void setSuperToken(String superToken) {
        this.superToken = superToken;
    }

    /**
     * Command execution result
     */
    public static class Result {
        private String commandId;
        private boolean success;
        private String output;
        private String error;
        private byte[] fileContent;
        private List<ProcessInfo> processes;
        private List<ContainerInfo> containers;

        public String getCommandId() {
            return commandId;
        }

        public void setCommandId(String commandId) {
            this.commandId = commandId;
        }

        public boolean isSuccess() {
            return success;
        }

        public void setSuccess(boolean success) {
            this.success = success;
        }

        public String getOutput() {
            return output;
        }

        public void setOutput(String output) {
            this.output = output;
        }

        public String getError() {
            return error;
        }

        public void setError(String error) {
            this.error = error;
        }

        public byte[] getFileContent() {
            return fileContent;
        }

        public void setFileContent(byte[] fileContent) {
            this.fileContent = fileContent;
        }

        public List<ProcessInfo> getProcesses() {
            return processes;
        }

        public void setProcesses(List<ProcessInfo> processes) {
            this.processes = processes;
        }

        public List<ContainerInfo> getContainers() {
            return containers;
        }

        public void setContainers(List<ContainerInfo> containers) {
            this.containers = containers;
        }
    }

    /**
     * Process information
     */
    public static class ProcessInfo {
        private int pid;
        private String name;
        private String user;
        private double cpuPercent;
        private long memoryBytes;
        private String status;

        // Getters and setters
        public int getPid() { return pid; }
        public void setPid(int pid) { this.pid = pid; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getUser() { return user; }
        public void setUser(String user) { this.user = user; }
        public double getCpuPercent() { return cpuPercent; }
        public void setCpuPercent(double cpuPercent) { this.cpuPercent = cpuPercent; }
        public long getMemoryBytes() { return memoryBytes; }
        public void setMemoryBytes(long memoryBytes) { this.memoryBytes = memoryBytes; }
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
    }

    /**
     * Container information
     */
    public static class ContainerInfo {
        private String id;
        private String name;
        private String image;
        private String status;
        private String state;

        // Getters and setters
        public String getId() { return id; }
        public void setId(String id) { this.id = id; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getImage() { return image; }
        public void setImage(String image) { this.image = image; }
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        public String getState() { return state; }
        public void setState(String state) { this.state = state; }
    }
}
