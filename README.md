# rpc_await
Small layer for Godot 4 RPC to allow awaitable requests with responses enabling you to use `await` when communicating with a peer over Godot's high level multiplayer. This way you can make calls to a peer and receive a return value

## Usage
* Add `rpc_await.gd` as an autoload or instantiate it and place in your tree wherever you like.
* Send requests containing arbitrary data with  

```GDScript
var result = await RpcAwait.send_request(target_net_id, my_data)
```

* Handle requests by connecting to the `request_received` event and fill in the result property with arbitrary data:

```GDScript
func _ready():
    RpcAwait.request_received.connect(_request_received)

func _request_received(req: RpcAwait.RequestData):
    var my_data = req.data
    [...]
    req.result = my_result
```

## Example
Small example of sending a request from the host to a client to retrieve the username. This example uses a dictionary as data to provide a message type and some request specific data fields.

On the host:


```GDScript
const MSG_GET_USER_INFO := 1

func request_player_name(net_id: int) -> void:
    var request_data := {
        "msg": MSG_GET_USER_INFO,
        "field": "name"
    }
    var player_name = RpcAwait.send_request(net_id, request_data)
    print("Player name: %s" % player_name)

```

Client handling the request:

```GDScript
func _ready() -> void:
    RpcAwait.handling_request.connect(_on_rpc_request)


func _on_rpc_request(req_data: RpcAwait.RequestData) -> void:
    if not req_data.data is Dictionary:
        return
    match req_data.data["msg"]:
        MSG_GET_USER_INFO:
            req_data.result = _handle_get_user_info_request(req_data.data["field"])


func _handle_get_user_info_request(field: String) -> String:
    match field:
        "name":
            return "Player 2"
        "game_version":
            return "1.1"
```