#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

# Configurable retry settings
MAX_RETRIES=12
SLEEP_SECONDS=5

info() { echo -e "[INFO] $*"; }
err() { echo -e "[ERROR] $*" >&2; }

# Ensure docker compose exists
command -v docker >/dev/null 2>&1 || {
	err "docker is required. Install Docker and Docker Compose (v2)"
	exit 1
}

# Create .env if missing
if [[ ! -f "$ENV_FILE" ]]; then
	if [[ -f "$ENV_EXAMPLE" ]]; then
		cp "$ENV_EXAMPLE" "$ENV_FILE"
		info "Created .env from .env.example"
	else
		# minimal defaults
		cat >"$ENV_FILE" <<EOF
ADDRESS=localhost:17549
PROJECTNAME=MY_PROJECT
EOF
		info "Created .env with default values"
	fi
	echo
	info "You can edit .env now if you want (press Enter to continue)"
	${EDITOR:-nano} $ENV_FILE
fi

# Create launcher directory
if [[ ! -d "launcher" ]]; then
	mkdir launcher
fi

info "Compose file and .env are ready. Starting the stack..."
docker compose up -d

# Helper to send control commands via socat
send_control() {
	local cmd="$1"

	echo "[INFO] Sending: $cmd"

	echo "$cmd" | docker compose exec -T -w /app gravitlauncher \
		socat UNIX-CONNECT:/app/data/control-file - ||
		{
			echo "[ERROR] Failed: $cmd"
			exit 1
		}
}

wait_for_control_file() {
    local socket="/app/data/control-file"
    local retries=0
    local max_retries=30
    local sleep_seconds=3

    echo "[INFO] Waiting for launcher control socket at $socket..."
    until docker compose exec -T gravitlauncher test -S "$socket" >/dev/null 2>&1; do
        ((retries++))
        if (( retries > max_retries )); then
            echo "[ERROR] Control socket not found after $((retries*sleep_seconds)) seconds"
            docker compose logs gravitlauncher --tail=50
            exit 1
        fi
        echo "[INFO] Waiting... ($retries/$max_retries)"
        sleep $sleep_seconds
    done
    echo "[INFO] Control socket is ready"
}

wait_for_control_file

commands=(
	"modules load MirrorHelper"
	"modules load GenerateCertificate"
	"generatecertificate"
)

for c in "${commands[@]}"; do
	send_control "$c"
done

# Download JavaRuntime.jar if missing in data volume
info "Ensuring JavaRuntime.jar is present in persistent volume..."
if ! docker compose exec -T gravitlauncher bash -lc 'test -f /app/data/JavaRuntime.jar' >/dev/null 2>&1; then
	info "Downloading JavaRuntime.jar into /app/data/"
	docker compose exec gravitlauncher bash -lc 'cd /app/data && wget -q --show-progress https://github.com/GravitLauncher/LauncherRuntime/releases/latest/download/JavaRuntime.jar || exit 1'
else
	info "JavaRuntime.jar already exists — skipping download"
fi

# Ensure runtime folder exists and contains runtime files
if ! docker compose exec -T gravitlauncher bash -lc 'test -d /app/data/runtime || test -f /app/data/runtime/runtime.zip' >/dev/null 2>&1; then
	info "Downloading and unpacking runtime.zip into /app/data/runtime"
	docker compose exec gravitlauncher bash -lc 'mkdir -p /app/data/runtime && cd /app/data/runtime && wget -q --show-progress https://github.com/GravitLauncher/LauncherRuntime/releases/latest/download/runtime.zip && unzip -q runtime.zip && rm runtime.zip'
else
	info "Runtime already present — skipping runtime download"
fi

# Tell launcher about the Java runtime jar
send_control "modules launcher-load JavaRuntime.jar"
send_control "modules load Prestarter"

# Download Prestarter.exe if missing
if ! docker compose exec -T gravitlauncher bash -lc 'test -f /app/data/Prestarter.exe' >/dev/null 2>&1; then
	info "Downloading Prestarter.exe into /app/data"
	docker compose exec gravitlauncher bash -lc 'cd /app/data && wget -q --show-progress https://github.com/GravitLauncher/LauncherPrestarter/releases/latest/download/Prestarter.exe || exit 1'
else
	info "Prestarter.exe already exists — skipping download"
fi

info "Apply workspace"
send_control "applyworkspace"

info "Installation / initial setup finished."

cat <<EOF
Next steps & tips:
- Check logs: docker compose logs -f gravitlauncher
- Attach console: docker compose attach gravitlauncher
- If you edited .env after install, run: docker compose up -d
- Use the included glctl.sh for common operations (start/stop/logs/install-module/cp-to/cp-from)
EOF

exit 0
