#!/usr/bin/env bash
# master.sh — self-contained persistent launcher with all tools embedded.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION=2.0.0
SESSION_DIR=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

cleanup() {
    [[ -n ${SESSION_DIR:-} && -d $SESSION_DIR ]] || return 0
    rm -f -- "$SESSION_DIR/nmap.sh" "$SESSION_DIR/ssh-tunnel-master.sh" "$SESSION_DIR/ipip-tunnel-master.sh"
    rmdir -- "$SESSION_DIR" 2>/dev/null || true
}
trap cleanup EXIT

write_nmap_payload() {
    cat > "$1" <<'__MASTER_NMAP_PAYLOAD__'
#!/usr/bin/env bash
# nmap.sh — interactive Nmap scan menu and advanced command wrapper.
# Use only on systems and networks you own or are explicitly authorized to test.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION="2.0.0"
NMAP_BIN=${NMAP_BIN:-nmap}

profile="default"
declare -a targets=() target_files=() excludes=() exclude_files=()
declare -a nmap_args=() raw_args=()
declare -a script_selectors=() script_args=()
output_base=""
output_dir=""
output_mode="normal"
resume_file=""
dry_run=0
authorized=0
verbose_wrapper=0
sudo_mode="auto"
show_command_only=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
note() { printf '%s\n' "$*" >&2; }
need_value() { (($# >= 2)) || die "$1 requires a value"; [[ -n $2 ]] || die "$1 requires a non-empty value"; }

quote_command() {
    local arg
    printf 'Command:'
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
}

usage() {
cat <<'HELP'
nmap.sh — beginner-friendly scan menu with advanced Nmap compatibility

USAGE
  nmap.sh                         Open the interactive scan menu
  nmap.sh [OPTIONS] -t TARGET     Advanced non-interactive use
  nmap.sh --list-profiles
  nmap.sh --explain PROFILE

SAFETY / EXECUTION
  --authorized              Confirm you are authorized; required to execute scans.
  --dry-run                 Build and print the command; do not execute or require Nmap.
  --show-command            Alias for --dry-run.
  --sudo MODE               auto (default), always, or never.
  --nmap-bin PATH           Nmap executable; default: nmap or $NMAP_BIN.
  -h, --help                Show this full help.
  --version                 Show wrapper version.

TARGETS
  -t, --target SPEC         Hostname, IP, CIDR, range, or other native Nmap target.
                            Repeatable. Quote shell wildcards/ranges when appropriate.
  -iL, --target-file FILE   Read targets using Nmap -iL. Repeatable.
  --exclude SPEC            Native Nmap --exclude specification. Repeatable.
  --exclude-file FILE       Native Nmap --excludefile. Repeatable.
  -4, --ipv4                Use IPv4 (Nmap's default; accepted as a readable no-op).
  -6, --ipv6                Force IPv6.

PRESETS
  -P, --profile NAME        Select one profile; default is Nmap's default behavior.
  --list-profiles           Show every built-in profile.
  --explain NAME            Explain one profile and its generated flags.

PORT SELECTION
  -p, --ports SPEC          Examples: 22; 22,80,443; 1-1024; T:22,80,U:53,161; -
  --exclude-ports SPEC      Native --exclude-ports.
  --top-ports N             Scan the N most common ports.
  --port-ratio RATIO        Scan ports more common than RATIO (0.0 through 1.0).
  -F, --fast                Native fast mode (fewer ports).
  -r, --sequential-ports    Do not randomize port order.

DISCOVERY
  -Pn, --no-discovery       Treat targets as online; skip host discovery.
  -sn, --discovery-only     Host discovery only; no port scan.
  -PR, --arp-ping           ARP/neighbor discovery on local Ethernet.
  -PE, --icmp-echo          ICMP echo discovery.
  -PP, --icmp-timestamp     ICMP timestamp discovery.
  -PM, --icmp-netmask       ICMP netmask discovery.
  -PS, --tcp-syn-ping LIST  TCP SYN discovery ports, e.g. 22,80,443.
  -PA, --tcp-ack-ping LIST  TCP ACK discovery ports.
  -PU, --udp-ping LIST      UDP discovery ports.
  -PY, --sctp-ping LIST     SCTP INIT discovery ports.
  -PO, --protocol-ping LIST IP protocol discovery list.
  --disable-arp-ping        Native --disable-arp-ping.

SCAN TECHNIQUE
  Profiles select techniques, or pass native flags after --. Common native flags:
    -sS SYN       -sT connect     -sU UDP          -sA ACK
    -sW window    -sN NULL        -sF FIN          -sX Xmas
    -sM Maimon    -sY SCTP INIT   -sZ SCTP COOKIE  -sO IP protocols
  --scan-type TYPE          Named type: syn, connect, udp, ack, window, null, fin,
                            xmas, maimon, sctp-init, sctp-cookie, ip-protocol.
                            Repeatable only where native Nmap permits combinations.

SERVICE / OS / ROUTE INFORMATION
  -sV, --service            Enable service/version detection.
  --version-intensity N     0 through 9.
  --version-light           Native light version detection.
  --version-all             Try every version probe.
  --version-trace           Trace version-detection activity.
  -O, --os                  Enable OS detection.
  --osscan-limit            Limit OS detection to promising targets.
  --osscan-guess            Guess more aggressively.
  --max-os-tries N          Maximum OS detection tries.
  --traceroute              Trace routes to targets.
  -A, --aggressive          OS, version, default scripts, and traceroute.

NSE SCRIPT ENGINE
  -sC, --default-scripts    Nmap default script set.
  --script SELECTOR         Script name, category, expression, directory, or file.
                            Repeatable; selectors are joined with commas.
  --script-args ARGS        Native key=value script arguments. Repeatable.
  --script-args-file FILE   Native script argument file.
  --script-help SELECTOR    Display native help for scripts matching selector.
  --script-trace            Show NSE communications.
  --script-updatedb         Update script database; target is not required.
  NSE scripts vary from passive information collection to intrusive checks.
  Review script documentation and arguments before execution.

TIMING / PERFORMANCE
  -T, --timing N|NAME       0-5 or paranoid/sneaky/polite/normal/aggressive/insane.
  --min-rate N              Minimum packets per second.
  --max-rate N              Maximum packets per second.
  --min-parallelism N       Minimum parallel probes.
  --max-parallelism N       Maximum parallel probes.
  --min-hostgroup N         Minimum hosts scanned together.
  --max-hostgroup N         Maximum hosts scanned together.
  --min-rtt-timeout TIME    Examples: 100ms, 1s.
  --max-rtt-timeout TIME
  --initial-rtt-timeout TIME
  --max-retries N
  --host-timeout TIME       Give up on a host after this time.
  --scan-delay TIME         Delay between probes to a host.
  --max-scan-delay TIME

DNS / ROUTING / INTERFACE
  -n, --no-dns              Disable reverse DNS resolution.
  -R, --always-dns          Always perform reverse DNS.
  --system-dns              Use system resolver.
  --dns-servers LIST        Comma-separated resolver addresses.
  -e, --interface NAME      Network interface.
  -S, --source-address IP   Source address (must be valid for the host/path).
  -g, --source-port PORT    Source port / --source-port.
  --send-eth                Send at raw Ethernet layer where supported.
  --send-ip                 Send using raw IP sockets.
  --privileged              Tell Nmap to assume raw-socket privilege.
  --unprivileged            Tell Nmap to assume no raw-socket privilege.

RESULT FILTERS / DETAIL
  --open                    Show only open or possibly open ports.
  --reason                  Explain port/host states.
  -v, --verbose             Increase Nmap verbosity; repeatable.
  -d, --debug               Increase Nmap debugging; repeatable.
  --packet-trace            Show sent and received packets.
  --iflist                  Print interfaces/routes; target is not required.
  --stats-every TIME        Periodic status, e.g. 10s.
  --stylesheet PATH         XML stylesheet.
  --webxml                  Reference Nmap.org stylesheet.
  --no-stylesheet           Omit XML stylesheet.

OUTPUT
  -oA, --output-all BASE    Normal, XML, and grepable output using BASE.
  -oN, --output-normal FILE Normal text output.
  -oX, --output-xml FILE    XML output.
  -oG, --output-grep FILE   Grepable output (deprecated by Nmap but available).
  -oS, --output-script FILE Script-kiddie output.
  --output-dir DIR          Create directory and place generated output there.
  --append-output           Native --append-output.
  --resume FILE             Native --resume; cannot be combined with targets/options.

PACKET / ADVANCED OPTIONS
  --mtu N                   Native --mtu (must meet Nmap's requirements).
  --fragment                Native -f; repeat to request additional fragmentation.
  --data-length N           Append random data to sent packets.
  --ttl N                   Set IPv4 TTL.
  --spoof-mac VALUE         Native --spoof-mac. Use only on a network you administer.
  --scanflags FLAGS         Custom TCP flags; interpretation uses the chosen scan type.
  --badsum                  Send invalid checksums for firewall/IDS testing.
  --adler32                 Deprecated SCTP checksum option, where supported.

FULL NMAP COMPATIBILITY
  --nmap-arg ARG            Add one exact native Nmap argument. Repeatable.
  -- ARGS...                Pass every remaining argument directly to Nmap.

  Arguments are stored in Bash arrays and executed without eval. Use separate shell
  words exactly as Nmap expects, for example:
    -- --proxies http://127.0.0.1:8080 --allports
    --nmap-arg=--defeat-rst-ratelimit

PROFILES (see --list-profiles for generated flags)
  default, discovery, arp-discovery, icmp-discovery, tcp-discovery,
  syn, connect, udp, syn-udp, ack, window, null, fin, xmas, maimon,
  sctp-init, sctp-cookie, ip-protocol, quick, full-tcp, service,
  os, inventory, aggressive, default-scripts, safe-scripts, vuln-scripts,
  web, dns, smb, ssh, database, firewall-review.

EXAMPLES
  # Show a reviewed command without sending traffic:
  nmap.sh --dry-run -P inventory -t 10.20.0.0/24 -oA inventory

  # Execute an authorized TCP inventory with output files:
  nmap.sh --authorized -P inventory -t 10.20.0.0/24 \
    --top-ports 200 --timing 3 --output-dir results -oA office

  # UDP services, bounded ports/rate and no discovery:
  sudo nmap.sh --authorized -P udp -Pn -t 10.20.0.53 \
    -p 53,123,161 --max-rate 50 -sV --reason

  # Native feature not modeled by the wrapper:
  nmap.sh --dry-run -t 10.20.0.10 -- -sS --defeat-rst-ratelimit

EXIT STATUS
  0 success/help/dry-run; 2 wrapper usage error; 3 authorization missing;
  4 dependency/output error; otherwise Nmap's own exit status.
HELP
}

list_profiles() {
cat <<'PROFILES'
PROFILE           GENERATED NMAP FLAGS              PURPOSE
default           (none)                            Native Nmap defaults
discovery         -sn                               Host discovery only
arp-discovery     -sn -PR                           Local-link ARP discovery
icmp-discovery    -sn -PE -PP                       ICMP discovery
tcp-discovery     -sn -PS22,80,443 -PA80,443        TCP discovery only
syn               -sS                               TCP SYN scan (privileged)
connect           -sT                               TCP connect scan
udp               -sU                               UDP scan
syn-udp           -sS -sU                           TCP SYN plus UDP
ack               -sA                               Firewall reachability mapping
window            -sW                               TCP window scan
null              -sN                               TCP NULL scan
fin               -sF                               TCP FIN scan
xmas              -sX                               TCP Xmas scan
maimon            -sM                               TCP Maimon scan
sctp-init         -sY                               SCTP INIT scan
sctp-cookie       -sZ                               SCTP COOKIE ECHO scan
ip-protocol       -sO                               IP protocol scan
quick             -T4 -F                            Faster common-port scan
full-tcp          -sS -p-                           All TCP ports
service           -sV                               Service detection
os                -O --osscan-limit                 OS detection
inventory         -sS -sV -O --osscan-limit        General host inventory
aggressive        -A -T4                            Nmap aggressive feature bundle
default-scripts   -sC                               Default NSE scripts
safe-scripts      --script safe                     NSE safe category
vuln-scripts      --script vuln                     NSE vulnerability checks; review first
web               -sT -sV -p 80,443,8000,8080,8443 Web service inventory
dns               -sU -sT -sV -p U:53,T:53         DNS TCP/UDP inventory
smb               -sT -sV -p 139,445                SMB service inventory
ssh               -sT -sV -p 22                     SSH service inventory
database          -sT -sV -p common DB ports        Database service inventory
firewall-review   -sA --reason                       ACK filtering review
PROFILES
}

profile_args() {
    local name=$1
    case "$name" in
        default) ;;
        discovery) nmap_args+=( -sn ) ;;
        arp-discovery) nmap_args+=( -sn -PR ) ;;
        icmp-discovery) nmap_args+=( -sn -PE -PP ) ;;
        tcp-discovery) nmap_args+=( -sn -PS22,80,443 -PA80,443 ) ;;
        syn) nmap_args+=( -sS ) ;;
        connect) nmap_args+=( -sT ) ;;
        udp) nmap_args+=( -sU ) ;;
        syn-udp) nmap_args+=( -sS -sU ) ;;
        ack) nmap_args+=( -sA ) ;;
        window) nmap_args+=( -sW ) ;;
        null) nmap_args+=( -sN ) ;;
        fin) nmap_args+=( -sF ) ;;
        xmas) nmap_args+=( -sX ) ;;
        maimon) nmap_args+=( -sM ) ;;
        sctp-init) nmap_args+=( -sY ) ;;
        sctp-cookie) nmap_args+=( -sZ ) ;;
        ip-protocol) nmap_args+=( -sO ) ;;
        quick) nmap_args+=( -T4 -F ) ;;
        full-tcp) nmap_args+=( -sS -p- ) ;;
        service) nmap_args+=( -sV ) ;;
        os) nmap_args+=( -O --osscan-limit ) ;;
        inventory) nmap_args+=( -sS -sV -O --osscan-limit ) ;;
        aggressive) nmap_args+=( -A -T4 ) ;;
        default-scripts) nmap_args+=( -sC ) ;;
        safe-scripts) nmap_args+=( --script safe ) ;;
        vuln-scripts) nmap_args+=( --script vuln ) ;;
        web) nmap_args+=( -sT -sV -p 80,443,8000,8080,8443 ) ;;
        dns) nmap_args+=( -sU -sT -sV -p U:53,T:53 ) ;;
        smb) nmap_args+=( -sT -sV -p 139,445 ) ;;
        ssh) nmap_args+=( -sT -sV -p 22 ) ;;
        database) nmap_args+=( -sT -sV -p 1433,1521,3306,5432,6379,9042,9200,27017 ) ;;
        firewall-review) nmap_args+=( -sA --reason ) ;;
        *) die "unknown profile: $name (use --list-profiles)" ;;
    esac
}

