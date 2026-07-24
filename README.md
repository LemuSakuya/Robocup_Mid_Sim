# RoboCup 中型组仿真

![比赛创建界面](./pics/first_ui.png)

本项目是 RoboCup 中型组 5v5 仿真框架，运行于 ROS 2 Jazzy 和 Gazebo Harmonic。项目包含比赛场地、机器人和足球模型、Gazebo 插件、ROS/Gazebo bridge、自动裁判以及机器人控制接口。

当前项目的最终运行环境是 Ubuntu。

## 1. 环境与编译

### 1.1 环境要求

- Ubuntu，推荐使用与比赛镜像一致的版本。
- ROS 2 Jazzy。
- Gazebo Harmonic。
- `ros_gz_sim`、`ros_gz_bridge` 以及项目所需的 ROS 2 消息依赖。
- 三机联调时，三台电脑必须处于同一个局域网。

### 1.2 编译工作空间

在 Ubuntu 的工作空间根目录执行：

```bash
cd /path/to/Robocup_Mid_Sim

# ROS setup 脚本可能读取未初始化变量，因此先关闭 nounset。
set +u
source /opt/ros/jazzy/setup.bash
colcon build
source install/setup.bash
```

修改 launch 文件、Python 节点、C++ 插件或消息接口后，需要重新执行 `colcon build`，并在每个运行终端重新执行 `source install/setup.bash`。

`build/`、`install/`、`log/` 应由实际运行 ROS 的 Ubuntu 环境生成。

## 2. 三机部署模型

规则第 6.2 节规定三台电脑的职责如下。

| 电脑 | 运行内容 | 启动入口 | 话题前缀 | 物理进攻方向 |
| --- | --- | --- | --- | --- |
| A：仿真主机 | Gazebo、bridge、自动裁判、唯一的 `/DribbleId` 服务 | `./scripts/run_match.sh arena` | - | - |
| B：cyan 队伍端 | 5 台世界模型、5 台底盘控制器、策略聚合器 | `./scripts/cyan_robot.sh` | `nubot` | `+X` |
| C：magenta 队伍端 | 5 台世界模型、5 台底盘控制器、策略聚合器 | `./scripts/magenta_robot.sh` | `rival` | `-X` |

`cyan` 和 `magenta` 是场地两侧的稳定身份，不应理解成固定不变的“攻方”和“守方”。比赛中的攻守状态由裁判命令和策略在运行时决定。

两队的策略坐标统一为“本方球门在 `-X`、对方球门在 `+X`”。因此策略可以使用同一套坐标逻辑，Gazebo 物理方向由队伍入口负责转换。

### 2.1 与参考 simatch 的对应关系

通过 `cyan_robot.sh`、`magenta_robot.sh` 分别启动两队的机器人代码。

当前实现把自动裁判和 CoachInfo 的统一发布放在 A 电脑，B/C 只运行本队节点。这样可以保证 `/nubot/receive_from_coach`、`/rival/receive_from_coach` 和 `/DribbleId` 各只有一个服务或发布源，避免三机模式下重复发布。

不要在 B/C 电脑运行旧的 `gameReady.sh gpu` 或 `gameReady.sh cpu`，它们会额外启动 Gazebo 和旧的单机接口。

## 3. 三机网络配置

三台电脑必须使用相同的 ROS 2 域和可跨主机发现的配置。在三台电脑的启动终端都执行：

```bash
export ROS_DOMAIN_ID=42
export ROS_LOCALHOST_ONLY=0
export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
```

如果使用不同的 ROS 2 middleware，三台电脑应统一。可以查看当前配置：

```bash
printf 'host=%s domain=%s localhost_only=%s discovery=%s rmw=%s\n' \
  "$(hostname)" "${ROS_DOMAIN_ID:-unset}" \
  "${ROS_LOCALHOST_ONLY:-unset}" \
  "${ROS_AUTOMATIC_DISCOVERY_RANGE:-unset}" \
  "${RMW_IMPLEMENTATION:-default}"
ip -br -4 addr show up
```

三台电脑的业务网卡必须处于同一子网。Parallels 或 VMware 虚拟机使用桥接网络，不要使用 NAT 或仅主机模式。WSL2 需要使用支持局域网通信的镜像网络；仿真主机优先使用原生 Ubuntu。

### 3.1 组播检查

如果每台电脑单独运行正常，但检查脚本只能发现本机节点，先做组播检查，不要先修改机器人代码。

在 A 电脑执行：

```bash
ros2 multicast receive
```

在 B、C 电脑分别执行：

```bash
ros2 multicast send
```

接收端应看到 `Hello World!`。随后交换接收端和发送端，再测试一次双向通信。

组播测试前后可以执行以下命令清除 ROS 2 CLI 的旧图缓存：

