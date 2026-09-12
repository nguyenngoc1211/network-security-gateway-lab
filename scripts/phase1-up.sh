#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

namespaces=(switches gateway client proxy web01 web02 attacker)
bridges=(br-lab-lan br-lab-dmz br-lab-wan)

for ns in "${namespaces[@]}"; do
  if ip netns list | awk '{print $1}' | grep -Fxq "$ns"; then
    echo "Namespace '$ns' already exists. Run phase1-down.sh first." >&2
    exit 1
  fi
done

for bridge in "${bridges[@]}"; do
  if ip link show "$bridge" &>/dev/null; then
    echo "Interface '$bridge' already exists. Run phase1-down.sh first." >&2
    exit 1
  fi
done

cleanup_on_error() {
  local status=$?
  trap - ERR
  for ns in "${namespaces[@]}"; do
    ip netns del "$ns" 2>/dev/null || true
  done
  for bridge in "${bridges[@]}"; do
    ip link del "$bridge" 2>/dev/null || true
  done
  echo "Setup failed; partially created lab interfaces were removed." >&2
  exit "$status"
}
trap cleanup_on_error ERR

for ns in "${namespaces[@]}"; do
  ip netns add "$ns"
  ip -n "$ns" link set lo up
done

for bridge in "${bridges[@]}"; do
  ip -n switches link add "$bridge" type bridge
  ip -n switches link set "$bridge" up
done

# These bridges are pure Layer-2 switches. Keep WSL/Docker host firewall hooks
# out of their frames; Layer-3 policy belongs exclusively to gateway/nftables.
ip netns exec switches sysctl -q -w net.bridge.bridge-nf-call-iptables=0
ip netns exec switches sysctl -q -w net.bridge.bridge-nf-call-ip6tables=0
ip netns exec switches sysctl -q -w net.bridge.bridge-nf-call-arptables=0

attach_interface() {
  local ns=$1
  local host_if=$2
  local peer_if=$3
  local ns_if=$4
  local bridge=$5
  local cidr=$6

  ip link add "$host_if" type veth peer name "$peer_if"
  ip link set "$host_if" netns switches
  ip -n switches link set "$host_if" master "$bridge"
  ip -n switches link set "$host_if" up
  ip link set "$peer_if" netns "$ns"
  ip -n "$ns" link set "$peer_if" name "$ns_if"
  ip -n "$ns" address add "$cidr" dev "$ns_if"
  ip -n "$ns" link set "$ns_if" up
}

# LAN: client and the LAN-facing gateway interface share only br-lab-lan.
attach_interface gateway  vl-gw    pl-gw    eth-lan br-lab-lan 10.10.10.1/24
attach_interface client   vl-client pl-client eth0    br-lab-lan 10.10.10.10/24

# DMZ: proxy and backends share br-lab-dmz with the gateway DMZ interface.
attach_interface gateway  vd-gw    pd-gw    eth-dmz br-lab-dmz 10.10.20.1/24
attach_interface proxy    vd-proxy pd-proxy eth0    br-lab-dmz 10.10.20.10/24
attach_interface web01    vd-web01 pd-web01 eth0    br-lab-dmz 10.10.20.21/24
attach_interface web02    vd-web02 pd-web02 eth0    br-lab-dmz 10.10.20.22/24

# Simulated WAN: attacker is not placed on the real Windows/WSL network.
attach_interface gateway  vw-gw       pw-gw       eth-wan br-lab-wan 10.10.40.1/24
attach_interface attacker vw-attacker pw-attacker eth0    br-lab-wan 10.10.40.10/24

# Endpoint routes identify the lab gateway. They do not enable routing in gateway.
ip -n client route add default via 10.10.10.1 dev eth0
ip -n proxy route add default via 10.10.20.1 dev eth0
ip -n web01 route add default via 10.10.20.1 dev eth0
ip -n web02 route add default via 10.10.20.1 dev eth0
ip -n attacker route add default via 10.10.40.1 dev eth0

# Keep Phase 1 strictly non-routing, even if the WSL host itself forwards traffic.
ip netns exec gateway sysctl -q -w net.ipv4.ip_forward=0

trap - ERR
echo "Phase 1 topology created. IPv4 forwarding remains disabled in gateway."
