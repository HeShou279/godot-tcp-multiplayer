## ============================================================================
## server_main.gd — 服务器主场景 (CanvasLayer)
## ============================================================================
##
## 架构定位:
##   纯 UI 控制器，不包含网络或游戏逻辑。
##   所有网络操作委托给 NetworkManager autoload。
##
## 职责:
##   - 启动/关闭服务器按钮 (创建/关闭 ENet 服务器)
##   - 容器注入: 将场景中的 Example_Area 和 BulletManager 传给 NetworkManager
##   - 信号监听: NetworkManager 的 5 个信号 → 更新日志面板
##   - 在线客户端查看 (Test 按钮)
##   - 日志清空 (Clear 按钮)
##
## 按钮状态机:
##   初始:     [创建]可用  [关闭]禁用
##   服务器启动: [创建]禁用  [关闭]可用
##   服务器关闭: [创建]可用  [关闭]禁用 (恢复初始)
## ============================================================================

extends CanvasLayer

# ============================================================
# 节点引用
# ============================================================

@onready var _output_label: RichTextLabel = $MarginContainer/VBoxContainer/MarginContainer/RichTextLabel
@onready var _address_input: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer1/LineEdit
@onready var _port_input: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer1/LineEdit2
@onready var _create_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer1/CreatServer_Btn
@onready var _close_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer2/CloseServer_Btn
@onready var _test_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer2/Test_Btn
@onready var _clear_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer2/Clear_Btn

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 将场景中的实例容器注入 NetworkManager
	# NetworkManager 使用这些容器创建/管理所有玩家和子弹实例
	NetworkManager.set_containers($Example_Area, $BulletManager)

	# 连接 NetworkManager 的全部信号到本地 UI 回调
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.server_stopped.connect(_on_server_stopped)
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.client_disconnected.connect(_on_client_disconnected)
	NetworkManager.server_log.connect(_on_server_log)

	_append_log("服务器就绪")

# ============================================================
# 按钮回调
# ============================================================

## 创建服务器按钮
## 读取地址/端口输入框，调用 NetworkManager.start_server。
## 成功后禁用创建按钮，启用关闭按钮。
func _on_create_server_btn_pressed() -> void:
	var address: String = _address_input.text
	var port: int = int(_port_input.text)

	var err: Error = NetworkManager.start_server(address, port)
	if err != OK:
		_append_log("服务器创建失败，错误代码: %d" % err)
		return

	_create_btn.disabled = true
	_close_btn.disabled = false

## 关闭服务器按钮
## 调用 NetworkManager.stop_server，内部处理:
##   断开所有客户端 → 清理实例 → 关闭 peer → 发射 server_stopped 信号
func _on_close_server_btn_pressed() -> void:
	NetworkManager.stop_server()

## 测试按钮 — 查看当前在线客户端列表
func _on_test_btn_pressed() -> void:
	var peers: Array = NetworkManager.get_connected_peers()
	if peers.is_empty():
		_append_log("当前无在线客户端")
		return

	_append_log("当前在线客户端 ID:")
	for id: int in peers:
		_append_log("  - %d" % id)

## 清空日志面板
func _on_clear_btn_pressed() -> void:
	_output_label.clear()
	_output_label.append_text("---\n")

# ============================================================
# 网络事件回调
# ============================================================

## 服务器启动成功
func _on_server_started(address: String, port: int) -> void:
	_append_log("服务器已启动 — %s:%d" % [address, port])

## 服务器已关闭
## 恢复按钮初始状态。
func _on_server_stopped() -> void:
	_create_btn.disabled = false
	_close_btn.disabled = true
	_append_log("服务器已关闭")

## 客户端连接
func _on_client_connected(peer_id: int) -> void:
	_append_log("客户端已连接，ID: %d" % peer_id)

## 客户端断开
func _on_client_disconnected(peer_id: int) -> void:
	_append_log("客户端已离开，ID: %d" % peer_id)

## 服务器内部日志 (来自 NetworkManager.server_log 信号)
func _on_server_log(message: String) -> void:
	_append_log(message)

# ============================================================
# 工具方法
# ============================================================

## 向日志面板追加带时间戳的消息
func _append_log(message: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	_output_label.append_text("%s:\n%s\n" % [timestamp, message])
