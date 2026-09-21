#!/usr/bin/env bash
# nmap-toolkit.sh — comprehensive, reviewable Nmap command builder/runner.
# Use only on systems and networks you own or are explicitly authorized to test.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION="1.0.0"
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
nmap-toolkit.sh — understandable Nmap wrapper with presets and full passthrough

USAGE
  nmap-toolkit.sh [WRAPPER OPTIONS] --target TARGET [-- NMAP OPTIONS...]
  nmap-toolkit.sh --profile PROFILE -t TARGET [OPTIONS]
  nmap-toolkit.sh --list-profiles
  nmap-toolkit.sh --explain PROFILE

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
  nmap-toolkit.sh --dry-run -P inventory -t 10.20.0.0/24 -oA inventory

  # Execute an authorized TCP inventory with output files:
  nmap-toolkit.sh --authorized -P inventory -t 10.20.0.0/24 \
    --top-ports 200 --timing 3 --output-dir results -oA office

  # UDP services, bounded ports/rate and no discovery:
  sudo nmap-toolkit.sh --authorized -P udp -Pn -t 10.20.0.53 \
    -p 53,123,161 --max-rate 50 -sV --reason

  # Native feature not modeled by the wrapper:
  nmap-toolkit.sh --dry-run -t 10.20.0.10 -- -sS --defeat-rst-ratelimit

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
