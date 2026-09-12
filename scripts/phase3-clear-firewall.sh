#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

ip netns exec gateway nft flush ruleset
echo "Gateway nftables ruleset cleared. Routing remains enabled."
