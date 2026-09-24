#!/usr/bin/env bash
# obsidian-network-map.sh — interactive network inventory and Obsidian map builder.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
VERSION=1.2.0
PROJECT_FILE=''
PROJECT_READY=0
PROJECT_DIRTY=0
STATE_DIR_OVERRIDE=''
declare -a RECENT_PROJECTS=()

declare -a D_NAME=() D_ROLE=() D_MGMT=() D_INTERNAL=() D_EXTERNAL=() D_INTERFACES=() D_NOTES=() D_SOURCE=()
declare -a R_FROM=() R_TO=() R_LABEL=() R_DEST=() R_GATEWAY=() R_INTERFACE=()

encode_field() { local value=$1; value=${value//%/%25}; value=${value//|/%7C}; printf '%s' "$value"; }
decode_field() { local value=$1; value=${value//%7C/|}; value=${value//%25/%}; printf '%s' "$value"; }

reset_map() {
    D_NAME=(); D_ROLE=(); D_MGMT=(); D_INTERNAL=(); D_EXTERNAL=(); D_INTERFACES=(); D_NOTES=(); D_SOURCE=()
    R_FROM=(); R_TO=(); R_LABEL=(); R_DEST=(); R_GATEWAY=(); R_INTERFACE=()
}

save_project() {
    local quiet=${1:-no} directory base temporary i value
    [[ -n $PROJECT_FILE ]] || return 0
    directory=$(dirname -- "$PROJECT_FILE"); base=$(basename -- "$PROJECT_FILE")
    mkdir -p -- "$directory" || { printf 'ERROR: cannot create project directory: %s\n' "$directory" >&2; return 1; }
    temporary="$directory/.$base.tmp.$$"
    {
        printf '# obsidian-network-map project v1\n'
        printf '# Do not edit while the mapper is running. Fields are percent-escaped.\n'
        for ((i=0; i<${#D_NAME[@]}; i++)); do
            printf 'D'
            for value in "${D_NAME[i]}" "${D_ROLE[i]}" "${D_MGMT[i]}" "${D_INTERNAL[i]}" "${D_EXTERNAL[i]}" "${D_INTERFACES[i]}" "${D_NOTES[i]}" "${D_SOURCE[i]}"; do printf '|%s' "$(encode_field "$value")"; done
            printf '\n'
        done
        for ((i=0; i<${#R_FROM[@]}; i++)); do
            printf 'R|%s|%s' "${R_FROM[i]}" "${R_TO[i]}"
            for value in "${R_LABEL[i]}" "${R_DEST[i]}" "${R_GATEWAY[i]}" "${R_INTERFACE[i]}"; do printf '|%s' "$(encode_field "$value")"; done
            printf '\n'
        done
    } > "$temporary" || { rm -f -- "$temporary"; return 1; }
    mv -f -- "$temporary" "$PROJECT_FILE" || { rm -f -- "$temporary"; return 1; }
    PROJECT_DIRTY=0
    [[ $quiet == yes ]] || printf 'Saved project: %s\n' "$PROJECT_FILE"
}

autosave() {
    ((PROJECT_READY)) || return 0
    PROJECT_DIRTY=1
    if save_project yes; then printf '[autosaved %s]\n' "$PROJECT_FILE"
    else printf 'WARNING: autosave failed; use option 9 after fixing the project path.\n' >&2; fi
}

load_project() {
    local file=$1 line=0 type a b c d e f g h extra from to
    [[ -r $file ]] || return 1
    reset_map
    while IFS='|' read -r type a b c d e f g h extra || [[ -n ${type-} ]]; do
        ((line+=1)); [[ -z ${type-} || $type == \#* ]] && continue
        case $type in
            D)
                [[ -z ${extra-} ]] || { printf 'ERROR: %s:%s has too many device fields.\n' "$file" "$line" >&2; return 2; }
                D_NAME+=("$(decode_field "$a")"); D_ROLE+=("$(decode_field "$b")"); D_MGMT+=("$(decode_field "$c")"); D_INTERNAL+=("$(decode_field "$d")")
                D_EXTERNAL+=("$(decode_field "$e")"); D_INTERFACES+=("$(decode_field "$f")"); D_NOTES+=("$(decode_field "$g")"); D_SOURCE+=("$(decode_field "$h")")
                ;;
            R)
                [[ -z ${h-} && -z ${extra-} ]] || { printf 'ERROR: %s:%s has too many route fields.\n' "$file" "$line" >&2; return 2; }
                from=$a; to=$b
                [[ $from =~ ^[0-9]+$ && $to =~ ^[0-9]+$ ]] || { printf 'ERROR: %s:%s has invalid route indexes.\n' "$file" "$line" >&2; return 2; }
                R_FROM+=("$from"); R_TO+=("$to"); R_LABEL+=("$(decode_field "$c")"); R_DEST+=("$(decode_field "$d")"); R_GATEWAY+=("$(decode_field "$e")"); R_INTERFACE+=("$(decode_field "$f")")
                ;;
            *) printf 'ERROR: %s:%s has an unknown record type.\n' "$file" "$line" >&2; return 2 ;;
        esac
    done < "$file"
    for ((line=0; line<${#R_FROM[@]}; line++)); do
        ((R_FROM[line] < ${#D_NAME[@]} && R_TO[line] < ${#D_NAME[@]})) || { printf 'ERROR: project route %s points to a missing device.\n' "$((line+1))" >&2; return 2; }
    done
    PROJECT_FILE=$file; PROJECT_READY=1; PROJECT_DIRTY=0
    printf 'Loaded %s device(s) and %s link(s) from %s\n' "${#D_NAME[@]}" "${#R_FROM[@]}" "$PROJECT_FILE"
}

open_project() {
    local requested=${1-} old_file=$PROJECT_FILE
    [[ -n $requested ]] || { prompt 'Project file to open or create' './obsidian-network-map.project'; requested=$REPLY; }
    [[ -n $requested ]] || { printf 'A project filename is required.\n'; return 1; }
    requested=$(absolute_project_path "$requested")
    [[ -z $old_file || $requested == "$old_file" ]] || save_project yes || return 1
    if [[ -e $requested ]]; then
        if ! load_project "$requested"; then
            printf 'Could not load that project. The previous project remains saved at %s.\n' "${old_file:-(none)}" >&2
            [[ -z $old_file || ! -r $old_file ]] || load_project "$old_file" >/dev/null
            return 1
        fi
    else
        reset_map; PROJECT_FILE=$requested; PROJECT_READY=1; PROJECT_DIRTY=1
        save_project yes || { PROJECT_READY=0; return 1; }
        printf 'Created new project: %s\n' "$PROJECT_FILE"
    fi
    remember_project "$PROJECT_FILE"
}

save_on_exit() { ((PROJECT_READY && PROJECT_DIRTY)) && save_project yes || true; }
trap save_on_exit EXIT
trap 'printf "\nClosing; the current project will be saved.\n"; exit 130' HUP INT TERM

recent_file() {
    local state_root=${STATE_DIR_OVERRIDE:-${XDG_STATE_HOME:-${HOME:-.}/.local/state}}
    printf '%s/obsidian-network-map/recent-projects' "$state_root"
}

absolute_project_path() {
    local value=$1
    if command -v realpath >/dev/null 2>&1; then realpath -m -- "$value"
    elif command -v readlink >/dev/null 2>&1 && readlink -m -- "$value" >/dev/null 2>&1; then readlink -m -- "$value"
    elif [[ $value == /* ]]; then printf '%s' "$value"
    else printf '%s/%s' "$PWD" "${value#./}"; fi
}

load_recent_projects() {
    local file item
    RECENT_PROJECTS=(); file=$(recent_file)
    [[ -r $file ]] || return 0
    while IFS= read -r item || [[ -n $item ]]; do
        [[ -n $item && -r $item ]] || continue
        RECENT_PROJECTS+=("$item")
        ((${#RECENT_PROJECTS[@]} >= 10)) && break
    done < "$file"
}

remember_project() {
    local project=$1 file directory temporary item count=0
    local -a remembered=("$project")
    file=$(recent_file); directory=$(dirname -- "$file"); mkdir -p -- "$directory" 2>/dev/null || return 0
    if [[ -r $file ]]; then
        while IFS= read -r item || [[ -n $item ]]; do
            [[ -n $item && $item != "$project" ]] || continue
            remembered+=("$item"); ((${#remembered[@]} >= 10)) && break
        done < "$file"
    fi
    temporary="$directory/.recent-projects.tmp.$$"
    for item in "${remembered[@]}"; do printf '%s\n' "$item"; done > "$temporary" || return 0
    mv -f -- "$temporary" "$file" 2>/dev/null || rm -f -- "$temporary"
}

project_start_screen() {
    local choice i requested
    while :; do
        load_recent_projects
        printf '\nOBSIDIAN NETWORK MAP — START OR RESUME\n'
        if ((${#RECENT_PROJECTS[@]})); then
            printf '  R) Resume last project: %s\n' "${RECENT_PROJECTS[0]}"
            printf '\n  RECENT PROJECTS\n'
            for ((i=0; i<${#RECENT_PROJECTS[@]}; i++)); do printf '  %s) %s\n' "$((i+1))" "${RECENT_PROJECTS[i]}"; done
        else
            printf '  No recent projects have been saved yet.\n'
        fi
        cat <<'START_MENU'

  O) Open an existing project file
  N) Create a new project
  Q) Close
START_MENU
        read -r -p 'Choose: ' choice || return 1
        case ${choice,,} in
            r)
                ((${#RECENT_PROJECTS[@]})) || { printf 'There is no recent project to resume.\n'; continue; }
                open_project "${RECENT_PROJECTS[0]}" && return 0
                ;;
            o)
                prompt_required 'Existing project file'; requested=$REPLY
                [[ -f $requested ]] || { printf 'That project file does not exist.\n'; continue; }
                open_project "$requested" && return 0
                ;;
            n)
                prompt_required 'New project file' './obsidian-network-map.project'; requested=$REPLY
                if [[ -e $requested ]]; then printf 'That file already exists. Choose Open or enter a different filename.\n'; continue; fi
                open_project "$requested" && return 0
                ;;
            q) return 1 ;;
            * )
                if [[ $choice =~ ^[0-9]+$ ]] && ((10#$choice >= 1 && 10#$choice <= ${#RECENT_PROJECTS[@]})); then
                    open_project "${RECENT_PROJECTS[$((10#$choice-1))]}" && return 0
                else printf 'Choose R, a recent project number, O, N, or Q.\n'; fi
                ;;
        esac
    done
}

prompt() {
    local label=$1 default=${2-} value
    if [[ -n $default ]]; then read -r -p "$label [$default]: " value || exit 0
    else read -r -p "$label: " value || exit 0; fi
    REPLY=${value:-$default}
}

prompt_required() {
    local label=$1 default=${2-}
    while :; do prompt "$label" "$default"; [[ -n $REPLY ]] && return; printf 'A value is required.\n'; done
}

prompt_yes_no() {
    local label=$1 default=${2:-n} value suffix
    [[ $default == y ]] && suffix=Y/n || suffix=y/N
    while :; do
        read -r -p "$label [$suffix]: " value || exit 0
        value=${value:-$default}
        case ${value,,} in y|yes) REPLY=yes; return ;; n|no) REPLY=no; return ;; *) printf 'Enter y or n.\n' ;; esac
    done
}

valid_ipv4() {
    local ip=$1 part
    local -a parts=()
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.; read -r -a parts <<< "$ip"
    ((${#parts[@]} == 4)) || return 1
    for part in "${parts[@]}"; do ((10#$part <= 255)) || return 1; done
}

valid_cidr() {
    local value=$1 ip prefix
    [[ $value == */* ]] || return 1
    ip=${value%/*}; prefix=${value##*/}
    valid_ipv4 "$ip" && [[ $prefix =~ ^[0-9]+$ ]] && ((10#$prefix <= 32))
}

valid_hostname() {
    local value=$1 label
    local -a labels=()
    ((${#value} >= 1 && ${#value} <= 253)) || return 1
    [[ $value != .* && $value != *. && $value != *..* ]] || return 1
    local IFS=.; read -r -a labels <<< "$value"
    for label in "${labels[@]}"; do
        ((${#label} >= 1 && ${#label} <= 63)) || return 1
        [[ $label =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

valid_ipv6() {
    local value=$1 zone='' left right part count=0
    local -a groups=()
    if [[ $value == \[*\] ]]; then value=${value:1:${#value}-2}
    elif [[ $value == *'['* || $value == *']'* ]]; then return 1; fi
    if [[ $value == *%* ]]; then zone=${value##*%}; value=${value%%%*}; [[ $zone =~ ^[A-Za-z0-9_.-]+$ ]] || return 1; fi
    [[ $value == *:* && $value =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    if [[ $value == *::* ]]; then
        left=${value%%::*}; right=${value#*::}; [[ $right != *::* ]] || return 1
        for part in "$left" "$right"; do
            [[ -z $part ]] && continue
            local IFS=:; read -r -a groups <<< "$part"
            for part in "${groups[@]}"; do [[ $part =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1; ((count+=1)); done
        done
        ((count < 8))
    else
        local IFS=:; read -r -a groups <<< "$value"
        ((${#groups[@]} == 8)) || return 1
        for part in "${groups[@]}"; do [[ $part =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1; done
    fi
}

valid_address() {
    local value=$1
    [[ -n $value && $value != *[[:space:]]* ]] || return 1
    if [[ $value == */* ]]; then valid_cidr "$value"; return; fi
    if [[ $value =~ ^[0-9.]+$ ]]; then valid_ipv4 "$value"; return; fi
    valid_ipv6 "$value" || valid_hostname "$value"
}

prompt_optional_address() {
    local label=$1 default=${2-}
    while :; do
        prompt "$label" "$default"
        [[ -z $REPLY ]] && return
        valid_address "$REPLY" && return
        printf 'Enter a complete IPv4 address, IPv4/prefix, IPv6 address, or hostname; or leave blank.\n'
        printf 'Example: 192.168.1.10 (not 192.168.1)\n'
    done
}

prompt_host() {
    local label=$1
    while :; do prompt_required "$label"; valid_address "$REPLY" && [[ $REPLY != */* ]] && return; printf 'Enter a complete IP address or hostname.\n'; done
}

clean_text() { local value=$1; [[ $value != *[[:cntrl:]]* ]] || { printf 'Control characters are not allowed.\n' >&2; return 1; }; }

find_device_by_address() {
    local address=$1 i field item
    local -a items=()
    for ((i=0; i<${#D_NAME[@]}; i++)); do
        for field in "${D_MGMT[i]}" "${D_INTERNAL[i]}" "${D_EXTERNAL[i]}"; do [[ $field == "$address" ]] && { printf '%s' "$i"; return 0; }; done
        local IFS=','; read -r -a items <<< "${D_INTERFACES[i]}"
        for item in "${items[@]}"; do [[ ${item#*:} == "$address" || ${item#*=} == "$address" ]] && { printf '%s' "$i"; return 0; }; done
    done
    return 1
}

add_device_record() {
    local name=$1 role=$2 mgmt=$3 internal=$4 external=$5 interfaces=$6 notes=$7 source=$8 existing
    clean_text "$name$role$interfaces$notes" || return 1
    if [[ -n $mgmt ]] && existing=$(find_device_by_address "$mgmt"); then
        printf 'Address %s is already recorded on device %s.\n' "$mgmt" "${D_NAME[existing]}"
        ADDED_INDEX=$existing
        return 0
    fi
    D_NAME+=("$name"); D_ROLE+=("$role"); D_MGMT+=("$mgmt"); D_INTERNAL+=("$internal"); D_EXTERNAL+=("$external")
    D_INTERFACES+=("$interfaces"); D_NOTES+=("$notes"); D_SOURCE+=("$source"); ADDED_INDEX=$((${#D_NAME[@]}-1))
    printf 'Added device %s as number %s.\n' "$name" "$((ADDED_INDEX+1))"
    autosave
}

add_device() {
    local name role mgmt internal external interfaces notes
    printf '\nADD A DEVICE\nUse a useful name such as Laptop, Edge Router, Jump Box, or Internal Web.\n'
    prompt_required 'Device name'; name=$REPLY
    prompt 'Role/type' host; role=$REPLY
    prompt_optional_address 'Management IP or hostname; blank if unknown'; mgmt=$REPLY
    prompt_optional_address 'Internal/private IP; blank if unknown'; internal=$REPLY
    prompt_optional_address 'External/public IP; blank if unknown'; external=$REPLY
    prompt 'Interfaces summary; blank if unknown (example: eth0=10.0.0.5/24, tun0=10.50.0.1/30)' ''; interfaces=$REPLY
    prompt 'Notes; blank if none' ''; notes=$REPLY
    add_device_record "$name" "$role" "$mgmt" "$internal" "$external" "$interfaces" "$notes" manual
}

discover_local() {
    local name role=local-host mgmt='' internal='' external='' interfaces='' notes='' line iface cidr default_route
    command -v ip >/dev/null 2>&1 || { printf 'The ip command is required for local discovery. Add the device manually instead.\n'; return 1; }
    prompt 'Device name' "$(hostname 2>/dev/null || printf local-host)"; name=$REPLY
    while IFS= read -r line; do
        iface=$(awk '{print $2}' <<< "$line"); cidr=$(awk '{print $4}' <<< "$line")
        [[ -z $cidr ]] && continue
        [[ -z $interfaces ]] || interfaces+=', '
        interfaces+="$iface=$cidr"
        [[ $iface == lo || -n $internal ]] || internal=$cidr
    done < <(ip -o -4 addr show 2>/dev/null || true)
    default_route=$(ip route show default 2>/dev/null | head -n 1 || true)
    [[ -z $default_route ]] || notes="Default route: $default_route"
    prompt_optional_address 'Management IP/hostname' "${internal%/*}"; mgmt=$REPLY
    prompt_optional_address 'External/public IP; blank if not known' ''; external=$REPLY
    add_device_record "$name" "$role" "$mgmt" "$internal" "$external" "$interfaces" "$notes" local-discovery
}

append_route() {
    R_FROM+=("$1"); R_TO+=("$2"); R_LABEL+=("$3"); R_DEST+=("$4"); R_GATEWAY+=("$5"); R_INTERFACE+=("$6")
    autosave
}

list_devices() {
    local i
    if ((${#D_NAME[@]} == 0)); then printf '\nNo devices recorded.\n'; return; fi
    printf '\n%-4s %-24s %-16s %-22s %-22s\n' '#' 'NAME' 'ROLE' 'INTERNAL' 'EXTERNAL'
    for ((i=0; i<${#D_NAME[@]}; i++)); do printf '%-4s %-24.24s %-16.16s %-22.22s %-22.22s\n' "$((i+1))" "${D_NAME[i]}" "${D_ROLE[i]}" "${D_INTERNAL[i]:--}" "${D_EXTERNAL[i]:--}"; done
}

prompt_device_number() {
    local label=$1 value
    while :; do prompt_required "$label"; value=$REPLY; [[ $value =~ ^[0-9]+$ ]] && ((10#$value >= 1 && 10#$value <= ${#D_NAME[@]})) && { REPLY=$((10#$value-1)); return; }; printf 'Choose a displayed device number.\n'; done
}

add_route() {
    local from to label destination gateway interface
    ((${#D_NAME[@]} >= 2)) || { printf 'Add at least two devices first.\n'; return; }
    list_devices
    prompt_device_number 'Traffic starts at device number'; from=$REPLY
    prompt_device_number 'Next device/hop number'; to=$REPLY
    [[ $from != "$to" ]] || { printf 'Start and next hop must be different devices.\n'; return; }
    prompt 'Connection label' routes-to; label=$REPLY
    while :; do prompt 'Destination network reached through this link; blank if general' ''; destination=$REPLY; [[ -z $destination || $destination == default ]] && break; valid_cidr "$destination" && break; printf 'Enter an IPv4 network/prefix such as 10.50.0.0/16, default, or blank.\n'; done
    while :; do prompt 'Gateway/next-hop IP; blank if unknown' ''; gateway=$REPLY; [[ -z $gateway ]] && break; { valid_ipv4 "$gateway" || valid_ipv6 "$gateway"; } && break; printf 'Enter a complete IPv4 or IPv6 address, or leave blank.\n'; done
    prompt 'Outgoing interface; blank if unknown' ''; interface=$REPLY
    append_route "$from" "$to" "$label" "$destination" "$gateway" "$interface"
    printf 'Added link %s -> %s.\n' "${D_NAME[from]}" "${D_NAME[to]}"
}

import_trace_text() {
    local output=$1 target=$2 command_name=$3 line ip previous=-1 index hop=0
    while IFS= read -r line; do
        # Ignore traceroute headers and diagnostics. A hop row begins with its
        # numeric hop index; parsing header addresses would reverse the path.
        [[ $line =~ ^[[:space:]]*[0-9]+[?]?:?[[:space:]] ]] || continue
        if [[ $line =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then ip=${BASH_REMATCH[0]}; valid_ipv4 "$ip" || continue; else continue; fi
        if index=$(find_device_by_address "$ip"); then :
        else ((hop+=1)); add_device_record "Trace hop $hop" router "$ip" "$ip" '' '' "Imported from $command_name to $target" traceroute; index=$ADDED_INDEX; fi
        if ((previous >= 0 && previous != index)); then append_route "$previous" "$index" "trace hop" '' '' ''; fi
        previous=$index
    done <<< "$output"
    ((hop > 0)) && printf 'Imported %s new hop(s). Review names and details in the exported map.\n' "$hop" || printf 'No IPv4 hops were found in the trace output.\n'
}

trace_route() {
    local target max command_name output
    prompt_host 'Trace destination IP or hostname'; target=$REPLY
    while :; do prompt 'Maximum hops' 20; [[ $REPLY =~ ^[0-9]+$ ]] && ((10#$REPLY >= 1 && 10#$REPLY <= 64)) && { max=$REPLY; break; }; printf 'Enter 1 through 64.\n'; done
    if command -v traceroute >/dev/null 2>&1; then command_name=traceroute; output=$(traceroute -n -m "$max" -w 2 "$target" 2>&1 || true)
    elif command -v tracepath >/dev/null 2>&1; then command_name=tracepath; output=$(tracepath -n -m "$max" "$target" 2>&1 || true)
    else printf 'Install traceroute or tracepath, or import saved traceroute output with option 4.\n'; return 1; fi
    printf '\n%s output:\n%s\n' "$command_name" "$output"
    import_trace_text "$output" "$target" "$command_name"
}

import_trace_file() {
    local file target output
    while :; do prompt_required 'Saved traceroute/tracepath output file'; file=$REPLY; [[ -r $file ]] && break; printf 'That file is not readable. Enter its path again.\n'; done
    prompt_host 'Destination represented by this trace'; target=$REPLY
    output=$(cat -- "$file")
    import_trace_text "$output" "$target" "${file##*/}"
}

markdown_escape() { local value=$1; value=${value//|/\\|}; value=${value//$'\n'/ }; printf '%s' "$value"; }
json_escape() { local value=$1; value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//$'\n'/\\n}; value=${value//$'\r'/}; value=${value//$'\t'/\\t}; printf '%s' "$value"; }
mermaid_escape() { local value=$1; value=${value//\"/\'}; value=${value//[/\(}; value=${value//]/\)}; value=${value//$'\n'/ }; printf '%s' "$value"; }

export_markdown() {
    local file=$1 title=$2 i details label
    {
        printf '%s\n' '---' 'type: network-map' "generated: $(date -Iseconds 2>/dev/null || date)" '---' '' "# $title" '' '## Visual map' '' '```mermaid' 'flowchart LR'
        for ((i=0; i<${#D_NAME[@]}; i++)); do
            details=$(mermaid_escape "${D_NAME[i]}<br/>${D_ROLE[i]}<br/>${D_INTERNAL[i]:-${D_MGMT[i]}}")
            printf '  n%s["%s"]\n' "$i" "$details"
        done
        for ((i=0; i<${#R_FROM[@]}; i++)); do label=${R_LABEL[i]}; [[ -n ${R_DEST[i]} ]] && label+=" ${R_DEST[i]}"; printf '  n%s -->|"%s"| n%s\n' "${R_FROM[i]}" "$(mermaid_escape "$label")" "${R_TO[i]}"; done
        printf '%s\n\n' '```' '## Devices' '' '| # | Device | Role | Management | Internal | External | Interfaces | Source |' '|---:|---|---|---|---|---|---|---|'
        for ((i=0; i<${#D_NAME[@]}; i++)); do printf '| %s | %s | %s | `%s` | `%s` | `%s` | %s | %s |\n' "$((i+1))" "$(markdown_escape "${D_NAME[i]}")" "$(markdown_escape "${D_ROLE[i]}")" "${D_MGMT[i]}" "${D_INTERNAL[i]}" "${D_EXTERNAL[i]}" "$(markdown_escape "${D_INTERFACES[i]}")" "${D_SOURCE[i]}"; [[ -z ${D_NOTES[i]} ]] || printf '\n> **%s:** %s\n\n' "$(markdown_escape "${D_NAME[i]}")" "$(markdown_escape "${D_NOTES[i]}")"; done
        printf '%s\n\n' '## Routes and links' '' '| From | Next hop/device | Label | Destination | Gateway | Interface |' '|---|---|---|---|---|---|'
        for ((i=0; i<${#R_FROM[@]}; i++)); do printf '| %s | %s | %s | `%s` | `%s` | `%s` |\n' "$(markdown_escape "${D_NAME[${R_FROM[i]}]}")" "$(markdown_escape "${D_NAME[${R_TO[i]}]}")" "$(markdown_escape "${R_LABEL[i]}")" "${R_DEST[i]}" "${R_GATEWAY[i]}" "${R_INTERFACE[i]}"; done
        printf '\n## Linux route command templates\n\nThese are reviewable examples only; the map builder does not change the routing table.\n\n'
        for ((i=0; i<${#R_FROM[@]}; i++)); do
            [[ -n ${R_DEST[i]} && -n ${R_GATEWAY[i]} ]] || continue
            printf '**On %s:**\n\n```sh\nip route replace %q via %q' "$(markdown_escape "${D_NAME[${R_FROM[i]}]}")" "${R_DEST[i]}" "${R_GATEWAY[i]}"
            [[ -z ${R_INTERFACE[i]} ]] || printf ' dev %q' "${R_INTERFACE[i]}"
            printf '\n```\n\n'
        done
    } > "$file"
}

export_canvas() {
    local file=$1 i x y text label comma=''
    {
        printf '{"nodes":['
        for ((i=0; i<${#D_NAME[@]}; i++)); do
            x=$(( (i % 4) * 420 )); y=$(( (i / 4) * 260 ))
            printf -v text '## %s\n**Role:** %s\n**Management:** %s\n**Internal:** %s\n**External:** %s' "${D_NAME[i]}" "${D_ROLE[i]}" "${D_MGMT[i]:--}" "${D_INTERNAL[i]:--}" "${D_EXTERNAL[i]:--}"
            printf '%s{"id":"node-%s","type":"text","x":%s,"y":%s,"width":360,"height":200,"text":"%s"}' "$comma" "$i" "$x" "$y" "$(json_escape "$text")"; comma=,
        done
        printf '],"edges":['; comma=''
        for ((i=0; i<${#R_FROM[@]}; i++)); do label=${R_LABEL[i]}; [[ -n ${R_DEST[i]} ]] && label+=" ${R_DEST[i]}"; printf '%s{"id":"edge-%s","fromNode":"node-%s","fromSide":"right","toNode":"node-%s","toSide":"left","toEnd":"arrow","label":"%s"}' "$comma" "$i" "${R_FROM[i]}" "${R_TO[i]}" "$(json_escape "$label")"; comma=,; done
        printf ']}\n'
    } > "$file"
}

export_map() {
    local destination title basename md canvas
    ((${#D_NAME[@]})) || { printf 'Add or discover at least one device first.\n'; return; }
    prompt_required 'Destination folder inside your Obsidian vault' './Network Maps'
    destination=$REPLY; mkdir -p -- "$destination" || { printf 'Could not create destination folder.\n'; return 1; }
    prompt_required 'Map title' 'Network Map'; title=$REPLY
    basename=${title//[^A-Za-z0-9._-]/-}; basename=${basename#-}; basename=${basename%-}; [[ -n $basename ]] || basename=Network-Map
    md="$destination/$basename.md"; canvas="$destination/$basename.canvas"
    if [[ -e $md || -e $canvas ]]; then prompt_yes_no 'Files already exist. Replace them?' n; [[ $REPLY == yes ]] || { printf 'Export cancelled.\n'; return; }; fi
    export_markdown "$md" "$title"; export_canvas "$canvas"
    printf '\nCreated Obsidian files:\n  %s\n  %s\n' "$md" "$canvas"
    printf 'Open the Markdown note for the Mermaid view or the Canvas file for a movable map.\n'
}

show_routes() {
    local i
    list_devices
    printf '\nROUTES / LINKS\n'
    if ((${#R_FROM[@]} == 0)); then printf 'No routes or links recorded.\n'; return; fi
    for ((i=0; i<${#R_FROM[@]}; i++)); do printf '%2s) %s -> %s | %s | destination=%s gateway=%s interface=%s\n' "$((i+1))" "${D_NAME[${R_FROM[i]}]}" "${D_NAME[${R_TO[i]}]}" "${R_LABEL[i]}" "${R_DEST[i]:--}" "${R_GATEWAY[i]:--}" "${R_INTERFACE[i]:--}"; done
}

usage() {
    cat <<HELP
$PROGRAM $VERSION — build Obsidian network maps

Interactive features:
  * Manual devices with management, internal, and external addresses
  * Local Linux interface and default-route discovery
  * Live or saved traceroute/tracepath hop import
  * Directed links with destination network, gateway, and interface
  * Obsidian Markdown/Mermaid and JSON Canvas export

Usage:
  $PROGRAM                         Ask which project to open or create
  $PROGRAM --project FILE          Open/create FILE and resume its map
  $PROGRAM --state-dir DIR         Store the recent-project list under DIR
  $PROGRAM --help                  Show this help

Every completed device, trace hop, and route is autosaved. Reopen the same
project file to continue without losing progress.
HELP
}

main_menu() {
    local choice initial_project=${1-}
    if [[ -n $initial_project ]]; then open_project "$initial_project" || return 2
    else project_start_screen || return 0; fi
    while :; do
        printf '\nOBSIDIAN NETWORK MAP — %s device(s), %s link(s)\nProject: %s\n' "${#D_NAME[@]}" "${#R_FROM[@]}" "$PROJECT_FILE"
        cat <<'MENU'
  1) Add a device manually
  2) Discover this Linux machine
  3) Run traceroute and import hops
  4) Import saved traceroute/tracepath output
  5) Add a route/link between devices
  6) Review devices and routes
  7) Export Markdown and Canvas to an Obsidian vault folder
  8) Clear the current map
  9) Save project now
  P) Open or create a different project
  Q) Save and close
MENU
        read -r -p 'Choose: ' choice || return 0
        case ${choice,,} in
            1) add_device || true ;; 2) discover_local || true ;; 3) trace_route || true ;; 4) import_trace_file || true ;; 5) add_route || true ;; 6) show_routes ;;
            7) export_map || true ;;
            8) prompt_yes_no 'Clear every device and route in memory?' n; if [[ $REPLY == yes ]]; then reset_map; autosave; fi ;;
            9) PROJECT_DIRTY=1; save_project ;;
            p) project_start_screen || true ;;
            q) PROJECT_DIRTY=1; save_project yes; return ;; *) printf 'Choose 1-9, P, or Q.\n' ;;
        esac
    done
}

project_arg=''
while (($#)); do
    case $1 in
        -h|--help) usage; exit 0 ;;
        --version) printf '%s %s\n' "$PROGRAM" "$VERSION"; exit 0 ;;
        -p|--project) (($# >= 2)) || { printf 'ERROR: --project requires a file.\n' >&2; exit 2; }; project_arg=$2; shift ;;
        --project=*) project_arg=${1#*=} ;;
        --state-dir) (($# >= 2)) || { printf 'ERROR: --state-dir requires a directory.\n' >&2; exit 2; }; STATE_DIR_OVERRIDE=$2; shift ;;
        --state-dir=*) STATE_DIR_OVERRIDE=${1#*=} ;;
        *) printf 'ERROR: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
main_menu "$project_arg"
