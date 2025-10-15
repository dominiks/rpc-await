class_name RpcAwaiter
extends Node
## Implements a communication scheme over RPC that allows a peer to await a
## function call or await a sent message until a response is received that brings a return value.


## How long requests may wait for a response until the await is relased.
##
## A timeout of <=0 means no timeout.
@export var default_timeout_secs := 5.0

## Timeout checker interval in seconds.
@export var timer_interval := 0.5


## Maps req_id -> RequestAwaiter to keep track of the open requests waiting for the response.
var _open_requests : Dictionary[int, RequestAwaiter] = {}

## ID counter for requests.
var _next_id := 0

## Timer node to regularly check
var _timeout_timer := Timer.new()

## Set of all registered listener callables.
##
## Dictionary used as a Set to prevent duplicates.
var _message_listeners: Dictionary[Callable, bool] = {}


func _init() -> void:
	_timeout_timer.autostart = true
	_timeout_timer.timeout.connect(_on_timeout_timer_tick)
	add_child(_timeout_timer)


func _ready() -> void:
	_timeout_timer.wait_time = timer_interval


## Register a callable to listen for message events.
##
## The callable must have one parameter with the type RpcAwaiter.Message.
## Registering the same callable multiple times has no effect.
func add_message_listener(listener: Callable) -> void:
	_message_listeners[listener] = true


## Unregister a callable from receiving message events.
func remove_message_listener(listener: Callable) -> void:
	_message_listeners.erase(listener)


## Send a message with a custom timeout (in seconds).
func send_msg_timeout(timeout: float, net_id: int, data: Variant, default_return: Variant = null) -> Variant:
	var req_obj := RequestAwaiter.new()
	req_obj.target_net_id = net_id
	req_obj.default_return = default_return

	if timeout > 0:
		req_obj.timeout = Time.get_ticks_msec() + (timeout * 1000)
	var req_id := _next_id
	_next_id += 1

	_open_requests[req_id] = req_obj
	_handle_msg_request.rpc_id(net_id, req_id, data)

	# The operation might have already completed when executing locally so
	# there is no use in waiting for the signal.
	if req_obj.is_done:
		return req_obj.result
	else:
		return await req_obj.done


## Send a message to the given peer and await the response.
func send_msg(net_id: int, data: Variant, default_return: Variant = null) -> Variant:
	return await send_msg_timeout(default_timeout_secs, net_id, data, default_return)


## Call function via RPC and return the result.
func send_rpc(net_id: int, callable: Callable, default_return: Variant = null) -> Variant:
	return await send_rpc_timeout(default_timeout_secs, net_id, callable, default_return)


## Call function via RPC and return the result. With custom timeout (in seconds).
func send_rpc_timeout(timeout: float, net_id: int, callable: Callable, default_return: Variant = null) -> Variant:
	var source_obj = callable.get_object()
	assert(source_obj is Node)
	assert(source_obj.is_inside_tree())

	var req_obj := RequestAwaiter.new()
	req_obj.target_net_id = net_id
	req_obj.default_return = default_return

	if timeout > 0:
		req_obj.timeout = Time.get_ticks_msec() + (timeout * 1000)
	var req_id = _next_id
	_next_id += 1
	_open_requests[req_id] = req_obj

	_handle_callable_request.rpc_id(net_id, req_id,
									callable.get_method(),
									source_obj.get_path(),
									callable.get_bound_arguments())

	# The operation might have already completed when executing locally so
	# there is no use in waiting for the signal.
	if req_obj.is_done:
		return req_obj.result
	else:
		return await req_obj.done


