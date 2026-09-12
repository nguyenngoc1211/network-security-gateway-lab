#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash $0" >&2
  exit 1
fi

test_dir=$(mktemp -d /tmp/nsgw-phase3.XXXXXX)
server_pids=()

cleanup() {
  local pid
  for pid in "${server_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf -- "$test_dir"
}
trap cleanup EXIT

start_http_server() {
  local ns=$1
  local port=$2
  ip netns exec "$ns" python3 -m http.server "$port" --bind 0.0.0.0 \
    --directory "$test_dir" >"$test_dir/${ns}-${port}.log" 2>&1 &
  server_pids+=("$!")
}

wait_for_listener() {
  local ns=$1
  local port=$2
  local attempt

  for attempt in {1..30}; do
    if ip netns exec "$ns" ss -H -lnt "sport = :$port" | grep -q .; then
      echo "Listener ready: $ns TCP/$port"
      return 0
    fi
    sleep 0.1
  done

  echo "Listener failed: $ns TCP/$port" >&2
  sed -n '1,160p' "$test_dir/${ns}-${port}.log" >&2
  return 1
}

expect_success() {
  local description=$1
  shift
  echo
  echo "TEST ALLOW: $description"
  if "$@"; then
    echo "PASS (allowed): $description"
  else
    echo "FAIL: expected traffic to be allowed: $description" >&2
    echo "Gateway forward-chain counters at failure:" >&2
    ip netns exec gateway nft list chain inet security_filter forward >&2 || true
    exit 1
  fi
}

expect_blocked() {
  local description=$1
  shift
  echo
  echo "TEST DROP: $description"
  if "$@"; then
    echo "FAIL: expected traffic to be blocked: $description" >&2
    exit 1
  else
    echo "PASS (blocked): $description"
  fi
}

# Temporary listeners test transport policy only; Nginx arrives in Phase 6.
start_http_server proxy 80
start_http_server proxy 443
start_http_server attacker 8080
start_http_server client 8080

wait_for_listener proxy 80
wait_for_listener proxy 443
wait_for_listener attacker 8080
wait_for_listener client 8080

for server_pid in "${server_pids[@]}"; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "A temporary HTTP listener failed to start:" >&2
    sed -n '1,160p' "$test_dir"/*.log >&2
    exit 1
  fi
done

# These requests stay inside their respective namespaces and verify the
# applications before any routed firewall test is interpreted.
ip netns exec proxy curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.20.10:80/
ip netns exec proxy curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.20.10:443/
ip netns exec attacker curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.40.10:8080/
ip netns exec client curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.10.10:8080/
echo "Temporary listeners passed local health checks."

expect_success "LAN can ping its gateway (INPUT rule)" \
  ip netns exec client ping -c 1 -W 1 10.10.10.1

expect_success "LAN to WAN is allowed" \
  ip netns exec client curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.40.10:8080/

expect_success "LAN to DMZ TCP/80 is allowed" \
  ip netns exec client curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.20.10:80/

expect_success "LAN to DMZ TCP/443 is allowed at Layer 4" \
  ip netns exec client nc -zvw 2 10.10.20.10 443

expect_blocked "LAN to DMZ ICMP is not in the allow policy" \
  ip netns exec client ping -c 1 -W 1 10.10.20.10

expect_blocked "LAN to DMZ TCP/22 is not in the allow policy" \
  ip netns exec client nc -zvw 2 10.10.20.10 22

expect_blocked "A new DMZ to LAN connection is denied" \
  ip netns exec proxy curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.10.10:8080/

expect_blocked "WAN to LAN is denied" \
  ip netns exec attacker curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.10.10:8080/

expect_success "WAN to DMZ TCP/80 is allowed" \
  ip netns exec attacker curl --noproxy '*' -fsS --max-time 2 -o /dev/null http://10.10.20.10:80/

expect_success "WAN to DMZ TCP/443 is allowed at Layer 4" \
  ip netns exec attacker nc -zvw 2 10.10.20.10 443

echo
echo "NMAP FROM LAN TO DMZ (80/443 open; 22 filtered)"
ip netns exec client nmap -n -Pn -T4 --max-retries 1 --host-timeout 15s \
  --reason -p 22,80,443 10.10.20.10

echo
echo "NMAP FROM WAN TO LAN (8080 filtered even though a listener exists)"
ip netns exec attacker nmap -n -Pn -T4 --max-retries 1 --host-timeout 15s \
  --reason -p 8080 10.10.10.10

echo
echo "RULESET WITH PACKET/BYTE COUNTERS AFTER TESTS"
ip netns exec gateway nft list ruleset
