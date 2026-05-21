#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"

OLLAMA_PACKAGE="${OLLAMA_PACKAGE:-}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_BIND_HOST="${OLLAMA_BIND_HOST:-127.0.0.1}"
OLLAMA_PUBLIC_HOST="${OLLAMA_PUBLIC_HOST:-127.0.0.1}"
OLLAMA_MODELS_PATH="${OLLAMA_MODELS_PATH:-/var/lib/ollama}"
OLLAMA_LOG_PATH="${OLLAMA_LOG_PATH:-/var/log/ollama/ollama.log}"
OLLAMA_ENV_FILE="${OLLAMA_ENV_FILE:-/etc/ollama.env}"
CONNECTION_FILE="${CONNECTION_FILE:-$SCRIPT_DIR/ollama-endpoint.txt}"

if [[ "${1:-}" == "--help" ]]; then
	cat <<'EOF'
Offline Ollama installer.

Place the Ollama offline artifacts in the same directory as this script, then run:
  chmod +x ./install_ollama_offline.sh
  sudo ./install_ollama_offline.sh

Supported offline inputs:
	- One or more local .tar.zst, .tgz, or .tar.gz Ollama archives in the script directory

Optional environment variables:
	OLLAMA_PACKAGE      Explicit path to a local package or archive
  OLLAMA_PORT         Ollama port (default: 11434)
	OLLAMA_BIND_HOST    Bind host (default: 127.0.0.1)
	OLLAMA_PUBLIC_HOST  Hostname/IP used in the emitted endpoint file (default: 127.0.0.1)
  OLLAMA_MODELS_PATH  Ollama models directory (default: /var/lib/ollama)
  OLLAMA_LOG_PATH     Ollama log file path (default: /var/log/ollama/ollama.log)
  OLLAMA_ENV_FILE     Environment file used by the systemd service
  CONNECTION_FILE     Output file for the endpoint URL
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
	printf '[ollama-offline] %s\n' "$*"
}

fail() {
	printf '[ollama-offline] ERROR: %s\n' "$*" >&2
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
			printf '%s' amd64
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
		*amd64*|*x86_64*|*x64*)
			printf '%s' amd64
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

