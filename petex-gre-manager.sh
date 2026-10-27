#!/usr/bin/env bash
set -Eeuo pipefail

# Netpars GRE Tunnel Manager
# - Creates one GRE tunnel from a predefined list of 10 inner-IP pairs.
# - Supports manual testing by the user.
# - Can persist the CURRENT live tunnel with a systemd unit.
# - Can remove only the live tunnel, or completely remove live + persistence.
#
# Ubuntu/Debian: requires iproute2 and systemd.

SCRIPT_NAME="Netpars GRE Tunnel Manager"
BASE_SYSTEMD_DIR="/etc/systemd/system"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log()   { printf '%b%s%b\n' "$CYAN" "$*" "$RESET"; }
ok()    { printf '%b%s%b\n' "$GREEN" "$*" "$RESET"; }
warn()  { printf '%b%s%b\n' "$YELLOW" "$*" "$RESET"; }
error() { printf '%b%s%b\n' "$RED" "$*" "$RESET" >&2; }

fail() {
    error "ERROR: $*"
    exit 1
}

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run this script as root (for example: sudo bash $0)."
}

require_commands() {
    command -v ip >/dev/null 2>&1 || fail "The 'ip' command is not installed. Install iproute2 first."
    command -v systemctl >/dev/null 2>&1 || fail "systemd/systemctl is required for permanent tunnels."
}

valid_ipv4() {
    local ip=$1
    local IFS='.'
    local -a octets
    read -r -a octets <<< "$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1

    local octet
    for octet in "${octets[@]}"; do
        [[ $octet =~ ^[0-9]+$ ]] || return 1
        ((10#$octet >= 0 && 10#$octet <= 255)) || return 1
    done
}

valid_tunnel_name() {
    # Linux interface names are limited to 15 characters.
    [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]]
}

unit_name_for() {
    local tunnel=$1
    printf 'netpars-gre-%s.service' "$tunnel"
}

unit_path_for() {
    local tunnel=$1
    printf '%s/%s' "$BASE_SYSTEMD_DIR" "$(unit_name_for "$tunnel")"
}

interface_exists() {
    ip link show dev "$1" >/dev/null 2>&1
}

get_live_remote_ip() {
    local tunnel=$1
    ip tunnel show dev "$tunnel" 2>/dev/null \
        | awk '{for (i=1; i<=NF; i++) if ($i == "remote" && (i+1) <= NF) {print $(i+1); exit}}'
}

get_live_local_ip() {
    local tunnel=$1
    ip -4 -o addr show dev "$tunnel" 2>/dev/null \
        | awk 'NR==1 {split($4,a,"/"); print a[1]}'
}

get_live_peer_ip() {
    local tunnel=$1
    ip -4 route show dev "$tunnel" scope link 2>/dev/null \
        | awk '$1 ~ /^[0-9]+([.][0-9]+){3}(\/[0-9]+)?$/ {split($1,a,"/"); print a[1]; exit}'
}

confirm() {
    local prompt=$1
    local answer
    read -r -p "$prompt [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

show_menu() {
    cat <<'MENU'

Select operation:

 1)  10.20.20.1  <->  10.20.20.2
 2)  10.21.20.1  <->  10.21.20.2
 3)  10.22.20.1  <->  10.22.20.2
 4)  10.23.20.1  <->  10.23.20.2
 5)  10.24.20.1  <->  10.24.20.2
 6)  10.25.20.1  <->  10.25.20.2
 7)  10.26.20.1  <->  10.26.20.2
 8)  10.27.20.1  <->  10.27.20.2
 9)  10.28.20.1  <->  10.28.20.2
10)  10.29.20.1  <->  10.29.20.2

11) Delete current tunnel only
12) Make the current live tunnel permanent
13) Completely remove tunnel + permanent configuration

q)  Quit
MENU
}

