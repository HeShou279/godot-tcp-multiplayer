## ============================================================================
## NetworkManager — 客户端网络通信单例 (autoload, /root/NetworkManager)
## ============================================================================
##
## 架构定位:
##   客户端唯一的网络门面。所有 RPC 收发、实例化、连接生命周期管理集中于此。
##   上层 UI (client_main.gd) 仅监听信号更新界面，不直接操作网络。
##
## 权威模型 (Server-Authoritative):
##   服务器 (peer ID=1) 持有所有游戏对象的创建权与销毁权。
##   客户端通过 RPC "请求" 服务器生成/移除实例，不能自行创建远程实例。
##   自身角色由客户端本地预创建 (预测)，服务器确认后广播给其他客户端。
##
## RPC 通信方向:
##
##   客户端 → 服务器 (rpc_id(1, ...)):
##     _server_req_spawn_player   — 请求创建玩家实例
##     _server_req_spawn_bullet   — 请求创建子弹实例
##     _server_req_remove_bullet  — 通知子弹已销毁 (飞行超距)
##     _server_req_bullet_hit     — 通知子弹命中玩家
##
##   服务器 → 所有客户端 (.rpc()):
##     server_spawn_player   — 广播: 创建远程玩家
##     server_spawn_bullet   — 广播: 创建远程子弹
##     server_remove_player  — 广播: 移除玩家
##     server_remove_bullet  — 广播: 移除子弹
##     server_player_hit     — 广播: 触发受击动画
##     server_verify_shot    — 广播: 服务器验证子弹位置 (预测校正)
##
## 关键设计决策:
##   - PLAYER/BULLET_CONTAINER_PATH 硬编码为 /root/Main/Example_Area 和
##     /root/Main/BulletManager，与场景结构耦合。变更场景结构需同步修改。
##   - 本地实例和远程实例使用不同的 _spawn_*_local/remote 方法，区分信号发送。
##   - @rpc 存根 (pass body) 仅用于 rpc_id 的配置查找，不执行实际逻辑。
## ============================================================================

extends Node

# ============================================================
# 常量
# ============================================================

## 玩家场景模板路径 (客户端完整版，含脚本/精灵/碰撞体/同步器)
const PLAYER_SCENE_PATH: String = "res://Scene/player.tscn"
## 子弹场景模板路径 (客户端完整版)
const BULLET_SCENE_PATH: String = "res://Scene/bullet.tscn"

## 玩家实例容器绝对路径 (场景根节点 Main → Example_Area)
const PLAYER_CONTAINER_PATH: String = "/root/Main/Example_Area"
## 子弹实例容器绝对路径 (场景根节点 Main → BulletManager)
const BULLET_CONTAINER_PATH: String = "/root/Main/BulletManager"

# ============================================================
# 信号
# ============================================================

## 成功连接到服务器
signal connected_to_server()
## 连接服务器失败 (超时/拒绝)
signal connection_failed()
## 与服务器断开连接 (主动登出/服务器关闭/网络中断)
signal server_disconnected()
## 远程玩家实例已创建 (本地玩家不触发此信号)
signal player_spawned(player_id: int)
## 玩家实例已移除
signal player_removed(player_id: int)
## 远程子弹实例已创建
signal bullet_spawned(owner_id: int, bullet_id: int)
## 子弹实例已移除
signal bullet_removed(owner_id: int, bullet_id: int)

# ============================================================
# 属性
# ============================================================

## ENet 网络对等体 (基于 UDP，在 Godot 中以 multiplayer_peer 形式使用)
var _peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
## 本客户端 peer ID (由服务器分配，连接成功后确定)
var _peer_id: int = 0
## 是否已连接到服务器
var _is_connected: bool = false

# ============================================================
# 公开方法
# ============================================================

## 连接到服务器
## 创建 ENet 客户端并设置 multiplayer.multiplayer_peer，
## 连接成功后触发 connected_to_server 信号。
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
## 触发完整的清理流程: 断开信号 → 清理容器 → 关闭 peer → 通知 UI
func disconnect_from_server() -> void:
	_close_connection()
	server_disconnected.emit()

