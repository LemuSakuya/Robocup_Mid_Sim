#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "启动 C/magenta 队伍端：rival1..5，物理进攻方向 -X"
exec "${script_dir}/run_match.sh" magenta "$@"