scan_type_arg() {
    case "$1" in
        syn) printf '%s' -sS ;; connect) printf '%s' -sT ;; udp) printf '%s' -sU ;;
        ack) printf '%s' -sA ;; window) printf '%s' -sW ;; null) printf '%s' -sN ;;
        fin) printf '%s' -sF ;; xmas) printf '%s' -sX ;; maimon) printf '%s' -sM ;;
        sctp-init) printf '%s' -sY ;; sctp-cookie) printf '%s' -sZ ;;
        ip-protocol) printf '%s' -sO ;;
        *) die "unknown scan type: $1" ;;
    esac
}

requires_privilege() {
    local arg
    for arg in "${nmap_args[@]}" "${raw_args[@]}"; do
        case "$arg" in
            -sS|-sU|-sA|-sW|-sN|-sF|-sX|-sM|-sY|-sZ|-sO|-O|-PR|-PE|-PP|-PM|-PY*|-PO*|-f|--mtu|--spoof-mac|--scanflags|--badsum|--send-eth|--privileged)
                return 0 ;;
        esac
    done
    return 1
}

script_path() {
    local source=${BASH_SOURCE[0]}
    if command -v realpath >/dev/null 2>&1; then realpath "$source"
    elif command -v readlink >/dev/null 2>&1 && readlink -f "$source" >/dev/null 2>&1; then readlink -f "$source"
    else (cd -P -- "$(dirname -- "$source")" && printf '%s/%s\n' "$PWD" "$(basename -- "$source")")
    fi
}

menu_pause() { printf '\n'; read -r -p 'Press Enter to return to the scan menu...' _ || true; }

interactive_nmap() {
    local choice profile description target ports timing skip_discovery save_output output_name action self
    local ask_ports
    local -a run_args=()
    self=$(script_path)
    while :; do
        cat <<'MENU'

NMAP SCAN MENU
Choose what you want to learn. The tool will explain the scan before asking
for a target. Nothing is scanned until you choose RUN.

 NETWORK AND HOST DISCOVERY
   1) Find online hosts — no port scan
   2) Find hosts on the local LAN with ARP
   3) Find hosts using common TCP discovery probes

 EVERYDAY PORT SCANS
   4) Quick scan of common TCP ports
   5) TCP SYN scan — common privileged TCP scan
   6) TCP connect scan — works without raw-packet privileges
   7) All 65,535 TCP ports
   8) UDP ports
   9) Combined TCP SYN and UDP scan
  10) Identify services and versions
  11) General inventory — TCP, services, and operating system
  12) Aggressive information scan
  13) Operating-system detection

 NSE SCRIPT SCANS
  14) Nmap default scripts
  15) Scripts categorized as safe
  16) Vulnerability-check scripts — review before running

 SERVICE-FOCUSED SCANS
  17) Web services
  18) DNS service over TCP and UDP
  19) SMB/file-sharing services
  20) SSH service
  21) Common database services

 FIREWALL AND SPECIALIZED SCANS
  22) ACK firewall-filtering scan
  23) Window scan
  24) FIN scan
  25) NULL scan
  26) Xmas scan
  27) Maimon scan
  28) SCTP INIT scan
  29) SCTP COOKIE-ECHO scan
  30) IP protocol scan

  H) Full advanced command-line help
  Q) Quit
MENU
        read -r -p 'Scan choice: ' choice || return
        ask_ports=yes
        case ${choice,,} in
            1) profile=discovery; ask_ports=no; description='Find which targets respond, without scanning their ports.' ;;
            2) profile=arp-discovery; ask_ports=no; description='Use ARP on the directly connected LAN. This is usually the most reliable local-network discovery.' ;;
            3) profile=tcp-discovery; ask_ports=no; description='Look for hosts using TCP probes to ports 22, 80, and 443, without a port scan.' ;;
            4) profile=quick; ask_ports=no; description='Scan a reduced list of common TCP ports with faster timing.' ;;
            5) profile=syn; description='Send TCP SYN probes. It is fast and normally needs root/sudo.' ;;
            6) profile=connect; description='Complete operating-system TCP connections. It is useful when raw SYN scans are unavailable.' ;;
            7) profile=full-tcp; ask_ports=no; description='Scan every TCP port from 1 through 65535. This can take a long time.' ;;
            8) profile=udp; description='Scan UDP services. UDP scans are commonly much slower than TCP scans.' ;;
            9) profile=syn-udp; description='Scan both TCP SYN and UDP ports in one Nmap run.' ;;
            10) profile=service; description='Probe open ports to identify the software and version answering.' ;;
            11) profile=inventory; description='Collect TCP port, service-version, and operating-system information.' ;;
            12) profile=aggressive; description='Enable OS detection, version detection, default scripts, and traceroute.' ;;
            13) profile=os; description='Compare network responses with Nmap fingerprints to estimate the operating system.' ;;
            14) profile=default-scripts; description='Run Nmap scripts selected for its default script set.' ;;
            15) profile=safe-scripts; description='Run NSE scripts categorized as safe by Nmap.' ;;
            16) profile=vuln-scripts; description='Run NSE vulnerability-check scripts. Some may be intrusive or produce false positives.' ;;
            17) profile=web; ask_ports=no; description='Check common HTTP/HTTPS ports and identify their services.' ;;
            18) profile=dns; ask_ports=no; description='Check DNS on TCP and UDP port 53 and identify the service.' ;;
            19) profile=smb; ask_ports=no; description='Check SMB/NetBIOS ports 139 and 445.' ;;
            20) profile=ssh; ask_ports=no; description='Check TCP port 22 and identify the SSH server.' ;;
            21) profile=database; ask_ports=no; description='Check common SQL, Redis, Cassandra, Elasticsearch, and MongoDB ports.' ;;
            22) profile=firewall-review; description='Send ACK probes to help distinguish filtered from unfiltered TCP ports.' ;;
            23) profile=window; description='Use TCP window behavior to classify ports on systems where this technique works.' ;;
            24) profile=fin; description='Send TCP FIN probes. Results depend heavily on the target operating system and firewall.' ;;
            25) profile=null; description='Send TCP packets with no flags set.' ;;
            26) profile=xmas; description='Send FIN, PSH, and URG flags together.' ;;
            27) profile=maimon; description='Use the TCP Maimon FIN/ACK technique.' ;;
            28) profile=sctp-init; description='Scan SCTP services with INIT chunks.' ;;
            29) profile=sctp-cookie; description='Scan SCTP services with COOKIE-ECHO chunks.' ;;
            30) profile=ip-protocol; ask_ports=no; description='Find supported IP protocols rather than TCP or UDP ports.' ;;
            h) usage; menu_pause; continue ;;
            q) return ;;
            *) printf 'That is not a menu choice.\n'; continue ;;
        esac

        printf '\nSELECTED: %s\n\n' "$description"
        printf 'TARGET EXAMPLES\n'
        printf '  One host:       192.0.2.10\n  A subnet:       192.0.2.0/24\n  A range:        192.0.2.10-50\n  A hostname:     server.example.com\n'
        read -r -p 'Target you own or are authorized to scan: ' target
        [[ -n $target ]] || { printf 'No target entered.\n'; continue; }
        run_args=(--profile "$profile" --target "$target")

        if [[ $ask_ports == yes ]]; then
            printf '\nPORTS\nLeave blank for Nmap defaults. Examples: 22,80,443 or 1-1024.\nType top:100 to scan the 100 most common ports.\n'
            read -r -p 'Ports: ' ports
            if [[ $ports == top:* ]]; then run_args+=(--top-ports "${ports#top:}")
            elif [[ -n $ports ]]; then run_args+=(--ports "$ports"); fi
        fi

        printf '\nSPEED\n  1) Careful/slower (T2)\n  2) Normal (T3, recommended)\n  3) Faster (T4; may lose results on weak or distant networks)\n'
        read -r -p 'Speed [2]: ' timing
        case ${timing:-2} in 1) timing=2 ;; 2) timing=3 ;; 3) timing=4 ;; *) timing=3 ;; esac
        run_args+=(--timing "$timing")

        if [[ $profile != discovery && $profile != arp-discovery && $profile != tcp-discovery ]]; then
            read -r -p 'If ping discovery is blocked, treat the target as online? [y/N]: ' skip_discovery
            case ${skip_discovery,,} in y|yes) run_args+=(--no-discovery) ;; esac
        fi

        read -r -p 'Save normal, XML, and grepable results? [y/N]: ' save_output
        case ${save_output,,} in
            y|yes) read -r -p 'Output base name [nmap-results]: ' output_name; output_name=${output_name:-nmap-results}; run_args+=(--output-all "$output_name") ;;
        esac

        while :; do
            printf '\n  P) Preview the exact command\n  R) Run the scan now\n  B) Go back without scanning\n'
            read -r -p 'Action: ' action
            case ${action,,} in
                p) bash "$self" --dry-run "${run_args[@]}"; menu_pause; break ;;
                r) if bash "$self" --authorized "${run_args[@]}"; then scan_status=0; else scan_status=$?; fi; printf '\nScan finished with status %s.\n' "$scan_status"; menu_pause; break ;;
                b) break ;;
                *) printf 'Choose P, R, or B.\n' ;;
            esac
        done
    done
}

