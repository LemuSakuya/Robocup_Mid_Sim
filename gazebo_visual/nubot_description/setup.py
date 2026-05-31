import os
from glob import glob
from setuptools import find_packages, setup

package_name = 'nubot_description'

def get_data_files():
    data_files = [
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ]

    # 安装 models/ 下所有内容（保留完整目录结构）
    models_path = 'models'
    if os.path.isdir(models_path):
        for root, dirs, files in os.walk(models_path):
            # 只收集普通文件（跳过目录本身，但保留其路径用于 install_path）
            file_paths = []
            for f in files:
                full_path = os.path.join(root, f)
                if os.path.isfile(full_path):  # 确保是文件（虽然这里大概率都是）
                    file_paths.append(full_path)

            if file_paths:
                # 安装路径 = share/<pkg>/ + 相对于源码根的路径
                install_dir = os.path.join('share', package_name, root)
                data_files.append((install_dir, file_paths))

    return data_files

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=get_data_files(),
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='lq',
    maintainer_email='1595642896@qq.com',
    description='TODO: Package description',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
        ],
    },
)
