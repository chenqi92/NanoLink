package com.nanolink.app.data.network

import com.nanolink.app.data.model.NanoJson
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

class ShellSession(
    private val client: OkHttpClient,
    val url: String,
    private val token: String?,
    private val connectionFailedMessage: String = "connection failed",
) {
    enum class Status { CONNECTING, CONNECTED, ERROR, CLOSED }
    enum class LineKind { SYSTEM, INPUT, OUTPUT, ERROR }

    data class Line(
        val id: String = UUID.randomUUID().toString(),
        val kind: LineKind,
        val text: String,
    )

    private val _lines = MutableStateFlow<List<Line>>(emptyList())
    val lines: StateFlow<List<Line>> = _lines.asStateFlow()

    private val _status = MutableStateFlow(Status.CONNECTING)
    val status: StateFlow<Status> = _status.asStateFlow()

    private var socket: WebSocket? = null

    val displayUrl: String get() = url.substringBefore('?')

    fun connect() {
        socket?.cancel()
        _status.value = Status.CONNECTING
        val request = Request.Builder().url(url).apply {
            token?.takeIf(String::isNotEmpty)?.let { header("Authorization", "Bearer $it") }
        }.build()
        socket = client.newWebSocket(request, Listener())
    }

    fun sendInput(command: String) {
        if (_status.value != Status.CONNECTED) return
        val payload = buildJsonObject {
            put("type", "input")
            put("data", command)
        }
        socket?.send(payload.toString())
    }

    fun resize(cols: Int, rows: Int) {
        if (_status.value != Status.CONNECTED) return
        val payload = buildJsonObject {
            put("type", "resize")
            put("cols", cols)
            put("rows", rows)
        }
        socket?.send(payload.toString())
    }

    fun echoInput(text: String) = emit(LineKind.INPUT, text)
    fun system(text: String) = emit(LineKind.SYSTEM, text)
    fun clearLines() { _lines.value = emptyList() }

    fun close() {
        socket?.close(1001, "client closed")
        socket = null
        if (_status.value != Status.ERROR) {
            _status.value = Status.CLOSED
        }
    }

    private fun emit(kind: LineKind, text: String) {
        _lines.value = _lines.value + Line(kind = kind, text = text)
    }

    private inner class Listener : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (socket === webSocket) _status.value = Status.CONNECTED
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (socket !== webSocket) return
            val message = runCatching { NanoJson.parseToJsonElement(text).jsonObject }.getOrNull() ?: return
            val type = message["type"]?.jsonPrimitive?.contentOrNull
            val data = message["data"]?.jsonPrimitive?.contentOrNull.orEmpty()
            when (type) {
                "output" -> {
                    val success = message["success"]?.jsonPrimitive?.booleanOrNull
                    if (data.isNotEmpty()) emit(if (success == false) LineKind.ERROR else LineKind.OUTPUT, data)
                }
                "error" -> emit(LineKind.ERROR, data)
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(code, reason)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            if (socket !== webSocket) return
            socket = null
            if (_status.value != Status.ERROR) _status.value = Status.CLOSED
        }

        override fun onFailure(webSocket: WebSocket, throwable: Throwable, response: Response?) {
            if (socket !== webSocket) return
            socket = null
            emit(LineKind.ERROR, throwable.localizedMessage ?: connectionFailedMessage)
            _status.value = Status.ERROR
        }
    }
}
