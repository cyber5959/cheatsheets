# Networking, Security & Command-Line Cheat Sheets

Independent, searchable command cookbooks for general administration, networking, and defensive security. The original collection has 280 numbered recipes. Additional guides cover network basics/CIDR sweeps, SSH forwarding, and Ligolo-ng, with worked layouts up to eight remote boxes deep. The Nmap toolkit adds a runnable Bash command builder with profiles, readable options, command preview, and native Nmap passthrough.

| File | Coverage |
|---|---|
| [Regex — recipes R01–R30](regex.md#example-cookbook) | Find exact fields, extract addresses, filter errors, search logs, validate token shapes |
| [awk — recipes A01–A30](awk.md#example-cookbook) | Select columns, count/sum/group, join inventories, find duplicates, calculate deltas |
| [gawk — recipes G01–G30](gawk.md#example-cookbook) | Capture groups, CSV, nested maps, percentiles, timestamps, flags, multiple files |
| [sed — recipes S01–S30](sed.md#example-cookbook) | Replace config values, trim text, redact fields, edit blocks, preview changes |
| [iptables — recipes I01–I30](iptables.md#example-cookbook) | Inspect counters, add/remove service rules, log drops, NAT, forwarding, IPv6, rollback |
| [iptables examples — FW001–FW100](iptables-examples.md) | Dedicated rule collection: services, restrictions, egress, LAN/VPN routing, NAT, logging, IPv6, complete configurations |
| [OpenVPN — recipes V01–V30](openvpn-configs.md#example-cookbook) | Change endpoints/routes/DNS, assign addresses, diagnose packets, verify certificates |
| [Network basics and ping sweeps](network-basics-ping-sweeps.md) | 50 recipes, IPv4 prefix table /32 through /0, subnet loops, bounded concurrency, Windows/IPv6, Python helper |
| [SSH tunneling](ssh-tunneling.md) | 50 recipes, local/remote TCP and SOCKS, jumps, Unix sockets, TUN/TAP, X11, eight-box worked layout |
| [Ligolo-ng tunneling](ligolo-ng-tunneling.md) | 38 recipes, routes, listeners, bind/SOCKS transport, cleanup, step-by-step eight-agent layout |
| [Nmap Bash toolkit](nmap-toolkit.sh) | Standalone wrapper with scan profiles, discovery, TCP/UDP/SCTP modes, service/OS detection, NSE, timing, output, dry-run, authorization gate, and complete native option passthrough |
| [SSH Tunnel Master](ssh-tunnel-master.sh) | Interactive unlimited tunnel builder for local, remote, dynamic, remote-SOCKS, and raw OpenSSH forwards; launches every tunnel in a named, balanced Terminator split |
| [IPIP Tunnel Master](ipip-tunnel-master.sh) | Interactive two-ended Linux IPIP topology manager with local/SSH execution, nested tunnel ordering, MTU guidance, routes, status, rollback, save/load, and endpoint-script export |

## Pick a tool by the problem

| I need to… | Start here |
|---|---|
| Find text, an error, an address, or a pattern | Regex recipes R01–R30 |
| Require two terms or exclude noisy matches | Regex R04–R05 |
| Extract all addresses and rank occurrences | Regex R11 |
| Pull out columns or filter by an exact value | awk A01–A11 |
| Get totals, averages, maximums, or top sources | awk A12–A15 |
| Compare an event list against an inventory | awk A18–A20 |
| Parse moving key=value fields | awk A24 or gawk G07 |
| Parse real CSV with quoted commas | gawk G09 (5.3+) |
| Calculate median/p95/p99 latency | gawk G14–G15 |
| Group or convert epoch timestamps | gawk G21–G23 |
| Change a setting or comment/uncomment it | sed S05–S08 |
| Keep/remove a block of lines | sed S17–S19 |
| Preview an edit without changing the file | sed S30 |
| Find which firewall rule sees my packet | iptables I01–I03 |
| Browse lots of individual firewall rules to adapt | Dedicated iptables examples FW001–FW100 |
| Open a service or restrict its allowed source | iptables I09–I14 |
| Debug a firewall decision without allowing traffic | iptables I18–I19 |
| Configure NAT or forward a public port | iptables I23–I26 |
| Change VPN transport, endpoint, or routes | OpenVPN V02–V11 |
| Diagnose VPN DNS problems | OpenVPN V12–V14 |
| Find where VPN packets stop | OpenVPN V21–V25 |
| Check a VPN certificate, key pair, or CRL | OpenVPN V26–V29 |
| Build, preview, and run an Nmap command | Nmap Bash toolkit (`--help`, `--list-profiles`, and `--dry-run`) |
| Build many visible, labeled SSH tunnels | SSH Tunnel Master (interactive menu, save/load, dry-run, Terminator panes) |
| Build routed IPv4-in-IPv4 links across multiple boxes | IPIP Tunnel Master (ordered topology, plan/apply/status/destroy, nested MTUs) |

## Nmap toolkit quick start

```sh
chmod +x nmap-toolkit.sh
./nmap-toolkit.sh --help
./nmap-toolkit.sh --list-profiles
./nmap-toolkit.sh --dry-run --profile inventory --target 192.0.2.0/24 --output-all inventory
./nmap-toolkit.sh --authorized --profile service --target scanme.nmap.org --ports 22,80,443
```

`--dry-run` prints the exact safely quoted command without sending packets. Actual scans require `--authorized`. The named wrapper options cover common scan work; put any native Nmap arguments after `--` for full compatibility with the installed Nmap version. Use the script only for hosts and networks you own or have explicit permission to assess.

## SSH Tunnel Master quick start

```sh
chmod +x ssh-tunnel-master.sh
./ssh-tunnel-master.sh --doctor
./ssh-tunnel-master.sh
```

Use the numbered menu to add local (`-L`), remote (`-R`), local SOCKS (`-D`), remote SOCKS, or advanced raw forwards. Give every tunnel a descriptive name; it becomes the Terminator pane title. Add as many tunnels as needed, review them with option 6, then press `L` to launch. Option 8 saves the set for later, and `--load FILE --launch` reopens it without rebuilding each entry.

## IPIP Tunnel Master quick start

```sh
chmod +x ipip-tunnel-master.sh
./ipip-tunnel-master.sh
./ipip-tunnel-master.sh --load ipip-topology.txt --plan
```

Define the underlay tunnel first and each deeper tunnel afterward. Every record describes endpoint A and B, where its commands run (`local` or SSH), outer and inner IPv4 addresses, routes, MTU, TTL, and forwarding. Review option 6 before applying option 7. Applied state is runtime-only unless you separately convert the exported endpoint scripts into your distribution's persistent network configuration.

## How to use this repository

Open any file above. GitHub renders the Markdown and its code blocks without requiring readers to sign in when the repository is public. Use the file's contents links or your browser's Find function to jump to a topic. The **Raw** view is convenient for copying text.

Start with the clickable **Find an example** list in each sheet. Search for either a problem word (such as `DNS`, `duplicate`, `port`, or `redact`) or a recipe ID (such as `A18`). Read the explanation before pasting: a field number or log-format assumption is often the only change you need, while firewall/VPN recipes can depend on surrounding policy and routing.

To upload: open your repository, choose **Add file → Upload files**, and drag in the extracted files from this folder. Commit the upload. Upload the individual files, not just the ZIP, so readers can browse each sheet.

## Conventions

- Commands use a Linux POSIX shell unless labeled otherwise. They are not PowerShell commands. WSL or a Linux VM is suitable for the text-processing examples.
- `awk.md` emphasizes portable awk; `gawk.md` explicitly uses GNU awk. `sed.md` labels GNU features. Installed versions and distributions differ.
- Firewall commands require Linux and administrative privileges. OpenVPN examples target Community Edition 2.6-style configuration, not Access Server administration.
- Example addresses `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, and `2001:db8::/32` are documentation addresses. `example.com` names are placeholders. Replace interface names, networks, paths, and identities before use.
- Examples are independent recipes unless a block is explicitly presented as one complete file or sequence. Do not paste an entire cheat sheet into a terminal.
- Keep real VPN profiles, private keys, tokens, passwords, logs, and identifying infrastructure details out of a public repository. A `.gitignore` helps with local Git but is not a security boundary or a substitute for reviewing uploads.

## Scope and verification

These are original worked examples, with official reference links in each sheet. They combine quick lookup tables with longer workflows and common failure cases. Reference review: September 2026. Version-specific features are labeled; no claim is made that an example is universally supported or production-ready without adaptation.

Recipe numbering, Markdown structure, internal links, and the Nmap wrapper's structure/options were checked during preparation. Linux commands were reviewed but were not runtime-tested in this restricted Windows workspace. Firewall and VPN examples are templates, not configurations tested against your network. Before changing remote networking, keep console access and a tested recovery path.
