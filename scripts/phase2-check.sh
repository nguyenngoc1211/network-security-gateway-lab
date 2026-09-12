#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

echo "FORWARDING STATE"
ip netns exec gateway sysctl net.ipv4.ip_forward

echo
echo "GATEWAY ROUTE LOOKUPS"
ip -n gateway route get 10.10.20.10
ip -n gateway route get 10.10.10.10

echo
echo "LAN TO DMZ (must succeed)"
ip netns exec client ping -c 2 -W 1 10.10.20.10

echo
echo "DMZ TO LAN (must also succeed before Phase 3 firewall)"
ip netns exec proxy ping -c 2 -W 1 10.10.10.10

echo
echo "ROUTED PATH: LAN TO DMZ"
echo "TTL=1 should expire at the gateway (10.10.10.1):"
ip netns exec client ping -c 1 -W 2 -t 1 10.10.20.10 || true
echo "TTL=2 should reach the proxy (10.10.20.10):"
ip netns exec client ping -c 1 -W 2 -t 2 10.10.20.10

echo
echo "UDP TRACEPATH (diagnostic; some WSL/kernel combinations return no UDP hop replies)"
timeout 8 ip netns exec client tracepath -n -m 3 10.10.20.10 || true
