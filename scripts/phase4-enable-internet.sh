#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
docker_network=nsgw-uplink
docker_bridge=nsgw-uplink0
host_veth=nsgw-up-host
peer_veth=nsgw-up-peer

if ! docker network inspect "$docker_network" &>/dev/null; then
  docker network create \
    --driver bridge \
    --subnet 172.31.255.0/24 \
    --gateway 172.31.255.1 \
    --opt com.docker.network.bridge.name="$docker_bridge" \
    "$docker_network" >/dev/null
fi

for attempt in {1..30}; do
  ip link show "$docker_bridge" &>/dev/null && break
  sleep 0.1
done
if ! ip link show "$docker_bridge" &>/dev/null; then
  echo "Docker uplink bridge '$docker_bridge' was not created." >&2
  exit 1
fi

if ! ip -n gateway link show eth-uplink &>/dev/null; then
  if ip link show "$host_veth" &>/dev/null; then
    # A previous gateway namespace may have been deleted, leaving this root
    # veth endpoint behind. It belongs exclusively to this lab uplink.
    ip link delete "$host_veth"
  fi

  ip link add "$host_veth" type veth peer name "$peer_veth"
  ip link set "$host_veth" master "$docker_bridge"
  ip link set "$host_veth" up
  ip link set "$peer_veth" netns gateway
  ip -n gateway link set "$peer_veth" name eth-uplink
  ip -n gateway address add 172.31.255.2/24 dev eth-uplink
  ip -n gateway link set eth-uplink up
fi

ip -n gateway route replace default via 172.31.255.1 dev eth-uplink

# ip-netns bind-mounts this file only for processes executed in namespace client.
# The WSL root namespace keeps its automatically generated resolver unchanged.
install -d -m 0755 /etc/netns/client
install -m 0644 "$project_dir/client/resolv.conf" /etc/netns/client/resolv.conf

# Reload only project-owned tables so the new interface policy is reproducible.
bash "$project_dir/scripts/phase3-apply-firewall.sh" >/dev/null
bash "$project_dir/scripts/phase4-apply-nat.sh" >/dev/null

echo "Internet uplink enabled."
echo "Gateway interfaces and routes:"
ip -n gateway -brief address
ip -n gateway route
echo "Docker uplink network:"
docker network inspect "$docker_network" \
  --format 'name={{.Name}} driver={{.Driver}} subnet={{(index .IPAM.Config 0).Subnet}} gateway={{(index .IPAM.Config 0).Gateway}} bridge={{index .Options "com.docker.network.bridge.name"}}'
echo "Client namespace DNS:"
ip netns exec client cat /etc/resolv.conf
