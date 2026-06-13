## 服务器
extends CanvasLayer

## 服务器的对等体
var Server_Peer = ENetMultiplayerPeer.new()
## 用于存储所有玩家的ID
var ClientID_Array:Array[int]

#region Node
## 输出版的节点
@onready var OutputLabel_Node = $MarginContainer/VBoxContainer/MarginContainer/RichTextLabel
## 服务器地址输入端的节点
@onready var Server_Address_Node = $MarginContainer/VBoxContainer/HBoxContainer1/LineEdit
## 服务器端口输入端的节点
@onready var Server_Port_Node = $MarginContainer/VBoxContainer/HBoxContainer1/LineEdit2
## 实例区的节点
@onready var Example_Area_Node = $MultiplayerSpawner/Example_Area
## 弹幕区的节点
@onready var BulletManager_Node = $MultiplayerSpawner2/BulletManager

#endregion

func _ready() -> void:
	OutputLabel_Node.append_text("_Ready\n")

## 返回当前系统时间(String)
func Get_Time() -> String:
	var SystemTime = Time.get_datetime_string_from_system(false,true)
	return SystemTime
	
## 测试按钮按下后发生的函数
func _Test_Btn_press():
	if !ClientID_Array:
		OutputLabel_Node.append_text("在线玩家数组为空\n")
		return
	
	OutputLabel_Node.append_text("当前在线玩家ID: \n")
	for ID in ClientID_Array:
		OutputLabel_Node.append_text(str(ID) + "\n")
	
## 清空页面按钮按下后发生的函数
func _Clear_Btn_press():
	OutputLabel_Node.clear()
	OutputLabel_Node.append_text("---\n")
	
## 创建服务器按下后发生的函数:
func _creat_server_button_pressed() -> void:
	$MarginContainer/VBoxContainer/HBoxContainer1/CreatServer_Btn.disabled = true
	$MarginContainer/VBoxContainer/HBoxContainer2/CloseServer_Btn.disabled = false
	
	# 创建监听服务器
	# 设置服务器地址,默认地址127.0.0.1
	Server_Peer.set_bind_ip(Server_Address_Node.text)
	# 设置服务器端口,默认端口7788
	var Peer_Error = Server_Peer.create_server(int(Server_Port_Node.text),800)
	if Peer_Error != OK:
		OutputLabel_Node.append_text("服务器创建失败,错误原因:\n " + str(Peer_Error) + "\n")
		return
	
	# 将联机的类的对等体设置为服务器
	multiplayer.multiplayer_peer = Server_Peer
	# 设置信号连接"监听客户端的连接"和"监听客户端的断开"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# multiplayer.get_unique_id() -> 获取对等体的ID,服务器ID一般为1,客户端为随机正整数
	
	# 预留:创建游戏服务器后需要运行的功能
	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("服务器创建成功,地址" + Server_Address_Node.text +":" + Server_Port_Node.text + "\n")

## 关闭服务器按钮按下后发生的函数
func _close_server_button_pressed() -> void:
	$MarginContainer/VBoxContainer/HBoxContainer1/CreatServer_Btn.disabled = false
	$MarginContainer/VBoxContainer/HBoxContainer2/CloseServer_Btn.disabled = true
	
	# 主动强制断开所有已连接的客户端
	for ClientID in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(ClientID)  
	
	# 关闭服务器
	Server_Peer.close()
	
	# 清空当前multiplayer_peer引用
	if multiplayer.multiplayer_peer == Server_Peer:
		multiplayer.multiplayer_peer = null
	
	# 清空客户端连接数组和实例区的对等体
	ClientID_Array.clear()
	for node in Example_Area_Node.get_children():
		node.queue_free()

	# 断开信号连接
	multiplayer.peer_connected.disconnect(_on_peer_connected)
	multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	
	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("服务器已关闭\n")

## 当有客户端连接服务器时发生的函数
func _on_peer_connected(ID:int):
	# 判断是否是服务端,这个判断在 服务器和客户端一体 的项目中比较重要
	if multiplayer.is_server():
		ClientID_Array.append(ID)
		OutputLabel_Node.append_text(Get_Time() + ":\n")
		OutputLabel_Node.append_text("有客户端连接服务器,ID:" + str(ID) + "\n")
	
## 当有玩家断开服务器连接时发生的函数
func _on_peer_disconnected(ID:int):
	# 移除该客户端在客户端数组的ID,移除该客户端生成的角色实例
	ClientID_Array.erase(ID)
	if Example_Area_Node.has_node(str(ID)):
		Example_Area_Node.get_node(str(ID)).queue_free()
	
	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("有玩家离开服务器,ID:" + str(ID) + "\n")

## 来自客户端的rpc调用:请求创建服务器对等体(客户端ID)
@rpc("any_peer", "call_local","reliable")  # 允许所有对等体调用,调用时在当前对等体也执行该函数
func FromClient_Request_Spawn_Player(ID:int):
	# 创建对等体(空实例)
	var player = load("res://Scene/player.tscn").instantiate()
	player.name = str(ID)
	
	# 一定不要忘记设置权限,不然会一直报错!
	player.set_multiplayer_authority(ID) 
	Example_Area_Node.add_child(player)
	
	# 向所有客户端调用生成客户端实例的rpc
	FromServer_Spawn_Player.rpc(ID) 

	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("客户端(ID: " + str(ID) + " )创建角色\n")
	
## 向其他客户端调用生成实例的rpc
@rpc("authority", "call_remote", "reliable") # 仅主控(默认指服务器)可调用,自身调用时不会在该对等体上执行该函数
func FromServer_Spawn_Player(ID:int):
	# 空实现,作为rpc的同名函数
	print(ID)


## 来自客户端rpc的调用:请求生成子弹(客户端ID,位置,角度)
@rpc("any_peer","call_local","reliable")
func FromClient_Request_Spawn_Bullet(ID:int, Bullet_ID):
	# 非创建非预测子弹实例
	var Bullet = load("res://Scene/bullet.tscn").instantiate()
	Bullet.name = str(Bullet_ID)

	Bullet.set_multiplayer_authority(ID)
	BulletManager_Node.add_child(Bullet)
	
	# 向所有客户端调用生成子弹实例的rpc(含子弹ID用于预测校正)
	FromServer_Spawn_Bullet.rpc(ID, Bullet_ID) 
	
	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("客户端(ID: " + str(ID) + " )创建子弹\n")

## 来自服务器rpc的调用:生成子弹(客户端ID,位置,角度)
@rpc("authority", "call_remote", "reliable")
func FromServer_Spawn_Bullet(ID, Bullet_ID):
	# 空实现,作为rpc的同名函数
	print(ID+Bullet_ID)
