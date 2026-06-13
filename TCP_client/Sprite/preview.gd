## 预览体,用于在生成玩家实例前定位生成位置
extends Sprite2D

## 预览确认(位置坐标)
signal Preview_Confirm(Position:Vector2)

## 左键状态
var LeftMouse_Status:bool
## 预览状态
var Preview_Status:bool = false
## 鼠标坐标(基于画布层)
@onready var Mouse_Position : Vector2 


func _ready() -> void:
	self.visible = false

## 侦测事件状态
func _input(event:InputEvent)->void:
	# 判断事件是否来自鼠标点击
	if event is InputEventMouseButton:
		LeftMouse_Status = event.is_action_pressed("Click_Mouse_Left")
		
		# 如果处于预览状态且鼠标左键按下,广播预览确认
		if Preview_Status and LeftMouse_Status:
			Preview_Confirm.emit(Mouse_Position)
			Preview_Status = false
			self.visible = false
	
	# 如果事件来自鼠标移动,且处于预览状态,则跟随鼠标
	if event is InputEventMouseMotion:
		if Preview_Status:
			Mouse_Position = get_global_mouse_position()
			global_position = Mouse_Position

## 显示预览,用于调整可见性
func Show_Preview():
	self.modulate.a8 = 150
	Preview_Status = true
	self.visible = true
