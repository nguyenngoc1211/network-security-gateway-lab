# Incident Response

1. Detection — Suricata identifies scan or suspicious URI.
2. Triage — validate SID, addresses, ports, severity, and affected service.
3. Investigation — correlate EVE, Nginx, nftables counters/logs, and tcpdump.
4. Containment — add the hostile source to `blocked_attackers`.
5. Remediation — correct exposed services/rules and preserve evidence.
6. Verification — repeat the bounded test and confirm it is filtered while
   legitimate LAN/VPN traffic remains available.
