# Network Basics and Ping Sweeps — CIDR and Copyable Commands

[Index](README.md) · [SSH tunnels](ssh-tunneling.md) · [Ligolo-ng tunnels](ligolo-ng-tunneling.md)

Examples are for your own or explicitly authorized networks. **Run location: your Linux workstation or the named Linux host whose network reachability you are testing**, unless a recipe says PowerShell. Commands here are references; none have been run against a network during preparation.

The Linux examples assume Bash, iputils `ping`, and Python 3 where specified. `ping -W` differs between operating systems: Linux examples use seconds; Windows `ping -w` uses milliseconds. A nonresponse means **no successful reply to that probe**, not proof that a host is down. Ordinary SSH SOCKS forwarding does not carry ICMP ping.

## Contents

- [CIDR sizes and boundaries](#cidr-sizes-and-boundaries)
- [Literal sweep one-liners](#literal-sweep-one-liners)
- [Any-prefix CIDR recipes](#any-prefix-cidr-recipes)
- [Parallel sweeps and alternatives](#parallel-sweeps-and-alternatives)
- [Basic troubleshooting commands](#basic-troubleshooting-commands)
- [Windows and IPv6](#windows-and-ipv6)
- [Reusable bounded CIDR helper](#reusable-bounded-cidr-helper)
- [Common mistakes](#common-mistakes)
- [References](#references)

## CIDR sizes and boundaries

The prefix is the number of fixed network bits. Total IPv4 addresses are `2^(32-prefix)`. For ordinary `/0` through `/30` host enumeration, omit network and broadcast. On a `/31` point-to-point link, both addresses can be endpoints; a `/32` identifies exactly one address. A tool's generated target list is a convention, not proof every listed address is a usable host in your deployment.

| Prefix | Mask | Total addresses | Conventional host enumeration |
|---|---|---:|---:|
| /32 | 255.255.255.255 | 1 | 1 |
| /31 | 255.255.255.254 | 2 | 2 |
| /30 | 255.255.255.252 | 4 | 2 |
| /29 | 255.255.255.248 | 8 | 6 |
| /28 | 255.255.255.240 | 16 | 14 |
| /27 | 255.255.255.224 | 32 | 30 |
| /26 | 255.255.255.192 | 64 | 62 |
| /25 | 255.255.255.128 | 128 | 126 |
| /24 | 255.255.255.0 | 256 | 254 |
| /23 | 255.255.254.0 | 512 | 510 |
| /22 | 255.255.252.0 | 1,024 | 1,022 |
| /21 | 255.255.248.0 | 2,048 | 2,046 |
| /20 | 255.255.240.0 | 4,096 | 4,094 |
| /19 | 255.255.224.0 | 8,192 | 8,190 |
| /18 | 255.255.192.0 | 16,384 | 16,382 |
| /17 | 255.255.128.0 | 32,768 | 32,766 |
| /16 | 255.255.0.0 | 65,536 | 65,534 |
| /15 | 255.254.0.0 | 131,072 | 131,070 |
| /14 | 255.252.0.0 | 262,144 | 262,142 |
| /13 | 255.248.0.0 | 524,288 | 524,286 |
| /12 | 255.240.0.0 | 1,048,576 | 1,048,574 |
| /11 | 255.224.0.0 | 2,097,152 | 2,097,150 |
| /10 | 255.192.0.0 | 4,194,304 | 4,194,302 |
| /9 | 255.128.0.0 | 8,388,608 | 8,388,606 |
| /8 | 255.0.0.0 | 16,777,216 | 16,777,214 |
| /7 | 254.0.0.0 | 33,554,432 | 33,554,430 |
| /6 | 252.0.0.0 | 67,108,864 | 67,108,862 |
| /5 | 248.0.0.0 | 134,217,728 | 134,217,726 |
| /4 | 240.0.0.0 | 268,435,456 | 268,435,454 |
| /3 | 224.0.0.0 | 536,870,912 | 536,870,910 |
| /2 | 192.0.0.0 | 1,073,741,824 | 1,073,741,822 |
| /1 | 128.0.0.0 | 2,147,483,648 | 2,147,483,646 |
| /0 | 0.0.0.0 | 4,294,967,296 | 4,294,967,294 |

The last column is address math, not a recommendation to sweep very large blocks or treat special-use space as ordinary unicast hosts. Prefer a scoped inventory/target list for large networks.

**Boundary example:** `10.20.30.70/28` belongs to `10.20.30.64/28`, whose ordinary hosts are `.65` through `.78`, not `.71` through `.84`. `/23` and shorter can cross octet boundaries; avoid assuming only the last octet changes.

## Literal sweep one-liners

All recipes N01–N15 run in **Bash on the host doing the probing**. Each sends one ICMP echo per address, waits up to about one second per unanswered target, prints successful addresses, and suppresses probe output. First test one address without redirecting errors so you know ping works. Sequential large sweeps can be slow. Change the whole intended range, not just the prefix label.

### N01: Probe one address — /32

```sh
for ip in 10.20.30.10; do ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** A host route has one target. Change `10.20.30.10`; there is no network/broadcast exclusion for `/32`.

### N02: Probe both endpoints — /31

```sh
for i in 0 1; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/31` contains `.0` and `.1`. Both are included for point-to-point enumeration. A range ending in `.0` is not automatically invalid.

### N03: Sweep the two ordinary hosts — /30

```sh
for i in {1..2}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/30`; excludes `.0` and `.3`.

### N04: Sweep six ordinary hosts — /29

```sh
for i in {1..6}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/29`; excludes `.0` and `.7`.

### N05: Sweep fourteen ordinary hosts — /28

```sh
for i in {1..14}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/28`; excludes `.0` and `.15`.

### N06: Sweep thirty ordinary hosts — /27

```sh
for i in {1..30}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/27`; excludes `.0` and `.31`.

### N07: Sweep sixty-two ordinary hosts — /26

```sh
for i in {1..62}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/26`; excludes `.0` and `.63`.

### N08: Sweep the lower half — /25

```sh
for i in {1..126}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/25`; excludes `.0` and `.127`.

### N09: Sweep the upper half — /25

```sh
for i in {129..254}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.128/25`; excludes `.128` and `.255`. A `/25` does not always start at `.0`.

### N10: Sweep a full /24

```sh
for i in {1..254}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.0/24`. Change the first three octets for a different aligned `/24`.

### N11: Sweep a /28 starting partway through the last octet

```sh
for i in {65..78}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** `10.20.30.64/28`. This avoids the common error of using `.1–.14` for every `/28`.

### N12: Sweep a /23 crossing two last-octet ranges

```sh
for third in 30 31; do for last in {0..255}; do ip="10.20.$third.$last"; [[ $ip == 10.20.30.0 || $ip == 10.20.31.255 ]] && continue; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done; done
```

**Use:** `10.20.30.0/23`, 510 targets. `.30.255` and `.31.0` are included: only the overall network/broadcast addresses are excluded. Change both loop and exclusion values together.

### N13: Sweep a /22 with four third-octet values

```sh
for third in {28..31}; do for last in {0..255}; do ip="10.20.$third.$last"; [[ $ip == 10.20.28.0 || $ip == 10.20.31.255 ]] && continue; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done; done
```

**Use:** `10.20.28.0/22`, 1,022 targets. Use CIDR generation below rather than manually adapting loops for larger or awkward boundaries.

### N14: Use variables for an arbitrary last-octet range

```sh
base=10.20.30; first=65; last=78; for ((i=first;i<=last;i++)); do ip="$base.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Use:** Arithmetic Bash loops expand variables correctly. `{${first}..${last}}` does not perform the equivalent brace expansion.

### N15: Add a small delay between probes

```sh
for i in {1..14}; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; sleep 0.1; done
```

**Use:** Adds 100 ms after each probe, whether or not it succeeds. Change delay/range to suit the agreed traffic budget; this is not a precise packets-per-second scheduler.

## Any-prefix CIDR recipes

### N16: Inspect a CIDR without generating targets or sending traffic

```sh
python3 -c 'import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1],strict=False); print("network:",n,"mask:",n.netmask,"last:",n.broadcast_address,"total:",n.num_addresses)' 10.20.30.70/28
```

**Run:** Local shell with Python 3. **Result:** Normalizes to `10.20.30.64/28`, total 16. **Change:** CIDR argument. `strict=False` intentionally normalizes host bits; use `strict=True` if such input should be rejected.

### N17: Generate a bounded host list from any IPv4 prefix

```sh
python3 -c 'import ipaddress,sys; n=ipaddress.IPv4Network(sys.argv[1],strict=False); n.num_addresses<=4096 or sys.exit("Scope exceeds 4096 addresses; split/review it first"); sys.stdout.writelines(str(a)+"\n" for a in n.hosts())' 10.20.30.64/28 > targets.txt
```

**Run:** Local shell. **What:** Handles `/31` and `/32` correctly and streams one IP per line. Accepts any valid prefix mathematically, but refuses blocks larger than 4,096 total addresses in this copyable version. Inspect the file before probing; a generation error may leave an empty output file.

### N18: Sweep a generated list in one loop

```sh
while IFS= read -r ip; do ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done < targets.txt
```

**Run:** The Linux probe host. **What:** Uses the reviewed list from N17; change the filename. List entries should be clean numeric addresses, one per line, without comments.

### N19: Generate and sweep one CIDR in one shell line

```sh
python3 -c 'import ipaddress,sys; n=ipaddress.IPv4Network(sys.argv[1],strict=False); n.num_addresses<=4096 or sys.exit("Scope too large"); sys.stdout.writelines(str(a)+"\n" for a in n.hosts())' 10.20.30.64/28 | while IFS= read -r ip; do ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done
```

**Run:** Linux shell with Python. **Change:** Only the CIDR for a different aligned or unaligned subnet. Use `set -o pipefail` in a Bash script when upstream generation failures must fail the whole pipeline.

### N20: Split a large authorized block into reviewable /24 subnets

```sh
python3 -c 'import ipaddress; n=ipaddress.ip_network("10.20.0.0/16"); print("\n".join(map(str,n.subnets(new_prefix=24))))'
```

**Run:** Local shell. **What:** Prints 256 subnet names and sends no packets. Change parent/prefix, ensuring the new prefix is longer than the original. Review which subnets are in scope instead of automatically probing every one.

### N21: Generate all addresses including network and broadcast for an inventory

```sh
python3 -c 'import ipaddress; n=ipaddress.ip_network("10.20.30.0/29"); print("\n".join(map(str,n)))'
```

**Run:** Local shell, generation only. **What:** Eight addresses, unlike six from `.hosts()`. Use when inspecting allocated address space; do not treat network/broadcast addresses as ordinary hosts on a broadcast subnet.

### N22: Exclude selected addresses from a target file

```sh
grep -Fvx -f excluded.txt targets.txt > targets-reviewed.txt
```

**Run:** Local shell. **What:** Exact whole-line exclusion. Put one numeric IP per line in `excluded.txt`; change paths. Review the resulting file before running N18.

### N23: Save successful replies to a file

```sh
while IFS= read -r ip; do ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done < targets.txt | tee alive.txt
```

**Run:** Probe host. **What:** Shows and saves positive responses. `tee` overwrites the output by default. “Alive” is just a filename; the list is only observed ICMP responders at this moment.

### N24: Record both success and nonresponse

```sh
while IFS= read -r ip; do if ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1; then printf '%s,reply\n' "$ip"; else printf '%s,no_reply_or_error\n' "$ip"; fi; done < targets.txt > results.csv
```

**Run:** Probe host. **What:** Records every input target. Errors are not separated from timeout in this short recipe; use the helper below for that distinction.

### N25: Compare two responder lists

```sh
LC_ALL=C sort -u previous.txt > previous.sorted
LC_ALL=C sort -u current.txt > current.sorted
LC_ALL=C comm -13 previous.sorted current.sorted
```

**Run:** Local shell, no probes. **What:** Prints responders seen now but not before. Use `comm -23` for previously seen but missing now. Lexical sorting is sufficient for set comparison even though it is not numeric IP order.

## Parallel sweeps and alternatives

### N26: Probe with at most sixteen concurrent ping processes

```sh
xargs -r -n 1 -P 16 sh -c 'ping -n -c 1 -W 1 "$1" >/dev/null 2>&1 && printf "%s\n" "$1"' sh < targets.txt
```

**Run:** Linux with GNU xargs and a numeric-IP list. **What:** Bounded concurrency; change 16. Output order is completion order. Some xargs implementations differ, and a nonzero aggregate status can reflect unanswered targets rather than a malformed command.

### N27: Use fping for a reviewed target list

```sh
fping -a -r 0 -t 1000 < targets.txt
```

**Run:** Probe host with fping installed and ICMP permissions. **What:** Emits responders, no retries, per-target timeout in milliseconds. Unreachable/errors may appear on stderr; inspect rather than hide all diagnostic output. Change list, timeout, retries.

### N28: Use fping with a CIDR directly

```sh
fping -a -r 0 -t 1000 -g 10.20.30.0/28
```

**Run:** Probe host. **What:** Lets fping generate targets. For exact `/31` and `/32` behavior across versions, use Python's explicit target list with N27 instead. Check your installed generator limits before choosing a large block.

### N29: Discover hosts without a port scan

```sh
nmap -sn -n 10.20.30.0/28
```

**Run:** Authorized probe host with Nmap. **What:** Host discovery, which can use ICMP, TCP, or local-link ARP depending on privilege/path. It is not necessarily an ICMP-only sweep. `-n` disables reverse DNS; no ordinary port scan follows.

### N30: Ask for ICMP echo discovery across a routed path

```sh
sudo nmap -sn -n -PE --disable-arp-ping 10.20.30.0/28
```

**Run:** Linux probe host with appropriate raw-packet privileges. **What:** ICMP echo-based discovery instead of automatic ARP discovery. Change CIDR. Negative results still do not establish that a host is absent.

### N31: Discover on the directly attached Ethernet segment

```sh
sudo nmap -sn -n -PR 10.20.30.0/28
```

**Run:** A host directly on that LAN. **What:** ARP discovery works only on the local link; it does not travel through SSH SOCKS, routed VPNs, or Ligolo's TUN as raw Ethernet discovery.

### N32: Check one known TCP service when ping is blocked

```sh
nc -n -z -v -w 2 10.20.30.10 443
```

**Run:** A host with a route to the destination; OpenBSD-style netcat flags. **What:** Tests a TCP connection, not HTTP/TLS validity. Change IP/port. Refusal shows a responding path but closed/rejected service; timeout is ambiguous.

### N33: Run a bounded TCP connect check through a routed Ligolo interface

```sh
nmap -sT -Pn -n -p 22,443 --max-parallelism 4 10.80.0.10
```

**Run:** Controller after the Ligolo route/tunnel works. **What:** Explicit TCP connect checks on two ports of one target; `-Pn` skips discovery and assumes it should attempt them. This is not a ping sweep and not proof a host is up just because discovery was skipped.

### N34: Probe from an authorized remote host over SSH

```sh
ssh admin@jump.example.com 'for i in 1 2 3 4; do ip="10.20.30.$i"; ping -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf "%s\n" "$ip"; done'
```

**Run:** Your workstation; the loop itself runs on the SSH server. **Why:** Tests that server's reachability. This is remote command execution with your account, not ICMP transported through a SOCKS port. Change server and range.

### N35: Retest a small responder list for packet loss

```sh
fping -C 5 -q < alive.txt
```

**Run:** Probe host. **What:** Five probes per listed address with summary/measurement output, commonly on stderr. Change count/list. Store stdout/stderr deliberately if parsing; do not assume every diagnostic is a target result.

## Basic troubleshooting commands

### N36: Show interface names and assigned addresses

```sh
ip -br address
```

**Run:** The machine you are diagnosing. **Why:** Find the real interface name/subnet instead of copying `eth0` blindly.

### N37: Show routing and the route to one target

```sh
ip route
ip route get 10.20.30.10
```

**Run:** Probe host/controller. **Why:** Confirms selected interface/gateway before a sweep. A route query does not transmit a test packet or confirm return routing.

### N38: Show local-link neighbor information

```sh
ip neigh show
```

**Run:** Local Linux host. **Why:** See already-known ARP/IPv6 neighbors. This is not a complete inventory; stale/incomplete entries need interpretation and remote subnets normally appear via a next-hop neighbor.

### N39: Test DNS separately from connectivity

```sh
getent ahosts app.internal.example
dig @10.20.0.53 app.internal.example A
```

**Run:** Host using the app. **Why:** `getent` follows system name-service configuration; direct `dig` tests the chosen resolver. Change names/address. The two need not return identical answers.

### N40: Inspect listening sockets

```sh
ss -lntup
```

**Run:** The machine that should be listening. **Why:** Diagnose a tunnel bind or service-port issue. Process details may need sudo. Listening only on `127.0.0.1` differs from a LAN-address listener.

### N41: Test HTTP and TLS with timeouts

```sh
curl --connect-timeout 3 --max-time 10 -I https://app.internal.example/
```

**Run:** Client/controller. **Why:** Tests more than TCP establishment. HEAD may be unsupported even when GET works; use the appropriate application request. Keep certificate verification enabled.

### N42: Inspect ICMP on the chosen interface

```sh
sudo tcpdump -ni eth0 -c 20 icmp
```

**Run:** Probe host or authorized router. **Why:** Distinguish requests leaving from replies returning. Change interface; stop with Ctrl-C if fewer than 20 packets arrive. Captures can contain private data.

### N43: Test a path with tracepath

```sh
tracepath -n 10.20.30.10
```

**Run:** Linux probe host with tracepath installed. **Why:** Helps inspect path/MTU behavior. Nonresponses and userspace tunnels can obscure topology; do not assume tunnel-internal hops will be visible.

### N44: Check larger IPv4 ICMP payloads without fragmentation

```sh
ping -4 -n -c 3 -W 2 -M do -s 1400 10.20.30.10
```

**Run:** Linux iputils host. **Why:** Diagnoses packet-size sensitivity; 1400 is payload, not total IP packet size. Change size/target, preserve error messages, and avoid treating one successful size as the universal path MTU.

### N45: Count and inspect a list before launching probes

```sh
wc -l targets.txt
head -5 targets.txt
tail -5 targets.txt
```

**Run:** Local shell, no network activity. **Why:** Catches an accidental `/16` instead of `/24` and wrong boundaries before sending traffic.

## Windows and IPv6

### N46: Sweep a small range with Windows ping

```powershell
1..14 | ForEach-Object { $ip="10.20.30.$_"; ping.exe -n 1 -w 1000 $ip *> $null; if ($LASTEXITCODE -eq 0) { $ip } }
```

**Run:** Windows PowerShell. **What:** One ping per address, 1000 ms timeout. Change range/base. For more reliable semantic response classification across Windows versions, prefer the .NET Ping helper in N47 rather than parsing localized command output/exit quirks.

### N47: Sweep with explicit ICMP status in PowerShell

```powershell
$probe=[System.Net.NetworkInformation.Ping]::new(); try { 1..14 | ForEach-Object { $ip="10.20.30.$_"; try { $reply=$probe.Send($ip,1000); if($reply.Status -eq 'Success') { $ip } } catch { Write-Warning "$ip : $($_.Exception.Message)" } } } finally { $probe.Dispose() }
```

**Run:** Windows PowerShell. **Why:** Checks actual reply status and reports errors. Change the range/base/timeout. This remains a sequential range example, not automatic CIDR arithmetic.

### N48: Probe an explicit IPv6 target list

```sh
while IFS= read -r ip; do ping -6 -n -c 1 -W 1 "$ip" >/dev/null 2>&1 && printf '%s\n' "$ip"; done < ipv6-targets.txt
```

**Run:** Linux host with IPv6 reachability. **Why:** Use known scoped targets rather than trying to exhaust a `/64` (over 18 quintillion addresses). Include appropriate scope/interface information for link-local addresses.

### N49: Probe a link-local IPv6 neighbor on one interface

```sh
ping -6 -n -c 3 -I eth0 fe80::1
```

**Run:** Host on that link. **What:** Uses the specified interface to disambiguate the link-local address. Change interface/neighbor; these addresses are not internet-routable.

### N50: Enumerate the two endpoints of an IPv6 /127 without probing

```sh
python3 -c 'import ipaddress; n=ipaddress.ip_network("2001:db8:20::/127"); print("\n".join(map(str,n.hosts())))'
```

**Run:** Local shell with Python. **What:** Produces two target addresses using Python's `/127` special case. `/128` produces one. Replace the documentation network with an authorized real prefix before any probes.

## Reusable bounded CIDR helper

Save the following as `cidr_ping.py` on the **Linux probe host**. It handles every IPv4 prefix mathematically, `/31` and `/32` included; a configurable size limit prevents accidentally expanding a huge range. Default mode **only prints targets**. `--run` actually probes, with bounded concurrency. No shell is used to execute IP values.

```python
#!/usr/bin/env python3
import argparse
import concurrent.futures
import ipaddress
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description="Review or ping an authorized IPv4 CIDR")
    parser.add_argument("cidr")
    parser.add_argument("--max-addresses", type=int, default=4096)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--timeout", type=int, default=1, help="Linux ping wait in seconds")
    parser.add_argument("--run", action="store_true", help="Send probes; otherwise list only")
    args = parser.parse_args()
    try:
        net = ipaddress.IPv4Network(args.cidr, strict=False)
    except ValueError as error:
        parser.error(str(error))
    if args.max_addresses < 1 or not 1 <= args.workers <= 64 or args.timeout < 1:
        parser.error("Use max-addresses>=1, workers in 1..64, timeout>=1")
    if net.num_addresses > args.max_addresses:
        parser.error(f"{net} has {net.num_addresses} addresses; review/split scope first")
    print(f"scope={net} total_addresses={net.num_addresses}", file=sys.stderr)
    if not args.run:
        for address in net.hosts():
            print(address)
        return 0
    if not sys.platform.startswith("linux"):
        parser.error("--run uses Linux iputils ping flags; list-only works elsewhere")
    ping = shutil.which("ping")
    if not ping:
        parser.error("ping is not installed or is not on PATH")

    def probe(address):
        ip = str(address)
        try:
            result = subprocess.run(
                [ping, "-n", "-c", "1", "-W", str(args.timeout), ip],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                timeout=args.timeout + 3, check=False,
            )
            if result.returncode == 0:
                return ip, "reply", ""
            if result.returncode == 1:
                return ip, "no_reply", ""
            return ip, "error", result.stderr.strip()
        except (OSError, subprocess.TimeoutExpired) as error:
            return ip, "error", str(error)

    errors = 0
    print("address,status")
    # Only a bounded window of futures is queued, even for an enlarged scope.
    hosts = iter(net.hosts())
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        pending = set()
        for _ in range(args.workers):
            address = next(hosts, None)
            if address is not None:
                pending.add(pool.submit(probe, address))
        while pending:
            completed, pending = concurrent.futures.wait(
                pending, return_when=concurrent.futures.FIRST_COMPLETED
            )
            for future in completed:
                ip, status, detail = future.result()
                print(f"{ip},{status}", flush=True)
                if status == "error":
                    errors += 1
                    print(f"{ip}: {detail}", file=sys.stderr)
                address = next(hosts, None)
                if address is not None:
                    pending.add(pool.submit(probe, address))
    return 2 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
```

```sh
# Linux/Python: inspect, then explicitly run the reviewed scope.
python3 cidr_ping.py 10.20.30.70/28
python3 cidr_ping.py 10.20.30.70/28 --run --workers 8 --timeout 1 > results.csv
# Larger authorized block: explicit override after reviewing scope; not a default.
python3 cidr_ping.py 10.20.0.0/19 --max-addresses 8192
```

Exit 2 indicates invocation/probe errors; valid no-reply results are observations, not script failures. Ctrl-C interrupts the run, though in-flight probes may take their short timeout to finish. Large scopes remain costly even with bounded memory and concurrency.

## Common mistakes

| Mistake | Fix |
|---|---|
| Treat every `/28` as `.1–.14` | Calculate the actual aligned block |
| Skip `.0` on a `/31` | Include both point-to-point endpoints |
| Skip every `.255` inside a `/23` | Exclude only the overall subnet broadcast |
| Use `for i in {$start..$end}` | Use Bash arithmetic loop or a CIDR generator |
| Launch 65,000 background pings at once | Bound worker count and review the target count |
| Declare a host dead after one timeout | Check policy, route, ARP, or a known service |
| Expect `proxychains ping` to use SSH SOCKS | SOCKS does not carry ordinary ICMP |
| Expect ARP across Ligolo/SSH | ARP is link-local Ethernet discovery |
| Redirect every error away before testing | Run one probe visibly first |
| Use Linux timeout flags on macOS/Windows | Check that platform's ping help |

## References

[Python ipaddress](https://docs.python.org/3/library/ipaddress.html), [fping manual](https://www.fping.org/fping.8.html), [Nmap host discovery](https://nmap.org/book/host-discovery-controls.html), and [iputils project](https://github.com/iputils/iputils). Prefix arithmetic and helper list-only behavior can be checked offline; successful network discovery depends on routes, permissions, and response policy.
