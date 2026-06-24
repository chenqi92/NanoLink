package com.kkape.sdk;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.kkape.sdk.model.Command;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Per-command permission-matrix tests.
 *
 * Loads the canonical matrix from sdk/protocol/permissions.json and asserts that
 * the Java SDK's own command -> required-permission map matches it exactly, so
 * any future drift between the three SDKs is caught here.
 */
class CommandPermissionTest {

    // Maven runs with the module dir (sdk/java) as the working directory.
    private static final Path PERMISSIONS_JSON =
            Paths.get("..", "protocol", "permissions.json");

    private JsonObject loadMatrix() throws IOException {
        String json = new String(Files.readAllBytes(PERMISSIONS_JSON), StandardCharsets.UTF_8);
        return JsonParser.parseString(json).getAsJsonObject();
    }

    @Test
    @DisplayName("permissions.json exists and is readable")
    void testMatrixFileExists() {
        assertTrue(Files.isRegularFile(PERMISSIONS_JSON),
                "missing " + PERMISSIONS_JSON.toAbsolutePath());
    }

    @Test
    @DisplayName("Every command type matches the canonical permission matrix")
    void testRequiredPermissionMatrix() throws IOException {
        JsonObject matrix = loadMatrix();
        JsonArray commands = matrix.getAsJsonArray("commands");

        // "UNSPECIFIED" is the default/unknown sentinel and has no Java enum
        // constant; it is validated separately via the null-type default below.
        Set<String> jsonEnumNames = new HashSet<>();

        for (int i = 0; i < commands.size(); i++) {
            JsonObject entry = commands.get(i).getAsJsonObject();
            String name = entry.get("name").getAsString();
            int code = entry.get("code").getAsInt();
            int level = entry.get("level").getAsInt();

            if ("UNSPECIFIED".equals(name)) {
                assertEquals(matrix.get("default").getAsInt(), level,
                        "UNSPECIFIED level must equal the fail-closed default");
                continue;
            }

            jsonEnumNames.add(name);
            Command.Type type = Command.Type.valueOf(name);
            assertEquals(code, type.getCode(),
                    name + ": enum code " + type.getCode() + " != json code " + code);
            assertEquals(level, type.getRequiredPermission(),
                    name + " (code " + code + "): got level " + type.getRequiredPermission()
                            + ", expected " + level);
        }

        // The canonical matrix (minus the UNSPECIFIED sentinel) and the Java enum
        // must describe exactly the same command set.
        Set<String> enumNames = new HashSet<>();
        for (Command.Type t : Command.Type.values()) {
            enumNames.add(t.name());
        }
        assertEquals(jsonEnumNames, enumNames, "command set drift between enum and permissions.json");
    }

    @Test
    @DisplayName("Unknown/null command fails closed at the default level")
    void testDefaultFailClosed() throws IOException {
        JsonObject matrix = loadMatrix();
        int expectedDefault = matrix.get("default").getAsInt();
        // A command with no type set resolves to the fail-closed default.
        Command cmd = new Command();
        assertEquals(expectedDefault, cmd.getRequiredPermission());
    }
}
