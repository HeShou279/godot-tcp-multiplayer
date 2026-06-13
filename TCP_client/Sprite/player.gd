## ============================================================================
## Player — 玩家角色 (CharacterBody2D)
## ============================================================================
##
## 架构定位:
##   游戏中的玩家实体，由服务器或本地 NetworkManager 实例化并加入场景。
##   节点名 = peer_id 的字符串形式，用于网络权限路由。
##
## 权威模型:
##   仅拥有 multiplayer_authority 的客户端执行:
##     - _input()       : 鼠标射击输入
##     - _physics_process() : WASD 移动 + 摄像机跟随
##     - _shoot()       : 调用 NetworkManager.request_spawn_bullet()
##   非权威端 (其他客户端上的远程玩家):
##     上述方法被 is_multiplayer_authority() 守卫跳过。
##     position 由 MultiplayerSynchronizer 自动同步。
##
## 同步机制:
##   MultiplayerSynchronizer (在 player.tscn 中配置) 自动同步:
##     - position (replication_mode = ON_CHANGE)
##   权威端 move_and_slide() 改变 position → 自动广播到服务器和所有客户端。
##
## 碰撞:
##   collision_layer = 2 (被子弹检测)
##   collision_mask   = 2 (检测其他玩家，防止重叠)
## ============================================================================

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

## 加入场景树时从节点名还原网络权限
## 节点名是 peer_id 的字符串形式，由 NetworkManager._spawn_*_player 设置。
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	_id_label.text = "ID: " + name

# ============================================================
# 输入（仅权威端处理）
# ============================================================

## 处理射击输入
## multiplayer.multiplayer_peer 为 null 时跳过 (客户端已断开)。
func _input(event: InputEvent) -> void:
	if multiplayer.multiplayer_peer == null or not is_multiplayer_authority():
		return

	if event is InputEventMouseButton:
		if event.is_action_pressed("Click_Mouse_Left"):
			_shoot()

# ============================================================
# 物理帧（仅权威端处理）
# ============================================================

## 每物理帧处理移动 + 摄像机
func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not is_multiplayer_authority():
		return
	_move()
	_update_camera()

# ============================================================
# 移动
# ============================================================

## WASD 移动，带加速度和摩擦力
## Input.get_vector() 使用 Input Map 中定义的 move_* 动作。
## move_and_slide() 自动处理与其他玩家 (collision_mask=2) 的碰撞。
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

## 向鼠标方向射击
## 计算 global_position 到鼠标位置的方向角，委托 NetworkManager 创建子弹。
func _shoot() -> void:
	var direction: float = (get_global_mouse_position() - global_position).angle()
	NetworkManager.request_spawn_bullet(global_position, direction)

# ============================================================
# 受击动画
# ============================================================

## 播放超亮白闪受击动画
## 使用 modulate 值 > 1.0 (Color(8,8,8,1)) 产生过曝效果，
## 形成明显的白色闪烁。由 server_player_hit RPC 链触发。
## 调用链: 子弹碰撞 → 权威端上报服务器 → 服务器广播 → 所有客户端 NetworkManager
##         → play_hit_animation()
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

## 让场景中的主摄像机跟随此玩家
func _update_camera() -> void:
	var camera: Camera2D = get_tree().current_scene.get_node_or_null("Camera2D")
	if camera:
		camera.position = position
