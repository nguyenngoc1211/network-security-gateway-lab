# WireGuard VPN

Runtime-only Curve25519 private keys identify gateway and remote peers. Public
keys may be exchanged; private keys never leave `run/wireguard/`. `AllowedIPs`
acts as both peer routing selector and cryptographic source-address policy. The
remote peer receives `10.10.30.2`; nftables permits it to the internal demo
service while direct WAN-to-LAN access remains blocked.
