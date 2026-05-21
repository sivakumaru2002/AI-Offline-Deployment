#### master-install.sh
#!/bin/sh
##### mongo Installation script for offline installation, intended to be run on a host with no internet access. This script is idempotent and can be safely re-run if interrupted.

mongoUsername="sampleUser"
mongoPassword="samplePassword"
mongoPort="27017"
mongoBindIp="0.0.0.0"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MONGO_INSTALLER="$SCRIPT_DIR/Mongo-server-offline-installation/install_mongodb_offline.sh"
mongoHost="$(hostname -f 2>/dev/null || hostname)"
connectionFile="$SCRIPT_DIR/Mongo-server-offline-installation/mongo-connection-string.txt"
connectionString="mongodb://$mongoUsername:$mongoPassword@$mongoHost:$mongoPort/admin?authSource=admin"
OLLAMA_INSTALLER="$SCRIPT_DIR/Ollama-server-installation/install_ollama_offline.sh"
OLLAMA_MODELS_INSTALLER="$SCRIPT_DIR/Ollama-server-installation/install_ollama_models_offline.sh"
ollamaPort="11434"
ollamaBindHost="127.0.0.1"
ollamaHost="127.0.0.1"
ollamaConnectionFile="$SCRIPT_DIR/Ollama-server-installation/ollama-endpoint.txt"
ollamaEndpoint="http://$ollamaHost:$ollamaPort"

check_mongo_installed() {
	command -v mongod >/dev/null 2>&1 || return 1
	if command -v systemctl >/dev/null 2>&1; then
		systemctl is-active --quiet mongod || return 1
	fi
	return 0
}

check_mongo_shell_installed() {
	command -v mongosh >/dev/null 2>&1 && return 0
	command -v mongo >/dev/null 2>&1 && return 0
	return 1
}

check_ollama_installed() {
	command -v ollama >/dev/null 2>&1 || return 1
	if command -v systemctl >/dev/null 2>&1; then
		systemctl is-active --quiet ollama || return 1
	fi
	return 0
}

if [ "${1:-}" = "--help" ]; then
	cat <<EOF
Usage: sudo ./master-install.sh
Static username: $mongoUsername
Static password: $mongoPassword
Expected installer: $MONGO_INSTALLER
Expected Ollama installer: $OLLAMA_INSTALLER
Expected Ollama models installer: $OLLAMA_MODELS_INSTALLER
EOF
	exit 0
fi

printf '[master-install] Using MongoDB host %s on port %s\n' "$mongoHost" "$mongoPort"

if check_mongo_installed && check_mongo_shell_installed; then
	printf '[master-install] MongoDB server and shell already installed. Skipping install\n'
else
	if check_mongo_installed; then
		printf '[master-install] MongoDB server is installed, but shell is missing. Installing offline shell artifacts\n'
	else
		printf '[master-install] MongoDB not found. Starting offline install\n'
	fi
	[ -f "$MONGO_INSTALLER" ] || { printf '[master-install] ERROR: installer not found: %s\n' "$MONGO_INSTALLER" >&2; exit 1; }
	MONGO_ADMIN_USER="$mongoUsername" \
	MONGO_ADMIN_PASSWORD="$mongoPassword" \
	MONGO_PUBLIC_HOST="$mongoHost" \
	MONGO_PORT="$mongoPort" \
	MONGO_BIND_IP="$mongoBindIp" \
	CONNECTION_FILE="$connectionFile" \
	bash "$MONGO_INSTALLER" || { printf '[master-install] ERROR: offline installer failed\n' >&2; exit 1; }
fi

check_mongo_installed || { printf '[master-install] ERROR: MongoDB install check failed\n' >&2; exit 1; }
check_mongo_shell_installed || { printf '[master-install] ERROR: MongoDB shell install check failed\n' >&2; exit 1; }
printf '[master-install] MongoDB installation check passed\n'

mkdir -p "$(dirname "$connectionFile")"
printf '%s\n' "$connectionString" > "$connectionFile"
printf '[master-install] Connection string: %s\n' "$connectionString"
printf '[master-install] Saved to %s\n' "$connectionFile"



##### Ollama installation script for offline installation, intended to be run on a host with no internet access. This script is idempotent and can be safely re-run if interrupted.

printf '[master-install] Using Ollama host %s on port %s\n' "$ollamaHost" "$ollamaPort"

if check_ollama_installed; then
	printf '[master-install] Ollama already installed. Skipping install\n'
else
	printf '[master-install] Ollama not found. Starting offline install\n'
	[ -f "$OLLAMA_INSTALLER" ] || { printf '[master-install] ERROR: installer not found: %s\n' "$OLLAMA_INSTALLER" >&2; exit 1; }
	OLLAMA_PUBLIC_HOST="$ollamaHost" \
	OLLAMA_PORT="$ollamaPort" \
	OLLAMA_BIND_HOST="$ollamaBindHost" \
	CONNECTION_FILE="$ollamaConnectionFile" \
	bash "$OLLAMA_INSTALLER" || { printf '[master-install] ERROR: Ollama offline installer failed\n' >&2; exit 1; }
fi

check_ollama_installed || { printf '[master-install] ERROR: Ollama install check failed\n' >&2; exit 1; }
printf '[master-install] Ollama installation check passed\n'

[ -f "$OLLAMA_MODELS_INSTALLER" ] || { printf '[master-install] ERROR: models installer not found: %s\n' "$OLLAMA_MODELS_INSTALLER" >&2; exit 1; }
printf '[master-install] Restoring offline Ollama models\n'
OLLAMA_MODELS_PATH="/var/lib/ollama" \
bash "$OLLAMA_MODELS_INSTALLER" || { printf '[master-install] ERROR: Ollama model restore failed\n' >&2; exit 1; }
printf '[master-install] Ollama model restore check passed\n'

mkdir -p "$(dirname "$ollamaConnectionFile")"
printf '%s\n' "$ollamaEndpoint" > "$ollamaConnectionFile"
printf '[master-install] Ollama endpoint: %s\n' "$ollamaEndpoint"
printf '[master-install] Saved to %s\n' "$ollamaConnectionFile"


##### Ollama model installation script for offline installation, intended to be run on a host with no internet access. This script is idempotent and can be safely re-run if interrupted.