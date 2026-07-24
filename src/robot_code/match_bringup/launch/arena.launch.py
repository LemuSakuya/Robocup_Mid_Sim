"""Launch Gazebo, bridges, the referee, and the shared dribble service."""

import os

from ament_index_python.packages import (
    get_package_prefix,
    get_package_share_directory,
)
from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    IncludeLaunchDescription,
    OpaqueFunction,
    SetEnvironmentVariable,
)
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


SIMULATION_TEAM_SIZE = 5


def _validate_team_size(context):
    team_size = int(LaunchConfiguration('team_size').perform(context))
    if team_size != SIMULATION_TEAM_SIZE:
        raise RuntimeError(
            'this world is configured for exactly 5 robots per team; '
            f'got team_size={team_size}'
        )
    return []


def generate_launch_description():
    """Create the arena-computer launch description."""
    gazebo_share = get_package_share_directory('nubot_gazebo')
    description_share = get_package_share_directory('nubot_description')
    referee_share = get_package_share_directory('auto_referee')
    plugin_prefix = get_package_prefix('nubot_plugin')

    render_engine = LaunchConfiguration('render_engine')
    verbosity = LaunchConfiguration('verbosity')
    cyan_prefix = LaunchConfiguration('cyan_prefix')
    magenta_prefix = LaunchConfiguration('magenta_prefix')
    team_size = LaunchConfiguration('team_size')
    start_team = LaunchConfiguration('start_team')
    use_sim_time = LaunchConfiguration('use_sim_time')
    enforce_area_rules = LaunchConfiguration('enforce_area_rules')
    launch_auto_referee = LaunchConfiguration('launch_auto_referee')
    launch_dribble_server = LaunchConfiguration(
        'launch_dribble_status_server'
    )

    world_path = os.path.join(
        gazebo_share, 'worlds', 'robocup15MSL.sdf'
    )
    bridge_config_path = os.path.join(
        gazebo_share, 'config', 'bridge.yaml'
    )

    gz_sim = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(
                get_package_share_directory('ros_gz_sim'),
                'launch',
                'gz_sim.launch.py',
            )
        ]),
        launch_arguments={
            'gz_args': [
                world_path,
                ' -v ',
                verbosity,
                ' --render-engine ',
                render_engine,
            ],
        }.items(),
    )

    bridge = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        name='ros_gz_bridge',
        output='screen',
        parameters=[{'config_file': bridge_config_path}],
    )
    set_pose_bridge = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        name='set_pose_bridge',
        output='screen',
        arguments=[
            '/world/RoboCup15MSL/set_pose'
            '@ros_gz_interfaces/srv/SetEntityPose'
        ],
    )

    referee = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            os.path.join(
                referee_share, 'launch', 'auto_referee.launch.py'
            )
        ]),
        launch_arguments={
            'cyan_prefix': cyan_prefix,
            'magenta_prefix': magenta_prefix,
            'team_size': team_size,
            'start_team': start_team,
            'use_sim_time': use_sim_time,
            'enforce_area_rules': enforce_area_rules,
        }.items(),
        condition=IfCondition(launch_auto_referee),
    )

    dribble_status_server = Node(
        package='simulation_interface',
        executable='dribble_status_server',
        name='dribble_status_server',
        output='screen',
        parameters=[{
            'service_name': '/DribbleId',
            'status_topic': '/dribble_id',
            'use_sim_time': ParameterValue(
                use_sim_time, value_type=bool
            ),
        }],
        condition=IfCondition(launch_dribble_server),
    )

    return LaunchDescription([
        DeclareLaunchArgument('render_engine', default_value='ogre2'),
        DeclareLaunchArgument('verbosity', default_value='4'),
        DeclareLaunchArgument('cyan_prefix', default_value='nubot'),
        DeclareLaunchArgument('magenta_prefix', default_value='rival'),
        DeclareLaunchArgument('team_size', default_value='5'),
        DeclareLaunchArgument('start_team', default_value='-1'),
        DeclareLaunchArgument('use_sim_time', default_value='true'),
        DeclareLaunchArgument('enforce_area_rules', default_value='true'),
        DeclareLaunchArgument('launch_auto_referee', default_value='true'),
        DeclareLaunchArgument(
            'launch_dribble_status_server', default_value='true'
        ),
        OpaqueFunction(function=_validate_team_size),
        SetEnvironmentVariable(
            name='GZ_SIM_RESOURCE_PATH',
            value=os.path.join(description_share, 'models'),
        ),
        SetEnvironmentVariable(
            name='GZ_SIM_SYSTEM_PLUGIN_PATH',
            value=os.path.join(plugin_prefix, 'lib'),
        ),
        gz_sim,
        bridge,
        set_pose_bridge,
        dribble_status_server,
        referee,
    ])
