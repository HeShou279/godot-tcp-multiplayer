## ============================================================================
## Preview — 生成位置预览体 (Sprite2D)
## ============================================================================
##
## 架构定位:
##   纯本地 UI 辅助节点，不参与任何网络通信。
##   在点击"创建角色实例"按钮后显示，跟随鼠标移动。
##   左键点击确认位置后发射 preview_confirm 信号，通知 client_main 发起生成。
##
## 交互流程:
##   1. client_main._on_generate_btn_pressed() → preview.show_preview()
##   2. Preview 显示并进入 _preview_active 模式
##   3. 鼠标移动 → Preview.global_position 跟随鼠标
##   4. 左键点击 → 发射 preview_confirm(position) → 隐藏自身
##   5. client_main._on_preview_confirm() → NetworkManager.request_spawn_player()
## ============================================================================

extends Sprite2D

# ============================================================
# 信号
# ============================================================

## 预览位置已确认，携带确认时的全局鼠标坐标
signal preview_confirm(position: Vector2)

# ============================================================
# 属性
# ============================================================

## 是否处于预览激活状态
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
	# 左键确认生成位置
	if event is InputEventMouseButton:
		var left_pressed: bool = event.is_action_pressed("Click_Mouse_Left")
		if _preview_active and left_pressed:
			preview_confirm.emit(get_global_mouse_position())
			_preview_active = false
			visible = false

	# 鼠标移动时更新预览位置
	if event is InputEventMouseMotion:
		if _preview_active:
			global_position = get_global_mouse_position()

# ============================================================
# 公开方法
# ============================================================

## 显示预览体，开始跟随鼠标
## 设置半透明 (modulate.a = 150/255 ≈ 0.59)，激活追踪模式。
func show_preview() -> void:
	modulate.a = 150
	_preview_active = true
	visible = true
