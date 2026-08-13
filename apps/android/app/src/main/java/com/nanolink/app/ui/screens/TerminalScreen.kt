package com.nanolink.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nanolink.app.data.model.Agent
import com.nanolink.app.data.network.ShellSession
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoEmptyState
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.NanoStatusDot
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr

@Composable
fun TerminalScreen(
    viewModel: AppViewModel,
    modifier: Modifier = Modifier,
    initialAgentId: String? = null,
    onBack: (() -> Unit)? = null,
) {
    val t = nano
    val allAgents by viewModel.agents.collectAsStateWithLifecycle()
    val activeServerId by viewModel.activeServerId.collectAsStateWithLifecycle()
    val activeAgents = allAgents.filter { it.serverId == activeServerId && it.isOnline }
    val terminalAgents = activeAgents.filter { it.permissionLevel >= 3 }
    val requestedAgent = initialAgentId?.let { id -> activeAgents.firstOrNull { it.id == id } }

    var selectedAgentId by remember(activeServerId, initialAgentId) {
        mutableStateOf(initialAgentId)
    }
    LaunchedEffect(terminalAgents, initialAgentId) {
        selectedAgentId = when {
            initialAgentId != null && terminalAgents.any { it.id == initialAgentId } -> initialAgentId
            terminalAgents.any { it.id == selectedAgentId } -> selectedAgentId
            else -> terminalAgents.firstOrNull()?.id
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        TerminalHeader(onBack)

        when {
            requestedAgent != null && requestedAgent.permissionLevel < 3 -> {
                Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
                    NanoEmptyState(
                        icon = Icons.Outlined.Terminal,
                        title = tr("terminal.lockedTitle"),
                        detail = tr("terminal.lockedDesc"),
                    )
                }
            }

            activeServerId == null || terminalAgents.isEmpty() -> {
                Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
                    NanoEmptyState(
                        icon = Icons.Outlined.Terminal,
                        title = tr("terminal.noAvailableNodes"),
                        detail = tr("terminal.noAvailableNodesSub"),
                    )
                }
            }

            else -> {
                val selectedAgent = terminalAgents.firstOrNull { it.id == selectedAgentId }
                    ?: terminalAgents.first()
                AgentSelector(
                    agents = terminalAgents,
                    selected = selectedAgent,
                    onSelect = { selectedAgentId = it.id },
                )
                LiveTerminal(viewModel, selectedAgent, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun TerminalHeader(onBack: (() -> Unit)?) {
    val t = nano
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 8.dp, end = 16.dp, top = if (t.isIOS) 28.dp else 4.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Outlined.ArrowBack,
                    contentDescription = tr("common.cancel"),
                    tint = t.fg,
                )
            }
        }
        Text(
            tr("terminal.title"),
            fontSize = if (t.isIOS) 32.sp else 28.sp,
            fontWeight = if (t.isIOS) FontWeight.Bold else FontWeight.SemiBold,
            color = t.fg,
        )
    }
}

