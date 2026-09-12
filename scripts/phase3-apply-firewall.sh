#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ruleset="$project_dir/gateway/nftables.conf"

if [[ $(ip netns exec gateway sysctl -n net.ipv4.ip_forward) != 1 ]]; then
  echo "Gateway forwarding is disabled. Complete Phase 2 first." >&2
  exit 1
fi

# Delete only our filter table. Do not flush the NAT table introduced later.
if ip netns exec gateway nft list table inet security_filter &>/dev/null; then
  ip netns exec gateway nft delete table inet security_filter
fi

# Check the complete batch first; only load it when nft accepts the syntax.
ip netns exec gateway nft --check --file "$ruleset"
ip netns exec gateway nft --file "$ruleset"

echo "Firewall loaded in the gateway namespace:"
ip netns exec gateway nft list ruleset
