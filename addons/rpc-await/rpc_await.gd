extends Node
## Implements a communication scheme over RPC that allows a peer to await a
## function call or await a sent message until a response is received that brings a return value.


## Emitted when a message has been received that now needs processing and a result.
##
## The Message contains the message's data and a field to place your result into.
signal message_received(req: Message)


## How long requests may wait for a response until the await is relased.
##
## A timeout of <=0 means no timeout.
@export var default_timeout_secs := 5.0

## Timeout checker interval in seconds.
@export var timer_interval := 0.5


## Maps req_id -> RequestAwaiter to keep track of the open requests waiting for the response.
var _open_requests := {}

## ID counter for requests.
var _next_id := 0

## Timer node to regularly check
var _timeout_timer := Timer.new()


func _init() -> void:
    _timeout_timer.autostart = true
    _timeout_timer.timeout.connect(_on_timeout_timer_tick)
    add_child(_timeout_timer)


func _ready() -> void:
    _timeout_timer.wait_time = timer_interval


## Send a message with a custom timeout (in seconds).
func send_msg_timeout(timeout: float, net_id: int, data: Variant) -> Variant:
    var req_obj := RequestAwaiter.new()

    if timeout > 0:
        req_obj.timeout = Time.get_ticks_msec() + timeout
    var req_id = _next_id
    _next_id += 1

    _open_requests[req_id] = req_obj
    _handle_msg_request.rpc_id(net_id, req_id, data)

    return await req_obj.done


## Send a message to the given peer and await the response.
func send_msg(net_id: int, data: Variant) -> Variant:
    return await send_msg_timeout(default_timeout_secs, net_id, data)


## Call function via RPC and return the result.
func send_rpc(net_id: int, callable: Callable) -> Variant:
    return await send_rpc_timeout(default_timeout_secs, net_id, callable)


## Call function via RPC and return the result. With custom timeout (in seconds).
func send_rpc_timeout(timeout: float, net_id: int, callable: Callable) -> Variant:
    # Store get_object() result in var until #73998 is fixed.
    var source_obj = callable.get_object()
    assert(source_obj is Node)
    assert(source_obj.is_inside_tree())
    
    var req_obj := RequestAwaiter.new()

    if timeout > 0:
        req_obj.timeout = Time.get_ticks_msec() + (timeout * 1000)
    var req_id = _next_id
    _next_id += 1
    _open_requests[req_id] = req_obj
    
    _handle_callable_request.rpc_id(net_id, req_id,
                                    callable.get_method(),
                                    source_obj.get_path(),
                                    callable.get_bound_arguments())
    return await req_obj.done


@rpc("any_peer")
func _handle_callable_request(req_id: int, method: String, path: String, args: Array) -> void:
    var sender_id := get_tree().get_multiplayer().get_remote_sender_id()

    # Reconstruct the callable
    var target := get_tree().root.get_node(path)
    var callable := Callable(target, method)
    if not args.is_empty():
        callable = callable.bindv(args)

    # Call it with await in case it's an async function.
    var result = await callable.call()
    _handle_response.rpc_id(sender_id, req_id, result)


@rpc("any_peer")
func _handle_msg_request(req_id: int, data: Variant) -> void:
    var sender_id := get_tree().get_multiplayer().get_remote_sender_id()
    var request := Message.new()
    request.data = data

    message_received.emit(request)

    _handle_response.rpc_id(sender_id, req_id, request.result)


@rpc("any_peer")
func _handle_response(req_id: int, data: Variant) -> void:
    if not req_id in _open_requests:
        push_warning("Received response for unknown id %s (timed out?)" % req_id)
        return
    var req_obj = _open_requests[req_id]
    _open_requests.erase(req_id)
    req_obj.done.emit(data)


## Iterate over all waiting RequestAwaiters and check if they timed out.
##
## Timed out awaiters emit their signal with null.
func _on_timeout_timer_tick() -> void:
    var now := Time.get_ticks_msec()
    for id in _open_requests.keys():
        var awaiter = _open_requests[id]

        if awaiter.timeout > 0 and awaiter.timeout <= now:
            _open_requests.erase(id)
            awaiter.done.emit(null)


## Utility object that represents an open await waiting for a resposne via rpc.
class RequestAwaiter:
    extends RefCounted


    signal done(data: Variant)


    ## Ticks msecs at which this request will time out. Or 0 to disable timeout.
    var timeout := 0.0


## Handed to signal handlers of the message_received signal to allow listeners to
## process the request data and place their result.
class Message:
    extends RefCounted

    ## The data that was sent with this message.
    var data: Variant
    
    ## The result that will be returned. Set by handlers of the message_received signal.
    var result: Variant
