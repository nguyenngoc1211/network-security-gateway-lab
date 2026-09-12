#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then echo "Run with sudo" >&2; exit 1; fi
project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# If IPS was just stopped, this removes any stale queue rule before the direct
# pre-VPN access test. The baseline firewall must enforce WAN-to-LAN denial.
bash "$project_dir/scripts/phase3-apply-firewall.sh" >/dev/null

if ! command -v wg &>/dev/null; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools
fi

# Recreate the remote namespace for every run so old TCP/conntrack state cannot
# make the pre-VPN denial test look like an established connection.
if ip netns list | awk '{print $1}' | grep -Fxq remote; then
  ip netns del remote
fi
ip -n switches link show vw-remote &>/dev/null && ip -n switches link delete vw-remote || true
ip netns add remote
ip -n remote link set lo up
ip link add vw-remote type veth peer name pw-remote
ip link set vw-remote netns switches
ip -n switches link set vw-remote master br-lab-wan
ip -n switches link set vw-remote up
ip link set pw-remote netns remote
ip -n remote link set pw-remote name eth0
ip -n remote address add 10.10.40.20/24 dev eth0
ip -n remote link set eth0 up
ip -n remote route add default via 10.10.40.1 dev eth0

echo "Before VPN (expected blocked):"
if ip netns exec remote curl --noproxy '*' -fsS --max-time 2 http://10.10.10.10:8080/; then
  echo "Unexpected direct WAN access to LAN" >&2
  exit 1
else
  echo "PASS: direct WAN access to LAN is blocked."
fi

key_dir="$project_dir/run/wireguard"
install -d -m 0700 "$key_dir"
umask 077
[[ -s $key_dir/gateway.key ]] || wg genkey >"$key_dir/gateway.key"
[[ -s $key_dir/remote.key ]] || wg genkey >"$key_dir/remote.key"
wg pubkey <"$key_dir/gateway.key" >"$key_dir/gateway.pub"
wg pubkey <"$key_dir/remote.key" >"$key_dir/remote.pub"
gateway_pub=$(<"$key_dir/gateway.pub")
remote_pub=$(<"$key_dir/remote.pub")

ip -n gateway link show wg0 &>/dev/null || ip -n gateway link add wg0 type wireguard
ip -n gateway address replace 10.10.30.1/24 dev wg0
ip netns exec gateway wg set wg0 private-key "$key_dir/gateway.key" listen-port 51820 \
  peer "$remote_pub" allowed-ips 10.10.30.2/32
ip -n gateway link set wg0 up

ip -n remote link show wg0 &>/dev/null || ip -n remote link add wg0 type wireguard
ip -n remote address replace 10.10.30.2/24 dev wg0
ip netns exec remote wg set wg0 private-key "$key_dir/remote.key" \
  peer "$gateway_pub" endpoint 10.10.40.1:51820 \
  allowed-ips 10.10.10.0/24,10.10.20.0/24 persistent-keepalive 15
ip -n remote link set wg0 up
ip -n remote route replace 10.10.10.0/24 dev wg0
ip -n remote route replace 10.10.20.0/24 dev wg0

bash "$project_dir/scripts/phase3-apply-firewall.sh" >/dev/null
bash "$project_dir/scripts/phase4-apply-nat.sh" >/dev/null

echo "After VPN (expected accessible):"
ip netns exec remote curl --noproxy '*' -fsS --max-time 5 http://10.10.10.10:8080/
ip netns exec remote wg show
