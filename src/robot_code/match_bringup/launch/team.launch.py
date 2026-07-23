"""Launch one team computer for either side of the field."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    IncludeLaunchDescription,
    LogInfo,
    OpaqueFunction,
)
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration


SIDE_PROFILES = {
    'cyan': {
        'team_prefix': 'nubot',
        'team_info': 'false',
        'dribble_id_offset_multiplier': 0,
        'physical_attack_direction': '+X',
    },
    'magenta': {
        'team_prefix': 'rival',
        'team_info': 'true',
        'dribble_id_offset_multiplier': 1,
        'physical_attack_direction': '-X',
    },
}
SIMULATION_TEAM_SIZE = 5


def _launch_team(context):
    side = LaunchConfiguration('side').perform(context).strip().lower()
    if side not in SIDE_PROFILES:
        valid = ', '.join(sorted(SIDE_PROFILES))
        raise RuntimeError(f'side must be one of: {valid}; got {side!r}')

    team_size = int(LaunchConfiguration('team_size').perform(context))
    if team_size != SIMULATION_TEAM_SIZE:
        raise RuntimeError(
            'this world is configured for exactly 5 robots per team; '
            f'got team_size={team_size}'
        )

    profile = SIDE_PROFILES[side]
    team_prefix = profile['team_prefix']
    team_info = profile['team_info']
    dribble_id_offset = (
        profile['dribble_id_offset_multiplier'] * SIMULATION_TEAM_SIZE
    )

    world_model_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(
                get_package_share_directory('world_model'),
                'launch',
                'sim_world_model.launch.py',
            )
        ]),
        launch_arguments={
            'team_prefix': team_prefix,
            'team_size': str(team_size),
            'update_period': LaunchConfiguration('world_update_period'),
            'dribble_id_offset': str(dribble_id_offset),
            'use_sim_time': LaunchConfiguration('use_sim_time'),
        }.items(),
        condition=IfCondition(LaunchConfiguration('launch_world_model')),
    )

    simulation_interface_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(
                get_package_share_directory('simulation_interface'),
                'launch',
                'simulation_interface.launch.py',
            )
        ]),
        launch_arguments={
            'team_prefix': team_prefix,
            'team_size': str(team_size),
            'publish_rate': LaunchConfiguration('strategy_publish_rate'),
            'strategy_timeout': LaunchConfiguration('strategy_timeout'),
            'use_sim_time': LaunchConfiguration('use_sim_time'),
            'launch_strategy_aggregator': LaunchConfiguration(
                'launch_strategy_aggregator'
            ),
            'launch_coach_bridge': 'false',
            'launch_dribble_status_server': 'false',
        }.items(),
    )

    controller_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(
                get_package_share_directory('nubot_hwcontroller'),
                'launch',
                'nubot_hwcontroller.launch.py',
            )
        ]),
        launch_arguments={
            'team_prefix': team_prefix,
            'team_size': str(team_size),
            'team_info': team_info,
            'control_period': LaunchConfiguration('control_period'),
            'command_timeout': LaunchConfiguration('command_timeout'),
            'use_sim_time': LaunchConfiguration('use_sim_time'),
        }.items(),
        condition=IfCondition(LaunchConfiguration('launch_hwcontroller')),
    )

    return [
        LogInfo(
            msg=(
                f'team side={side} prefix={team_prefix} '
                f'physical_attack={profile["physical_attack_direction"]} '
                'strategy_attack=+X'
            )
        ),
        world_model_launch,
        simulation_interface_launch,
        controller_launch,
    ]


def generate_launch_description():
    """Create a side-safe team launch description."""
    return LaunchDescription([
        DeclareLaunchArgument(
            'side',
            default_value='cyan',
            description='Team side: cyan (nubot) or magenta (rival).',
        ),
        DeclareLaunchArgument('team_size', default_value='5'),
        DeclareLaunchArgument('use_sim_time', default_value='true'),
        DeclareLaunchArgument('launch_world_model', default_value='true'),
        DeclareLaunchArgument(
            'launch_strategy_aggregator', default_value='true'
        ),
        DeclareLaunchArgument('launch_hwcontroller', default_value='true'),
        DeclareLaunchArgument('world_update_period', default_value='0.015'),
        DeclareLaunchArgument('strategy_publish_rate', default_value='30.0'),
        DeclareLaunchArgument('strategy_timeout', default_value='0.10'),
        DeclareLaunchArgument('control_period', default_value='0.005'),
        DeclareLaunchArgument('command_timeout', default_value='0.25'),
        OpaqueFunction(function=_launch_team),
    ])
