#!/bin/sh

removeMongo="${REMOVE_MONGO:-${MONGO:-false}}"
removeOllama="${REMOVE_OLLAMA:-${OLLAMA:-false}}"
removeOllamaModels="${REMOVE_OLLAMA_MODELS:-${OLLAMA_MODELS:-${REMOVE_MODELS:-false}}}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MONGO_REMOVER="$SCRIPT_DIR/Mongo-server-offline-installation/remove_mongodb_offline.sh"
OLLAMA_REMOVER="$SCRIPT_DIR/Ollama-server-installation/remove_ollama_offline.sh"
OLLAMA_MODELS_REMOVER="$SCRIPT_DIR/Ollama-server-installation/remove_ollama_models_offline.sh"
connectionFile="$SCRIPT_DIR/Mongo-server-offline-installation/mongo-connection-string.txt"
ollamaConnectionFile="$SCRIPT_DIR/Ollama-server-installation/ollama-endpoint.txt"

if [ "${1:-}" = "--help" ]; then
	cat <<EOF
Usage: sudo ./master-remove.sh
Expected remover: $MONGO_REMOVER
Expected Ollama remover: $OLLAMA_REMOVER
Expected Ollama models remover: $OLLAMA_MODELS_REMOVER

Selection environment variables:
	REMOVE_MONGO or MONGO                    Remove MongoDB runtime (default: false)
	REMOVE_OLLAMA or OLLAMA                  Remove Ollama runtime (default: false)
	REMOVE_OLLAMA_MODELS or OLLAMA_MODELS    Remove Ollama model files (default: false)

Nothing is removed unless you explicitly select it with env vars or CLI flags.

MongoDB removal deletes binaries, service files, config, logs, and the saved
connection string file, but preserves the database files in /var/lib/mongo unless
REMOVE_DATA=true is also set.

Ollama runtime removal deletes binaries, service files, logs, and the saved endpoint
file, but preserves Ollama model files in /var/lib/ollama unless models are selected
separately.

To also delete the database files:
  sudo REMOVE_DATA=true ./master-remove.sh

To control each removal independently:
	sudo MONGO=true OLLAMA=false OLLAMA_MODELS=true ./master-remove.sh
	sudo REMOVE_MONGO=false REMOVE_OLLAMA=true REMOVE_OLLAMA_MODELS=false ./master-remove.sh

To remove only one target:
	sudo ./master-remove.sh --mongo
	sudo ./master-remove.sh --ollama
	sudo ./master-remove.sh --ollama-models

To remove all three explicitly:
	sudo ./master-remove.sh --all
EOF
	exit 0
fi

if [ "$#" -gt 0 ]; then
	removeMongo="false"
	removeOllama="false"
	removeOllamaModels="false"
	for arg in "$@"; do
		case "$arg" in
			--mongo)
				removeMongo="true"
				;;
			--ollama)
				removeOllama="true"
				;;
			--ollama-models)
				removeOllamaModels="true"
				;;
			--all)
				removeMongo="true"
				removeOllama="true"
				removeOllamaModels="true"
				;;
			*)
				printf '[master-remove] ERROR: unknown option: %s\n' "$arg" >&2
				exit 1
				;;
		esac
		done
fi

if [ "$removeMongo" != "true" ] && [ "$removeOllama" != "true" ] && [ "$removeOllamaModels" != "true" ]; then
	printf '[master-remove] ERROR: nothing selected. Use env vars or --mongo, --ollama, --ollama-models, or --all\n' >&2
	exit 1
fi

if [ "$removeMongo" = "true" ]; then
	[ -f "$MONGO_REMOVER" ] || {
		printf '[master-remove] ERROR: remover not found: %s\n' "$MONGO_REMOVER" >&2
		exit 1
	}

	printf '[master-remove] Starting MongoDB removal\n'
	CONNECTION_FILE="$connectionFile" bash "$MONGO_REMOVER"
	status=$?

	if [ "$status" -ne 0 ]; then
		printf '[master-remove] ERROR: MongoDB removal failed\n' >&2
		exit "$status"
	fi

	printf '[master-remove] MongoDB removal completed\n'
fi

if [ "$removeOllama" = "true" ]; then
	[ -f "$OLLAMA_REMOVER" ] || {
		printf '[master-remove] ERROR: remover not found: %s\n' "$OLLAMA_REMOVER" >&2
		exit 1
	}

	printf '[master-remove] Starting Ollama removal\n'
	REMOVE_MODELS=false CONNECTION_FILE="$ollamaConnectionFile" bash "$OLLAMA_REMOVER"
	status=$?

	if [ "$status" -ne 0 ]; then
		printf '[master-remove] ERROR: Ollama removal failed\n' >&2
		exit "$status"
	fi

	printf '[master-remove] Ollama removal completed\n'
	fi

if [ "$removeOllamaModels" = "true" ]; then
	[ -f "$OLLAMA_MODELS_REMOVER" ] || {
		printf '[master-remove] ERROR: models remover not found: %s\n' "$OLLAMA_MODELS_REMOVER" >&2
		exit 1
	}

	printf '[master-remove] Starting Ollama model removal\n'
	OLLAMA_MODELS_PATH="/var/lib/ollama" bash "$OLLAMA_MODELS_REMOVER"
	status=$?

	if [ "$status" -ne 0 ]; then
		printf '[master-remove] ERROR: Ollama model removal failed\n' >&2
		exit "$status"
	fi

	printf '[master-remove] Ollama model removal completed\n'
fi