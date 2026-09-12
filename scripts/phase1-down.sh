#!/usr/bin/env bash
set -u

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

for ns in gateway client proxy web01 web02 attacker remote switches; do
  ip netns del "$ns" 2>/dev/null || true
done

for bridge in br-lab-lan br-lab-dmz br-lab-wan; do
  ip link del "$bridge" 2>/dev/null || true
done

echo "Phase 1 lab namespaces, veth pairs, and bridges removed."
