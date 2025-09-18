# rpc_await
Small layer for Godot 4 RPC to allow making rpc-calls or sending messages to peers that you can `await` on for a return value.

Because sometimes you just want to request something from a client and await the result to continue instead of spreading your code over multiple functions that call each other over different machines.

*Requires Godot 4.5*. If you are using Godot 4.x earlier than that you must use rpc_await 1.0.

## Documentation
* This readme for a quick overview
* The example scene for a working example
* The code documentation for details

## Installation
* Add the `addons/rpc-await` folder to your project.
* Add `rpc_await.gd` as an autoload or instantiate an `RpcAwaiter` node in your tree wherever you like.

## Usage calling functions
* Use `send_rpc` or `send_rpc_timeout` to call a function on the same location in the scene tree of the peer:


```GDScript
var result = await RpcAwait.send_rpc(target_net_id, _do_some_work)
```

* The peer needs to have this function and it needs the correct rpc annotation to be accessible ("any_peer" or "authority"):

```GDScript
@rpc("any_peer")
func _do_some_work() -> String:
	await get_tree().create_timer(2).timeout # You can use await on this side, too.
	return "My Answer!"
```

## Usage for messages
* Use `send_msg` or `send_msg_timeout` to send arbitrary data to a peer and get a response. This message can also be a `Dictionary` with msg data or just an `int` to specify a message type.

```GDScript
var result = await RpcAwait.send_msg(target_net_id, my_data)
```

* Handle these requests on the peer by connecting to the `request_received` signal and fill in the result property with your result:

```GDScript
func _ready():
	RpcAwait.message_received.connect(_message_received)

func _message_received(req: RpcAwait.RequestData):
	var my_data = req.data
	[...]
	req.result = my_result
```

## Notes
* The signal handlers of `message_received` may not use `await` themselves.
* `RpcAwait.default_timeout_secs` [default 5.0] can be changed to suit your needs. Values <= 0 disable the timeout.
* Give a custom timeout value for specific calls using `send_rpc_timeout` and `send_msg_timeout` variants.
