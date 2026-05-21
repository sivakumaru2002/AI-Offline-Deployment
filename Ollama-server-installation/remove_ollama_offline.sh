#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MODELS_PATH="/var/lib/ollama"
DEFAULT_LOG_PATH="/var/log/ollama/ollama.log"

OLLAMA_MODELS_PATH="${OLLAMA_MODELS_PATH:-$DEFAULT_MODELS_PATH}"
OLLAMA_LOG_PATH="${OLLAMA_LOG_PATH:-$DEFAULT_LOG_PATH}"
OLLAMA_ENV_FILE="${OLLAMA_ENV_FILE:-/etc/ollama.env}"
CONNECTION_FILE="${CONNECTION_FILE:-$SCRIPT_DIR/ollama-endpoint.txt}"
REMOVE_MODELS="${REMOVE_MODELS:-false}"
REMOVE_LOGS="${REMOVE_LOGS:-true}"

if [[ "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Offline Ollama remover.

Usage:
  chmod +x ./remove_ollama_offline.sh
  sudo ./remove_ollama_offline.sh

Optional environment variables:
  OLLAMA_MODELS_PATH  Models directory to remove when REMOVE_MODELS=true
  OLLAMA_LOG_PATH     Log file path to remove (default: /var/log/ollama/ollama.log)
  OLLAMA_ENV_FILE     Environment file to remove (default: /etc/ollama.env)
  CONNECTION_FILE     Endpoint file to remove
  REMOVE_MODELS       Remove Ollama model files (default: false)
  REMOVE_LOGS         Remove Ollama logs directory (default: true)
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
    printf '[ollama-remove] %s\n' "$*"
}

stop_and_disable_service() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
            log "Stopping ollama service"
            $SUDO systemctl stop ollama >/dev/null 2>&1 || true
            $SUDO systemctl disable ollama >/dev/null 2>&1 || true
        fi
        return
    fi

    if command -v service >/dev/null 2>&1 && [[ -f /etc/init.d/ollama ]]; then
        log "Stopping ollama service"
        $SUDO service ollama stop >/dev/null 2>&1 || true
    fi
}

remove_service_files() {
    local service_files=(
        /etc/systemd/system/ollama.service
        /usr/lib/systemd/system/ollama.service
        /lib/systemd/system/ollama.service
        /etc/init.d/ollama
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

remove_archive_install() {
    local install_root="/opt/ollama-offline"

    if [[ -d "$install_root" ]]; then
        log "Removing $install_root"
        $SUDO rm -rf "$install_root"
    fi

    if [[ -L /usr/local/bin/ollama || -f /usr/local/bin/ollama ]]; then
        log "Removing /usr/local/bin/ollama"
        $SUDO rm -f /usr/local/bin/ollama
    fi
}

remove_runtime_artifacts() {
    if [[ -f "$OLLAMA_ENV_FILE" ]]; then
        log "Removing $OLLAMA_ENV_FILE"
        $SUDO rm -f "$OLLAMA_ENV_FILE"
    fi

    if [[ -f "$CONNECTION_FILE" ]]; then
        log "Removing $CONNECTION_FILE"
        rm -f "$CONNECTION_FILE"
    fi

    if [[ "$REMOVE_LOGS" == "true" ]]; then
        if [[ -f "$OLLAMA_LOG_PATH" ]]; then
            log "Removing $OLLAMA_LOG_PATH"
            $SUDO rm -f "$OLLAMA_LOG_PATH"
        fi

        if [[ -d "$(dirname "$OLLAMA_LOG_PATH")" ]]; then
            log "Removing $(dirname "$OLLAMA_LOG_PATH")"
            $SUDO rm -rf "$(dirname "$OLLAMA_LOG_PATH")"
        fi
    fi

    if [[ "$REMOVE_MODELS" == "true" && -d "$OLLAMA_MODELS_PATH" ]]; then
        log "Removing $OLLAMA_MODELS_PATH"
        $SUDO rm -rf "$OLLAMA_MODELS_PATH"
    elif [[ -d "$OLLAMA_MODELS_PATH" ]]; then
        log "Preserving $OLLAMA_MODELS_PATH (set REMOVE_MODELS=true to delete it)"
    fi
}

main() {
    stop_and_disable_service
    remove_archive_install
    remove_service_files
    remove_runtime_artifacts
    log "Ollama removal completed"
}

main "$@"