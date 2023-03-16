extends Node
## Implements a communication scheme over RPC that allows a peer to await a request
## until a response is received that brings a return value.


## Emitted when a request has been received that now needs processing and a result.
##
## The RequestData contains the request's data and a field to place your result into.
signal request_received(req: RequestData)


## How long requests may wait for a response until the await is relased.
##
## A timeout of <=0 means no timeout.
@export var default_timeout := 5.0

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



## Send a request with a custom timeout.
func send_request_timeout(timeout: float, net_id: int, data: Variant) -> Variant:
    var req_obj := RequestAwaiter.new()

    if timeout > 0:
        req_obj.timeout = Time.get_ticks_msec() + timeout
    var req_id = _next_id
    _next_id += 1

    _open_requests[req_id] = req_obj
    _handle_request.rpc_id(net_id, req_id, data)

    return await req_obj.done


## Send a request of arbritrary data to the given peer and await the response.
func send_request(net_id: int, data: Variant) -> Variant:
    return await send_request_timeout(default_timeout, net_id, data)


@rpc("any_peer")
func _handle_request(req_id: int, data: Variant) -> void:
    var sender_id := get_tree().get_multiplayer().get_remote_sender_id()
    var request := RequestData.new()
    request.data = data

    request_received.emit(request)

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


## Handed to signal handlers of rpc_await::request_received to allow listeners to
## process the request data and place their result.
class RequestData:
    extends RefCounted


    var data: Variant
    var result: Variant
