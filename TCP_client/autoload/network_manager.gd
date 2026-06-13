## NetworkManager — 网络通信单例 (autoload)
## 职责：封装所有 ENetMultiplayerPeer 连接与 RPC 通信，通过信号通知游戏层。
extends Node

# ============================================================
# 常量
# ============================================================

const PLAYER_SCENE_PATH: String = "res://Scene/player.tscn"
const BULLET_SCENE_PATH: String = "res://Scene/bullet.tscn"

# 场景容器路径（场景根节点下的相对路径）
const PLAYER_CONTAINER_PATH: String = "/root/Main/Example_Area"
const BULLET_CONTAINER_PATH: String = "/root/Main/BulletManager"

# ============================================================
# 信号
# ============================================================

signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal player_spawned(player_id: int)
signal player_removed(player_id: int)
signal bullet_spawned(owner_id: int, bullet_id: int)
signal bullet_removed(owner_id: int, bullet_id: int)

# ============================================================
# 属性
# ============================================================

var _peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var _peer_id: int = 0
var _is_connected: bool = false

# ============================================================
# 公开方法
# ============================================================

## 连接到服务器
func connect_to_server(address: String, port: int) -> Error:
	if _is_connected:
		printerr("NetworkManager: 已连接到服务器，无法重复连接")
		return ERR_ALREADY_IN_USE

	var err: Error = _peer.create_client(address, port)
	if err != OK:
		printerr("NetworkManager: 连接服务器失败，错误代码: ", err)
		return err

	multiplayer.multiplayer_peer = _peer

	_disconnect_signals()
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

	return OK

## 断开与服务器的连接
func disconnect_from_server() -> void:
	_close_connection()
	server_disconnected.emit()

## 请求服务器生成玩家角色
func request_spawn_player(spawn_position: Vector2) -> void:
	# 本地先创建实例（权威端）
	_spawn_player_local(_peer_id, spawn_position)
	# 通知服务器
	rpc_id(1, "_server_req_spawn_player", _peer_id, spawn_position)

## 请求服务器生成子弹
func request_spawn_bullet(spawn_position: Vector2, direction: float) -> void:
	var bullet_id: int = BulletTracker.next_bullet_id()
	BulletTracker.register_local_shot(bullet_id, direction)
	# 本地创建预测子弹
	_spawn_bullet_local(_peer_id, bullet_id, spawn_position, direction)
	# 通知服务器
	rpc_id(1, "_server_req_spawn_bullet", _peer_id, bullet_id, spawn_position, direction)

## 获取当前客户端对等体 ID
func get_peer_id() -> int:
	return _peer_id

## 是否已连接
func is_connected_to_server() -> bool:
	return _is_connected

# ============================================================
# RPC 存根（供 rpc_id 查找配置用）
# ============================================================

@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	pass

