# Firewall and NAT

The `inet security_filter` table uses INPUT, FORWARD, and OUTPUT base chains.
INPUT and FORWARD default to drop. Conntrack permits established/related return
traffic. New LAN-to-DMZ connections are restricted to TCP/80 and TCP/443; new
DMZ/WAN-to-LAN connections are denied.

The `ip security_nat` table performs LAN masquerading and WAN TCP/80 DNAT.
Firewall policy authorizes traffic; NAT only rewrites addressing.
