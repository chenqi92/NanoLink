package com.nanolink.app.ui

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.screens.ActivityScreen
import com.nanolink.app.ui.screens.AddServerScreen
import com.nanolink.app.ui.screens.AgentDetailScreen
import com.nanolink.app.ui.screens.DashboardScreen
import com.nanolink.app.ui.screens.NodesScreen
import com.nanolink.app.ui.screens.ServerDetailScreen
import com.nanolink.app.ui.screens.SettingsScreen
import com.nanolink.app.ui.screens.TerminalScreen

sealed class MainTab(val route: String, val labelKey: String) {
    data object Dashboard : MainTab("dashboard", "nav.overview")
    data object Nodes : MainTab("nodes", "nav.nodes")
    data object Terminal : MainTab("terminal", "nav.terminal")
    data object Activity : MainTab("activity", "nav.activity")
    data object Settings : MainTab("settings", "nav.settings")
}

private object DetailRoute {
    const val AddServer = "add-server"
    const val Server = "server/{serverId}"
    const val Agent = "agent/{agentId}"
    const val AgentTerminal = "agent-terminal/{agentId}"

    fun server(serverId: String) = "server/${Uri.encode(serverId)}"
    fun agent(agentId: String) = "agent/${Uri.encode(agentId)}"
    fun terminal(agentId: String) = "agent-terminal/${Uri.encode(agentId)}"
}

