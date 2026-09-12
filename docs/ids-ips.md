# IDS and IPS

IDS mode reads WAN traffic with AF_PACKET and alerts without changing delivery.
IPS mode consumes nftables queue 0 with NFQUEUE. `alert` records, `drop` blocks,
`reject` would block and notify the sender, and `pass` suppresses further rule
inspection for matching traffic. Custom SIDs 1000001–1000003 cover SYN scanning,
suspicious enumeration, and an inline-blocked HTTP URI.
