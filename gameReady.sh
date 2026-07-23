#!/usr/bin/env bash

source install/setup.bash

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"
export ROS_AUTOMATIC_DISCOVERY_RANGE="${ROS_AUTOMATIC_DISCOVERY_RANGE:-SUBNET}"

mode="${1:-gpu}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$mode" in
    arena)
        render_mode="${1:-gpu}"
        if [[ $# -gt 0 ]]; then
            shift
        fi
        case "$render_mode" in
            gpu)
                render_engine="ogre2"
                ;;
            cpu)
                render_engine="ogre"
                ;;
            *)
                echo "用法: source gameReady.sh arena [gpu|cpu]"
                return 2 2>/dev/null || exit 2
                ;;
        esac
        ros2 launch match_bringup arena.launch.py \
            render_engine:="$render_engine" "$@"
        ;;
    cyan|magenta)
        ros2 launch match_bringup team.launch.py side:="$mode" "$@"
        ;;
    gpu)
        ros2 launch nubot_gazebo load_world_gpu.launch.py "$@"
        ;;
    cpu)
        ros2 launch nubot_gazebo load_world_cpu.launch.py "$@"
        ;;
    *)
        echo "用法: source gameReady.sh [arena [gpu|cpu]|cyan|magenta|gpu|cpu]"
        echo "  arena: 三机模式仿真主机"
        echo "  cyan: 三机模式 cyan 队伍端"
        echo "  magenta: 三机模式 magenta 队伍端"
        echo "  gpu: 默认，使用 Ogre2"
        echo "  cpu: GPU 渲染失败时使用 Ogre 1.x 兼容模式"
        return 2 2>/dev/null || exit 2
        ;;
esac
