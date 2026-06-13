## 子弹 — 权威端驱动的 Area2D
## 飞行逻辑仅权威端执行。position/rotation 由生成器设置，MultiplayerSynchronizer 自动同步。
extends Area2D

# ============================================================
# 属性
# ============================================================

## 子弹唯一 ID（从节点名解析）
var bullet_id: int = 0

## 拥有者（射击者）的 peer ID
var owner_id: int = 0

## 已飞行距离
var _traveled_distance: float = 0.0

# ============================================================
# 生命周期
# ============================================================

func _enter_tree() -> void:
	bullet_id = name.to_int()
	owner_id = get_multiplayer_authority()

func _ready() -> void:
	visible = true
	monitoring = true
	if is_multiplayer_authority():
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)
		print("[Bullet %d] authority ready, body_entered connected" % bullet_id)

func _exit_tree() -> void:
	BulletTracker.unregister_bullet(bullet_id)

# ============================================================
# 飞行（仅权威端处理）
# ============================================================

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not is_multiplayer_authority():
		return

	var movement: Vector2 = Vector2.RIGHT.rotated(rotation) * BulletTracker.SPEED * delta
	position += movement
	_traveled_distance += movement.length()

	if _traveled_distance >= BulletTracker.MAX_DISTANCE:
		NetworkManager.rpc_id(1, "_server_req_remove_bullet", owner_id, bullet_id, position)
		queue_free()

# ============================================================
# 碰撞检测（仅权威端处理）
# ============================================================

func _on_body_entered(body: Node2D) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	print("[Bullet %d] body_entered fired! body=%s, class=%s, is_auth=%s" % [bullet_id, body.name, body.get_class(), is_multiplayer_authority()])

	if not is_multiplayer_authority():
		return

	# 只检测玩家（CharacterBody2D）
	if not body is CharacterBody2D:
		print("[Bullet %d] body is not CharacterBody2D, ignoring" % bullet_id)
		return

	# 不检测自己
	var hit_player_id: int = body.name.to_int()
	if hit_player_id == owner_id:
		print("[Bullet %d] hit self (owner_id=%d), ignoring" % [bullet_id, owner_id])
		return

	print("[Bullet %d] HIT player %d! Sending RPC to server..." % [bullet_id, hit_player_id])
	# 通知服务器：子弹命中
	NetworkManager.rpc_id(1, "_server_req_bullet_hit", owner_id, bullet_id, hit_player_id, position)
	queue_free()
