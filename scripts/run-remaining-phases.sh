#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 1
fi

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
mkdir -p logs/suricata logs/sanitized run docs screenshots diagrams

stage() { echo; echo "========== $* =========="; }

if ! ip netns list | awk '{print $1}' | grep -Fxq gateway; then
  stage "PREFLIGHT: REBUILD MISSING TOPOLOGY"
  bash scripts/phase1-up.sh
  bash scripts/phase2-enable-routing.sh
  bash scripts/phase3-apply-firewall.sh
fi

stage "PHASE 4B: INTERNET UPLINK"
bash scripts/phase4-enable-internet.sh
bash scripts/phase4-test-internet.sh

stage "PHASES 5-7: DMZ, REVERSE PROXY, LOAD BALANCER"
bash scripts/services-up.sh
echo "LAN -> DMZ HTTP:"
ip netns exec client curl --noproxy '*' -fsS http://10.10.20.10/
echo "Round robin (10 requests):"
for _ in {1..10}; do
  ip netns exec client curl --noproxy '*' -fsS http://10.10.20.10/
done
echo "DMZ -> LAN new connection (expected blocked):"
if ip netns exec proxy curl --noproxy '*' -fsS --max-time 2 http://10.10.10.10:8080/; then
  echo "FAIL: DMZ reached LAN" >&2; exit 1
else
  echo "PASS: DMZ segmentation enforced."
fi

stage "PHASE 8: SURICATA IDS"
bash scripts/phase3-apply-firewall.sh >/dev/null
bash scripts/phase4-apply-nat.sh >/dev/null
bash scripts/suricata-mode.sh ids
ip netns exec attacker nmap -n -Pn -sS -T4 --max-retries 1 -p 1-100 10.10.20.10 >/dev/null
ip netns exec attacker curl --noproxy '*' -fsS --max-time 3 \
  http://10.10.20.10/lab-suspicious >/dev/null
sleep 3
bash scripts/suricata-mode.sh stop
if ! jq -s -e 'any(.[]; .event_type == "alert" and (.alert.signature_id == 1000001 or .alert.signature_id == 1000002))' \
  logs/suricata/eve.json >/dev/null; then
  echo "Expected IDS alerts were not found." >&2; exit 1
fi
echo "PASS: IDS produced lab alerts."
jq -c 'select(.event_type == "alert") | {timestamp,src_ip,src_port,dest_ip,dest_port,proto,signature:.alert.signature,sid:.alert.signature_id,severity:.alert.severity}' \
  logs/suricata/eve.json | tail -n 10

stage "PHASE 9: SURICATA IPS"
bash scripts/suricata-mode.sh ips
if ip netns exec attacker curl --noproxy '*' -fsS --max-time 3 \
  http://10.10.20.10/blocked-by-ips >/dev/null; then
  echo "FAIL: IPS signature did not block the request." >&2
  bash scripts/suricata-mode.sh stop
  exit 1
else
  echo "PASS: IPS dropped the matching HTTP request."
fi
sleep 2
bash scripts/suricata-mode.sh stop
# Restore the non-NFQUEUE baseline before any subsequent connectivity test.
bash scripts/phase3-apply-firewall.sh >/dev/null

stage "PHASE 10: WIREGUARD VPN"
bash scripts/setup-wireguard.sh

stage "PHASES 11-12: MONITORING AND ATTACK CORRELATION"
timeout 6 ip netns exec gateway tcpdump -n -tttt -i eth-wan \
  'host 10.10.40.10 and tcp port 80' >logs/attack-tcpdump.log 2>&1 &
capture_pid=$!
ip netns exec attacker curl --noproxy '*' -fsS http://10.10.20.10/lab-suspicious >/dev/null
wait "$capture_pid" || true
cp logs/nginx-access.log logs/sanitized/nginx-access.log
jq -c 'select(.event_type == "alert")' logs/suricata/eve.json >logs/sanitized/eve-alerts.jsonl

{
  echo "# Incident Timeline"
  echo
  echo "Attacker: 10.10.40.10"
  echo
  echo "## Suricata"
  jq -r 'select(.event_type == "alert") | "- \(.timestamp) SID \(.alert.signature_id): \(.alert.signature) \(.src_ip):\(.src_port) -> \(.dest_ip):\(.dest_port)"' logs/suricata/eve.json | tail -n 12
  echo
  echo "## Nginx"
  tail -n 12 logs/nginx-access.log | sed 's/^/- /'
  echo
  echo "## Packet capture"
  sed -n '/ IP /p' logs/attack-tcpdump.log | tail -n 12 | sed 's/^/- /'
} >docs/incident-timeline.md
echo "Correlation written to docs/incident-timeline.md"

stage "PHASE 13: INCIDENT RESPONSE CONTAINMENT"
ip netns exec gateway nft add element inet security_filter blocked_attackers '{ 10.10.40.10 }'
if ip netns exec attacker curl --noproxy '*' -fsS --max-time 2 http://10.10.20.10/ >/dev/null; then
  echo "FAIL: attacker remains reachable after containment." >&2; exit 1
else
  echo "PASS: attacker 10.10.40.10 blocked by nftables set."
fi
ip netns exec gateway nft list set inet security_filter blocked_attackers

stage "PHASE 14: PORTFOLIO VERIFICATION"
chmod 0644 logs/sanitized/* docs/incident-timeline.md 2>/dev/null || true
if [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
  chown -R "$SUDO_UID:$SUDO_GID" logs run docs
fi
echo "ALL REMAINING PHASES PASSED"
echo "Review: README.md, docs/, logs/sanitized/, and nftables counters."
