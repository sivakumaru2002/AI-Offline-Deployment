#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MODELS_PATH="/var/lib/ollama"

OLLAMA_MODELS_PATH="${OLLAMA_MODELS_PATH:-$DEFAULT_MODELS_PATH}"

if [[ "${1:-}" == "--help" ]]; then
	cat <<'EOF'
Offline Ollama models remover.

Usage:
  chmod +x ./remove_ollama_models_offline.sh
  sudo ./remove_ollama_models_offline.sh

Optional environment variables:
  OLLAMA_MODELS_PATH  Models directory to remove (default: /var/lib/ollama)
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
	printf '[ollama-models-remove] %s\n' "$*"
}

main() {
	if [[ -d "$OLLAMA_MODELS_PATH" ]]; then
		log "Removing $OLLAMA_MODELS_PATH"
		$SUDO rm -rf "$OLLAMA_MODELS_PATH"
	else
		log "Models path not present, skipping: $OLLAMA_MODELS_PATH"
	fi

	log "Ollama models removal completed"
}

main "$@"