```bash
ros2 daemon stop
```

如果组播失败，检查局域网、防火墙和虚拟机网络模式：

```bash
sudo ufw status verbose
```

如果局域网允许单播但禁用了组播，可以尝试在三台电脑启动前配置静态 peer 地址：

```bash
export ROS_STATIC_PEERS='192.168.1.10;192.168.1.11;192.168.1.12'
```

将示例地址替换成三台电脑实际的业务网卡地址。

## 4. 启动比赛

开始前，三台电脑都应完成第 1 节的编译，并完成第 3 节的网络配置。建议先启动 A，确认 Gazebo 正常运行后，再启动 B 和 C。

下面两种启动方案功能相同。方案二只是对方案一的命令封装；每台电脑选择其中一种即可，不要重复启动同一个角色。

### 4.1 方案一：直接使用 `match_bringup`

使用本方案前，每个终端都要加载 ROS 2 和当前工作空间环境：

```bash
set +u
source /opt/ros/jazzy/setup.bash
source install/setup.bash
```

三台电脑分别执行：

| 电脑 | 启动命令 |
| --- | --- |
| A：GPU/Ogre2 | `ros2 launch match_bringup arena.launch.py render_engine:=ogre2` |
| A：CPU/Ogre1 兼容模式 | `ros2 launch match_bringup arena.launch.py render_engine:=ogre` |
| B：cyan | `ros2 launch match_bringup team.launch.py side:=cyan` |
| C：magenta | `ros2 launch match_bringup team.launch.py side:=magenta` |

### 4.2 方案二：使用启动脚本

脚本会自动加载 ROS 2 和当前工作空间环境，并检查三机通信所需的环境变量。

| 电脑 | 启动命令 |
| --- | --- |
| A：GPU/Ogre2 | `./scripts/run_match.sh arena gpu` |
| A：CPU/Ogre1 兼容模式 | `./scripts/run_match.sh arena cpu` |
| B：cyan | `./scripts/cyan_robot.sh` |
| C：magenta | `./scripts/magenta_robot.sh` |

其中，B 会启动 `nubot1` 到 `nubot5` 的世界模型、底盘控制器和 `/nubot_strategy_pub`；C 会启动 `rival1` 到 `rival5` 的对应节点和 `/rival_strategy_pub`。B/C 都不会启动 Gazebo。

A 电脑启动后应提供 Gazebo、`/clock`、自动裁判、ROS/Gazebo bridge、`/DribbleId` 和 set-pose 服务。

停止比赛时，在对应启动终端按 `Ctrl+C`。不要同时启动旧的单机 Gazebo 入口，否则会造成重复节点、重复服务或重复话题发布者。

## 5. 三机验收

三台进程启动并等待几秒后，在任意一台 Ubuntu 电脑执行：

```bash
./scripts/check_match.sh
```

检查脚本会验证节点、话题发布者和服务。正常情况下至少应看到以下节点：

```text
/auto_referee
/dribble_status_server
/ros_gz_bridge
/set_pose_bridge
/nubot_world_model_1
/rival_world_model_1
/nubot_hwcontroller_1
/rival_hwcontroller_1
/nubot_strategy_pub
/rival_strategy_pub
```

脚本还会确认以下话题存在真实发布者，而不是只有本地订阅者：

```text
/clock
/nubot/receive_from_coach
/rival/receive_from_coach
/nubot1/omnivision/OmniVisionInfo
/rival1/omnivision/OmniVisionInfo
/nubot1/worldmodel/worldmodelinfo
/rival1/worldmodel/worldmodelinfo
```

如果只发现 arena、cyan 或 magenta 的本机节点，优先检查 `ROS_DOMAIN_ID`、`ROS_LOCALHOST_ONLY`、虚拟机桥接网络、组播和防火墙。此时不要先重编译机器人代码。

检查 CoachInfo 只有一个发布者：

```bash
ros2 topic info /nubot/receive_from_coach -v
ros2 topic info /rival/receive_from_coach -v
```

发布者应来自 A 电脑的自动裁判。检查服务：

```bash
ros2 service list | grep -x /DribbleId
ros2 service list | grep -x /world/RoboCup15MSL/set_pose
```

检查视觉和世界模型是否持续刷新：

```bash
timeout 5 ros2 topic hz /nubot1/omnivision/OmniVisionInfo
timeout 5 ros2 topic hz /rival1/omnivision/OmniVisionInfo
timeout 5 ros2 topic hz /nubot1/worldmodel/worldmodelinfo
timeout 5 ros2 topic hz /rival1/worldmodel/worldmodelinfo
```

## 6. 方向与运动验收

查看两队 1 号机器人的世界模型：

