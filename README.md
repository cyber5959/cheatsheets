# Networking, Security & Command-Line Cheat Sheets

Six independent, searchable command cookbooks for general administration, networking, and defensive security. Each sheet starts with **30 problem-based recipes**: a command or configuration snippet, what it does, and what to change. That is **180 numbered recipes**, plus the longer reference examples and complete templates further down each file.

| File | Coverage |
|---|---|
| [Regex — recipes R01–R30](regex.md#example-cookbook) | Find exact fields, extract addresses, filter errors, search logs, validate token shapes |
| [awk — recipes A01–A30](awk.md#example-cookbook) | Select columns, count/sum/group, join inventories, find duplicates, calculate deltas |
| [gawk — recipes G01–G30](gawk.md#example-cookbook) | Capture groups, CSV, nested maps, percentiles, timestamps, flags, multiple files |
| [sed — recipes S01–S30](sed.md#example-cookbook) | Replace config values, trim text, redact fields, edit blocks, preview changes |
| [iptables — recipes I01–I30](iptables.md#example-cookbook) | Inspect counters, add/remove service rules, log drops, NAT, forwarding, IPv6, rollback |
| [OpenVPN — recipes V01–V30](openvpn-configs.md#example-cookbook) | Change endpoints/routes/DNS, assign addresses, diagnose packets, verify certificates |

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
| Open a service or restrict its allowed source | iptables I09–I14 |
| Debug a firewall decision without allowing traffic | iptables I18–I19 |
| Configure NAT or forward a public port | iptables I23–I26 |
| Change VPN transport, endpoint, or routes | OpenVPN V02–V11 |
| Diagnose VPN DNS problems | OpenVPN V12–V14 |
| Find where VPN packets stop | OpenVPN V21–V25 |
| Check a VPN certificate, key pair, or CRL | OpenVPN V26–V29 |

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

Recipe numbering, Markdown structure, and internal links were checked during preparation. Commands were reviewed, but the Linux commands were not runtime-tested in this Windows workspace. Firewall and VPN examples are templates, not configurations tested against your network. Before changing remote networking, keep console access and a tested recovery path.
