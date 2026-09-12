# Network Security Gateway Lab — WSL2

An isolated, no-cost security engineering lab built with WSL2, Linux network
namespaces, veth pairs, Linux bridges, Docker networking, nftables, Suricata,
WireGuard, Nginx, tcpdump, curl, netcat, and Nmap.

## Problem

Developer-friendly container networks often hide routing and may permit direct
east-west communication. This project builds explicit LAN, DMZ, WAN, VPN, and
Internet-uplink boundaries so every routed packet crosses one security gateway.

## Architecture

```text
Internet -- Windows/WSL/Docker uplink -- eth-uplink
                                           |
attacker -- WAN -- eth-wan -- SECURITY GATEWAY -- eth-lan -- LAN client
                              nftables          \
                              Suricata           wg0 -- VPN 10.10.30.0/24
                              WireGuard
                                  |
                               eth-dmz
                                  |
                     Nginx reverse proxy / load balancer
                            /                 \
                         WEB01               WEB02
```

Layer-2 bridges live in a dedicated `switches` namespace, preventing Docker's
host firewall from filtering lab frames before they reach the gateway.

## Implementation

- LAN: `10.10.10.0/24`
- DMZ: `10.10.20.0/24`
- VPN: `10.10.30.0/24`
- Simulated WAN: `10.10.40.0/24`
- WSL/Docker uplink: `172.31.255.0/24`
- Default-drop stateful firewall and incident-response blocklist
- MASQUERADE, Internet egress, and WAN TCP/80 DNAT
- Nginx reverse proxy with round-robin WEB01/WEB02 upstreams
- Suricata AF_PACKET IDS and NFQUEUE IPS
- WireGuard encrypted remote access

## Verification

Run the phase scripts with `sudo`. The final consolidated verification is:

```bash
sudo bash scripts/run-remaining-phases.sh
```

It validates route/NAT transformations, firewall allow/drop decisions, load
balancing, IDS alerts, IPS drops, VPN-only access, log correlation, and attacker
containment.

## Attack Simulation

Only `10.10.40.10` attacks lab-owned addresses using a bounded SYN scan and two
custom HTTP paths. No public target is scanned.

## Investigation

Evidence comes from nftables counters/log prefixes, Suricata `eve.json` and
`fast.log`, Nginx access logs, and tcpdump. The runner creates
`docs/incident-timeline.md` and sanitized evidence under `logs/sanitized/`.

## Security Analysis

Routing, filtering, NAT, application proxying, detection, and prevention remain
separate controls. Return traffic is allowed through conntrack; new DMZ/WAN to
LAN connections are denied. Runtime WireGuard keys, raw logs, tokens, packet
captures, and secrets are excluded from Git.

## Current scope and limitations

The canonical topology uses Linux namespaces for maximum networking visibility;
Docker supplies the Internet uplink and an optional Compose toolbox. Suricata's
automated demo monitors the hostile WAN interface, while tcpdump verifies
LAN/DMZ paths. The reverse proxy is HTTP-only in this lab; TCP/443 firewall and
NAT behavior are transport tests, not deployed TLS. A future extension can add
TLS certificates, multi-interface Suricata capture, and a Windows WireGuard
client without changing the segmentation model.
