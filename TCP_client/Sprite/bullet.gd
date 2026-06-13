## ============================================================================
## Bullet — 子弹实体 (Area2D)
## ============================================================================
##
## 架构定位:
##   由 NetworkManager 实例化的飞行弹丸。权威端驱动飞行逻辑和碰撞检测，
##   非权威端仅通过 MultiplayerSynchronizer 观察 position/rotation 变化。
##
## 权威模型:
##   仅拥有 multiplayer_authority 的客户端执行:
##     - _physics_process() : 沿 rotation 方向移动，累计飞行距离
##     - _on_body_entered()  : 检测与玩家的碰撞
##   非权威端:
##     所有逻辑被 is_multiplayer_authority() 守卫跳过。
##
## 生命周期:
##   1. NetworkManager._spawn_bullet_* 实例化并 add_child
##   2. _enter_tree(): 从节点名解析 bullet_id，记录 owner_id
##   3. _ready(): 显示精灵，权威端连接 body_entered 信号
##   4. _physics_process(): 每帧飞行 (仅权威端)
##   5. 销毁条件之一:
##      a. 飞行距离 >= MAX_DISTANCE → 通知服务器移除 → queue_free
##      b. 碰撞到玩家 → 通知服务器命中 → queue_free
##      c. 发射者登出 → 服务器广播移除 → queue_free
##   6. _exit_tree(): 从 BulletTracker 注销，防止字典泄漏
##
## 碰撞检测:
##   使用 Area2D.body_entered 信号，而非 _physics_process 中的手动碰撞检查。
##   body_entered 在物理帧中自动触发，比手动检查更可靠。
##   Body 的 Node 必须直接是 CharacterBody2D (不能是静态体或区域)。
##
## 同步机制:
##   MultiplayerSynchronizer 同步 position + rotation (ON_CHANGE 模式)。
##   注意: _traveled_distance 不同步，因此非权威端无法判断子弹何时超距。
##   超距销毁由权威端触发 RPC，服务器广播 server_remove_bullet 统一处理。
## ============================================================================

extends Area2D

# ============================================================
# 属性
# ============================================================

## 子弹唯一 ID（从节点名解析，节点名 = bullet_id 字符串）
var bullet_id: int = 0

## 拥有者（射击者）的 peer ID (从 multiplayer_authority 读取)
var owner_id: int = 0

## 已飞行距离（仅权威端维护，不同步）
var _traveled_distance: float = 0.0

# ============================================================
# 生命周期
# ============================================================

## 加入场景树时从节点名和 authority 还原身份
func _enter_tree() -> void:
	bullet_id = name.to_int()
	owner_id = get_multiplayer_authority()

## 就绪后连接碰撞信号（仅权威端）
## monitoring = true 确保 Area2D 参与物理重叠检测。
## is_connected 检查防止重复连接 (防御性编程)。
func _ready() -> void:
	visible = true
	monitoring = true
	if is_multiplayer_authority():
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)
		print("[Bullet %d] authority ready, body_entered connected" % bullet_id)

## 离开场景树时注销，防止 BulletTracker 字典无限增长
func _exit_tree() -> void:
	BulletTracker.unregister_bullet(bullet_id)

# ============================================================
# 飞行（仅权威端处理）
# ============================================================

## 每物理帧沿 rotation 方向飞行
## multiplayer.multiplayer_peer == null 检查防止客户端断开后崩溃。
func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not is_multiplayer_authority():
		return

	# 沿发射方向直线飞行
	var movement: Vector2 = Vector2.RIGHT.rotated(rotation) * BulletTracker.SPEED * delta
	position += movement
	_traveled_distance += movement.length()

	# 超距销毁
	if _traveled_distance >= BulletTracker.MAX_DISTANCE:
		NetworkManager.rpc_id(1, "_server_req_remove_bullet", owner_id, bullet_id, position)
		queue_free()

# ============================================================
# 碰撞检测（仅权威端处理）
# ============================================================

## Area2D.body_entered 信号回调
## 在物理帧中自动触发（当子弹 Area 与 CharacterBody2D 重叠时）。
##
## 完整的命中处理链:
##   bullet._on_body_entered (权威客户端)
##     → NetworkManager.rpc_id(1, "_server_req_bullet_hit", ...)   [上报服务器]
##     → queue_free()                                                [移除子弹]
##   服务器 _server_req_bullet_hit:
##     → remove_bullet(owner_id, bullet_id)                         [服务器移除]
##     → server_remove_bullet.rpc(owner_id, bullet_id)              [广播移除]
##     → server_player_hit.rpc(hit_player_id)                       [广播受击]
##   所有客户端 server_player_hit:
##     → player.play_hit_animation()                                [播放动画]
func _on_body_entered(body: Node2D) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	print("[Bullet %d] body_entered fired! body=%s, class=%s, is_auth=%s" % [bullet_id, body.name, body.get_class(), is_multiplayer_authority()])

	if not is_multiplayer_authority():
		return

	# 只检测玩家（CharacterBody2D），忽略静态体和 Area
	if not body is CharacterBody2D:
		print("[Bullet %d] body is not CharacterBody2D, ignoring" % bullet_id)
		return

	# 防止自伤 (子弹不能命中发射者)
	var hit_player_id: int = body.name.to_int()
	if hit_player_id == owner_id:
		print("[Bullet %d] hit self (owner_id=%d), ignoring" % [bullet_id, owner_id])
		return

	print("[Bullet %d] HIT player %d! Sending RPC to server..." % [bullet_id, hit_player_id])
	# 通知服务器：子弹命中
	NetworkManager.rpc_id(1, "_server_req_bullet_hit", owner_id, bullet_id, hit_player_id, position)
	queue_free()
