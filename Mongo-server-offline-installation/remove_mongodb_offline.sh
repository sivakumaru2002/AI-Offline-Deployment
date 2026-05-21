#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DB_PATH="/var/lib/mongo"
DEFAULT_LOG_PATH="/var/log/mongodb/mongod.log"

MONGO_DB_PATH="${MONGO_DB_PATH:-$DEFAULT_DB_PATH}"
MONGO_LOG_PATH="${MONGO_LOG_PATH:-$DEFAULT_LOG_PATH}"
CONNECTION_FILE="${CONNECTION_FILE:-$SCRIPT_DIR/mongo-connection-string.txt}"
REMOVE_DATA="${REMOVE_DATA:-false}"
REMOVE_LOGS="${REMOVE_LOGS:-true}"

if [[ "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Offline MongoDB remover.

Usage:
  chmod +x ./remove_mongodb_offline.sh
  sudo ./remove_mongodb_offline.sh

Optional environment variables:
    MONGO_DB_PATH    Data directory to remove when REMOVE_DATA=true
  MONGO_LOG_PATH   Log file path to remove (default: /var/log/mongodb/mongod.log)
  CONNECTION_FILE  Connection string file to remove
    REMOVE_DATA      Remove MongoDB data directory (default: false)
  REMOVE_LOGS      Remove MongoDB logs directory (default: true)
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
    printf '[mongo-remove] %s\n' "$*"
}

service_exists() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-unit-files mongod.service >/dev/null 2>&1
        return $?
    fi

    [[ -f /etc/init.d/mongod ]]
}

stop_and_disable_service() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files mongod.service >/dev/null 2>&1; then
            log "Stopping mongod service"
            $SUDO systemctl stop mongod >/dev/null 2>&1 || true
            $SUDO systemctl disable mongod >/dev/null 2>&1 || true
        fi
        return
    fi

    if command -v service >/dev/null 2>&1 && [[ -f /etc/init.d/mongod ]]; then
        log "Stopping mongod service"
        $SUDO service mongod stop >/dev/null 2>&1 || true
    fi
}

remove_service_files() {
    local service_files=(
        /etc/systemd/system/mongod.service
        /usr/lib/systemd/system/mongod.service
        /lib/systemd/system/mongod.service
        /etc/init.d/mongod
    )
    local service_file

    for service_file in "${service_files[@]}"; do
        if [[ -e "$service_file" ]]; then
            log "Removing $service_file"
            $SUDO rm -f "$service_file"
        fi
    done

    if command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

collect_owned_packages() {
    local binary_path="$1"
    local package_name

    if [[ -z "$binary_path" || ! -e "$binary_path" ]]; then
        return
    fi

    if command -v dpkg-query >/dev/null 2>&1; then
        package_name="$(dpkg-query -S "$binary_path" 2>/dev/null | head -n 1 | cut -d: -f1)"
        if [[ -n "$package_name" ]]; then
            printf '%s\n' "$package_name"
        fi
    fi

    if command -v rpm >/dev/null 2>&1; then
        package_name="$(rpm -qf "$binary_path" 2>/dev/null)"
        if [[ -n "$package_name" && "$package_name" != *"is not owned by any package"* ]]; then
            printf '%s\n' "$package_name"
        fi
    fi
}

remove_owned_packages() {
    local mongod_path=""
    local mongosh_path=""
    local mongo_path=""
    local packages=()
    local package_name

    mongod_path="$(command -v mongod 2>/dev/null || true)"
    mongosh_path="$(command -v mongosh 2>/dev/null || true)"
    mongo_path="$(command -v mongo 2>/dev/null || true)"

    while IFS= read -r package_name; do
        [[ -n "$package_name" ]] && packages+=("$package_name")
    done < <(
        {
            collect_owned_packages "$mongod_path"
            collect_owned_packages "$mongosh_path"
            collect_owned_packages "$mongo_path"
        } | sort -u
    )

    [[ ${#packages[@]} -gt 0 ]] || return

    if command -v dpkg >/dev/null 2>&1; then
        log "Removing MongoDB Debian packages"
        $SUDO dpkg -r "${packages[@]}" >/dev/null 2>&1 || true
    fi

    if command -v rpm >/dev/null 2>&1; then
        log "Removing MongoDB RPM packages"
        $SUDO rpm -e "${packages[@]}" >/dev/null 2>&1 || true
    fi
}

remove_archive_install() {
    local install_root="/opt/mongodb-offline"
    local symlink

    if [[ -d "$install_root" ]]; then
        log "Removing $install_root"
        $SUDO rm -rf "$install_root"
    fi

    for symlink in /usr/local/bin/mongod /usr/local/bin/mongosh /usr/local/bin/mongo; do
        if [[ -L "$symlink" || -f "$symlink" ]]; then
            log "Removing $symlink"
            $SUDO rm -f "$symlink"
        fi
    done
}

remove_runtime_artifacts() {
    if [[ -f /etc/mongod.conf ]]; then
        log "Removing /etc/mongod.conf"
        $SUDO rm -f /etc/mongod.conf
    fi

    if [[ -f "$CONNECTION_FILE" ]]; then
        log "Removing $CONNECTION_FILE"
        rm -f "$CONNECTION_FILE"
    fi

    if [[ "$REMOVE_LOGS" == "true" ]]; then
        if [[ -f "$MONGO_LOG_PATH" ]]; then
            log "Removing $MONGO_LOG_PATH"
            $SUDO rm -f "$MONGO_LOG_PATH"
        fi

        if [[ -d "$(dirname "$MONGO_LOG_PATH")" ]]; then
            log "Removing $(dirname "$MONGO_LOG_PATH")"
            $SUDO rm -rf "$(dirname "$MONGO_LOG_PATH")"
        fi
    fi

    if [[ "$REMOVE_DATA" == "true" && -d "$MONGO_DB_PATH" ]]; then
        log "Removing $MONGO_DB_PATH"
        $SUDO rm -rf "$MONGO_DB_PATH"
    elif [[ -d "$MONGO_DB_PATH" ]]; then
        log "Preserving $MONGO_DB_PATH (set REMOVE_DATA=true to delete it)"
    fi
}

main() {
    if service_exists; then
        stop_and_disable_service
    fi

    remove_owned_packages
    remove_archive_install
    remove_service_files
    remove_runtime_artifacts
    log "MongoDB removal completed"
}

main "$@"