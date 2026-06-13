## BulletTracker — 子弹生命周期管理单例 (autoload)
## 职责：管理所有子弹的注册/注销/预测校正，替代旧 bullet_manager + Bullet_Dictionary。
extends Node

# ============================================================
# 常量
# ============================================================

## 子弹最大飞行距离
const MAX_DISTANCE: float = 1000.0
## 子弹飞行速度
const SPEED: float = 400.0

# ============================================================
# 属性
# ============================================================

## 已注册子弹数据字典  {bullet_id: {owner_id, position, direction, is_predicted}}
var bullets: Dictionary = {}

## 待服务器验证的预测子弹 ID 列表
var pending_shots: Array[int] = []

## 自增 ID 计数器
var _id_counter: int = 0

# ============================================================
# 公开方法
# ============================================================

## 生成下一个子弹 ID (格式: peer_id_counter，避免碰撞)
func next_bullet_id() -> int:
	return _id_counter + 1

## 注册本地射击（预测生成 + 待验证）
func register_local_shot(bullet_id: int, direction: float) -> void:
	_id_counter += 1
	bullets[bullet_id] = {
		owner_id = NetworkManager.get_peer_id(),
		position = Vector2.ZERO,   # 由 bullet 实例在 _enter_tree 中回填
		direction = direction,
		is_predicted = true
	}
	pending_shots.append(bullet_id)

## 注册远程子弹（来自服务器同步）
func register_remote_bullet(bullet_id: int, owner_id: int, spawn_position: Vector2, direction: float) -> void:
	bullets[bullet_id] = {
		owner_id = owner_id,
		position = spawn_position,
		direction = direction,
		is_predicted = false
	}

## 更新子弹位置（由 bullet.gd 的 _process 调用）
func update_bullet_position(bullet_id: int, new_position: Vector2) -> void:
	if bullets.has(bullet_id):
		bullets[bullet_id].position = new_position

## 注销子弹（bullet 销毁时调用，修复内存泄漏）
func unregister_bullet(bullet_id: int) -> void:
	bullets.erase(bullet_id)
	pending_shots.erase(bullet_id)

## 服务器验证射击通过，校正预测子弹
func verify_shot(bullet_id: int, actual_position: Vector2) -> void:
	if not bullets.has(bullet_id):
		return
	bullets[bullet_id].is_predicted = false
	bullets[bullet_id].position = actual_position
	pending_shots.erase(bullet_id)

## 获取子弹数据（bullet.gd 在 _enter_tree 中读取初始化数据）
func get_bullet_data(bullet_id: int) -> Dictionary:
	return bullets.get(bullet_id, {})

## 清理指定玩家的所有子弹（玩家断开时调用）
func clear_player_bullets(player_id: int) -> void:
	var to_remove: Array[int] = []
	for bullet_id: int in bullets:
		if bullets[bullet_id].owner_id == player_id:
			to_remove.append(bullet_id)
	for bid: int in to_remove:
		bullets.erase(bid)
		pending_shots.erase(bid)

## 断开时清理全部数据
func clear_all() -> void:
	bullets.clear()
	pending_shots.clear()