@rpc("any_peer", "call_local", "reliable")
func _handle_callable_request(req_id: int, method: String, path: String, args: Array) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	# Reconstruct the callable
	var target := get_tree().root.get_node(path)

	# Check for target validity
	if target == null:
		var err_msg := "rpc target not found at %s" % path
		push_error(err_msg)
		_handle_fail_response.rpc_id(sender_id, req_id, err_msg)
		return

	if target == self:
		var err_msg := "blocked recursive rpc call to rpc_await node"
		push_error(err_msg)
		_handle_fail_response.rpc_id(sender_id, req_id, err_msg)
		return

	# Check for script validity
	var script = target.get_script()
	if script == null:
		var err_msg := "no script found at %s" % path
		push_error(err_msg)
		_handle_fail_response.rpc_id(sender_id, req_id, err_msg)
		return

	# Retrieve and check the rpc mode of the target method
	var rpc_config = script.get_rpc_config()
	var callable_rpc_mode := _get_rpc_mode(rpc_config, method)
	if callable_rpc_mode == MultiplayerAPI.RPC_MODE_DISABLED:
		var err_msg := "%s not marked as rpc-method" % method
		push_error(err_msg)
		_handle_fail_response.rpc_id(sender_id, req_id, err_msg)
		return

	if callable_rpc_mode == MultiplayerAPI.RPC_MODE_AUTHORITY and target.get_multiplayer_authority() != sender_id:
		var err_msg := "%s called by %s but only available for authority (%s)" % [method, sender_id, target.get_multiplayer_authority()]
		push_error(err_msg)
		_handle_fail_response.rpc_id(sender_id, req_id, err_msg)
		return

	# Check for rpc sync mode
	if not _is_rpc_call_local(rpc_config, method) and multiplayer.get_remote_sender_id() == multiplayer.get_unique_id():
		var err_msg := "%s called via rpc on local but is not set as call_local" % method
		push_error(err_msg)
		_handle_fail_response.rpc_id(sender_id, req_id, err_msg)
		return

	# Reconstruct the callable
	var callable := Callable(target, method)
	if not args.is_empty():
		callable = callable.bindv(args)

	# Call it with await in case it's an async function.
	var result = await callable.call()
	_handle_response.rpc_id(sender_id, req_id, result)


@rpc("any_peer", "call_local", "reliable")
func _handle_msg_request(req_id: int, data: Variant) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	var request := Message.new()
	request.data = data

	for callable in _message_listeners.keys():
		await callable.call(request)

	_handle_response.rpc_id(sender_id, req_id, request.result)


@rpc("any_peer", "call_local", "reliable")
func _handle_response(req_id: int, data: Variant) -> void:
	if not req_id in _open_requests:
		push_warning("Received response for unknown id %s (timed out?)" % req_id)
		return
	var req_obj := _open_requests[req_id]
	if req_obj.target_net_id != multiplayer.get_remote_sender_id():
		push_warning("Dismissed response from unexpected net_id")
		return

	_open_requests.erase(req_id)
	req_obj.done.emit(data)


@rpc("any_peer", "call_local", "reliable")
func _handle_fail_response(req_id: int, error_msg: String) -> void:
	if not req_id in _open_requests:
		push_warning("Received fail response for unknown id %s (timed out?)" % req_id)
		return
	var req_obj := _open_requests[req_id]
	if req_obj.target_net_id != multiplayer.get_remote_sender_id():
		push_warning("Dismissed fail response from unexpected net_id")
		return

	_open_requests.erase(req_id)
	push_error(error_msg)
	req_obj.done.emit(req_obj.default_return)


## Iterate over all waiting RequestAwaiters and check if they timed out.
##
## Timed out awaiters emit their signal with null.
func _on_timeout_timer_tick() -> void:
	var now := Time.get_ticks_msec()
	for id in _open_requests.keys():
		var awaiter := _open_requests[id]

		if awaiter.timeout > 0 and awaiter.timeout <= now:
			_open_requests.erase(id)
			awaiter.done.emit(awaiter.default_return)


func _get_rpc_mode(rpc_config: Dictionary, method_name: String) -> MultiplayerAPI.RPCMode:
	if method_name not in rpc_config:
		return MultiplayerAPI.RPC_MODE_DISABLED
	if "rpc_mode" not in rpc_config[method_name]:
		return MultiplayerAPI.RPC_MODE_DISABLED
	return rpc_config[method_name]["rpc_mode"]


func _is_rpc_call_local(rpc_config: Dictionary, method_name: String) -> bool:
	if method_name not in rpc_config:
		return false
	if "call_local" not in rpc_config[method_name]:
		return false
	return rpc_config[method_name]["call_local"]


## Utility object that represents an open await waiting for a response via rpc.
class RequestAwaiter:
	extends RefCounted


	signal done(data: Variant)


	## Flag to check whether this request has completed
	var is_done := false

	## Result of the operation
	var result: Variant

	## Ticks msecs at which this request will time out. Or 0 to disable timeout.
	var timeout := 0

	## The net_id that we expect to receive a response from for this request
	var target_net_id := 0

	## The default value that is to be returned in case of timeout or error
	var default_return: Variant = null


	func _init() -> void:
		done.connect(_on_done)


	## When done, set result and done-flag on yourself - in case the operation
	## is complete before anyone was able to listen to the signal.
	func _on_done(result: Variant) -> void:
		self.is_done = true
		self.result = result


## Handed to signal handlers of the message_received signal to allow listeners to
## process the request data and place their result.
class Message:
	extends RefCounted

	## The data that was sent with this message.
	var data: Variant

	## The result that will be returned. Set by handlers of the message_received signal.
	var result: Variant