prompt_base_info() {
    while true; do
        read -r -p "Remote server PUBLIC IPv4: " REMOTE_PUBLIC_IP
        if valid_ipv4 "$REMOTE_PUBLIC_IP"; then
            break
        fi
        error "Invalid IPv4 address."
    done

    while true; do
        read -r -p "Tunnel name (max 15 chars, e.g. ge4): " TUNNEL_NAME
        if valid_tunnel_name "$TUNNEL_NAME"; then
            break
        fi
        error "Invalid tunnel name. Use only letters, numbers, '-' or '_', max 15 chars, and do not start with '-' or '_'."
    done

    while true; do
        read -r -p $'This server:\n  1) Iran (.1 local / .2 remote)\n  2) Europe (.2 local / .1 remote)\nSelect [1-2]: ' SERVER_SIDE
        case "$SERVER_SIDE" in
            1|2) break ;;
            *) error "Please select 1 or 2." ;;
        esac
    done
}

create_tunnel() {
    local choice=$1
    local third=$((19 + choice))
    local local_ip remote_inner_ip

    if [[ $SERVER_SIDE == 1 ]]; then
        local_ip="10.${third}.20.1"
        remote_inner_ip="10.${third}.20.2"
    else
        local_ip="10.${third}.20.2"
        remote_inner_ip="10.${third}.20.1"
    fi

    if interface_exists "$TUNNEL_NAME"; then
        fail "Tunnel '$TUNNEL_NAME' already exists. Use option 11 first, or choose another tunnel name."
    fi

    log "Creating tunnel '$TUNNEL_NAME'..."
    log "Outer remote IP : $REMOTE_PUBLIC_IP"
    log "Local inner IP  : $local_ip/32"
    log "Remote inner IP : $remote_inner_ip/32"

    ip tunnel add "$TUNNEL_NAME" mode gre remote "$REMOTE_PUBLIC_IP"
    ip link set dev "$TUNNEL_NAME" up
    ip addr add "${local_ip}/32" dev "$TUNNEL_NAME"
    ip route add "${remote_inner_ip}/32" dev "$TUNNEL_NAME" scope link

    ok "Tunnel '$TUNNEL_NAME' created."
    printf '\n'
    printf 'Run the same script on the remote server with the matching option, then test:\n'
    printf '  ping -c 10 %s\n' "$remote_inner_ip"
    printf '\n'
    printf 'Current configuration:\n'
    printf '  Tunnel name : %s\n' "$TUNNEL_NAME"
    printf '  Remote IP   : %s\n' "$REMOTE_PUBLIC_IP"
    printf '  Local IP    : %s/32\n' "$local_ip"
    printf '  Remote inner: %s/32\n' "$remote_inner_ip"
}

delete_live_tunnel() {
    if ! interface_exists "$TUNNEL_NAME"; then
        warn "Tunnel '$TUNNEL_NAME' is not currently active."
        return 0
    fi

    local unit
    unit=$(unit_name_for "$TUNNEL_NAME")

    # Stop a managed service, but intentionally DO NOT disable/remove it.
    # This is the 'delete current tunnel only' action.
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        systemctl stop "$unit" || true
    fi

    ip link set dev "$TUNNEL_NAME" down 2>/dev/null || true
    ip link del dev "$TUNNEL_NAME"
    ok "Live tunnel '$TUNNEL_NAME' deleted."
    warn "Any existing permanent systemd configuration was left untouched."
}

