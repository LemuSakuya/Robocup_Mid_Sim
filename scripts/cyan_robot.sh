#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "启动 B/cyan 队伍端：nubot1..5，物理进攻方向 +X"
exec "${script_dir}/run_match.sh" cyan "$@"
