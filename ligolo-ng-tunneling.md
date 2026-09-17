# Ligolo-ng Tunneling — Practical Recipes and Eight-Agent Chains

[Index](README.md) · [SSH tunneling](ssh-tunneling.md) · [Network commands and sweeps](network-basics-ping-sweeps.md)

For authorized network administration and labs. Examples use a Linux controller **O** and managed agent machines **B1–B8**. Download matching proxy/agent builds from the official project. Names `proxy` and `agent` below refer to the downloaded binaries, which may have longer release filenames. Check `./proxy -h`, `./agent -h`, and console `help` against your installed release. The documented examples and release source were reviewed for v0.9.1-style operation.

## Contents

- [How the directions work](#how-the-directions-work)
- [First connection](#first-connection)
- [Routes and application examples](#routes-and-application-examples)
- [Listeners and reverse access](#listeners-and-reverse-access)
- [Bind connections and SOCKS transport](#bind-connections-and-socks-transport)
- [Eight agents deep](#eight-agents-deep)
- [Troubleshooting and cleanup](#troubleshooting-and-cleanup)
- [References](#references)

## How the directions work

Ligolo-ng is a routed userspace tunnel, not an SSH server. It does not implement SSH's `-L`, `-R`, and `-D` flags. Choose the corresponding path:

| Need | Ligolo approach | Run location |
|---|---|---|
| O reaches networks visible from B | TUN route through B's selected session | O shell plus O proxy console |
| B initiates the agent transport | Agent `-connect` to proxy or relay listener | B shell |
| O initiates agent transport | Agent `-bind`, console `connect_agent` | B shell plus O console |
| A machine near B reaches a service on O | Listener on B, destination reached from O | O console, select B |
| Many services on B's network | Route their subnet through B | O shell |
| Agent transport through an existing SOCKS service | Agent `-proxy` on supported releases | B shell |
| A SOCKS listener for arbitrary apps | Use SSH `-D` separately if required | See SSH guide |

**O shell** means a Linux terminal on the controller. **O console** means commands typed inside the running Ligolo proxy. **B shell** means the operating-system terminal on that agent machine. Console `session` opens an interactive selector: choose the named machine, not an assumed fixed numeric ID.

TUN provides a convenient routed interface, but this is not an unrestricted raw-packet VPN. TCP is implemented using connections from the agent; UDP and ICMP echo have their own support/limitations. ARP, arbitrary raw probes, traceroute behavior, and OS fingerprinting should not be assumed equivalent to a direct Ethernet link. Use application tests and modest TCP connect checks for validation.

## First connection

### LG01: Check versions before mixing binaries

```sh
# O shell
./proxy -version
./proxy -h
# B1 shell
./agent -version
./agent -h
```

**Why:** Helps distinguish syntax mismatch from a networking failure. Change binary paths. Read local help rather than copying outdated aliases or guessing flags.

### LG02: Create an operator-owned Linux TUN interface

```sh
# O shell, replace alice with the account running proxy
sudo ip tuntap add dev lig1 mode tun user alice
sudo ip link set dev lig1 up
```

**Why:** Separates privileged interface provisioning from the proxy process. Run once for a new interface. Ordinary application access through the agent usually does not require administrator privileges there; creating/managing O's TUN and routes does.

### LG03: Start the controller with pinned self-signed TLS

```sh
# O shell; this address must actually belong to O
./proxy -selfcert -laddr 192.0.2.10:11601
```

```text
# O console
certificate_fingerprint
```

**Why:** Starts transport and prints the certificate fingerprint. Securely convey that fingerprint to the agent operator. Replace O's address; permit TCP 11601 from only intended agents/relays. Binding only an external address matters when using later relay listeners: use that address as their destination, or use LG04's loopback arrangement.

### LG04: Listen on all IPv4 interfaces when the topology needs loopback relays

```sh
# O shell: alternative to LG03, not an additional proxy on the same port
./proxy -selfcert -laddr 0.0.0.0:11601
```

**Why:** Allows both incoming B1 and listener relays targeting O's `127.0.0.1:11601`. Restrict external exposure with O's firewall. This is the proxy binding used by the eight-agent worked example.

### LG05: Connect the first agent with certificate pinning

```sh
# B1 Bash shell; replace the placeholder with O's actual hex fingerprint
FP='REPLACE_WITH_PROXY_SHA256_FINGERPRINT'
./agent -connect 192.0.2.10:11601 -accept-fingerprint "$FP"
```

**Why:** B1 initiates TCP/TLS to O and checks the pinned proxy certificate. Change controller address/fingerprint. The placeholder is intentionally invalid. A fingerprint mismatch should lead to certificate inspection, not a blanket verification bypass.

### LG06: Select B1 and start its network tunnel

```text
# O console: select B1 when prompted
session
ifconfig
tunnel_start --tun lig1
```

**Why:** Associates B1 with the TUN you provisioned on O. `ifconfig` here shows agent network information, not O's interfaces. Check the selected session before starting the tunnel.

### LG07: Route one target first

```sh
# O shell
sudo ip route add 10.20.0.20/32 dev lig1
ip route get 10.20.0.20
curl --connect-timeout 3 --max-time 10 http://10.20.0.20:8080/
```

**Why:** A narrow host route limits accidental traffic diversion while testing. Target must be reachable from B1. Change IP/port/path; route creation is not proof of application access.

### LG08: Use a publicly trusted proxy certificate

```sh
# O shell: alternative proxy startup with provisioned matching cert/key
./proxy -laddr 192.0.2.10:11601 -certfile ./certs/proxy.crt -keyfile ./certs/proxy.key
# B1 shell: the hostname must match the cert and resolve to O
./agent -connect proxy.example.com:11601
```

**Why:** Uses normal certificate validation when the agent trusts the issuer. A custom CA needs actual agent/platform trust provisioning; merely supplying a certificate file to the proxy does not establish agent trust. Keep the private key private.

## Routes and application examples

### LG09: Route a whole authorized subnet

```sh
# O shell; after validating the selected B1 tunnel
sudo ip route add 10.20.0.0/24 dev lig1
ip route get 10.20.0.53
```

**Why:** Applications on O can now reach that subnet using ordinary destinations. They do not need proxychains. Existing more-specific routes can take precedence. Change subnet/interface; record your previous routing before edits.

### LG10: Add several distinct reachable networks

```sh
# O shell; B1 must reach every listed network
sudo ip route add 10.20.0.0/24 dev lig1
sudo ip route add 10.21.0.0/24 dev lig1
sudo ip route add 10.22.0.25/32 dev lig1
```

**Why:** One agent can serve multiple networks if its own routes and policy permit them. Do not add duplicate entries from earlier recipes; inspect `ip route` first.

### LG11: Use managed route creation where installed console supports it

```text
# O console; requires permission to manage O's networking
interface_create --name ligmanaged
interface_add_route --name ligmanaged --route 10.20.0.0/24
session
tunnel_start --tun ligmanaged
```

**Why:** Alternative to manual Linux TUN/route provisioning. Choose B1 in the selector. Local console help is authoritative for command names across releases; do not combine managed/manual creation of the same interface. Creating routes may also save them in Ligolo configuration.

### LG12: Test HTTP on the far-side LAN

```sh
# O shell
curl --connect-timeout 3 --max-time 10 http://10.20.0.20:8080/health
```

**Why:** Checks a real application response through the selected route. Change endpoint. An HTTP 401 may prove the path works while indicating that application authentication is still required.

### LG13: Preserve a target's HTTPS identity while using its routed address

```sh
# O shell
curl --resolve app.internal.example:443:10.20.0.20 https://app.internal.example/
```

**Why:** Supplies a one-command DNS mapping while retaining SNI/name verification. Change hostname/address to match the real certificate. Do not disable TLS verification to compensate for a name mismatch.

### LG14: Query a far-side DNS server explicitly

```sh
# O shell
dig @10.20.0.53 app.internal.example A
dig +tcp @10.20.0.53 app.internal.example A
```

**Why:** Tests both UDP and TCP DNS directly. Route the resolver too. Ligolo does not automatically rewrite O's system resolver just because you started a tunnel.

### LG15: Use SSH over the routed tunnel

```sh
# O shell
ssh admin@10.20.0.25
```

**Why:** Normal SSH connects through O's selected TUN route. Verify host keys and authenticate normally. Once reachable, this host can become an SSH forwarding endpoint too, but that is a distinct session.

### LG16: Test one ICMP echo destination

```sh
# O shell
ping -n -c 3 -W 2 10.20.0.20
```

**Why:** A supported echo test, subject to permissions and target response policy. A TCP-accessible host may still decline ping. Do not extrapolate support for arbitrary ICMP/raw protocols from a working echo request.

### LG17: Perform a small, scoped TCP connect check

```sh
# O shell
nmap -sT -Pn -n -p 22,443 --max-parallelism 4 10.20.0.20
```

**Why:** Uses connection-oriented testing to two known service ports. `-Pn` skips discovery rather than proving a host exists. Target must already route through the chosen agent. Keep the scope/traffic budget explicit.

### LG18: Access a service bound only to the agent's loopback

```sh
# O shell; selected B1 tunnel owns lig1
sudo ip route add 240.0.0.1/32 dev lig1
curl http://240.0.0.1:8080/
```

**Why:** Ligolo's documented special address handling maps this routed destination to the selected agent's loopback. This is not a real private network behind B1. Never route the entire special /4 merely to test one service.

### LG19: Keep different agents' loopback access distinct

```sh
# O shell: two already-working tunnels
sudo ip route add 240.0.0.1/32 dev lig1
sudo ip route add 240.0.0.2/32 dev lig2
curl http://240.0.0.1:8080/
curl http://240.0.0.2:8080/
```

**Why:** Each synthetic destination selects a different TUN, hence a different agent loopback. Confirm your release's documented special-address behavior. Do not add the first route twice if LG18 already created it.

### LG20: Handle overlapping remote subnets deliberately

```sh
# O shell: choose ONE path for this specific host after inspecting existing routes
sudo ip route add 10.20.0.20/32 dev lig2
ip route get 10.20.0.20
```

**Why:** A /32 can override a less-specific /24 path, but cannot distinguish two simultaneous applications targeting the same IP through different agents. For genuinely overlapping networks, use separate controller network namespaces/VMs or a planned addressing/routing design. Do not install equal competing routes and assume session selection changes OS routing.

## Listeners and reverse access

Listeners bind **on the selected agent**, but `--to` is reached **from O**, the proxy host. This distinction is essential for both reverse application access and chained agent connections.

### LG21: Send a B1-local request to O's web application

```text
# O console, select B1 first
session
listener_add --addr 127.0.0.1:18080 --to 127.0.0.1:8080 --tcp
```

```sh
# B1 shell; O already runs an HTTP app on O:8080
curl http://127.0.0.1:18080/
```

**Why:** A reverse fixed-service path. The two loopbacks refer to different hosts: `--addr` belongs to B1, `--to` to O. Change ports; listener does not create the web application itself.

### LG22: Let a downstream machine reach a controller-side service

```text
# O console with B1 selected; B1 owns 10.11.0.1
listener_add --addr 10.11.0.1:18080 --to 127.0.0.1:8080 --tcp
```

```sh
# B2 shell on B1's downstream network
curl http://10.11.0.1:18080/
```

**Why:** Exposes O's app through one B1 interface. B1's host firewall must permit the intended source. Prefer this address-specific bind over all interfaces and retain application authentication.

### LG23: Forward to another service reachable from O

```text
# O console with B1 selected
listener_add --addr 10.11.0.1:15432 --to 10.50.0.20:5432 --tcp
```

**Why:** Downstream clients connect to B1:15432; O then reaches its own-side database host. Change addresses/ports. `--to 10.50.0.20` is not automatically resolved/reached from B1.

### LG24: Forward a UDP application deliberately

```text
# O console with B1 selected
listener_add --addr 10.11.0.1:1053 --to 127.0.0.1:5353 --udp
```

**Why:** Relays a chosen UDP service to one already listening on O. Test with the application's real UDP client; TCP curl is not the right test. This is not arbitrary bidirectional IP forwarding or a guarantee every UDP protocol's timing/association behavior will work.

### LG25: Inspect listeners and remove the selected one

```text
# O console
listener_list
listener_stop
```

**Why:** Inspect and then use the interactive selector to stop the intended listener. Verify its agent/address before confirming. Stopping a relay listener can also disconnect deeper agents using it; clean up from the deepest level backward.

### LG26: Use a loopback-only relay for a second agent transported by SSH

```text
# O console, B1 selected
listener_add --addr 127.0.0.1:4444 --to 127.0.0.1:11601 --tcp
```

```sh
# B2 shell: keep this SSH local forward running
ssh -NT -L 127.0.0.1:14444:127.0.0.1:4444 admin@10.11.0.1
# B2 second shell: FP is O's proxy fingerprint
./agent -connect 127.0.0.1:14444 -accept-fingerprint "$FP"
```

**Why:** B2 reaches a B1 loopback listener through an authorized SSH session without exposing that listener to the whole downstream LAN. O must accept the listener destination on its loopback 11601, as in LG04. Change addresses/ports and verify the SSH host key.

## Bind connections and SOCKS transport

### LG27: Agent listens instead of connecting outward

```sh
# B1 shell, on an assigned address reachable from O
./agent -bind 10.20.0.5:4444
```

```text
# O console
connect_agent --ip 10.20.0.5:4444
```

**Why:** Reverses who initiates the transport TCP connection. Compare the presented certificate fingerprint with the one printed on B1 before accepting. Restrict B1's listener with its host firewall. A bind agent does not by itself create routes on O.

### LG28: Pin a bind agent's certificate explicitly

```text
# O console; replace the invalid placeholder with B1's printed fingerprint
connect_agent --ip 10.20.0.5:4444 --accept-fingerprint REPLACE_WITH_AGENT_SHA256_FINGERPRINT
```

**Why:** On supported releases, avoids a trust decision based only on an unauthenticated prompt. This pin is **the bind agent's fingerprint**, not O's usual proxy fingerprint. Recheck after any certificate regeneration.

### LG29: Reach a bind agent over an existing earlier tunnel

```sh
# O shell: B1/lig1 can reach B2's bind address
sudo ip route add 10.11.0.2/32 dev lig1
# B2 shell
./agent -bind 10.11.0.2:4444
```

```text
# O console: verify B2's bind fingerprint when prompted
connect_agent --ip 10.11.0.2:4444
```

**Why:** O uses B1's routed path to establish a separate B2 session. Once selected, give B2 its own `lig2` tunnel/routes. Preserve the B2 transport host route through B1; redirecting it into B2's own tunnel can create a routing dependency loop.

### LG30: Carry an agent's outgoing transport through SOCKS

```sh
# B1 shell, v0.9.1-style agent flag; SOCKS must already listen on B1
./agent -connect 192.0.2.10:11601 -proxy socks5://127.0.0.1:1080 -accept-fingerprint "$FP"
```

**Why:** SOCKS is only the transport path from B1 toward O. It does not turn Ligolo into a SOCKS listener for O's apps. Some older documentation uses `--socks`; check the actual agent help. Avoid putting real proxy passwords into command history/process arguments.

### LG31: Create that SOCKS transport with an authorized SSH relay

```sh
# B1 shell, separate foreground terminal; relay can reach O
ssh -NT -D 127.0.0.1:1080 relayuser@relay.example.com
```

**Why:** Supplies the SOCKS service used in LG30. Both SSH transport and Ligolo agent must remain running. O's certificate pin still refers to O despite the intermediary relay.

### LG32: Retry initial connection errors explicitly

```sh
# Agent shell, supported v0.9.1 flags
./agent -connect 192.0.2.10:11601 -accept-fingerprint "$FP" -retry -retry-delay 10
```

**Why:** Waits and retries initial failure rather than immediately ending. This is not a durable service installation. Stop the process when the exercise/admin task ends, and do not use retries to ignore a certificate mismatch.

### LG33: Bound reconnect attempts after a dropped session

```sh
# Agent shell
./agent -connect 192.0.2.10:11601 -accept-fingerprint "$FP" -reconnect=true -reconnect-delay 20 -reconnect-timeout 300
```

**Why:** Makes reconnect policy explicit on releases supporting these options. Chained listener restoration/session recovery remains version-dependent; verify listeners, interfaces, and routes after reconnect rather than assuming every downstream session recovered.

## Eight agents deep

**Meaning:** Eight remote boxes B1–B8, with an agent on each. O runs one proxy. You already have authorized OS access to start each agent; this guide supplies connectivity, not exploitation or credential acquisition. Each adjacent pair can communicate on the lab link below. Application network `10.80.0.0/24` is reachable from B8.

```text
O proxy TCP 11601
   ^
   | B1 outbound transport
  B1 <-- B2 <-- B3 <-- B4 <-- B5 <-- B6 <-- B7 <-- B8
       Agent connections go to the preceding box's TCP 4444 listener.
       Each listener relays through its own session to O:11601.

O application -> lig8 -> B8 -> service 10.80.0.10:443
```

| Agent | Its upstream connection destination | Downstream listener address | O TUN | Example application network visible from agent |
|---|---|---|---|---|
| B1 | 192.0.2.10:11601 | 10.11.0.1:4444 | lig1 | 10.11.0.0/24 |
| B2 | 10.11.0.1:4444 | 10.12.0.1:4444 | lig2 | 10.12.0.0/24 |
| B3 | 10.12.0.1:4444 | 10.13.0.1:4444 | lig3 | 10.13.0.0/24 |
| B4 | 10.13.0.1:4444 | 10.14.0.1:4444 | lig4 | 10.14.0.0/24 |
| B5 | 10.14.0.1:4444 | 10.15.0.1:4444 | lig5 | 10.15.0.0/24 |
| B6 | 10.15.0.1:4444 | 10.16.0.1:4444 | lig6 | 10.16.0.0/24 |
| B7 | 10.16.0.1:4444 | 10.17.0.1:4444 | lig7 | 10.17.0.0/24 |
| B8 | 10.17.0.1:4444 | None needed | lig8 | 10.80.0.0/24 |

### Prepare O and B1

```sh
# O shell, provisioning account name changed to your actual operator
for i in 1 2 3 4 5 6 7 8; do sudo ip tuntap add dev "lig$i" mode tun user alice; sudo ip link set dev "lig$i" up; done
# O shell: proxy, kept running
./proxy -selfcert -laddr 0.0.0.0:11601
```

In O console, run `certificate_fingerprint` and securely provide the resulting fingerprint to every agent operator. On **each agent shell**, define `FP` to that actual hex value before using the commands below. All eight authenticate **O's same proxy certificate**: intermediate listeners relay the transport rather than issuing replacement certificates.

```sh
# B1 shell
FP='REPLACE_WITH_PROXY_SHA256_FINGERPRINT'
./agent -connect 192.0.2.10:11601 -accept-fingerprint "$FP"
```

Provisioning loop is intended only for new unused interface names; do not ignore creation errors or reuse somebody else's TUN. Firewall O's listener to the intended upstream connection source. Each agent must actually own its stated downstream listener IP.

### Add B2 through B1

```text
# O console: session selector -> B1
session
tunnel_start --tun lig1
listener_add --addr 10.11.0.1:4444 --to 127.0.0.1:11601 --tcp
listener_list
```

```sh
# B2 shell; FP already set to O's fingerprint
./agent -connect 10.11.0.1:4444 -accept-fingerprint "$FP"
```

**Check:** B2 appears as a distinct session in O console. B1 firewall must permit TCP 4444 from B2's upstream-link address. There is no requirement to enable general IP forwarding on B1 merely to relay this listener's transport.

### Add B3 through B2

```text
# O console: select B2
session
tunnel_start --tun lig2
listener_add --addr 10.12.0.1:4444 --to 127.0.0.1:11601 --tcp
```

```sh
# B3 shell
./agent -connect 10.12.0.1:4444 -accept-fingerprint "$FP"
```

**Check:** B3 connected before continuing. The `--to` loopback is still O's, not B1's or B2's. B2's existing session carries the relay back toward O through B1.

### Add B4 through B3

```text
# O console: select B3
session
tunnel_start --tun lig3
listener_add --addr 10.13.0.1:4444 --to 127.0.0.1:11601 --tcp
```

```sh
# B4 shell
./agent -connect 10.13.0.1:4444 -accept-fingerprint "$FP"
```

**Check:** B4 session identity and B3's listener, not merely whether B1 remains online.

### Add B5 through B4

```text
# O console: select B4
session
tunnel_start --tun lig4
listener_add --addr 10.14.0.1:4444 --to 127.0.0.1:11601 --tcp
```

```sh
# B5 shell
./agent -connect 10.14.0.1:4444 -accept-fingerprint "$FP"
```

**Check:** If connection fails here, examine B5→B4 TCP reachability and B4's session/listener before recreating earlier working links.

### Add B6 through B5

```text
# O console: select B5
session
tunnel_start --tun lig5
listener_add --addr 10.15.0.1:4444 --to 127.0.0.1:11601 --tcp
```

```sh
# B6 shell
./agent -connect 10.15.0.1:4444 -accept-fingerprint "$FP"
```

**Check:** B6 should be a new session; do not assume its ID equals six if agents connected/reconnected in a different order.

### Add B7 through B6

```text
# O console: select B6
session
tunnel_start --tun lig6
listener_add --addr 10.16.0.1:4444 --to 127.0.0.1:11601 --tcp
```

```sh
# B7 shell
./agent -connect 10.16.0.1:4444 -accept-fingerprint "$FP"
```

**Check:** Inspect listener-specific failures/port conflicts on B6. Another process using TCP 4444 prevents that bind.

### Add B8 through B7 and start its application tunnel

```text
# O console: select B7
session
tunnel_start --tun lig7
listener_add --addr 10.17.0.1:4444 --to 127.0.0.1:11601 --tcp
```

```sh
# B8 shell
./agent -connect 10.17.0.1:4444 -accept-fingerprint "$FP"
```

```text
# O console: now select B8
session
ifconfig
tunnel_start --tun lig8
```

**Check:** B8's own route/firewall can reach the final application. Eight nested relays add overhead and dependencies; there is no promise of a universal supported performance limit. Prefer the shortest approved path that meets your topology needs.

### Install explicit application routes on O

```sh
# O shell: independent non-overlapping routes for this worked lab
sudo ip route add 10.11.0.0/24 dev lig1
sudo ip route add 10.12.0.0/24 dev lig2
sudo ip route add 10.13.0.0/24 dev lig3
sudo ip route add 10.14.0.0/24 dev lig4
sudo ip route add 10.15.0.0/24 dev lig5
sudo ip route add 10.16.0.0/24 dev lig6
sudo ip route add 10.17.0.0/24 dev lig7
sudo ip route add 10.80.0.0/24 dev lig8
ip route get 10.80.0.10
```

O should see `lig8` selected for the final application. Each listed agent must genuinely reach the application network assigned to it. Agent-to-predecessor transport runs on those agent hosts; these controller routes are for O's application traffic. Do not route O's own proxy endpoint into a dependent tunnel or add a blanket default route through the chain.

### Use applications eight agents deep

```sh
# O shell, after B8/lig8 route validation
curl --resolve app.internal.example:443:10.80.0.10 https://app.internal.example/
ssh admin@10.80.0.25
dig @10.80.0.53 app.internal.example A
ping -n -c 3 -W 2 10.80.0.10
```

These are independent tests of HTTPS, SSH, DNS, and supported ICMP echo. Change targets to authorized services. They run on O without SOCKS wrappers; far-side connections use B8's reachability. A target rejecting one protocol may still accept another.

### Bring a B8-side request back to O

```text
# O console, B8 selected; O already runs an HTTP app at 127.0.0.1:8080
listener_add --addr 127.0.0.1:18080 --to 127.0.0.1:8080 --tcp
```

```sh
# B8 shell
curl http://127.0.0.1:18080/
```

This reverse fixed-service path uses B8's session over the established relay chain. It does not require adding eight more application listeners. To allow another host near B8, bind only B8's appropriate LAN address and restrict permitted sources there.

## Troubleshooting and cleanup

### LG34: Check route and interface on the controller first

```sh
# O shell
ip -br link
ip route get 10.80.0.10
ip route show dev lig8
```

**Why:** Session selection in the console does not automatically rewrite every manual OS route. If the route selects `lig1`, application traffic will not magically use B8 just because B8 is selected for the next console command.

### LG35: Compare controller capture with the agent's direct application test

```sh
# O shell
sudo tcpdump -ni lig8 -c 20 'host 10.80.0.10 and tcp port 443'
# B8 shell, independent direct TCP diagnostic
nc -n -z -v -w 3 10.80.0.10 443
```

**Why:** A failed direct B8→application path is not fixed by rebuilding earlier transport relays. Captures can contain private traffic; keep them scoped. Netcat option support varies.

### LG36: Stop an application tunnel, then remove its manual route

```text
# O console: session selector -> B8
session
tunnel_stop
```

```sh
# O shell: only the route you created for this exercise
sudo ip route del 10.80.0.0/24 dev lig8
```

**Why:** Stops B8 application tunneling and removes the manual path. Tunnel stop is distinct from terminating the agent connection or removing a relay listener. Managed/persisted routes need corresponding configuration cleanup, too.

### LG37: Tear down the eight-agent lab from deepest to earliest

1. Stop B8 application traffic and its optional reverse application listener.
2. Stop B8's agent process on B8; stop its tunnel/remove O's B8 routes.
3. Stop the B7 listener that admitted B8, selecting its exact address in `listener_stop`.
4. Repeat for B7, B6, B5, B4, B3, and B2, removing their routes/tunnels and predecessor relay listeners.
5. Stop B1 last, then the O proxy if no other authorized sessions depend on it.
6. Remove only the exercise-owned unused TUNs and review any saved configuration for auto-restoration.

```sh
# O shell AFTER dependent processes/tunnels have ended:
sudo ip link delete dev lig8
# Repeat for the other exercise-owned TUN names only after checking ownership/use.
```

**Why:** Stopping B1 first collapses every dependent connection and makes orderly cleanup harder. Deleting an interface is a mutation, not an inspection step. Do not delete unrelated interfaces or overwrite the original routing snapshot blindly.

### LG38: Diagnose a depth-specific failure with a small checklist

| Symptom | Check next |
|---|---|
| Agent never appears | Actual connect endpoint, TCP reachability, proxy/listener bind, TLS pin |
| B4 connected, B5 absent | B4 selected for listener creation, its assigned downstream IP, B5's connect destination |
| Listener creation fails | Address belongs to selected agent, port unused, host policy, correct session |
| Session alive, target unreachable | O route/TUN association, target reachable directly from chosen agent |
| TCP works, ping fails | Echo permissions/filtering; not proof the whole tunnel is broken |
| DNS direct query works, application name fails | O resolver configuration; Ligolo does not automatically configure DNS |
| Another agent's network answers | Wrong route/interface association or overlapping networks |
| SOCKS flag rejected | Installed release uses different transport flags; inspect `agent -h` |
| Reconnect succeeds but deep chain fails | Relay listeners/session mappings were not fully restored |
| Loopback service unreachable | Synthetic host route assigned to correct agent TUN, actual agent listener |
| Slow at depth eight | Nested transport latency, loss, concurrency, timeouts, CPU; reduce workload/depth |

## References

- [Ligolo-ng quickstart](https://docs.ligolo.ng/Quickstart/) — TLS and initial tunneling.
- [Listeners](https://docs.ligolo.ng/Listeners/) — agent binding and controller-side destinations.
- [Advanced pivot example](https://docs.ligolo.ng/sample/double/) — recursive transport relay pattern.
- [Bind connections](https://docs.ligolo.ng/Bind/) — controller-initiated transport.
- [Agent loopback access](https://docs.ligolo.ng/Localhost/) — synthetic special addresses.
- [Project and releases](https://github.com/nicocha30/ligolo-ng) — official binaries/source.
- [v0.9.1 agent source](https://github.com/nicocha30/ligolo-ng/blob/v0.9.1/cmd/agent/main.go) — release-specific transport flags.

The eight-agent topology is an original extension of the documented relay pattern. It is not a live-tested eight-agent deployment or a guarantee every release/platform supports identical behavior. Link/structure checks are offline; actual operation requires the named links, permissions, and services.
