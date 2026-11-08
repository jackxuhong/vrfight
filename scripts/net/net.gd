class_name Net
extends Node
## LAN connection for two players. The host runs an ENet server on `port` and announces itself
## once a second by UDP broadcast on `discovery_port`. A joining player connects to the first host
## it hears, or straight to an IP. The game's RPCs live on Main; this node only connects.

signal connected
signal disconnected

const HELLO := "VRFIGHT1"

var port := 47230
var discovery_port := 47231
var _udp := PacketPeerUDP.new()
var _active := false
var _announcing := false
var _listening := false
var _announce_t := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_lost)
	multiplayer.server_disconnected.connect(_on_lost)
	multiplayer.connection_failed.connect(_on_lost)


func host() -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", discovery_port)
	_active = true
	_announcing = true
	return OK


## `ip` empty: wait for a host's broadcast on the LAN.
func join(ip: String) -> Error:
	stop()
	_active = true
	if ip != "":
		return _connect(ip)
	var err := _udp.bind(discovery_port)
	_listening = err == OK
	return err


func is_live() -> bool:
	return _active and not multiplayer.get_peers().is_empty()


func stop() -> void:
	_active = false  # first, so closing doesn't report a lost connection
	_announcing = false
	_listening = false
	_udp.close()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _process(dt: float) -> void:
	if _announcing:
		_announce_t -= dt
		if _announce_t <= 0.0:
			_announce_t = 1.0
			_udp.put_packet(HELLO.to_utf8_buffer())
	elif _listening and _udp.get_available_packet_count() > 0:
		var hello := _udp.get_packet().get_string_from_utf8()
		var ip := _udp.get_packet_ip()
		if hello == HELLO:
			_listening = false
			_udp.close()
			_connect(ip)


func _connect(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func _on_peer_connected(_id: int) -> void:
	_announcing = false
	connected.emit()


func _on_lost(_id := 0) -> void:
	if _active:
		_active = false
		disconnected.emit()
