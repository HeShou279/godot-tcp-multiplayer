## 弹幕子弹
extends Area2D

### main节点
#@onready var Main_Node : Node = get_tree().current_scene
var Main_Node : Node

## 子弹ID
var Bullet_ID : int
## 生成体ID
var PlayerID :int
## 初始化字典
var InitData:Array

## 最大飞行距离
var Max_Sistance = 1000
## 子弹飞行速度
var Speed = 100
## 已飞行距离
var Traveled_Distance = 0


func _enter_tree() -> void:
	Main_Node  = get_node_or_null("/root/Main")
	if !Main_Node.Bullet_Dictionary.has(self.name):
		return
	
	InitData = Main_Node.Bullet_Dictionary[self.name]
	set_multiplayer_authority(InitData[0])
	position = InitData[1]
	rotation = InitData[2]
	


func _ready() -> void:
	self.visible = true
	
func _process(delta):
	if !is_multiplayer_authority():
		return
		
		
	var Movement = Vector2.RIGHT.rotated(rotation) * Speed * delta
	position += Movement
	Traveled_Distance += Movement.length()
	#if Traveled_Distance >= Max_Sistance:
		#queue_free()  # 超出距离后销毁
