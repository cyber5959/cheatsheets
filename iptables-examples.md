# iptables Examples — 100 Practical Recipes

[Repository index](README.md) · [Original iptables reference](iptables.md) · [OpenVPN configurations](openvpn-configs.md)

**Find a problem, copy its command, and change the addresses, ports, interfaces, and paths.** This file is an example collection rather than a long syntax lesson. Recipes are independent unless explicitly described as a sequence. The final three entries are complete starting configurations.

## Before copying a rule

- These are Linux shell commands. `sudo iptables` changes the running IPv4 firewall; `sudo ip6tables` changes IPv6. Nothing here has been applied to your computer.
- `INPUT` means traffic **to this machine**. `OUTPUT` means traffic **created by this machine**. `FORWARD` means traffic **passing through this machine**. Choose the right path first.
- `-A` appends. It cannot override an earlier matching ACCEPT, DROP, or REJECT. Put an exception before the broader decision it must override. A built-in DROP *policy* is different from a DROP *rule*: appended rules are still before the policy.
- `-I INPUT 1` puts a rule first. Use that only when it should override existing INPUT rules. Inserting a source block first can cut off an existing administration session.
- Most allow snippets assume a default-deny policy with loopback and reply traffic already handled. Most outbound snippets assume you are building a restricted OUTPUT policy. An allow rule alone does not deny everything else.
- Reply handling is kept brief and used where a complete example needs it. This is not a separate connection-tracking tutorial.
- On a host managed by UFW, firewalld, containers, or orchestration, change policy through its manager or designated integration chain. Do not replace manager-owned tables with the standalone templates.
- Save a backup and retain console/timed rollback access before remote edits. Do not paste the entire file into a terminal.

### Values used in examples

| Example | Replace with |
|---|---|
| `eth0` | Internet/WAN interface, perhaps `ens3` or `enp1s0` |
| `eth1` | LAN interface |
| `eth2` | Guest/second-LAN interface |
| `tun0` | OpenVPN tunnel interface |
| `198.51.100.10` | Your administration source address |
| `203.0.113.10` | Your server/router's public address |
| `10.20.0.0/24` | Main LAN |
| `10.30.0.0/24` | Guest/branch LAN |
| `10.8.0.0/24` | VPN client network |
| `10.20.0.20` | Internal application server |
| `10.20.0.53` | Internal DNS server |
| `192.0.2.53` | Example external resolver, not a real resolver to use |
| `2001:db8::/32` addresses | Your actual IPv6 addresses/prefixes |

Documentation public addresses above are placeholders. Do not put hostnames into rules as a substitute for ongoing DNS-aware filtering: iptables normally resolves them when adding the rule, not for each packet.

## Find a group

