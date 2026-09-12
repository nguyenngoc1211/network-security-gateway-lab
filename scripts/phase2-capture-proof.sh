#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

if [[ $(ip netns exec gateway sysctl -n net.ipv4.ip_forward) != 1 ]]; then
  echo "Gateway forwarding is disabled. Run phase2-enable-routing.sh first." >&2
  exit 1
fi

capture_dir=$(mktemp -d /tmp/nsgw-phase2.XXXXXX)
cleanup() {
  rm -rf -- "$capture_dir"
}
trap cleanup EXIT

packet_filter='icmp and host 10.10.10.10 and host 10.10.20.10'

timeout 8 ip netns exec gateway tcpdump -e -n -vv -tttt -l -i eth-lan -c 2 "$packet_filter" \
  >"$capture_dir/eth-lan.txt" 2>&1 &
lan_capture_pid=$!

timeout 8 ip netns exec gateway tcpdump -e -n -vv -tttt -l -i eth-dmz -c 2 "$packet_filter" \
  >"$capture_dir/eth-dmz.txt" 2>&1 &
dmz_capture_pid=$!

# Give both capture processes time to attach before generating the single test flow.
sleep 1
ip netns exec client ping -c 1 -W 2 10.10.20.10

wait "$lan_capture_pid" || true
wait "$dmz_capture_pid" || true

echo
echo "PACKETS OBSERVED ON GATEWAY eth-lan"
sed -n '1,120p' "$capture_dir/eth-lan.txt"

echo
echo "THE SAME FLOW OBSERVED ON GATEWAY eth-dmz"
sed -n '1,120p' "$capture_dir/eth-dmz.txt"
