#!/usr/bin/env bash

set -eo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_dir="$(cd -- "${script_dir}/.." && pwd)"
ros_setup="${ROS_SETUP:-/opt/ros/jazzy/setup.bash}"
workspace_setup="${workspace_dir}/install/setup.bash"

if [[ ! -r "${ros_setup}" || ! -r "${workspace_setup}" ]]; then
    echo "请先安装 ROS 2 Jazzy，并在 Ubuntu 中执行 colcon build" >&2
    exit 2
fi

source "${ros_setup}"
source "${workspace_setup}"

# ROS 2 and colcon setup files read optional variables that may be unset.
set -u

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"
export ROS_AUTOMATIC_DISCOVERY_RANGE="${ROS_AUTOMATIC_DISCOVERY_RANGE:-SUBNET}"

echo "等待三台电脑完成 DDS 发现..."
sleep 3

expected_nodes=(
    /auto_referee
    /dribble_status_server
    /nubot_world_model_1
    /rival_world_model_1
    /nubot_hwcontroller_1
    /rival_hwcontroller_1
    /nubot_strategy_pub
    /rival_strategy_pub
)
expected_topics=(
    /clock
    /nubot/receive_from_coach
    /rival/receive_from_coach
    /nubot1/omnivision/OmniVisionInfo
    /rival1/omnivision/OmniVisionInfo
    /nubot1/worldmodel/worldmodelinfo
    /rival1/worldmodel/worldmodelinfo
)
expected_services=(
    /DribbleId
    /world/RoboCup15MSL/set_pose
)

node_list="$(ros2 node list 2>/dev/null || true)"
topic_list="$(ros2 topic list 2>/dev/null || true)"
service_list="$(ros2 service list 2>/dev/null || true)"
failed=0

check_items() {
    local kind="$1"
    local values="$2"
    shift 2
    local item
    for item in "$@"; do
        if grep -Fxq "${item}" <<<"${values}"; then
            printf '[OK]   %-8s %s\n' "${kind}" "${item}"
        else
            printf '[MISS] %-8s %s\n' "${kind}" "${item}"
            failed=1
        fi
    done
}

check_items node "${node_list}" "${expected_nodes[@]}"
check_items topic "${topic_list}" "${expected_topics[@]}"
check_items service "${service_list}" "${expected_services[@]}"

if [[ ${failed} -ne 0 ]]; then
    echo >&2
    echo "当前 DDS 图中发现的节点:" >&2
    if [[ -n "${node_list}" ]]; then
        sort <<<"${node_list}" >&2
    else
        echo "  (无)" >&2
    fi

    if grep -Eq \
        '^/(world_model_[1-5]|nubot_hwcontroller_[1-5]|strategy_pub_node)$' \
        <<<"${node_list}"; then
        echo >&2
        echo "检测到旧版节点名：请重新 colcon build，并重启三个启动进程。" >&2
    else
        echo >&2
        echo "检查未通过。若话题/服务已为 OK，请检查缺失节点所在启动终端是否退出或报错。" >&2
    fi
    exit 1
fi

echo "基础 ROS 图检查通过。继续按 README 的方向测试核对坐标和运动。"
