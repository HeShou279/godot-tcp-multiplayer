## 预览体 — 生成角色前跟随鼠标定位
extends Sprite2D

# ============================================================
# 信号
# ============================================================

signal preview_confirm(position: Vector2)

# ============================================================
# 属性
# ============================================================

var _preview_active: bool = false

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	visible = false

# ============================================================
# 输入处理
# ============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var left_pressed: bool = event.is_action_pressed("Click_Mouse_Left")
		if _preview_active and left_pressed:
			preview_confirm.emit(get_global_mouse_position())
			_preview_active = false
			visible = false

	if event is InputEventMouseMotion:
		if _preview_active:
			global_position = get_global_mouse_position()

# ============================================================
# 公开方法
# ============================================================

## 显示预览体，开始跟随鼠标
func show_preview() -> void:
	modulate.a = 150
	_preview_active = true
	visible = true