pick_package() {
	local explicit="${OLLAMA_PACKAGE}"
	if [[ -n "$explicit" ]]; then
		[[ -f "$explicit" ]] || fail "OLLAMA_PACKAGE does not exist: $explicit"
		printf '%s' "$explicit"
		return
	fi

	local candidates=()
	local search_dirs=("$SCRIPT_DIR" "$SCRIPT_DIR/installation-src" "$SCRIPT_DIR/installtion-src")
	local search_dir

	for search_dir in "${search_dirs[@]}"; do
		[[ -d "$search_dir" ]] || continue

		while IFS= read -r file; do
			candidates+=("$file")
		done < <(find "$search_dir" -maxdepth 1 -type f \( -name '*.tar.zst' -o -name '*.tgz' -o -name '*.tar.gz' \) | sort)
	done

	[[ ${#candidates[@]} -gt 0 ]] || fail "No local Ollama archive found in $SCRIPT_DIR"
	printf '%s' "${candidates[0]}"
}

detect_ollama_user() {
	if id -u ollama >/dev/null 2>&1; then
		printf '%s' ollama
		return
	fi

	$SUDO useradd --system --home "$OLLAMA_MODELS_PATH" --shell /usr/sbin/nologin ollama >/dev/null 2>&1 || true
	printf '%s' ollama
}

install_from_archives() {
	local package_dir="$1"
	local host_arch
	local install_root="/opt/ollama-offline"
	local temp_dir
	local archives=()
	local archive
	local archive_name
	local installed_binary

	require_command tar
	host_arch="$(normalize_host_arch)"

	while IFS= read -r file; do
		archives+=("$file")
	done < <(find "$package_dir" -maxdepth 1 -type f \( -name '*.tar.zst' -o -name '*.tgz' -o -name '*.tar.gz' \) | sort)

	[[ ${#archives[@]} -gt 0 ]] || fail "No local Ollama archive found in $package_dir"

	temp_dir="$($SUDO mktemp -d /tmp/ollama-offline.XXXXXX)"

	log "Extracting local archives"
	$SUDO rm -rf "$install_root"
	$SUDO mkdir -p "$install_root"

	for archive in "${archives[@]}"; do
		archive_name="$(basename "$archive")"
		validate_archive_architecture "$archive_name" "$host_arch"
		$SUDO rm -rf "$temp_dir"/*

		case "$archive" in
			*.tar.zst)
				require_command zstd
				$SUDO tar --zstd -xf "$archive" -C "$temp_dir"
				;;
			*.tgz|*.tar.gz)
				$SUDO tar -xzf "$archive" -C "$temp_dir"
				;;
			*)
				fail "Unsupported Ollama archive type: $archive"
				;;
		esac

		$SUDO cp -R "$temp_dir"/. "$install_root"/
	done

	installed_binary="$($SUDO find "$install_root" -type f -name 'ollama' | head -n 1)"
	if [[ -z "$installed_binary" ]]; then
		$SUDO rm -rf "$temp_dir"
		fail "No archive containing the ollama binary was found in $package_dir. Add the base Ollama Linux archive; ROCm archives only provide GPU libraries."
	fi

	$SUDO chmod +x "$installed_binary"
	$SUDO ln -sf "$installed_binary" /usr/local/bin/ollama
	$SUDO rm -rf "$temp_dir"
}

ensure_systemd_service() {
	if [[ -f /etc/systemd/system/ollama.service ]] || [[ -f /usr/lib/systemd/system/ollama.service ]]; then
		return
	fi

	local ollama_user="$1"
	log "Creating ollama systemd service"
	$SUDO tee /etc/systemd/system/ollama.service >/dev/null <<EOF
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
User=$ollama_user
Group=$ollama_user
EnvironmentFile=$OLLAMA_ENV_FILE
ExecStart=$(command -v ollama) serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

write_env_file() {
	local ollama_user="$1"

	log "Writing $OLLAMA_ENV_FILE"
	$SUDO mkdir -p "$OLLAMA_MODELS_PATH" "$(dirname "$OLLAMA_LOG_PATH")"
	$SUDO chown -R "$ollama_user:$ollama_user" "$OLLAMA_MODELS_PATH" "$(dirname "$OLLAMA_LOG_PATH")"
	$SUDO tee "$OLLAMA_ENV_FILE" >/dev/null <<EOF
OLLAMA_HOST=$OLLAMA_BIND_HOST:$OLLAMA_PORT
OLLAMA_MODELS=$OLLAMA_MODELS_PATH
OLLAMA_DEBUG=0
EOF
}

service_action() {
	local action="$1"
	if command -v systemctl >/dev/null 2>&1; then
		$SUDO systemctl daemon-reload >/dev/null 2>&1 || true
		$SUDO systemctl "$action" ollama
		return
	fi

	require_command service
	$SUDO service ollama "$action"
}

reload_service_manager() {
	if command -v systemctl >/dev/null 2>&1; then
		$SUDO systemctl daemon-reload
	fi
}

enable_service() {
	if command -v systemctl >/dev/null 2>&1; then
		$SUDO systemctl enable ollama >/dev/null 2>&1 || true
	fi
}

wait_for_ollama() {
	local attempts=30

	while (( attempts > 0 )); do
		if OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT" ollama list >/dev/null 2>&1; then
			return
		fi
		attempts=$(( attempts - 1 ))
		sleep 2
	done

	fail "ollama did not become ready on port $OLLAMA_PORT"
}

emit_endpoint() {
	local endpoint

	endpoint="http://$OLLAMA_PUBLIC_HOST:$OLLAMA_PORT"
	printf '%s\n' "$endpoint" | tee "$CONNECTION_FILE"
	log "Endpoint saved to $CONNECTION_FILE"
}

main() {
	local package_path
	local package_dir
	package_path="$(pick_package)" || exit 1
	package_dir="$(dirname "$package_path")"

	install_from_archives "$package_dir"
	command -v ollama >/dev/null 2>&1 || fail "ollama binary was not found after installation"

	local ollama_user
	ollama_user="$(detect_ollama_user)"
	write_env_file "$ollama_user"
	ensure_systemd_service "$ollama_user"
	reload_service_manager
	enable_service
	service_action start
	wait_for_ollama
	emit_endpoint
}

main "$@"
