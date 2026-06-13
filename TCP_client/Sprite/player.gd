## 玩家实例
extends CharacterBody2D

## 移动速度
@export var speed := 400
## 移动加速度
@export var acceleration := 50
## 摩擦值
@export var friction := 30

## main节点
@onready var Main_Node : Node = get_tree().current_scene

func _enter_tree() -> void:
	# 设置节点权限
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	$ID_Label.text = "ID: " + self.name
	
	if is_multiplayer_authority():
		self.position = Main_Node.Player_Position

## 侦测事件状态
func _input(event:InputEvent)->void:
	# 非权威体不处理该函数
	if !is_multiplayer_authority():
		return
	
	# 判断事件是否来自鼠标点击
	if event is InputEventMouseButton:
		if event.is_action_pressed("Click_Mouse_Left"):
			Player_Shoot()
			
			pass

	

func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	Move()

## 移动
func Move():
# 获取输入向量
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# 计算移动方向
	if input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(input_vector * speed, acceleration)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction)
	
	# 摄像机聚焦自己
	Main_Node.get_node("Camera2D").position = self.position
	# 执行移动并处理碰撞
	move_and_slide()

## 生成子弹(发射弹幕)
func Player_Shoot():
	var direction = (get_global_mouse_position() - global_position).angle()
	# 来自客户端rpc的调用:请求生成子弹
	var Bullet_ID:int = randi()
	Main_Node.Bullet_Dictionary[str(Bullet_ID)] = [Main_Node.SelfID,global_position,direction]
	Main_Node.Request_Spawn_Bullet(Main_Node.SelfID, Bullet_ID)
