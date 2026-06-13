## ============================================================================
## NetworkManager — 服务器网络管理单例 (autoload, /root/NetworkManager)
## ============================================================================
##
## 架构定位:
##   服务器唯一的网络门面。所有 RPC 接收、实例生命周期管理、广播集中于此。
##   上层 UI (server_main.gd) 仅监听信号更新界面，不直接操作网络。
##
## 权威模型 (Server-Authoritative):
##   服务器持有所有游戏对象的创建权与销毁权。
##   所有客户端请求 (生成/移除/命中) 必须经过服务器验证后广播。
##   服务器不执行移动/射击逻辑 — 这些由权威客户端驱动，
##   服务器仅负责: 实例化模板 + 设置 authority + 广播给所有客户端。
##
## RPC 通信方向:
##
##   客户端 → 服务器 (通过 rpc_id(1, ...) 调用):
##     _server_req_spawn_player   — 接收: 为请求客户端创建玩家
##     _server_req_spawn_bullet   — 接收: 为请求客户端创建子弹
##     _server_req_remove_bullet  — 接收: 移除子弹 (飞行超距)
##     _server_req_bullet_hit     — 接收: 结算命中 + 广播受击
##
##   服务器 → 所有客户端 (通过 .rpc() 广播):
##     server_spawn_player   — 广播: 创建远程玩家 (跳过拥有者)
##     server_spawn_bullet   — 广播: 创建远程子弹 (跳过拥有者)
##     server_remove_player  — 广播: 移除玩家实例
##     server_remove_bullet  — 广播: 移除子弹实例
##     server_player_hit     — 广播: 触发受击动画
##     server_verify_shot    — 广播: 验证子弹位置
##
## 实例容器:
##   _player_container (Example_Area) — 所有玩家 CharacterBody2D 的父节点
##   _bullet_container (BulletManager) — 所有子弹 Area2D 的父节点
##   由 server_main.gd 的 _ready() 通过 set_containers() 注入。
##
## 关键设计决策:
##   - 服务器模板 (player.tscn / bullet.tscn) 不含脚本和精灵。
##     服务器仅创建"骨架"实例，脚本/精灵由客户端模板提供。
##     但碰撞体 + MultiplayerSynchronizer 必须在服务器模板中配置，
##     以确保服务器端物理空间与客户端一致。
##   - _sync_existing_state 解决晚期加入问题:
##     新客户端连接后，服务器遍历所有已有实例，逐一 rpc_id 给新客户端。
##   - _cleanup_player 在客户端断开时清理其所有实例并广播。
## ============================================================================

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

## 玩家实例容器节点（由场景在 _ready 中注入）
var _player_container: Node = null
## 子弹实例容器节点（由场景在 _ready 中注入）
var _bullet_container: Node = null

# 场景模板路径 (服务器端模板，无脚本/精灵，仅碰撞体 + 同步器)
const PLAYER_SCENE_PATH: String = "res://Scene/player.tscn"
const BULLET_SCENE_PATH: String = "res://Scene/bullet.tscn"

# ============================================================
# 公开方法
# ============================================================

## 启动服务器
## 创建 ENet 服务器并绑定地址/端口，注册 peer 连接/断开信号。
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
## 主动断开所有客户端 → 断开信号 → 关闭 ENet peer → 置空 multiplayer_peer。
func stop_server() -> void:
	if not _is_running:
		return

	# 主动断开所有客户端 (触发 _on_peer_disconnected → _cleanup_player)
	for peer_id: int in multiplayer.get_peers():
		_peer.disconnect_peer(peer_id)

	_disconnect_signals()
	_peer.close()

	if multiplayer.multiplayer_peer == _peer:
		multiplayer.multiplayer_peer = null

	_is_running = false
	server_stopped.emit()

## 获取已连接的 peer ID 列表（副本）
func get_connected_peers() -> Array[int]:
	return _connected_peers.duplicate()

## 是否正在运行
func is_server_running() -> bool:
	return _is_running

## 设置实例容器
## 由 server_main.gd 的 _ready() 调用，将场景中的 Example_Area 和 BulletManager
## 注入到 NetworkManager，供后续 spawn_*_for_client 使用。
func set_containers(player_container: Node, bullet_container: Node) -> void:
	_player_container = player_container
	_bullet_container = bullet_container

# ============================================================
# RPC 接收（来自客户端的请求）
#
# @rpc("any_peer", "call_local", "reliable") 的含义:
#   - any_peer: 任何 peer 可以调用此 RPC
#   - call_local: 允许本地调用 (此处用于客户端 rpc_id 后服务器本地执行)
#   - reliable: 保证送达
# 所有方法首行检查 is_server() 防止客户端误调。
# ============================================================

## 客户端请求生成玩家
## 客户端 A 调用 rpc_id(1, "_server_req_spawn_player", A_id, pos)
## → 服务器为 A 创建玩家实例并广播给所有其他客户端。
@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	if not multiplayer.is_server():
		return

	spawn_player_for_client(peer_id, spawn_position)

