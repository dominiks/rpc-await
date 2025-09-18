extends Control


@onready var _txt_address: LineEdit = find_child("txt_address")
@onready var _txt_port: LineEdit = find_child("txt_port")
@onready var _btn_join: Button = find_child("btn_join")
@onready var _btn_host: Button = find_child("btn_host")
@onready var _btn_send_message: Button = find_child("btn_send_message")
@onready var _btn_send_rpc: Button = find_child("btn_send_rpc")
@onready var _txt_output: TextEdit = find_child("txt_output")


## The id of the other end.
var _peer_id: int = -1


func _ready() -> void:
    RpcAwait.message_received.connect(_on_rpc_await_message_received)

    get_tree().get_multiplayer().peer_connected.connect(_on_peer_connected)
    get_tree().get_multiplayer().peer_disconnected.connect(_on_peer_disconnected)

    get_tree().get_multiplayer().connection_failed.connect(_on_connection_failed)
    get_tree().get_multiplayer().connected_to_server.connect(_on_connection_success)
    get_tree().get_multiplayer().server_disconnected.connect(_on_server_disconnected)

    _set_test_buttons_disabled(true)


######### rpc_await-related functions #########

## rpc_await node sends out a signal when a msg is received so handlers can
## set a result. The message contents is placed in req.data but in this case
## we just expect an int to multiply with 2.
func _on_rpc_await_message_received(req: RpcAwait.Message) -> void:
    _append_line("Received message, setting result.")
    req.result = req.data * 2


## This function gets called on the other peer via rpc. It is not possible to
## check if a function called this way has a @rpc marker so it does not
## need one.
@rpc("any_peer")
func _rpc_get_number_doubled(number: int) -> int:
    _append_line("Number doubling function called, we'll wait for 2 seconds.")
    await get_tree().create_timer(2).timeout
    _append_line("Timer run through, returning result.")
    return number * 2


######### Button handlers #########

## Test button was pressed. Send the message to the peer and wait for the result.
func _on_btn_send_message_pressed():
    _append_line("Sending message '5' to peer %s" % _peer_id)
    var result = await RpcAwait.send_msg(_peer_id, 5)
    _append_line("Received result: '%s'" % result)


## Test the rpc function call. The function will be called with a parameter
## and we await the result.
func _on_btn_send_rpc_pressed():
    var number = randi_range(1,48)
    _append_line("Calling function peer %s to ask what %s * 2 is" % [_peer_id, number])
    var result = await RpcAwait.send_rpc(_peer_id, _rpc_get_number_doubled.bind(number))
    _append_line("Turns out %s*2 is %s!" % [number, result])


## When join is pressed, disable the mp buttons and start a connection attempt.
func _on_btn_join_pressed():
    _set_mp_buttons_disabled(true)
    _append_line("Trying to connect to %s:%s" % [_txt_address.text, _txt_port.text])

    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_client(_txt_address.text, int(_txt_port.text))
    if err != OK:
        _append_line("Could not attempt to join: %s" % err)
        _set_mp_buttons_disabled(false)
    get_tree().get_multiplayer().multiplayer_peer = peer


## When host is pressed, disable mp buttons and create the server. It'll wait for connections.
func _on_btn_host_pressed():
    _set_mp_buttons_disabled(true)
    _append_line("Creating server on port %s" % _txt_port.text)

    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(int(_txt_port.text), 1)
    if err != OK:
        _append_line("Could not create server: %s" % err)
        _set_mp_buttons_disabled(false)
    get_tree().get_multiplayer().multiplayer_peer = peer


######### Godot MP event handlers #########

## When a peer is connected, store the id and enable test buttons.
func _on_peer_connected(net_id: int) -> void:
    _append_line("Peer %s connected." % net_id)
    _peer_id = net_id
    _set_test_buttons_disabled(false)


## When the peer disconnects, reset the _peer_is and disable test buttons.
func _on_peer_disconnected(net_id: int) -> void:
    _append_line("Peer %s disconnected." % net_id)
    _peer_id = -1
    _set_test_buttons_disabled(true)


func _on_connection_failed() -> void:
    _append_line("Connecting to server failed.")
    _set_mp_buttons_disabled(false)
    get_tree().get_multiplayer().multiplayer_peer = null


func _on_server_disconnected() -> void:
    _append_line("Server closed connection.")
    _peer_id = -1
    _set_test_buttons_disabled(true)
    _set_mp_buttons_disabled(false)
    get_tree().get_multiplayer().multiplayer_peer = null


func _on_connection_success() -> void:
    _append_line("Connected to server.")
    _peer_id = 1
    _set_mp_buttons_disabled(true)


######### Helper functions #########
func _append_line(msg: String) -> void:
    _txt_output.text += "\n%s\t%s" % [Time.get_time_string_from_system(), msg]
    _txt_output.get_v_scroll_bar().value = _txt_output.get_v_scroll_bar().max_value


func _set_mp_buttons_disabled(state: bool) -> void:
    _btn_host.disabled = state
    _btn_join.disabled = state


func _set_test_buttons_disabled(state: bool) -> void:
    _btn_send_message.disabled = state
    _btn_send_rpc.disabled = state
