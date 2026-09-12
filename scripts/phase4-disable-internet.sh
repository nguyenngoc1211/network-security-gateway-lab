#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

ip -n gateway route del default 2>/dev/null || true
ip link delete nsgw-up-host 2>/dev/null || true
docker network rm nsgw-uplink >/dev/null 2>&1 || true
rm -f /etc/netns/client/resolv.conf
rmdir /etc/netns/client 2>/dev/null || true
echo "Internet uplink removed; simulated WAN remains intact."
