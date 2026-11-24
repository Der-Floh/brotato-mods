extends Reference

const JsonValue := preload("res://mods-unpacked/der_floh-test_harness/json_value.gd")
const BIND_ADDRESS := "127.0.0.1"
const TOKEN_HEADER := "x-harness-token"
const HEADER_END := "\r\n\r\n"
const CONTINUE_RESPONSE := "HTTP/1.1 100 Continue\r\n\r\n"
const REQUEST_TIMEOUT_MS := 10000
const MAX_REQUEST_BYTES := 1048576
const STATUS_TEXT := {200: "OK", 400: "Bad Request", 401: "Unauthorized", 413: "Payload Too Large"}

var _listener := TCP_Server.new()
var _token := ""
var _router: Object
var _route_method := ""
var _connections := []


func start(port: int, token: String, router: Object, route_method: String) -> int:
	_token = token
	_router = router
	_route_method = route_method
	return _listener.listen(port, BIND_ADDRESS)


func stop() -> void:
	_listener.stop()


func poll() -> void:
	while _listener.is_connection_available():
		_connections.append({"peer": _listener.take_connection(), "data": PoolByteArray(), "opened": OS.get_ticks_msec(), "continued": false})
	for connection in _connections.duplicate():
		_advance(connection)


func _advance(connection: Dictionary) -> void:
	var peer: StreamPeerTCP = connection["peer"]
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or OS.get_ticks_msec() - connection["opened"] > REQUEST_TIMEOUT_MS:
		_close(connection)
		return
	_receive(connection)
	if connection["data"].size() > MAX_REQUEST_BYTES:
		_connections.erase(connection)
		_respond(peer, 413, {"ok": false, "error": "The request is too large."})
		return
	var request := _parse(connection["data"])
	if request.empty():
		return
	if not request["complete"]:
		_continue_once(connection, request)
		return
	_connections.erase(connection)
	_serve(peer, request)


func _receive(connection: Dictionary) -> void:
	var peer: StreamPeerTCP = connection["peer"]
	var available := peer.get_available_bytes()
	if available <= 0:
		return
	var chunk: Array = peer.get_data(available)
	if chunk[0] == OK:
		var data: PoolByteArray = connection["data"]
		data.append_array(chunk[1])
		connection["data"] = data


# Windows PowerShell 5.1 waits for "100 Continue" before it sends a POST body.
func _continue_once(connection: Dictionary, request: Dictionary) -> void:
	if connection["continued"] or String(request["headers"].get("expect", "")).to_lower() != "100-continue":
		return
	connection["continued"] = true
	var peer: StreamPeerTCP = connection["peer"]
	peer.put_data(CONTINUE_RESPONSE.to_ascii())


func _serve(peer: StreamPeerTCP, request: Dictionary):
	if request["headers"].get(TOKEN_HEADER, "") != _token:
		_respond(peer, 401, {"ok": false, "error": "Missing or wrong X-Harness-Token header."})
		return
	var args = _parse_body(String(request["body"]))
	if not args is Dictionary:
		_respond(peer, 400, {"ok": false, "error": "The request body must be a JSON object."})
		return
	var result = _router.call(_route_method, request["method"], request["path"], args)
	if result is GDScriptFunctionState:
		result = yield(result, "completed")
	_respond(peer, 200, result)


func _close(connection: Dictionary) -> void:
	var peer: StreamPeerTCP = connection["peer"]
	peer.disconnect_from_host()
	_connections.erase(connection)


static func _parse_body(body: String):
	if body.strip_edges().empty():
		return {}
	var parsed := JSON.parse(body)
	return parsed.result if parsed.error == OK else null


# Decoding as ASCII keeps one character per byte, so header offsets are byte offsets.
static func _parse(data: PoolByteArray) -> Dictionary:
	var raw := data.get_string_from_ascii()
	var header_end := raw.find(HEADER_END)
	if header_end < 0:
		return {}
	var lines: PoolStringArray = raw.substr(0, header_end).split("\r\n")
	var request_line: PoolStringArray = lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var separator: int = lines[i].find(":")
		if separator > 0:
			headers[lines[i].substr(0, separator).strip_edges().to_lower()] = lines[i].substr(separator + 1).strip_edges()
	var body_start := header_end + HEADER_END.length()
	var body_length := int(headers.get("content-length", "0"))
	var complete := data.size() - body_start >= body_length
	return {
		"method": request_line[0],
		"path": request_line[1].split("?")[0] if request_line.size() > 1 else "/",
		"headers": headers,
		"complete": complete,
		"body": data.subarray(body_start, body_start + body_length - 1).get_string_from_utf8() if complete and body_length > 0 else "",
	}


static func _respond(peer: StreamPeerTCP, status: int, payload: Dictionary) -> void:
	var body: PoolByteArray = JSON.print(JsonValue.convert_value(payload)).to_utf8()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, STATUS_TEXT.get(status, "OK"), body.size()]
	peer.put_data(head.to_ascii())
	peer.put_data(body)
	peer.disconnect_from_host()