@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_bullet(peer_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	pass

@rpc("any_peer", "call_local", "reliable")
func _server_req_remove_bullet(owner_id: int, bullet_id: int, current_position: Vector2) -> void:
	pass

@rpc("any_peer", "call_local", "reliable")
func _server_req_bullet_hit(owner_id: int, bullet_id: int, hit_player_id: int, hit_position: Vector2) -> void:
	pass

# ============================================================
# RPC 接收（来自服务器的调用）
# ============================================================

## 服务器通知：生成远程玩家
@rpc("authority", "call_remote", "reliable")
func server_spawn_player(player_id: int, spawn_position: Vector2) -> void:
	if player_id == _peer_id:
		return
	_spawn_player_remote(player_id, spawn_position)

## 服务器通知：移除玩家
@rpc("authority", "call_remote", "reliable")
func server_remove_player(player_id: int) -> void:
	_remove_player(player_id)

## 服务器通知：生成远程子弹
@rpc("authority", "call_remote", "reliable")
func server_spawn_bullet(owner_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	if owner_id == _peer_id:
		return
	_spawn_bullet_remote(owner_id, bullet_id, spawn_position, direction)

## 服务器通知：移除子弹
@rpc("authority", "call_remote", "reliable")
func server_remove_bullet(owner_id: int, bullet_id: int) -> void:
	_remove_bullet(owner_id, bullet_id)

## 服务器验证射击（预测校正）
@rpc("authority", "call_remote", "reliable")
func server_verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	BulletTracker.verify_shot(bullet_id, actual_position)

## 服务器通知：玩家受击
@rpc("authority", "call_remote", "reliable")
func server_player_hit(hit_player_id: int) -> void:
	print("[NetworkManager] server_player_hit received for player %d" % hit_player_id)
	var container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if not container:
		print("[NetworkManager] ERROR: container not found at %s" % PLAYER_CONTAINER_PATH)
		return
	if not container.has_node(str(hit_player_id)):
		print("[NetworkManager] ERROR: player node %d not found in container" % hit_player_id)
		return
	var player: Node = container.get_node(str(hit_player_id))
	if not player.has_method("play_hit_animation"):
		print("[NetworkManager] ERROR: player %d has no play_hit_animation method" % hit_player_id)
		return
	print("[NetworkManager] calling play_hit_animation on player %d" % hit_player_id)
	player.play_hit_animation()

# ============================================================
# 实例化（本地/远程通用）
# ============================================================

func _spawn_player_local(player_id: int, spawn_position: Vector2) -> void:
	var container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if not container or container.has_node(str(player_id)):
		return

	var player: CharacterBody2D = load(PLAYER_SCENE_PATH).instantiate()
	player.name = str(player_id)
	player.position = spawn_position
	player.set_multiplayer_authority(player_id)
	container.add_child(player)

func _spawn_player_remote(player_id: int, spawn_position: Vector2) -> void:
	var container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if not container or container.has_node(str(player_id)):
		return

	var player: CharacterBody2D = load(PLAYER_SCENE_PATH).instantiate()
	player.name = str(player_id)
	player.position = spawn_position
	player.set_multiplayer_authority(player_id)
	container.add_child(player)
	player_spawned.emit(player_id)

func _spawn_bullet_local(owner_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	var container: Node = get_node_or_null(BULLET_CONTAINER_PATH)
	if not container or container.has_node(str(bullet_id)):
		return

	var bullet: Area2D = load(BULLET_SCENE_PATH).instantiate()
	bullet.name = str(bullet_id)
	bullet.position = spawn_position
	bullet.rotation = direction
	bullet.set_multiplayer_authority(owner_id)
	container.add_child(bullet)

func _spawn_bullet_remote(owner_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	var container: Node = get_node_or_null(BULLET_CONTAINER_PATH)
	if not container or container.has_node(str(bullet_id)):
		return

	var bullet: Area2D = load(BULLET_SCENE_PATH).instantiate()
	bullet.name = str(bullet_id)
	bullet.position = spawn_position
	bullet.rotation = direction
	bullet.set_multiplayer_authority(owner_id)
	container.add_child(bullet)
	bullet_spawned.emit(owner_id, bullet_id)

func _remove_player(player_id: int) -> void:
	var container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if container and container.has_node(str(player_id)):
		container.get_node(str(player_id)).queue_free()
	player_removed.emit(player_id)

func _remove_bullet(owner_id: int, bullet_id: int) -> void:
	var container: Node = get_node_or_null(BULLET_CONTAINER_PATH)
	if container and container.has_node(str(bullet_id)):
		container.get_node(str(bullet_id)).queue_free()
	bullet_removed.emit(owner_id, bullet_id)

# ============================================================
# 内部方法
# ============================================================

func _on_connected_to_server() -> void:
	_peer_id = multiplayer.get_unique_id()
	_is_connected = true
	BulletTracker.clear_all()  # 重置子弹追踪
	connected_to_server.emit()

func _on_connection_failed() -> void:
	_close_connection()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	_close_connection()
	server_disconnected.emit()

func _close_connection() -> void:
	_disconnect_signals()
	# 先清理所有实例（避免 peer 置空后残留节点调用 is_multiplayer_authority 崩溃）
	_clear_containers()
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		_peer.close()
	if multiplayer.multiplayer_peer == _peer:
		multiplayer.multiplayer_peer = null
	_is_connected = false
	_peer_id = 0

func _clear_containers() -> void:
	var player_container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if player_container:
		for child: Node in player_container.get_children():
			child.queue_free()
	var bullet_container: Node = get_node_or_null(BULLET_CONTAINER_PATH)
	if bullet_container:
		for child: Node in bullet_container.get_children():
			child.queue_free()

func _disconnect_signals() -> void:
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
