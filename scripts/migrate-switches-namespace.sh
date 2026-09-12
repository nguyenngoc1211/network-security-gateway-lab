#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

if ! ip netns list | awk '{print $1}' | grep -Fxq switches; then
  ip netns add switches
fi
ip -n switches link set lo up

move_segment() {
  local bridge=$1
  shift
  local port

  # This makes the script safe to rerun after an already migrated segment.
  if ip -n switches link show "$bridge" &>/dev/null; then
    echo "Already migrated: $bridge"
    return 0
  fi

  if ! ip link show "$bridge" &>/dev/null; then
    echo "Missing bridge '$bridge' in both root and switches namespaces." >&2
    return 1
  fi

  for port in "$@"; do
    if ! ip link show "$port" &>/dev/null; then
      echo "Missing root-namespace port '$port' for '$bridge'." >&2
      return 1
    fi
  done

  # A WSL bridge cannot be moved between namespaces. Replace only the empty
  # switch device; the veth pairs and endpoint interfaces remain intact.
  for port in "$@"; do
    ip link set "$port" nomaster 2>/dev/null || true
  done

  ip link set "$bridge" down
  ip link delete "$bridge"
  ip -n switches link add "$bridge" type bridge
  for port in "$@"; do
    ip link set "$port" netns switches
    ip -n switches link set "$port" master "$bridge"
    ip -n switches link set "$port" up
  done
  ip -n switches link set "$bridge" up
}

move_segment br-lab-lan vl-gw vl-client
move_segment br-lab-dmz vd-gw vd-proxy vd-web01 vd-web02
move_segment br-lab-wan vw-gw vw-attacker

ip netns exec switches sysctl -q -w net.bridge.bridge-nf-call-iptables=0
ip netns exec switches sysctl -q -w net.bridge.bridge-nf-call-ip6tables=0
ip netns exec switches sysctl -q -w net.bridge.bridge-nf-call-arptables=0

echo "Lab bridges moved out of the WSL/Docker host into namespace 'switches'."
ip -n switches -brief link
ip netns exec switches sysctl net.bridge.bridge-nf-call-iptables
