#!/usr/bin/env bash
set -u
project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for name in nginx-launcher nginx web01 web02 client; do
  pid_file="$project_dir/run/$name.pid"
  if [[ -f $pid_file ]]; then
    pid=$(<"$pid_file")
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
done
rm -f "$project_dir/run/nginx.pid"
echo "Lab application processes stopped."
