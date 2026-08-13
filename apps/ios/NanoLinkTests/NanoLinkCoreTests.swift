import XCTest
@testable import NanoLink

final class NanoLinkCoreTests: XCTestCase {
    func testJSONCoercesMixedServerPayloadTypes() {
        let json = JSON([
            "integer": "42",
            "decimal": "12.5",
            "enabled": "1",
            "fallbackName": "nano-node"
        ])

        XCTAssertEqual(json.int("integer"), 42)
        XCTAssertEqual(json.double("decimal"), 12.5, accuracy: 0.0001)
        XCTAssertTrue(json.bool("enabled"))
        XCTAssertEqual(json.string("missing", "fallbackName"), "nano-node")
    }

    func testAccountTokenTakesPriorityOverDeviceToken() {
        let connection = ServerConnection(
            name: "Local",
            url: "http://192.168.1.10:8080",
            token: "device-token",
            userToken: "account-token"
        )

        XCTAssertEqual(connection.authToken, "account-token")
        XCTAssertTrue(connection.hasFullPermissions)
    }

    func testSystemInfoAcceptsServerMotherboardModelKey() {
        let info = SystemInfo.from(JSON([
            "hostname": "nano-node",
            "motherboard_model": "NanoBoard X1"
        ]))

        XCTAssertEqual(info.motherboardName, "NanoBoard X1")
    }

    func testDateParserHandlesUnixMilliseconds() {
        let date = DateParse.date(1_700_000_000_000 as NSNumber)

        XCTAssertNotNil(date)
        XCTAssertEqual(date?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 0.001)
    }

    func testAgentDecodesCamelCasePermissionAndHeartbeat() {
        let heartbeat = Date().addingTimeInterval(-5)
        let agent = Agent.from(JSON([
            "id": "agent-1",
            "hostname": "nano-node",
            "permissionLevel": "3",
            "lastHeartbeat": heartbeat.timeIntervalSince1970
        ]), serverId: "server-1")

        XCTAssertEqual(agent.permissionLevel, 3)
        XCTAssertTrue(agent.isOnline)
    }
}
