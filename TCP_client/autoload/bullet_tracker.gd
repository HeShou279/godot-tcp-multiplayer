## ============================================================================
## BulletTracker — 子弹生命周期管理单例 (autoload, /root/BulletTracker)
## ============================================================================
##
## 架构定位:
##   负责子弹的 ID 分配、数据字典维护、预测弹道校正。
##   不参与 RPC 通信 (通信由 NetworkManager 统一处理)。
##   不创建/销毁子弹节点 (实例化由 NetworkManager 的 _spawn_* 方法完成)。
##
## 双层子弹管理:
##
##   本地预测层 (is_predicted = true):
##     客户端射击时立即创建子弹 (预测)，同时发送 RPC 给服务器验证。
##     预测子弹在收到 server_verify_shot 前已开始飞行，避免射击延迟感。
##     服务器校验后回传校正位置，BulletTracker 更新子弹数据。
##
##   服务器权威层 (is_predicted = false):
##     服务器验证通过后，子弹状态标记为已验证。
##     其他客户端通过 server_spawn_bullet RPC 创建的远程子弹属于此层。
##
## ID 分配策略:
##   使用自增计数器 (_id_counter)，而非 randi()。
##   虽未完全杜绝碰撞 (多客户端同时射击)，但概率远低于 randi。
##   正式项目建议用 peer_id + 本地递增序列的复合键。
## ============================================================================

extends Node

# ============================================================
# 常量
# ============================================================

## 子弹最大飞行距离 (像素)，超过后自动销毁
const MAX_DISTANCE: float = 1000.0
## 子弹飞行速度 (像素/秒)
const SPEED: float = 400.0

# ============================================================
# 属性
# ============================================================

## 已注册子弹数据字典
## 键: bullet_id (int)
## 值: { owner_id, position, direction, is_predicted }
var bullets: Dictionary = {}

## 待服务器验证的预测子弹 ID 列表
var pending_shots: Array[int] = []

## 自增 ID 计数器
var _id_counter: int = 0

# ============================================================
# 公开方法
# ============================================================

## 生成下一个子弹 ID
## 返回递增后的值，调用方在注册时使用。
func next_bullet_id() -> int:
	return _id_counter + 1

## 注册本地射击
## 在发射子弹时调用，标记为预测状态，加入待验证列表。
## 参数 bullet_id 必须与 NetworkManager._spawn_bullet_local 使用的 ID 一致。
func register_local_shot(bullet_id: int, direction: float) -> void:
	_id_counter += 1
	bullets[bullet_id] = {
		owner_id = NetworkManager.get_peer_id(),
		position = Vector2.ZERO,   # 由 bullet 实例在 _enter_tree 中回填
		direction = direction,
		is_predicted = true
	}
	pending_shots.append(bullet_id)

## 注册远程子弹
## 由 NetworkManager._spawn_bullet_remote 调用，标记为非预测状态。
func register_remote_bullet(bullet_id: int, owner_id: int, spawn_position: Vector2, direction: float) -> void:
	bullets[bullet_id] = {
		owner_id = owner_id,
		position = spawn_position,
		direction = direction,
		is_predicted = false
	}

## 更新子弹位置
## 由 bullet.gd 的 _physics_process 每帧调用，用于追踪飞行距离和位置。
func update_bullet_position(bullet_id: int, new_position: Vector2) -> void:
	if bullets.has(bullet_id):
		bullets[bullet_id].position = new_position

## 注销子弹
## 子弹销毁时调用 (bullet._exit_tree)，防止字典膨胀 (内存泄漏)。
func unregister_bullet(bullet_id: int) -> void:
	bullets.erase(bullet_id)
	pending_shots.erase(bullet_id)

## 服务器验证射击通过，校正预测子弹
## 将预测子弹标记为已验证，校正其位置为服务器权威值。
## 由 server_verify_shot RPC 触发。
func verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	if not bullets.has(bullet_id):
		return
	bullets[bullet_id].is_predicted = false
	bullets[bullet_id].position = actual_position
	pending_shots.erase(bullet_id)

## 获取子弹数据
## bullet.gd 在 _enter_tree 中调用以读取初始化参数。
func get_bullet_data(bullet_id: int) -> Dictionary:
	return bullets.get(bullet_id, {})

## 清理指定玩家的所有子弹记录
## 玩家断开时由服务器 RPC 链触发。
func clear_player_bullets(player_id: int) -> void:
	var to_remove: Array[int] = []
	for bullet_id: int in bullets:
		if bullets[bullet_id].owner_id == player_id:
			to_remove.append(bullet_id)
	for bid: int in to_remove:
		bullets.erase(bid)
		pending_shots.erase(bid)

## 断开时清理全部数据
## 在 NetworkManager._on_connected_to_server 中调用，防止重连后残留旧会话数据。
func clear_all() -> void:
	bullets.clear()
	pending_shots.clear()