## 请求服务器生成玩家角色
## 流程: ①本地预创建权威实例 ②RPC 通知服务器 ③服务器广播给其他客户端
func request_spawn_player(spawn_position: Vector2) -> void:
	# 本地先创建实例（权威端，由本客户端驱动移动/射击）
	_spawn_player_local(_peer_id, spawn_position)
	# 通知服务器创建并广播
	rpc_id(1, "_server_req_spawn_player", _peer_id, spawn_position)

## 请求服务器生成子弹
## 流程: ①BulletTracker 分配 ID ②本地预创建预测子弹 ③RPC 通知服务器
func request_spawn_bullet(spawn_position: Vector2, direction: float) -> void:
	var bullet_id: int = BulletTracker.next_bullet_id()
	BulletTracker.register_local_shot(bullet_id, direction)
	# 本地创建预测子弹（权威端驱动飞行 + 碰撞检测）
	_spawn_bullet_local(_peer_id, bullet_id, spawn_position, direction)
	# 通知服务器验证并广播
	rpc_id(1, "_server_req_spawn_bullet", _peer_id, bullet_id, spawn_position, direction)

## 获取当前客户端对等体 ID
func get_peer_id() -> int:
	return _peer_id

## 是否已连接
func is_connected_to_server() -> bool:
	return _is_connected

# ============================================================
# RPC 存根（供 rpc_id 查找配置用）
#
# 这些方法体为 pass，仅用于 rpc_id(target, method_name, ...) 的配置查找。
# rpc_id 需要在调用节点上找到带 @rpc 注解的同名方法来确定传输模式
# (reliable/unreliable, call_local/call_remote 等)。
# 实际逻辑在服务器端的同名方法中执行。
# ============================================================

## [RPC存根] 请求生成玩家
@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	pass