if (($# == 0)); then interactive_nmap; exit 0; fi

while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --version) printf '%s %s\n' "$PROGRAM" "$VERSION"; exit 0 ;;
        --list-profiles) list_profiles; exit 0 ;;
        --explain) need_value "$1" "${2-}"; tmp=(); old=("${nmap_args[@]}"); nmap_args=(); profile_args "$2"; printf '%s: ' "$2"; quote_command nmap "${nmap_args[@]}" TARGET; nmap_args=("${old[@]}"); exit 0 ;;
        --authorized) authorized=1 ;;
        --dry-run|--show-command) dry_run=1 ; show_command_only=1 ;;
        --sudo) need_value "$1" "${2-}"; sudo_mode=$2; shift ;;
        --sudo=*) sudo_mode=${1#*=} ;;
        --nmap-bin) need_value "$1" "${2-}"; NMAP_BIN=$2; shift ;;
        --nmap-bin=*) NMAP_BIN=${1#*=} ;;
        -P|--profile) need_value "$1" "${2-}"; profile=$2; shift ;;
        --profile=*) profile=${1#*=} ;;
        -t|--target) need_value "$1" "${2-}"; targets+=( "$2" ); shift ;;
        --target=*) targets+=( "${1#*=}" ) ;;
        -iL|--target-file) need_value "$1" "${2-}"; target_files+=( "$2" ); shift ;;
        --target-file=*) target_files+=( "${1#*=}" ) ;;
        --exclude) need_value "$1" "${2-}"; excludes+=( "$2" ); shift ;;
        --exclude=*) excludes+=( "${1#*=}" ) ;;
        --exclude-file) need_value "$1" "${2-}"; exclude_files+=( "$2" ); shift ;;
        --exclude-file=*) exclude_files+=( "${1#*=}" ) ;;
        -4|--ipv4) : ;; # IPv4 is Nmap's default; Nmap has no required -4 flag.
        -6|--ipv6) nmap_args+=( -6 ) ;;
        -p|--ports) need_value "$1" "${2-}"; nmap_args+=( -p "$2" ); shift ;;
        --ports=*) nmap_args+=( -p "${1#*=}" ) ;;
        --exclude-ports) need_value "$1" "${2-}"; nmap_args+=( --exclude-ports "$2" ); shift ;;
        --top-ports) need_value "$1" "${2-}"; nmap_args+=( --top-ports "$2" ); shift ;;
        --port-ratio) need_value "$1" "${2-}"; nmap_args+=( --port-ratio "$2" ); shift ;;
        -F|--fast) nmap_args+=( -F ) ;;
        -r|--sequential-ports) nmap_args+=( -r ) ;;
        -Pn|--no-discovery) nmap_args+=( -Pn ) ;;
        -sn|--discovery-only) nmap_args+=( -sn ) ;;
        -PR|--arp-ping) nmap_args+=( -PR ) ;;
        -PE|--icmp-echo) nmap_args+=( -PE ) ;;
        -PP|--icmp-timestamp) nmap_args+=( -PP ) ;;
        -PM|--icmp-netmask) nmap_args+=( -PM ) ;;
        -PS|--tcp-syn-ping) need_value "$1" "${2-}"; nmap_args+=( "-PS$2" ); shift ;;
        -PA|--tcp-ack-ping) need_value "$1" "${2-}"; nmap_args+=( "-PA$2" ); shift ;;
        -PU|--udp-ping) need_value "$1" "${2-}"; nmap_args+=( "-PU$2" ); shift ;;
        -PY|--sctp-ping) need_value "$1" "${2-}"; nmap_args+=( "-PY$2" ); shift ;;
        -PO|--protocol-ping) need_value "$1" "${2-}"; nmap_args+=( "-PO$2" ); shift ;;
        --disable-arp-ping) nmap_args+=( --disable-arp-ping ) ;;
        --scan-type) need_value "$1" "${2-}"; nmap_args+=( "$(scan_type_arg "$2")" ); shift ;;
        --scan-type=*) nmap_args+=( "$(scan_type_arg "${1#*=}")" ) ;;
        -sV|--service) nmap_args+=( -sV ) ;;
        --version-intensity) need_value "$1" "${2-}"; nmap_args+=( --version-intensity "$2" ); shift ;;
        --version-light|--version-all|--version-trace|--osscan-limit|--osscan-guess|--traceroute|--open|--reason|--packet-trace|--system-dns|--send-eth|--send-ip|--privileged|--unprivileged|--webxml|--no-stylesheet|--script-trace|--append-output|--badsum|--adler32) nmap_args+=( "$1" ) ;;
        -O|--os) nmap_args+=( -O ) ;;
        --max-os-tries|--script-args-file|--script-help|--min-rate|--max-rate|--min-parallelism|--max-parallelism|--min-hostgroup|--max-hostgroup|--min-rtt-timeout|--max-rtt-timeout|--initial-rtt-timeout|--max-retries|--host-timeout|--scan-delay|--max-scan-delay|--dns-servers|--stats-every|--stylesheet|--mtu|--data-length|--ttl|--spoof-mac|--scanflags)
            need_value "$1" "${2-}"; nmap_args+=( "$1" "$2" ); shift ;;
        -A|--aggressive) nmap_args+=( -A ) ;;
        -sC|--default-scripts) nmap_args+=( -sC ) ;;
        --script) need_value "$1" "${2-}"; script_selectors+=( "$2" ); shift ;;
        --script=*) script_selectors+=( "${1#*=}" ) ;;
        --script-args) need_value "$1" "${2-}"; script_args+=( "$2" ); shift ;;
        --script-args=*) script_args+=( "${1#*=}" ) ;;
        --script-updatedb) nmap_args+=( --script-updatedb ) ;;
        -T|--timing) need_value "$1" "${2-}"; nmap_args+=( "-T$2" ); shift ;;
        --timing=*) nmap_args+=( "-T${1#*=}" ) ;;
        -n|--no-dns) nmap_args+=( -n ) ;;
        -R|--always-dns) nmap_args+=( -R ) ;;
        -e|--interface) need_value "$1" "${2-}"; nmap_args+=( -e "$2" ); shift ;;
        -S|--source-address) need_value "$1" "${2-}"; nmap_args+=( -S "$2" ); shift ;;
        -g|--source-port) need_value "$1" "${2-}"; nmap_args+=( -g "$2" ); shift ;;
        -v|--verbose) nmap_args+=( -v ) ;;
        -d|--debug) nmap_args+=( -d ) ;;
        --iflist) nmap_args+=( --iflist ) ;;
        -oA|--output-all) need_value "$1" "${2-}"; output_mode=all; output_base=$2; shift ;;
        -oN|--output-normal) need_value "$1" "${2-}"; output_mode=normal-file; output_base=$2; shift ;;
        -oX|--output-xml) need_value "$1" "${2-}"; output_mode=xml; output_base=$2; shift ;;
        -oG|--output-grep) need_value "$1" "${2-}"; output_mode=grep; output_base=$2; shift ;;
        -oS|--output-script) need_value "$1" "${2-}"; output_mode=script; output_base=$2; shift ;;
        --output-dir) need_value "$1" "${2-}"; output_dir=$2; shift ;;
        --resume) need_value "$1" "${2-}"; resume_file=$2; shift ;;
        --fragment) nmap_args+=( -f ) ;;
        --nmap-arg) need_value "$1" "${2-}"; raw_args+=( "$2" ); shift ;;
        --nmap-arg=*) raw_args+=( "${1#*=}" ) ;;
        --) shift; raw_args+=( "$@" ); break ;;
        -*) die "unknown wrapper option: $1 (use -- before native Nmap options)" ;;
        *) targets+=( "$1" ) ;;
    esac
    shift
done

case "$sudo_mode" in auto|always|never) ;; *) die "--sudo must be auto, always, or never" ;; esac
[[ -n $NMAP_BIN ]] || die "Nmap executable cannot be empty"

