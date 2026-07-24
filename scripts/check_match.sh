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

echo "等待三台电脑完成 DDS 发现..."
sleep 3

expected_nodes=(
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

check_topic_publishers() {
    local topic info publisher_count
    for topic in "$@"; do
        info="$(ros2 topic info "${topic}" 2>/dev/null || true)"
        publisher_count="$(
            awk '/^Publisher count:/ { print $3; exit }' <<<"${info}"
        )"
        if [[ "${publisher_count:-0}" =~ ^[0-9]+$ ]] \
            && (( publisher_count > 0 )); then
            printf '[OK]   %-8s %s (publishers=%s)\n' \
                topic "${topic}" "${publisher_count}"
        else
            printf '[MISS] %-8s %s (无发布者)\n' topic "${topic}"
            failed=1
        fi
    done
}

check_items node "${node_list}" "${expected_nodes[@]}"
check_topic_publishers "${expected_topics[@]}"
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
        '^/(world_model_[1-5]|strategy_pub_node)$' \
        <<<"${node_list}"; then
        echo >&2
        echo "检测到旧版节点名：请重新 colcon build，并重启三个启动进程。" >&2
    fi

    if grep -Fxq '/nubot_world_model_1' <<<"${node_list}" \
        && ! grep -Fxq '/rival_world_model_1' <<<"${node_list}"; then
        echo >&2
        echo "cyan 队伍端已运行，但 magenta 队伍端未发现；请保持 ./scripts/magenta_robot.sh 运行。" >&2
    fi

    if grep -Eq '^/nubot_gazebo_(nubot|rival)[1-5]$' <<<"${node_list}" \
        && ! grep -Fxq '/auto_referee' <<<"${node_list}"; then
        echo >&2
        echo "Gazebo 已运行，但 arena 配套节点缺失；请检查 arena 启动终端是否报错或已经退出。" >&2
    fi

    discovered_roles=()
    if grep -Eq '^/(auto_referee|dribble_status_server)$' <<<"${node_list}"; then
        discovered_roles+=(arena)
    fi
    if grep -Eq '^/nubot_(world_model|hwcontroller)_1$' <<<"${node_list}"; then
        discovered_roles+=(cyan)
    fi
    if grep -Eq '^/rival_(world_model|hwcontroller)_1$' <<<"${node_list}"; then
        discovered_roles+=(magenta)
    fi
    if [[ ${#discovered_roles[@]} -eq 1 ]]; then
        echo >&2
        echo "当前只发现 ${discovered_roles[0]} 本机角色：跨主机 DDS 自动发现尚未建立。" >&2
        echo "确认三机同一子网、RMW 实现一致、UDP 组播未被防火墙阻断；VMware 网卡应使用桥接模式。" >&2
    fi

    echo >&2
    echo "检查未通过。请先处理以上缺失进程，再排查 DDS 网络。" >&2
    exit 1
fi

echo "基础 ROS 图检查通过。继续按 README 的方向测试核对坐标和运动。"
