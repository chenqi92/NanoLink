import XCTest
@testable import NanoOps

final class NanoOpsCoreTests: XCTestCase {
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

    func testAssistantFindingLocalizesLegacyPayloadAndNormalizesActions() {
        let originalLanguage = L10n.shared.language
        L10n.shared.setLanguage("zh")
        defer { L10n.shared.setLanguage(originalLanguage) }

        let finding = AssistantFinding.from(JSON([
            "kind": "ok",
            "title": "Fleet healthy",
            "detail": "All visible monitored agents are within thresholds.",
            "actions": ["View history", "List processes"],
        ]))

        XCTAssertEqual(finding.title, "节点运行正常")
        XCTAssertEqual(finding.detail, "所有可见监控节点的指标均处于阈值范围内。")
        XCTAssertEqual(finding.actions, ["history"])
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

    func testShellSectionRawValuesKeepTabOrder() {
        XCTAssertEqual(ShellSection.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
        XCTAssertEqual(ShellSection.overview.titleKey, "nav.overview")
        XCTAssertEqual(ShellSection.nodes.icon, "server.rack")
        XCTAssertEqual(ShellSection(rawValue: 3), .activity)
    }

    func testAgentSelectionResolvesOnlyVisibleNodes() {
        let agents = [
            Agent.from(JSON(["id": "agent-1", "hostname": "one"]), serverId: "server-1"),
            Agent.from(JSON(["id": "agent-2", "hostname": "two"]), serverId: "server-1")
        ]

        XCTAssertEqual(AgentSelection.resolve("agent-2", in: agents), "agent-2")
        XCTAssertNil(AgentSelection.resolve("agent-3", in: agents), "removed node must not stay selected")
        XCTAssertNil(AgentSelection.resolve("agent-1", in: []), "server switch empties the visible set")
        XCTAssertNil(AgentSelection.resolve(nil, in: agents))
    }

    func testShellRouterSelectingNodeLandsOnNodesSection() {
        let router = ShellRouter()

        router.show(.settings)
        XCTAssertEqual(router.section, .settings)
        XCTAssertNil(router.selectedAgentID, "showing a section must not select a node")

        router.select(agentID: "agent-1")
        XCTAssertEqual(router.selectedAgentID, "agent-1")
        XCTAssertEqual(router.section, .nodes)
        XCTAssertEqual(router.nodesFilter, "all")

        router.show(.terminal)
        XCTAssertEqual(router.selectedAgentID, "agent-1", "section switch keeps the selected node")

        router.clearSelection()
        XCTAssertNil(router.selectedAgentID)
        XCTAssertEqual(router.section, .terminal, "clearing selection must not move the section")
    }

    func testShellRouterShowsFilteredNodeWorkspaceWithoutSelection() {
        let router = ShellRouter()
        router.select(agentID: "agent-1")

        router.showNodes(filter: "offline")

        XCTAssertEqual(router.section, .nodes)
        XCTAssertEqual(router.nodesFilter, "offline")
        XCTAssertNil(router.selectedAgentID)
    }

    func testShellRouterSelectingNilDoesNotSwitchSection() {
        let router = ShellRouter()
        router.show(.activity)

        router.select(agentID: nil)

        XCTAssertNil(router.selectedAgentID)
        XCTAssertEqual(router.section, .activity)
    }

    func testShellRouterRefreshTickAdvancesPerRequest() {
        let router = ShellRouter()

        XCTAssertEqual(router.refreshTick, 0)
        router.requestRefresh()
        router.requestRefresh()
        XCTAssertEqual(router.refreshTick, 2)
    }
}
