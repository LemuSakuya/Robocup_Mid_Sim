# RoboCup Mid-Size Simulation

![比赛创建界面](./pics/first_ui.png)

本项目基于 ROS 2 Jazzy 和 Gazebo Harmonic，提供 RoboCup 中型组仿真所需的比赛场地、机器人模型、足球模型、Gazebo 插件、ROS/Gazebo 通信桥接及相关控制模块。

## 1. 编译工作空间

在工作空间根目录执行：

```bash
source /opt/ros/jazzy/setup.bash
colcon build
```

编译完成后加载工作空间环境：

```bash
source install/setup.bash
```

修改 launch 文件、Python 节点或配置文件后，建议重新执行编译命令。

## 2. 国赛三机分方向启动

规则中的三台电脑在当前 ROS 2 版本中的对应关系如下：

| 电脑 | 运行内容 | 启动入口 |
| --- | --- | --- |
| A：仿真主机 | Gazebo、ROS-Gazebo bridge、自动裁判、唯一的 `/DribbleId` 服务 | `arena` |
| B：cyan 队伍端 | `nubot` 世界模型、策略聚合、5 台底盘控制器 | `cyan` |
| C：magenta 队伍端 | `rival` 世界模型、策略聚合、5 台底盘控制器 | `magenta` |

三台 Ubuntu 电脑必须使用相同的 `ROS_DOMAIN_ID`，并且不能启用只允许本机通信的模式。项目脚本会设置默认值；三台电脑都需要执行一次：

```bash
cd /path/to/Robocup_Mid_Sim
export ROS_DOMAIN_ID=42
export ROS_LOCALHOST_ONLY=0
export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
```

当前场景和插件按规则固定为 5v5，启动时保持 `team_size:=5`，不要改成其他值。

在每台 Ubuntu 电脑上编译并加载工作空间：

```bash
source /opt/ros/jazzy/setup.bash
colcon build --symlink-install
source install/setup.bash
```

然后分别执行以下命令。A 电脑先启动仿真主机：

```bash
./scripts/run_match.sh arena gpu
```

如果 A 电脑的 Gazebo Ogre2 渲染失败，改用兼容模式：

```bash
./scripts/run_match.sh arena cpu
```

B 电脑启动 cyan 队伍端，C 电脑启动 magenta 队伍端：

```bash
./scripts/run_match.sh cyan
./scripts/run_match.sh magenta
```

也可以直接使用 ROS 2 命令：

```bash
ros2 launch match_bringup team.launch.py side:=cyan
ros2 launch match_bringup team.launch.py side:=magenta
```

`cyan` 使用 `nubot` 话题和物理 `+X` 进攻方向；`magenta` 使用 `rival` 话题和物理 `-X` 进攻方向。两边的策略坐标都统一为本方球门在 `-X`、对方球门在 `+X`，因此策略代码不需要为两个颜色写两套坐标逻辑。

不要在 B/C 电脑启动旧的 `gameReady.sh gpu/cpu`，它会额外启动 Gazebo 和旧的单队伍接口。三机模式只使用 `scripts/run_match.sh` 的三个入口。

当前仓库的高层策略节点尚未包含在基础框架中。队伍端启动后，会等待策略节点向以下话题发布动作和策略状态：

```text
/{team_prefix}{id}/nubotcontrol/actioncmd
/{team_prefix}{id}/nubotcontrol/strategy
```

其中 `team_prefix` 为 `nubot` 或 `rival`，`id` 为 1 到 5。没有策略节点时，控制器会保持零速度，这是故意的安全默认行为。

### 2.1 Ubuntu 端验收顺序

三台进程都启动后，在任意一台 Ubuntu 电脑执行：

```bash
./scripts/check_match.sh
```

