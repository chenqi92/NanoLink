package com.kkape.demo;

import com.kkape.sdk.TokenValidator;
import com.kkape.sdk.model.Command;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Permission level tests for NanoLink
 *
 * Permission Levels:
 * - 0 (READ_ONLY): Can view metrics, process list, service status, docker list, file tail
 * - 1 (BASIC_WRITE): Level 0 + file download, file truncate, docker logs
 * - 2 (SERVICE_CONTROL): Level 1 + process kill, service start/stop/restart, docker start/stop/restart, file upload
 * - 3 (SYSTEM_ADMIN): Level 2 + system reboot, shell execute
 */
public class PermissionTest {

    @Test
    @DisplayName("Level 0 - READ_ONLY commands should require permission 0")
    void testLevel0Commands() {
        assertEquals(TokenValidator.PermissionLevel.READ_ONLY, Command.Type.PROCESS_LIST.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.READ_ONLY, Command.Type.SERVICE_STATUS.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.READ_ONLY, Command.Type.DOCKER_LIST.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.READ_ONLY, Command.Type.FILE_TAIL.getRequiredPermission());
    }

    @Test
    @DisplayName("Level 1 - BASIC_WRITE commands should require permission 1")
    void testLevel1Commands() {
        assertEquals(TokenValidator.PermissionLevel.BASIC_WRITE, Command.Type.FILE_DOWNLOAD.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.BASIC_WRITE, Command.Type.FILE_TRUNCATE.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.BASIC_WRITE, Command.Type.DOCKER_LOGS.getRequiredPermission());
    }

    @Test
    @DisplayName("Level 2 - SERVICE_CONTROL commands should require permission 2")
    void testLevel2Commands() {
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.PROCESS_KILL.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.SERVICE_START.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.SERVICE_STOP.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.SERVICE_RESTART.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.DOCKER_START.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.DOCKER_STOP.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.DOCKER_RESTART.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SERVICE_CONTROL, Command.Type.FILE_UPLOAD.getRequiredPermission());
    }

    @Test
    @DisplayName("Level 3 - SYSTEM_ADMIN commands should require permission 3")
    void testLevel3Commands() {
        assertEquals(TokenValidator.PermissionLevel.SYSTEM_ADMIN, Command.Type.SYSTEM_REBOOT.getRequiredPermission());
        assertEquals(TokenValidator.PermissionLevel.SYSTEM_ADMIN, Command.Type.SHELL_EXECUTE.getRequiredPermission());
    }

    @Test
    @DisplayName("Token with permission 0 should only access level 0 commands")
    void testPermission0Access() {
        int userPermission = TokenValidator.PermissionLevel.READ_ONLY;

        // Should be allowed
        assertTrue(Command.Type.PROCESS_LIST.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.SERVICE_STATUS.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.DOCKER_LIST.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.FILE_TAIL.getRequiredPermission() <= userPermission);

        // Should be denied
        assertFalse(Command.Type.FILE_DOWNLOAD.getRequiredPermission() <= userPermission);
        assertFalse(Command.Type.PROCESS_KILL.getRequiredPermission() <= userPermission);
        assertFalse(Command.Type.SYSTEM_REBOOT.getRequiredPermission() <= userPermission);
        assertFalse(Command.Type.SHELL_EXECUTE.getRequiredPermission() <= userPermission);
    }

    @Test
    @DisplayName("Token with permission 1 should access level 0 and 1 commands")
    void testPermission1Access() {
        int userPermission = TokenValidator.PermissionLevel.BASIC_WRITE;

        // Level 0 - Should be allowed
        assertTrue(Command.Type.PROCESS_LIST.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.SERVICE_STATUS.getRequiredPermission() <= userPermission);

        // Level 1 - Should be allowed
        assertTrue(Command.Type.FILE_DOWNLOAD.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.FILE_TRUNCATE.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.DOCKER_LOGS.getRequiredPermission() <= userPermission);

        // Level 2 and above - Should be denied
        assertFalse(Command.Type.PROCESS_KILL.getRequiredPermission() <= userPermission);
        assertFalse(Command.Type.SERVICE_START.getRequiredPermission() <= userPermission);
        assertFalse(Command.Type.SYSTEM_REBOOT.getRequiredPermission() <= userPermission);
    }

    @Test
    @DisplayName("Token with permission 2 should access level 0, 1, and 2 commands")
    void testPermission2Access() {
        int userPermission = TokenValidator.PermissionLevel.SERVICE_CONTROL;

        // Level 0 - Should be allowed
        assertTrue(Command.Type.PROCESS_LIST.getRequiredPermission() <= userPermission);

        // Level 1 - Should be allowed
        assertTrue(Command.Type.FILE_DOWNLOAD.getRequiredPermission() <= userPermission);

        // Level 2 - Should be allowed
        assertTrue(Command.Type.PROCESS_KILL.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.SERVICE_START.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.SERVICE_STOP.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.DOCKER_START.getRequiredPermission() <= userPermission);
        assertTrue(Command.Type.FILE_UPLOAD.getRequiredPermission() <= userPermission);

        // Level 3 - Should be denied
        assertFalse(Command.Type.SYSTEM_REBOOT.getRequiredPermission() <= userPermission);
        assertFalse(Command.Type.SHELL_EXECUTE.getRequiredPermission() <= userPermission);
    }

    @Test
    @DisplayName("Token with permission 3 should access all commands")
    void testPermission3Access() {
        int userPermission = TokenValidator.PermissionLevel.SYSTEM_ADMIN;

        // All levels should be allowed
        for (Command.Type type : Command.Type.values()) {
            assertTrue(type.getRequiredPermission() <= userPermission,
                    "SYSTEM_ADMIN should have access to " + type.name());
        }
    }

    @Test
    @DisplayName("Permission escalation should be prevented")
    void testNoPrivilegeEscalation() {
        // Verify that lower permission levels cannot access higher permission commands
        for (int level = 0; level < TokenValidator.PermissionLevel.SYSTEM_ADMIN; level++) {
            for (Command.Type type : Command.Type.values()) {
                if (type.getRequiredPermission() > level) {
                    assertFalse(type.getRequiredPermission() <= level,
                            "Permission level " + level + " should NOT access " + type.name());
                }
            }
        }
    }

    @Test
    @DisplayName("TokenValidator should correctly validate permissions")
    void testTokenValidator() {
        // Create token validators for different permission levels
        TokenValidator readOnlyValidator = token ->
            new TokenValidator.ValidationResult(true, TokenValidator.PermissionLevel.READ_ONLY, null);

        TokenValidator basicWriteValidator = token ->
            new TokenValidator.ValidationResult(true, TokenValidator.PermissionLevel.BASIC_WRITE, null);

        TokenValidator serviceControlValidator = token ->
            new TokenValidator.ValidationResult(true, TokenValidator.PermissionLevel.SERVICE_CONTROL, null);

        TokenValidator adminValidator = token ->
            new TokenValidator.ValidationResult(true, TokenValidator.PermissionLevel.SYSTEM_ADMIN, null);

        // Test each validator
        assertEquals(0, readOnlyValidator.validate("test").getPermissionLevel());
        assertEquals(1, basicWriteValidator.validate("test").getPermissionLevel());
        assertEquals(2, serviceControlValidator.validate("test").getPermissionLevel());
        assertEquals(3, adminValidator.validate("test").getPermissionLevel());
    }
}