if [[ -n $resume_file ]]; then
    ((${#targets[@]} == 0 && ${#target_files[@]} == 0 && ${#nmap_args[@]} == 0 && ${#raw_args[@]} == 0 && ${#script_selectors[@]} == 0 && ${#script_args[@]} == 0)) || die "--resume cannot be combined with scan options/targets"
    nmap_args=( --resume "$resume_file" )
else
    # Put profile defaults first. Native options that use last-value semantics can
    # then be adjusted explicitly; Nmap still rejects incompatible combinations.
    declare -a user_nmap_args=( "${nmap_args[@]}" )
    nmap_args=()
    profile_args "$profile"
    nmap_args+=( "${user_nmap_args[@]}" )
fi

if ((${#script_selectors[@]})); then
    joined=$(IFS=,; printf '%s' "${script_selectors[*]}")
    nmap_args+=( --script "$joined" )
fi
if ((${#script_args[@]})); then
    joined=$(IFS=,; printf '%s' "${script_args[*]}")
    nmap_args+=( --script-args "$joined" )
fi
for item in "${target_files[@]}"; do [[ $dry_run == 1 || -r $item ]] || die "target file is not readable: $item"; nmap_args+=( -iL "$item" ); done
for item in "${excludes[@]}"; do nmap_args+=( --exclude "$item" ); done
for item in "${exclude_files[@]}"; do [[ $dry_run == 1 || -r $item ]] || die "exclude file is not readable: $item"; nmap_args+=( --excludefile "$item" ); done

if [[ -n $output_base ]]; then
    if [[ -n $output_dir ]]; then
        [[ $output_base != */* && $output_base != *\\* ]] || die "when --output-dir is used, output name must not contain a path separator"
        [[ $dry_run == 1 ]] || mkdir -p -- "$output_dir" || exit 4
        output_base="$output_dir/$output_base"
    fi
    case "$output_mode" in
        all) nmap_args+=( -oA "$output_base" ) ;;
        normal-file) nmap_args+=( -oN "$output_base" ) ;;
        xml) nmap_args+=( -oX "$output_base" ) ;;
        grep) nmap_args+=( -oG "$output_base" ) ;;
        script) nmap_args+=( -oS "$output_base" ) ;;
    esac
elif [[ -n $output_dir ]]; then
    die "--output-dir requires an output option such as -oA NAME"
fi

nmap_args+=( "${raw_args[@]}" )
nmap_args+=( "${targets[@]}" )

target_optional=0
for item in "${nmap_args[@]}"; do
    case "$item" in --iflist|--script-help|--script-updatedb|--resume) target_optional=1 ;; esac
done
if [[ $target_optional == 0 && ${#targets[@]} == 0 && ${#target_files[@]} == 0 && ${#raw_args[@]} == 0 ]]; then
    die "no target supplied (use --target or --target-file)"
fi

declare -a command=( "$NMAP_BIN" "${nmap_args[@]}" )
if [[ $sudo_mode == always ]] || { [[ $sudo_mode == auto ]] && requires_privilege && (( EUID != 0 )); }; then
    command=( sudo -- "${command[@]}" )
fi

quote_command "${command[@]}"
if [[ $dry_run == 1 ]]; then exit 0; fi
if [[ $authorized != 1 ]]; then
    printf 'Refusing to execute without --authorized. Review the command above first.\n' >&2
    exit 3
fi
if [[ ${command[0]} == sudo ]]; then
    command -v sudo >/dev/null 2>&1 || { warn "sudo is required but was not found"; exit 4; }
else
    command -v "$NMAP_BIN" >/dev/null 2>&1 || { warn "Nmap executable not found: $NMAP_BIN"; exit 4; }
fi

exec "${command[@]}"
__MASTER_NMAP_PAYLOAD__
}

write_ssh_payload() {
    cat > "$1" <<'__MASTER_SSH_PAYLOAD__'
#!/usr/bin/env bash
# ssh-tunnel-master.sh — interactive SSH tunnel builder and Terminator launcher.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION=2.0.0
SPLIT_MODE=auto
DRY_RUN=0
AUTO_LAUNCH=0
LOAD_FILE=""

declare -a T_NAME=() T_TYPE=() T_HOST=() T_USER=() T_SSH_PORT=()
declare -a T_BIND=() T_LISTEN=() T_DEST=() T_DEST_PORT=() T_IDENTITY=()
declare -a T_JUMP=() T_RECONNECT=() T_COMPRESS=() T_RAW_FLAG=() T_RAW_SPEC=()
declare -a T_ALIVE=() T_ALIVE_COUNT=()
declare -a SSH_COMMAND=() RECORD_ARGS=()
MASTER_UUID=""
LAUNCHED_COUNT=0
declare -a PANE_QUEUE_UUIDS=() PANE_QUEUE_DEPTHS=()

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
note() { printf '%s\n' "$*" >&2; }

usage() {
cat <<'HELP'
ssh-tunnel-master.sh — build unlimited labeled SSH tunnels in one Terminator window

USAGE
  ssh-tunnel-master.sh
  ssh-tunnel-master.sh --load FILE [--launch] [--split MODE]
  ssh-tunnel-master.sh --dry-run --load FILE --launch
  ssh-tunnel-master.sh --doctor

WHAT IT DOES
  The default interactive menu asks for a tunnel name, SSH server, username,
  ports, destination, key, jump host, and reconnect preference. When launched,
  every tunnel receives its own labeled Terminator pane. Panes are split in a
  balanced order so earlier tunnels do not become tiny immediately.

TUNNEL TYPES
  local         -L: open a local port that reaches a host through the SSH server
  remote        -R: open a port on the SSH server that reaches back through you
  dynamic       -D: local SOCKS4/5 proxy
  remote-socks  -R with no destination: SOCKS proxy listening on the SSH server
  raw            Exact -L, -R, -D, or -w specification for Unix sockets,
                 tunnel devices, IPv6, or another advanced OpenSSH form

OPTIONS
  --load FILE       Load a saved tunnel set before showing the menu.
  --launch          Launch immediately after --load; do not show the menu.
  --split MODE      auto, horizontal, or vertical. Default: auto.
  --dry-run         Print SSH commands and pane plan; open nothing.
  --doctor          Check Bash, ssh, Terminator, Remotinator, and autossh.
  -h, --help        Show this help.
  --version         Show version.

EXAMPLES
  ./ssh-tunnel-master.sh
  ./ssh-tunnel-master.sh --load work-tunnels.txt --launch
  ./ssh-tunnel-master.sh --dry-run --load work-tunnels.txt --launch

LOCAL FORWARD EXAMPLE
  Listen on this computer's 127.0.0.1:8080 and reach web.internal:80 through
  alice@bastion.example:22. Equivalent core SSH arguments:
    ssh -N -T -L 127.0.0.1:8080:web.internal:80 alice@bastion.example

REMOTE FORWARD EXAMPLE
  Listen on the SSH server's 127.0.0.1:9000 and send connections back to this
  computer's 127.0.0.1:3000:
    ssh -N -T -R 127.0.0.1:9000:127.0.0.1:3000 alice@server.example

DYNAMIC FORWARD EXAMPLE
  Create a local SOCKS proxy on 127.0.0.1:1080:
    ssh -N -T -D 127.0.0.1:1080 alice@bastion.example

NOTES
  * Password and key-passphrase prompts appear inside each tunnel pane.
  * Reconnect mode uses autossh with SSH keepalives and is best with key auth.
  * A remote bind beyond loopback also depends on the server's GatewayPorts.
  * Terminator DBus must be enabled; do not launch Terminator with -u/--no-dbus.
  * Saved files contain connection metadata and key paths, but never passwords.
HELP
}

doctor() {
    local failed=0 item path help_text
    printf 'SSH Tunnel Master %s dependency check\n\n' "$VERSION"
    for item in bash ssh terminator remotinator; do
        path=$(command -v "$item" 2>/dev/null || true)
        if [[ -n $path ]]; then printf '  OK       %-12s %s\n' "$item" "$path"
        else printf '  MISSING  %-12s\n' "$item"; failed=1
        fi
    done
    path=$(command -v autossh 2>/dev/null || true)
    if [[ -n $path ]]; then printf '  OPTIONAL %-12s %s\n' autossh "$path"
    else printf '  OPTIONAL %-12s not installed; reconnect mode unavailable\n' autossh
    fi
    printf '\n'
    if command -v remotinator >/dev/null 2>&1; then
        help_text=$(remotinator -h 2>&1 || true)
        if [[ $help_text == *--execute* && $help_text == *--title* ]]; then
            printf '  OK       Remotinator supports command-enabled, titled splits.\n'
        else
            printf '  INCOMPAT Remotinator lacks --execute or --title; install a current Terminator release.\n'
            failed=1
        fi
        if remotinator get_terminals >/dev/null 2>&1; then
            printf '  OK       Terminator DBus is reachable.\n'
        else
            printf '  INFO     Terminator DBus is not reachable yet; starting Terminator normally should enable it.\n'
        fi
    fi
    return "$failed"
}

prompt() {
    local label=$1 default=${2-} value
    if [[ -n $default ]]; then read -r -p "$label [$default]: " value || exit 1
    else read -r -p "$label: " value || exit 1
    fi
    REPLY=${value:-$default}
}

prompt_required() {
    local label=$1 default=${2-}
    while :; do
        prompt "$label" "$default"
        [[ -n $REPLY ]] && return
        printf 'A value is required.\n'
    done
}

prompt_yes_no() {
    local label=$1 default=${2:-n} value suffix
    [[ $default == y ]] && suffix='Y/n' || suffix='y/N'
    while :; do
        read -r -p "$label [$suffix]: " value || exit 1
        value=${value:-$default}
        case ${value,,} in y|yes) REPLY=yes; return ;; n|no) REPLY=no; return ;; esac
        printf 'Enter y or n.\n'
    done
}

valid_port() { [[ $1 =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }

prompt_port() {
    local label=$1 default=${2-}
    while :; do
        prompt_required "$label" "$default"
        valid_port "$REPLY" && return
        printf 'Enter a port from 1 through 65535.\n'
    done
}

clean_field() {
    local value=$1 label=$2
    [[ $value != *[[:cntrl:]]* && $value != *'|'* ]] || die "$label cannot contain control characters or |"
}

append_tunnel() {
    local name=$1 type=$2 host=$3 user=$4 ssh_port=$5 bind=$6 listen=$7
    local dest=$8 dest_port=$9 identity=${10} jump=${11} reconnect=${12}
    local compress=${13} raw_flag=${14} raw_spec=${15} alive=${16} alive_count=${17}
    local field
    for field in "$name" "$type" "$host" "$user" "$ssh_port" "$bind" "$listen" "$dest" "$dest_port" "$identity" "$jump" "$reconnect" "$compress" "$raw_flag" "$raw_spec" "$alive" "$alive_count"; do
        clean_field "$field" 'tunnel field'
    done
    T_NAME+=("$name"); T_TYPE+=("$type"); T_HOST+=("$host"); T_USER+=("$user")
    T_SSH_PORT+=("$ssh_port"); T_BIND+=("$bind"); T_LISTEN+=("$listen")
    T_DEST+=("$dest"); T_DEST_PORT+=("$dest_port"); T_IDENTITY+=("$identity")
    T_JUMP+=("$jump"); T_RECONNECT+=("$reconnect"); T_COMPRESS+=("$compress")
    T_RAW_FLAG+=("$raw_flag"); T_RAW_SPEC+=("$raw_spec"); T_ALIVE+=("$alive")
    T_ALIVE_COUNT+=("$alive_count")
}

collect_connection() {
    printf '\nCONNECTION TO THE SSH SERVER\n'
    printf 'The SSH server is the machine that carries the tunnel. It is the same\n'
    printf 'machine you would normally connect to with: ssh user@server\n\n'
    prompt_required 'Short pane name (example: Office Database)'; C_NAME=$REPLY
    prompt_required 'SSH server address (example: 203.0.113.10 or bastion.example.com)'; C_HOST=$REPLY
    prompt_required 'Username on that SSH server' "${USER:-}"; C_USER=$REPLY
    prompt_port 'SSH service port (normally 22)' 22; C_SSH_PORT=$REPLY
    printf 'Key file is optional. Leave it blank to let SSH use ssh-agent, its default\nkey files, or ask for a password inside the tunnel pane.\n'
    prompt 'Private-key file (example: ~/.ssh/id_ed25519)' ''; C_IDENTITY=$REPLY
    C_JUMP=''; C_COMPRESS=no; C_RECONNECT=no; C_ALIVE=30; C_ALIVE_COUNT=3
    prompt_yes_no 'Show advanced connection questions?' n
    if [[ $REPLY == yes ]]; then
        printf 'A jump host is another SSH server that must be crossed first.\n'
        prompt 'Jump host; blank for none (example: admin@jump.example.com:22)' ''; C_JUMP=$REPLY
        prompt_yes_no 'Compress traffic? Usually leave this off' n; C_COMPRESS=$REPLY
        prompt_yes_no 'Reconnect automatically with autossh if disconnected?' n; C_RECONNECT=$REPLY
        prompt 'Seconds between connection checks' 30; C_ALIVE=$REPLY
        [[ $C_ALIVE =~ ^[0-9]+$ ]] || C_ALIVE=30
        prompt 'Failed checks allowed before disconnecting' 3; C_ALIVE_COUNT=$REPLY
        [[ $C_ALIVE_COUNT =~ ^[0-9]+$ ]] || C_ALIVE_COUNT=3
    fi
}

add_local() {
    printf '\nLOCAL FORWARD — reach something on the far side of the SSH server.\n'
    printf 'Example: open localhost:8080 here and reach an internal website at\nweb.internal:80. Your application connects to localhost:8080.\n'
    collect_connection
    prompt_port 'Port to open on this computer (example: 8080)' 8080; local listen=$REPLY
    prompt_required 'Destination address visible from the SSH server (example: 10.20.0.15)'; local dest=$REPLY
    prompt_port 'Destination service port (example: 80, 443, 3389, or 5432)'; local dport=$REPLY
    local bind=127.0.0.1
    prompt_yes_no 'Allow other computers to connect to your local tunnel port?' n
    [[ $REPLY == yes ]] && bind=0.0.0.0
    append_tunnel "$C_NAME" local "$C_HOST" "$C_USER" "$C_SSH_PORT" "$bind" "$listen" "$dest" "$dport" "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" '' '' "$C_ALIVE" "$C_ALIVE_COUNT"
}

add_remote() {
    printf '\nREMOTE FORWARD — expose a service from your side on the SSH server.\n'
    printf 'Example: make port 9000 on the SSH server lead back to a web application\nrunning on this computer at 127.0.0.1:3000.\n'
    collect_connection
    prompt_port 'Port to open on the SSH server (example: 9000)' 9000; local listen=$REPLY
    prompt 'Service address on your side' 127.0.0.1; local dest=$REPLY
    prompt_port 'Service port on your side (example: 3000)' 3000; local dport=$REPLY
    local bind=127.0.0.1
    prompt_yes_no 'Request a remotely public listening port? Server GatewayPorts must allow it' n
    [[ $REPLY == yes ]] && bind=0.0.0.0
    append_tunnel "$C_NAME" remote "$C_HOST" "$C_USER" "$C_SSH_PORT" "$bind" "$listen" "$dest" "$dport" "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" '' '' "$C_ALIVE" "$C_ALIVE_COUNT"
}

add_dynamic() {
    printf '\nLOCAL SOCKS PROXY — applications use a SOCKS proxy on this computer.\n'
    printf 'Set the application proxy to SOCKS5 127.0.0.1 and the port below.\n'
    collect_connection
    local bind=127.0.0.1
    prompt_port 'SOCKS port on this computer' 1080; local listen=$REPLY
    append_tunnel "$C_NAME" dynamic "$C_HOST" "$C_USER" "$C_SSH_PORT" "$bind" "$listen" '' '' "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" '' '' "$C_ALIVE" "$C_ALIVE_COUNT"
}

add_remote_socks() {
    printf '\nREMOTE SOCKS PROXY — the SOCKS proxy listens on the SSH server.\n'
    printf 'This requires a recent OpenSSH server. By default only programs on that\nserver can use the proxy.\n'
    collect_connection
    local bind=127.0.0.1
    prompt_port 'Remote SOCKS listening port' 1080; local listen=$REPLY
    append_tunnel "$C_NAME" remote-socks "$C_HOST" "$C_USER" "$C_SSH_PORT" "$bind" "$listen" '' '' "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" '' '' "$C_ALIVE" "$C_ALIVE_COUNT"
}

add_raw() {
    printf '\nADVANCED FORWARD: supply an exact OpenSSH forwarding specification.\n'
    printf 'Examples: -L /tmp/local.sock:db.internal:5432, -R 9000, -w 0:0\n'
    collect_connection
    while :; do
        prompt_required 'Forward flag (-L, -R, -D, or -w)'
        case $REPLY in -L|-R|-D|-w) local flag=$REPLY; break ;; *) printf 'Choose -L, -R, -D, or -w.\n' ;; esac
    done
    prompt_required 'Exact forwarding specification'; local spec=$REPLY
    append_tunnel "$C_NAME" raw "$C_HOST" "$C_USER" "$C_SSH_PORT" '' '' '' '' "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" "$flag" "$spec" "$C_ALIVE" "$C_ALIVE_COUNT"
}

describe_tunnel() {
    local i=$1
    case ${T_TYPE[i]} in
        local) printf '%s:%s -> %s:%s' "${T_BIND[i]}" "${T_LISTEN[i]}" "${T_DEST[i]}" "${T_DEST_PORT[i]}" ;;
        remote) printf 'remote %s:%s -> %s:%s' "${T_BIND[i]}" "${T_LISTEN[i]}" "${T_DEST[i]}" "${T_DEST_PORT[i]}" ;;
        dynamic) printf 'SOCKS %s:%s' "${T_BIND[i]}" "${T_LISTEN[i]}" ;;
        remote-socks) printf 'remote SOCKS %s:%s' "${T_BIND[i]}" "${T_LISTEN[i]}" ;;
        raw) printf '%s %s' "${T_RAW_FLAG[i]}" "${T_RAW_SPEC[i]}" ;;
    esac
}

list_tunnels() {
    local i
    if ((${#T_NAME[@]} == 0)); then printf '\nNo tunnels defined.\n'; return; fi
    printf '\n%-4s %-10s %-20s %-13s %-28s %s\n' '#' 'STATE' 'NAME' 'TYPE' 'SSH CONNECTION' 'FORWARD'
    printf '%-4s %-10s %-20s %-13s %-28s %s\n' '----' '----------' '--------------------' '-------------' '----------------------------' '------------------------------'
    for ((i=0; i<${#T_NAME[@]}; i++)); do
        local state=waiting; ((i < LAUNCHED_COUNT)) && state=launched
        printf '%-4s %-10s %-20.20s %-13s %-28.28s ' "$((i+1))" "$state" "${T_NAME[i]}" "${T_TYPE[i]}" "${T_USER[i]}@${T_HOST[i]}:${T_SSH_PORT[i]}"
        describe_tunnel "$i"; printf '\n'
    done
    printf '\n'
}

remove_tunnel() {
    list_tunnels
    ((${#T_NAME[@]})) || return
    prompt_required 'Number to remove'
    [[ $REPLY =~ ^[0-9]+$ ]] || { printf 'Not a valid number.\n'; return; }
    local i=$((10#$REPLY - 1)) a
    ((i >= 0 && i < ${#T_NAME[@]})) || { printf 'No tunnel has that number.\n'; return; }
    ((i >= LAUNCHED_COUNT)) || { printf 'That tunnel is already running. Stop its pane and restart this manager before removing its definition.\n'; return; }
    for a in T_NAME T_TYPE T_HOST T_USER T_SSH_PORT T_BIND T_LISTEN T_DEST T_DEST_PORT T_IDENTITY T_JUMP T_RECONNECT T_COMPRESS T_RAW_FLAG T_RAW_SPEC T_ALIVE T_ALIVE_COUNT; do
        local -n array_ref=$a
        unset 'array_ref[i]'
        array_ref=("${array_ref[@]}")
        unset -n array_ref
    done
    printf 'Removed tunnel %s.\n' "$REPLY"
}

save_tunnels() {
    local file=$1 i
    [[ -n $file ]] || die 'save filename is empty'
    { printf '# ssh-tunnel-master v1 — fields are pipe-delimited; no passwords are stored\n'
      printf '# name|type|ssh_host|ssh_user|ssh_port|bind|listen|dest|dest_port|identity|jump|reconnect|compress|raw_flag|raw_spec|alive_interval|alive_count\n'
      for ((i=0; i<${#T_NAME[@]}; i++)); do
          printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${T_NAME[i]}" "${T_TYPE[i]}" "${T_HOST[i]}" "${T_USER[i]}" "${T_SSH_PORT[i]}" \
            "${T_BIND[i]}" "${T_LISTEN[i]}" "${T_DEST[i]}" "${T_DEST_PORT[i]}" "${T_IDENTITY[i]}" \
            "${T_JUMP[i]}" "${T_RECONNECT[i]}" "${T_COMPRESS[i]}" "${T_RAW_FLAG[i]}" \
            "${T_RAW_SPEC[i]}" "${T_ALIVE[i]}" "${T_ALIVE_COUNT[i]}"
      done
    } > "$file"
    chmod 600 "$file" 2>/dev/null || true
    printf 'Saved %s tunnel(s) to %s\n' "${#T_NAME[@]}" "$file"
}

validate_loaded() {
    local type=$1 ssh_port=$2 listen=$3 dest_port=$4 reconnect=$5 compress=$6 raw_flag=$7 alive=$8 alive_count=$9
    case $type in local|remote|dynamic|remote-socks|raw) ;; *) return 1 ;; esac
    valid_port "$ssh_port" || return 1
    case $type in local|remote|dynamic|remote-socks) valid_port "$listen" || return 1 ;; esac
    case $type in local|remote) valid_port "$dest_port" || return 1 ;; esac
    [[ $reconnect == yes || $reconnect == no ]] || return 1
    [[ $compress == yes || $compress == no ]] || return 1
    [[ $alive =~ ^[0-9]+$ && $alive_count =~ ^[0-9]+$ ]] || return 1
    [[ $type != raw || $raw_flag == -L || $raw_flag == -R || $raw_flag == -D || $raw_flag == -w ]] || return 1
}

load_tunnels() {
    local file=$1 line=0 loaded=0
    local name type host user ssh_port bind listen dest dest_port identity jump reconnect compress raw_flag raw_spec alive alive_count extra
    [[ -r $file ]] || die "cannot read tunnel file: $file"
    while IFS='|' read -r name type host user ssh_port bind listen dest dest_port identity jump reconnect compress raw_flag raw_spec alive alive_count extra || [[ -n ${name-} ]]; do
        ((line+=1))
        [[ -z ${name-} || $name == \#* ]] && continue
        [[ -z ${extra-} ]] || die "$file:$line has too many fields"
        [[ -n $name && -n $host && -n $user ]] || die "$file:$line is missing a required field"
        validate_loaded "$type" "$ssh_port" "$listen" "$dest_port" "$reconnect" "$compress" "$raw_flag" "$alive" "$alive_count" || die "$file:$line has invalid values"
        append_tunnel "$name" "$type" "$host" "$user" "$ssh_port" "$bind" "$listen" "$dest" "$dest_port" "$identity" "$jump" "$reconnect" "$compress" "$raw_flag" "$raw_spec" "$alive" "$alive_count"
        ((loaded+=1))
    done < "$file"
    printf 'Loaded %s tunnel(s) from %s\n' "$loaded" "$file"
}

expand_home() {
    case $1 in '~') printf '%s' "$HOME" ;; '~/'*) printf '%s/%s' "$HOME" "${1:2}" ;; *) printf '%s' "$1" ;; esac
}

build_ssh_command() {
    local i=$1 spec identity destination
    SSH_COMMAND=()
    if [[ ${T_RECONNECT[i]} == yes ]]; then SSH_COMMAND=(env AUTOSSH_GATETIME=0 autossh -M 0)
    else SSH_COMMAND=(ssh)
    fi
    SSH_COMMAND+=( -N -T -o ExitOnForwardFailure=yes -o "ServerAliveInterval=${T_ALIVE[i]}" -o "ServerAliveCountMax=${T_ALIVE_COUNT[i]}" -p "${T_SSH_PORT[i]}" )
    [[ ${T_COMPRESS[i]} == yes ]] && SSH_COMMAND+=( -C )
    if [[ -n ${T_IDENTITY[i]} ]]; then identity=$(expand_home "${T_IDENTITY[i]}"); SSH_COMMAND+=( -i "$identity" ); fi
    [[ -n ${T_JUMP[i]} ]] && SSH_COMMAND+=( -J "${T_JUMP[i]}" )
    case ${T_TYPE[i]} in
        local) spec="${T_BIND[i]}:${T_LISTEN[i]}:${T_DEST[i]}:${T_DEST_PORT[i]}"; SSH_COMMAND+=( -L "$spec" ) ;;
        remote) spec="${T_BIND[i]}:${T_LISTEN[i]}:${T_DEST[i]}:${T_DEST_PORT[i]}"; SSH_COMMAND+=( -R "$spec" ) ;;
        dynamic) spec="${T_BIND[i]}:${T_LISTEN[i]}"; SSH_COMMAND+=( -D "$spec" ) ;;
        remote-socks) spec="${T_BIND[i]}:${T_LISTEN[i]}"; SSH_COMMAND+=( -R "$spec" ) ;;
        raw) SSH_COMMAND+=( "${T_RAW_FLAG[i]}" "${T_RAW_SPEC[i]}" ) ;;
    esac
    destination=${T_HOST[i]}
    [[ -n ${T_USER[i]} ]] && destination="${T_USER[i]}@$destination"
    SSH_COMMAND+=( "$destination" )
}

print_command() { local arg; printf '  '; for arg in "$@"; do printf '%q ' "$arg"; done; printf '\n'; }

self_path() {
    local source=${BASH_SOURCE[0]}
    if command -v realpath >/dev/null 2>&1; then realpath "$source"
    elif command -v readlink >/dev/null 2>&1 && readlink -f "$source" >/dev/null 2>&1; then readlink -f "$source"
    else (cd -P -- "$(dirname -- "$source")" && printf '%s/%s\n' "$PWD" "$(basename -- "$source")")
    fi
}

record_args() {
    local i=$1
    RECORD_ARGS=( "${T_NAME[i]}" "${T_TYPE[i]}" "${T_HOST[i]}" "${T_USER[i]}" "${T_SSH_PORT[i]}" "${T_BIND[i]}" "${T_LISTEN[i]}" "${T_DEST[i]}" "${T_DEST_PORT[i]}" "${T_IDENTITY[i]}" "${T_JUMP[i]}" "${T_RECONNECT[i]}" "${T_COMPRESS[i]}" "${T_RAW_FLAG[i]}" "${T_RAW_SPEC[i]}" "${T_ALIVE[i]}" "${T_ALIVE_COUNT[i]}" )
}

pane_mode() {
    (($# == 17)) || die 'internal pane record is incomplete'
    append_tunnel "$@"
    printf '\033]0;%s\007' "${T_NAME[0]}"
    printf '\n=== SSH TUNNEL: %s ===\n' "${T_NAME[0]}"
    printf 'Type:       %s\n' "${T_TYPE[0]}"
    printf 'SSH server: %s@%s:%s\n' "${T_USER[0]}" "${T_HOST[0]}" "${T_SSH_PORT[0]}"
    printf 'Forward:    '; describe_tunnel 0; printf '\nCommand:\n'
    build_ssh_command 0
    print_command "${SSH_COMMAND[@]}"
    printf '\nPress Ctrl-C to stop this tunnel.\n\n'
    if [[ ${T_RECONNECT[0]} == yes ]] && ! command -v autossh >/dev/null 2>&1; then
        printf 'ERROR: autossh is required for reconnect mode. Install it or disable reconnect.\n' >&2
        rc=127
    else
        set +e
        "${SSH_COMMAND[@]}"
        rc=$?
        set -e
    fi
    printf '\nTunnel stopped with status %s. This pane will remain open.\n' "$rc"
    printf 'Type exit or press Ctrl-D to close it.\n\n'
    exec "${SHELL:-/bin/bash}" -i
}

first_uuid() {
    local line
    while IFS= read -r line; do case $line in urn:uuid:*) printf '%s\n' "$line"; return 0 ;; esac; done
    return 1
}

ensure_terminator_workspace() {
    local output attempt all
    if [[ -n $MASTER_UUID ]]; then
        all=$(remotinator get_terminals 2>/dev/null || true)
        [[ $all == *"$MASTER_UUID"* ]] && return 0
        MASTER_UUID=''; PANE_QUEUE_UUIDS=(); PANE_QUEUE_DEPTHS=()
    fi

    if remotinator get_terminals >/dev/null 2>&1; then
        output=$(remotinator new_window 2>&1) || die "Terminator DBus refused a new window: $output"
        MASTER_UUID=$(printf '%s\n' "$output" | first_uuid) || die "Terminator created a window but returned no terminal UUID: $output"
    else
        terminator --title='SSH Tunnel Master' >/dev/null 2>&1 &
        for ((attempt=0; attempt<80; attempt++)); do
            output=$(remotinator get_terminals 2>/dev/null || true)
            if MASTER_UUID=$(printf '%s\n' "$output" | first_uuid); then break; fi
            sleep 0.125
        done
        [[ -n $MASTER_UUID ]] || die 'Terminator did not expose its DBus terminal list. Run ssh-tunnel-master.sh --doctor and ensure Terminator was not started with --no-dbus.'
    fi
    PANE_QUEUE_UUIDS=("$MASTER_UUID")
    PANE_QUEUE_DEPTHS=(0)
    printf 'Created a dedicated Terminator workspace. UUID: %s\n' "$MASTER_UUID"
}

launch_tunnels() {
    local count=${#T_NAME[@]} i script new_uuid split_cmd command_string split_output arg
    local anchor depth line remotinator_help
    ((count > 0)) || die 'add or load at least one tunnel before launching'
    if ((LAUNCHED_COUNT >= count)); then printf '\nEvery defined tunnel is already launched. Add another tunnel or close this tool.\n'; return; fi
    printf '\nNew tunnel launch plan (%s new pane(s), split mode: %s):\n' "$((count-LAUNCHED_COUNT))" "$SPLIT_MODE"
    for ((i=LAUNCHED_COUNT; i<count; i++)); do build_ssh_command "$i"; printf '[%s] %s\n' "$((i+1))" "${T_NAME[i]}"; print_command "${SSH_COMMAND[@]}"; done
    if ((DRY_RUN)); then printf '\nDry run complete; no window or connection was opened.\n'; return; fi
    for arg in ssh terminator remotinator; do command -v "$arg" >/dev/null 2>&1 || die "required command not found: $arg"; done
    remotinator_help=$(remotinator -h 2>&1 || true)
    [[ $remotinator_help == *--execute* ]] || die 'this Terminator/Remotinator version lacks command-enabled splits; install a current Terminator release'
    [[ $remotinator_help == *--title* ]] || die 'this Terminator/Remotinator version lacks titled splits; install a current Terminator release'
    for ((i=LAUNCHED_COUNT; i<count; i++)); do
        if [[ ${T_RECONNECT[i]} == yes ]] && ! command -v autossh >/dev/null 2>&1; then die "tunnel '${T_NAME[i]}' requests reconnect but autossh is not installed"; fi
    done
    script=$(self_path)
    ensure_terminator_workspace
    for ((i=LAUNCHED_COUNT; i<count; i++)); do
        anchor=${PANE_QUEUE_UUIDS[0]}
        depth=${PANE_QUEUE_DEPTHS[0]}
        PANE_QUEUE_UUIDS=("${PANE_QUEUE_UUIDS[@]:1}")
        PANE_QUEUE_DEPTHS=("${PANE_QUEUE_DEPTHS[@]:1}")
        case $SPLIT_MODE in horizontal) split_cmd=hsplit ;; vertical) split_cmd=vsplit ;; auto) ((depth % 2 == 0)) && split_cmd=vsplit || split_cmd=hsplit ;; esac
        record_args "$i"
        command_string=''
        printf -v command_string '%q ' bash "$script" __pane "${RECORD_ARGS[@]}"
        split_output=$(remotinator "$split_cmd" --uuid "$anchor" --title "${T_NAME[i]}" --execute "$command_string" 2>&1) || die "could not create pane for ${T_NAME[i]}: $split_output"
        new_uuid=''
        while IFS= read -r line; do
            case $line in urn:uuid:*) new_uuid=$line; break ;; esac
        done <<< "$split_output"
        [[ -n $new_uuid ]] || die "Terminator rejected pane for ${T_NAME[i]}: $split_output"
        PANE_QUEUE_UUIDS+=("$anchor" "$new_uuid")
        PANE_QUEUE_DEPTHS+=("$((depth+1))" "$((depth+1))")
        printf 'Opened pane %s/%s: %s\n' "$((i+1))" "$count" "${T_NAME[i]}"
        LAUNCHED_COUNT=$((i+1))
    done
    printf '\nAll new tunnel panes were created. The menu remains available for more tunnels.\n'
}

interactive_menu() {
    local choice file
    while :; do
        printf '\nSSH TUNNEL MASTER — %s tunnel(s) defined\n' "${#T_NAME[@]}"
        cat <<'MENU'
  1) Reach a remote/internal service from this computer (local -L)
  2) Make one of your services reachable on the SSH server (remote -R)
  3) Create a SOCKS proxy on this computer (dynamic -D)
  4) Create a SOCKS proxy on the SSH server
  5) Advanced/raw OpenSSH forwarding
  6) List tunnels
  7) Remove a tunnel
  8) Save tunnel set
  9) Load and append tunnel set
  S) Change pane split mode
  L) Launch every tunnel that is not running yet
  D) Preview every tunnel that is not running yet
  Q) Quit
MENU
        read -r -p 'Choose: ' choice || exit 0
        case ${choice,,} in
            1) add_local ;; 2) add_remote ;; 3) add_dynamic ;; 4) add_remote_socks ;;
            5) add_raw ;; 6) list_tunnels ;; 7) remove_tunnel ;;
            8) prompt_required 'Save filename' 'ssh-tunnels.txt'; save_tunnels "$REPLY" ;;
            9) prompt_required 'File to load'; load_tunnels "$REPLY" ;;
            s) prompt 'Split mode: auto, horizontal, or vertical' "$SPLIT_MODE"; case $REPLY in auto|horizontal|vertical) SPLIT_MODE=$REPLY ;; *) printf 'Unknown split mode.\n' ;; esac ;;
            l) DRY_RUN=0; launch_tunnels ;;
            d) DRY_RUN=1; launch_tunnels; DRY_RUN=0 ;;
            q) return ;;
            *) printf 'Choose one of the displayed options.\n' ;;
        esac
    done
}

if [[ ${1-} == __pane ]]; then shift; pane_mode "$@"; exit; fi

while (($#)); do
    case $1 in
        -h|--help) usage; exit 0 ;;
        --version) printf '%s %s\n' "$PROGRAM" "$VERSION"; exit 0 ;;
        --doctor) doctor; exit $? ;;
        --load) (($# >= 2)) || die '--load requires a file'; LOAD_FILE=$2; shift ;;
        --load=*) LOAD_FILE=${1#*=} ;;
        --launch) AUTO_LAUNCH=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --split) (($# >= 2)) || die '--split requires a mode'; SPLIT_MODE=$2; shift ;;
        --split=*) SPLIT_MODE=${1#*=} ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

case $SPLIT_MODE in auto|horizontal|vertical) ;; *) die '--split must be auto, horizontal, or vertical' ;; esac
[[ -z $LOAD_FILE ]] || load_tunnels "$LOAD_FILE"
if ((AUTO_LAUNCH)); then launch_tunnels; fi
interactive_menu
__MASTER_SSH_PAYLOAD__
}

write_ipip_payload() {
    cat > "$1" <<'__MASTER_IPIP_PAYLOAD__'
#!/usr/bin/env bash
# ipip-tunnel-master.sh — interactive Linux IP-in-IP topology manager.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION=2.0.0
ACTION=menu
LOAD_FILE=""
ASSUME_YES=0

declare -a N_IF=() N_A_KIND=() N_A_HOST=() N_A_USER=() N_A_PORT=() N_A_KEY=() N_A_JUMP=()
declare -a N_A_OUTER=() N_A_INNER=() N_A_DEV=() N_A_ROUTES=()
declare -a N_B_KIND=() N_B_HOST=() N_B_USER=() N_B_PORT=() N_B_KEY=() N_B_JUMP=()
declare -a N_B_OUTER=() N_B_INNER=() N_B_DEV=() N_B_ROUTES=()
declare -a N_MTU=() N_TTL=() N_PMTU=() N_FORWARD=()

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

usage() {
cat <<'HELP'
ipip-tunnel-master.sh — plan and manage multi-hop Linux IPIP tunnels

USAGE
  ipip-tunnel-master.sh
  ipip-tunnel-master.sh --load TOPOLOGY --plan
  ipip-tunnel-master.sh --load TOPOLOGY --apply [--yes]
  ipip-tunnel-master.sh --load TOPOLOGY --status
  ipip-tunnel-master.sh --load TOPOLOGY --destroy [--yes]

MODEL
  Each tunnel has endpoint A and endpoint B. An endpoint may be this computer
  or a Linux box reached over SSH. You provide the outer IPv4 address, inner
  tunnel address, routes, SSH user/port/key/jump host, MTU, TTL, and whether
  routing should be enabled.

  Tunnels are applied in the order listed and destroyed in reverse order.
  Therefore a later tunnel may use an address or route created by an earlier
  tunnel as its underlay. This is how tunnel-inside-tunnel topologies are built.
  There is no fixed hop limit in the script.

ACTIONS
  --plan       Print every command without changing a host.
  --apply      Configure both endpoints of every tunnel in listed order.
  --status     Show each tunnel, address, and tunnel-specific routes.
  --destroy    Remove tunnels and their routes in reverse order.
  --export DIR Write standalone apply/destroy scripts for every endpoint.
  --yes        Skip the typed APPLY/DESTROY confirmation.
  --load FILE  Load a saved topology before performing an action.
  -h, --help   Show this help.
  --version    Show version.

REQUIREMENTS
  * Linux endpoints with Bash, iproute2, sudo/root, and IPIP kernel support.
  * SSH access to remote endpoints. No password is stored by this tool.
  * The underlay must route both outer endpoint addresses in both directions.
  * Firewalls/NAT between endpoints must permit IP protocol 4. IPIP has no port.

IMPORTANT BEHAVIOR
  * Runtime configuration is temporary and normally disappears after reboot.
  * IPIP encapsulates IPv4 inside IPv4. It does not encrypt or authenticate.
  * A standard IPIP layer adds a 20-byte outer IPv4 header. Lower the MTU for
    every nested layer; the interactive wizard calculates a suggested value.
  * Keep console/provider access when applying routes remotely. A wrong route,
    outer address, or MTU can disconnect the SSH management path.

NESTED EXAMPLE
  Tunnel 1: box A outer 192.0.2.10 <-> box B outer 198.51.100.20
            inner 10.200.1.1/30 <-> 10.200.1.2/30, MTU 1480
  Tunnel 2: endpoints whose outer addresses are routed through Tunnel 1
            inner 10.200.2.1/30 <-> 10.200.2.2/30, MTU 1460

  The exact outer addresses for Tunnel 2 depend on the topology. The script
  does not guess them: it shows all routes and endpoint commands before apply.
HELP
}

prompt() {
    local label=$1 default=${2-} value
    if [[ -n $default ]]; then read -r -p "$label [$default]: " value || exit 1
    else read -r -p "$label: " value || exit 1
    fi
    REPLY=${value:-$default}
}

prompt_required() { local label=$1 default=${2-}; while :; do prompt "$label" "$default"; [[ -n $REPLY ]] && return; printf 'A value is required.\n'; done; }

prompt_yes_no() {
    local label=$1 default=${2:-n} value suffix
    [[ $default == y ]] && suffix=Y/n || suffix=y/N
    while :; do
        read -r -p "$label [$suffix]: " value || exit 1
        value=${value:-$default}
        case ${value,,} in y|yes) REPLY=yes; return ;; n|no) REPLY=no; return ;; esac
        printf 'Enter y or n.\n'
    done
}

valid_port() { [[ $1 =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }

valid_ipv4() {
    local ip=$1 part
    local -a parts=()
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.; read -r -a parts <<< "$ip"
    for part in "${parts[@]}"; do ((10#$part <= 255)) || return 1; done
}

valid_cidr() {
    local value=$1 ip prefix
    [[ $value == */* ]] || return 1
    ip=${value%/*}; prefix=${value##*/}
    valid_ipv4 "$ip" && [[ $prefix =~ ^[0-9]+$ ]] && ((10#$prefix <= 32))
}

ip_to_int() {
    local IFS=. octets
    read -r -a octets <<< "$1"
    printf '%u' "$(( (10#${octets[0]} << 24) | (10#${octets[1]} << 16) | (10#${octets[2]} << 8) | 10#${octets[3]} ))"
}

same_inner_network() {
    local a b ap bp ai bi mask
    a=$1; b=$2; ap=${a##*/}; bp=${b##*/}
    [[ $ap == "$bp" ]] || return 1
    ai=$(ip_to_int "${a%/*}"); bi=$(ip_to_int "${b%/*}")
    if ((10#$ap == 32)); then ((ai != bi)); return; fi
    if ((10#$ap == 0)); then mask=0; else mask=$(( (0xFFFFFFFF << (32 - 10#$ap)) & 0xFFFFFFFF )); fi
    (( (ai & mask) == (bi & mask) && ai != bi ))
}

int_to_ip() {
    local value=$1
    printf '%d.%d.%d.%d' "$(( (value >> 24) & 255 ))" "$(( (value >> 16) & 255 ))" "$(( (value >> 8) & 255 ))" "$(( value & 255 ))"
}

inner_pair_from_subnet() {
    local cidr=$1 ip prefix value mask network a_value b_value
    ip=${cidr%/*}; prefix=${cidr##*/}
    ((10#$prefix <= 31)) || return 1
    value=$(ip_to_int "$ip")
    if ((10#$prefix == 0)); then mask=0; else mask=$(( (0xFFFFFFFF << (32 - 10#$prefix)) & 0xFFFFFFFF )); fi
    network=$((value & mask))
    if ((10#$prefix == 31)); then a_value=$network; b_value=$((network+1))
    else a_value=$((network+1)); b_value=$((network+2)); fi
    PAIR_A="$(int_to_ip "$a_value")/$prefix"
    PAIR_B="$(int_to_ip "$b_value")/$prefix"
}

valid_routes() {
    local input=$1 route
    local -a route_items=()
    [[ -z $input ]] && return 0
    local IFS=,; read -r -a route_items <<< "$input"
    for route in "${route_items[@]}"; do
        [[ $route == default ]] || valid_cidr "$route" || return 1
    done
}

clean_field() { [[ $1 != *[[:cntrl:]]* && $1 != *'|'* ]] || die "$2 cannot contain control characters or |"; }

same_executor() {
    local k1=$1 h1=$2 p1=$3 k2=$4 h2=$5 p2=$6
    [[ $k1 == local && $k2 == local ]] || [[ $k1 == ssh && $k2 == ssh && $h1 == "$h2" && $p1 == "$p2" ]]
}

prompt_ipv4() { local label=$1 default=${2-}; while :; do prompt_required "$label" "$default"; valid_ipv4 "$REPLY" && return; printf 'Enter a valid IPv4 address.\n'; done; }
prompt_cidr() { local label=$1 default=${2-}; while :; do prompt_required "$label" "$default"; valid_cidr "$REPLY" && return; printf 'Enter IPv4/prefix, for example 10.200.1.1/30.\n'; done; }

collect_executor() {
    local label=$1 default=${2:-ssh}
    while :; do
        printf '%s may be this computer or another Linux box managed through SSH.\n' "$label"
        prompt "$label command location (local/ssh)" "$default"
        case ${REPLY,,} in local|ssh) E_KIND=${REPLY,,}; break ;; *) printf 'Enter local or ssh.\n' ;; esac
    done
    E_HOST=''; E_USER=''; E_PORT=22; E_KEY=''; E_JUMP=''
    if [[ $E_KIND == ssh ]]; then
        prompt_required "$label management hostname/IP"; E_HOST=$REPLY
        prompt_required "$label SSH username" "${USER:-}"; E_USER=$REPLY
        while :; do prompt_required "$label SSH port" 22; valid_port "$REPLY" && { E_PORT=$REPLY; break; }; printf 'Enter a port from 1 through 65535.\n'; done
        prompt "$label identity file; blank uses normal SSH authentication" ''; E_KEY=$REPLY
        prompt "$label ProxyJump; blank for none ([user@]host[:port])" ''; E_JUMP=$REPLY
    fi
}

collect_endpoint() {
    local label=$1
    collect_executor "$label"
    EP_KIND=$E_KIND; EP_HOST=$E_HOST; EP_USER=$E_USER; EP_PORT=$E_PORT; EP_KEY=$E_KEY; EP_JUMP=$E_JUMP
    prompt_ipv4 "$label outer IPv4 address (must exist on that box)"; EP_OUTER=$REPLY
    prompt_cidr "$label inner tunnel address/prefix"; EP_INNER=$REPLY
    prompt "$label underlay device; blank lets Linux route normally" ''; EP_DEV=$REPLY
    prompt "$label routes through the peer, comma-separated; blank for none" ''; EP_ROUTES=$REPLY
}

append_tunnel() {
    (($# == 26)) || die 'internal tunnel record has the wrong field count'
    local value i
    for value in "$@"; do clean_field "$value" 'tunnel field'; done
    same_executor "$2" "$3" "$5" "${12}" "${13}" "${15}" && die "tunnel $1 assigns both endpoints to the same network namespace"
    for ((i=0; i<${#N_IF[@]}; i++)); do
        if [[ ${N_IF[i]} == "$1" ]]; then
            same_executor "$2" "$3" "$5" "${N_A_KIND[i]}" "${N_A_HOST[i]}" "${N_A_PORT[i]}" && die "interface $1 is already defined on endpoint A of tunnel $((i+1))"
            same_executor "$2" "$3" "$5" "${N_B_KIND[i]}" "${N_B_HOST[i]}" "${N_B_PORT[i]}" && die "interface $1 is already defined on endpoint B of tunnel $((i+1))"
            same_executor "${12}" "${13}" "${15}" "${N_A_KIND[i]}" "${N_A_HOST[i]}" "${N_A_PORT[i]}" && die "interface $1 is already defined on endpoint A of tunnel $((i+1))"
            same_executor "${12}" "${13}" "${15}" "${N_B_KIND[i]}" "${N_B_HOST[i]}" "${N_B_PORT[i]}" && die "interface $1 is already defined on endpoint B of tunnel $((i+1))"
        fi
    done
    N_IF+=("$1"); N_A_KIND+=("$2"); N_A_HOST+=("$3"); N_A_USER+=("$4"); N_A_PORT+=("$5"); N_A_KEY+=("$6"); N_A_JUMP+=("$7")
    N_A_OUTER+=("$8"); N_A_INNER+=("$9"); N_A_DEV+=("${10}"); N_A_ROUTES+=("${11}")
    N_B_KIND+=("${12}"); N_B_HOST+=("${13}"); N_B_USER+=("${14}"); N_B_PORT+=("${15}"); N_B_KEY+=("${16}"); N_B_JUMP+=("${17}")
    N_B_OUTER+=("${18}"); N_B_INNER+=("${19}"); N_B_DEV+=("${20}"); N_B_ROUTES+=("${21}")
    N_MTU+=("${22}"); N_TTL+=("${23}"); N_PMTU+=("${24}"); N_FORWARD+=("${25}")
    # Field 26 is reserved for forwards-compatible topology notes.
}

add_tunnel() {
    local ifname depth suggested mtu ttl pmtu forward subnet advanced
    printf '\nCREATE ONE IPIP LINK\n'
    printf 'You will enter each outer address once. The tool automatically creates the\nreverse configuration on endpoint B by swapping the outer addresses. You enter\none inner subnet and the tool assigns both tunnel addresses.\n\n'
    printf 'Add a normal/base tunnel first. Add tunnels that depend on it afterward.\n'
    while :; do
        prompt_required 'Tunnel interface name (15 characters maximum)'
        ifname=$REPLY
        [[ ${#ifname} -le 15 && $ifname =~ ^[A-Za-z0-9_.-]+$ ]] && break
        printf 'Use 1-15 letters, digits, dots, underscores, or dashes.\n'
    done
    printf '\n--- Endpoint A: usually this computer ---\n'; collect_executor A local
    local a_kind=$E_KIND a_host=$E_HOST a_user=$E_USER a_port=$E_PORT a_key=$E_KEY a_jump=$E_JUMP
    printf '\n--- Endpoint B: usually the remote box ---\n'; collect_executor B ssh
    local b_kind=$E_KIND b_host=$E_HOST b_user=$E_USER b_port=$E_PORT b_key=$E_KEY b_jump=$E_JUMP
    printf '\nOUTER ADDRESSES\nThese are real IPv4 addresses already configured and mutually reachable before\nthe IPIP tunnel starts. They are entered once and swapped automatically.\n'
    prompt_ipv4 'Outer IPv4 on endpoint A'; local a_outer=$REPLY
    prompt_ipv4 'Outer IPv4 on endpoint B'; local b_outer=$REPLY
    printf '\nINNER TUNNEL SUBNET\nUse a private, unused subnet. /30 is easiest; /31 also works. Example: 10.200.1.0/30\n'
    while :; do
        prompt_cidr 'Inner subnet' 10.200.1.0/30; subnet=$REPLY
        if inner_pair_from_subnet "$subnet"; then break; fi
        printf 'Use a prefix from /0 through /31; /32 cannot hold two endpoints.\n'
    done
    local a_inner=$PAIR_A b_inner=$PAIR_B
    printf 'Assigned automatically: endpoint A = %s, endpoint B = %s\n' "$a_inner" "$b_inner"
    local a_dev='' b_dev='' a_routes='' b_routes=''
    printf '\nROUTES (OPTIONAL)\nA route is a network located behind the opposite endpoint. Leave these blank if\nyou only need traffic between the two inner tunnel addresses.\n'
    prompt 'Network(s) behind endpoint B that A should reach, comma-separated (example: 10.50.0.0/16)' ''; a_routes=$REPLY
    prompt 'Network(s) behind endpoint A that B should reach, comma-separated (example: 10.60.0.0/16)' ''; b_routes=$REPLY
    valid_routes "$a_routes" && valid_routes "$b_routes" || die 'routes must be IPv4/prefix values or default, separated by commas'
    while :; do prompt 'Encapsulation depth (1 for a normal IPIP tunnel)' 1; [[ $REPLY =~ ^[0-9]+$ ]] && ((10#$REPLY >= 1)) && { depth=$((10#$REPLY)); break; }; printf 'Enter 1 or greater.\n'; done
    suggested=$((1500 - 20 * depth)); ((suggested < 576)) && suggested=576
    while :; do prompt 'Tunnel interface MTU' "$suggested"; [[ $REPLY =~ ^[0-9]+$ ]] && ((10#$REPLY >= 68 && 10#$REPLY <= 65535)) && { mtu=$REPLY; break; }; printf 'Enter a valid IPv4 MTU.\n'; done
    while :; do prompt 'Outer TTL (inherit or 1-255)' inherit; ttl=$REPLY; [[ $ttl == inherit ]] && break; [[ $ttl =~ ^[0-9]+$ ]] && ((10#$ttl >= 1 && 10#$ttl <= 255)) && break; printf 'Enter inherit or 1-255.\n'; done
    prompt_yes_no 'Use path-MTU discovery?' y; pmtu=$REPLY
    if [[ $pmtu == no && $ttl != inherit ]]; then
        printf 'Using TTL inherit because a fixed TTL is incompatible with nopmtudisc.\n'
        ttl=inherit
    fi
    prompt_yes_no 'Enable IPv4 forwarding on both endpoints for routed networks?' y; forward=$REPLY
    prompt_yes_no 'Show advanced underlay-device settings?' n; advanced=$REPLY
    if [[ $advanced == yes ]]; then
        prompt 'Endpoint A physical/underlay interface; blank lets Linux choose' ''; a_dev=$REPLY
        prompt 'Endpoint B physical/underlay interface; blank lets Linux choose' ''; b_dev=$REPLY
    fi
    append_tunnel "$ifname" "$a_kind" "$a_host" "$a_user" "$a_port" "$a_key" "$a_jump" "$a_outer" "$a_inner" "$a_dev" "$a_routes" \
      "$b_kind" "$b_host" "$b_user" "$b_port" "$b_key" "$b_jump" "$b_outer" "$b_inner" "$b_dev" "$b_routes" "$mtu" "$ttl" "$pmtu" "$forward" ''
}

target_label() { local i=$1 side=$2; local kind host user; if [[ $side == A ]]; then kind=${N_A_KIND[i]}; host=${N_A_HOST[i]}; user=${N_A_USER[i]}; else kind=${N_B_KIND[i]}; host=${N_B_HOST[i]}; user=${N_B_USER[i]}; fi; [[ $kind == local ]] && printf 'local machine' || printf '%s@%s' "$user" "$host"; }

list_tunnels() {
    local i
    ((${#N_IF[@]})) || { printf '\nNo IPIP tunnels defined.\n'; return; }
    printf '\n%-4s %-15s %-24s %-24s %-6s %-8s\n' '#' 'INTERFACE' 'ENDPOINT A' 'ENDPOINT B' 'MTU' 'FORWARD'
    printf '%-4s %-15s %-24s %-24s %-6s %-8s\n' '---' '---------------' '------------------------' '------------------------' '------' '--------'
    for ((i=0; i<${#N_IF[@]}; i++)); do
        printf '%-4s %-15s %-24.24s %-24.24s %-6s %-8s\n' "$((i+1))" "${N_IF[i]}" "$(target_label "$i" A):${N_A_INNER[i]}" "$(target_label "$i" B):${N_B_INNER[i]}" "${N_MTU[i]}" "${N_FORWARD[i]}"
        printf '     outer %s <-> %s; A routes: %s; B routes: %s\n' "${N_A_OUTER[i]}" "${N_B_OUTER[i]}" "${N_A_ROUTES[i]:-(none)}" "${N_B_ROUTES[i]:-(none)}"
    done
    printf '\nApplied order is top-to-bottom; destroy order is bottom-to-top.\n'
}

remove_tunnel() {
    list_tunnels; ((${#N_IF[@]})) || return
    prompt_required 'Tunnel number to remove'
    [[ $REPLY =~ ^[0-9]+$ ]] || { printf 'Not a number.\n'; return; }
    local i=$((10#$REPLY-1)) name
    ((i >= 0 && i < ${#N_IF[@]})) || { printf 'No tunnel has that number.\n'; return; }
    for name in N_IF N_A_KIND N_A_HOST N_A_USER N_A_PORT N_A_KEY N_A_JUMP N_A_OUTER N_A_INNER N_A_DEV N_A_ROUTES N_B_KIND N_B_HOST N_B_USER N_B_PORT N_B_KEY N_B_JUMP N_B_OUTER N_B_INNER N_B_DEV N_B_ROUTES N_MTU N_TTL N_PMTU N_FORWARD; do
        local -n ref=$name; unset 'ref[i]'; ref=("${ref[@]}"); unset -n ref
    done
}

save_topology() {
    local file=$1 i
    { printf '# ipip-tunnel-master v1; pipe-delimited; no passwords are stored\n'
      printf '# if|A_kind|A_host|A_user|A_port|A_key|A_jump|A_outer|A_inner|A_dev|A_routes|B_kind|B_host|B_user|B_port|B_key|B_jump|B_outer|B_inner|B_dev|B_routes|mtu|ttl|pmtu|forward|notes\n'
      for ((i=0; i<${#N_IF[@]}; i++)); do
          printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|\n' \
            "${N_IF[i]}" "${N_A_KIND[i]}" "${N_A_HOST[i]}" "${N_A_USER[i]}" "${N_A_PORT[i]}" "${N_A_KEY[i]}" "${N_A_JUMP[i]}" "${N_A_OUTER[i]}" "${N_A_INNER[i]}" "${N_A_DEV[i]}" "${N_A_ROUTES[i]}" \
            "${N_B_KIND[i]}" "${N_B_HOST[i]}" "${N_B_USER[i]}" "${N_B_PORT[i]}" "${N_B_KEY[i]}" "${N_B_JUMP[i]}" "${N_B_OUTER[i]}" "${N_B_INNER[i]}" "${N_B_DEV[i]}" "${N_B_ROUTES[i]}" "${N_MTU[i]}" "${N_TTL[i]}" "${N_PMTU[i]}" "${N_FORWARD[i]}"
      done
    } > "$file"
    chmod 600 "$file" 2>/dev/null || true
    printf 'Saved %s tunnel(s) to %s\n' "${#N_IF[@]}" "$file"
}

validate_record() {
    local ifname=$1 ak=$2 ah=$3 au=$4 ap=$5 ao=$6 ai=$7 bk=$8 bh=$9 bu=${10} bp=${11} bo=${12} bi=${13} mtu=${14} ttl=${15} pmtu=${16} forward=${17}
    [[ ${#ifname} -le 15 && $ifname =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
    [[ $ak == local || $ak == ssh ]] && [[ $bk == local || $bk == ssh ]] || return 1
    if [[ $ak == ssh ]]; then [[ -n $ah && -n $au ]] && valid_port "$ap" || return 1; fi
    if [[ $bk == ssh ]]; then [[ -n $bh && -n $bu ]] && valid_port "$bp" || return 1; fi
    valid_ipv4 "$ao" && valid_cidr "$ai" && valid_ipv4 "$bo" && valid_cidr "$bi" && same_inner_network "$ai" "$bi" || return 1
    [[ $mtu =~ ^[0-9]+$ ]] && ((10#$mtu >= 68 && 10#$mtu <= 65535)) || return 1
    if [[ $ttl != inherit ]]; then [[ $ttl =~ ^[0-9]+$ ]] && ((10#$ttl >= 1 && 10#$ttl <= 255)) || return 1; fi
    [[ $pmtu != no || $ttl == inherit ]] || return 1
    [[ $pmtu == yes || $pmtu == no ]] && [[ $forward == yes || $forward == no ]]
}

load_topology() {
    local file=$1 line=0 loaded=0
    local f ak ah au ap akey ajump ao ai adev ar bk bh bu bp bkey bjump bo bi bdev br mtu ttl pmtu forward notes extra
    [[ -r $file ]] || die "cannot read topology: $file"
    while IFS='|' read -r f ak ah au ap akey ajump ao ai adev ar bk bh bu bp bkey bjump bo bi bdev br mtu ttl pmtu forward notes extra || [[ -n ${f-} ]]; do
        ((line+=1)); [[ -z ${f-} || $f == \#* ]] && continue
        [[ -z ${extra-} ]] || die "$file:$line has too many fields"
        validate_record "$f" "$ak" "$ah" "$au" "$ap" "$ao" "$ai" "$bk" "$bh" "$bu" "$bp" "$bo" "$bi" "$mtu" "$ttl" "$pmtu" "$forward" || die "$file:$line contains invalid values"
        valid_routes "$ar" && valid_routes "$br" || die "$file:$line has an invalid route list"
        append_tunnel "$f" "$ak" "$ah" "$au" "$ap" "$akey" "$ajump" "$ao" "$ai" "$adev" "$ar" "$bk" "$bh" "$bu" "$bp" "$bkey" "$bjump" "$bo" "$bi" "$bdev" "$br" "$mtu" "$ttl" "$pmtu" "$forward" "$notes"
        ((loaded+=1))
    done < "$file"
    printf 'Loaded %s tunnel(s) from %s\n' "$loaded" "$file"
}

append_cmd() { local -n output_ref=$1; local line; printf -v line '%q ' "${@:2}"; output_ref+="$line"$'\n'; }

build_script() {
    local i side operation ifname outer peer inner peer_inner dev routes mtu ttl pmtu forward
    i=$1; side=$2; operation=$3; ifname=${N_IF[i]}; mtu=${N_MTU[i]}; ttl=${N_TTL[i]}
    if [[ $side == A ]]; then outer=${N_A_OUTER[i]}; peer=${N_B_OUTER[i]}; inner=${N_A_INNER[i]}; peer_inner=${N_B_INNER[i]%/*}; dev=${N_A_DEV[i]}; routes=${N_A_ROUTES[i]}
    else outer=${N_B_OUTER[i]}; peer=${N_A_OUTER[i]}; inner=${N_B_INNER[i]}; peer_inner=${N_A_INNER[i]%/*}; dev=${N_B_DEV[i]}; routes=${N_B_ROUTES[i]}; fi
    pmtu=pmtudisc; [[ ${N_PMTU[i]} == no ]] && pmtu=nopmtudisc
    forward=${N_FORWARD[i]}; ENDPOINT_SCRIPT='set -Eeuo pipefail'$'\n'
    local -a route_list=() tunnel_args=(mode ipip local "$outer" remote "$peer" ttl "$ttl" "$pmtu")
    [[ -n $dev ]] && tunnel_args+=(dev "$dev")
    case $operation in
        apply)
            ENDPOINT_SCRIPT+='modprobe ipip 2>/dev/null || true'$'\n'
            local add_line change_line
            printf -v add_line '%q ' ip tunnel add "$ifname" "${tunnel_args[@]}"
            printf -v change_line '%q ' ip tunnel change "$ifname" "${tunnel_args[@]}"
            ENDPOINT_SCRIPT+="if ip tunnel show $(printf '%q' "$ifname") >/dev/null 2>&1; then $change_line; else $add_line; fi"$'\n'
            if [[ ${inner##*/} == 32 ]]; then append_cmd ENDPOINT_SCRIPT ip addr replace "$inner" peer "$peer_inner/32" dev "$ifname"
            else append_cmd ENDPOINT_SCRIPT ip addr replace "$inner" dev "$ifname"; fi
            append_cmd ENDPOINT_SCRIPT ip link set dev "$ifname" mtu "$mtu" up
            if [[ -n $routes ]]; then local IFS=,; read -r -a route_list <<< "$routes"; for route in "${route_list[@]}"; do [[ -n $route ]] && append_cmd ENDPOINT_SCRIPT ip route replace "$route" via "$peer_inner" dev "$ifname"; done; fi
            [[ $forward == yes ]] && append_cmd ENDPOINT_SCRIPT sysctl -w net.ipv4.ip_forward=1
            ;;
        destroy)
            if [[ -n $routes ]]; then local IFS=,; read -r -a route_list <<< "$routes"; for route in "${route_list[@]}"; do [[ -n $route ]] && { local q; printf -v q '%q ' ip route del "$route" via "$peer_inner" dev "$ifname"; ENDPOINT_SCRIPT+="$q 2>/dev/null || true"$'\n'; }; done; fi
            local q; printf -v q '%q ' ip tunnel del "$ifname"; ENDPOINT_SCRIPT+="$q 2>/dev/null || true"$'\n'
            ;;
        status)
            append_cmd ENDPOINT_SCRIPT ip -d tunnel show "$ifname"
            append_cmd ENDPOINT_SCRIPT ip -br addr show dev "$ifname"
            append_cmd ENDPOINT_SCRIPT ip route show dev "$ifname"
            ;;
    esac
}

endpoint_fields() {
    local i=$1 side=$2
    if [[ $side == A ]]; then X_KIND=${N_A_KIND[i]}; X_HOST=${N_A_HOST[i]}; X_USER=${N_A_USER[i]}; X_PORT=${N_A_PORT[i]}; X_KEY=${N_A_KEY[i]}; X_JUMP=${N_A_JUMP[i]}
    else X_KIND=${N_B_KIND[i]}; X_HOST=${N_B_HOST[i]}; X_USER=${N_B_USER[i]}; X_PORT=${N_B_PORT[i]}; X_KEY=${N_B_KEY[i]}; X_JUMP=${N_B_JUMP[i]}; fi
}

print_endpoint() { local i=$1 side=$2 op=$3; build_script "$i" "$side" "$op"; printf '\n### %s endpoint %s (%s)\n%s' "${N_IF[i]}" "$side" "$(target_label "$i" "$side")" "$ENDPOINT_SCRIPT"; }

run_endpoint() {
    local i=$1 side=$2 op=$3 remote_command
    build_script "$i" "$side" "$op"; endpoint_fields "$i" "$side"
    printf '\n[%s endpoint %s on %s]\n' "${N_IF[i]}" "$side" "$(target_label "$i" "$side")"
    if [[ $X_KIND == local ]]; then
        if ((EUID == 0)); then bash -c "$ENDPOINT_SCRIPT"; else command -v sudo >/dev/null 2>&1 || die 'sudo is required for local configuration'; sudo bash -c "$ENDPOINT_SCRIPT"; fi
    else
        local -a ssh_args=(ssh -tt -o ConnectTimeout=15 -p "$X_PORT")
        if [[ -n $X_KEY ]]; then
            case $X_KEY in '~') X_KEY=$HOME ;; '~/'*) X_KEY="$HOME/${X_KEY:2}" ;; esac
            ssh_args+=( -i "$X_KEY" )
        fi
        [[ -n $X_JUMP ]] && ssh_args+=( -J "$X_JUMP" )
        if [[ $X_USER == root ]]; then printf -v remote_command 'bash -c %q' "$ENDPOINT_SCRIPT"
        else printf -v remote_command 'sudo bash -c %q' "$ENDPOINT_SCRIPT"; fi
        "${ssh_args[@]}" "$X_USER@$X_HOST" "$remote_command"
    fi
}

confirm_action() {
    local word=$1 value
    ((ASSUME_YES)) && return
    printf '\nThis action changes live routing on local/remote hosts and may interrupt SSH.\n'
    read -r -p "Type $word to continue: " value || exit 1
    [[ $value == "$word" ]] || die 'confirmation did not match; nothing changed'
}

perform_action() {
    local op=$1 i side
    ((${#N_IF[@]})) || die 'no tunnels are defined'
    if [[ $op == plan ]]; then list_tunnels; for ((i=0; i<${#N_IF[@]}; i++)); do print_endpoint "$i" A apply; print_endpoint "$i" B apply; done; return; fi
    [[ $op != apply ]] || confirm_action APPLY
    [[ $op != destroy ]] || confirm_action DESTROY
    if [[ $op == destroy ]]; then
        for ((i=${#N_IF[@]}-1; i>=0; i--)); do run_endpoint "$i" B destroy; run_endpoint "$i" A destroy; done
    else
        for ((i=0; i<${#N_IF[@]}; i++)); do for side in A B; do run_endpoint "$i" "$side" "$op"; done; done
    fi
}

export_scripts() {
    local dir=$1 i side op file
    mkdir -p -- "$dir"
    for ((i=0; i<${#N_IF[@]}; i++)); do
        for side in A B; do for op in apply destroy status; do
            build_script "$i" "$side" "$op"; file=$(printf '%s/%02d-%s-%s-%s.sh' "$dir" "$((i+1))" "${N_IF[i]}" "$side" "$op")
            { printf '#!/usr/bin/env bash\n# Run as root on %s.\n' "$(target_label "$i" "$side")"; printf '%s' "$ENDPOINT_SCRIPT"; } > "$file"; chmod 700 "$file"
        done; done
    done
    printf 'Exported endpoint scripts to %s\n' "$dir"
}

interactive_menu() {
    local choice
    while :; do
        printf '\nIPIP TUNNEL MASTER — %s tunnel(s)\n' "${#N_IF[@]}"
        cat <<'MENU'
  1) Add an IPIP tunnel
  2) List tunnel topology
  3) Remove a tunnel definition
  4) Save topology
  5) Load and append topology
  6) Print complete command plan
  7) Apply all tunnels
  8) Show live status
  9) Destroy all tunnels
  E) Export standalone endpoint scripts
  Q) Quit
MENU
        read -r -p 'Choose: ' choice || exit 0
        case ${choice,,} in
            1) add_tunnel ;; 2) list_tunnels ;; 3) remove_tunnel ;;
            4) prompt_required 'Save filename' ipip-topology.txt; save_topology "$REPLY" ;;
            5) prompt_required 'Topology file'; load_topology "$REPLY" ;;
            6) perform_action plan ;; 7) perform_action apply ;; 8) perform_action status ;; 9) perform_action destroy ;;
            e) prompt_required 'Export directory' ipip-endpoint-scripts; export_scripts "$REPLY" ;;
            q) return ;; *) printf 'Choose one of the displayed options.\n' ;;
        esac
    done
}

EXPORT_DIR=""
while (($#)); do
    case $1 in
        -h|--help) usage; exit 0 ;; --version) printf '%s %s\n' "$PROGRAM" "$VERSION"; exit 0 ;;
        --load) (($# >= 2)) || die '--load requires a file'; LOAD_FILE=$2; shift ;; --load=*) LOAD_FILE=${1#*=} ;;
        --plan) ACTION=plan ;; --apply) ACTION=apply ;; --status) ACTION=status ;; --destroy) ACTION=destroy ;;
        --export) (($# >= 2)) || die '--export requires a directory'; ACTION=export; EXPORT_DIR=$2; shift ;; --export=*) ACTION=export; EXPORT_DIR=${1#*=} ;;
        --yes) ASSUME_YES=1 ;; *) die "unknown option: $1" ;;
    esac
    shift
done

[[ -z $LOAD_FILE ]] || load_topology "$LOAD_FILE"
case $ACTION in menu) interactive_menu ;; plan|apply|status|destroy) perform_action "$ACTION" ;; export) export_scripts "$EXPORT_DIR" ;; esac
__MASTER_IPIP_PAYLOAD__
}

prepare_embedded_tools() {
    [[ -n $SESSION_DIR ]] && return 0
    SESSION_DIR=$(mktemp -d "${TMPDIR:-/tmp}/network-master.XXXXXX")
    write_nmap_payload "$SESSION_DIR/nmap.sh"
    write_ssh_payload "$SESSION_DIR/ssh-tunnel-master.sh"
    write_ipip_payload "$SESSION_DIR/ipip-tunnel-master.sh"
    chmod 700 "$SESSION_DIR/nmap.sh" "$SESSION_DIR/ssh-tunnel-master.sh" "$SESSION_DIR/ipip-tunnel-master.sh"
}

pause_menu() {
    printf '\n'
    read -r -p 'Press Enter to return to the master menu...' _ || true
}

run_tool() {
    local file=$1 label=$2 status
    prepare_embedded_tools
    printf '\nStarting %s...\n' "$label"
    if bash "$SESSION_DIR/$file"; then status=0; else status=$?; fi
    printf '\n%s closed with status %s. Returning to the master menu.\n' "$label" "$status"
    pause_menu
}

dependency_check() {
    local name path
    printf '\nEMBEDDED TOOLS\n'
    printf '  BUILT IN   nmap.sh\n'
    printf '  BUILT IN   ssh-tunnel-master.sh\n'
    printf '  BUILT IN   ipip-tunnel-master.sh\n'

    printf '\nSYSTEM COMMANDS\n'
    for name in bash ssh ip nmap sudo terminator remotinator; do
        path=$(command -v "$name" 2>/dev/null || true)
        if [[ -n $path ]]; then printf '  OK         %-12s %s\n' "$name" "$path"
        else printf '  MISSING    %-12s\n' "$name"; fi
    done
    for name in autossh realpath readlink; do
        path=$(command -v "$name" 2>/dev/null || true)
        if [[ -n $path ]]; then printf '  OPTIONAL   %-12s %s\n' "$name" "$path"
        else printf '  OPTIONAL   %-12s not installed\n' "$name"; fi
    done

    prepare_embedded_tools
    printf '\nSSH / TERMINATOR DETAIL\n'
    bash "$SESSION_DIR/ssh-tunnel-master.sh" --doctor || true
    pause_menu
}

extract_tools() {
    local destination=$1
    mkdir -p -- "$destination"
    write_nmap_payload "$destination/nmap.sh"
    write_ssh_payload "$destination/ssh-tunnel-master.sh"
    write_ipip_payload "$destination/ipip-tunnel-master.sh"
    chmod 700 "$destination/nmap.sh" "$destination/ssh-tunnel-master.sh" "$destination/ipip-tunnel-master.sh"
    printf 'Extracted all three embedded tools to %s\n' "$destination"
}

about() {
    cat <<ABOUT

$PROGRAM $VERSION

This is one self-contained Bash file. Complete copies of all three tools are
embedded inside master.sh. It does not search for or load companion scripts.

When a tool starts, the master writes its embedded copy into a private temporary
directory, runs it, returns to this menu when it closes, and deletes the runtime
copies when the master exits.

Embedded tools:
  nmap.sh                 Interactive scanning and discovery
  ssh-tunnel-master.sh    Local, remote, SOCKS, and advanced SSH tunnels
  ipip-tunnel-master.sh   Multi-box and nested Linux IPIP tunnels
ABOUT
    pause_menu
}

main_menu() {
    local choice
    while :; do
        cat <<'MENU'
============================================================
                 NETWORK / SECURITY MASTER
============================================================
  1) Nmap scanner and network discovery
  2) SSH Tunnel Master
  3) IPIP Tunnel Master
  4) Check system dependencies
  5) About this self-contained tool
  Q) Quit
MENU
        read -r -p 'Choose: ' choice || return 0
        case ${choice,,} in
            1) run_tool nmap.sh 'Nmap tool' ;;
            2) run_tool ssh-tunnel-master.sh 'SSH Tunnel Master' ;;
            3) run_tool ipip-tunnel-master.sh 'IPIP Tunnel Master' ;;
            4) dependency_check ;;
            5) about ;;
            q) return 0 ;;
            *) printf 'Choose 1-5 or Q.\n' ;;
        esac
    done
}

usage() {
cat <<HELP
$PROGRAM $VERSION — self-contained networking tool collection

Usage:
  ./$PROGRAM                 Open the persistent master menu
  ./$PROGRAM --check         Check dependencies, then open the menu
  ./$PROGRAM --extract DIR   Write standalone copies of the embedded tools
  ./$PROGRAM --help          Show this help

No companion scripts or cheat sheets are required by master.sh.
HELP
}

case ${1-} in
    '') ;;
    -h|--help) usage; exit 0 ;;
    --version) printf '%s %s\n' "$PROGRAM" "$VERSION"; exit 0 ;;
    --check) dependency_check ;;
    --extract) (($# >= 2)) || die '--extract requires a directory'; extract_tools "$2"; exit 0 ;;
    --extract=*) extract_tools "${1#*=}"; exit 0 ;;
    *) die "unknown option: $1" ;;
esac

main_menu