- [001–010: Inspect and diagnose](#inspect-and-diagnose)
- [011–020: Add, remove, organize, and recover](#add-remove-organize-and-recover)
- [021–030: Allow inbound services](#allow-inbound-services)
- [031–040: Block, reject, and narrow access](#block-reject-and-narrow-access)
- [041–050: Control outbound traffic](#control-outbound-traffic)
- [051–060: Route between networks and VPNs](#route-between-networks-and-vpns)
- [061–070: NAT and port forwarding](#nat-and-port-forwarding)
- [071–080: Logging, rate limits, and address sets](#logging-rate-limits-and-address-sets)
- [081–090: IPv6 examples](#ipv6-examples)
- [091–100: Advanced matches and complete configurations](#advanced-matches-and-complete-configurations)

## Inspect and diagnose

- [FW001: Identify the iptables backend](#fw001-identify-the-iptables-backend)
- [FW002: List incoming rules with counters and positions](#fw002-list-incoming-rules-with-counters-and-positions)
- [FW003: Show the exact rule syntax](#fw003-show-the-exact-rule-syntax)
- [FW004: Inspect NAT rules instead of the filter table](#fw004-inspect-nat-rules-instead-of-the-filter-table)
- [FW005: Export every IPv4 table to a private backup](#fw005-export-every-ipv4-table-to-a-private-backup)
- [FW006: Check whether a specific rule exists](#fw006-check-whether-a-specific-rule-exists)
- [FW007: Watch forwarding counters during a connectivity test](#fw007-watch-forwarding-counters-during-a-connectivity-test)
- [FW008: Verify that the application is actually listening](#fw008-verify-that-the-application-is-actually-listening)
- [FW009: Inspect the route to your test destination](#fw009-inspect-the-route-to-your-test-destination)
- [FW010: Check a rule extension's installed options](#fw010-check-a-rule-extensions-installed-options)

### FW001: Identify the iptables backend

```sh
iptables --version
ip6tables --version
```

**What it does:** Shows the installed version and often `nf_tables` or `legacy`. Different backends can hold different rules; inspecting one does not necessarily show the other. **Change:** Nothing. If both tools/backends exist, determine which your firewall manager actually uses before editing.

### FW002: List incoming rules with counters and positions

```sh
sudo iptables -L INPUT -n -v -x --line-numbers
```

**What it does:** Shows packet/byte counts, exact numbers, and current rule positions without DNS lookups. **Change:** INPUT to OUTPUT or FORWARD for another path. Run before and after one test to see which counters increased.

### FW003: Show the exact rule syntax

```sh
sudo iptables -S INPUT
```

**What it does:** Prints policy and rules in command-like form, useful when copying an exact specification for deletion. **Change:** The chain name, or omit it for all chains in the filter table. This does not list every table.

### FW004: Inspect NAT rules instead of the filter table

```sh
sudo iptables -t nat -L -n -v --line-numbers
sudo iptables -t nat -S
```

**What it does:** Shows address/port translation rules and their counters. **Change:** `nat` to `mangle` when investigating packet marking. NAT counters are not total traffic-volume counters for an existing flow.

### FW005: Export every IPv4 table to a private backup

```sh
sudo iptables-save -c > before-v4.rules
```

**What it does:** Saves the current IPv4 rules and counters to a file. **Change:** Output path/name. Shell redirection writes as your current user, so choose a location you can write. Keep real firewall snapshots private.

### FW006: Check whether a specific rule exists

```sh
sudo iptables -C INPUT -i eth0 -p udp --dport 1194 -j ACCEPT
```

**What it does:** Checks an exact rule without adding it. Exit 0 means found; nonzero may mean missing or an error, so read stderr. **Change:** The full specification, including interface/port. It does not answer whether a different rule already permits that traffic.

### FW007: Watch forwarding counters during a connectivity test

```sh
sudo watch -n 2 'iptables -L FORWARD -n -v -x --line-numbers'
```

**What it does:** Refreshes routed-traffic counters every two seconds; stop with Ctrl-C. **Change:** Interval or chain. Requires `watch`. Increasing request counters with no reply counters often suggests a return-path problem, but verify with captures.

### FW008: Verify that the application is actually listening

```sh
sudo ss -lntup
```

**What it does:** Lists listening TCP/UDP sockets and processes. **Change:** Nothing, or add a suitable `ss` filter. A firewall ACCEPT cannot make a service listen, and a listener bound to `127.0.0.1` is not an external listener.

### FW009: Inspect the route to your test destination

```sh
ip route get 10.20.0.20
```

**What it does:** Reports the route the local host would choose without sending traffic. **Change:** Destination address. If the actual outgoing interface is `ens3`, an `-o eth0` rule will not match just because that was the example interface.

### FW010: Check a rule extension's installed options

```sh
sudo iptables -m hashlimit -h
```

**What it does:** Shows local help for the hashlimit match. **Change:** `hashlimit` to `multiport`, `iprange`, `owner`, or another installed match. For a target use, for example, `sudo iptables -j LOG -h`. Syntax help does not guarantee kernel/backend support when applying a rule.

## Add, remove, organize, and recover

- [FW011: Append a labeled HTTPS allowance](#fw011-append-a-labeled-https-allowance)
- [FW012: Insert a rule before an existing terminal deny](#fw012-insert-a-rule-before-an-existing-terminal-deny)
- [FW013: Delete a rule by exact specification](#fw013-delete-a-rule-by-exact-specification)
- [FW014: Delete a numbered rule after checking its current position](#fw014-delete-a-numbered-rule-after-checking-its-current-position)
- [FW015: Replace one rule in place](#fw015-replace-one-rule-in-place)
- [FW016: Build a small custom chain for one service](#fw016-build-a-small-custom-chain-for-one-service)
- [FW017: Remove a custom chain without flushing unrelated rules](#fw017-remove-a-custom-chain-without-flushing-unrelated-rules)
- [FW018: Test a saved candidate without committing it](#fw018-test-a-saved-candidate-without-committing-it)
- [FW019: Apply a candidate with timed rollback](#fw019-apply-a-candidate-with-timed-rollback)
- [FW020: Restore the saved IPv4 policy from a console](#fw020-restore-the-saved-ipv4-policy-from-a-console)

### FW011: Append a labeled HTTPS allowance

```sh
sudo iptables -A INPUT -p tcp --dport 443 \
  -m comment --comment 'web HTTPS ingress' -j ACCEPT
```

**What it does:** Permits incoming TCP 443 if evaluation reaches this rule. **Change:** Port and comment. **Placement:** Before a terminal deny. An existing earlier deny still wins; an earlier broad accept may make this rule's counter stay at zero.

### FW012: Insert a rule before an existing terminal deny

```sh
sudo iptables -L INPUT -n --line-numbers
# Only after verifying that position 5 is the intended insertion point:
sudo iptables -I INPUT 5 -s 198.51.100.10/32 -p tcp --dport 22 -j ACCEPT
```

**What it does:** Inserts before the current rule 5 and shifts later positions. **Change:** Position, administration address, and SSH port. The listing is a review step; do not assume position 5 fits your firewall.

### FW013: Delete a rule by exact specification

```sh
sudo iptables -D INPUT -p tcp --dport 443 \
  -m comment --comment 'web HTTPS ingress' -j ACCEPT
```

**What it does:** Removes the rule created by FW011. **Change:** All arguments to match the actual rule. Include its comment if present. If duplicate rules exist, verify which copy was removed and whether another still allows the traffic.

### FW014: Delete a numbered rule after checking its current position

```sh
sudo iptables -L INPUT -n --line-numbers
# Example position only; replace after inspecting the listing:
sudo iptables -D INPUT 7
```

**What it does:** Deletes the current seventh rule. **Change:** Chain and verified position. Every later rule is renumbered afterward; do not delete several ascending positions from an old list.

### FW015: Replace one rule in place

```sh
sudo iptables -R INPUT 5 -s 198.51.100.25/32 -p tcp --dport 22 \
  -m comment --comment 'new SSH administration source' -j ACCEPT
```

**What it does:** Replaces the entire rule at position 5. **Change:** Verified position and new complete rule. Unlike editing a label, this removes any old matches you do not restate. Changing a remote administration source needs a working recovery path.

### FW016: Build a small custom chain for one service

```sh
sudo iptables -N ADMIN_SSH
sudo iptables -A ADMIN_SSH -s 198.51.100.10/32 -j ACCEPT
sudo iptables -A ADMIN_SSH -j REJECT --reject-with tcp-reset
sudo iptables -I INPUT 1 -p tcp --dport 22 -j ADMIN_SSH
```

**What it does:** Creates a chain, permits one source, rejects other SSH sources, then attaches it to incoming TCP 22. **Change:** Chain name, source, port. The chain must not already exist. Because the jump is first, it can terminate SSH access from other existing sources immediately; deploy with console access.

### FW017: Remove a custom chain without flushing unrelated rules

```sh
sudo iptables -D INPUT -p tcp --dport 22 -j ADMIN_SSH
sudo iptables -F ADMIN_SSH
sudo iptables -X ADMIN_SSH
```

**What it does:** Undoes FW016's jump, clears only its custom chain, then deletes it. **Change:** Exact jump and chain. The effective policy after removal is whatever the surrounding INPUT rules say; removing a restriction can broaden access. Other references must be removed before `-X` succeeds.

### FW018: Test a saved candidate without committing it

```sh
sudo iptables-restore --test < candidate-v4.rules
```

**What it does:** Parses/builds a candidate without installing it. **Change:** Filename. This does not test network reachability or ensure your address is allowed. A valid file can still lock you out.

### FW019: Apply a candidate with timed rollback

```sh
sudo iptables-apply -t 60 candidate-v4.rules
```

**What it does:** On systems providing `iptables-apply`, installs a candidate and rolls back unless confirmed. **Change:** Timeout/path. Verify a fresh administration connection before confirming. A candidate replaces the tables it contains; use only where you own those tables.

### FW020: Restore the saved IPv4 policy from a console

```sh
sudo iptables-restore < before-v4.rules
```

**What it does:** Loads the saved policy, replacing the included tables. **Change:** Backup path. It does not restore routes, sysctls, ipsets, or service configs. Saved counters need an appropriate counter-restore option if retaining them matters.

## Allow inbound services

- [FW021: Allow SSH from one administration machine](#fw021-allow-ssh-from-one-administration-machine)
- [FW022: Allow SSH from a VPN subnet on its tunnel interface](#fw022-allow-ssh-from-a-vpn-subnet-on-its-tunnel-interface)
- [FW023: Allow HTTP and HTTPS together](#fw023-allow-http-and-https-together)
- [FW024: Allow HTTP/3 over QUIC](#fw024-allow-http3-over-quic)
- [FW025: Allow an OpenVPN UDP listener](#fw025-allow-an-openvpn-udp-listener)
- [FW026: Allow a WireGuard UDP listener](#fw026-allow-a-wireguard-udp-listener)
- [FW027: Allow LAN clients to query this DNS server](#fw027-allow-lan-clients-to-query-this-dns-server)
- [FW028: Allow a PostgreSQL server only from the application subnet](#fw028-allow-a-postgresql-server-only-from-the-application-subnet)
- [FW029: Allow SMB file sharing from a LAN](#fw029-allow-smb-file-sharing-from-a-lan)
- [FW030: Allow a configured passive FTP data range](#fw030-allow-a-configured-passive-ftp-data-range)

### FW021: Allow SSH from one administration machine

```sh
sudo iptables -A INPUT -s 198.51.100.10/32 -p tcp --dport 22 -j ACCEPT
```

**What it does:** Allows that source to reach this host's SSH port. **Change:** Source and port. **Placement:** Before the final deny; remove broader SSH allowances if this is meant to be exclusive. On a shared NAT, multiple users can have the same public source address.

### FW022: Allow SSH from a VPN subnet on its tunnel interface

```sh
sudo iptables -A INPUT -i tun0 -s 10.8.0.0/24 -p tcp --dport 22 -j ACCEPT
```

**What it does:** Requires both the VPN interface and source network. **Change:** Interface, subnet, SSH port. It does not disable a separate existing public SSH allowance.

### FW023: Allow HTTP and HTTPS together

```sh
sudo iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
```

**What it does:** Allows two TCP destination ports in one rule. **Change:** Comma-separated list. Only open ports your web server actually uses. HTTP/3 is UDP and is not included by this TCP rule.

### FW024: Allow HTTP/3 over QUIC

```sh
sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT
```

**What it does:** Permits UDP 443 for a server configured to serve QUIC/HTTP/3. **Change:** Port if deliberately nonstandard. It does not enable HTTP/3 in the application and does not replace TCP HTTPS for clients using TCP.

### FW025: Allow an OpenVPN UDP listener

```sh
sudo iptables -A INPUT -i eth0 -p udp --dport 1194 -j ACCEPT
```

**What it does:** Permits encrypted VPN transport to the server. **Change:** WAN interface, port, protocol to match OpenVPN. Tunnel-to-LAN traffic is a separate FORWARD problem; this rule alone does not permit it.

### FW026: Allow a WireGuard UDP listener

```sh
sudo iptables -A INPUT -i eth0 -p udp --dport 51820 -j ACCEPT
```

**What it does:** Opens the example outer UDP port for a configured WireGuard interface. **Change:** Actual ListenPort and WAN interface. Peer keys, AllowedIPs, routing, and inner-interface firewall policy remain separate configuration.

### FW027: Allow LAN clients to query this DNS server

```sh
sudo iptables -A INPUT -i eth1 -s 10.20.0.0/24 -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -i eth1 -s 10.20.0.0/24 -p tcp --dport 53 -j ACCEPT
```

**What it does:** Allows DNS over both UDP and TCP from the selected LAN. **Change:** Interface/network. Keep resolver recursion policy restricted in the DNS application too; a firewall allowance is not application authorization.

### FW028: Allow a PostgreSQL server only from the application subnet

```sh
sudo iptables -A INPUT -s 10.20.10.0/24 -p tcp --dport 5432 -j ACCEPT
```

**What it does:** Admits TCP traffic from the application network to the database port. **Change:** Source network and configured port. Database bind addresses, TLS, authentication, and access policy must also permit the intended clients.

### FW029: Allow SMB file sharing from a LAN

```sh
sudo iptables -A INPUT -i eth1 -s 10.20.0.0/24 -p tcp --dport 445 -j ACCEPT
```

**What it does:** Allows direct SMB over TCP 445 from the selected LAN. **Change:** Interface/subnet. This does not open legacy NetBIOS discovery or other Windows services; add only those actually needed and avoid a broad public SMB allowance.

### FW030: Allow a configured passive FTP data range

```sh
sudo iptables -A INPUT -s 10.20.0.0/24 -p tcp --dport 21 -j ACCEPT
sudo iptables -A INPUT -s 10.20.0.0/24 -p tcp --dport 50000:50100 -j ACCEPT
```

**What it does:** Allows a control connection and a fixed passive data-port range. **Change:** Trusted client network and the exact passive range configured in your server. FTPS can use the same explicitly configured range; SFTP is a different protocol normally using SSH. NAT deployments also need the FTP server to advertise the correct reachable address.

## Block, reject, and narrow access

- [FW031: Block a single incoming source immediately](#fw031-block-a-single-incoming-source-immediately)
- [FW032: Block a source subnet from reaching the router's LAN](#fw032-block-a-source-subnet-from-reaching-the-routers-lan)
- [FW033: Block a contiguous source-address range](#fw033-block-a-contiguous-source-address-range)
- [FW034: Reject TCP access to an unwanted service quickly](#fw034-reject-tcp-access-to-an-unwanted-service-quickly)
- [FW035: Reject an unwanted UDP service with an ICMP error](#fw035-reject-an-unwanted-udp-service-with-an-icmp-error)
- [FW036: Block an exposed development port on the WAN only](#fw036-block-an-exposed-development-port-on-the-wan-only)
- [FW037: Drop impossible local-LAN source addresses arriving from the WAN](#fw037-drop-impossible-local-lan-source-addresses-arriving-from-the-wan)
- [FW038: Permit a source range to one service and deny the rest](#fw038-permit-a-source-range-to-one-service-and-deny-the-rest)
- [FW039: Match a directly attached device's source MAC and IP](#fw039-match-a-directly-attached-devices-source-mac-and-ip)
- [FW040: Block ping requests without blocking all ICMP](#fw040-block-ping-requests-without-blocking-all-icmp)

### FW031: Block a single incoming source immediately

```sh
sudo iptables -I INPUT 1 -s 192.0.2.66/32 -j DROP
```

**What it does:** Drops all IPv4 traffic from that source to this host before ordinary INPUT allowances. **Change:** Address after verifying the intended source. It affects existing traffic too when it passes this chain; do not accidentally select your administration address. It does not block routed traffic or IPv6.

### FW032: Block a source subnet from reaching the router's LAN

```sh
sudo iptables -I FORWARD 1 -s 192.0.2.0/24 -d 10.20.0.0/24 -j DROP
```

**What it does:** Rejects routed traffic by source/destination networks using a silent drop. **Change:** Both subnets. It does not affect traffic addressed to the router itself, which uses INPUT. Wide prefixes can include unrelated hosts.

### FW033: Block a contiguous source-address range

```sh
sudo iptables -I INPUT 1 -m iprange --src-range 192.0.2.100-192.0.2.120 -j DROP
```

**What it does:** Drops inclusive source addresses .100 through .120 without listing each one. **Change:** Start/end addresses. Requires `iprange` support. For a natural subnet, `-s NETWORK/PREFIX` is usually easier to read.

### FW034: Reject TCP access to an unwanted service quickly

```sh
sudo iptables -I INPUT 1 -p tcp --dport 23 -j REJECT --reject-with tcp-reset
```

**What it does:** Refuses TCP 23 with a TCP reset rather than waiting for a timeout. **Change:** TCP port. This does not stop the process listening there; it filters the packet path. `tcp-reset` is not an appropriate target option for UDP.

### FW035: Reject an unwanted UDP service with an ICMP error

```sh
sudo iptables -I INPUT 1 -p udp --dport 161 -j REJECT --reject-with icmp-port-unreachable
```

**What it does:** Rejects inbound UDP 161, commonly an SNMP listener. **Change:** Port. If monitoring legitimately uses this service, restrict by source instead of rejecting everyone. A later ACCEPT cannot override this first-position rejection.

### FW036: Block an exposed development port on the WAN only

```sh
sudo iptables -I INPUT 1 -i eth0 -p tcp --dport 3000 -j REJECT --reject-with tcp-reset
```

**What it does:** Blocks the host's TCP 3000 only when arriving on the WAN interface. **Change:** Interface/port. Localhost and another interface follow their own rules. Container-published ports may traverse FORWARD instead, so verify their actual path.

### FW037: Drop impossible local-LAN source addresses arriving from the WAN

```sh
sudo iptables -I INPUT 1 -i eth0 -s 10.20.0.0/24 -j DROP
sudo iptables -I FORWARD 1 -i eth0 -s 10.20.0.0/24 -j DROP
```

**What it does:** Drops packets claiming your directly attached LAN source network when they arrive on the wrong interface. **Change:** True WAN interface and LAN prefix. Do not apply if that interface legitimately carries these sources through a private uplink, tunnel, asymmetric route, or cloud topology.

### FW038: Permit a source range to one service and deny the rest

```sh
sudo iptables -N APP8443_SOURCES
sudo iptables -A APP8443_SOURCES -m iprange --src-range 10.20.0.100-10.20.0.120 -j ACCEPT
sudo iptables -A APP8443_SOURCES -j REJECT --reject-with tcp-reset
sudo iptables -I INPUT 1 -p tcp --dport 8443 -j APP8443_SOURCES
```

**What it does:** Enforces a range-specific rule for TCP 8443 using an attached chain. **Change:** Unused chain name, source range, port. This sequence is complete for the chosen incoming-port decision, and placing it first deliberately overrides other INPUT allowances for that port.

### FW039: Match a directly attached device's source MAC and IP

```sh
sudo iptables -A INPUT -i eth1 -s 10.20.0.50/32 -m mac \
  --mac-source 02:00:00:00:00:50 -p tcp --dport 22 -j ACCEPT
```

**What it does:** Requires the expected source IP and Ethernet source MAC for SSH arriving from the local link. **Change:** Interface/IP/MAC/port. It is not strong identity: both can be spoofed. Across a router, the source MAC is normally the next-hop router's, not the original client's.

### FW040: Block ping requests without blocking all ICMP

```sh
sudo iptables -I INPUT 1 -i eth0 -p icmp --icmp-type echo-request -j DROP
```

**What it does:** Stops WAN-originated IPv4 echo requests only. **Change:** Interface or add a source restriction. It leaves other ICMP types to the existing policy, including errors used for troubleshooting/MTU. Hiding ping replies does not make a host undiscoverable.

## Control outbound traffic

Allow recipes here belong inside a planned restricted OUTPUT policy. Do not switch OUTPUT to DROP until loopback, reply traffic, DNS, administration replies, and all required applications are accounted for. These rules operate on this machine's own traffic, not automatically on LAN/container clients.

- [FW041: Allow this host to use a selected DNS resolver](#fw041-allow-this-host-to-use-a-selected-dns-resolver)
- [FW042: Block classic DNS requests to other resolvers](#fw042-block-classic-dns-requests-to-other-resolvers)
- [FW043: Allow outbound HTTPS](#fw043-allow-outbound-https)
- [FW044: Allow this host to synchronize with a chosen time server](#fw044-allow-this-host-to-synchronize-with-a-chosen-time-server)
- [FW045: Allow SMTP submission to one mail relay](#fw045-allow-smtp-submission-to-one-mail-relay)
- [FW046: Prevent direct outgoing SMTP on port 25](#fw046-prevent-direct-outgoing-smtp-on-port-25)
- [FW047: Allow outbound SSH to one backup server](#fw047-allow-outbound-ssh-to-one-backup-server)
- [FW048: Block one destination for a specific local Unix UID](#fw048-block-one-destination-for-a-specific-local-unix-uid)
- [FW049: Allow a service UID to reach one database](#fw049-allow-a-service-uid-to-reach-one-database)
- [FW050: Send application syslog over TLS to one collector](#fw050-send-application-syslog-over-tls-to-one-collector)

### FW041: Allow this host to use a selected DNS resolver

```sh
sudo iptables -A OUTPUT -d 192.0.2.53/32 -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -d 192.0.2.53/32 -p tcp --dport 53 -j ACCEPT
```

**What it does:** Permits classic DNS to one resolver. **Change:** A real approved resolver address. Both transport protocols matter. A host using a local stub also needs loopback access and the stub's upstream traffic allowed.

### FW042: Block classic DNS requests to other resolvers

```sh
sudo iptables -I OUTPUT 1 ! -d 192.0.2.53/32 -p udp --dport 53 -j REJECT
sudo iptables -I OUTPUT 1 ! -d 192.0.2.53/32 -p tcp --dport 53 -j REJECT
```

**What it does:** Rejects port-53 requests unless the destination is the selected resolver. **Change:** Approved destination. This example permits only one resolver and would reject requests to a different local stub such as `127.0.0.53`; adapt exceptions before applying. It does not block DNS over HTTPS/TLS or IPv6.

### FW043: Allow outbound HTTPS

```sh
sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
```

**What it does:** Allows this host to initiate/use outbound TCP 443 subject to surrounding policy. **Change:** Add `-d ADDRESS/PREFIX` to narrow destinations. It permits any protocol carried on that port, not only trustworthy websites. HTTP/3 needs a separate UDP decision.

### FW044: Allow this host to synchronize with a chosen time server

```sh
sudo iptables -A OUTPUT -d 192.0.2.123/32 -p udp --dport 123 -j ACCEPT
```

**What it does:** Permits NTP requests to a fixed server. **Change:** Real time-server address. If you configure a rotating hostname/pool, a single static address rule may stop matching later. NTS-enabled clients may need additional traffic beyond this NTP rule.

### FW045: Allow SMTP submission to one mail relay

```sh
sudo iptables -A OUTPUT -d 203.0.113.25/32 -p tcp --dport 587 -j ACCEPT
```

**What it does:** Allows local applications to contact a designated submission service. **Change:** Relay and configured port; some services use 465. Authentication and TLS are mail-client/server settings, not firewall features.

### FW046: Prevent direct outgoing SMTP on port 25

```sh
sudo iptables -I OUTPUT 1 -p tcp --dport 25 -j REJECT --reject-with tcp-reset
```

**What it does:** Blocks this host's direct port-25 SMTP traffic, commonly useful when it should send only through a submission relay. **Change:** Add destination exceptions through a deliberate chain if needed. This would break a host that is intentionally an outbound mail transfer agent; it does not block SMTP on every possible port.

### FW047: Allow outbound SSH to one backup server

```sh
sudo iptables -A OUTPUT -d 203.0.113.40/32 -p tcp --dport 22 -j ACCEPT
```

**What it does:** Permits SSH/SFTP-based backup traffic to one destination. **Change:** Address/port. File permissions, SSH host-key verification, and backup credentials remain application responsibilities.

### FW048: Block one destination for a specific local Unix UID

```sh
sudo iptables -I OUTPUT 1 -m owner --uid-owner 1001 -d 203.0.113.66/32 -j REJECT
```

**What it does:** Rejects matching locally created socket traffic associated with UID 1001. **Change:** Numeric UID/destination. Owner matching is not a FORWARD filter for remote users and is not a robust sandbox against privileged processes or all kernel-generated traffic.

### FW049: Allow a service UID to reach one database

```sh
sudo iptables -A OUTPUT -m owner --uid-owner 1002 -d 10.20.0.20/32 \
  -p tcp --dport 5432 -j ACCEPT
```

**What it does:** Adds a UID-specific database exception to an otherwise restricted OUTPUT policy. **Change:** Service UID, database IP, port. It does not deny other users if broader OUTPUT rules allow them, and containers may use different UID mappings/namespaces.

### FW050: Send application syslog over TLS to one collector

```sh
sudo iptables -A OUTPUT -d 10.20.0.60/32 -p tcp --dport 6514 -j ACCEPT
```

**What it does:** Allows a local logging agent to contact the selected TLS syslog port. **Change:** Collector address/actual configured port. This only permits transport; configure TLS verification and buffering in the logging agent itself.

## Route between networks and VPNs

These recipes require correct routes and `net.ipv4.ip_forward=1` on the router. To inspect it: `sysctl net.ipv4.ip_forward`. To enable it for the current runtime on an intended router: `sudo sysctl -w net.ipv4.ip_forward=1`. Durable configuration is distribution-specific. Never assume an INPUT allowance also permits FORWARD traffic.

- [FW051: Allow LAN clients to browse through a router](#fw051-allow-lan-clients-to-browse-through-a-router)
- [FW052: Allow LAN clients to reach an external DNS resolver](#fw052-allow-lan-clients-to-reach-an-external-dns-resolver)
- [FW053: Keep a guest subnet away from the main LAN](#fw053-keep-a-guest-subnet-away-from-the-main-lan)
- [FW054: Add one guest-to-LAN exception above that deny](#fw054-add-one-guest-to-lan-exception-above-that-deny)
- [FW055: Allow one application subnet to reach a database subnet](#fw055-allow-one-application-subnet-to-reach-a-database-subnet)
- [FW056: Allow VPN clients to reach an internal HTTPS server](#fw056-allow-vpn-clients-to-reach-an-internal-https-server)
- [FW057: Allow VPN clients to query the LAN DNS server](#fw057-allow-vpn-clients-to-query-the-lan-dns-server)
- [FW058: Stop routed traffic between VPN clients](#fw058-stop-routed-traffic-between-vpn-clients)
- [FW059: Allow a site-to-site VPN subnet toward the main LAN](#fw059-allow-a-site-to-site-vpn-subnet-toward-the-main-lan)
- [FW060: Permit a VPN subnet to use the WAN for full-tunnel access](#fw060-permit-a-vpn-subnet-to-use-the-wan-for-full-tunnel-access)

### FW051: Allow LAN clients to browse through a router

```sh
sudo iptables -A FORWARD -i eth1 -o eth0 -s 10.20.0.0/24 \
  -p tcp -m multiport --dports 80,443 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -d 10.20.0.0/24 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

**What it does:** Permits LAN-originated web TCP traffic and its tracked return traffic. **Change:** Interfaces/subnet/ports. DNS is not included. Add routing or source NAT for the return path; the WAN side should not have a separate broad new-traffic allowance.

### FW052: Allow LAN clients to reach an external DNS resolver

```sh
sudo iptables -A FORWARD -i eth1 -o eth0 -s 10.20.0.0/24 -d 192.0.2.53/32 \
  -p udp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -s 10.20.0.0/24 -d 192.0.2.53/32 \
  -p tcp --dport 53 -j ACCEPT
```

**What it does:** Adds routed DNS requests to a selected resolver. **Change:** Interfaces, source network, real resolver. Assumes return handling such as FW051's return rule and working WAN routing/NAT. It does not allow DNS queries addressed to the router itself.

### FW053: Keep a guest subnet away from the main LAN

```sh
sudo iptables -I FORWARD 1 -s 10.30.0.0/24 -d 10.20.0.0/24 -j REJECT
```

**What it does:** Denies routed guest-to-main-LAN traffic before general FORWARD accepts. **Change:** Guest and protected subnets. It does not block access to the router's own services, same-subnet traffic switched without this router, or additional IPv6 paths.

### FW054: Add one guest-to-LAN exception above that deny

```sh
sudo iptables -I FORWARD 1 -s 10.30.0.0/24 -d 10.20.0.50/32 \
  -p tcp --dport 631 -j ACCEPT
```

**What it does:** Allows guests to a specific IPP printing service before FW053's deny. **Change:** Source, printer, port. Insert this after installing the broad deny so the exception ends up above it. Reply handling is also required; printer discovery and other protocols are not included.

### FW055: Allow one application subnet to reach a database subnet

```sh
sudo iptables -A FORWARD -i eth1 -o eth2 -s 10.20.10.0/24 -d 10.30.10.0/24 \
  -p tcp --dport 5432 -j ACCEPT
```

**What it does:** Adds only the routed application-to-database service path. **Change:** Interfaces, source/destination networks, database port. Requires appropriate return traffic policy. Interface names and subnets must reflect the actual routing decision.

### FW056: Allow VPN clients to reach an internal HTTPS server

```sh
sudo iptables -A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.20/32 \
  -p tcp --dport 443 -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o tun0 -s 10.20.0.20/32 -d 10.8.0.0/24 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

**What it does:** Allows requests to one LAN service and tracked return traffic from that host. **Change:** Interfaces, networks, target, port. Configure the VPN-pushed route and LAN return route. A broader related-ICMP policy may be needed for errors generated by intermediate routers rather than that host.

### FW057: Allow VPN clients to query the LAN DNS server

```sh
sudo iptables -A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.53/32 \
  -p udp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.53/32 \
  -p tcp --dport 53 -j ACCEPT
```

**What it does:** Opens both DNS transports through the VPN gateway toward a separate DNS host. **Change:** Interface/network/server. Needs return handling for this DNS host, not only the web-host return rule in FW056. If DNS runs on the VPN gateway itself, use INPUT instead.

### FW058: Stop routed traffic between VPN clients

```sh
sudo iptables -I FORWARD 1 -i tun0 -o tun0 -s 10.8.0.0/24 -d 10.8.0.0/24 -j DROP
```

**What it does:** Blocks VPN-to-VPN traffic that passes through this kernel FORWARD chain. **Change:** Tunnel/subnet. OpenVPN's internal `client-to-client` option and offload behavior can change the path, so confirm actual isolation with client tests. This does not filter traffic that bypasses the hook.

### FW059: Allow a site-to-site VPN subnet toward the main LAN

```sh
sudo iptables -A FORWARD -i tun0 -o eth1 -s 10.30.0.0/24 -d 10.20.0.0/24 -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o tun0 -s 10.20.0.0/24 -d 10.30.0.0/24 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

**What it does:** Allows branch-initiated routed traffic into the main LAN and its replies. **Change:** Actual branch/main networks and interfaces. OpenVPN `route`/`iroute`, forwarding on both gateways, and LAN return routes still need configuration. Narrow protocol/ports if full subnet access is unnecessary.

### FW060: Permit a VPN subnet to use the WAN for full-tunnel access

```sh
sudo iptables -A FORWARD -i tun0 -o eth0 -s 10.8.0.0/24 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o tun0 -d 10.8.0.0/24 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

**What it does:** Permits VPN-initiated internet traffic and replies through the gateway. **Change:** Tunnel/WAN/subnet. Add a WAN NAT rule such as FW062 unless the upstream routes the VPN network. Client redirect/DNS/IPv6 policy is separate; these rules alone are not a full VPN privacy configuration.

## NAT and port forwarding

NAT changes addresses/ports; it does not grant firewall permission. Routed examples need forwarding enabled and FORWARD rules. Translation is normally chosen when a tracked flow begins, so test with a fresh flow after edits. Do not stack every alternative below onto the same traffic.

- [FW061: Give a private LAN internet access through a changing WAN address](#fw061-give-a-private-lan-internet-access-through-a-changing-wan-address)
- [FW062: Source-NAT VPN clients to the internet](#fw062-source-nat-vpn-clients-to-the-internet)
- [FW063: Source-NAT through a fixed public address](#fw063-source-nat-through-a-fixed-public-address)
- [FW064: Forward public TCP 8443 to a LAN HTTPS server](#fw064-forward-public-tcp-8443-to-a-lan-https-server)
- [FW065: Forward an outer VPN UDP port to a different LAN machine](#fw065-forward-an-outer-vpn-udp-port-to-a-different-lan-machine)
- [FW066: Make a port forward available only to one external source](#fw066-make-a-port-forward-available-only-to-one-external-source)
- [FW067: Redirect an incoming port to another local port](#fw067-redirect-an-incoming-port-to-another-local-port)
- [FW068: Let LAN clients use the server's public address through hairpin NAT](#fw068-let-lan-clients-use-the-servers-public-address-through-hairpin-nat)
- [FW069: Exempt routed private-network traffic from a broad source-NAT rule](#fw069-exempt-routed-private-network-traffic-from-a-broad-source-nat-rule)
- [FW070: Translate this host's outgoing connection to a replacement backend](#fw070-translate-this-hosts-outgoing-connection-to-a-replacement-backend)

### FW061: Give a private LAN internet access through a changing WAN address

```sh
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE
```

**What it does:** Rewrites selected outgoing sources to the WAN interface's address. **Change:** LAN network and WAN interface. Add forwarding permissions such as FW051/FW052. MASQUERADE does not fix missing DNS settings or a wrong upstream default route.

### FW062: Source-NAT VPN clients to the internet

```sh
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
```

**What it does:** Provides a WAN return path for the example private VPN pool. **Change:** Actual VPN subnet and WAN interface. Pair with FW060 and appropriate OpenVPN client routes. This does not translate IPv6 or protect a disconnected client.

### FW063: Source-NAT through a fixed public address

```sh
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 \
  -j SNAT --to-source 203.0.113.10
```

**What it does:** Uses an explicitly chosen source address rather than the current interface address. **Change:** LAN, WAN, actual assigned/routed public address. Use this as an alternative to a matching MASQUERADE rule, not an extra rule you expect to override an earlier translation.

### FW064: Forward public TCP 8443 to a LAN HTTPS server

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -d 203.0.113.10/32 \
  -p tcp --dport 8443 -j DNAT --to-destination 10.20.0.20:443
sudo iptables -A FORWARD -i eth0 -o eth1 -d 10.20.0.20/32 \
  -p tcp --dport 443 -j ACCEPT
```

**What it does:** Changes the incoming destination then permits the translated request path. **Change:** Public IP/port, private IP/port, interfaces. The LAN host must return through this router and the policy must allow replies. FORWARD sees port 443 after DNAT, not 8443.

### FW065: Forward an outer VPN UDP port to a different LAN machine

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -d 203.0.113.10/32 \
  -p udp --dport 1194 -j DNAT --to-destination 10.20.0.10:1194
sudo iptables -A FORWARD -i eth0 -o eth1 -d 10.20.0.10/32 \
  -p udp --dport 1194 -j ACCEPT
```

**What it does:** Makes a router send outside VPN packets to a separate internal VPN server. **Change:** Addresses, interfaces, ports. The router's INPUT allowance is not the relevant service path here. Return routing/forwarding must work, and the VPN server needs its own local INPUT rule.

### FW066: Make a port forward available only to one external source

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -s 198.51.100.10/32 \
  -d 203.0.113.10/32 -p tcp --dport 2222 -j DNAT --to-destination 10.20.0.20:22
sudo iptables -A FORWARD -i eth0 -o eth1 -s 198.51.100.10/32 \
  -d 10.20.0.20/32 -p tcp --dport 22 -j ACCEPT
```

**What it does:** Restricts both the mapping and forwarded service allowance to the chosen source. **Change:** Administrator, public endpoint, backend. This is an alternative mapping; an earlier broad DNAT/ACCEPT can defeat your intended restriction. Other sources that do not match DNAT follow normal routing/INPUT policy for the original destination.

### FW067: Redirect an incoming port to another local port

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 8080 \
  -j REDIRECT --to-ports 80
```

**What it does:** Sends incoming TCP 8080 to a local port 80 listener. **Change:** Interface and ports. INPUT policy must allow the translated local destination. This is not an HTTP redirect, does not rewrite URLs, and does not affect locally generated requests that skip PREROUTING.

### FW068: Let LAN clients use the server's public address through hairpin NAT

```sh
sudo iptables -t nat -A PREROUTING -i eth1 -s 10.20.0.0/24 \
  -d 203.0.113.10/32 -p tcp --dport 443 -j DNAT --to-destination 10.20.0.20:443
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -d 10.20.0.20/32 \
  -o eth1 -p tcp --dport 443 -j SNAT --to-source 10.20.0.1
sudo iptables -A FORWARD -i eth1 -o eth1 -s 10.20.0.0/24 \
  -d 10.20.0.20/32 -p tcp --dport 443 -j ACCEPT
```

**What it does:** Loops a LAN request for the public HTTPS address back to the internal server and keeps the reply passing through the router. **Change:** Every network/address, especially `10.20.0.1`, which must be this router's LAN address. Requires reply allowances. The SNAT rule also affects other matching routed LAN-to-server HTTPS traffic; split DNS can avoid this design and preserve original client addresses.

### FW069: Exempt routed private-network traffic from a broad source-NAT rule

```sh
sudo iptables -t nat -I POSTROUTING 1 -s 10.20.0.0/24 -d 10.30.0.0/24 -j ACCEPT
```

**What it does:** Ends NAT-table processing for this path before a later broad source translation. **Change:** The two networks. ACCEPT here does not bypass filter-table restrictions. Both networks must have real return routes when you preserve original addresses.

### FW070: Translate this host's outgoing connection to a replacement backend

```sh
sudo iptables -t nat -A OUTPUT -d 203.0.113.10/32 -p tcp --dport 8443 \
  -j DNAT --to-destination 10.20.0.20:443
```

**What it does:** Changes this machine's locally generated connections targeting the old endpoint into connections to a new backend. **Change:** Old destination/port and replacement. Requires a working route, return path, and OUTPUT policy for the backend. It does not rewrite another machine's traffic, HTTP Host headers, or TLS server-name verification.

## Logging, rate limits, and address sets

- [FW071: Log a specific port before deciding whether to allow it](#fw071-log-a-specific-port-before-deciding-whether-to-allow-it)
- [FW072: Log denied traffic and then actually drop it](#fw072-log-denied-traffic-and-then-actually-drop-it)
- [FW073: Send selected packet logs to a userspace collector](#fw073-send-selected-packet-logs-to-a-userspace-collector)
- [FW074: Rate-limit incoming IPv4 ping with an explicit over-limit drop](#fw074-rate-limit-incoming-ipv4-ping-with-an-explicit-over-limit-drop)
- [FW075: Drop excessive DNS UDP query packets per source](#fw075-drop-excessive-dns-udp-query-packets-per-source)
- [FW076: Block temporary source IPs without adding a rule for each](#fw076-block-temporary-source-ips-without-adding-a-rule-for-each)
- [FW077: Remove a temporary block early](#fw077-remove-a-temporary-block-early)
- [FW078: Replace a block-list set without a partially populated interval](#fw078-replace-a-block-list-set-without-a-partially-populated-interval)
- [FW079: Mark selected voice traffic with a DSCP class](#fw079-mark-selected-voice-traffic-with-a-dscp-class)
- [FW080: Clamp TCP MSS on packets entering a tunnel](#fw080-clamp-tcp-mss-on-packets-entering-a-tunnel)

### FW071: Log a specific port before deciding whether to allow it

```sh
sudo iptables -I INPUT 1 -p tcp --dport 8443 \
  -m limit --limit 6/minute --limit-burst 10 \
  -j LOG --log-prefix 'CHECK8443: '
```

**What it does:** Emits limited kernel log messages, then continues to later rules. **Change:** Port/rate/prefix. LOG is not ACCEPT or DROP. View with `sudo journalctl -k` where available, and remove this diagnostic rule after use.

### FW072: Log denied traffic and then actually drop it

```sh
sudo iptables -N LOG_DENIED
sudo iptables -A LOG_DENIED -m limit --limit 5/minute --limit-burst 10 \
  -j LOG --log-prefix 'DENIED: '
sudo iptables -A LOG_DENIED -j DROP
sudo iptables -A INPUT -j LOG_DENIED
```

**What it does:** Creates a reusable terminal log/drop path. **Change:** Unused chain name and logging rate/prefix. **Placement:** The INPUT jump belongs after every intended allowance; otherwise it blocks them. Logging is limited, but dropping is not limited.

### FW073: Send selected packet logs to a userspace collector

```sh
sudo iptables -I INPUT 1 -p udp --dport 1194 \
  -m limit --limit 10/minute --limit-burst 20 \
  -j NFLOG --nflog-group 10 --nflog-prefix 'VPN_INPUT'
```

**What it does:** Sends matching records to NFLOG group 10 and continues evaluating policy. **Change:** Port/group/prefix/rate. A compatible userspace collector must subscribe to that group; NFLOG is not automatically a text file or a packet verdict. Limit collection and protect its contents.

### FW074: Rate-limit incoming IPv4 ping with an explicit over-limit drop

```sh
sudo iptables -N PING_RATE
sudo iptables -A PING_RATE -m limit --limit 2/second --limit-burst 5 -j ACCEPT
sudo iptables -A PING_RATE -j DROP
sudo iptables -I INPUT 1 -p icmp --icmp-type echo-request -j PING_RATE
```

**What it does:** Permits a shared burst/rate of echo requests and drops excess. **Change:** Unused chain and rate. The token bucket is shared across matching sources; this is not a per-source limit. Other ICMP types do not enter this chain.

### FW075: Drop excessive DNS UDP query packets per source

```sh
sudo iptables -I INPUT 1 -i eth1 -s 10.20.0.0/24 -p udp --dport 53 \
  -m hashlimit --hashlimit-above 50/second --hashlimit-burst 100 \
  --hashlimit-mode srcip --hashlimit-name dns_src_rate -j DROP
```

**What it does:** Drops matching source-IP packet rates above the example threshold before DNS accepts. **Change:** Interface/network/rate/name based on measured normal traffic. Lower-rate packets continue to later policy; this rule does not allow them itself. Shared-NAT users share one bucket, and application DNS rate limiting can make better protocol-aware decisions.

### FW076: Block temporary source IPs without adding a rule for each

```sh
sudo ipset create temp_block_v4 hash:ip family inet timeout 3600
sudo iptables -I INPUT 1 -m set --match-set temp_block_v4 src -j DROP
sudo ipset add temp_block_v4 192.0.2.66 timeout 600
```

**What it does:** Creates a set, references it once, and blocks one member for ten minutes. **Change:** Set/address/timeouts. Run creation/attachment once, then use `ipset add` for later members. Requires compatible ipset support; set/rule persistence must be configured separately.

### FW077: Remove a temporary block early

```sh
sudo ipset del temp_block_v4 192.0.2.66
sudo ipset list temp_block_v4
```

**What it does:** Deletes one set member and shows the remaining set. **Change:** Set/address. If the entry already expired, deletion can report that it is absent. Other firewall rules can still block the source.

### FW078: Replace a block-list set without a partially populated interval

```sh
sudo ipset create temp_block_v4_next hash:ip family inet timeout 3600
sudo ipset add temp_block_v4_next 192.0.2.70 timeout 600
sudo ipset add temp_block_v4_next 192.0.2.71 timeout 600
sudo ipset swap temp_block_v4_next temp_block_v4
sudo ipset destroy temp_block_v4_next
```

**What it does:** Builds a replacement, swaps it into the already-referenced name from FW076, then destroys the old contents now held under the temporary name. **Change:** Names and complete intended membership. Both sets must be swap-compatible; the temporary name must be unused. This replaces the whole list, so old members not included become unblocked by this set.

### FW079: Mark selected voice traffic with a DSCP class

```sh
sudo iptables -t mangle -A FORWARD -s 10.20.10.0/24 -p udp \
  --dport 10000:20000 -j DSCP --set-dscp-class EF
```

**What it does:** Sets the DSCP marking for the chosen routed UDP range. **Change:** Actual voice subnet/range and QoS class. A downstream scheduler must honor it to affect priority; this rule does not reserve bandwidth. Do not trust arbitrary unclassified traffic merely because it uses a voice-like port.

### FW080: Clamp TCP MSS on packets entering a tunnel

```sh
sudo iptables -t mangle -A FORWARD -o tun0 -p tcp \
  --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

**What it does:** Adjusts the advertised maximum segment size on matching SYN packets based on path MTU. **Change:** Actual egress tunnel. Use only for a diagnosed PMTU problem; asymmetric routes need careful analysis. This does not fix UDP packet sizing or replace proper ICMP error handling.

## IPv6 examples

IPv4 iptables rules do not protect IPv6 listeners. Examples here use `ip6tables` deliberately. Keep IPv6 neighbor discovery and essential ICMPv6 errors working. Documentation `2001:db8::` addresses must be replaced with actual deployed prefixes.

- [FW081: Inspect the IPv6 policy and counters](#fw081-inspect-the-ipv6-policy-and-counters)
- [FW082: Allow IPv6 SSH from one administration address](#fw082-allow-ipv6-ssh-from-one-administration-address)
- [FW083: Serve HTTP and HTTPS over IPv6](#fw083-serve-http-and-https-over-ipv6)
- [FW084: Open a VPN listener over an IPv6 WAN](#fw084-open-a-vpn-listener-over-an-ipv6-wan)
- [FW085: Preserve ICMPv6 on a general host](#fw085-preserve-icmpv6-on-a-general-host)
- [FW086: Preserve core IPv6 error reporting in a selective policy](#fw086-preserve-core-ipv6-error-reporting-in-a-selective-policy)
- [FW087: Permit DHCPv6 server replies to this client](#fw087-permit-dhcpv6-server-replies-to-this-client)
- [FW088: Block one IPv6 source prefix](#fw088-block-one-ipv6-source-prefix)
- [FW089: Route a global IPv6 LAN toward a WAN without IPv4-style NAT](#fw089-route-a-global-ipv6-lan-toward-a-wan-without-ipv4-style-nat)
- [FW090: Back up and validate an IPv6 candidate](#fw090-back-up-and-validate-an-ipv6-candidate)

### FW081: Inspect the IPv6 policy and counters

```sh
sudo ip6tables -S
sudo ip6tables -L -n -v --line-numbers
```

**What it does:** Shows the separate IPv6 filter policy. **Change:** Add a chain name to focus. If IPv4 looks locked down but a service remains reachable, compare IPv6 listeners and this policy before assuming the IPv4 rule failed.

### FW082: Allow IPv6 SSH from one administration address

```sh
sudo ip6tables -A INPUT -s 2001:db8:100::10/128 -p tcp --dport 22 -j ACCEPT
```

**What it does:** Adds an IPv6 SSH allowance from one address. **Change:** Real administration IPv6 address and SSH port. Privacy/temporary client addresses can rotate; choose a sustainable administration path instead of opening a huge prefix without review.

### FW083: Serve HTTP and HTTPS over IPv6

```sh
sudo ip6tables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
```

**What it does:** Allows TCP web ports in IPv6. **Change:** Required ports and optionally destination/interface. The application must also listen on IPv6 and have appropriate routing; DNS AAAA records alone do not enable the service.

### FW084: Open a VPN listener over an IPv6 WAN

```sh
sudo ip6tables -A INPUT -i eth0 -p udp --dport 1194 -j ACCEPT
```

**What it does:** Allows an IPv6 outer UDP transport to a VPN server. **Change:** WAN interface/port. Configure the application to listen compatibly. IPv6 outer transport and IPv6 payload routing inside the VPN are separate choices.

### FW085: Preserve ICMPv6 on a general host

```sh
sudo ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
```

**What it does:** Broadly permits ICMPv6, including functions IPv6 needs to operate. **Change:** Nothing unless designing a more selective, tested policy. Place before a terminal deny. This is a broad baseline, not a claim that every ICMPv6 type is required from every source.

### FW086: Preserve core IPv6 error reporting in a selective policy

```sh
sudo ip6tables -A INPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j ACCEPT
sudo ip6tables -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT
sudo ip6tables -A INPUT -p ipv6-icmp --icmpv6-type time-exceeded -j ACCEPT
sudo ip6tables -A INPUT -p ipv6-icmp --icmpv6-type parameter-problem -j ACCEPT
```

**What it does:** Permits important IPv6 error types. **Change:** Refine source/interface scope only with knowledge of the topology. These four rules are not a complete ICMPv6 policy: neighbor discovery, router discovery, multicast membership, and other roles need separate consideration. If FW085 already accepts all ICMPv6 earlier, these narrower rules add no restriction.

### FW087: Permit DHCPv6 server replies to this client

```sh
sudo ip6tables -A INPUT -i eth0 -p udp --sport 547 --dport 546 -j ACCEPT
```

**What it does:** Allows the client-side reply ports on the interface using DHCPv6. **Change:** Actual client interface; narrow server sources if your deployment supports a stable verified scope. This alone does not configure router advertisements, SLAAC, or outbound DHCPv6 requests.

### FW088: Block one IPv6 source prefix

```sh
sudo ip6tables -I INPUT 1 -s 2001:db8:bad::/48 -j DROP
```

**What it does:** Drops incoming traffic from an entire example /48 prefix. **Change:** The intended real prefix and mask after reviewing scope. A /48 is large; use /128 to target one address. Do not accidentally include management or upstream infrastructure.

### FW089: Route a global IPv6 LAN toward a WAN without IPv4-style NAT

```sh
sudo ip6tables -A FORWARD -i eth1 -o eth0 -s 2001:db8:20::/64 -j ACCEPT
sudo ip6tables -A FORWARD -i eth0 -o eth1 -d 2001:db8:20::/64 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

**What it does:** Allows LAN-initiated IPv6 traffic and tracked return traffic. **Change:** Real routed global prefix/interfaces. Requires deliberate IPv6 forwarding, upstream routing, appropriate router ICMPv6 handling, and valid client addressing. Enabling IPv6 forwarding can change router-advertisement acceptance; check your WAN configuration.

### FW090: Back up and validate an IPv6 candidate

```sh
sudo ip6tables-save > before-v6.rules
sudo ip6tables-restore --test < candidate-v6.rules
```

**What it does:** Saves current IPv6 rules and checks a prepared IPv6 rules file without applying it. **Change:** Paths. IPv4 rollback does not restore IPv6. Apply through a separately planned recoverable process, and test IPv6 management access explicitly.

## Advanced matches and complete configurations

- [FW091: Add a service allowance during specified UTC hours](#fw091-add-a-service-allowance-during-specified-utc-hours)
- [FW092: Log incoming packets whose destination is local to this host](#fw092-log-incoming-packets-whose-destination-is-local-to-this-host)
- [FW093: Assign a packet mark for another subsystem to use](#fw093-assign-a-packet-mark-for-another-subsystem-to-use)
- [FW094: Clear untrusted DSCP priority claims at a guest boundary](#fw094-clear-untrusted-dscp-priority-claims-at-a-guest-boundary)
- [FW095: Use RETURN to hand a decision back to the main chain](#fw095-use-return-to-hand-a-decision-back-to-the-main-chain)
- [FW096: Maintain several permitted source networks in one set](#fw096-maintain-several-permitted-source-networks-in-one-set)
- [FW097: Remove a port-forward mapping cleanly](#fw097-remove-a-port-forward-mapping-cleanly)
- [FW098: Complete starting configuration for a standalone web server](#fw098-complete-starting-configuration-for-a-standalone-web-server)
- [FW099: Complete starting configuration for an IPv4 LAN internet router](#fw099-complete-starting-configuration-for-an-ipv4-lan-internet-router)
- [FW100: Complete starting configuration for an OpenVPN gateway](#fw100-complete-starting-configuration-for-an-openvpn-gateway)

### FW091: Add a service allowance during specified UTC hours

```sh
sudo iptables -A INPUT -s 198.51.100.10/32 -p tcp --dport 8443 \
  -m time --timestart 09:00 --timestop 17:00 --weekdays Mon,Tue,Wed,Thu,Fri -j ACCEPT
```

**What it does:** Matches the selected source/service during the weekday UTC window. **Change:** Source, port, hours, days. Needs default-deny/other appropriate policy outside the window. It is not a guaranteed session cutoff: earlier broad or established-flow accepts can keep existing traffic allowed. Local daylight-saving changes do not change the default UTC schedule.

### FW092: Log incoming packets whose destination is local to this host

```sh
sudo iptables -t mangle -A PREROUTING -m addrtype --dst-type LOCAL \
  -p tcp --dport 8080 -m limit --limit 5/minute \
  -j LOG --log-prefix 'LOCAL8080: '
```

**What it does:** Logs matching incoming TCP 8080 packets for destinations classified as local at that hook. **Change:** Port/rate/prefix. LOCAL means an address assigned/treated as local by routing, not “private RFC1918.” It logs packets regardless of whether they begin a connection. This is diagnostic, not an allow rule; NAT later in the path can alter the destination.

### FW093: Assign a packet mark for another subsystem to use

```sh
sudo iptables -t mangle -A PREROUTING -i eth1 -s 10.20.10.0/24 \
  -j MARK --set-xmark 0x10/0xff
```

**What it does:** Sets the low eight bits of the packet's local mark to hexadecimal 10, preserving other bits. **Change:** Interface/subnet and a mark/mask that does not conflict with your existing policy. An `ip rule`/traffic-control consumer is needed for an effect such as policy routing. The mark is kernel metadata, not a field transmitted to the remote peer.

### FW094: Clear untrusted DSCP priority claims at a guest boundary

```sh
sudo iptables -t mangle -A PREROUTING -i eth2 -s 10.30.0.0/24 \
  -j DSCP --set-dscp 0
```

**What it does:** Resets DSCP for traffic entering from the selected guest network. **Change:** Guest interface/subnet. This can support a QoS trust boundary; it does not rate-limit or drop packets. Apply only where you intend to discard client-supplied priority markings.

### FW095: Use RETURN to hand a decision back to the main chain

```sh
sudo iptables -N SOURCE_SCREEN
sudo iptables -A SOURCE_SCREEN -s 192.0.2.66/32 -j DROP
sudo iptables -A SOURCE_SCREEN -j RETURN
sudo iptables -I INPUT 1 -j SOURCE_SCREEN
```

**What it does:** Drops one source; all other traffic returns to the next INPUT rule instead of being automatically accepted. **Change:** Unused chain name/source. RETURN is useful for a screening chain that should not replace the rest of your policy. The attached first-position block can affect existing management traffic from that source.

### FW096: Maintain several permitted source networks in one set

```sh
sudo ipset create web_trusted_v4 hash:net family inet
sudo ipset add web_trusted_v4 10.20.0.0/24
sudo ipset add web_trusted_v4 10.8.0.0/24
sudo iptables -A INPUT -p tcp --dport 8443 \
  -m set --match-set web_trusted_v4 src -j ACCEPT
```

**What it does:** Keeps a multi-network service allowance in one set-backed rule. **Change:** Unused set name, networks, port. This is an allowance under an otherwise restrictive policy; it does not cancel a broader existing 8443 ACCEPT. Save/restore the set before any boot-time rule that references it.

### FW097: Remove a port-forward mapping cleanly

```sh
sudo iptables -t nat -D PREROUTING -i eth0 -d 203.0.113.10/32 \
  -p tcp --dport 8443 -j DNAT --to-destination 10.20.0.20:443
sudo iptables -D FORWARD -i eth0 -o eth1 -d 10.20.0.20/32 \
  -p tcp --dport 443 -j ACCEPT
```

**What it does:** Removes the exact mapping and forwarding allowance from FW064. **Change:** Match the actual rules. Check whether the FORWARD allowance is also needed by another mapping before removing it. Existing translated flows can retain their mappings/permission through other reply rules; test a fresh connection rather than assuming immediate revocation.

### FW098: Complete starting configuration for a standalone web server

**Use this when:** One Linux host serves public HTTP/HTTPS, allows SSH from one administration address, and may make arbitrary outbound connections. It does not route traffic. This is an IPv4 filter-table replacement, not a snippet to append. It assumes static addressing; add DHCP requirements if applicable.

Save as `web-host-v4.rules` after changing the administration address:

```iptables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

-A INPUT -s 198.51.100.10/32 -p tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

# Preserve ICMP for diagnosis and path-MTU operation.
-A INPUT -p icmp -j ACCEPT

-A INPUT -m limit --limit 3/minute --limit-burst 5 -j LOG --log-prefix "WEB DROP: "
COMMIT
```

**Why it works:** Unsolicited inbound traffic is dropped unless a rule permits it; local communication and tracked replies are handled before service allowances. HTTP/3 is not opened. **Change:** Administration source, service ports, optional ICMP policy. Add a separate IPv6 policy. Use FW018/FW019 to review/apply; do not replace a manager/container-owned filter table with this file.

### FW099: Complete starting configuration for an IPv4 LAN internet router

**Use this when:** `eth1` serves LAN `10.20.0.0/24`, `eth0` is the WAN, clients may initiate internet connections, and only the LAN may SSH into the router. Both interfaces and addressing already exist. This replaces **filter and nat tables**. Enable IPv4 forwarding separately.

Save as `lan-router-v4.rules` after adapting interfaces/networks:

```iptables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i eth1 -s 10.20.0.0/24 -p tcp --dport 22 -j ACCEPT
-A INPUT -p icmp -j ACCEPT

-A FORWARD -m conntrack --ctstate INVALID -j DROP
-A FORWARD -i eth1 -o eth0 -s 10.20.0.0/24 -j ACCEPT
-A FORWARD -i eth0 -o eth1 -d 10.20.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

-A FORWARD -m limit --limit 3/minute --limit-burst 5 -j LOG --log-prefix "ROUTER DROP: "
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE
COMMIT
```

**Why it works:** LAN traffic can leave through the WAN, translated to the WAN address; unsolicited WAN forwarding stays denied. **Change:** Interfaces, LAN prefix, management-source scope. Clients need this router as a gateway and a reachable DNS resolver. This does not run a DNS/DHCP service or permit DHCP client/server traffic; add those only if the router uses/provides them. IPv6 is separate.

### FW100: Complete starting configuration for an OpenVPN gateway

**Use this when:** This host terminates OpenVPN on WAN UDP 1194, has `tun0` clients in `10.8.0.0/24`, and routes to LAN `10.20.0.0/24` through `eth1`. VPN clients may use the internet through `eth0`, reach one LAN HTTPS server, and query one LAN DNS server. This replaces **filter and nat tables**. Interfaces, VPN configuration, and IPv4 forwarding must already be provisioned.

Save as `openvpn-gateway-v4.rules`:

```iptables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i eth0 -s 198.51.100.10/32 -p tcp --dport 22 -j ACCEPT
-A INPUT -i eth0 -p udp --dport 1194 -j ACCEPT
-A INPUT -p icmp -j ACCEPT

-A FORWARD -m conntrack --ctstate INVALID -j DROP
-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Specific LAN services reachable from VPN clients.
-A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.20/32 -p tcp --dport 443 -j ACCEPT
-A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.53/32 -p udp --dport 53 -j ACCEPT
-A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.53/32 -p tcp --dport 53 -j ACCEPT

# Internet access through the actual WAN route.
-A FORWARD -i tun0 -o eth0 -s 10.8.0.0/24 -j ACCEPT

-A FORWARD -m limit --limit 3/minute --limit-burst 5 -j LOG --log-prefix "VPN FWD DROP: "
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
COMMIT
```

**Why it works:** INPUT permits the outer VPN connection, FORWARD permits selected inner paths, and WAN NAT supplies internet return routing. LAN traffic keeps the original VPN client address. **Change:** All interfaces, networks, admin source, LAN service addresses, and listener port. LAN hosts need a route back to `10.8.0.0/24` via this server's LAN address. Use narrowly scoped LAN NAT only if return routing cannot be installed.

**Complete the VPN side:** Push the intended LAN/default routes and DNS settings. Decide IPv6 and disconnect behavior separately. Do not enable internal `client-to-client` forwarding and assume this kernel policy still isolates clients; verify the real userspace/offload path. Existing flows accepted by the broad reply rule may outlive policy changes; use fresh tests when checking restrictions.

## Quick fixes when an example does not work

| Symptom | First things to check |
|---|---|
| New rule never counts packets | Wrong family, chain, interface, namespace, or an earlier terminating rule |
| Rule counts requests but application fails | Listener, destination port after NAT, server response path |
| VPN connects but LAN does not | Pushed route, FORWARD allowance, LAN return route |
| Allow rule does not restrict anyone else | Broader allow or ACCEPT default policy remains |
| New deny seems ineffective | Placement after ACCEPT, existing flow/offload path, wrong address family |
| Port forward works outside but not on LAN | Hairpin NAT or split DNS design |
| Router can browse but LAN cannot | OUTPUT differs from FORWARD; inspect forwarding and source NAT |
| Rules disappear or come back | Firewall manager, containers, or persistence service overwrote manual changes |
| DNS sometimes works, sometimes fails | UDP plus TCP handling, actual resolver address, MTU, IPv6 |
| Service reachable despite IPv4 deny | IPv6 listener/policy or a different network namespace/path |
| Match/target unavailable | Installed extension and kernel/backend capabilities |

## References and verification

These are original example scenarios, with version-specific option references in the official [iptables manual](https://ipset.netfilter.org/iptables.man.html), [extension manual](https://ipset.netfilter.org/iptables-extensions.man.html), and [Netfilter documentation](https://www.netfilter.org/documentation/). Check your installed `man iptables`, `man iptables-extensions`, `man iptables-restore`, and `man ipset`: the linked web manuals may describe older packages.

Recipe numbering, Markdown, internal navigation, and packaged contents were checked. Commands and templates were reviewed but were not executed against a Linux firewall in this Windows workspace. Persist changes using the distribution's existing firewall system after validation; merely running `iptables-save` does not install a boot-time restore service.