```bash
ros2 topic echo /nubot1/worldmodel/worldmodelinfo --once
ros2 topic echo /rival1/worldmodel/worldmodelinfo --once
```

两边策略坐标都应满足：本方球门方向为负 `x`，对方球门方向为正 `x`。初始状态下本方 1 号机器人约在 `x=-1050 cm`，朝向约为 `0 rad`。

物理场景中，cyan 应向 `+X` 移动，magenta 应向 `-X` 移动。

在没有其他策略节点发布动作时，可以用下面的命令测试 cyan 2 号机器人。命令持续约 1 秒，控制器超时后应自动停止：

```bash
timeout 1 ros2 topic pub --rate 20 \
  /nubot2/nubotcontrol/actioncmd nubot_interfaces/msg/ActionCmd \
  "{target: {x: -100.0, y: 100.0}, target_ori: 0.0, maxvel: 100.0, maxw: 2.0, robot_pos: {x: -200.0, y: 100.0}, robot_ori: 0.0, move_action: 12, rotate_action: 21}"
```

magenta 2 号机器人使用对应话题：

```bash
timeout 1 ros2 topic pub --rate 20 \
  /rival2/nubotcontrol/actioncmd nubot_interfaces/msg/ActionCmd \
  "{target: {x: -100.0, y: -100.0}, target_ori: 0.0, maxvel: 100.0, maxw: 2.0, robot_pos: {x: -200.0, y: -100.0}, robot_ori: 0.0, move_action: 12, rotate_action: 21}"
```

cyan 的 Gazebo 模型应向物理 `+X` 移动，magenta 的 Gazebo 模型应向物理 `-X` 移动。

## 7. 策略节点边界

当前仓库已提供队伍端基础设施，但尚未包含完整的 ROS 2 高层策略节点。队伍入口会等待策略节点发布以下话题：

```text
/{team_prefix}{id}/nubotcontrol/actioncmd
/{team_prefix}{id}/nubotcontrol/strategy
```

其中 `team_prefix` 是 `nubot` 或 `rival`，`id` 为 1 到 5。没有策略节点时，底盘控制器保持零速度，这是安全默认行为，不代表三机启动失败。

策略节点应负责角色分配、跑位、带球、传球、射门和比赛状态响应。世界模型和策略聚合器只负责接收、汇总和发布策略数据，不会自动生成完整比赛策略。

## 8. Gazebo 渲染故障

### 8.1 GPU/Ogre2 失败

如果出现黑屏、Gazebo 窗口立即关闭或以下错误：

```text
Ogre::RenderingAPIException
Fragment Program 100000000PixelShader_ps failed to compile
GLSL compile log: 100000000PixelShader_ps
```

结束当前进程后使用兼容模式：

```bash
./scripts/run_match.sh arena cpu
```

CPU/兼容模式使用 Ogre 1.x，适合部分 ARM64 虚拟机、virgl/Mesa 虚拟显卡和 OpenGL 驱动环境。

### 8.2 确认渲染器

启动日志中应分别出现：

```text
# GPU 模式
Loading plugin [gz-rendering-ogre2]

# CPU/兼容模式
Loading plugin [gz-rendering-ogre]
```

项目通过 launch 参数指定渲染器，一般不需要修改 `~/.gz/sim/8/gui.config`。

## 9. 项目结构

```text
src/
├── gazebo_visual/
│   ├── nubot_gazebo/          # 世界、bridge 配置和场地启动文件
│   ├── nubot_description/     # 机器人、足球和资源模型
│   └── nubot_plugin/          # Gazebo 机器人插件
├── robot_code/
│   ├── nubot_interfaces/      # ROS 2 消息和服务
│   ├── world_model/            # 单机器人世界模型
│   ├── nubot_hwcontroller/     # ActionCmd 到 VelCmd 的控制器
│   ├── simulation_interface/   # 策略聚合、Coach bridge、带球服务
│   └── match_bringup/          # arena/cyan/magenta 三机启动编排包
├── auto_referee/               # 自动裁判
└── tools/                      # 辅助工具
```

常用脚本：

- `scripts/run_match.sh`：统一的 arena、cyan、magenta 入口。
- `scripts/cyan_robot.sh`：B 电脑 cyan 队伍入口。
- `scripts/magenta_robot.sh`：C 电脑 magenta 队伍入口。
- `scripts/check_match.sh`：三机 ROS 图和发布者验收。
- `gameReady.sh`：旧的单机兼容入口，不用于国赛三机启动。

## 10. 规则与参考

- 比赛规则：2025 中国机器人大赛暨 RoboCup 机器人世界杯中国赛中型组仿真规则 PDF。

比赛场地、机器人模型、足球模型和规则相关模块应以赛事提供版本为准，不要为了策略开发随意修改官方仿真环境。