make_current_permanent() {
    local unit unit_path remote_inner local_inner remote_outer
    unit=$(unit_name_for "$TUNNEL_NAME")
    unit_path=$(unit_path_for "$TUNNEL_NAME")

    if ! interface_exists "$TUNNEL_NAME"; then
        fail "Tunnel '$TUNNEL_NAME' is not active. Create it first, then run option 12."
    fi

    remote_outer=$(get_live_remote_ip "$TUNNEL_NAME")
    local_inner=$(get_live_local_ip "$TUNNEL_NAME")
    remote_inner=$(get_live_peer_ip "$TUNNEL_NAME")

    [[ -n $remote_outer ]] || fail "Could not detect the GRE outer remote IP from the live tunnel."
    [[ -n $local_inner ]] || fail "Could not detect the tunnel local inner IP."
    [[ -n $remote_inner ]] || fail "Could not detect the tunnel remote inner IP/route."

    valid_ipv4 "$remote_outer" || fail "Detected outer remote IP '$remote_outer' is invalid."
    valid_ipv4 "$local_inner" || fail "Detected local inner IP '$local_inner' is invalid."
    valid_ipv4 "$remote_inner" || fail "Detected remote inner IP '$remote_inner' is invalid."

    if [[ -e $unit_path ]] && ! confirm "A permanent configuration for '$TUNNEL_NAME' already exists. Replace it"; then
        warn "Nothing changed."
        return 0
    fi

    cat > "$unit_path" <<EOF_UNIT
[Unit]
Description=Netpars GRE tunnel $TUNNEL_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/ip link del dev $TUNNEL_NAME
ExecStart=/sbin/ip tunnel add $TUNNEL_NAME mode gre remote $remote_outer
ExecStart=/sbin/ip link set dev $TUNNEL_NAME up
ExecStart=/sbin/ip addr add ${local_inner}/32 dev $TUNNEL_NAME
ExecStart=/sbin/ip route add ${remote_inner}/32 dev $TUNNEL_NAME scope link
ExecStop=-/sbin/ip link set dev $TUNNEL_NAME down
ExecStop=-/sbin/ip link del dev $TUNNEL_NAME

[Install]
WantedBy=multi-user.target
EOF_UNIT

    chmod 0644 "$unit_path"
    systemctl daemon-reload
    systemctl enable "$unit" >/dev/null

    ok "Permanent configuration enabled for '$TUNNEL_NAME'."
    printf '\n'
    printf 'Saved service : %s\n' "$unit_path"
    printf 'Outer remote  : %s\n' "$remote_outer"
    printf 'Local inner   : %s/32\n' "$local_inner"
    printf 'Remote inner  : %s/32\n' "$remote_inner"
    printf '\n'
    printf 'The CURRENT tunnel was left running. On reboot systemd will recreate it.\n'
}

remove_completely() {
    local unit unit_path
    unit=$(unit_name_for "$TUNNEL_NAME")
    unit_path=$(unit_path_for "$TUNNEL_NAME")

    if ! confirm "Completely remove '$TUNNEL_NAME' including any permanent systemd configuration"; then
        warn "Cancelled."
        return 0
    fi

    # Stop any managed instance.
    systemctl disable --now "$unit" >/dev/null 2>&1 || true

    # Also remove a manually-created live tunnel if it exists.
    if interface_exists "$TUNNEL_NAME"; then
        ip link set dev "$TUNNEL_NAME" down 2>/dev/null || true
        ip link del dev "$TUNNEL_NAME" 2>/dev/null || true
    fi

    rm -f "$unit_path"
    systemctl daemon-reload
    systemctl reset-failed "$unit" >/dev/null 2>&1 || true

    ok "Tunnel '$TUNNEL_NAME' and its permanent configuration were completely removed."
}

main() {
    require_root
    require_commands

    clear || true
    printf '%b%s%b\n' "$CYAN" "$SCRIPT_NAME" "$RESET"
    printf '%s\n\n' '========================================'

    prompt_base_info
    show_menu

    local choice
    read -r -p "Select: " choice

    case "$choice" in
        1|2|3|4|5|6|7|8|9|10)
            create_tunnel "$choice"
            ;;
        11)
            delete_live_tunnel
            ;;
        12)
            make_current_permanent
            ;;
        13)
            remove_completely
            ;;
        q|Q)
            exit 0
            ;;
        *)
            fail "Invalid option."
            ;;
    esac
}

main "$@"
