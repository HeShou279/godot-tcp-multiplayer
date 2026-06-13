# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个用于测试 Godot 4.4 引擎通过 TCP 局域网联机的原型项目。分为两个独立的 Godot 工程：
- `TCP_server/` — 服务器模块
- `TCP_client/` — 客户端模块

每个工程需在 Godot 编辑器中单独打开（`.godot` 文件各自独立）。

## 运行方式

两个工程都使用 **Godot 4.4**、**GL Compatibility** 渲染器。

```bash
# 运行服务器（在 TCP_server 目录下）
godot --path TCP_server

# 运行客户端（在 TCP_client 目录下，可开多个实例模拟多人）
godot --path TCP_client
```

服务器默认监听 `127.0.0.1:7788`，客户端连接相同地址和端口。

## 核心架构

### 网络模型：服务器权威（Server-Authoritative）

使用 Godot 内置的 `ENetMultiplayerPeer` 作为网络对等体层。所有游戏对象由**服务器创建并持有权威**，客户端通过 RPC 请求服务器生成实例。

### RPC 通信流程

**玩家生成：**
1. 客户端点击"创建角色实例" → 预览体跟随鼠标 → 点击确认位置
2. 客户端 RPC 调用 `FromClient_Request_Spawn_Player(SelfID)` → 转发到服务器（ID=1）
3. 服务器实例化 `player.tscn`，设置 `multiplayer_authority` 为客户端 ID，加入场景
4. 服务器 RPC 广播 `FromServer_Spawn_Player(ID)` 到所有客户端（跳过拥有者本身）同步远程玩家

**子弹生成：**
1. 玩家点击鼠标左键 → `Player_Shoot()` 计算方向 → 本地记录子弹字典 → RPC 调用 `Request_Spawn_Bullet`
2. 服务器实例化 `bullet.tscn`，设置权限后广播给所有客户端
3. 客户端 `BulletManager` 支持预测生成本地子弹，再由服务器验证校正位置（`On_Shoot_Verified`）

### 关键文件和职责

**服务器端：**
- `TCP_server/Script/server_main.gd` — 服务器核心逻辑（CanvasLayer）。管理 ENetMultiplayerPeer 的创建/关闭、客户端连接/断开信号处理、RPC 玩家和子弹生成
- `TCP_server/Scene/server_main.tscn` — 主场景，包含 UI 面板 + 两个 `MultiplayerSpawner`（分别管理玩家和子弹的生成路径）
- `TCP_server/Scene/player.tscn` / `bullet.tscn` — 由服务器实例化并同步给客户端的场景模板

**客户端：**
- `TCP_client/Sprite/client_main.gd` — 客户端核心逻辑（Node）。管理服务器连接/断开、RPC 请求生成、子弹字典维护
- `TCP_client/Sprite/player.gd` — 玩家角色（CharacterBody2D）。在 `_enter_tree()` 中通过节点名设置 `multiplayer_authority`；仅权威端处理输入和移动
- `TCP_client/Sprite/bullet.gd` — 子弹（Area2D）。权威端驱动飞行逻辑，初始化数据从 `Bullet_Dictionary` 读取
- `TCP_client/Sprite/bullet_manager.gd` — 弹幕管理器，客户端预测生成子弹 + 服务器验证后校正
- `TCP_client/Sprite/preview.gd` — 生成位置预览体（Sprite2D），生成角色前跟随鼠标定位

### MultiplayerSpawner 机制

两个 `MultiplayerSpawner` 节点配置了 `spawn_path`：
- `MultiplayerSpawner` → `Example_Area`（玩家生成路径）
- `MultiplayerSpawner2` → `BulletManager`（子弹生成路径）

`_spawnable_scenes` 限制了可生成的场景类型。

### 网络权限模式

所有网络节点在 `_enter_tree()` 中通过 `set_multiplayer_authority(name.to_int())` 设置权限——**节点名就是客户端 ID 的数字字符串**。移动/射击逻辑均以 `is_multiplayer_authority()` 守卫，确保只有拥有者驱动。

### 输入映射（仅客户端）

客户端通过 Input Map 定义了：
- `move_left/right/up/down` — WASD + 方向键控制移动
- `Click_Mouse_Left` — 鼠标左键射击

### 共享资源

`Server_Theme.tres` 是客户端和服务器共用的 Godot 主题资源，两份副本内容相同。

## 开发注意事项

- 服务器和客户端是**两个独立 Godot 工程**，需分别用 Godot 编辑器打开。修改共享资源（如主题）时需手动同步两份副本。
- 默认连接地址 `127.0.0.1`，如需局域网联机测试，需将地址改为服务器所在 IP。
- `ENetMultiplayerPeer` 的高层 API 封装了底层 ENet 库（基于 UDP），但在 Godot 中使用方式与 TCP 概念一致。
- 客户端 `main` 场景根节点是 `Node`（非 CanvasLayer），因此有独立的 `Camera2D` 节点。
- 子弹使用 `randi()` 生成随机 ID，存在极小概率的 ID 碰撞，正式项目应改用递增序列或 UUID。
