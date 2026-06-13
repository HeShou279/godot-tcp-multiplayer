## 弹幕管理器
extends Node

## 待验证的射击队列（用于预测校正）
var PendingShots_Array = []

## 本地预测生成子弹,调用这个脚本后会先在本地生成子弹实例,再从服务器同步有效的子弹
func _Create_Bullet_Local(Position, Direction):
	var Bullet:Node = load("res://Scene/bullet.tscn").instantiate()
	# 设置网络权限为当前客户端
	Bullet.set_multiplayer_authority(multiplayer.get_unique_id())
	# 初始化子弹（true表示是预测生成的临时弹幕）
	Bullet.init(Position, Direction, true)  
	add_child(Bullet)
	# 加入待验证队列
	PendingShots_Array.append(Bullet)

## 服务端验证通过,修正子弹的位置(对应子弹ID,实际位置)
func On_Shoot_Verified(Shot_Id:int, Actual_Position:Vector2):
	# 遍历待验证队列
	for Bullet in PendingShots_Array:
		if Bullet.Shot_Id == Shot_Id:
			# 校正预测子弹的位置
			Bullet.Reconcile(Actual_Position)
			# 从队列移除
			PendingShots_Array.erase(Bullet)