@Composable
private fun AgentSelector(agents: List<Agent>, selected: Agent, onSelect: (Agent) -> Unit) {
    val t = nano
    var expanded by remember { mutableStateOf(false) }
    Box(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(t.cardRadius))
                .background(t.card)
                .clickable { expanded = true }
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NanoStatusDot(color = t.ok, pulse = true)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text(selected.hostname, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = t.fg)
                Text(
                    "${selected.os} ${selected.arch} · L${selected.permissionLevel}",
                    fontSize = 11.sp,
                    fontFamily = NanoMonoFamily,
                    color = t.fg4,
                )
            }
            if (agents.size > 1) {
                Icon(Icons.Outlined.ExpandMore, contentDescription = tr("terminal.switchAgent"), tint = t.fg3)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            agents.forEach { agent ->
                DropdownMenuItem(
                    text = { Text("${agent.hostname} · L${agent.permissionLevel}") },
                    onClick = {
                        onSelect(agent)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
private fun LiveTerminal(viewModel: AppViewModel, agent: Agent, modifier: Modifier = Modifier) {
    val t = nano
    val service = viewModel.serviceForAgent(agent.id)
    val connectingMessage = tr("terminal.consoleConnecting", "url" to (service?.connection?.url ?: "—"))
    var session by remember(agent.id) { mutableStateOf<ShellSession?>(null) }

    DisposableEffect(agent.id, service) {
        val created = service?.openShell(agent.id)
        session = created
        created?.system(connectingMessage)
        created?.connect()
        onDispose {
            created?.close()
            if (session === created) session = null
        }
    }

    val activeSession = session
    if (activeSession == null) {
        Box(modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
            NanoEmptyState(
                icon = Icons.Outlined.Terminal,
                title = tr("status.error"),
                detail = tr("terminal.consoleNoServer"),
            )
        }
    } else {
        TerminalConsole(agent, activeSession, modifier)
    }
}

@Composable
private fun TerminalConsole(agent: Agent, session: ShellSession, modifier: Modifier = Modifier) {
    val t = nano
    val lines by session.lines.collectAsStateWithLifecycle()
    val status by session.status.collectAsStateWithLifecycle()
    var input by remember(session) { mutableStateOf("") }
    val listState = rememberLazyListState()
    val authenticatedMessage = tr("terminal.consoleAuthenticated", "level" to agent.permissionLevel)

    LaunchedEffect(status) {
        if (status == ShellSession.Status.CONNECTED) {
            session.system(authenticatedMessage)
            session.resize(cols = 120, rows = 40)
        }
    }
    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) listState.animateScrollToItem(lines.lastIndex)
    }

    fun submit() {
        val command = input.trim()
        if (command.isEmpty() || status != ShellSession.Status.CONNECTED) return
        session.echoInput("$ $command")
        session.sendInput(command)
        input = ""
    }

    Column(modifier = modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = t.cardRadius, topEnd = t.cardRadius))
                .background(t.card)
                .padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NanoStatusDot(color = terminalStatusColor(status), pulse = status == ShellSession.Status.CONNECTED)
            Spacer(Modifier.width(8.dp))
            Text(terminalStatusLabel(status), fontSize = 11.sp, fontFamily = NanoMonoFamily, color = t.fg3)
            Spacer(Modifier.weight(1f))
            if (status == ShellSession.Status.ERROR || status == ShellSession.Status.CLOSED) {
                IconButton(onClick = session::connect) {
                    Icon(Icons.Outlined.Refresh, contentDescription = tr("status.reconnect"), tint = t.accent)
                }
            }
            IconButton(onClick = session::clearLines) {
                Icon(Icons.Outlined.Delete, contentDescription = tr("terminal.clear"), tint = t.fg3)
            }
        }

        LazyColumn(
            state = listState,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .background(t.bg.copy(alpha = 0.55f))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            items(lines, key = { it.id }) { line ->
                val color = when (line.kind) {
                    ShellSession.LineKind.SYSTEM -> t.fg4
                    ShellSession.LineKind.INPUT -> t.accent
                    ShellSession.LineKind.OUTPUT -> t.fg2
                    ShellSession.LineKind.ERROR -> t.crit
                }
                Text(
                    line.text,
                    fontSize = 13.sp,
                    fontFamily = NanoMonoFamily,
                    color = color,
                    lineHeight = 18.sp,
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(bottomStart = t.cardRadius, bottomEnd = t.cardRadius))
                .background(t.card)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("$", fontSize = 15.sp, fontFamily = NanoMonoFamily, fontWeight = FontWeight.Bold, color = t.accent)
            BasicTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f),
                textStyle = androidx.compose.ui.text.TextStyle(
                    fontSize = 14.sp,
                    fontFamily = NanoMonoFamily,
                    color = t.fg,
                ),
                cursorBrush = SolidColor(t.accent),
                enabled = status == ShellSession.Status.CONNECTED,
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { submit() }),
                decorationBox = { innerTextField ->
                    Box {
                        if (input.isEmpty()) {
                            Text(
                                if (status == ShellSession.Status.CONNECTED) tr("terminal.inputHint")
                                else tr("terminal.inputHintWaiting"),
                                fontSize = 14.sp,
                                fontFamily = NanoMonoFamily,
                                color = t.fg4,
                            )
                        }
                        innerTextField()
                    }
                },
            )
            IconButton(onClick = ::submit, enabled = input.isNotBlank() && status == ShellSession.Status.CONNECTED) {
                Icon(
                    Icons.AutoMirrored.Outlined.Send,
                    contentDescription = tr("terminal.inputHint"),
                    tint = if (input.isNotBlank() && status == ShellSession.Status.CONNECTED) t.accent else t.fg4,
                )
            }
        }
    }
}

@Composable
private fun terminalStatusLabel(status: ShellSession.Status): String = when (status) {
    ShellSession.Status.CONNECTING -> tr("status.connecting")
    ShellSession.Status.CONNECTED -> tr("status.connected")
    ShellSession.Status.ERROR -> tr("status.error")
    ShellSession.Status.CLOSED -> tr("status.closed")
}

@Composable
private fun terminalStatusColor(status: ShellSession.Status) = when (status) {
    ShellSession.Status.CONNECTING -> nano.warn
    ShellSession.Status.CONNECTED -> nano.ok
    ShellSession.Status.ERROR -> nano.crit
    ShellSession.Status.CLOSED -> nano.fg4
}
