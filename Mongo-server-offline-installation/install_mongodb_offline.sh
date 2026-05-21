#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"

MONGO_PACKAGE="${MONGO_PACKAGE:-}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_BIND_IP="${MONGO_BIND_IP:-0.0.0.0}"
MONGO_ADMIN_USER="${MONGO_ADMIN_USER:-mongoAdmin}"
MONGO_ADMIN_PASSWORD="${MONGO_ADMIN_PASSWORD:-ChangeMe123!}"
MONGO_PUBLIC_HOST="${MONGO_PUBLIC_HOST:-$DEFAULT_HOSTNAME}"
MONGO_DB_PATH="${MONGO_DB_PATH:-/var/lib/mongo}"
MONGO_LOG_PATH="${MONGO_LOG_PATH:-/var/log/mongodb/mongod.log}"
CONNECTION_FILE="${CONNECTION_FILE:-$SCRIPT_DIR/mongo-connection-string.txt}"

if [[ "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Offline MongoDB installer.

Place the MongoDB offline artifacts in the same directory as this script, then run:
  chmod +x ./install_mongodb_offline.sh
  sudo MONGO_ADMIN_USER=appuser MONGO_ADMIN_PASSWORD='StrongPassword!' ./install_mongodb_offline.sh

Supported offline inputs:
  - One or more .deb packages in the script directory
  - One or more .rpm packages in the script directory
    - One or more local .tgz or .tar.gz MongoDB archives in the script directory

Optional environment variables:
  MONGO_PACKAGE      Explicit path to a local package or archive
  MONGO_PORT         MongoDB port (default: 27017)
  MONGO_BIND_IP      Bind IPs for mongod (default: 0.0.0.0)
  MONGO_PUBLIC_HOST  Hostname/IP used in the emitted connection string
  MONGO_ADMIN_USER   Admin username (default: mongoAdmin)
  MONGO_ADMIN_PASSWORD
                     Admin password (default: ChangeMe123!)
  MONGO_DB_PATH      Data directory (default: /var/lib/mongo)
  CONNECTION_FILE    Output file for the connection string
EOF
    exit 0
fi

if [[ "$EUID" -eq 0 ]]; then
    SUDO=""
else
    if ! command -v sudo >/dev/null 2>&1; then
        echo "This script must run as root or with sudo available." >&2
        exit 1
    fi
    SUDO="sudo"
fi

log() {
    printf '[mongo-offline] %s\n' "$*"
}

fail() {
    printf '[mongo-offline] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

normalize_host_arch() {
    local host_arch

    host_arch="$(uname -m)"
    case "$host_arch" in
        x86_64|amd64)
            printf '%s' x86_64
            ;;
        aarch64|arm64)
            printf '%s' arm64
            ;;
        *)
            printf '%s' "$host_arch"
            ;;
    esac
}

detect_archive_arch() {
    local archive_name="$1"

    case "$archive_name" in
        *x86_64*|*amd64*|*x64*)
            printf '%s' x86_64
            ;;
        *arm64*|*aarch64*)
            printf '%s' arm64
            ;;
        *)
            printf '%s' unknown
            ;;
    esac
}

validate_archive_architecture() {
    local archive_name="$1"
    local host_arch="$2"
    local archive_arch

    archive_arch="$(detect_archive_arch "$archive_name")"
    if [[ "$archive_arch" == "unknown" ]]; then
        log "Skipping architecture validation for $archive_name"
        return
    fi

    [[ "$archive_arch" == "$host_arch" ]] || fail "Archive $archive_name targets $archive_arch but host is $host_arch"
}

