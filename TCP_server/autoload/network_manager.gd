## NetworkManager — 服务器网络管理单例 (autoload)
## 职责：创建/关闭服务器，接收客户端 RPC 请求，管理玩家/子弹实例生命周期，广播给所有客户端。
extends Node

# ============================================================
# 信号
# ============================================================

signal server_started(address: String, port: int)
signal server_stopped()
signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal server_log(message: String)

# ============================================================
# 属性
# ============================================================

var _peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var _is_running: bool = false
var _connected_peers: Array[int] = []

# 实例容器节点（由场景注入）
var _player_container: Node = null
var _bullet_container: Node = null

# 场景模板路径
const PLAYER_SCENE_PATH: String = "res://Scene/player.tscn"
const BULLET_SCENE_PATH: String = "res://Scene/bullet.tscn"

# ============================================================
# 公开方法
# ============================================================

## 启动服务器
func start_server(address: String, port: int, max_clients: int = 800) -> Error:
	if _is_running:
		printerr("NetworkManager: 服务器已在运行")
		return ERR_ALREADY_IN_USE

	_peer.set_bind_ip(address)
	var err: Error = _peer.create_server(port, max_clients)
	if err != OK:
		printerr("NetworkManager: 服务器创建失败，错误: ", err)
		return err

	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_is_running = true
	server_started.emit(address, port)
	return OK

## 关闭服务器
func stop_server() -> void:
	if not _is_running:
		return

	# 主动断开所有客户端
	for peer_id: int in multiplayer.get_peers():
		_peer.disconnect_peer(peer_id)

	_disconnect_signals()
	_peer.close()

	if multiplayer.multiplayer_peer == _peer:
		multiplayer.multiplayer_peer = null

	_is_running = false
	server_stopped.emit()

## 获取已连接的 peer ID 列表
func get_connected_peers() -> Array[int]:
	return _connected_peers.duplicate()

## 是否正在运行
func is_server_running() -> bool:
	return _is_running

## 设置实例容器（由场景在 _ready 中调用）
func set_containers(player_container: Node, bullet_container: Node) -> void:
	_player_container = player_container
	_bullet_container = bullet_container

# ============================================================
# RPC 接收（来自客户端的请求）
# ============================================================

## 客户端请求生成玩家
@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	if not multiplayer.is_server():
		return

	spawn_player_for_client(peer_id, spawn_position)