## [RPC存根] 请求生成子弹
@rpc("any_peer", "call_local", "reliable")
func _server_req_spawn_bullet(peer_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	pass

## [RPC存根] 请求移除子弹 (飞行超距)
@rpc("any_peer", "call_local", "reliable")
func _server_req_remove_bullet(owner_id: int, bullet_id: int, current_position: Vector2) -> void:
	pass

## [RPC存根] 通知子弹命中
@rpc("any_peer", "call_local", "reliable")
func _server_req_bullet_hit(owner_id: int, bullet_id: int, hit_player_id: int, hit_position: Vector2) -> void:
	pass

# ============================================================
# RPC 接收（来自服务器的调用）
#
# 以下方法由服务器通过 .rpc() 广播调用，在客户端本地执行。
# @rpc("authority", "call_remote", "reliable") 的含义:
#   - authority: 仅服务器 (ID=1) 有权调用此 RPC
#   - call_remote: 仅在远程端执行 (服务器端同名方法为 pass)
#   - reliable: 保证送达，不丢包
# ============================================================

## 服务器通知：创建远程玩家实例
## 服务器广播给所有客户端；跳过本地玩家 (player_id == _peer_id)
@rpc("authority", "call_remote", "reliable")
func server_spawn_player(player_id: int, spawn_position: Vector2) -> void:
	if player_id == _peer_id:
		return  # 本地玩家已在 request_spawn_player 中预创建
	_spawn_player_remote(player_id, spawn_position)

## 服务器通知：移除玩家实例 (客户端登出/服务器关闭)
@rpc("authority", "call_remote", "reliable")
func server_remove_player(player_id: int) -> void:
	_remove_player(player_id)

## 服务器通知：创建远程子弹实例
## 跳过本地玩家发射的子弹 (owner_id == _peer_id，已在本地预创建)
@rpc("authority", "call_remote", "reliable")
func server_spawn_bullet(owner_id: int, bullet_id: int, spawn_position: Vector2, direction: float) -> void:
	if owner_id == _peer_id:
		return  # 本地子弹已在 request_spawn_bullet 中预创建
	_spawn_bullet_remote(owner_id, bullet_id, spawn_position, direction)

## 服务器通知：移除子弹实例 (子弹超距/命中/发射者登出)
@rpc("authority", "call_remote", "reliable")
func server_remove_bullet(owner_id: int, bullet_id: int) -> void:
	_remove_bullet(owner_id, bullet_id)

## 服务器验证射击位置 (预测校正)
## 客户端预测子弹位置可能与服务器权威位置有偏差，此 RPC 校正。
@rpc("authority", "call_remote", "reliable")
func server_verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	BulletTracker.verify_shot(bullet_id, actual_position)

## 服务器通知：玩家受击
## 命中事件由子弹权威客户端检测并上报服务器，服务器广播给所有客户端
## 以触发受击动画。受击动画在每个客户端本地播放。
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
#
# 本地 vs 远程的差异:
#   - 本地实例 (_local): 由本客户端发起请求时创建，不发 player_spawned 信号
#   - 远程实例 (_remote): 由服务器广播触发创建，发射 player_spawned 信号通知 UI
# ============================================================

## 在本地创建玩家实例（权威端）
## 节点名为 peer_id 的字符串形式，multiplayer_authority 设为本客户端。
## 权威端负责: 输入处理、移动、射击、子弹碰撞检测。
func _spawn_player_local(player_id: int, spawn_position: Vector2) -> void:
	var container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if not container or container.has_node(str(player_id)):
		return

	var player: CharacterBody2D = load(PLAYER_SCENE_PATH).instantiate()
	player.name = str(player_id)
	player.position = spawn_position
	player.set_multiplayer_authority(player_id)
	container.add_child(player)

## 在本地创建远程玩家实例（非权威端）
## 仅用于展示: MultiplayerSynchronizer 自动同步 position 到所有客户端。
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

## 在本地创建子弹实例（权威端，预测生成）
## 子弹的 movement + collision 逻辑由权威客户端驱动。
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

## 在本地创建远程子弹实例（非权威端，仅展示飞行轨迹）
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

## 从场景中移除玩家实例
func _remove_player(player_id: int) -> void:
	var container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if container and container.has_node(str(player_id)):
		container.get_node(str(player_id)).queue_free()
	player_removed.emit(player_id)

## 从场景中移除子弹实例
func _remove_bullet(owner_id: int, bullet_id: int) -> void:
	var container: Node = get_node_or_null(BULLET_CONTAINER_PATH)
	if container and container.has_node(str(bullet_id)):
		container.get_node(str(bullet_id)).queue_free()
	bullet_removed.emit(owner_id, bullet_id)

# ============================================================
# 内部方法
# ============================================================

## 连接成功回调
## 记录 peer ID，重置 BulletTracker 状态，通知 UI。
func _on_connected_to_server() -> void:
	_peer_id = multiplayer.get_unique_id()
	_is_connected = true
	BulletTracker.clear_all()  # 重置子弹追踪（防止上次会话残留数据）
	connected_to_server.emit()

## 连接失败回调
func _on_connection_failed() -> void:
	_close_connection()
	connection_failed.emit()

## 服务器断开回调
func _on_server_disconnected() -> void:
	_close_connection()
	server_disconnected.emit()

## 关闭连接并清理所有状态
## 清理顺序至关重要:
##   1. 断开 multiplayer 信号 (防止回调重入)
##   2. 清理容器内所有实例 (在 peer 置空前，避免 is_multiplayer_authority 崩溃)
##   3. 关闭 ENet peer
##   4. 置空 multiplayer.multiplayer_peer
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

## 清理两个容器的所有子节点
## remove_child 强制脱离树（使路径立即失效），再 queue_free 延迟释放。
## 这解决了重连时 MultiplayerSynchronizer 路径残留导致 scene_cache 崩溃的问题。
func _clear_containers() -> void:
	# 先 remove_child 强制脱离场景树（立即失效路径引用），再延迟释放
	var player_container: Node = get_node_or_null(PLAYER_CONTAINER_PATH)
	if player_container:
		for child: Node in player_container.get_children():
			player_container.remove_child(child)
			child.queue_free()
	var bullet_container: Node = get_node_or_null(BULLET_CONTAINER_PATH)
	if bullet_container:
		for child: Node in bullet_container.get_children():
			bullet_container.remove_child(child)
			child.queue_free()

## 断开 multiplayer 信号连接，防止重复注册
func _disconnect_signals() -> void:
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
