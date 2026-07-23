#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_dir="$(cd -- "${script_dir}/.." && pwd)"
ros_setup="${ROS_SETUP:-/opt/ros/jazzy/setup.bash}"
workspace_setup="${workspace_dir}/install/setup.bash"

if [[ ! -r "${ros_setup}" ]]; then
    echo "找不到 ROS 2 Jazzy 环境: ${ros_setup}" >&2
    exit 2
fi
if [[ ! -r "${workspace_setup}" ]]; then
    echo "项目尚未编译，请先在 Ubuntu 中执行 colcon build" >&2
    exit 2
fi

source "${ros_setup}"
source "${workspace_setup}"

# ROS 2 and colcon setup files read optional variables that may be unset.
set -u

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"
export ROS_AUTOMATIC_DISCOVERY_RANGE="${ROS_AUTOMATIC_DISCOVERY_RANGE:-SUBNET}"

if [[ "${ROS_LOCALHOST_ONLY}" != "0" ]]; then
    echo "三机模式要求 ROS_LOCALHOST_ONLY=0，当前为 ${ROS_LOCALHOST_ONLY}" >&2
    exit 2
fi
if [[ "${ROS_AUTOMATIC_DISCOVERY_RANGE}" == "LOCALHOST" \
    || "${ROS_AUTOMATIC_DISCOVERY_RANGE}" == "OFF" ]]; then
    echo "三机模式要求允许子网发现，当前 ROS_AUTOMATIC_DISCOVERY_RANGE=${ROS_AUTOMATIC_DISCOVERY_RANGE}" >&2
    exit 2
fi

printf '主机=%s ROS_DOMAIN_ID=%s ROS_LOCALHOST_ONLY=%s discovery=%s RMW=%s\n' \
    "$(hostname)" "${ROS_DOMAIN_ID}" "${ROS_LOCALHOST_ONLY}" \
    "${ROS_AUTOMATIC_DISCOVERY_RANGE}" "${RMW_IMPLEMENTATION:-default}"

role="${1:-}"
case "${role}" in
    arena)
        shift
        render_mode="${1:-gpu}"
        if [[ $# -gt 0 ]]; then
            shift
        fi
        case "${render_mode}" in
            gpu) render_engine="ogre2" ;;
            cpu) render_engine="ogre" ;;
            *)
                echo "渲染模式只能是 gpu 或 cpu" >&2
                exit 2
                ;;
        esac
        exec ros2 launch match_bringup arena.launch.py \
            render_engine:="${render_engine}" "$@"
        ;;
    cyan|magenta)
        shift
        exec ros2 launch match_bringup team.launch.py \
            side:="${role}" "$@"
        ;;
    *)
        echo "用法:" >&2
        echo "  ./scripts/run_match.sh arena [gpu|cpu] [launch 参数...]" >&2
        echo "  ./scripts/run_match.sh cyan [launch 参数...]" >&2
        echo "  ./scripts/run_match.sh magenta [launch 参数...]" >&2
        exit 2
        ;;
esac
