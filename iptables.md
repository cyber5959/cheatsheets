# iptables — Linux Firewall, NAT & VPN Networking

[Repository index](README.md) · [OpenVPN configurations](openvpn-configs.md)

## Contents

- [Example cookbook: 30 problems and commands](#example-cookbook)
- [Scope and packet flow](#scope-and-packet-flow)
- [Inspect before changing](#inspect-before-changing)
- [Command and match reference](#command-and-match-reference)
- [Connection tracking and rule order](#connection-tracking-and-rule-order)
- [Recoverable deployment](#recoverable-deployment)
- [Complete IPv4 host template](#complete-ipv4-host-template)
- [Service and logging recipes](#service-and-logging-recipes)
- [Forwarding and NAT](#forwarding-and-nat)
- [OpenVPN firewall integration](#openvpn-firewall-integration)
- [IPv6](#ipv6)
- [Sets and rate limits](#sets-and-rate-limits)
- [Persistence and troubleshooting](#persistence-and-troubleshooting)
- [Official references](#official-references)

## Example cookbook

Each example is independent. Inspect the active firewall manager/backend first; these commands change Linux rules immediately when run. For `-A` recipes, place the rule before any terminal DROP/REJECT and consider earlier ACCEPT rules. If needed, use `-I CHAIN POSITION` with a position you just inspected. These are focused edits, not complete policies; apply remotely only with the recovery procedure in this sheet. Example interfaces/addresses must be replaced.

### Find an example

- [I01: See which INPUT rule is matching traffic](#i01-see-which-input-rule-is-matching-traffic)
- [I02: Show rules in a form that is easier to copy and review](#i02-show-rules-in-a-form-that-is-easier-to-copy-and-review)
- [I03: Inspect address-translation rules separately](#i03-inspect-address-translation-rules-separately)
- [I04: Back up both address families before editing](#i04-back-up-both-address-families-before-editing)
- [I05: Check whether an exact rule already exists](#i05-check-whether-an-exact-rule-already-exists)
- [I06: Add a descriptive comment to a service rule](#i06-add-a-descriptive-comment-to-a-service-rule)
- [I07: Delete a rule by its exact specification](#i07-delete-a-rule-by-its-exact-specification)
- [I08: Delete one rule by its current position](#i08-delete-one-rule-by-its-current-position)
- [I09: Open a UDP OpenVPN listener](#i09-open-a-udp-openvpn-listener)
- [I10: Permit SSH only from a chosen administration address](#i10-permit-ssh-only-from-a-chosen-administration-address)
- [I11: Permit SSH arriving through the VPN interface](#i11-permit-ssh-arriving-through-the-vpn-interface)
- [I12: Permit a web service on several TCP ports](#i12-permit-a-web-service-on-several-tcp-ports)
- [I13: Permit a contiguous port range from a private network](#i13-permit-a-contiguous-port-range-from-a-private-network)
- [I14: Permit LAN clients to use this host as a DNS server](#i14-permit-lan-clients-to-use-this-host-as-a-dns-server)
- [I15: Block one source address immediately on this host](#i15-block-one-source-address-immediately-on-this-host)
- [I16: Block access to one destination from this host](#i16-block-access-to-one-destination-from-this-host)
- [I17: Reject a closed TCP service with a reset](#i17-reject-a-closed-tcp-service-with-a-reset)
- [I18: Log traffic for a port without deciding its fate](#i18-log-traffic-for-a-port-without-deciding-its-fate)
- [I19: View firewall messages in the kernel journal](#i19-view-firewall-messages-in-the-kernel-journal)
- [I20: Create a shared log-and-drop destination](#i20-create-a-shared-log-and-drop-destination)
- [I21: Permit a VPN client subnet to reach one LAN service](#i21-permit-a-vpn-client-subnet-to-reach-one-lan-service)
- [I22: Prevent VPN clients from directly forwarding to each other](#i22-prevent-vpn-clients-from-directly-forwarding-to-each-other)
- [I23: Source-NAT VPN clients leaving through the WAN](#i23-source-nat-vpn-clients-leaving-through-the-wan)
- [I24: Source-NAT a LAN using a fixed external address](#i24-source-nat-a-lan-using-a-fixed-external-address)
- [I25: Forward an external port to an internal HTTPS server](#i25-forward-an-external-port-to-an-internal-https-server)
- [I26: Redirect an incoming port to another port on this host](#i26-redirect-an-incoming-port-to-another-port-on-this-host)
- [I27: Add a temporary block-list member with expiry](#i27-add-a-temporary-block-list-member-with-expiry)
- [I28: Allow HTTPS over IPv6 too](#i28-allow-https-over-ipv6-too)
- [I29: Validate a candidate rules file without applying it](#i29-validate-a-candidate-rules-file-without-applying-it)
- [I30: Apply with timed rollback and verify a fresh session](#i30-apply-with-timed-rollback-and-verify-a-fresh-session)

### I01: See which INPUT rule is matching traffic

```sh
sudo iptables -L INPUT -n -v -x --line-numbers
```

Shows exact packet/byte counters and current line positions. Change INPUT to FORWARD for routed traffic or OUTPUT for locally generated traffic. Re-run after a test connection and compare counters.

### I02: Show rules in a form that is easier to copy and review

```sh
sudo iptables -S INPUT
```

Displays rule specifications rather than the tabular view. Change the chain or omit it for all filter-table chains. This is inspection, not a backup of all tables; use I04 for that.

### I03: Inspect address-translation rules separately

```sh
sudo iptables -t nat -L -n -v --line-numbers
sudo iptables -t nat -S
```

The default filter listing does not show NAT rules. Change `nat` to `mangle` for packet-mark/header rules. NAT counters mostly reflect connection setup rather than every packet in a flow.

### I04: Back up both address families before editing

```sh
sudo iptables-save > before-v4.rules
sudo ip6tables-save > before-v6.rules
```

Change output names and keep these real network snapshots private. This saves files only; it does not configure boot-time restoration or provide automatic rollback.

### I05: Check whether an exact rule already exists

```sh
sudo iptables -C INPUT -p udp --dport 1194 -j ACCEPT
```

Exit 0 means the exact rule exists; a nonzero status can mean absent or an error, so read stderr. Change the complete specification to match your intended rule. A different rule might already allow the traffic even when this check fails.

### I06: Add a descriptive comment to a service rule

```sh
sudo iptables -A INPUT -p tcp --dport 443 \
  -m comment --comment 'public HTTPS service' -j ACCEPT
```

Change port and label. Comments help identify rule ownership during review. Existing earlier denies can still prevent this appended rule from being reached.

### I07: Delete a rule by its exact specification

```sh
sudo iptables -D INPUT -p tcp --dport 443 \
  -m comment --comment 'public HTTPS service' -j ACCEPT
```

Removes the rule from I06. Change every argument to match the actual rule, including its comment. This is less sensitive to renumbering than deleting by position, but duplicates may require repeated deliberate removal.

### I08: Delete one rule by its current position

```sh
sudo iptables -L INPUT -n --line-numbers
# After inspecting the CURRENT listing, remove the intended position:
sudo iptables -D INPUT 7
```

Change 7 to the position you just verified. The second command mutates policy; do not run it merely because an old screenshot showed rule 7. All later positions shift after deletion.

### I09: Open a UDP OpenVPN listener

```sh
sudo iptables -A INPUT -i eth0 -p udp --dport 1194 -j ACCEPT
```

Change WAN interface, protocol, and port to match the server configuration. This permits the outer VPN transport only; access through the tunnel needs separate routing/FORWARD rules.

### I10: Permit SSH only from a chosen administration address

```sh
sudo iptables -A INPUT -s 198.51.100.10/32 -p tcp --dport 22 -j ACCEPT
```

Replace the source and port. This allow rule restricts nothing if another broad SSH ACCEPT already exists; remove/restrict conflicting rules through a recoverable policy change. A default-deny or appropriate later deny supplies the restriction.

### I11: Permit SSH arriving through the VPN interface

```sh
sudo iptables -A INPUT -i tun0 -s 10.8.0.0/24 -p tcp --dport 22 -j ACCEPT
```

Change tunnel name, VPN subnet, and SSH port. Both the interface and source subnet must match. Existing public-interface SSH allowances remain in effect until you deliberately change them.

### I12: Permit a web service on several TCP ports

```sh
sudo iptables -A INPUT -p tcp -m multiport --dports 80,443,8443 -j ACCEPT
```

Change the comma-separated port list. This does not create listeners or configure TLS. Use `ss -lntp` to confirm the application listens on the intended addresses/ports.

### I13: Permit a contiguous port range from a private network

```sh
sudo iptables -A INPUT -s 10.20.0.0/24 -p tcp --dport 8000:8010 -j ACCEPT
```

Change subnet and inclusive range. Use a narrow range covering the actual service; avoid opening a whole high-port range just to discover which port an application needs.

### I14: Permit LAN clients to use this host as a DNS server

```sh
sudo iptables -A INPUT -i eth1 -s 10.20.0.0/24 -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -i eth1 -s 10.20.0.0/24 -p tcp --dport 53 -j ACCEPT
```

Change LAN interface/subnet. DNS uses both UDP and TCP. These are inbound DNS-server rules, not rules for a host merely making DNS queries.

### I15: Block one source address immediately on this host

```sh
sudo iptables -I INPUT 1 -s 192.0.2.66/32 -j DROP
```

Change the source after verifying it is the intended address. Position 1 makes the deny precede existing INPUT accepts. It affects local-host traffic, not routed traffic; use the appropriate chain for that path. Do not block your own management source.

### I16: Block access to one destination from this host

```sh
sudo iptables -I OUTPUT 1 -d 203.0.113.66/32 -j REJECT
```

Change the destination. This applies to locally generated traffic and returns an error instead of silently discarding. Shared-hosting IPs may serve many unrelated domains, and IPv6 needs its own policy.

### I17: Reject a closed TCP service with a reset

```sh
sudo iptables -A INPUT -p tcp --dport 23 -j REJECT --reject-with tcp-reset
```

Change port 23 to the unwanted TCP service. TCP reset is appropriate only for TCP. Put the reject before a broader service allowance if it must override that allowance.

### I18: Log traffic for a port without deciding its fate

```sh
sudo iptables -I INPUT 1 -p tcp --dport 8443 \
  -m limit --limit 6/minute --limit-burst 10 \
  -j LOG --log-prefix 'DEBUG 8443: '
```

Change port, rate, and prefix. LOG continues to later rules; it does not permit or block the packet. Remove the temporary diagnostic rule when done and inspect kernel logs privately.

### I19: View firewall messages in the kernel journal

```sh
sudo journalctl -k --since '10 minutes ago' | grep -F 'DEBUG 8443: '
```

Change prefix and time window. Requires systemd journal integration and LOG output reaching the kernel log. A lack of messages can reflect rate limiting or logging configuration, not just absence of traffic.

### I20: Create a shared log-and-drop destination

```sh
sudo iptables -N REVIEW_DROP
sudo iptables -A REVIEW_DROP -m limit --limit 5/minute -j LOG --log-prefix 'REVIEW DROP: '
sudo iptables -A REVIEW_DROP -j DROP
sudo iptables -A INPUT -s 192.0.2.66/32 -j REVIEW_DROP
```

Change chain name, prefix, and source. The chain must not already exist; inspect before running. This sequence creates, populates, and references one custom chain; it does not create a full firewall.

### I21: Permit a VPN client subnet to reach one LAN service

```sh
sudo iptables -A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.20 \
  -p tcp --dport 443 -j ACCEPT
```

Change interfaces, networks, target, and port. Assumes the baseline return-traffic allowance, forwarding sysctl, client route, and LAN return route are already configured. This single request-direction rule alone is not a working routed policy.

### I22: Prevent VPN clients from directly forwarding to each other

```sh
sudo iptables -I FORWARD 1 -i tun0 -o tun0 -s 10.8.0.0/24 -d 10.8.0.0/24 -j DROP
```

Change the tunnel interface and subnet. Applies only to traffic traversing this kernel FORWARD path. OpenVPN internal `client-to-client` forwarding and offload paths require separate verification; do not claim isolation based on this rule alone.

### I23: Source-NAT VPN clients leaving through the WAN

```sh
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
```

Change tunnel subnet and WAN interface. Requires forwarding permissions, enabled IP forwarding, and client routes. It does not by itself make a split tunnel into a full tunnel.

### I24: Source-NAT a LAN using a fixed external address

```sh
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 \
  -j SNAT --to-source 203.0.113.10
```

Replace all addresses/interfaces. The selected public address must be yours and routed correctly. Use this instead of a competing MASQUERADE rule for the same traffic, not in addition to it.

### I25: Forward an external port to an internal HTTPS server

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -d 203.0.113.10 -p tcp --dport 8443 \
  -j DNAT --to-destination 10.20.0.20:443
sudo iptables -A FORWARD -i eth0 -o eth1 -d 10.20.0.20 -p tcp --dport 443 -j ACCEPT
```

Change external/internal addresses, interfaces, and ports. Requires baseline return-traffic handling, routing, and forwarding. FORWARD sees destination port 443 after translation, not original port 8443. Test from an external machine.

### I26: Redirect an incoming port to another port on this host

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 8080 \
  -j REDIRECT --to-ports 80
```

Change interface and ports. The host needs a listener on translated port 80 and an INPUT allowance for that path. Locally originated requests use OUTPUT and do not traverse this external PREROUTING rule.

### I27: Add a temporary block-list member with expiry

```sh
sudo ipset create temp_block_v4 hash:ip family inet timeout 3600
sudo iptables -I INPUT 1 -m set --match-set temp_block_v4 src -j DROP
sudo ipset add temp_block_v4 192.0.2.66 timeout 600
```

Requires ipset and compatible kernel/backend support. Create the set/rule once; add later members separately. Change address and timeout in seconds. State is not automatically persistent across reboot.

### I28: Allow HTTPS over IPv6 too

```sh
sudo ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
```

Change port as needed. IPv4 `iptables` and IPv6 `ip6tables` policies are separate. Add this within a coherent IPv6 host policy that preserves required ICMPv6 behavior.

### I29: Validate a candidate rules file without applying it

```sh
sudo iptables-restore --test < candidate-v4.rules
```

Change the path. Checks construction without committing the rules; requires appropriate privileges/backend support. This is not a reachability test and does not catch an incorrect administration address or service port.

### I30: Apply with timed rollback and verify a fresh session

```sh
sudo iptables-apply -t 60 candidate-v4.rules
```

Requires a distribution providing `iptables-apply`. Change timeout/path, keep console access, and confirm only after a new management connection and required service checks succeed. The candidate can replace existing manager/container filter chains; review its ownership and scope first.

## Scope and packet flow

This sheet targets the Linux iptables command interface. `iptables-nft` translates that interface into the nftables backend; `iptables-legacy` uses the older backend. Rules in one backend may be invisible to the other. Identify the active firewall manager before editing.

```text
Packet arrives
    |
PREROUTING (DNAT can change destination)
    |
Routing decision
    +---- local destination ---- INPUT ---- local process
    |
    +---- routed destination --- FORWARD --- POSTROUTING (SNAT) ---> network

Local process ---- OUTPUT ---- POSTROUTING ---> network
```

This is a simplified map, omitting some hook priorities, rerouting, and bridge details. The central distinction: traffic addressed to this machine uses INPUT; traffic passing through it uses FORWARD.

| Table | Typical use | Common built-in chains |
|---|---|---|
| `filter` | Permit/drop traffic | INPUT, FORWARD, OUTPUT |
| `nat` | Address translation for tracked connections | PREROUTING, INPUT, OUTPUT, POSTROUTING |
| `mangle` | Packet marks and selected header changes | INPUT, OUTPUT, FORWARD, PREROUTING, POSTROUTING |
| `raw` | Early handling, including tracking exemptions | PREROUTING, OUTPUT |
| `security` | Security labeling / mandatory access control integration | INPUT, FORWARD, OUTPUT |

NAT does not grant forwarding permission. Its rules usually process the first packet of a connection; connection tracking applies the mapping to subsequent packets. NAT rule counters are therefore not a full traffic meter.

## Inspect before changing

```sh
iptables --version
sudo iptables -S
sudo iptables -L -n -v --line-numbers
sudo iptables -t nat -S
sudo iptables -t nat -L -n -v --line-numbers
sudo ip6tables -S
sudo nft list ruleset                  # where nft is installed
ip -br address
ip route
ip -6 route
ss -lntup
```

`-n` avoids name/service resolution. `-v` shows counters and interfaces. Check Docker, Kubernetes, firewalld, UFW, VPN software, cloud firewalls, and network namespaces; they can create or override rules. Do not flush their chains as a troubleshooting shortcut.

### Snapshot and counters

```sh
sudo iptables-save -c > ipv4-before.rules
sudo ip6tables-save -c > ipv6-before.rules
sudo iptables -L INPUT -n -v -x
sudo iptables -t filter -S INPUT
sudo iptables -C INPUT -p tcp --dport 22 -j ACCEPT
```

`-C` checks for an exact rule specification, not whether the policy effectively permits traffic. A more-specific SSH rule will not match the example check. `iptables-save` may reveal private network details; keep real snapshots private.

## Command and match reference

| Operation | Example | Effect |
|---|---|---|
| Append | `-A INPUT ...` | Add to chain end |
| Insert | `-I INPUT 3 ...` | Insert before current rule 3 |
| Delete exact | `-D INPUT ...` | Remove matching rule |
| Delete by number | `-D INPUT 3` | Remove current rule 3 |
| Replace | `-R INPUT 3 ...` | Replace current rule 3 |
| Check | `-C INPUT ...` | Test exact rule existence |
| New chain | `-N AUDIT_DROP` | Create custom chain |
| Delete chain | `-X AUDIT_DROP` | Requires empty and unreferenced chain |
| Policy | `-P INPUT DROP` | Default for built-in chain |
| List rules | `-S` | Command-like representation |
| Zero counters | `-Z INPUT` | Reset accounting; loses diagnostic history |
| Flush | `-F INPUT` | Remove all rules in chain; high impact |

Rule numbers change after inserts/deletes. Re-list before acting, or delete by exact specification.

| Match | Example |
|---|---|
| Source | `-s 192.0.2.10/32` |
| Destination | `-d 203.0.113.20` |
| Input interface | `-i eth0` |
| Output interface | `-o tun0` |
| Protocol | `-p tcp`, `-p udp`, `-p icmp` |
| Destination port | `--dport 443` with TCP/UDP |
| Source port | `--sport 53` with TCP/UDP |
| Port interval | `--dport 8000:8100` |
| Several ports | `-m multiport --dports 22,80,443` |
| Connection state | `-m conntrack --ctstate NEW` |
| Negation | `! -s 192.0.2.0/24` |
| Comment | `-m comment --comment "HTTPS ingress"` |
| Wait for rule lock | `-w 5` before operation |

INPUT has an incoming interface; OUTPUT has an outgoing interface. FORWARD has both. Use source/destination addresses, not hostnames, for deterministic firewall rules.

| Target | Meaning |
|---|---|
| `ACCEPT` | Accept at this ruleset point; other hooks/policies may still matter |
| `DROP` | Silently discard |
| `REJECT` | Discard with a configured error response |
| `LOG` | Log and continue evaluation |
| `RETURN` | Return from custom chain; built-in policy applies in built-in chain |
| `DNAT` | Change destination in supported NAT hooks |
| `SNAT` | Change source in supported NAT hooks |
| `MASQUERADE` | Source NAT using outgoing interface address |
| `REDIRECT` | Redirect destination to this machine |

## Connection tracking and rule order

```sh
sudo iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT
```

These are rule fragments, not a full policy. Placement matters: an earlier DROP can make them unreachable, and an earlier broad ACCEPT can make later restrictions ineffective.

- **NEW:** traffic starting a tracked connection, including UDP exchanges; not simply “TCP SYN.”
- **ESTABLISHED:** traffic in a tracked flow that has seen appropriate bidirectional traffic.
- **RELATED:** traffic associated with an existing flow, such as certain ICMP errors; helper-based behavior depends on configuration.
- **INVALID:** cannot be assigned valid connection state.
- **UNTRACKED:** deliberately excluded from connection tracking.

An established-flow accept can keep an already-open connection alive after you add a later deny. Test with a fresh connection. Do not clear the entire connection-tracking table casually; it disrupts unrelated sessions.

## Recoverable deployment

Changing a remote firewall can disconnect your management session. Build and inspect a candidate file first, retain out-of-band console access, and use timed rollback where available.

```sh
# Save current state in private local files
sudo iptables-save > ipv4-before.rules
sudo ip6tables-save > ipv6-before.rules

# Parse/build the candidate without committing it
sudo iptables-restore --test < host-v4.rules

# If the distribution provides iptables-apply, it rolls back unless confirmed
sudo iptables-apply -t 60 host-v4.rules

# Manual recovery from a console if needed
sudo iptables-restore < ipv4-before.rules
```

`--test` does not verify reachability, service availability, routing, or correctness of your policy. `iptables-apply` availability differs by distribution. Confirm only after opening a new management connection and checking required services. A pre-existing SSH session is not sufficient evidence.

`iptables-restore` normally replaces the tables included in the file. A filter-only candidate replaces the filter table, including manager/container chains there, but leaves other tables alone. Do not use this standalone template on a machine whose filter table is owned by another manager without adapting its policy through that manager.

## Complete IPv4 host template

Save this as `host-v4.rules` after replacing the documentation address. Assumptions: standalone server, SSH from one administration address, public HTTP/HTTPS, all outbound allowed, no routing, static network setup. DHCP clients and other services need additional rules.

```iptables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Replace with the actual administration source address or VPN subnet.
-A INPUT -s 198.51.100.10/32 -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT

-A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW -j ACCEPT

# Preserve diagnostic/error ICMP; restrict echo separately if required.
-A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT
-A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT
-A INPUT -p icmp --icmp-type parameter-problem -j ACCEPT
-A INPUT -p icmp --icmp-type echo-request -m limit --limit 5/second --limit-burst 10 -j ACCEPT

-A INPUT -m limit --limit 3/minute --limit-burst 5 -j LOG --log-prefix "HOST DROP: " --log-level 6
COMMIT
```

The echo limit is shared by matching traffic, not per source. The LOG rule is nonterminal; the INPUT policy drops afterward. This is only IPv4; apply a deliberate IPv6 policy too.

## Service and logging recipes

Insert these before a terminal deny, and only when the corresponding service is required:

```sh
# OpenVPN listener
sudo iptables -A INPUT -p udp --dport 1194 -j ACCEPT

# DNS server for a private LAN; DNS uses UDP and TCP
sudo iptables -A INPUT -s 10.20.0.0/24 -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -s 10.20.0.0/24 -p tcp --dport 53 -j ACCEPT

# SSH only over a VPN interface and subnet
sudo iptables -A INPUT -i tun0 -s 10.8.0.0/24 -p tcp --dport 22 -j ACCEPT

# Explicitly refuse a TCP service instead of silently dropping
sudo iptables -A INPUT -p tcp --dport 23 -j REJECT --reject-with tcp-reset
```

### Reusable log-and-drop chain

```sh
sudo iptables -N AUDIT_DROP
sudo iptables -A AUDIT_DROP -m limit --limit 5/minute --limit-burst 10 \
  -j LOG --log-prefix "AUDIT DROP: " --log-level 6
sudo iptables -A AUDIT_DROP -j DROP
sudo iptables -A INPUT -s 192.0.2.66 -j AUDIT_DROP
sudo journalctl -k --since '10 minutes ago'
```

Creating the chain twice fails; check existing state when scripting. Logging can reveal metadata and fill storage without limits. Traditional LOG output goes through kernel logging; availability in a specific file depends on the logging configuration.

### Outbound restrictions

An OUTPUT DROP policy needs explicit allowances for loopback, established traffic, DNS, time synchronization, package repositories, monitoring, and required destinations. Example fragments for a chosen resolver:

```sh
sudo iptables -A OUTPUT -d 192.0.2.53 -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -d 192.0.2.53 -p tcp --dport 53 -j ACCEPT
```

These do not establish a complete egress policy. Filtering TCP/UDP port 53 does not control all DNS-over-HTTPS or application-level tunneling. Firewall rules do not authenticate application identity.

## Forwarding and NAT

For these examples: WAN `eth0`, LAN `eth1`, LAN subnet `10.20.0.0/24`. Replace all values. Enable forwarding only on a router:

```sh
sudo sysctl -w net.ipv4.ip_forward=1
```

### LAN internet access using source NAT

```sh
sudo iptables -A FORWARD -i eth1 -o eth0 -s 10.20.0.0/24 \
  -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -d 10.20.0.0/24 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE
```

For a fixed public source address, a corresponding SNAT rule can be used instead of MASQUERADE:

```sh
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 \
  -j SNAT --to-source 203.0.113.10
```

Use one appropriate source-NAT method for the same traffic, not both. Routing and the FORWARD policy must also work.

### Public port forwarding to an internal web server

```sh
sudo iptables -t nat -A PREROUTING -i eth0 -d 203.0.113.10 \
  -p tcp --dport 8443 -j DNAT --to-destination 10.20.0.20:443
sudo iptables -A FORWARD -i eth0 -o eth1 -d 10.20.0.20 \
  -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o eth0 -s 10.20.0.20 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

FORWARD sees the translated destination/port. The server needs a return path through the translating router. LAN access to the same public address may need separate hairpin NAT or split DNS. Locally generated traffic uses OUTPUT, so it does not test the external PREROUTING path.

### MSS clamping, only for diagnosed path-MTU problems

```sh
sudo iptables -t mangle -A FORWARD -o tun0 -p tcp \
  --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

This affects TCP SYN MSS advertisement, not UDP packets. Asymmetric paths can require a different design. Preserve ICMP fragmentation-needed/Packet Too Big messages and diagnose MTU before changing it.

## OpenVPN firewall integration

Assumptions: server tunnel `tun0`, clients `10.8.0.0/24`, LAN `eth1`/`10.20.0.0/24`, WAN `eth0`. Start with default-deny INPUT/FORWARD plus necessary management and established-flow rules.

```sh
# Tunnel's outer transport terminates on the VPN server
sudo iptables -A INPUT -i eth0 -p udp --dport 1194 -j ACCEPT

# VPN clients may reach the LAN
sudo iptables -A FORWARD -i tun0 -o eth1 -s 10.8.0.0/24 -d 10.20.0.0/24 \
  -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o tun0 -s 10.20.0.0/24 -d 10.8.0.0/24 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

LAN routers need a route back to `10.8.0.0/24` via the OpenVPN server's LAN address. If that route cannot be installed, narrowly scoped NAT is an alternative that hides individual client addresses:

```sh
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -d 10.20.0.0/24 -o eth1 -j MASQUERADE
```

For full-tunnel IPv4 internet access, add:

```sh
sudo iptables -A FORWARD -i tun0 -o eth0 -s 10.8.0.0/24 \
  -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o tun0 -d 10.8.0.0/24 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
```

Server-hosted services use INPUT, not FORWARD. Push routes in OpenVPN as well; firewall rules do not install client routes. These rules do not address client IPv6 leakage or client-side kill-switch requirements.

## IPv6

IPv4 rules do not protect IPv6 services. Inspect both families, including listeners on `::`. IPv6 depends on ICMPv6 for neighbor discovery and path-MTU operation; indiscriminate ICMPv6 blocking breaks connectivity.

Standalone IPv6 host template, requiring the same deployment/recovery care as the IPv4 file:

```iptables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Broad ICMPv6 allowance for a general host; refine with an IPv6-aware policy.
-A INPUT -p ipv6-icmp -j ACCEPT
# Replace the documentation administration address.
-A INPUT -s 2001:db8:100::10/128 -p tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
COMMIT
```

Save as `host-v6.rules`, inspect with `ip6tables-restore --test`, and apply through a recoverable deployment process. DHCPv6 clients may need UDP 547→546 allowances on the correct interface. SLAAC/router-advertisement behavior depends on host/router sysctls. Prefer routed IPv6 addressing over assuming IPv4 NAT examples should be copied to IPv6.

## Sets and rate limits

### ipset-backed address collection

Requires compatible ipset/iptables support. Place the match where it should take precedence over existing accepts.

```sh
sudo ipset create blocked_v4 hash:ip family inet timeout 3600
sudo ipset add blocked_v4 192.0.2.66 timeout 600
sudo iptables -A INPUT -m set --match-set blocked_v4 src -j DROP
sudo ipset list blocked_v4
sudo ipset del blocked_v4 192.0.2.66
```

Appending after an established-flow accept blocks new connections but may leave existing ones working. Set contents and iptables rules have separate persistence requirements. Do not populate a block list from unauthenticated input without review and expiration logic.

### Per-source new-connection rate example

```sh
sudo iptables -A INPUT -p tcp --syn --dport 22 \
  -m hashlimit --hashlimit-above 6/minute --hashlimit-burst 10 \
  --hashlimit-mode srcip --hashlimit-name ssh_rate -j DROP
```

Place before the corresponding SSH ACCEPT rule. This counts matching SYN packets, including retransmissions; it does not count failed logins or authenticate users. Shared-NAT clients share a source address. It does not stop a distributed attack or a saturated upstream link.

## Persistence and troubleshooting

Persistence is distribution-specific. `iptables-save` creates a snapshot; it does not arrange restoration at boot. Use the distribution's service/package or the existing firewall manager, and verify after restart. Do not mix several independent persistence systems.

```sh
sudo iptables-save > reviewed-v4.rules
sudo ip6tables-save > reviewed-v6.rules
sysctl net.ipv4.ip_forward
ip route get 10.20.0.20
sudo iptables -L FORWARD -n -v --line-numbers
sudo tcpdump -ni tun0 host 10.20.0.20
sudo tcpdump -ni eth1 host 10.20.0.20
```

Capture only the traffic needed for diagnosis; payloads can contain sensitive data. Packet observation alone does not establish which firewall rule matched.

| Symptom | Investigate |
|---|---|
| New rule counter stays zero | Wrong chain/interface/family/namespace; earlier terminating rule |
| Counter rises but service unreachable | Listener, return route, downstream firewall, response path |
| VPN connects but LAN fails | FORWARD policy, pushed route, LAN return route |
| DNS works for small replies only | TCP 53, fragmentation, MTU |
| Old sessions ignore new deny | Existing connection state and rule order |
| Port forward works externally only | Hairpin NAT/split DNS/local OUTPUT path |
| Rules disappear | Firewall manager, container runtime, boot persistence |
| IPv4 blocked but service reachable | IPv6 policy or alternate namespace/path |
| `Permission denied` | Root/capabilities or container restrictions |
| `No chain/target/match` | Missing extension/kernel support/backend mismatch |

For a specific service, trace: listener → route → correct family/namespace → rule counters → packet capture → return path. Change one hypothesis at a time.

## Official references

- [Netfilter iptables project](https://www.netfilter.org/projects/iptables/index.html).
- [iptables manual](https://ipset.netfilter.org/iptables.man.html).
- [iptables extension manual](https://ipset.netfilter.org/iptables-extensions.man.html).
- [Netfilter documentation index](https://www.netfilter.org/documentation/).
- [nftables project](https://www.netfilter.org/projects/nftables/index.html).
- Installed manuals: `man iptables`, `man ip6tables`, `man iptables-restore`, `man iptables-apply`, `man ipset`.

The linked iptables web manual may describe an older release than your installed package. Local manuals and actual backend/module support take precedence for version-specific options.
