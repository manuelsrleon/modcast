extends Node

# Signals
signal offer_received(peer_id: int, offer: String)
signal answer_received(peer_id: int, answer: String)
signal ice_candidate_received(peer_id: int, mid: String, index: int, sdp: String)
signal session_created(session_id: String)
signal session_joined(session_id: String)
signal peer_list_updated(peers: Array)
signal connection_error(error_message: String)

# WebSocket connection
var ws: WebSocketPeer = null
var server_url: String = ""
var is_connected: bool = false
var session_id: String = ""
var player_name: String = ""

func _ready() -> void:
	set_process(false)

# Connect to signaling server
func connect_to_server(url: String) -> Error:
	server_url = url
	ws = WebSocketPeer.new()

	var err = ws.connect_to_url(url)
	if err != OK:
		push_error("Failed to connect to signaling server: ", err)
		connection_error.emit("Failed to connect to signaling server")
		return err

	set_process(true)
	print("Connecting to signaling server: ", url)
	return OK

# Disconnect from signaling server
func disconnect_from_server() -> void:
	if ws:
		ws.close()
		ws = null

	is_connected = false
	set_process(false)
	print("Disconnected from signaling server")

# Create a new session (host)
func create_session(session_name: String, p_player_name: String) -> void:
	player_name = p_player_name

	var message = {
		"type": "create_session",
		"session_name": session_name,
		"player_name": player_name
	}

	_send_message(message)

# Join an existing session (client)
func join_session(p_session_id: String, p_player_name: String) -> void:
	session_id = p_session_id
	player_name = p_player_name

	var message = {
		"type": "join_session",
		"session_id": session_id,
		"player_name": player_name
	}

	_send_message(message)

# Leave current session
func leave_session() -> void:
	var message = {
		"type": "leave_session",
		"session_id": session_id,
		"player_name": player_name
	}

	_send_message(message)
	session_id = ""

# Send offer to peer
func send_offer(target_peer_id: int, offer: String) -> void:
	var message = {
		"type": "offer",
		"target_peer_id": target_peer_id,
		"from_peer_id": multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0,
		"sdp": offer
	}

	_send_message(message)

# Send answer to peer
func send_answer(target_peer_id: int, answer: String) -> void:
	var message = {
		"type": "answer",
		"target_peer_id": target_peer_id,
		"from_peer_id": multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0,
		"sdp": answer
	}

	_send_message(message)

# Send ICE candidate to peer
func send_ice_candidate(target_peer_id: int, mid: String, index: int, sdp: String) -> void:
	var message = {
		"type": "ice_candidate",
		"target_peer_id": target_peer_id,
		"from_peer_id": multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0,
		"mid": mid,
		"index": index,
		"sdp": sdp
	}

	_send_message(message)

# Process WebSocket messages
func _process(delta: float) -> void:
	if not ws:
		return

	ws.poll()

	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			print("Connected to signaling server")

		# Process incoming messages
		while ws.get_available_packet_count() > 0:
			var packet = ws.get_packet()
			var message_text = packet.get_string_from_utf8()

			var json = JSON.new()
			var parse_result = json.parse(message_text)

			if parse_result == OK:
				var message = json.data
				_handle_message(message)
			else:
				push_error("Failed to parse signaling message: ", message_text)

	elif state == WebSocketPeer.STATE_CLOSING:
		pass

	elif state == WebSocketPeer.STATE_CLOSED:
		var code = ws.get_close_code()
		var reason = ws.get_close_reason()
		print("Signaling server connection closed: ", code, " - ", reason)
		is_connected = false
		set_process(false)

# Send message to signaling server
func _send_message(message: Dictionary) -> void:
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_error("Cannot send message: not connected to signaling server")
		return

	var json_string = JSON.stringify(message)
	var err = ws.send_text(json_string)

	if err != OK:
		push_error("Failed to send signaling message: ", err)

# Handle incoming message from signaling server
func _handle_message(message: Dictionary) -> void:
	var type = message.get("type", "")

	match type:
		"session_created":
			session_id = message.get("session_id", "")
			print("Session created: ", session_id)
			session_created.emit(session_id)

		"session_joined":
			session_id = message.get("session_id", "")
			print("Joined session: ", session_id)
			session_joined.emit(session_id)

		"peer_list":
			var peers = message.get("peers", [])
			print("Peer list updated: ", peers)
			peer_list_updated.emit(peers)

		"offer":
			var from_peer_id = message.get("from_peer_id", 0)
			var sdp = message.get("sdp", "")
			print("Received offer from peer: ", from_peer_id)
			offer_received.emit(from_peer_id, sdp)

		"answer":
			var from_peer_id = message.get("from_peer_id", 0)
			var sdp = message.get("sdp", "")
			print("Received answer from peer: ", from_peer_id)
			answer_received.emit(from_peer_id, sdp)

		"ice_candidate":
			var from_peer_id = message.get("from_peer_id", 0)
			var mid = message.get("mid", "")
			var index = message.get("index", 0)
			var sdp = message.get("sdp", "")
			print("Received ICE candidate from peer: ", from_peer_id)
			ice_candidate_received.emit(from_peer_id, mid, index, sdp)

		"error":
			var error_message = message.get("message", "Unknown error")
			push_error("Signaling server error: ", error_message)
			connection_error.emit(error_message)

		_:
			push_warning("Unknown message type from signaling server: ", type)