## 客户端请求生成子弹
## 客户端 A 调用 rpc_id(1, "_server_req_spawn_bullet", A_id, bullet_id, pos, dir)
## → 服务器为 A 创建子弹实例并广播。
@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_bullet(peer_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	if not multiplayer.is_server():
		return

	spawn_bullet_for_client(peer_id, bullet_id, spawn_position, direction)

## 客户端请求移除子弹（子弹飞完/超出最大距离）
@rpc("any_peer", "call_local", "reliable")
func _server_req_remove_bullet(owner_id: int, bullet_id: int, current_position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	server_log.emit("子弹 %d 已销毁（客户端 %d），最终位置: %s" % [bullet_id, owner_id, str(current_position)])
	remove_bullet(owner_id, bullet_id)

## 客户端通知：子弹命中玩家
## 权威客户端检测到碰撞后上报。
## 服务器处理: ①移除子弹 ②广播受击事件给所有客户端触发动画。
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
## 流程:
##   1. 实例化 player.tscn 模板
##   2. 节点名 = peer_id 字符串 (用于 enter_tree 时 set_multiplayer_authority)
##   3. 设置初始 position 和 multiplayer_authority
##   4. 加入 _player_container
##   5. .rpc() 广播给所有客户端 (含初始位置)
func spawn_player_for_client(peer_id: int, spawn_position: Vector2) -> void:
	if _player_container == null:
		printerr("NetworkManager: _player_container 未设置")
		return

	# 避免重复创建 (客户端可能重复发送请求)
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
## 参数 bullet_id 由客户端 BulletTracker 预分配，服务器沿用。
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

## 移除玩家实例 (服务器本地 + 广播)
func remove_player(peer_id: int) -> void:
	if _player_container and _player_container.has_node(str(peer_id)):
		_player_container.get_node(str(peer_id)).queue_free()
	server_remove_player.rpc(peer_id)

## 移除子弹实例 (服务器本地 + 广播)
## 广播时同时传递 owner_id 和 bullet_id，客户端据此查找对应实例。
func remove_bullet(owner_id: int, bullet_id: int) -> void:
	if _bullet_container and _bullet_container.has_node(str(bullet_id)):
		_bullet_container.get_node(str(bullet_id)).queue_free()
	server_remove_bullet.rpc(owner_id, bullet_id)

## 验证射击（预测校正用）
## 客户端预测子弹位置 vs 服务器权威位置，回传位置以供校正。
## 当前简化实现: 仅回传位置确认，不做强制校正。
func verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	server_verify_shot.rpc(bullet_id, actual_position)

## 清理指定玩家的所有实例（服务器本地 + 广播通知所有客户端）
## 当客户端断开时调用。
## 清理顺序: 先玩家 → 后子弹 (子弹依赖玩家存在)
func _cleanup_player(peer_id: int) -> void:
	# 移除玩家实例并广播
	if _player_container and _player_container.has_node(str(peer_id)):
		_player_container.get_node(str(peer_id)).queue_free()
	server_remove_player.rpc(peer_id)

	# 移除该玩家的所有子弹并广播
	# 遍历 _bullet_container 查找 authority 匹配 peer_id 的所有子弹
	if _bullet_container:
		for child: Node in _bullet_container.get_children():
			if child is Area2D and child.get_multiplayer_authority() == peer_id:
				var bullet_id: int = child.name.to_int()
				child.queue_free()
				server_remove_bullet.rpc(peer_id, bullet_id)

	server_log.emit("客户端 %d 已断开，已清理其实例及子弹" % peer_id)

## 清理所有实例（服务器关闭时调用）
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
#
# @rpc("authority", "call_remote", "reliable") 的含义:
#   - authority: 仅服务器 (ID=1) 有权调用此 RPC
#   - call_remote: 仅远程端执行此方法体，服务器端为 pass
#   - reliable: 保证送达
# 实际逻辑在客户端 NetworkManager 的同名方法中执行。
# ============================================================

## [RPC存根] 广播: 创建远程玩家实例
@rpc("authority", "call_remote", "reliable")
func server_spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	pass  # 客户端同名 RPC 负责实例化

## [RPC存根] 广播: 移除玩家实例
@rpc("authority", "call_remote", "reliable")
func server_remove_player(peer_id: int) -> void:
	pass

## [RPC存根] 广播: 创建远程子弹实例
@rpc("authority", "call_remote", "reliable")
func server_spawn_bullet(owner_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	pass

## [RPC存根] 广播: 移除子弹实例
@rpc("authority", "call_remote", "reliable")
func server_remove_bullet(owner_id: int, bullet_id: int) -> void:
	pass

## [RPC存根] 广播: 验证子弹位置 (预测校正)
@rpc("authority", "call_remote", "reliable")
func server_verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	pass

## [RPC存根] 广播: 触发受击动画
@rpc("authority", "call_remote", "reliable")
func server_player_hit(hit_player_id: int) -> void:
	pass

# ============================================================
# 内部信号回调
# ============================================================

## 新客户端连接回调
## 记录 peer ID，延迟一帧同步场上已有实例给新客户端。
## call_deferred 确保客户端 NetworkManager 完全就绪后再发送 RPC。
func _on_peer_connected(peer_id: int) -> void:
	if not _connected_peers.has(peer_id):
		_connected_peers.append(peer_id)
	client_connected.emit(peer_id)
	# 延迟同步现有实例给新客户端（等待客户端 NetworkManager 就绪）
	_sync_existing_state.bind(peer_id).call_deferred()

## 客户端断开回调
## 清理该客户端的所有实例 + 广播移除。
func _on_peer_disconnected(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	_cleanup_player(peer_id)
	client_disconnected.emit(peer_id)

## 将场上所有现有实例同步给新加入的客户端
## 异步方法: 等待一帧确保客户端场景就绪，然后逐一 rpc_id 发送。
## 跳过新客户端自己的实例 (peer_id == new_peer_id)。
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

## 断开 multiplayer 信号连接，防止重复注册或关闭后回调
func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
