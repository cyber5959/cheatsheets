#!/usr/bin/env bash
# ssh-tunnel-master.sh — interactive SSH tunnel builder and Terminator launcher.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION=1.0.0
SPLIT_MODE=auto
DRY_RUN=0
AUTO_LAUNCH=0
LOAD_FILE=""

declare -a T_NAME=() T_TYPE=() T_HOST=() T_USER=() T_SSH_PORT=()
declare -a T_BIND=() T_LISTEN=() T_DEST=() T_DEST_PORT=() T_IDENTITY=()
declare -a T_JUMP=() T_RECONNECT=() T_COMPRESS=() T_RAW_FLAG=() T_RAW_SPEC=()
declare -a T_ALIVE=() T_ALIVE_COUNT=()
declare -a SSH_COMMAND=() RECORD_ARGS=()

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
    prompt_required 'Tunnel name shown in the pane title'; C_NAME=$REPLY
    prompt_required 'SSH server hostname or IP'; C_HOST=$REPLY
    prompt_required 'SSH username' "${USER:-}"; C_USER=$REPLY
    prompt_port 'SSH server port' 22; C_SSH_PORT=$REPLY
    prompt 'Identity file; blank lets SSH use its normal keys/passwords' ''; C_IDENTITY=$REPLY
    prompt 'Jump host; blank for none ([user@]host[:port])' ''; C_JUMP=$REPLY
    prompt_yes_no 'Compress the SSH connection?' n; C_COMPRESS=$REPLY
    prompt_yes_no 'Automatically reconnect with autossh?' n; C_RECONNECT=$REPLY
    prompt 'Server-alive interval in seconds' 30; C_ALIVE=$REPLY
    [[ $C_ALIVE =~ ^[0-9]+$ ]] || { printf 'Using 30 because the interval was invalid.\n'; C_ALIVE=30; }
    prompt 'Missed server-alive replies before disconnecting' 3; C_ALIVE_COUNT=$REPLY
    [[ $C_ALIVE_COUNT =~ ^[0-9]+$ ]] || { printf 'Using 3 because the count was invalid.\n'; C_ALIVE_COUNT=3; }
}

add_local() {
    printf '\nLOCAL FORWARD: a port on this computer reaches a destination through SSH.\n'
    collect_connection
    prompt 'Local bind address' 127.0.0.1; local bind=$REPLY
    prompt_port 'Local listening port'; local listen=$REPLY
    prompt_required 'Destination host as seen by the SSH server'; local dest=$REPLY
    prompt_port 'Destination port'; local dport=$REPLY
    append_tunnel "$C_NAME" local "$C_HOST" "$C_USER" "$C_SSH_PORT" "$bind" "$listen" "$dest" "$dport" "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" '' '' "$C_ALIVE" "$C_ALIVE_COUNT"
}

add_remote() {
    printf '\nREMOTE FORWARD: a port on the SSH server reaches a destination through you.\n'
    collect_connection
    prompt 'Remote bind address' 127.0.0.1; local bind=$REPLY
    prompt_port 'Remote listening port'; local listen=$REPLY
    prompt_required 'Destination host as seen from this computer' 127.0.0.1; local dest=$REPLY
    prompt_port 'Destination port'; local dport=$REPLY
    append_tunnel "$C_NAME" remote "$C_HOST" "$C_USER" "$C_SSH_PORT" "$bind" "$listen" "$dest" "$dport" "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" '' '' "$C_ALIVE" "$C_ALIVE_COUNT"
}

add_dynamic() {
    printf '\nDYNAMIC FORWARD: create a local SOCKS4/5 proxy through SSH.\n'
    collect_connection
    prompt 'Local SOCKS bind address' 127.0.0.1; local bind=$REPLY
    prompt_port 'Local SOCKS listening port' 1080; local listen=$REPLY
    append_tunnel "$C_NAME" dynamic "$C_HOST" "$C_USER" "$C_SSH_PORT" "$bind" "$listen" '' '' "$C_IDENTITY" "$C_JUMP" "$C_RECONNECT" "$C_COMPRESS" '' '' "$C_ALIVE" "$C_ALIVE_COUNT"
}