## 客户端请求生成子弹
@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_bullet(peer_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	if not multiplayer.is_server():
		return

	spawn_bullet_for_client(peer_id, bullet_id, spawn_position, direction)

## 客户端请求移除子弹（子弹飞完/命中后）
@rpc("any_peer", "call_local", "reliable")
func _server_req_remove_bullet(owner_id: int, bullet_id: int, current_position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	server_log.emit("子弹 %d 已销毁（客户端 %d），最终位置: %s" % [bullet_id, owner_id, str(current_position)])
	remove_bullet(owner_id, bullet_id)

## 客户端通知：子弹命中玩家
@rpc("any_peer", "call_local", "reliable")
func _server_req_bullet_hit(owner_id: int, bullet_id: int, hit_player_id: int, hit_position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	server_log.emit("子弹 %d（来自客户端 %d）命中客户端 %d，位置: %s" % [bullet_id, owner_id, hit_player_id, str(hit_position)])
	remove_bullet(owner_id, bullet_id)
	# 广播受击事件，触发受击动画
	server_player_hit.rpc(hit_player_id)

# ============================================================
# 实例管理
# ============================================================

## 为指定客户端创建玩家实例并广播
func spawn_player_for_client(peer_id: int, spawn_position: Vector2) -> void:
	if _player_container == null:
		printerr("NetworkManager: _player_container 未设置")
		return

	# 避免重复创建
	if _player_container.has_node(str(peer_id)):
		return

	var player: CharacterBody2D = load(PLAYER_SCENE_PATH).instantiate()
	player.name = str(peer_id)
	player.position = spawn_position
	player.set_multiplayer_authority(peer_id)
	_player_container.add_child(player)

	server_log.emit("客户端 %d 创建角色，位置: %s" % [peer_id, str(spawn_position)])

	# 广播给所有客户端（含初始位置）
	server_spawn_player.rpc(peer_id, spawn_position)

## 为指定客户端创建子弹实例并广播
func spawn_bullet_for_client(peer_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	if _bullet_container == null:
		printerr("NetworkManager: _bullet_container 未设置")
		return

	if _bullet_container.has_node(str(bullet_id)):
		return

	var bullet: Area2D = load(BULLET_SCENE_PATH).instantiate()
	bullet.name = str(bullet_id)
	bullet.position = spawn_position
	bullet.rotation = direction
	bullet.set_multiplayer_authority(peer_id)
	_bullet_container.add_child(bullet)

	server_log.emit("客户端 %d 生成子弹 %d，位置: %s，方向: %.2f" % [peer_id, bullet_id, str(spawn_position), direction])

	# 广播给所有客户端（含初始位置和方向）
	server_spawn_bullet.rpc(peer_id, bullet_id, spawn_position, direction)

## 移除玩家实例
func remove_player(peer_id: int) -> void:
	if _player_container and _player_container.has_node(str(peer_id)):
		_player_container.get_node(str(peer_id)).queue_free()
	server_remove_player.rpc(peer_id)

## 移除子弹实例
func remove_bullet(owner_id: int, bullet_id: int) -> void:
	if _bullet_container and _bullet_container.has_node(str(bullet_id)):
		_bullet_container.get_node(str(bullet_id)).queue_free()
	server_remove_bullet.rpc(owner_id, bullet_id)

## 验证射击（预测校正用，暂简化：仅回传位置确认）
func verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	server_verify_shot.rpc(bullet_id, actual_position)

## 清理指定玩家的所有实例（服务器本地 + 广播通知所有客户端）
func _cleanup_player(peer_id: int) -> void:
	# 移除玩家实例
	if _player_container and _player_container.has_node(str(peer_id)):
		_player_container.get_node(str(peer_id)).queue_free()
	server_remove_player.rpc(peer_id)

	# 移除该玩家的所有子弹
	if _bullet_container:
		for child: Node in _bullet_container.get_children():
			if child is Area2D and child.get_multiplayer_authority() == peer_id:
				var bullet_id: int = child.name.to_int()
				child.queue_free()
				server_remove_bullet.rpc(peer_id, bullet_id)

	server_log.emit("客户端 %d 已断开，已清理其实例及子弹" % peer_id)

## 清理所有实例
func _cleanup_all() -> void:
	if _player_container:
		for child: Node in _player_container.get_children():
			var peer_id: int = child.name.to_int()
			child.queue_free()
			server_remove_player.rpc(peer_id)
	if _bullet_container:
		for child: Node in _bullet_container.get_children():
			var owner_id: int = child.get_multiplayer_authority()
			var bullet_id: int = child.name.to_int()
			child.queue_free()
			server_remove_bullet.rpc(owner_id, bullet_id)
	_connected_peers.clear()

# ============================================================
# 广播 RPC（服务器 → 所有客户端）
# ============================================================

@rpc("authority", "call_remote", "reliable")
func server_spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	pass  # 客户端同名 RPC 负责实例化

@rpc("authority", "call_remote", "reliable")
func server_remove_player(peer_id: int) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func server_spawn_bullet(owner_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func server_remove_bullet(owner_id: int, bullet_id: int) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func server_verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func server_player_hit(hit_player_id: int) -> void:
	pass

# ============================================================
# 内部信号回调
# ============================================================

func _on_peer_connected(peer_id: int) -> void:
	if not _connected_peers.has(peer_id):
		_connected_peers.append(peer_id)
	client_connected.emit(peer_id)
	# 延迟同步现有实例给新客户端（等待客户端 NetworkManager 就绪）
	_sync_existing_state.bind(peer_id).call_deferred()

func _on_peer_disconnected(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	_cleanup_player(peer_id)
	client_disconnected.emit(peer_id)

## 将场上所有现有实例同步给新加入的客户端
func _sync_existing_state(new_peer_id: int) -> void:
	# 等待一帧确保客户端场景就绪
	await get_tree().process_frame

	# 同步所有现有玩家
	if _player_container:
		for child: Node in _player_container.get_children():
			var peer_id: int = child.name.to_int()
			if peer_id == new_peer_id:
				continue
			server_spawn_player.rpc_id(new_peer_id, peer_id, child.position)
			server_log.emit("向新客户端 %d 同步已有玩家 %d" % [new_peer_id, peer_id])

	# 同步所有现有子弹
	if _bullet_container:
		for child: Node in _bullet_container.get_children():
			var bullet_id: int = child.name.to_int()
			var owner_id: int = child.get_multiplayer_authority()
			server_spawn_bullet.rpc_id(new_peer_id, owner_id, bullet_id, child.position, child.rotation)
			server_log.emit("向新客户端 %d 同步已有子弹 %d" % [new_peer_id, bullet_id])

func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
