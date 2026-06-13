## 客户端
extends Node

## 创建对等体类
var Game_Peer : ENetMultiplayerPeer
## 作为对等体联机的ID
var SelfID:int
## 生成对等体玩家的坐标
var Player_Position:Vector2 = Vector2(500,500)

#region Node
## 输出版的节点
@onready var OutputLabel_Node =$MarginContainer/VBoxContainer/MarginContainer/RichTextLabel
## 服务器地址输入端的节点
@onready var Server_Address_Node = $MarginContainer/VBoxContainer/HBoxContainer/LineEdit
## 服务器端口输入端的节点
@onready var Server_Port_Node = $MarginContainer/VBoxContainer/HBoxContainer/LineEdit2
## 实例区的节点
@onready var Example_Area_Node = $MultiplayerSpawner/Example_Area
## 子弹区的节点
@onready var BulletManager_Node = $MultiplayerSpawner2/BulletManager

#endregion

## 客户端对服务器端的连接状态
var Connect_State:bool = false

## 该玩家生成的子弹的字典(ID:[位置,速度])
var Bullet_Dictionary:Dictionary


## 返回当前系统时间(String)
func Get_Time() -> String:
	var SystemTime = Time.get_datetime_string_from_system(false,true)
	return SystemTime

func _ready() -> void:
	Game_Peer = ENetMultiplayerPeer.new()
	$Preview.Preview_Confirm.connect(_CallbackGeneration)

## 连接服务器按钮按下时发生的函数
func _ConnectToServer_Btn_press():
	Connect_To_Server(int(Server_Port_Node.text)) 


## 连接到服务器(端口:int)
func Connect_To_Server(port:int):
	# 判断客户端是否已创建
	if Connect_State:
		OutputLabel_Node.append_text("客户端连接服务器失败,错误原因:\n 客户端已存在\n")
		return
	
	# 连接服务器
	var Peer_Error = Game_Peer.create_client(Server_Address_Node.text,port)
	if Peer_Error != OK:
		OutputLabel_Node.append_text("客户端连接服务器失败,错误代码：\n " + str(Peer_Error) + "\n")
		return
		
	# 客户端加入游戏，触发服务端信号，并将自己的ID传给服务端
	multiplayer.multiplayer_peer = Game_Peer  
	# 获取客户端的唯一ID
	SelfID = multiplayer.get_unique_id()
	
	# 设置信号连接: "监听客户端连接失败","监听服务器端连接断开","监听客户端的连接成功"
	multiplayer.connection_failed.connect(_server_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	OutputLabel_Node.append_text("连接中......若长时间无反应,有可能是服务器未开启\n")
	$MarginContainer/VBoxContainer/HBoxContainer/ConnectToServer_Btn.disabled = true

## 服务器连接失败时发生的函数
func _server_connection_failed():
	Game_Peer.close()
	# 断开对应连接
	multiplayer.connection_failed.disconnect(_server_connection_failed)
	multiplayer.server_disconnected.disconnect(_server_disconnected)
	multiplayer.connected_to_server.disconnect(_connected_to_server)
	
	OutputLabel_Node.append_text("连接失败,服务器未响应\n")
	$MarginContainer/VBoxContainer/HBoxContainer/ConnectToServer_Btn.disabled = false

## 服务器断开连接时发生的函数
func _server_disconnected():
	Game_Peer.close()
	# 断开对应连接
	multiplayer.connection_failed.disconnect(_server_connection_failed)
	multiplayer.server_disconnected.disconnect(_server_disconnected)
	multiplayer.connected_to_server.disconnect(_connected_to_server)
	
	Connect_State = false
	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("服务器已关闭\n")
	$MarginContainer/VBoxContainer/HBoxContainer/ConnectToServer_Btn.disabled = false

## 客户端连接到服务器时发生的函数
func _connected_to_server():
	Connect_State = true
	# 预留:连接到服务器发生的函数
	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("客户端连接成功,ID： " + str(SelfID) + "\n")
	$MarginContainer/VBoxContainer/HBoxContainer/ConnectToServer_Btn.disabled = true
	$MarginContainer/VBoxContainer/HBoxContainer/GenerateRoles_Btn.disabled = false

## 按下生成角色按钮时发生的函数
func _GenerateRoles_Btn_press():
	#启用预览体,接受到预览体确认信号后会调用rpc
	$Preview.Show_Preview()
	
## 预览体传回定位信息后,向服务器调用(位置)
func _CallbackGeneration(Position:Vector2):
	#将预览体的位置信息保留,用于设置对等体的生成位置
	Player_Position = Position
	
	# 向ID为1(服务器端)的peer调用rpc
	FromClient_Request_Spawn_Player(SelfID)
	
	OutputLabel_Node.append_text(Get_Time() + ":\n")
	OutputLabel_Node.append_text("向服务器调用rpc:生成角色\n")
	$MarginContainer/VBoxContainer/HBoxContainer/GenerateRoles_Btn.disabled = true

## 来自客户端rpc的调用:请求创建服务器对等体(注:必须存在该同名函数以匹配服务器的方法)
@rpc("authority","call_remote","reliable") 
func FromClient_Request_Spawn_Player(ID):
	rpc_id(1, "FromClient_Request_Spawn_Player", ID)
	
## 来自服务器rpc的调用:创建客户端对等体
@rpc("authority","call_remote","reliable") # 仅主控(默认指服务器)可调用,自身调用时不会在该对等体上执行该函数
func FromServer_Spawn_Player(ID):
	if ID == SelfID or Example_Area_Node.has_node(str(ID)):
		return
	# 添加实例(ID),该实例会将ID设为节点名
	var player = load("res://Scene/player.tscn").instantiate()
	player.name = str(ID)
	
	Example_Area_Node.add_child(player)
	OutputLabel_Node.append_text("同步远程玩家:" + str(ID) + "\n")

## 内部申请子弹
# 该方法的调用来自player发射子弹时
func Request_Spawn_Bullet(ID, Bullet_ID):
	FromClient_Request_Spawn_Bullet(ID, Bullet_ID)

## 来自客户端rpc的调用:请求生成子弹(客户端ID,位置,角度)
@rpc("authority","call_remote","reliable")
func FromClient_Request_Spawn_Bullet(ID, Bullet_ID):
	rpc_id(1, "FromClient_Request_Spawn_Bullet", ID, Bullet_ID) 

## 来自服务器rpc的调用:生成子弹(客户端ID,子弹ID,位置,角度)
@rpc("authority","call_remote","reliable")
func FromServer_Spawn_Bullet(ID, Bullet_ID):
	if ID == SelfID or BulletManager_Node.has_node(str(ID)):
		return
	# 添加实例(ID),该实例会将ID设为节点名
	var Bullet = load("res://Scene/bullet.tscn").instantiate()
	
	Bullet.name = str(Bullet_ID)
	
	BulletManager_Node.add_child(Bullet)
	OutputLabel_Node.append_text("同步远程子弹:" + str(ID) + "\n")
