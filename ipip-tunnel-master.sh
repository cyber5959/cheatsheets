#!/usr/bin/env bash
# ipip-tunnel-master.sh — interactive Linux IP-in-IP topology manager.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION=1.0.0
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
    local a=$1 b=$2 ap=${a##*/} bp=${b##*/} ai bi mask
    [[ $ap == "$bp" ]] || return 1
    ai=$(ip_to_int "${a%/*}"); bi=$(ip_to_int "${b%/*}")
    if ((10#$ap == 32)); then ((ai != bi)); return; fi
    if ((10#$ap == 0)); then mask=0; else mask=$(( (0xFFFFFFFF << (32 - 10#$ap)) & 0xFFFFFFFF )); fi
    (( (ai & mask) == (bi & mask) && ai != bi ))
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
    local label=$1
    while :; do
        prompt "$label runs commands locally or over SSH? (local/ssh)" ssh
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
    local ifname depth suggested mtu ttl pmtu forward
    printf '\nAdd tunnels in dependency order: underlay first, nested tunnels later.\n'
    while :; do
        prompt_required 'Tunnel interface name (15 characters maximum)'
        ifname=$REPLY
        [[ ${#ifname} -le 15 && $ifname =~ ^[A-Za-z0-9_.-]+$ ]] && break
        printf 'Use 1-15 letters, digits, dots, underscores, or dashes.\n'
    done
    printf '\n--- Endpoint A ---\n'; collect_endpoint A
    local a_kind=$EP_KIND a_host=$EP_HOST a_user=$EP_USER a_port=$EP_PORT a_key=$EP_KEY a_jump=$EP_JUMP a_outer=$EP_OUTER a_inner=$EP_INNER a_dev=$EP_DEV a_routes=$EP_ROUTES
    printf '\n--- Endpoint B ---\n'; collect_endpoint B
    local b_kind=$EP_KIND b_host=$EP_HOST b_user=$EP_USER b_port=$EP_PORT b_key=$EP_KEY b_jump=$EP_JUMP b_outer=$EP_OUTER b_inner=$EP_INNER b_dev=$EP_DEV b_routes=$EP_ROUTES
    same_inner_network "$a_inner" "$b_inner" || die 'endpoint inner addresses must be different members of the same IPv4 prefix'
    valid_routes "$a_routes" && valid_routes "$b_routes" || die 'routes must be IPv4/prefix values or default, separated by commas'
    [[ ! ($a_kind == local && $b_kind == local) ]] || die 'both endpoints cannot use the same local network namespace'
    [[ ! ($a_kind == ssh && $b_kind == ssh && $a_host == "$b_host" && $a_port == "$b_port") ]] || die 'both endpoints cannot be the same remote network namespace'
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
    local i=$1 side=$2 operation=$3 ifname=${N_IF[i]} outer peer inner peer_inner dev routes mtu=${N_MTU[i]} ttl=${N_TTL[i]} pmtu forward
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
