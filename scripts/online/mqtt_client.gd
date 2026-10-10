## The smallest MQTT 3.1.1 client that can hold a room together: connect over
## a WebSocket, subscribe to one topic, publish at QoS 0 and keep the link
## alive with pings. Public brokers speak this over WebSockets, which is the
## one transport a web export has, so two browsers can meet with no server of
## our own. The owner calls poll() every frame; nothing here touches the tree.
class_name MqttClient
extends RefCounted

signal connected
signal message(topic: String, payload: PackedByteArray)
signal closed(reason: String)

enum State { IDLE, CONNECTING, CONNECTED, CLOSING, CLOSED }

## Seconds between pings; the broker drops us after 1.5x this without one.
const KEEPALIVE := 30
## Seconds to get from connect_to() to CONNACK before giving up.
const CONNECT_TIMEOUT := 12.0

const TYPE_CONNECT := 0x10
const TYPE_CONNACK := 0x20
const TYPE_PUBLISH := 0x30
const TYPE_SUBSCRIBE := 0x82
const TYPE_SUBACK := 0x90
const TYPE_PINGREQ := 0xC0
const TYPE_PINGRESP := 0xD0
const TYPE_DISCONNECT := 0xE0

var state := State.IDLE

var _peer := WebSocketPeer.new()
var _buffer := PackedByteArray()
var _packet_id := 0
var _elapsed := 0.0
var _since_ping := 0.0
var _client_id := ""
var _connect_sent := false
var _closing := false


## Opens the socket; `connected` fires once the broker has accepted us.
func connect_to(url: String, client_id: String) -> void:
	_client_id = client_id
	_peer.supported_protocols = PackedStringArray(["mqtt"])
	var err := _peer.connect_to_url(url)
	if err != OK:
		state = State.CLOSED
		closed.emit("cannot open %s (%s)" % [url, error_string(err)])
		return
	state = State.CONNECTING


func subscribe(topic: String) -> void:
	_packet_id = (_packet_id % 65535) + 1
	var body := PackedByteArray([_packet_id >> 8, _packet_id & 0xFF])
	body.append_array(_string(topic))
	body.append(0)
	_send(TYPE_SUBSCRIBE, body)


func publish(topic: String, payload: PackedByteArray) -> void:
	var body := _string(topic)
	body.append_array(payload)
	_send(TYPE_PUBLISH, body)


## A polite goodbye. Keep calling poll() for a moment so the last packets and
## the close frame go out; `closed` does not fire for a close we asked for.
func close() -> void:
	if state == State.CLOSED or state == State.CLOSING:
		return
	_closing = true
	if state == State.CONNECTED:
		_send(TYPE_DISCONNECT, PackedByteArray())
	_peer.close()
	state = State.CLOSING if state != State.IDLE else State.CLOSED


func poll(delta: float) -> void:
	if state == State.IDLE or state == State.CLOSED:
		return
	_elapsed += delta
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if _elapsed > CONNECT_TIMEOUT:
				_fail("the relay did not answer")
		WebSocketPeer.STATE_OPEN:
			if state == State.CLOSING:
				return
			if not _connect_sent:
				_connect_sent = true
				_send_connect()
			while _peer.get_available_packet_count() > 0:
				_buffer.append_array(_peer.get_packet())
			_drain()
			if state == State.CONNECTING and _elapsed > CONNECT_TIMEOUT:
				_fail("the relay did not accept the connection")
			elif state == State.CONNECTED:
				_since_ping += delta
				if _since_ping >= KEEPALIVE:
					_since_ping = 0.0
					_send(TYPE_PINGREQ, PackedByteArray())
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if not _closing:
				var reason := _peer.get_close_reason()
				_fail("the relay closed the connection" + ("" if reason.is_empty() else " (%s)" % reason))
			state = State.CLOSED


# --- packets ---------------------------------------------------------------

func _send_connect() -> void:
	var body := _string("MQTT")
	body.append_array(PackedByteArray([4, 0x02, KEEPALIVE >> 8, KEEPALIVE & 0xFF]))
	body.append_array(_string(_client_id))
	_send(TYPE_CONNECT, body)


func _send(type: int, body: PackedByteArray) -> void:
	var packet := PackedByteArray([type])
	var remaining := body.size()
	while true:
		var byte := remaining % 128
		remaining /= 128
		if remaining > 0:
			byte |= 0x80
		packet.append(byte)
		if remaining == 0:
			break
	packet.append_array(body)
	_peer.put_packet(packet)


## Pulls every complete packet out of the receive buffer. A WebSocket frame
## may carry several MQTT packets or, in principle, part of one.
func _drain() -> void:
	while _buffer.size() >= 2:
		var remaining := 0
		var multiplier := 1
		var index := 1
		var complete := false
		while index < _buffer.size() and index < 5:
			var byte := _buffer[index]
			remaining += (byte & 0x7F) * multiplier
			multiplier *= 128
			index += 1
			if byte & 0x80 == 0:
				complete = true
				break
		if not complete:
			return
		var total := index + remaining
		if _buffer.size() < total:
			return
		var type := _buffer[0]
		var body := _buffer.slice(index, total)
		_buffer = _buffer.slice(total)
		_handle(type, body)


func _handle(type: int, body: PackedByteArray) -> void:
	match type & 0xF0:
		TYPE_CONNACK:
			var rc := body[1] if body.size() >= 2 else 255
			if rc == 0:
				state = State.CONNECTED
				connected.emit()
			else:
				_fail("the relay refused the connection (code %d)" % rc)
		TYPE_PUBLISH:
			if body.size() < 2:
				return
			var length := (body[0] << 8) | body[1]
			var offset := 2 + length
			if body.size() < offset:
				return
			var topic := body.slice(2, offset).get_string_from_utf8()
			var qos := (type >> 1) & 0x03
			if qos > 0:
				# We subscribe at QoS 0; a broker that still sends higher
				# carries a packet id we have no use for, and we never ack it.
				offset += 2
			message.emit(topic, body.slice(offset))
		_:
			# SUBACK, PINGRESP and anything else: nothing to do.
			pass


func _fail(reason: String) -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	_closing = true
	_peer.close()
	closed.emit(reason)


static func _string(s: String) -> PackedByteArray:
	var bytes := s.to_utf8_buffer()
	var out := PackedByteArray([bytes.size() >> 8, bytes.size() & 0xFF])
	out.append_array(bytes)
	return out
