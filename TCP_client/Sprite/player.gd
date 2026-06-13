## 玩家角色 — 权威端驱动的 CharacterBody2D
## 仅拥有网络权限的客户端处理输入与移动，MultiplayerSynchronizer 自动同步。
extends CharacterBody2D

# ============================================================
# 导出属性
# ============================================================

@export var speed: float = 400.0
@export var acceleration: float = 50.0
@export var friction: float = 30.0

# ============================================================
# 节点引用
# ============================================================

@onready var _id_label: Label = $ID_Label
@onready var _sprite: Sprite2D = $Sprite2D

# ============================================================
# 生命周期
# ============================================================

func _enter_tree() -> void:
	# 从节点名还原网络权限 ID
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	_id_label.text = "ID: " + name

# ============================================================
# 输入（仅权威端处理）
# ============================================================

func _input(event: InputEvent) -> void:
	if multiplayer.multiplayer_peer == null or not is_multiplayer_authority():
		return

	if event is InputEventMouseButton:
		if event.is_action_pressed("Click_Mouse_Left"):
			_shoot()

# ============================================================
# 物理帧（仅权威端处理）
# ============================================================

func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not is_multiplayer_authority():
		return
	_move()
	_update_camera()

# ============================================================
# 移动
# ============================================================

func _move() -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(input_vector * speed, acceleration)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction)

	move_and_slide()

# ============================================================
# 射击
# ============================================================

func _shoot() -> void:
	var direction: float = (get_global_mouse_position() - global_position).angle()
	NetworkManager.request_spawn_bullet(global_position, direction)

# ============================================================
# 受击动画
# ============================================================

## 播放超亮白闪受击动画（modulate > 1.0 产生过曝效果）
func play_hit_animation() -> void:
	if not _sprite:
		return
	print("[Player %s] play_hit_animation() called" % name)
	var tw: Tween = create_tween()
	var overbright: Color = Color(8, 8, 8, 1)
	var normal: Color = Color(1, 1, 1, 1)
	tw.tween_property(_sprite, "modulate", overbright, 0.05)
	tw.tween_property(_sprite, "modulate", normal, 0.05)
	tw.tween_property(_sprite, "modulate", overbright, 0.05)
	tw.tween_property(_sprite, "modulate", normal, 0.05)

# ============================================================
# 摄像机
# ============================================================

func _update_camera() -> void:
	var camera: Camera2D = get_tree().current_scene.get_node_or_null("Camera2D")
	if camera:
		camera.position = position
