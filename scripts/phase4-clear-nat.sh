#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

if ip netns exec gateway nft list table ip security_nat &>/dev/null; then
  ip netns exec gateway nft delete table ip security_nat
fi
echo "NAT table removed. Phase 3 filter table was not changed."
