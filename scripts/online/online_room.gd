## One room for one match between two players. Both peers subscribe to the
## room's topic on the relay (a public MQTT broker over WebSockets, so a web
## export can reach it with no server of ours) and talk through it: the guest
## knocks, the host answers with the seed and the deck, the guest says it is
## ready, and from then on each side publishes its own shot actions and the
## other applies them. The rules never see the network: MatchState gets the
## same seed and the same actions on both sides, which is all it needs.
## No reconnection, no matchmaking, one match per room.
class_name OnlineRoom
extends Node

## A line for the lobby screen.
signal status_changed(text: String)
## Both peers agree: {seed, deck_ids, points_to_win, seat}. `seat` is the
## local player's index in the shared MatchState: 0 for the host, 1 for the guest.
signal started(config: Dictionary)
## The other peer's shot, as a MatchState action.
signal action_received(action: Dictionary)
## The room is over before or during the match; the text says why.
signal ended(reason: String)
## The other peer said goodbye. Its playback may simply have finished first:
## the Director ends the room only when the match here cannot finish alone.
signal peer_left

const DEFAULT_RELAY := "wss://broker.emqx.io:8084/mqtt"
const TOPIC_PREFIX := "ponpong/v1/"
## No 0/O or 1/I, so a code read out loud survives.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4
const HELLO_EVERY := 2.0
const JOIN_TIMEOUT := 45.0
const POINTS_TO_WIN := 7
const PROTOCOL := 1
## Seconds a room keeps polling after leave(), so its goodbye and close
## frame get out before the node frees itself.
const LINGER := 1.0

var code := ""
var is_host := false
var relay_url := DEFAULT_RELAY
## True from `started` until the room ends.
var running := false
## True once the other peer said goodbye.
var peer_gone := false

var _client := MqttClient.new()
var _me := ""
var _nonce := ""
var _peer_nonce := ""
var _seed := 0
var _deck_ids: Array = []
var _since_hello := HELLO_EVERY
var _waited := 0.0
var _subscribed := false
var _started := false
var _out_seq := 0
var _in_seq := 0
var _left := false
var _lingered := 0.0


func _ready() -> void:
	# The pause menu must not stall the other player's shots.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_client.connected.connect(_on_connected)
	_client.message.connect(_on_message)
	_client.closed.connect(_on_closed)


## Opens a room. With an empty `p_code` a fresh one is drawn.
func host(p_code := "") -> void:
	is_host = true
	_me = "h"
	code = p_code if not p_code.is_empty() else new_code()
	_seed = randi() & 0x7FFFFFFF
	_deck_ids = CardLibrary.starter_ids()
	_open()


func join(p_code: String) -> void:
	is_host = false
	_me = "g"
	code = p_code.strip_edges().to_upper()
	_open()


func _open() -> void:
	_nonce = "%08x" % (randi() & 0xFFFFFFFF)
	status_changed.emit("Connecting to the relay…")
	_client.connect_to(relay_url, "ponpong-%s-%s-%s" % [code, _me, _nonce])


## Publishes a local shot for the other peer.
func send_action(action: Dictionary) -> void:
	_out_seq += 1
	_publish({"t": "act", "n": _out_seq, "a": action})


## Says goodbye, closes the socket and frees the node a moment later. Safe to
## call more than once.
func leave() -> void:
	if _left:
		return
	_left = true
	running = false
	if _client.state == MqttClient.State.CONNECTED:
		_publish({"t": "bye"})
	_client.close()


func _process(delta: float) -> void:
	_client.poll(delta)
	if _left:
		_lingered += delta
		if _lingered >= LINGER or _client.state == MqttClient.State.CLOSED:
			queue_free()
		return
	if _started or not _subscribed:
		return
	_waited += delta
	if is_host:
		return
	_since_hello += delta
	if _since_hello >= HELLO_EVERY:
		_since_hello = 0.0
		_publish({"t": "hello"})
	if _waited > JOIN_TIMEOUT:
		_finish("Nobody answered in room %s. Check the code and try again." % code)


