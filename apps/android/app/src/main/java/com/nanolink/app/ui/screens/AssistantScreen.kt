package com.nanolink.app.ui.screens

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Error
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nanolink.app.data.model.AssistantChatError
import com.nanolink.app.data.model.AssistantFinding
import com.nanolink.app.data.model.ChatMessage
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr
import kotlinx.coroutines.launch
import java.util.UUID

private data class AssistantTurn(
    val id: String = UUID.randomUUID().toString(),
    val role: String,
    val content: String,
    val isError: Boolean = false,
)

@Composable
fun AssistantScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenAgent: (String) -> Unit,
    onOpenTerminal: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val turns = remember { mutableStateListOf<AssistantTurn>() }
    var findings by remember { mutableStateOf<List<AssistantFinding>>(emptyList()) }
    var inputText by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }

    fun send(preset: String? = null) {
        val message = preset ?: inputText.trim()
        if (message.isEmpty() || sending) return

        turns.add(AssistantTurn(role = "user", content = message))
        inputText = ""
        sending = true

        scope.launch {
            val history = turns.map { ChatMessage(role = it.role, content = it.content) }
            val service = viewModel.activeServer?.id?.let(viewModel::serviceForServer)
            if (service == null) {
                sending = false
                turns.add(
                    AssistantTurn(
                        role = "assistant",
                        content = viewModel.localization.text("errors.serverNotConnected"),
                        isError = true,
                    ),
                )
                return@launch
            }
            val result = service.assistantChat(history)
            sending = false

            if (result.ok && result.reply != null) {
                turns.add(AssistantTurn(role = result.reply.role, content = result.reply.content))
            } else {
                val errorMsg = when (result.error) {
                    AssistantChatError.NOT_CONFIGURED -> viewModel.localization.text("assistant.error.notConfigured")
                    AssistantChatError.BAD_REQUEST -> viewModel.localization.text("assistant.error.badRequest")
                    AssistantChatError.UPSTREAM_FAILED -> viewModel.localization.text("assistant.error.upstreamFailed")
                    AssistantChatError.SERVER_ERROR -> viewModel.localization.text("assistant.error.serverError")
                    AssistantChatError.NETWORK -> viewModel.localization.text("assistant.error.network")
                    else -> result.message ?: viewModel.localization.text("assistant.error.unknown")
                }
                turns.add(AssistantTurn(role = "assistant", content = errorMsg, isError = true))
            }
        }
    }

    LaunchedEffect(Unit) {
        val result = viewModel.activeServer?.id
            ?.let(viewModel::serviceForServer)
            ?.fetchAssistantFindings()
        if (result != null) findings = result
    }

    LaunchedEffect(turns.size, sending) {
        if (turns.isNotEmpty() || sending) {
            val target = if (sending) turns.size else turns.size - 1
            listState.animateScrollToItem(target.coerceAtLeast(0))
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = tr("common.cancel"), tint = t.fg)
            }
            Icon(Icons.Outlined.AutoAwesome, contentDescription = null, tint = t.accent, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                tr("assistant.title"),
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                color = t.fg,
            )
        }

        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (findings.isNotEmpty()) {
                item { FindingsSection(findings, onOpenAgent, onOpenTerminal) }
            }

            if (turns.isEmpty() && !sending) {
                item { EmptyChatState(onSendPreset = ::send) }
            }

            items(turns, key = { it.id }) { turn ->
                ChatBubble(turn)
            }

            if (sending) {
                item { ThinkingBubble() }
            }
        }

        Composer(
            value = inputText,
            onValueChange = { inputText = it },
            onSend = { send() },
            enabled = !sending,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FindingsSection(
    findings: List<AssistantFinding>,
    onOpenAgent: (String) -> Unit,
    onOpenTerminal: (String) -> Unit,
) {
    val t = nano
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            tr("assistant.diagnosis"),
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = t.fg3,
        )
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            findings.forEach { finding ->
                FindingCard(finding, onOpenAgent, onOpenTerminal)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FindingCard(
    finding: AssistantFinding,
    onOpenAgent: (String) -> Unit,
    onOpenTerminal: (String) -> Unit,
) {
    val t = nano
    val (icon, tone) = when (finding.kind) {
        "anomaly" -> Icons.Outlined.Bolt to t.crit
        "warn" -> Icons.Outlined.Warning to t.warn
        "info" -> Icons.Outlined.Info to t.info
        "ok" -> Icons.Outlined.CheckCircle to t.ok
        else -> Icons.Outlined.Info to t.fg3
    }

    NanoCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = tone, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Text(finding.title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = t.fg)
            }
            Text(finding.detail, fontSize = 12.sp, color = t.fg3, lineHeight = 16.sp)

            if (finding.actions.isNotEmpty() && finding.agentId != null) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    finding.actions.forEach { action ->
                        ActionChip(
                            label = tr("assistant.action.$action"),
                            onClick = {
                                when (action) {
                                    "history" -> onOpenAgent(finding.agentId)
                                    "shell", "terminal" -> onOpenTerminal(finding.agentId)
                                    else -> onOpenAgent(finding.agentId)
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ActionChip(label: String, onClick: () -> Unit) {
    val t = nano
    Box(
        modifier = Modifier
            .height(24.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(t.accent.copy(alpha = 0.14f))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = t.accent,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EmptyChatState(onSendPreset: (String) -> Unit) {
    val t = nano
    val suggestions = listOf(
        tr("assistant.suggestion.highCpu"),
        tr("assistant.suggestion.diskSpace"),
        tr("assistant.suggestion.offlineNodes"),
        tr("assistant.suggestion.resourceTrend"),
    )

    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(Icons.Outlined.AutoAwesome, contentDescription = null, tint = t.fg4, modifier = Modifier.size(42.dp))
        Text(tr("assistant.greeting"), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = t.fg)
        Text(
            tr("assistant.intro"),
            fontSize = 13.sp,
            color = t.fg3,
            modifier = Modifier.padding(horizontal = 24.dp),
        )

        Spacer(Modifier.height(8.dp))
        Text(tr("assistant.tryThese"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = t.fg3)

        FlowRow(
            modifier = Modifier.padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            suggestions.forEach { suggestion ->
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(t.card2)
                        .clickable { onSendPreset(suggestion) }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                ) {
                    Text(suggestion, fontSize = 12.sp, color = t.fg2)
                }
            }
        }
    }
}

@Composable
private fun ChatBubble(turn: AssistantTurn) {
    val t = nano
    val isUser = turn.role == "user"
    val bgColor = if (isUser) t.accent.copy(alpha = 0.14f) else if (turn.isError) t.crit.copy(alpha = 0.12f) else t.card2
    val textColor = if (isUser) t.fg else if (turn.isError) t.crit else t.fg2

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(16.dp))
                .background(bgColor)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            Text(
                turn.content,
                fontSize = 14.sp,
                color = textColor,
                lineHeight = 19.sp,
            )
        }
    }
}

@Composable
private fun ThinkingBubble() {
    val t = nano
    val transition = rememberInfiniteTransition(label = "thinking")
    val progress = transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1_200, easing = LinearEasing), RepeatMode.Restart),
        label = "thinkingProgress",
    ).value

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
    ) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(16.dp))
                .background(t.card2)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(3) { index ->
                    Box(
                        modifier = Modifier
                            .size(6.dp)
                            .scale(1f + 0.4f * kotlin.math.sin((progress + index * 0.33f) * 2 * kotlin.math.PI.toFloat()))
                            .alpha(0.4f + 0.4f * kotlin.math.sin((progress + index * 0.33f) * 2 * kotlin.math.PI.toFloat()))
                            .background(t.fg3, CircleShape),
                    )
                }
            }
        }
    }
}

@Composable
private fun Composer(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    enabled: Boolean,
) {
    val t = nano
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(t.bg)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text(tr("assistant.inputHint"), color = t.fg4, fontSize = 14.sp) },
            colors = TextFieldDefaults.colors(
                focusedContainerColor = t.card,
                unfocusedContainerColor = t.card,
                disabledContainerColor = t.card,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent,
            ),
            shape = RoundedCornerShape(20.dp),
            modifier = Modifier.weight(1f),
            enabled = enabled,
        )
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(if (enabled && value.trim().isNotEmpty()) t.accent else t.card2)
                .clickable(enabled = enabled && value.trim().isNotEmpty(), onClick = onSend),
            contentAlignment = Alignment.Center,
        ) {
            if (enabled && value.trim().isNotEmpty()) {
                Icon(
                    Icons.Outlined.AutoAwesome,
                    contentDescription = tr("common.send"),
                    tint = t.onAccent,
                    modifier = Modifier.size(20.dp),
                )
            } else {
                CircularProgressIndicator(
                    color = t.fg4,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp).alpha(if (enabled) 0f else 1f),
                )
            }
        }
    }
}
