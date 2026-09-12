# Architecture

Each endpoint has its own network namespace. Three independent Linux bridges in
the `switches` namespace emulate physical Layer-2 switches. Only `gateway` is
multi-homed, so LAN/DMZ/WAN packets cannot bypass routing. The Docker bridge
`nsgw-uplink0` is a separate transport from the hostile simulated WAN.

Packet order is: ingress interface → optional DNAT → route lookup → nftables
FORWARD/Suricata NFQUEUE → optional SNAT → egress interface.
