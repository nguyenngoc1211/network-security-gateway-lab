#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
nat_rules="$project_dir/gateway/nat.conf"

if ! ip netns exec gateway nft list table inet security_filter &>/dev/null; then
  echo "Phase 3 filter table is missing. Complete Phase 3 first." >&2
  exit 1
fi

if ip netns exec gateway nft list table ip security_nat &>/dev/null; then
  ip netns exec gateway nft delete table ip security_nat
fi

ip netns exec gateway nft --check --file "$nat_rules"
ip netns exec gateway nft --file "$nat_rules"

echo "NAT table loaded; filter table remains active:"
ip netns exec gateway nft list table ip security_nat
