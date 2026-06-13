## ============================================================================
## client_main.gd — 客户端主场景 (Main Node)
## ============================================================================
##
## 架构定位:
##   纯 UI 控制器，不包含网络或游戏逻辑。
##   所有网络操作委托给 NetworkManager autoload。
##   所有游戏逻辑由 Player/Bullet 节点自行处理。
##
## 职责边界:
##   - UI 按钮的启用/禁用状态管理
##   - 日志输出 (_output_label)
##   - 信号监听与转发 (NetworkManager → UI 更新)
##   - 预览体 (Preview) 的交互管理
##
## 不负责:
##   - 网络连接的建立/关闭 (由 NetworkManager 处理)
##   - 玩家/子弹的创建与同步 (由 NetworkManager + BulletTracker 处理)
##   - 碰撞检测、移动、射击 (由 Player/Bullet 自行处理)
##
## 按钮状态机:
##   初始:     [连接]可用  [登出]禁用  [创建]禁用
##   连接成功: [连接]禁用  [登出]可用  [创建]可用
##   断开连接: [连接]可用  [登出]禁用  [创建]禁用 (恢复初始)
## ============================================================================

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
@onready var _exit_Server_btn: Button = $MarginContainer/VBoxContainer/HBoxContainer/ExitServer_Btn
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

## 将所有 NetworkManager 信号绑定到本地 UI 回调
func _connect_network_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.player_spawned.connect(_on_remote_player_spawned)

# ============================================================
# UI 回调
# ============================================================

## 连接服务器按钮
## 读取地址和端口输入框，禁用自己的按钮并异步连接。
func _on_connect_btn_pressed() -> void:
	var address: String = _address_input.text
	var port: int = int(_port_input.text)
	_append_log("正在连接 %s:%d ..." % [address, port])
	_connect_btn.disabled = true
	NetworkManager.connect_to_server(address, port)

## 生成角色按钮 → 显示预览体
## 预览体跟随鼠标，点击确认位置后触发 _on_preview_confirm。
func _on_generate_btn_pressed() -> void:
	_preview.show_preview()

## 登出服务器按钮
## 立即禁用自身和生成按钮 (防止重复点击)，然后断开连接。
## NetworkManager.disconnect_from_server() 内部触发完整清理链:
##   _close_connection → _clear_containers → 置空 peer → 发射 server_disconnected 信号
func _on_exit_server_btn_pressed() -> void:
	_append_log("正在登出服务器...")
	_exit_Server_btn.disabled = true
	_generate_btn.disabled = true
	NetworkManager.disconnect_from_server()

## 预览体确认回调 (Preview.preview_confirm 信号)
## 在鼠标位置请求服务器创建玩家角色。
func _on_preview_confirm(position: Vector2) -> void:
	_spawn_position = position
	_generate_btn.disabled = true
	NetworkManager.request_spawn_player(_spawn_position)
	_append_log("请求生成角色，位置: %s" % str(position))

# ============================================================
# 网络事件回调
# ============================================================

## 连接成功
## 更新按钮状态: 连接按钮禁用，登出和生成按钮启用。
func _on_connected() -> void:
	_append_log("连接成功，ID: %d" % NetworkManager.get_peer_id())
	_connect_btn.disabled = true
	_exit_Server_btn.disabled = false
	_generate_btn.disabled = false

## 连接失败
## 恢复连接按钮，确保登出按钮保持禁用。
func _on_connection_failed() -> void:
	_append_log("连接失败，服务器未响应")
	_connect_btn.disabled = false
	_exit_Server_btn.disabled = true

## 与服务器断开连接
## 恢复所有按钮到初始状态，重置摄像头到默认位置。
func _on_server_disconnected() -> void:
	_append_log("与服务器断开连接")
	_connect_btn.disabled = false
	_exit_Server_btn.disabled = true
	_generate_btn.disabled = true
	# 重置摄像头到初始位置 (场景默认值 640,360)
	$Camera2D.position = Vector2(640, 360)

## 远程玩家加入
## 由 NetworkManager.player_spawned 信号触发 (本地玩家不触发)。
func _on_remote_player_spawned(player_id: int) -> void:
	_append_log("远程玩家加入，ID: %d" % player_id)

# ============================================================
# 工具方法
# ============================================================

## 向日志面板追加带时间戳的消息
func _append_log(message: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	_output_label.append_text("%s:\n%s\n" % [timestamp, message])
