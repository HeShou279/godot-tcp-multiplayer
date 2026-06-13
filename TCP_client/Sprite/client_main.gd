## 客户端主场景 — UI 控制器
## 职责：仅负责 UI 交互，所有网络/游戏逻辑委托给 autoload 单例。
extends Node

# ============================================================
# 属性
# ============================================================

## 玩家生成预览位置（由 Preview 回调设置）
var _spawn_position: Vector2 = Vector2(500, 500)

# ============================================================
# 节点引用
# ============================================================

@onready var _output_label: RichTextLabel = $MarginContainer/VBoxContainer/MarginContainer/RichTextLabel
@onready var _address_input: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/LineEdit
@onready var _port_input: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/LineEdit2
@onready var _connect_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer/ConnectToServer_Btn
@onready var _generate_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer/GenerateRoles_Btn
@onready var _preview: Sprite2D = $Preview

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_connect_network_signals()
	_preview.preview_confirm.connect(_on_preview_confirm)

# ============================================================
# 信号连接
# ============================================================

func _connect_network_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.player_spawned.connect(_on_remote_player_spawned)

# ============================================================
# UI 回调
# ============================================================

## 连接服务器按钮
func _on_connect_btn_pressed() -> void:
	var address: String = _address_input.text
	var port: int = int(_port_input.text)
	_append_log("正在连接 %s:%d ..." % [address, port])
	_connect_btn.disabled = true
	NetworkManager.connect_to_server(address, port)

## 生成角色按钮 → 显示预览体
func _on_generate_btn_pressed() -> void:
	_preview.show_preview()

## 预览体确认回调
func _on_preview_confirm(position: Vector2) -> void:
	_spawn_position = position
	_generate_btn.disabled = true
	NetworkManager.request_spawn_player(_spawn_position)
	_append_log("请求生成角色，位置: %s" % str(position))

# ============================================================
# 网络事件回调
# ============================================================

func _on_connected() -> void:
	_append_log("连接成功，ID: %d" % NetworkManager.get_peer_id())
	_generate_btn.disabled = false

func _on_connection_failed() -> void:
	_append_log("连接失败，服务器未响应")
	_connect_btn.disabled = false

func _on_server_disconnected() -> void:
	_append_log("与服务器断开连接")
	_connect_btn.disabled = false
	_generate_btn.disabled = true

func _on_remote_player_spawned(player_id: int) -> void:
	_append_log("远程玩家加入，ID: %d" % player_id)

# ============================================================
# 工具方法
# ============================================================

func _append_log(message: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	_output_label.append_text("%s:\n%s\n" % [timestamp, message])