func _on_connected() -> void:
	_client.subscribe(_topic())
	_subscribed = true
	if is_host:
		status_changed.emit("Room %s is open. Waiting for your friend…" % code)
	else:
		status_changed.emit("Knocking on room %s…" % code)


func _on_message(_topic: String, payload: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	if String(msg.get("from", "")) == _me or int(msg.get("v", 0)) != PROTOCOL:
		return
	match String(msg.get("t", "")):
		"hello":
			if not is_host:
				return
			var who := String(msg.get("nonce", ""))
			if _peer_nonce.is_empty():
				_peer_nonce = who
			if who != _peer_nonce:
				# A third player: the room is taken.
				return
			_publish({"t": "start", "to": who, "seed": _seed, "deck": _deck_ids, "ptw": POINTS_TO_WIN})
		"start":
			if is_host or _started or String(msg.get("to", "")) != _nonce:
				return
			_seed = int(msg.get("seed", 0))
			_deck_ids = (msg.get("deck", []) as Array).duplicate()
			_publish({"t": "ready"})
			_begin()
		"ready":
			if is_host and not _started and String(msg.get("nonce", "")) == _peer_nonce:
				_begin()
		"act":
			if not running:
				return
			var n := int(msg.get("n", 0))
			if n <= _in_seq:
				return
			if n != _in_seq + 1:
				_finish("The relay dropped a move; the match cannot go on.")
				return
			_in_seq = n
			var action: Variant = msg.get("a", {})
			if typeof(action) == TYPE_DICTIONARY:
				action_received.emit(action)
		"bye":
			if not peer_gone:
				peer_gone = true
				peer_left.emit()


func _on_closed(reason: String) -> void:
	if _left:
		return
	_finish("Lost the relay: %s." % reason)


func _begin() -> void:
	_started = true
	running = true
	status_changed.emit("Found each other. Starting…")
	started.emit({
		"seed": _seed,
		"deck_ids": _deck_ids.duplicate(),
		"points_to_win": POINTS_TO_WIN,
		"seat": 0 if is_host else 1,
	})


## Ends the room from outside, with the reason the lobby will show.
func end(reason: String) -> void:
	_finish(reason)


func _finish(reason: String) -> void:
	if _left:
		return
	leave()
	ended.emit(reason)


func _publish(msg: Dictionary) -> void:
	msg["v"] = PROTOCOL
	msg["from"] = _me
	msg["nonce"] = _nonce
	_client.publish(_topic(), JSON.stringify(msg).to_utf8_buffer())


func _topic() -> String:
	return TOPIC_PREFIX + code


static func new_code() -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return out


static func is_valid_code(text: String) -> bool:
	var t := text.strip_edges().to_upper()
	if t.length() != CODE_LENGTH:
		return false
	for ch in t:
		if not CODE_ALPHABET.contains(ch):
			return false
	return true


## The relay to use: `?relay=wss://…` on the page in a browser, `--relay=…`
## after `--` on the command line elsewhere, the public broker otherwise.
static func relay_from_environment() -> String:
	var from_page := _page_param("relay")
	if not from_page.is_empty():
		return from_page
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--relay="):
			return String(arg).substr(8)
	return DEFAULT_RELAY


## The room a page was opened with (`?room=ABCD`, a share link), or "".
static func room_from_environment() -> String:
	var code := _page_param("room").strip_edges().to_upper()
	return code if is_valid_code(code) else ""


## A link that joins `p_code` straight from the browser; "" off the web. A
## relay override on this page rides along so both players use the same one.
static func share_link(p_code: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var base: Variant = JavaScriptBridge.eval("location.origin + location.pathname", true)
	if typeof(base) != TYPE_STRING:
		return ""
	var link := "%s?room=%s" % [String(base), p_code]
	var relay := _page_param("relay")
	if not relay.is_empty():
		link += "&relay=" + relay.uri_encode()
	return link


static func _page_param(name: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % name, true)
	return String(v) if typeof(v) == TYPE_STRING else ""