url_encode() {
    local input="$1"
    local output=""
    local char
    local index

    for (( index=0; index<${#input}; index++ )); do
        char="${input:index:1}"
        case "$char" in
            [a-zA-Z0-9.~_-]) output+="$char" ;;
            *) printf -v output '%s%%%02X' "$output" "'${char}" ;;
        esac
    done

    printf '%s' "$output"
}

js_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

pick_package() {
    local explicit="${MONGO_PACKAGE}"
    if [[ -n "$explicit" ]]; then
        [[ -f "$explicit" ]] || fail "MONGO_PACKAGE does not exist: $explicit"
        printf '%s' "$explicit"
        return
    fi

    local candidates=()
    local search_dirs=("$SCRIPT_DIR" "$SCRIPT_DIR/installation-src")
    local search_dir

    for search_dir in "${search_dirs[@]}"; do
        [[ -d "$search_dir" ]] || continue

        while IFS= read -r file; do
            candidates+=("$file")
        done < <(find "$search_dir" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' -o -name '*.tgz' -o -name '*.tar.gz' \) | sort)
    done

    [[ ${#candidates[@]} -gt 0 ]] || fail "No local MongoDB package or archive found in $SCRIPT_DIR"
    printf '%s' "${candidates[0]}"
}

detect_mongo_user() {
    if id -u mongodb >/dev/null 2>&1; then
        printf '%s' mongodb
        return
    fi
    if id -u mongod >/dev/null 2>&1; then
        printf '%s' mongod
        return
    fi

    $SUDO useradd --system --home "$MONGO_DB_PATH" --shell /usr/sbin/nologin mongodb >/dev/null 2>&1 || true
    printf '%s' mongodb
}

install_from_debs() {
    require_command dpkg
    local package_dir="$1"
    local debs=()

    while IFS= read -r file; do
        debs+=("$file")
    done < <(find "$package_dir" -maxdepth 1 -type f -name '*.deb' | sort)

    [[ ${#debs[@]} -gt 0 ]] || fail "No .deb files found in $package_dir"
    log "Installing local .deb packages"
    $SUDO dpkg -i "${debs[@]}"
}

install_from_rpms() {
    local package_dir="$1"
    local rpms=()

    while IFS= read -r file; do
        rpms+=("$file")
    done < <(find "$package_dir" -maxdepth 1 -type f -name '*.rpm' | sort)

    [[ ${#rpms[@]} -gt 0 ]] || fail "No .rpm files found in $package_dir"
    log "Installing local .rpm packages"

    if command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y --disablerepo='*' "${rpms[@]}"
        return
    fi
    if command -v yum >/dev/null 2>&1; then
        $SUDO yum localinstall -y --disablerepo='*' "${rpms[@]}"
        return
    fi
    if command -v zypper >/dev/null 2>&1; then
        $SUDO zypper --non-interactive install --allow-unsigned-rpm "${rpms[@]}"
        return
    fi

    require_command rpm
    $SUDO rpm -ivh --nosignature --replacepkgs "${rpms[@]}"
}

install_from_archives() {
    local package_dir="$1"
    require_command tar

    local install_root="/opt/mongodb-offline"
    local temp_dir
    local archives=()
    local archive
    local extracted_dir
    local host_arch

    while IFS= read -r file; do
        archives+=("$file")
    done < <(find "$package_dir" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.tar.gz' \) | sort)

    [[ ${#archives[@]} -gt 0 ]] || fail "No .tgz or .tar.gz archives found in $package_dir"

    host_arch="$(normalize_host_arch)"

    temp_dir="$($SUDO mktemp -d /tmp/mongodb-offline.XXXXXX)"

    log "Extracting local archives"
    $SUDO rm -rf "$install_root"
    $SUDO mkdir -p "$install_root"

    for archive in "${archives[@]}"; do
        validate_archive_architecture "$(basename "$archive")" "$host_arch"
        $SUDO rm -rf "$temp_dir"/*
        $SUDO tar -xzf "$archive" -C "$temp_dir"
        extracted_dir="$($SUDO find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
        [[ -n "$extracted_dir" ]] || fail "Unable to determine extracted MongoDB directory from $archive"
        $SUDO cp -R "$extracted_dir"/. "$install_root"/
    done

    $SUDO ln -sf "$install_root/bin/mongod" /usr/local/bin/mongod
    if [[ -x "$install_root/bin/mongosh" ]]; then
        $SUDO ln -sf "$install_root/bin/mongosh" /usr/local/bin/mongosh
    fi
    if [[ -x "$install_root/bin/mongo" ]]; then
        $SUDO ln -sf "$install_root/bin/mongo" /usr/local/bin/mongo
    fi
    $SUDO rm -rf "$temp_dir"
}

ensure_systemd_service() {
    if [[ -f /etc/systemd/system/mongod.service ]] || [[ -f /usr/lib/systemd/system/mongod.service ]]; then
        return
    fi

    local mongo_user="$1"
    log "Creating mongod systemd service"
    $SUDO tee /etc/systemd/system/mongod.service >/dev/null <<EOF
[Unit]
Description=MongoDB Database Server
After=network.target

[Service]
User=$mongo_user
Group=$mongo_user
ExecStart=$(command -v mongod) --config /etc/mongod.conf
PIDFile=/tmp/mongod.pid
LimitNOFILE=64000
TimeoutStartSec=30
TimeoutStopSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}

write_config() {
    local mongo_user="$1"
    local authorization_state="$2"

    log "Writing /etc/mongod.conf"
    $SUDO mkdir -p "$MONGO_DB_PATH" "$(dirname "$MONGO_LOG_PATH")"
    $SUDO chown -R "$mongo_user:$mongo_user" "$MONGO_DB_PATH" "$(dirname "$MONGO_LOG_PATH")"
    $SUDO tee /etc/mongod.conf >/dev/null <<EOF
storage:
  dbPath: $MONGO_DB_PATH
systemLog:
  destination: file
  path: $MONGO_LOG_PATH
  logAppend: true
net:
  bindIp: $MONGO_BIND_IP
  port: $MONGO_PORT
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
security:
  authorization: $authorization_state
EOF
}

service_action() {
    local action="$1"
    if command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
        $SUDO systemctl "$action" mongod
        return
    fi

    require_command service
    $SUDO service mongod "$action"
}

reload_service_manager() {
    if command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl daemon-reload
    fi
}

enable_service() {
    if command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl enable mongod >/dev/null 2>&1 || true
    fi
}

detect_shell_binary() {
    if command -v mongosh >/dev/null 2>&1; then
        printf '%s' mongosh
        return
    fi
    if command -v mongo >/dev/null 2>&1; then
        printf '%s' mongo
        return
    fi
    fail "Mongo shell not found. Include offline mongosh or mongo package alongside the server artifacts."
}

wait_for_mongo() {
    local mongo_shell="$1"
    local attempts=30

    while (( attempts > 0 )); do
        if "$mongo_shell" --quiet --host 127.0.0.1 --port "$MONGO_PORT" --eval 'db.runCommand({ ping: 1 }).ok' >/dev/null 2>&1; then
            return
        fi
        attempts=$(( attempts - 1 ))
        sleep 2
    done

    fail "mongod did not become ready on port $MONGO_PORT"
}

create_or_update_admin_user() {
    local mongo_shell="$1"
    local escaped_user
    local escaped_password

    escaped_user="$(js_escape "$MONGO_ADMIN_USER")"
    escaped_password="$(js_escape "$MONGO_ADMIN_PASSWORD")"

    "$mongo_shell" --quiet --host 127.0.0.1 --port "$MONGO_PORT" admin <<EOF
var adminDb = db.getSiblingDB("admin");
var existingUser = adminDb.getUser("$escaped_user");
if (existingUser) {
  adminDb.updateUser("$escaped_user", { pwd: "$escaped_password", roles: [{ role: "root", db: "admin" }] });
  print("UPDATED_ADMIN_USER");
} else {
  adminDb.createUser({ user: "$escaped_user", pwd: "$escaped_password", roles: [{ role: "root", db: "admin" }] });
  print("CREATED_ADMIN_USER");
}
EOF
}

emit_connection_string() {
    local encoded_user
    local encoded_password

    encoded_user="$(url_encode "$MONGO_ADMIN_USER")"
    encoded_password="$(url_encode "$MONGO_ADMIN_PASSWORD")"

    local connection_string
    connection_string="mongodb://$encoded_user:$encoded_password@$MONGO_PUBLIC_HOST:$MONGO_PORT/admin?authSource=admin"

    printf '%s\n' "$connection_string" | tee "$CONNECTION_FILE"
    log "Connection string saved to $CONNECTION_FILE"
}

main() {
    local package_path
        package_path="$(pick_package)" || exit 1
    local package_dir
    package_dir="$(dirname "$package_path")"

    case "$package_path" in
        *.deb)
            install_from_debs "$package_dir"
            ;;
        *.rpm)
            install_from_rpms "$package_dir"
            ;;
        *.tgz|*.tar.gz)
            install_from_archives "$package_dir"
            ;;
        *)
            fail "Unsupported offline package type: $package_path"
            ;;
    esac

    command -v mongod >/dev/null 2>&1 || fail "mongod binary was not found after installation"

    local mongo_user
    mongo_user="$(detect_mongo_user)"
    write_config "$mongo_user" disabled
    ensure_systemd_service "$mongo_user"
    reload_service_manager
    enable_service
    service_action start

    local mongo_shell
    mongo_shell="$(detect_shell_binary)"
    wait_for_mongo "$mongo_shell"
    create_or_update_admin_user "$mongo_shell"

    write_config "$mongo_user" enabled
    service_action restart
    wait_for_mongo "$mongo_shell"
    emit_connection_string
}

main "$@"