应看到以下项目全部为 `[OK]`：`auto_referee`、`dribble_status_server`、两边的 `*_world_model_1`、`*_hwcontroller_1`、两边的 `*_strategy_pub`，以及两边的全向视觉、世界模型和 Coach 话题。如果出现 `[MISS]`，先检查三台电脑的 `ROS_DOMAIN_ID`、`ROS_LOCALHOST_ONLY`、局域网和防火墙。

再检查裁判命令没有被重复发布：

```bash
ros2 topic info /nubot/receive_from_coach -v
ros2 topic info /rival/receive_from_coach -v
```

三机模式下每个话题应只有 1 个发布者，发布者应来自 `auto_referee`。带球服务也只能有 1 个服务提供者：

```bash
ros2 service list | grep -x /DribbleId
```

检查两边视觉和世界模型确实在刷新：

```bash
timeout 5 ros2 topic hz /nubot1/omnivision/OmniVisionInfo
timeout 5 ros2 topic hz /rival1/omnivision/OmniVisionInfo
timeout 5 ros2 topic hz /nubot1/worldmodel/worldmodelinfo
timeout 5 ros2 topic hz /rival1/worldmodel/worldmodelinfo
```

方向检查看世界模型中的本方 1 号机器人：

```bash
ros2 topic echo /nubot1/worldmodel/worldmodelinfo --once
ros2 topic echo /rival1/worldmodel/worldmodelinfo --once
```

两条输出中的本地坐标都应满足：本方球门方向为负 `x`，对方球门方向为正 `x`；初始状态下本方 1 号机器人约在 `x=-1050 cm`，朝向约为 `0 rad`。物理场景中 cyan 向 `+X` 移动，magenta 向 `-X` 移动。

最后做短距离运动验收。确认没有其他高层策略同时发布命令后，在 cyan 端让 2 号机器人沿策略坐标 `+X` 运动约 1 秒：

```bash
timeout 1 ros2 topic pub --rate 20 \
  /nubot2/nubotcontrol/actioncmd nubot_interfaces/msg/ActionCmd \
  "{target: {x: -100.0, y: 100.0}, target_ori: 0.0, maxvel: 100.0, maxw: 2.0, robot_pos: {x: -200.0, y: 100.0}, robot_ori: 0.0, move_action: 12, rotate_action: 21}"
```

在 magenta 端执行对应命令：

```bash
timeout 1 ros2 topic pub --rate 20 \
  /rival2/nubotcontrol/actioncmd nubot_interfaces/msg/ActionCmd \
  "{target: {x: -100.0, y: -100.0}, target_ori: 0.0, maxvel: 100.0, maxw: 2.0, robot_pos: {x: -200.0, y: -100.0}, robot_ori: 0.0, move_action: 12, rotate_action: 21}"
```

cyan 的 Gazebo 机器人应向物理 `+X` 移动，magenta 应向物理 `-X` 移动。运动命令超时后，控制器应在约 0.25 秒内停止机器人。

## 3. 启动比赛场地

项目提供两套 Gazebo 启动文件：

| 启动模式         | Launch 文件                | 渲染器   | 使用场景                                        |
| ---------------- | -------------------------- | -------- | ----------------------------------------------- |
| GPU 模式（默认） | `load_world_gpu.launch.py` | Ogre2    | 正常支持 GPU/OpenGL 渲染的设备                  |
| CPU/兼容模式     | `load_world_cpu.launch.py` | Ogre 1.x | Ogre2 无法渲染、Shader 编译失败或 Gazebo 闪退时 |

### 3.1 默认启动：GPU 模式

正常情况下优先使用 GPU 模式：

```bash
source install/setup.bash
ros2 launch nubot_gazebo load_world_gpu.launch.py
```

也可以使用项目根目录下的简化脚本。未指定模式时，脚本默认启动 GPU 版本：

```bash
source gameReady.sh
```

以下写法与默认启动等价：

```bash
source gameReady.sh gpu
```

GPU 启动文件会显式使用 Gazebo 默认的 Ogre2 渲染后端：

```text
--render-engine ogre2
```

