#!/usr/bin/env bash
set -euo pipefail

SERVICE=gravitlauncher
WORKDIR=/app
DATADIR=/app/data
SOCKET=control-file

info() { echo "[INFO] $*"; }
err() {
	echo "[ERROR] $*" >&2
	exit 1
}

send_control() {
	local cmd="$1"
	echo "$cmd" | docker compose exec -T -w "$WORKDIR" "$SERVICE" socat UNIX-CONNECT:"$SOCKET" -
}

CMD=${1:-help}
shift || true

case "$CMD" in
start)
	docker compose up -d
	;;

stop)
	docker compose stop
	;;

restart)
	docker compose restart
	;;

logs)
	docker compose logs -f "$SERVICE"
	;;

attach)
	docker compose attach "$SERVICE"
	;;

ps)
	docker compose ps
	;;

stats)
	docker compose stats
	;;

shell)
	docker compose exec -it -w "$WORKDIR" "$SERVICE" /bin/bash
	;;

control)
	[[ $# -gt 0 ]] || err "Usage: glctl.sh control <command>"
	send_control "$*"
	;;

load-module)
	[[ $# -eq 1 ]] || err "Usage: glctl.sh load-module MODULE_NAME"
	send_control "modules load $1"
	;;

edit-config)
	docker compose exec -it "$SERVICE" sh -c "${EDITOR:-nano} $DATADIR/LaunchServerConfig.json"
	;;

cp-to)
	[[ $# -eq 2 ]] || err "Usage: glctl.sh cp-to SRC DST_IN_CONTAINER"
	docker cp "$1" "$(docker compose ps -q $SERVICE):$2"
	;;

cp-from)
	[[ $# -eq 2 ]] || err "Usage: glctl.sh cp-from SRC_IN_CONTAINER DST"
	docker cp "$(docker compose ps -q $SERVICE):$1" "$2"
	;;

esac
