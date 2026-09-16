# OpenVPN Configurations — Client, Server, Routing & Troubleshooting

[Repository index](README.md) · [Firewall integration](iptables.md#openvpn-firewall-integration)

## Contents

- [Example cookbook: 30 problems and configurations](#example-cookbook)
- [Scope and topology](#scope-and-topology)
- [Configuration directive reference](#configuration-directive-reference)
- [PKI and file layout](#pki-and-file-layout)
- [Server template](#server-template)
- [Matching client template](#matching-client-template)
- [Split tunnel](#split-tunnel)
- [Full tunnel and DNS](#full-tunnel-and-dns)
- [IPv6 decisions](#ipv6-decisions)
- [Per-client settings and site-to-site routes](#per-client-settings-and-site-to-site-routes)
- [Control-channel protection](#control-channel-protection)
- [Authentication and revocation](#authentication-and-revocation)
- [Operations and validation](#operations-and-validation)
- [Troubleshooting matrix](#troubleshooting-matrix)
- [MTU, transport, and performance](#mtu-transport-and-performance)
- [Public repository hygiene](#public-repository-hygiene)
- [Official references](#official-references)

## Example cookbook

Configuration snippets are **edits to the full server/client templates below**, not complete standalone profiles. Each entry says which side to change. Replace existing conflicting directives instead of piling on duplicates. Shell diagnostics are for Linux unless stated otherwise; service names and resolver tools depend on your distribution. Real profiles and keys stay private.

### Find an example

- [V01: Connect interactively with a profile and relative key files](#v01-connect-interactively-with-a-profile-and-relative-key-files)
- [V02: Point a client at a different server endpoint](#v02-point-a-client-at-a-different-server-endpoint)
- [V03: Force an IPv4 outer transport for diagnosis](#v03-force-an-ipv4-outer-transport-for-diagnosis)
- [V04: Change the listener port on both ends](#v04-change-the-listener-port-on-both-ends)
- [V05: Use TCP transport when your network requires it](#v05-use-tcp-transport-when-your-network-requires-it)
- [V06: Add a second compatible VPN endpoint](#v06-add-a-second-compatible-vpn-endpoint)
- [V07: Route only one internal subnet through the VPN](#v07-route-only-one-internal-subnet-through-the-vpn)
- [V08: Route one specific internal host](#v08-route-one-specific-internal-host)
- [V09: Make a client choose its own route list](#v09-make-a-client-choose-its-own-route-list)
- [V10: Ignore only a pushed full-tunnel directive](#v10-ignore-only-a-pushed-full-tunnel-directive)
- [V11: Enable full-tunnel IPv4 routing](#v11-enable-full-tunnel-ipv4-routing)
- [V12: Push an internal DNS resolver](#v12-push-an-internal-dns-resolver)
- [V13: Check which DNS servers Linux actually uses](#v13-check-which-dns-servers-linux-actually-uses)
- [V14: Query the internal resolver directly](#v14-query-the-internal-resolver-directly)
- [V15: Give a client a fixed tunnel address](#v15-give-a-client-a-fixed-tunnel-address)
- [V16: Advertise a network behind a branch client](#v16-advertise-a-network-behind-a-branch-client)
- [V17: Bind the server to one local address](#v17-bind-the-server-to-one-local-address)
- [V18: Limit the number of connected clients](#v18-limit-the-number-of-connected-clients)
- [V19: Use a predictable Linux tunnel name](#v19-use-a-predictable-linux-tunnel-name)
- [V20: Temporarily increase connection diagnostics](#v20-temporarily-increase-connection-diagnostics)
- [V21: Read recent server startup errors](#v21-read-recent-server-startup-errors)
- [V22: Confirm that a UDP listener exists](#v22-confirm-that-a-udp-listener-exists)
- [V23: See whether encrypted VPN packets reach the WAN interface](#v23-see-whether-encrypted-vpn-packets-reach-the-wan-interface)
- [V24: See whether decrypted packets reach the tunnel interface](#v24-see-whether-decrypted-packets-reach-the-tunnel-interface)
- [V25: Ask Linux which route it will use](#v25-ask-linux-which-route-it-will-use)
- [V26: Check certificate validity dates and subject](#v26-check-certificate-validity-dates-and-subject)
- [V27: Check whether a certificate expires within 30 days](#v27-check-whether-a-certificate-expires-within-30-days)
- [V28: Verify a certificate and private key belong together](#v28-verify-a-certificate-and-private-key-belong-together)
- [V29: Check whether the CRL is current](#v29-check-whether-the-crl-is-current)
- [V30: Diagnose an offload-specific issue with one controlled test](#v30-diagnose-an-offload-specific-issue-with-one-controlled-test)

### V01: Connect interactively with a profile and relative key files

```sh
sudo openvpn --cd /home/alice/vpn --config client.ovpn
```

Change the absolute directory and profile filename. `--cd` makes relative key/certificate paths resolve from that directory. This starts a real VPN connection and can change routes/DNS; stop with Ctrl-C when testing in the foreground.

### V02: Point a client at a different server endpoint

```conf
# Client: replace the existing remote line
remote vpn.example.com 1194
```

Change hostname and port to your server. Keep certificate-name verification tied to the expected certificate identity; changing the DNS endpoint is not a reason to disable verification.

### V03: Force an IPv4 outer transport for diagnosis

```conf
# Client: replace the existing proto line
proto udp4
```

Useful when a dual-stack hostname resolves but the client's outer IPv6 path is broken. The server must listen on compatible UDP IPv4. This selects the outer transport family; it does not control IPv6 traffic inside or outside the tunnel.

### V04: Change the listener port on both ends

```conf
# Server: replace its port directive
port 21194
```

```conf
# Client: replace its remote directive
remote vpn.example.com 21194
```

Change 21194 consistently. Update host firewall, cloud security group, and upstream port forwarding too. Restarting the server to apply a listener change disrupts connected clients.

### V05: Use TCP transport when your network requires it

```conf
# Server: replace proto and port
proto tcp-server
port 443
```

```conf
# Client: replace proto and remote
proto tcp-client
remote vpn.example.com 443
```

Requires matching firewall changes and an available server port. TCP 443 does not turn OpenVPN into HTTPS or guarantee passage through an HTTP proxy. Use this for a real transport constraint; TCP-over-TCP can behave poorly under loss.

### V06: Add a second compatible VPN endpoint

```conf
# Client: two endpoints, same transport and compatible trust/configuration
remote vpn1.example.com 1194
remote vpn2.example.com 1194
```

Replace the existing remote list. Both servers must support the client's identity, routing, and verification policy. With `verify-x509-name vpn-server name`, both must present that expected identity; otherwise design a deliberate multi-endpoint trust policy. Failover is not session continuity.

### V07: Route only one internal subnet through the VPN

```conf
# Server: push this route, with no redirect-gateway push
push "route 10.20.0.0 255.255.255.0"
```

Change subnet/netmask. Other pushed routes may still apply. Requires server forwarding, firewall permission, and a return route from that LAN; route advertisement alone does not create access.

### V08: Route one specific internal host

```conf
# Server: push a host route
push "route 10.20.0.25 255.255.255.255"
```

Change host address. This sends traffic to one destination through the VPN; it does not restrict which ports are allowed there. Use a firewall for that service-level restriction.

### V09: Make a client choose its own route list

```conf
# Client: add only when rejecting pushed routes is intentional
route-nopull
route 10.20.0.0 255.255.255.0
```

Change the local route. This affects pulled routing and some network options; verify DNS integration afterward. The server must still support the traffic and return path.

### V10: Ignore only a pushed full-tunnel directive

```conf
# Client
pull-filter ignore "redirect-gateway"
```

Preserves other accepted pushes while discarding matching redirect directives. Change the prefix only if you understand the option text being filtered. A full-tunnel directive written locally in the profile is not a pushed directive and is not removed by this filter.

### V11: Enable full-tunnel IPv4 routing

```conf
# Server
push "redirect-gateway def1"
```

Add to the server template only when the server can forward/NAT or route client internet traffic. This does not configure DNS or handle client IPv6 by itself; complete those decisions before calling the tunnel a full-traffic solution.

### V12: Push an internal DNS resolver

```conf
# Server
push "dhcp-option DNS 10.20.0.53"
```

Replace the resolver address. Ensure clients have a route to it and can reach both UDP/TCP 53. Whether this changes the operating system resolver depends on client/platform integration.

### V13: Check which DNS servers Linux actually uses

```sh
resolvectl status
```

For systems using systemd-resolved, inspect the VPN link's DNS servers and routing domains. This is read-only. On systems without it, inspect the actual network manager/resolver rather than assuming `/etc/resolv.conf` tells the whole story.

### V14: Query the internal resolver directly

```sh
dig @10.20.0.53 internal.example.com A
dig +tcp @10.20.0.53 internal.example.com A
```

Change resolver/name; requires `dig`. These separate tests distinguish direct UDP/TCP DNS reachability from the OS's default resolver behavior. Success does not prove applications are using that resolver.

### V15: Give a client a fixed tunnel address

```conf
# Server CCD file: /etc/openvpn/server/ccd/laptop-01
ifconfig-push 10.8.0.10 255.255.255.0
```

Requires server `topology subnet` and `client-config-dir` pointing to this directory. Change the CN-derived filename and address. Reserve the address outside the dynamic pool, as shown in the full per-client section.

### V16: Advertise a network behind a branch client

```conf
# Server main configuration
route 10.30.0.0 255.255.255.0
```

```conf
# Server CCD file for the branch gateway client's certificate CN
iroute 10.30.0.0 255.255.255.0
```

Change branch network and CCD identity. The branch gateway needs forwarding, firewall policy, and return routing; main-site hosts need a route too. These two snippets have different destinations and must not both be placed in the client profile.

### V17: Bind the server to one local address

```conf
# Server
local 192.0.2.10
```

Replace the documentation address with an address actually assigned to the server. Useful on multihomed hosts. A public address belonging only to an upstream NAT router cannot normally be bound here.

### V18: Limit the number of connected clients

```conf
# Server
max-clients 25
```

Change 25 to your capacity/policy target. This caps concurrent clients, not certificate issuance, per-user bandwidth, or application sessions. Confirm behavior with your server mode/version.

### V19: Use a predictable Linux tunnel name

```conf
# Linux server: replace the existing dev directive
dev tun0
```

Change the name consistently with firewall/route monitoring. Ensure another process is not already using it. GUI clients and other platforms can have different device naming rules.

### V20: Temporarily increase connection diagnostics

```sh
sudo openvpn --cd /home/alice/vpn --config client.ovpn --verb 4
```

Change directory/profile. Starts a real client connection at a more detailed log level; inspect the output for transport, TLS, route, and option problems. Avoid posting full logs publicly; lower verbosity after diagnosing.

### V21: Read recent server startup errors

```sh
sudo journalctl -u openvpn-server@server --since '15 minutes ago' --no-pager
```

Change the unit name to your distribution's actual instance. This is read-only. Look for the first causal error, not only the last generic service-failed line.

### V22: Confirm that a UDP listener exists

```sh
sudo ss -lunp 'sport = :1194'
```

Change the port. Shows local UDP sockets/processes; it does not prove reachability through upstream firewalls or NAT. For TCP transport, use `ss -ltnp` instead.

### V23: See whether encrypted VPN packets reach the WAN interface

```sh
sudo tcpdump -ni eth0 -c 30 'udp port 1194'
```

Change interface/port/protocol. Captures up to 30 matching packets, or stop with Ctrl-C. Arrival proves only that packets reached this capture point; certificate checks, key matching, and firewall handling still need inspection.

### V24: See whether decrypted packets reach the tunnel interface

```sh
sudo tcpdump -ni tun0 -c 30 'host 10.20.0.25'
```

Change interface and test destination. Compare with WAN/LAN captures to localize a routing failure. Tunnel captures can expose plaintext traffic metadata or contents; keep results private and account for DCO-specific paths.

### V25: Ask Linux which route it will use

```sh
ip route get 10.20.0.25
ip -6 route get 2001:db8::25
```

Replace targets with real intended destinations. Run on the client for client routing, or server for server routing. These queries show selected routes without sending a test packet; they do not prove firewall permission or a working return path.

### V26: Check certificate validity dates and subject

```sh
openssl x509 -in laptop-01.crt -noout -subject -issuer -dates
```

Change certificate path. This prints public certificate metadata, not the private key. Compare expiry dates with system time; also verify CA trust, certificate purpose, and server-name requirements.

### V27: Check whether a certificate expires within 30 days

```sh
openssl x509 -in laptop-01.crt -checkend 2592000 -noout
```

Change certificate or seconds (`30*24*60*60 = 2592000`). Exit status distinguishes validity beyond the requested interval from expiry/failure; inspect messages too. This does not test revocation or endpoint connectivity.

### V28: Verify a certificate and private key belong together

```sh
openssl x509 -in laptop-01.crt -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256
openssl pkey -in laptop-01.key -pubout -outform DER | openssl dgst -sha256
```

Change both paths; the public-key hashes should match. Both pipelines must complete without errors: matching hashes of empty output after a failed read prove nothing. This works across common RSA/EC key types, unlike RSA-modulus-only recipes. Encrypted keys may prompt for a passphrase; neither command prints the private key.

### V29: Check whether the CRL is current

```sh
openssl crl -in /etc/openvpn/server/crl.pem -noout -lastupdate -nextupdate
```

Change the CRL path. Compare `nextUpdate` with the current time and refresh through your CA workflow if needed. A present but expired CRL can still prevent intended authentication behavior.

### V30: Diagnose an offload-specific issue with one controlled test

```conf
# On the affected OpenVPN 2.6 endpoint, for a temporary comparison
disable-dco
```

Add only as a deliberate troubleshooting change and restart/reconnect the relevant instance. Compare logs and behavior with the previous state, then choose the intended deployment mode. This may reduce throughput; it is not a universal fix for routing, MTU, or authentication problems.

## Scope and topology

These templates target OpenVPN Community Edition **2.6-style** TLS client/server operation on Linux. They are not Access Server or CloudConnexa configuration exports. Check `openvpn --version` and the manual matching both endpoints; newer versions and packaged service defaults can differ.

No certificates or secrets are embedded. The templates will not start until you supply PKI files, replace placeholders, create required directories, and configure routing/firewall rules.

```text
Client internet interface
        |
        | UDP 1194, encrypted outer traffic
        v
vpn.example.com / WAN eth0
OpenVPN server
  tun0: 10.8.0.1/24
  LAN eth1: 10.20.0.2/24
        |
        +---- LAN 10.20.0.0/24, gateway 10.20.0.1
        +---- internet via eth0, if full tunnel is enabled

Clients receive an address in 10.8.0.0/24.
```

Choose tunnel and LAN networks that do not overlap each other or likely client networks. Replace `vpn.example.com`, `eth0`, `eth1`, certificate names, and local paths. `dev tun0` deliberately gives the Linux server a predictable firewall interface name.

TUN carries routed IP packets. TAP carries Ethernet frames and requires a bridging design; do not change `tun` to `tap` as a connectivity fix.

## Configuration directive reference

Configuration files use option names without leading `--`. Each directive occupies a line; comments use `#` or `;`.

| Directive | Purpose | Important detail |
|---|---|---|
| `client` | TLS client helper | Includes pull behavior |
| `dev tun` | Routed tunnel device | Both ends need compatible device type |
| `proto udp` | Outer transport | Must agree with server |
| `remote HOST PORT` | Server endpoint | DNS resolution happens before tunnel is ready |
| `nobind` | No fixed local client port | Typical client setting |
| `server NET MASK` | Server address pool helper | Requires routing/firewall integration |
| `topology subnet` | Subnet-style tunnel addressing | Affects static client address syntax |
| `ca FILE` | Trust anchor | Public certificate, not CA private key |
| `cert FILE` / `key FILE` | Local identity | Key is secret |
| `remote-cert-tls server` | Verify server certificate role | Use on clients |
| `remote-cert-tls client` | Verify client certificate role | Use on server with suitable client certs |
| `verify-x509-name NAME name` | Pin expected certificate name | Default RDN is commonly CN; not automatic DNS/SAN hostname verification |
| `data-ciphers LIST` | Negotiated data encryption | Distinct from TLS control-channel ciphers |
| `tls-version-min 1.2` | Minimum TLS version | Verify endpoint/library compatibility |
| `tls-crypt FILE` | Encrypt/authenticate control packets | Shared group key; no key-direction |
| `tls-crypt-v2 FILE` | Per-client control protection | Different client/server key files |
| `dh none` | Use ECDH instead of finite-field DH params | Requires compatible TLS setup |
| `keepalive A B` | Ping/restart helper | Server/client interpretation differs |
| `persist-key` / `persist-tun` | Preserve selected resources during restart | Not a network kill switch |
| `route NET MASK` | Local route | Does not select an internal client by itself |
| `push "route ..."` | Send route to clients | Client may reject/filter it |
| `redirect-gateway def1` | Redirect IPv4 with two /1 routes | Does not alone secure IPv6 or DNS |
| `client-config-dir DIR` | Client-specific configuration files | Filenames normally match certificate CN |
| `crl-verify FILE` | Certificate revocation list | Keep current and readable |
| `verb 3` | Operational logging | Higher levels reveal more metadata |

## PKI and file layout

Use a unique client certificate/key for every person or device. Keep the CA private key off the VPN server when possible. Distinguish certificate issuance from runtime configuration.

```text
Certificate authority, private administration environment:
  pki/private/ca.key              SECRET: signing authority
  pki/ca.crt                      trust certificate
  pki/issued/vpn-server.crt       server certificate
  pki/issued/laptop-01.crt        client certificate
  pki/crl.pem                     revocation list

VPN server:
  /etc/openvpn/server/server.conf
  /etc/openvpn/server/ca.crt
  /etc/openvpn/server/vpn-server.crt
  /etc/openvpn/server/vpn-server.key      SECRET
  /etc/openvpn/server/tls-crypt.key       SECRET
  /etc/openvpn/server/crl.pem
  /etc/openvpn/server/ccd/                optional

Client, kept private:
  client.ovpn
  ca.crt
  laptop-01.crt
  laptop-01.key                           SECRET
  tls-crypt.key                           SECRET
```

### Illustrative Easy-RSA 3 workflow

Run from a correctly installed Easy-RSA environment. These are PKI administration steps, not commands to run on every connection. Run `init-pki` only for a new PKI; it can replace existing PKI material after confirmation.

```sh
./easyrsa init-pki
./easyrsa build-ca
./easyrsa gen-req vpn-server
./easyrsa sign-req server vpn-server
./easyrsa gen-req laptop-01
./easyrsa sign-req client laptop-01
./easyrsa gen-crl
```

Follow prompts carefully and verify the request identity before signing. This compact example shows one administration environment. In a separated deployment, generate each private key on its endpoint, transfer only its request to the CA, use `import-req`, sign there, and return the certificate. Never transfer the CA private key to clients or the VPN server.

Encrypted endpoint keys require an unlock strategy. An unattended daemon cannot answer an interactive passphrase prompt. Decide how your service manager securely supplies unlock material, or use a tightly protected service key according to your policy; do not publish passphrases or assume `nopass` is required everywhere.

```sh
# Generate control-channel group key on a trusted system
umask 077
openvpn --genkey tls-crypt tls-crypt.key

# Inspect certificate identities and validity (does not show private keys)
openssl x509 -in vpn-server.crt -noout -subject -issuer -dates
openssl x509 -in vpn-server.crt -noout -text
openssl verify -CAfile ca.crt vpn-server.crt
openssl crl -in crl.pem -noout -lastupdate -nextupdate
```

Certificate inspection should confirm the intended server/client extended key usage. `openssl verify` without an explicit purpose is not a substitute for OpenVPN's role/name checks.

## Server template

Save privately as `/etc/openvpn/server/server.conf`. This is a split-tunnel baseline that pushes access to the example LAN. Supply all referenced files first.

```conf
# Transport and addressing
port 1194
proto udp
dev tun0
topology subnet
server 10.8.0.0 255.255.255.0

# PKI: never deploy the CA private key here
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/vpn-server.crt
key /etc/openvpn/server/vpn-server.key
dh none
remote-cert-tls client
crl-verify /etc/openvpn/server/crl.pem

# Control-channel and data-channel security
tls-crypt /etc/openvpn/server/tls-crypt.key
tls-version-min 1.2
data-ciphers AES-256-GCM:AES-128-GCM
allow-compression no

# Split-tunnel LAN route; requires forwarding and LAN return routing
push "route 10.20.0.0 255.255.255.0"

# Recovery and logging
keepalive 10 120
persist-key
persist-tun
verb 3

# Optional: enable only after creating and provisioning this directory
# client-config-dir /etc/openvpn/server/ccd
# ccd-exclusive

# Optional: use an actual dedicated local service account/group
# user openvpn
# group openvpn
```

The commented privilege-drop options require an existing account and suitable file/directory access, including later CRL reads. Distribution service units may apply their own restrictions. Start from package defaults and verify permissions after privilege changes.

The template omits `client-to-client`. Firewall routing policy still determines whether clients can reach each other through the operating system; omission alone is not a full isolation policy. Keep FORWARD default-deny and permit only intended destinations. DCO can change forwarding details; verify the actual packet path.

Before startup, configure the listener allowance, IPv4 forwarding, LAN return route, and FORWARD rules in the [iptables sheet](iptables.md#openvpn-firewall-integration). If the server is behind a router, forward UDP 1194 to it there and permit it in any cloud security group.

## Matching client template

Save privately as `client.ovpn`. File paths below are relative to the launch context; GUI importers may bundle or relocate files. Use paths/import procedures supported by your client.

```conf
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind

persist-key
persist-tun

ca ca.crt
cert laptop-01.crt
key laptop-01.key

# Verify certificate role AND expected identity
remote-cert-tls server
verify-x509-name vpn-server name

tls-crypt tls-crypt.key
tls-version-min 1.2
data-ciphers AES-256-GCM:AES-128-GCM
allow-compression no

auth-nocache
verb 3
```

`vpn-server` must match the server certificate name selected by OpenVPN's name-verification settings. It is not necessarily the endpoint's DNS name. Do not remove verification to “fix” an identity mismatch; inspect the certificate and intended trust relationship.

`auth-nocache` reduces retention of authentication input; it does not encrypt files on disk, implement MFA, or replace certificate checks.

### Inline profile shape

Some clients import a single file with inline material:

```conf
<ca>
PASTE_CA_CERTIFICATE_PEM_HERE
</ca>
<cert>
PASTE_CLIENT_CERTIFICATE_PEM_HERE
</cert>
<key>
PASTE_CLIENT_PRIVATE_KEY_PEM_HERE
</key>
<tls-crypt>
PASTE_SHARED_TLS_CRYPT_KEY_HERE
</tls-crypt>
```

These placeholders are intentionally invalid. Replace file directives with corresponding inline blocks when constructing a real profile. An actual inline profile containing a private key or tls-crypt key is a credential; never commit it to this public repository.

## Split tunnel

Split tunneling sends only selected routes through the VPN. The baseline pushes `10.20.0.0/24`; the client's ordinary internet default route stays in place.

```conf
# Server: additional internal network
push "route 10.30.0.0 255.255.255.0"

# Client alternative: ignore pushed routes, install selected route locally
# route-nopull
# route 10.20.0.0 255.255.255.0
```

`route-nopull` also affects some pushed network settings, including DNS-related settings depending on client/option handling. Do not add it and assume DNS behavior is unchanged. A narrower `pull-filter` can reject a specific pushed option:

```conf
# Client: ignore only the matching pushed redirect directive prefix
pull-filter ignore "redirect-gateway"
```

Check client support. Pull filters act on option text; broad prefixes can suppress more than intended.

### LAN return path

On the LAN gateway, route `10.8.0.0/24` via the VPN server's LAN address `10.20.0.2`. A Linux gateway example:

```sh
sudo ip route add 10.8.0.0/24 via 10.20.0.2
```

Use the gateway's persistent configuration mechanism for durable routing. A route on the wrong machine does not fix the return path. If routing cannot be changed, use narrowly scoped LAN NAT as explained in the firewall sheet, accepting loss of source-address visibility.

## Full tunnel and DNS

For full-tunnel **IPv4**, add to the server:

```conf
push "redirect-gateway def1"
push "dhcp-option DNS 10.20.0.53"
```

`10.20.0.53` must be a real reachable resolver in your deployment. The server must forward client internet traffic and provide either routed return paths or WAN source NAT. Full-tunnel routes alone do not enable internet access.

DNS application is client/platform-specific. A Linux command-line client may need a distribution-provided resolver integration or NetworkManager; `dhcp-option DNS` is not a universal automatic resolver change. Windows clients can support:

```conf
# Windows clients only, where supported
block-outside-dns
```

This is not a cross-platform firewall kill switch. Test the system resolver and application-specific DNS, including browser secure-DNS settings. Split DNS (only internal domains through internal resolvers) usually needs the operating system's resolver integration rather than just one DNS IP.

### Kill-switch design requirements

A kill switch is a separate endpoint firewall policy: allow the VPN's outer endpoint, required initial DNS or pinned endpoints, intended local-network access, and tunnel egress; block other egress when disconnected. Include IPv6 and interface changes. Implement through the client platform's supported policy mechanism and test reconnect, boot, suspend, and endpoint failover. `persist-tun` and `redirect-gateway` alone are not kill switches.

## IPv6 decisions

Choose explicitly:

1. **Route IPv6 through the VPN:** allocate a suitable IPv6 tunnel prefix, configure `server-ipv6`, push IPv6 routes/redirect behavior, enable IPv6 forwarding, and set IPv6 firewall/return routes. Use an actually routed prefix for internet access.
2. **Block IPv6 for VPN use:** use a tested client/platform policy, covering disconnect behavior too.
3. **Allow local IPv6 outside the tunnel:** document this as intentional split behavior, not full-tunnel privacy.

An IPv4 full tunnel leaves ordinary IPv6 routing untouched. `block-ipv6` can reject IPv6 packets that reach OpenVPN, but is ineffective for IPv6 traffic that is still routed outside the tunnel. It needs corresponding tunnel IPv6 configuration and routing; it is not a standalone one-line leak fix.

For routed dual-stack deployments, consult the versioned manual's `server-ipv6`, `route-ipv6`, and `redirect-gateway ipv6` options and test both address families. Do not use a documentation prefix such as `2001:db8::/32` for real internet routing.

## Per-client settings and site-to-site routes

Enable on the server after creating a protected directory:

```conf
client-config-dir /etc/openvpn/server/ccd
```

With `topology subnet`, a CCD file named after a client's certificate CN can set a fixed tunnel address:

```conf
# /etc/openvpn/server/ccd/laptop-01
ifconfig-push 10.8.0.10 255.255.255.0
```

Reserve static addresses outside the dynamic allocation range. For example, replace the baseline server helper line with the following pair and keep `topology subnet`:

```conf
server 10.8.0.0 255.255.255.0 nopool
ifconfig-pool 10.8.0.100 10.8.0.200 255.255.255.0
```

Do not keep a second `server` directive alongside this replacement. A pool persistence file is a convenience mapping, not the same guarantee as an explicit static assignment.

### Site behind a VPN client

Assume branch gateway client CN `branch-gw`, LAN `10.30.0.0/24`. On the server:

```conf
client-config-dir /etc/openvpn/server/ccd
route 10.30.0.0 255.255.255.0
```

In `/etc/openvpn/server/ccd/branch-gw`:

```conf
iroute 10.30.0.0 255.255.255.0
```

`route` directs the OS toward the VPN. `iroute` identifies the client owning that subnet inside OpenVPN. DCO can influence route installation details; the explicit pair documents the conventional userspace design.

The branch gateway must enable forwarding and have firewall allowances. Branch hosts need a return route to the main-site/tunnel networks; main-site hosts need a route to the branch through the VPN server. Push the branch route to other clients only if they should access it, and allow that traffic deliberately. Overlapping branch networks require redesign or carefully planned translation.

`ccd-exclusive` can require a corresponding CCD file before admitting a client, but it is not an application authorization system. Certificate identities, routes, and firewall permissions are separate controls.

## Control-channel protection

The baseline uses `tls-crypt` with a shared group key. An alternative is `tls-crypt-v2` with distinct per-client keys:

```sh
umask 077
openvpn --genkey tls-crypt-v2-server tls-crypt-v2-server.key
openvpn --tls-crypt-v2 tls-crypt-v2-server.key \
  --genkey tls-crypt-v2-client laptop-01-tls-crypt-v2.key
```

Then replace the baseline `tls-crypt` directive on each side:

```conf
# Server
tls-crypt-v2 /etc/openvpn/server/tls-crypt-v2-server.key

# Client, in its separate profile
tls-crypt-v2 laptop-01-tls-crypt-v2.key
```

Do not put both snippets into one profile. Protect the server wrapping key and client-specific keys. Certificate revocation is still required; a per-client tls-crypt key is not a replacement for identity validation or access policy.

Legacy `tls-auth` uses a shared authentication key and typically complementary directions (`0` server, `1` client). Do not copy `key-direction` into a tls-crypt-only configuration, or mix the three key modes without understanding interoperability.

## Authentication and revocation

The baseline authenticates clients using certificates. If you add username/password or MFA, configure a real server-side authentication plugin/service as well as the client prompt:

```conf
# Client only, when the server is configured for this authentication
auth-user-pass
auth-nocache
```

Adding `auth-user-pass` to a client does not configure a server authentication database or MFA. Avoid password files where an interactive prompt or supported secure credential store is available. Password-only designs require separate assessment; do not disable required client certificates casually.

### Revoke a device

In the CA administration environment:

```sh
./easyrsa revoke laptop-01
./easyrsa gen-crl
openssl crl -in pki/crl.pem -noout -lastupdate -nextupdate
```

Securely deploy the updated CRL to the server's configured `crl-verify` path with permissions readable by the running daemon. Verify the affected client can no longer establish a new connection. Terminate an already-connected compromised session deliberately; publishing a CRL is not guaranteed to instantly disconnect it. Track CRL expiration and renew it even when no new certificates are revoked.

If a client private key was publicly exposed, revoke/reissue it. If a shared tls-crypt group key was exposed, rotate it across participants. If the CA private key was exposed, plan trust-anchor replacement; deleting a GitHub file does not restore secrecy.

## Operations and validation

```sh
openvpn --version
openvpn --show-ciphers
ip -br address
ip route
ip -6 route
ss -lunp
```

Common systemd packaging uses `openvpn-server@server` for `/etc/openvpn/server/server.conf`, but unit names and locations differ. Inspect what your package installed:

```sh
systemctl list-unit-files 'openvpn*'
systemctl cat openvpn-server@server
sudo systemctl status openvpn-server@server
sudo journalctl -u openvpn-server@server --since '15 minutes ago'
```

After provisioning and reviewing the configuration, a typical package startup is:

```sh
sudo systemctl enable --now openvpn-server@server
```

For foreground debugging on a lab host, stop any conflicting instance first:

```sh
sudo openvpn --config /etc/openvpn/server/server.conf
```

This is a real startup, not a harmless syntax-only check: it opens sockets and can configure networking or execute configured hooks. OpenVPN does not offer a universal equivalent of `nginx -t` that validates all runtime behavior without side effects. `--test-crypto` tests a different aspect and is not a complete TLS server configuration validator.

### Connection verification sequence

1. Confirm client DNS resolves the intended VPN endpoint.
2. Confirm listener, upstream port forwarding, and cloud/host firewall permissions.
3. Connect and inspect both logs for successful TLS/authentication and assigned tunnel address.
4. Inspect client routes and DNS state (`ip route`, `ip -6 route`, `resolvectl status` where available).
5. Reach a permitted tunnel/server service, then a permitted LAN service.
6. For full tunnel, compare observed IPv4 and IPv6 egress using a trusted check endpoint or server you control.
7. Verify actual DNS behavior, including browsers and split-DNS domains.
8. Disconnect and test the intended fail-open/fail-closed policy.
9. Test reboot/reconnect, revoked credentials, and an unauthorized destination.

Optional status output, after provisioning a writable, protected path:

```conf
status /var/log/openvpn/server-status.log 10
status-version 3
```

Status records contain client identity and addressing details. Restrict access and rotate operational logs. Keep management interfaces local and protected; a publicly exposed unauthenticated management interface is not an acceptable monitoring shortcut.

## Troubleshooting matrix

| Symptom | Likely causes | Useful checks |
|---|---|---|
| TLS negotiation timeout | UDP filtered, wrong endpoint/port, transport mismatch, control-key mismatch | Listener, both-side logs, WAN capture |
| Certificate verification failure | Wrong CA, expired cert/CRL, clock skew, role/name mismatch | `openssl x509`, system time, configured identity |
| `AUTH_FAILED` | Credentials/plugin policy; sometimes negotiation-related message details | Full surrounding logs, authentication backend |
| No shared cipher | `data-ciphers` overlap absent, old peer, unsupported cipher | Versions, `--show-ciphers`, configured list |
| Connects but no LAN access | Route missing, FORWARD denied, return route absent | Client route, server counters, LAN gateway |
| IP access works but names fail | Resolver not applied/reachable, split-DNS issue | Resolver state, direct DNS query, TCP/UDP 53 |
| Internet fails only in full tunnel | No forwarding/NAT/return path | Server forwarding sysctl, WAN rules |
| Client still uses local IPv6 | Only IPv4 was redirected | IPv6 routes and endpoint firewall |
| Some sites hang | MTU/PMTU issue, blocked ICMP, DNS/TCP problem | Packet sizes, retransmits, ICMP visibility |
| Permission denied after startup | Privilege drop, CRL/log path ownership, service sandbox | Running identity, directory permissions, unit restrictions |
| Route conflicts | Client LAN overlaps VPN/LAN networks | Routes and subnet design |
| Duplicate identity/session issues | Reused client certificates | Issue unique certs; avoid `duplicate-cn` shortcut |

## MTU, transport, and performance

- Prefer UDP for ordinary routed VPN use. TCP transport is sometimes necessary through restricted networks, but carrying TCP inside TCP can amplify loss/retransmission delays.
- If switching transport, update both endpoints (`tcp-server`/`tcp-client` as appropriate), listener permissions, and upstream forwarding.
- Diagnose path-MTU behavior before tuning. Preserve ICMP error traffic and inspect fragmentation/retransmission.
- `mssfix` syntax and interpretation vary by version. A documented 2.6-style example is `mssfix 1360 mtu`, but 1360 is a test value, not a universal optimum.
- `fragment` can interact with offload and compatibility; do not enable it as a default.
- Data Channel Offload (DCO) requires compatible operating-system support and configuration. It can improve throughput but changes which options and packet paths apply. Inspect startup logs; do not assume activation.
- Keep compression disabled. Do not add obsolete `comp-lzo` or `compress` directives to silence mismatches without understanding the other peer's configuration and compression risks.
- Avoid legacy `cipher BF-CBC`, static-key `secret` tutorials, blanket verification bypasses, and disabling encryption as troubleshooting shortcuts.
- AEAD `data-ciphers` control the data channel; `tls-cipher`/`tls-ciphersuites` control TLS and are different settings. Avoid arbitrary TLS cipher overrides unless required and verified.

## Public repository hygiene

Good public content: this Markdown, invalid placeholders, generic topology diagrams, and configs containing no real credentials or identifying details.

Keep private: real `.ovpn` profiles, private keys, passwords, auth files, shared control keys, CA signing material, logs, and status reports. A certificate is public-key material, but it can still reveal identity information; use placeholders here.

Review Git history as well as the current tree. If a secret was committed, revoke/rotate first and then clean history as appropriate. `.gitignore` does not untrack existing files, prevent all manual uploads, or remove secrets from past commits.

## Official references

- [OpenVPN Community 2.6 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html) — versioned directive semantics.
- [OpenVPN community documentation](https://openvpn.net/community-docs/) — deployment and platform documentation.
- [Easy-RSA documentation](https://easy-rsa.readthedocs.io/en/latest/) — PKI workflow and request/certificate handling.
- [Easy-RSA project](https://github.com/OpenVPN/easy-rsa) — official project and versioned releases.
- Installed manual: `man openvpn`; installed package documentation for systemd units and resolver integration.
