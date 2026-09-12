#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

if ! ip netns list | awk '{print $1}' | grep -Fxq gateway; then
  echo "The gateway namespace does not exist. Complete Phase 1 first." >&2
  exit 1
fi

# This sysctl is network-namespace scoped: it turns only the lab gateway into a router.
ip netns exec gateway sysctl -w net.ipv4.ip_forward=1

echo "Gateway connected routes:"
ip -n gateway route
