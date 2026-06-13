## 服务器主场景 — UI 控制器
## 职责：仅负责 UI 交互，所有网络/游戏逻辑委托给 NetworkManager autoload。
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
	NetworkManager.set_containers($Example_Area, $BulletManager)

	# 连接 NetworkManager 信号
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.server_stopped.connect(_on_server_stopped)
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.client_disconnected.connect(_on_client_disconnected)
	NetworkManager.server_log.connect(_on_server_log)

	_append_log("服务器就绪")

# ============================================================
# 按钮回调
# ============================================================

func _on_create_server_btn_pressed() -> void:
	var address: String = _address_input.text
	var port: int = int(_port_input.text)

	var err: Error = NetworkManager.start_server(address, port)
	if err != OK:
		_append_log("服务器创建失败，错误代码: %d" % err)
		return

	_create_btn.disabled = true
	_close_btn.disabled = false

func _on_close_server_btn_pressed() -> void:
	NetworkManager.stop_server()

func _on_test_btn_pressed() -> void:
	var peers: Array = NetworkManager.get_connected_peers()
	if peers.is_empty():
		_append_log("当前无在线客户端")
		return

	_append_log("当前在线客户端 ID:")
	for id: int in peers:
		_append_log("  - %d" % id)

func _on_clear_btn_pressed() -> void:
	_output_label.clear()
	_output_label.append_text("---\n")

# ============================================================
# 网络事件回调
# ============================================================

func _on_server_started(address: String, port: int) -> void:
	_append_log("服务器已启动 — %s:%d" % [address, port])

func _on_server_stopped() -> void:
	_create_btn.disabled = false
	_close_btn.disabled = true
	_append_log("服务器已关闭")

func _on_client_connected(peer_id: int) -> void:
	_append_log("客户端已连接，ID: %d" % peer_id)

func _on_client_disconnected(peer_id: int) -> void:
	_append_log("客户端已离开，ID: %d" % peer_id)

func _on_server_log(message: String) -> void:
	_append_log(message)

# ============================================================
# 工具方法
# ============================================================

func _append_log(message: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	_output_label.append_text("%s:\n%s\n" % [timestamp, message])