### 3.2 GPU 渲染失败：切换 CPU/兼容模式

如果 GPU 模式无法显示场景、Gazebo 窗口打开后立即关闭，或者终端中出现 Ogre2 Shader 编译错误，请先使用 `Ctrl+C` 结束当前进程，然后启动 CPU/兼容版本：

```bash
source install/setup.bash
ros2 launch nubot_gazebo load_world_cpu.launch.py
```

使用简化脚本时执行：

```bash
source gameReady.sh cpu
```

CPU/兼容启动文件默认使用 Ogre 1.x：

```text
--render-engine ogre
```

该模式主要用于规避部分 ARM64 虚拟机、virgl/Mesa 虚拟显卡或 OpenGL 驱动环境中的 Ogre2 兼容问题。兼容模式的渲染性能和部分视觉效果可能低于 Ogre2，但通常具有更好的环境兼容性。

## 4. Ogre2 闪退故障判断

如果 GPU 模式启动后出现以下日志，通常表示 Ogre2 无法在当前图形环境中编译 GLSL Shader：

```text
Ogre::RenderingAPIException
Fragment Program 100000000PixelShader_ps failed to compile
GLSL compile log: 100000000PixelShader_ps
```

也可能看到类似错误：

```text
error: no matching function for call to `texelFetch(...)`
terminate called after throwing an instance of 'Ogre::RenderingAPIException'
Aborted
```

此时不需要修改世界文件或机器人模型，直接切换到 CPU/兼容启动文件：

```bash
source gameReady.sh cpu
```

以下警告通常不是本次闪退的直接原因：

```text
Binding loop detected
Trying to serialize component
Trying to deserialize component
Gazebo does not support Ogre material scripts
```

## 5. 确认当前渲染器

启动时可以通过终端日志确认 Gazebo 实际加载的渲染器。

GPU/Ogre2 模式：

```text
Loading plugin [gz-rendering-ogre2]
```

CPU/兼容模式：

```text
Loading plugin [gz-rendering-ogre]
```

两个 launch 文件都通过 Gazebo 的 `--render-engine` 命令行参数指定渲染器，因此会覆盖 `~/.gz/sim/8/gui.config` 中保存的 `<engine>` 值。一般不需要手动修改用户目录下的 Gazebo GUI 配置。

## 6. 推荐启动流程

```text
开始
  |
  v
启动 GPU 模式（默认）
  |
  +-- 正常渲染 -----------------> 使用 GPU 模式
  |
  +-- 黑屏 / 闪退 / Shader 错误 -> Ctrl+C 停止
                                    |
                                    v
                              启动 CPU/兼容模式
```

对应命令：

```bash
# 第一次启动，默认使用 GPU/Ogre2
source gameReady.sh

# 如果 GPU/Ogre2 报错，改用 CPU/Ogre1 兼容模式
source gameReady.sh cpu
```

## 7. 项目目录说明

```text
src/
├── gazebo_visual/       # Gazebo 世界、模型和仿真插件
├── robot_code/          # 机器人接口、公共库和控制节点
├── auto_referee/        # 自动裁判模块
├── tools/               # 辅助工具
└── py_scripts/          # Python 辅助脚本
```

主要模块包括：

- `nubot_interfaces`：ROS 2 消息和服务接口。
- `nubot_common`：公共数据结构、几何工具和基础库。
- `nubot_description`：机器人、足球、网格和纹理资源。
- `nubot_gazebo`：Gazebo 世界启动与 ROS/Gazebo Bridge 配置。
- `nubot_plugin`：Gazebo System 插件。
- `nubot_hwcontroller`：机器人硬件控制与仿真控制适配。
- `auto_referee`：比赛控制和自动裁判模块。

## 8. 注意事项

`gazebo_visual` 包含比赛场地、足球模型、机器人模型及 Gazebo 仿真平台。比赛选手不应随意修改比赛场地和官方模型，最终比赛环境以赛事提供的版本为准。
