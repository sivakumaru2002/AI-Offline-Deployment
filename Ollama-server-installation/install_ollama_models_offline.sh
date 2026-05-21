#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLLAMA_MODELS_PATH="${OLLAMA_MODELS_PATH:-/var/lib/ollama}"
OLLAMA_MODEL_BUNDLE="${OLLAMA_MODEL_BUNDLE:-}"

if [[ "${1:-}" == "--help" ]]; then
	cat <<'EOF'
Offline Ollama model installer.

Place a copied Ollama model store alongside this script, then run:
  chmod +x ./install_ollama_models_offline.sh
  sudo ./install_ollama_models_offline.sh

Supported offline inputs:
	- A directory containing models/blobs and models/manifests
	- A parent directory containing a models/ directory

Optional environment variables:
	OLLAMA_MODEL_BUNDLE  Explicit path to the copied model bundle or models directory
	OLLAMA_MODELS_PATH   Ollama data directory on the target host (default: /var/lib/ollama)
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
	printf '[ollama-models-offline] %s\n' "$*"
}

fail() {
	printf '[ollama-models-offline] ERROR: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

service_action() {
	local action="$1"

	if command -v systemctl >/dev/null 2>&1; then
		$SUDO systemctl daemon-reload >/dev/null 2>&1 || true
		$SUDO systemctl "$action" ollama
		return
	fi

	if command -v service >/dev/null 2>&1; then
		$SUDO service ollama "$action"
		return
	fi

	fail "Could not manage the Ollama service; neither systemctl nor service is available"
}

wait_for_ollama() {
	local attempts=30

	while (( attempts > 0 )); do
		if OLLAMA_HOST="127.0.0.1:11434" ollama list >/dev/null 2>&1; then
			return
		fi
		attempts=$(( attempts - 1 ))
		sleep 2
	done

	fail "ollama did not become ready after restoring models"
}

find_model_store() {
	local explicit="$OLLAMA_MODEL_BUNDLE"
	local candidates=()
	local candidate

	if [[ -n "$explicit" ]]; then
		if [[ -d "$explicit/models" ]]; then
			printf '%s' "$explicit/models"
			return
		fi
		if [[ -d "$explicit/blobs" && -d "$explicit/manifests" ]]; then
			printf '%s' "$explicit"
			return
		fi
		fail "OLLAMA_MODEL_BUNDLE must point to a directory containing models/, or directly to a models directory"
	fi

	candidates=(
		"$SCRIPT_DIR/installtion-src/Models/models"
		"$SCRIPT_DIR/installation-src/Models/models"
		"$SCRIPT_DIR/Models/models"
	)

	for candidate in "${candidates[@]}"; do
		if [[ -d "$candidate/blobs" && -d "$candidate/manifests" ]]; then
			printf '%s' "$candidate"
			return
		fi
	done

	fail "No offline Ollama model store found next to this script"
}

detect_ollama_user() {
	if id -u ollama >/dev/null 2>&1; then
		printf '%s' ollama
		return
	fi

	printf '%s' root
}

restore_models() {
	local source_models_dir="$1"
	local target_models_dir="$OLLAMA_MODELS_PATH/models"

	log "Restoring models from $source_models_dir"
	$SUDO mkdir -p "$target_models_dir"
	$SUDO cp -R "$source_models_dir"/. "$target_models_dir"/
}

fix_permissions() {
	local ollama_user="$1"

	$SUDO mkdir -p "$OLLAMA_MODELS_PATH"
	$SUDO chown -R "$ollama_user:$ollama_user" "$OLLAMA_MODELS_PATH"
}

verify_restore() {
	local target_models_dir="$OLLAMA_MODELS_PATH/models"

	[[ -d "$target_models_dir/blobs" ]] || fail "Restored model store is missing blobs"
	[[ -d "$target_models_dir/manifests" ]] || fail "Restored model store is missing manifests"
	find "$target_models_dir/manifests" -type f | grep -q . || fail "No model manifests were restored"
	log "Model restore completed"
}

restart_ollama_if_present() {
	if ! command -v ollama >/dev/null 2>&1; then
		log "Skipping Ollama restart because the binary is not installed yet"
		return
	fi

	if command -v systemctl >/dev/null 2>&1; then
		if ! $SUDO systemctl list-unit-files ollama.service >/dev/null 2>&1; then
			log "Skipping Ollama restart because the service is not installed"
			return
		fi
	elif ! command -v service >/dev/null 2>&1; then
		log "Skipping Ollama restart because no service manager is available"
		return
	fi

	log "Restarting Ollama to reload restored models"
	service_action restart
	wait_for_ollama
}

main() {
	local source_models_dir
	local ollama_user

	source_models_dir="$(find_model_store)"
	restore_models "$source_models_dir"
	ollama_user="$(detect_ollama_user)"
	fix_permissions "$ollama_user"
	verify_restore
	restart_ollama_if_present

	ensure_models_registered
}

blob_path_for_digest() {
	local digest="$1"

	printf '%s/models/blobs/%s\n' "$OLLAMA_MODELS_PATH" "${digest/:/-}"
}

manifest_model_name() {
	local manifest_path="$1"
	local relative_path
	local parts=()
	local count

	relative_path="${manifest_path#$OLLAMA_MODELS_PATH/models/manifests/}"
	IFS='/' read -r -a parts <<< "$relative_path"
	count="${#parts[@]}"

	if (( count < 2 )); then
		fail "Unexpected manifest path: $manifest_path"
	fi

	if (( count >= 4 )) && [[ "${parts[0]}" == "registry.ollama.ai" && "${parts[1]}" == "library" ]]; then
		printf '%s:%s' "${parts[count-2]}" "${parts[count-1]}"
		return
	fi

	printf '%s:%s' "${parts[count-2]}" "${parts[count-1]}"
}

extract_manifest_digest() {
	local manifest_path="$1"
	local media_type="$2"

	grep -o '"mediaType":"'"$media_type"'","digest":"sha256:[^"]*"' "$manifest_path" \
		| sed -E 's/.*"digest":"(sha256:[^"]*)"/\1/' \
		| head -n 1
}

write_modelfile() {
	local manifest_path="$1"
	local modelfile_path="$2"
	local model_digest
	local template_digest
	local system_digest

	model_digest="$(extract_manifest_digest "$manifest_path" 'application/vnd.ollama.image.model')"
	[[ -n "$model_digest" ]] || fail "Manifest $manifest_path does not contain a model layer"

	template_digest="$(extract_manifest_digest "$manifest_path" 'application/vnd.ollama.image.template')"
	system_digest="$(extract_manifest_digest "$manifest_path" 'application/vnd.ollama.image.system')"

	{
		printf 'FROM %s\n' "$(blob_path_for_digest "$model_digest")"

		if [[ -n "$template_digest" ]]; then
			printf 'TEMPLATE """\n'
			cat "$(blob_path_for_digest "$template_digest")"
			printf '\n"""\n'
		fi

		if [[ -n "$system_digest" ]]; then
			printf 'SYSTEM """\n'
			cat "$(blob_path_for_digest "$system_digest")"
			printf '\n"""\n'
		fi
	} > "$modelfile_path"
}

ensure_models_registered() {
	local manifest_path
	local model_name
	local modelfile_path

	require_command ollama

	while IFS= read -r manifest_path; do
		model_name="$(manifest_model_name "$manifest_path")"
		if OLLAMA_HOST="127.0.0.1:11434" ollama show "$model_name" >/dev/null 2>&1; then
			log "Model already registered: $model_name"
			continue
		fi

		modelfile_path="$(mktemp /tmp/ollama-modelfile.XXXXXX)"
		write_modelfile "$manifest_path" "$modelfile_path"
		log "Registering model $model_name from restored bundle"
		OLLAMA_HOST="127.0.0.1:11434" ollama create "$model_name" -f "$modelfile_path"
		rm -f "$modelfile_path"
	done < <(find "$OLLAMA_MODELS_PATH/models/manifests" -type f | sort)
}

main "$@"
