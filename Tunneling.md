# SSH Tunneling — Local, Remote, Dynamic, and Eight-Box Chains

[Index](README.md) · [Ping/network commands](network-basics-ping-sweeps.md) · [Ligolo-ng](ligolo-ng-tunneling.md)

**Scope:** OpenSSH forwarding for authorized administration and lab networks. Includes local/remote TCP, local/remote SOCKS, jump chains, Unix sockets, TUN/TAP, X11, restricted forwarding, testing, and cleanup. Extensions and policy vary by installed OpenSSH/platform; this is not a claim that every SSH product supports every mode.

## Contents

- [Which side means what](#which-side-means-what)
- [Local forwards](#local-forwards)
- [Remote forwards](#remote-forwards)
- [Dynamic SOCKS forwarding](#dynamic-socks-forwarding)
- [Jump hosts and control sessions](#jump-hosts-and-control-sessions)
- [Other forwarding modes](#other-forwarding-modes)
- [Server policy and diagnostics](#server-policy-and-diagnostics)
- [Eight-box worked topology](#eight-box-worked-topology)
- [Troubleshooting by symptom](#troubleshooting-by-symptom)
- [References and testing limits](#references-and-testing-limits)

## Which side means what

**O** = your workstation running the `ssh` client. **B** = the SSH server you authenticate to. **T** = the final application target. Unless a recipe explicitly says otherwise, type SSH commands on **O**, keep them running in a terminal, and test from a second terminal.

| Mode | Listener | Final target connection originates from | Typical purpose |
|---|---|---|---|
| `-L` local | O | B | Reach a service B can access |
| `-R` remote | B | O | Let B reach a service O can access |
| `-D` local dynamic | O | B | SOCKS clients on O select TCP destinations |
| `-R PORT` remote dynamic | B | O | SOCKS clients on B select TCP destinations through O |
| `-J` jump chain | Transport through named SSH servers | Final SSH endpoint for its forwards | Reach a deeper SSH server |
| `-W HOST:PORT` | Standard input/output stream | SSH server | ProxyCommand building block |
| `-w` TUN/TAP | Virtual network interface | Routing-dependent | Layer-3/Layer-2 networking with privileges/policy |

```text
Local:   app on O -> O:15432 -> encrypted SSH -> B -> T:5432
Remote:  app on B -> B:18080 -> encrypted SSH -> O -> T:8080
SOCKS:   app chooses T -> SOCKS on O -> SSH -> B -> T:chosen-port
```

With `-L`, destination `127.0.0.1` is **B's** loopback. With `-R`, destination `127.0.0.1` is **O's** loopback. The address before the listening port is the listener's bind address; it is not the target address.

Useful common flags: `-N` no remote command, `-T` no pseudo-terminal, `-p` SSH server port, `-i` client private key, `-v`/`-vvv` diagnostics. `ExitOnForwardFailure=yes` catches forwarding setup errors, not future failure to reach the application target. `ServerAliveInterval=30` and `ServerAliveCountMax=3` detect an unresponsive connection; they do not recreate it automatically.

Bind examples to loopback by default. Other local users can often access loopback listeners; loopback is not application authentication. Preserve host-key and target TLS verification. Ordinary SSH port/SOCKS forwards carry TCP, not generic UDP or ICMP. Agent forwarding (`-A`) is unrelated to network forwarding and is not required for ProxyJump.

## Local forwards

### SSH01: Reach a database visible from the SSH server

```sh
ssh -NT -o ExitOnForwardFailure=yes -L 127.0.0.1:15432:10.20.0.20:5432 admin@jump.example.com
```

**Run on O.** Connect your database client on O to `127.0.0.1:15432`. B makes the connection to `10.20.0.20:5432`. Change local port, target IP/port, and SSH account. No database credentials are bypassed.

### SSH02: Reach a service bound to the SSH server's loopback

```sh
ssh -NT -L 127.0.0.1:18080:127.0.0.1:8080 admin@jump.example.com
```

**Run on O.** O's port 18080 reaches **B's** loopback port 8080. Useful for a privately bound web dashboard. It does not target O's port 8080.

### SSH03: Test a locally forwarded HTTP service

```sh
curl --connect-timeout 3 --max-time 10 http://127.0.0.1:18080/
```

**Run on O in another terminal while SSH02 runs.** Tests the application, not just listener existence. Change port/path; preserve any required authentication.

### SSH04: Preserve HTTPS hostname verification through a local port

```sh
ssh -NT -L 127.0.0.1:18443:10.20.0.20:443 admin@jump.example.com
```

```sh
curl --connect-to app.internal.example:443:127.0.0.1:18443 https://app.internal.example/
```

**Run both on O, in separate terminals.** Curl connects to the local listener but retains the original URL hostname for TLS/HTTP. Change hostname/target. The server certificate still needs a trusted issuer and matching name; do not use `-k` as a routine workaround.

### SSH05: Forward several services over one SSH connection

```sh
ssh -NT -o ExitOnForwardFailure=yes -L 127.0.0.1:15432:10.20.0.20:5432 -L 127.0.0.1:16379:10.20.0.21:6379 -L 127.0.0.1:18080:10.20.0.22:8080 admin@jump.example.com
```

**Run on O.** Each local port has a different destination reached from B. Change each mapping independently. Setup success does not guarantee all three applications are reachable.

### SSH06: Use a nonstandard SSH port and a specific key

```sh
ssh -NT -p 2222 -i ~/.ssh/lab_ed25519 -o IdentitiesOnly=yes -L 127.0.0.1:15432:10.20.0.20:5432 admin@jump.example.com
```

**Run on O.** `-p 2222` is the SSH transport port, not either application port. The private key stays on O; change path/account/endpoint as appropriate.

### SSH07: Reach an internal SSH service through a local forwarded port

```sh
ssh -NT -L 127.0.0.1:10022:10.20.0.25:22 admin@jump.example.com
```

```sh
ssh -p 10022 -o HostKeyAlias=internal-server admin@127.0.0.1
```

**Run both on O.** First establishes the tunnel; second independently authenticates to the internal server. Verify the target host key under the chosen alias. Prefer ProxyJump when you only need an SSH connection rather than a reusable local port.

### SSH08: Deliberately share a local forward with a trusted LAN

```sh
ssh -NT -g -L 192.0.2.10:15432:10.20.0.20:5432 admin@jump.example.com
```

**Run on O, which must own `192.0.2.10`.** A permitted LAN client connects to O's address/port. Bind only the intended interface and restrict incoming sources with O's firewall. This exposes the target service through O and does not add SOCKS/database authentication.

### SSH09: Use an IPv6 destination through a local forward

```sh
ssh -NT -L '127.0.0.1:18443:[2001:db8:20::20]:443' admin@jump.example.com
```

**Run on O.** B needs IPv6 reachability to the target. Brackets distinguish IPv6 colons from forwarding separators. Replace the documentation address.

### SSH10: Bind the local listener to IPv6 loopback

```sh
ssh -NT -L '[::1]:18080:10.20.0.20:8080' admin@jump.example.com
```

**Run on O.** Applications use `[::1]:18080`; the remote target here is IPv4. Listener and transport/target address families can differ. Change bind/port deliberately.

## Remote forwards

### SSH11: Let the SSH server reach a web service on your workstation

```sh
ssh -NT -o ExitOnForwardFailure=yes -R 127.0.0.1:18080:127.0.0.1:8080 admin@jump.example.com
```

**Run on O.** **Test on B:** `curl http://127.0.0.1:18080/`. B's listener forwards to O's loopback 8080. Keep the SSH client running on O and the application running there too.

### SSH12: Let the SSH server reach a separate service on your LAN

```sh
ssh -NT -R 127.0.0.1:15432:10.50.0.20:5432 admin@jump.example.com
```

**Run on O.** B's loopback 15432 reaches `10.50.0.20:5432` **from O**. Useful when O is the authorized network bridge to that LAN. B does not need a direct route to the database.

### SSH13: Make a remote forward available on one remote interface

```sh
ssh -NT -o ExitOnForwardFailure=yes -R 10.20.0.5:18080:127.0.0.1:8080 admin@jump.example.com
```

**Run on O; B must own `10.20.0.5`.** Requires B's administrator to allow the requested bind, typically `GatewayPorts clientspecified`, plus incoming firewall permission. Inspect the real listener on B; server policy can reject or alter a requested bind.

### SSH14: Expose a remote forward on all remote IPv4 interfaces intentionally

```sh
ssh -NT -o ExitOnForwardFailure=yes -R 0.0.0.0:18080:127.0.0.1:8080 admin@jump.example.com
```

**Run on O.** Requires an appropriate B `GatewayPorts` policy. This is much broader than loopback and can expose O's service publicly. Use only when that scope is intended and protected by B's firewall/application authentication.

### SSH15: Reverse access from an internal managed host to a relay

```sh
ssh -NT -o ExitOnForwardFailure=yes -R 127.0.0.1:10022:127.0.0.1:22 relayuser@relay.example.com
```

**Run on the internal managed host, which is the SSH client in this recipe.** Its SSH service becomes available at the relay's loopback port 10022. **Test on relay:** `ssh -p 10022 -o HostKeyAlias=managed-host admin@127.0.0.1`. Requires authorization and authentication to both systems.

### SSH16: Let the remote server allocate an unused forwarding port

```sh
ssh -NT -v -R 127.0.0.1:0:127.0.0.1:8080 admin@jump.example.com
```

**Run on O.** Remote port zero requests dynamic allocation; inspect the allocated port in output before testing on B. This is dynamic **port allocation**, not SOCKS dynamic forwarding. Change target service.

### SSH17: Forward in both directions in one connection

```sh
ssh -NT -o ExitOnForwardFailure=yes -L 127.0.0.1:15432:10.20.0.20:5432 -R 127.0.0.1:18080:127.0.0.1:8080 admin@jump.example.com
```

**Run on O.** O gets a database listener; B gets a listener for O's web service. Separate local and remote bind addresses in your notes so you test on the correct machine.

### SSH18: Inspect the actual remote listening socket

```sh
ss -lnt 'sport = :18080'
```

**Run on B after a remote forward starts.** Confirms its bound address, not destination reachability. A loopback bind will not accept another host's LAN connection even if a firewall allows it.

## Dynamic SOCKS forwarding

### SSH19: Start a local SOCKS proxy through one SSH server

```sh
ssh -NT -o ExitOnForwardFailure=yes -D 127.0.0.1:1080 admin@jump.example.com
```

**Run on O.** SOCKS-aware applications on O select destinations reached from B. Configure each application; this does not automatically change O's system routes, DNS, or all applications.

### SSH20: Use SOCKS with remote hostname resolution

```sh
curl --socks5-hostname 127.0.0.1:1080 https://app.internal.example/
```

**Run on O while SSH19 runs.** Passes the hostname through SOCKS for resolution on the far side. Change SOCKS port/URL. Target TLS verification remains enabled.

### SSH21: Deliberately resolve locally before using SOCKS

```sh
curl --socks5 127.0.0.1:1080 https://app.internal.example/
```

**Run on O.** Unlike `--socks5-hostname`, this asks curl to resolve locally. Useful for diagnosing differing DNS views, but it fails if only B knows the internal name and can send a local DNS query outside the tunnel.

### SSH22: Give a SOCKS-aware application a proxy URL

```sh
ALL_PROXY=socks5h://127.0.0.1:1080 curl https://app.internal.example/
```

**Run on O.** `socks5h` requests proxy-side hostname handling in curl. Not every application honors `ALL_PROXY`, and existing proxy/no-proxy settings can override your intended path; inspect the application's actual behavior.

### SSH23: Run a TCP program through a controlled proxychains configuration

```text
strict_chain
proxy_dns
[ProxyList]
socks5 127.0.0.1 1080
```

```sh
proxychains4 -f ./proxychains-lab.conf curl http://10.20.0.20:8080/
```

**Save the text as `proxychains-lab.conf` on O, then run the command there.** Requires a compatible proxychains installation. It intercepts supported userspace connections; it does not make raw packets, ICMP, every binary, or all UDP work through SSH SOCKS.

### SSH24: Create a SOCKS listener on the remote SSH server

```sh
ssh -NT -o ExitOnForwardFailure=yes -R 127.0.0.1:1080 admin@jump.example.com
```

**Run on O; use SOCKS on B.** With supported modern OpenSSH, omitting the destination creates remote dynamic forwarding. Destinations are reached from O. Check your client supports this syntax; this is not available in every SSH implementation.

### SSH25: Test remote dynamic forwarding from the correct side

```sh
curl --socks5-hostname 127.0.0.1:1080 https://service-on-o-network.example/
```

**Run on B while SSH24 runs on O.** The connection exits from O. Change the URL to a service O can resolve/reach. Running this test on O instead would look for an unrelated local SOCKS listener.

### SSH26: Combine a local SOCKS listener and one fixed mapping

```sh
ssh -NT -D 127.0.0.1:1080 -L 127.0.0.1:15432:10.20.0.20:5432 admin@jump.example.com
```

**Run on O.** Use SOCKS for proxy-aware apps and the fixed database port for an app without SOCKS support. Both exit via B; the port numbers must be free on O.

## Jump hosts and control sessions

### SSH27: Reach a server through one jump host

```sh
ssh -J admin@jump.example.com admin@10.20.0.25
```

**Run on O.** Jump host can reach the final server's SSH port; O authenticates/verifies the final server through that transport. Agent forwarding is unnecessary. Change accounts and endpoints.

### SSH28: Reach a server through two jump hosts

```sh
ssh -J admin@192.0.2.11,admin@10.11.0.2 admin@10.12.0.2
```

**Run on O.** Transport path is O → first jump → second jump → final SSH server. Each preceding host needs TCP reachability to the next. The comma order matters.

### SSH29: Put a local forward at the end of a jump chain

```sh
ssh -NT -J admin@192.0.2.11,admin@10.11.0.2 -L 127.0.0.1:15432:10.30.0.20:5432 admin@10.12.0.2
```

**Run on O.** The final SSH server `10.12.0.2`, not the first jump, connects to the database. Change the target to something the final server can reach.

### SSH30: Put a SOCKS exit at the end of a jump chain

```sh
ssh -NT -J admin@192.0.2.11,admin@10.11.0.2 -D 127.0.0.1:1080 admin@10.12.0.2
```

**Run on O.** Applications using local SOCKS exit from the final server's network. Intermediate jumps transport SSH; they are not automatically SOCKS proxies.

### SSH31: Use a different SSH port on a jump and final server

```sh
ssh -J admin@jump.example.com:2222 -p 2200 admin@10.20.0.25
```

**Run on O.** Jump uses 2222; final destination uses 2200. Client command-line identity options generally apply to the final destination, so place distinct jump identities in host-specific SSH configuration.

### SSH32: Use ProxyCommand when you need the lower-level form

```sh
ssh -o 'ProxyCommand=ssh -W %h:%p admin@jump.example.com' admin@10.20.0.25
```

**Run on O.** `-W` sends the transport over the jump server's TCP connection to the final host/port. This is an alternative to `-J`, not a second layer to add blindly. Keep interpolated host/config inputs trusted.

### SSH33: Start a controllable background forwarding session

```sh
mkdir -p ~/.ssh/control
chmod 700 ~/.ssh/control
ssh -M -S ~/.ssh/control/lab.sock -fNT -o ExitOnForwardFailure=yes -L 127.0.0.1:18080:10.20.0.20:8080 admin@jump.example.com
```

**Run on O.** Creates a private control socket and backgrounds after setup/authentication. Use a unique socket per intended master session. Foreground mode is easier for the first test; backgrounding is not reboot persistence.

### SSH34: Check whether a control master is alive

```sh
ssh -S ~/.ssh/control/lab.sock -O check admin@jump.example.com
```

**Run on O after SSH33.** Checks the SSH master process. It does not verify that the downstream application service works.

### SSH35: Add a forward to the existing control master

```sh
ssh -S ~/.ssh/control/lab.sock -O forward -L 127.0.0.1:15432:10.20.0.20:5432 admin@jump.example.com
```

**Run on O.** Adds a mapping without a second independent SSH session. Change mapping/socket. Server policy and local port conflicts can still prevent it.

### SSH36: Cancel one existing mapping

```sh
ssh -S ~/.ssh/control/lab.sock -O cancel -L 127.0.0.1:15432:10.20.0.20:5432 admin@jump.example.com
```

**Run on O.** Cancels the specified listening forward. Match the original specification. Do not assume removing a listener forcibly terminates every already-open application stream.

### SSH37: Close the controlled SSH session

```sh
ssh -S ~/.ssh/control/lab.sock -O exit admin@jump.example.com
```

**Run on O.** Terminates that master and disrupts its dependent forwards/sessions. Change only the intended control socket. A foreground session can instead be stopped with Ctrl-C.

### SSH38: Detect a stalled session without pretending to auto-reconnect

```sh
ssh -NT -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -D 127.0.0.1:1080 admin@jump.example.com
```

**Run on O.** Sends SSH keepalive checks and exits after repeated failures. It does not relaunch itself. Use an explicitly configured service supervisor only when persistent operation is actually intended.

## Other forwarding modes

### SSH39: Expose a remote Unix socket through a local TCP port

```sh
ssh -NT -L 127.0.0.1:18080:/run/lab-app/http.sock admin@jump.example.com
```

**Run on O; Unix socket is on B.** Requires OpenSSH streamlocal support and B-side permission to access that socket. Useful for an HTTP application socket; exposing privileged management sockets grants their capabilities to listener users.

### SSH40: Create a local Unix socket for a remote TCP service

```sh
ssh -NT -L /home/alice/.ssh/lab-app.sock:10.20.0.20:8080 admin@jump.example.com
```

**Run on O; local path must be valid and unused.** Example local test: `curl --unix-socket /home/alice/.ssh/lab-app.sock http://localhost/`. Change path/target. Inspect ownership and remove only your stale socket after stopping its owner; do not blindly unlink live sockets.

### SSH41: Expose O's service through a remote Unix socket

```sh
ssh -NT -R /home/admin/lab-app.sock:127.0.0.1:8080 admin@jump.example.com
```

**Run on O; socket path is on B.** A B-side Unix-socket client connects through to O's loopback service. Requires server streamlocal forwarding permission and appropriate directory/socket access.

### SSH42: Set up an SSH layer-3 TUN transport

```sh
sudo ssh -NT -w 10:10 -o Tunnel=point-to-point -i /home/alice/.ssh/lab_ed25519 admin@jump.example.com
```

**Run on O.** Requests `tun10` on both endpoints; B must permit `PermitTunnel point-to-point` (or equivalent allowed mode) and have permission to create/own the remote device. Ordinary unprivileged accounts do not gain this automatically. Key path and known-host verification run in the sudo execution context; provision them intentionally. Then configure addresses/routes as shown below, in separate shells.

```sh
# O shell, after devices exist:
sudo ip address add 10.255.255.1/30 dev tun10
sudo ip link set tun10 up
sudo ip route add 10.20.0.0/24 via 10.255.255.2 dev tun10
# B shell, after devices exist:
sudo ip address add 10.255.255.2/30 dev tun10
sudo ip link set tun10 up
```

B needs forwarding/firewall and the LAN needs a return route or deliberately scoped NAT for O's tunnel address. Unlike ordinary port forwards, this can carry routed IP protocols. Do not mix this setup with an existing interface/subnet using the same names/addresses.

### SSH43: Request an SSH layer-2 TAP transport

```sh
sudo ssh -NT -w 11:11 -o Tunnel=ethernet -i /home/alice/.ssh/lab_ed25519 admin@jump.example.com
```

**Run on O with matching B privileges/policy.** Requires platform TAP support and `PermitTunnel ethernet`/appropriate permission. Device creation is only the transport step; bridge design, address assignment, loop prevention, and interface ownership are deployment-specific. Do not add a production NIC to a bridge blindly. This is not ordinary SOCKS or port forwarding.

### SSH44: Forward an X11 application

```sh
ssh -X admin@jump.example.com
```

**Run on O with a working local X server; launch the GUI app in the B shell.** Needs B's X11 forwarding support and xauth integration. `-Y` requests trusted X11 forwarding with broader trust; do not choose it casually. X11 forwarding is distinct from an arbitrary TCP service tunnel.

## Server policy and diagnostics

### SSH45: Diagnose forwarding refusal with client logs

```sh
ssh -vvv -NT -o ExitOnForwardFailure=yes -L 127.0.0.1:15432:10.20.0.20:5432 admin@jump.example.com
```

**Run on O.** Inspect whether failure is authentication, bind collision, administratively prohibited channel, or downstream connection. Logs contain identity/infrastructure details; keep real output private.

### SSH46: Inspect effective client configuration without connecting

```sh
ssh -G deep8
```

**Run on O after defining the alias below.** Prints the resolved configuration, including jumps, identity choices, and forwards. It does not verify that hosts are reachable or keys accepted.

### SSH47: Restrict a server account to selected local-forward destinations

```text
# B: relevant portion of sshd_config, integrated into existing policy
Match User tunneluser
    AllowTcpForwarding local
    PermitOpen 10.20.0.20:5432 10.20.0.22:8080
    AllowAgentForwarding no
    X11Forwarding no
```

**Edit on B as its administrator.** `local` is from the SSH client's perspective: O-side `-L`/`-D` destinations reached by B. This is forwarding policy, not a complete restricted-account design; an unrestricted shell can provide other network access. Existing `DisableForwarding`, key restrictions, and Match blocks can further constrain behavior.

### SSH48: Permit a specified remote listener without making every bind public

```text
# B: relevant portion of sshd_config
Match User tunneluser
    AllowTcpForwarding remote
    GatewayPorts clientspecified
    PermitListen 10.20.0.5:18080
    AllowAgentForwarding no
    X11Forwarding no
```

**Edit on B as its administrator.** Allows the intended remote listener address/port, not every destination the client might forward to. Change account/address. `PermitOpen` is not a substitute for controlling remote-forward destinations on the client side. Request the exact bound address in `-R`, then test effective policy.

### SSH49: Validate server syntax and inspect account-specific settings

```sh
sudo sshd -t
sudo sshd -T -C user=tunneluser,host=client.example,addr=192.0.2.10
```

**Run on B before reloading its SSH service.** Set actual connection values; some Match conditions need additional parameters. Keep the current management session open and verify a fresh one after the distribution-specific reload. A successful syntax check does not prove your account will be allowed every desired tunnel.

### SSH50: Confirm the final service from the final SSH endpoint

```sh
nc -n -z -v -w 3 10.80.0.10 443
```

**Run on the final endpoint B8 in the topology below, not on an arbitrary jump.** Confirms the last-leg TCP path. If this fails directly on B8, rebuilding seven earlier jumps will not fix the service or its firewall. Change destination/port; netcat options vary by implementation.

## Eight-box worked topology

Here **eight boxes deep means O → B1 → B2 → B3 → B4 → B5 → B6 → B7 → B8**. B8 is the eighth remote SSH endpoint; an application target T behind it is separate. If you mean eight intermediate jump hosts *plus* a ninth SSH endpoint, add that endpoint after B8 using the same pattern.

```text
O --SSH--> B1 --SSH transport--> B2 --> B3 --> B4 --> B5 --> B6 --> B7 --> B8
                                                                               |
                                                                               +--> T 10.80.0.10:443
```

| Box | SSH address reachable from predecessor | Downstream link address for this lab |
|---|---|---|
| B1 | 192.0.2.11 | 10.11.0.1 |
| B2 | 10.11.0.2 | 10.12.0.1 |
| B3 | 10.12.0.2 | 10.13.0.1 |
| B4 | 10.13.0.2 | 10.14.0.1 |
| B5 | 10.14.0.2 | 10.15.0.1 |
| B6 | 10.15.0.2 | 10.16.0.1 |
| B7 | 10.16.0.2 | 10.17.0.1 |
| B8 | 10.17.0.2 | 10.80.0.1 |

Assume each predecessor can connect to the next SSH port and you have authorized accounts/host keys for all eight. You do not need to copy O's private key onto them or enable `-A`. Each jump's server policy must permit its next TCP destination. The final B8 policy must allow the desired `-L`, `-R`, or `-D` operation.

### Configure readable host aliases on O

Add to **O's** `~/.ssh/config`; adapt identities/accounts per host. The base `b1`–`b8` aliases deliberately contain no ProxyJump, so their connection chain is explicit in the examples.

```sshconfig
Host b1
    HostName 192.0.2.11
Host b2
    HostName 10.11.0.2
Host b3
    HostName 10.12.0.2
Host b4
    HostName 10.13.0.2
Host b5
    HostName 10.14.0.2
Host b6
    HostName 10.15.0.2
Host b7
    HostName 10.16.0.2
Host b8
    HostName 10.17.0.2
Host deep8
    HostName 10.17.0.2
    ProxyJump b1,b2,b3,b4,b5,b6,b7
    HostKeyAlias b8

Host b1 b2 b3 b4 b5 b6 b7 b8 deep8
    User admin
    Port 22
    IdentityFile ~/.ssh/lab_ed25519
    IdentitiesOnly yes
    ForwardAgent no
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Put host-specific settings before broad defaults when a different value must win. Verify host keys for the logical systems; `HostKeyAlias b8` intentionally consolidates verification for the extra alias, not disables it.

### Test one depth at a time from O

These are eight independent tests; run them progressively, not as a single all-or-nothing script. Each runs `hostname` on the final endpoint so you can verify where you landed.

```sh
# O -> B1
ssh b1 hostname
# O -> B1 -> B2
ssh -J b1 b2 hostname
# O -> B1 -> B2 -> B3
ssh -J b1,b2 b3 hostname
# O -> ... -> B4
ssh -J b1,b2,b3 b4 hostname
# O -> ... -> B5
ssh -J b1,b2,b3,b4 b5 hostname
# O -> ... -> B6
ssh -J b1,b2,b3,b4,b5 b6 hostname
# O -> ... -> B7
ssh -J b1,b2,b3,b4,b5,b6 b7 hostname
# O -> ... -> B8
ssh -J b1,b2,b3,b4,b5,b6,b7 b8 hostname
```

### Local HTTPS forward eight boxes deep

```sh
# O shell: keep running
ssh -NT -o ExitOnForwardFailure=yes -J b1,b2,b3,b4,b5,b6,b7 -L 127.0.0.1:18443:10.80.0.10:443 b8
# O second shell: app.internal.example must match the real target certificate
curl --connect-to app.internal.example:443:127.0.0.1:18443 https://app.internal.example/
```

**Data path:** O local listener → encrypted SSH to B8 through seven jumps → B8 connects to T. No local listener is needed on every intermediate box. The final B8→T leg is outside SSH's encryption; HTTPS continues to protect that application leg.

### Local SOCKS eight boxes deep

```sh
# O shell
ssh -NT -o ExitOnForwardFailure=yes -J b1,b2,b3,b4,b5,b6,b7 -D 127.0.0.1:1080 b8
# O second shell
curl --socks5-hostname 127.0.0.1:1080 https://app.internal.example/
```

SOCKS target DNS and TCP connections originate from B8. A workstation `ping` still does not use this SOCKS listener. To probe from B8, explicitly run a remote command with SSH and your authorized scope instead.

### Remote fixed forward eight boxes deep

```sh
# O shell; O already has an HTTP service on 127.0.0.1:8080
ssh -NT -o ExitOnForwardFailure=yes -J b1,b2,b3,b4,b5,b6,b7 -R 127.0.0.1:18080:127.0.0.1:8080 b8
```

```sh
# B8 shell
curl http://127.0.0.1:18080/
```

B8's listener sends requests through the chain back to O's service. The application client in this example runs on B8. Earlier jumps do not automatically receive the remote listener.

### Remote dynamic SOCKS eight boxes deep

```sh
# O shell; requires remote dynamic support
ssh -NT -o ExitOnForwardFailure=yes -J b1,b2,b3,b4,b5,b6,b7 -R 127.0.0.1:1080 b8
```

```sh
# B8 shell: resolve/connect through O's side
curl --socks5-hostname 127.0.0.1:1080 https://service-on-o-network.example/
```

The exit is O, not B8. This is useful when B8 needs an explicitly approved service on O's network. It does not transparently redirect B8's whole IP stack.

### Short alias versions

```sh
# All on O, separate alternatives:
ssh deep8
ssh -NT -L 127.0.0.1:15432:10.80.0.20:5432 deep8
ssh -NT -D 127.0.0.1:1080 deep8
ssh -NT -R 127.0.0.1:18080:127.0.0.1:8080 deep8
```

They inherit `ProxyJump` from O's config. Do not run all alternatives on overlapping ports at once. To terminate a foreground chain, stop its O-side SSH process; dependent forwarding ends with it. With a private control master, use its matching `-O exit` command.

## Troubleshooting by symptom

| Symptom | Check |
|---|---|
| `Address already in use` | Listener side, bind address, local port, stale intended session |
| `administratively prohibited` | Server forwarding settings, PermitOpen/PermitListen, key options, final/jump role |
| Tunnel starts but application refuses | Destination service/port as seen from the correct endpoint |
| `-L ...127.0.0.1...` reaches wrong service | That target loopback belongs to the SSH server |
| `-R ...127.0.0.1...` reaches wrong service | That target loopback belongs to the SSH client |
| Internal names fail over SOCKS | Local versus remote DNS resolution, resolver on exit side |
| Ping ignores SOCKS | Expected: ordinary SSH SOCKS is TCP-oriented, not ICMP routing |
| Remote listener only on loopback | GatewayPorts/PermitListen, actual bind inspection on B |
| Hop 5 fails but hop 4 works | B4→B5 reachability, B4 forwarding policy, B5 host key/account |
| Final target fails at depth 8 | Test target directly from B8 before changing earlier hops |
| Slow at large depth | Latency, retransmissions, per-hop limits, nested transport overhead |
| TUN exists but no LAN access | Routes, forwarding, firewall, return path, device permissions |

## References and testing limits

[OpenSSH ssh manual](https://man.openbsd.org/ssh), [client configuration](https://man.openbsd.org/ssh_config), [server configuration](https://man.openbsd.org/sshd_config), [curl manual](https://curl.se/docs/manpage.html). Check installed `ssh -V`/manuals; OpenBSD's current manual may be newer than your Linux package.

Eight-hop examples are a worked topology, not a live-tested deployment. Every intermediate link/account/policy must work. Forwarding does not grant access to an application you are not authenticated/authorized to use; it only supplies a network path.
