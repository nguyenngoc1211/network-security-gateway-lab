#!/usr/bin/env bash
set -u

echo "NAMESPACES"
ip netns list

echo
echo "HOST BRIDGES AND VETH ENDS"
ip -brief link show type bridge
ip -brief link show type veth

echo
echo "ISOLATED LAYER-2 SWITCH NAMESPACE"
ip -n switches -brief link show type bridge
ip -n switches -brief link show type veth
ip netns exec switches sysctl net.bridge.bridge-nf-call-iptables

for ns in gateway client proxy web01 web02 attacker; do
  echo
  echo "NAMESPACE: $ns"
  ip -n "$ns" -brief address
  ip -n "$ns" route
done

echo
echo "SAME-SEGMENT TESTS (must succeed)"
ip netns exec client ping -c 2 -W 1 10.10.10.1
ip netns exec proxy ping -c 2 -W 1 10.10.20.21
ip netns exec proxy ping -c 2 -W 1 10.10.20.22
ip netns exec attacker ping -c 2 -W 1 10.10.40.1

echo
echo "CROSS-SEGMENT TEST (must fail in Phase 1)"
if ip netns exec client ping -c 2 -W 1 10.10.20.10; then
  echo "UNEXPECTED: LAN reached DMZ while forwarding should be disabled." >&2
  exit 1
else
  echo "EXPECTED: client cannot reach proxy until Phase 2 enables forwarding."
fi

echo
echo "TRACEPATH BEFORE FORWARDING (destination must not be reached)"
timeout 8 ip netns exec client tracepath -n -m 3 10.10.20.10 || true