@Composable
fun NanoShell(viewModel: AppViewModel, modifier: Modifier = Modifier) {
    val navController = rememberNavController()
    val t = nano
    val unackedCount by viewModel.unackedAlertCount.collectAsStateWithLifecycle()
    val servers by viewModel.servers.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val tabRoutes = setOf(
        MainTab.Dashboard.route,
        MainTab.Nodes.route,
        MainTab.Terminal.route,
        MainTab.Activity.route,
        MainTab.Settings.route,
    )

    LaunchedEffect(isLoading, servers.isEmpty(), currentRoute) {
        if (!isLoading && servers.isEmpty() && currentRoute != DetailRoute.AddServer) {
            navController.navigate(DetailRoute.AddServer) { launchSingleTop = true }
        }
    }

    fun navigateToTab(tab: MainTab) {
        navController.navigate(tab.route) {
            popUpTo(MainTab.Dashboard.route) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    Scaffold(
        modifier = modifier,
        containerColor = t.bg,
        bottomBar = {
            if (currentRoute in tabRoutes) {
                NanoTabBar(
                    navController = navController,
                    unackedCount = unackedCount,
                )
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = MainTab.Dashboard.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(MainTab.Dashboard.route) {
                DashboardScreen(
                    viewModel = viewModel,
                    onAddServer = { navController.navigate(DetailRoute.AddServer) },
                    onNavigateToNodes = { navigateToTab(MainTab.Nodes) },
                    onNavigateToSettings = { navigateToTab(MainTab.Settings) },
                    onOpenServer = { serverId -> navController.navigate(DetailRoute.server(serverId)) },
                )
            }
            composable(MainTab.Nodes.route) {
                NodesScreen(
                    viewModel,
                    onNavigateToDetail = { agent -> navController.navigate(DetailRoute.agent(agent.id)) },
                )
            }
            composable(MainTab.Terminal.route) { TerminalScreen(viewModel) }
            composable(MainTab.Activity.route) { ActivityScreen(viewModel) }
            composable(MainTab.Settings.route) {
                SettingsScreen(
                    viewModel = viewModel,
                    onAddServer = { navController.navigate(DetailRoute.AddServer) },
                    onOpenServer = { serverId -> navController.navigate(DetailRoute.server(serverId)) },
                )
            }
            composable(DetailRoute.AddServer) {
                AddServerScreen(
                    viewModel = viewModel,
                    onBack = navController::navigateUp,
                    onAdded = {
                        navController.navigate(MainTab.Dashboard.route) {
                            popUpTo(DetailRoute.AddServer) { inclusive = true }
                            launchSingleTop = true
                        }
                    },
                )
            }
            composable(
                route = DetailRoute.Server,
                arguments = listOf(navArgument("serverId") { type = NavType.StringType }),
            ) { entry ->
                ServerDetailScreen(
                    viewModel = viewModel,
                    serverId = entry.arguments?.getString("serverId").orEmpty(),
                    onBack = navController::navigateUp,
                    onRemoved = navController::navigateUp,
                )
            }
            composable(
                route = DetailRoute.Agent,
                arguments = listOf(navArgument("agentId") { type = NavType.StringType }),
            ) { entry ->
                val agentId = entry.arguments?.getString("agentId").orEmpty()
                AgentDetailScreen(
                    viewModel = viewModel,
                    agentId = agentId,
                    onBack = navController::navigateUp,
                    onOpenTerminal = { navController.navigate(DetailRoute.terminal(agentId)) },
                )
            }
            composable(
                route = DetailRoute.AgentTerminal,
                arguments = listOf(navArgument("agentId") { type = NavType.StringType }),
            ) { entry ->
                TerminalScreen(
                    viewModel = viewModel,
                    initialAgentId = entry.arguments?.getString("agentId"),
                    onBack = navController::navigateUp,
                )
            }
        }
    }
}

@Composable
private fun NanoTabBar(
    navController: NavHostController,
    unackedCount: Int,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    val tabs = listOf(
        Triple(MainTab.Dashboard, Icons.Outlined.Dashboard, null),
        Triple(MainTab.Nodes, Icons.AutoMirrored.Filled.List, null),
        Triple(MainTab.Terminal, Icons.Outlined.Terminal, null),
        Triple(MainTab.Activity, Icons.Default.Notifications, unackedCount.takeIf { it > 0 }),
        Triple(MainTab.Settings, Icons.Default.Settings, null),
    )

    if (t.isIOS) {
        // iOS-style raised translucent bar with glass border.
        Box(
            modifier = modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(t.glassBorder),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .background(t.tabBg)
                .padding(horizontal = 8.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            tabs.forEach { (tab, icon, badge) ->
                val selected = currentRoute == tab.route
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .clickable {
                            navController.navigate(tab.route) {
                                popUpTo(MainTab.Dashboard.route) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                        .padding(vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    BadgedBox(
                        badge = {
                            if (badge != null) {
                                Badge(
                                    containerColor = t.crit,
                                    contentColor = t.onAccent,
                                    modifier = Modifier.size(16.dp),
                                ) {
                                    Text(badge.toString(), fontSize = 10.sp)
                                }
                            }
                        },
                    ) {
                        Icon(
                            icon,
                            contentDescription = null,
                            tint = if (selected) t.accent else t.fg3,
                            modifier = Modifier.size(24.dp),
                        )
                    }
                    Text(
                        text = tr(tab.labelKey),
                        fontSize = 10.sp,
                        color = if (selected) t.accent else t.fg3,
                    )
                }
            }
        }
    } else {
        // Material 3 standard navigation bar.
        NavigationBar(containerColor = t.tabBg, tonalElevation = 0.dp) {
            tabs.forEach { (tab, icon, badge) ->
                val selected = currentRoute == tab.route
                NavigationBarItem(
                    selected = selected,
                    onClick = {
                        navController.navigate(tab.route) {
                            popUpTo(MainTab.Dashboard.route) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    icon = {
                        BadgedBox(
                            badge = {
                                if (badge != null) {
                                    Badge(
                                        containerColor = t.crit,
                                        contentColor = t.onAccent,
                                    ) {
                                        Text(badge.toString())
                                    }
                                }
                            },
                        ) {
                            Icon(icon, contentDescription = null)
                        }
                    },
                    label = { Text(tr(tab.labelKey)) },
                )
            }
        }
    }
}