add_remote_socks() {
    printf '\nREMOTE SOCKS: create a SOCKS proxy that listens on the SSH server.\n'
    collect_connection
    prompt 'Remote SOCKS bind address' 127.0.0.1; local bind=$REPLY
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
    printf '\n%-4s %-20s %-13s %-28s %s\n' '#' 'NAME' 'TYPE' 'SSH CONNECTION' 'FORWARD'
    printf '%-4s %-20s %-13s %-28s %s\n' '----' '--------------------' '-------------' '----------------------------' '------------------------------'
    for ((i=0; i<${#T_NAME[@]}; i++)); do
        printf '%-4s %-20.20s %-13s %-28.28s ' "$((i+1))" "${T_NAME[i]}" "${T_TYPE[i]}" "${T_USER[i]}@${T_HOST[i]}:${T_SSH_PORT[i]}"
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

wait_for_new_terminal() {
    local before_file=$1 attempt uuid
    for ((attempt=0; attempt<80; attempt++)); do
        while IFS= read -r uuid; do
            [[ -n $uuid ]] || continue
            if ! grep -Fqx -- "$uuid" "$before_file" 2>/dev/null; then printf '%s\n' "$uuid"; return 0; fi
        done < <(remotinator get_terminals 2>/dev/null || true)
        sleep 0.125
    done
    return 1
}

launch_tunnels() {
    local count=${#T_NAME[@]} i script before_file root_uuid new_uuid split_cmd command_string split_output arg
    local anchor depth line remotinator_help
    local -a queue_uuids=() queue_depths=()
    ((count > 0)) || die 'add or load at least one tunnel before launching'
    printf '\nTunnel launch plan (%s panes, split mode: %s):\n' "$count" "$SPLIT_MODE"
    for ((i=0; i<count; i++)); do build_ssh_command "$i"; printf '[%s] %s\n' "$((i+1))" "${T_NAME[i]}"; print_command "${SSH_COMMAND[@]}"; done
    if ((DRY_RUN)); then printf '\nDry run complete; no window or connection was opened.\n'; return; fi
    for arg in ssh terminator remotinator; do command -v "$arg" >/dev/null 2>&1 || die "required command not found: $arg"; done
    remotinator_help=$(remotinator -h 2>&1 || true)
    [[ $remotinator_help == *--execute* ]] || die 'this Terminator/Remotinator version lacks command-enabled splits; install a current Terminator release'
    [[ $remotinator_help == *--title* ]] || die 'this Terminator/Remotinator version lacks titled splits; install a current Terminator release'
    for ((i=0; i<count; i++)); do
        if [[ ${T_RECONNECT[i]} == yes ]] && ! command -v autossh >/dev/null 2>&1; then die "tunnel '${T_NAME[i]}' requests reconnect but autossh is not installed"; fi
    done
    script=$(self_path)
    before_file=$(mktemp)
    trap 'rm -f -- "${before_file:-}"' EXIT
    remotinator get_terminals > "$before_file" 2>/dev/null || :
    record_args 0
    terminator --title="${T_NAME[0]}" -x bash "$script" __pane "${RECORD_ARGS[@]}" >/dev/null 2>&1 &
    root_uuid=$(wait_for_new_terminal "$before_file") || die 'Terminator started, but its new pane UUID could not be found. Check that Terminator DBus is enabled.'
    printf 'Opened pane 1/%s: %s\n' "$count" "${T_NAME[0]}"
    queue_uuids=("$root_uuid")
    queue_depths=(0)
    for ((i=1; i<count; i++)); do
        anchor=${queue_uuids[0]}
        depth=${queue_depths[0]}
        queue_uuids=("${queue_uuids[@]:1}")
        queue_depths=("${queue_depths[@]:1}")
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
        queue_uuids+=("$anchor" "$new_uuid")
        queue_depths+=("$((depth+1))" "$((depth+1))")
        printf 'Opened pane %s/%s: %s\n' "$((i+1))" "$count" "${T_NAME[i]}"
    done
    rm -f -- "$before_file"; trap - EXIT
    printf '\nAll tunnel panes were created.\n'
}

interactive_menu() {
    local choice file
    while :; do
        printf '\nSSH TUNNEL MASTER — %s tunnel(s) defined\n' "${#T_NAME[@]}"
        cat <<'MENU'
  1) Add local forward       (-L)
  2) Add remote forward      (-R)
  3) Add local SOCKS proxy   (-D)
  4) Add remote SOCKS proxy  (-R without destination)
  5) Add advanced/raw forward
  6) List tunnels
  7) Remove a tunnel
  8) Save tunnel set
  9) Load and append tunnel set
  S) Change pane split mode
  L) Launch all tunnels
  D) Dry-run all tunnels
  Q) Quit
MENU
        read -r -p 'Choose: ' choice || exit 0
        case ${choice,,} in
            1) add_local ;; 2) add_remote ;; 3) add_dynamic ;; 4) add_remote_socks ;;
            5) add_raw ;; 6) list_tunnels ;; 7) remove_tunnel ;;
            8) prompt_required 'Save filename' 'ssh-tunnels.txt'; save_tunnels "$REPLY" ;;
            9) prompt_required 'File to load'; load_tunnels "$REPLY" ;;
            s) prompt 'Split mode: auto, horizontal, or vertical' "$SPLIT_MODE"; case $REPLY in auto|horizontal|vertical) SPLIT_MODE=$REPLY ;; *) printf 'Unknown split mode.\n' ;; esac ;;
            l) DRY_RUN=0; launch_tunnels; return ;;
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
if ((AUTO_LAUNCH)); then launch_tunnels
else interactive_menu
fi
