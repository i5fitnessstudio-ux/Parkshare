#!/usr/bin/env bash
# =============================================================================
# ParkShare VPS discovery — READ ONLY.
#
# Runs no mutation: only `ls`, `cat` (redacted), and `docker inspect`.
# Nothing is restarted, recreated, or written.
#
# Run on the VPS:
#     bash inspect-vps.sh | tee /tmp/parkshare-inspect.txt
#
# Then send me the output (or the file). Secret *values* are redacted below, so
# the output is safe to share. It reveals only NAMES (networks, entrypoints,
# certresolver, service/container names) that the Traefik labels need.
# =============================================================================
set -u

hr() { printf '\n===== %s =====\n' "$1"; }

hr "docker + compose versions"
docker --version
docker compose version 2>/dev/null || docker-compose version 2>/dev/null || echo "(compose plugin not found)"

hr "running containers (parkshare / traefik / postgres)"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Networks}}' \
  | grep -Ei 'parkshare|traefik|postgres|db' || echo "(none matched)"

hr "docker networks"
docker network ls

hr "/opt/parkshare contents"
ls -la /opt/parkshare 2>/dev/null || echo "(cannot list /opt/parkshare)"

hr "compose file candidates (secret values redacted)"
for f in /opt/parkshare/compose.y*ml /opt/parkshare/docker-compose*.y*ml /opt/parkshare/*/compose.y*ml; do
  if [ -f "$f" ]; then
    echo "----- $f -----"
    sed -E 's/((PASSWORD|SECRET|KEY|TOKEN)[A-Z_]*[[:space:]]*[:=][[:space:]]*).+/\1<redacted>/I' "$f"
    echo
  fi
done

hr "traefik container: labels (these name the entrypoints + certresolver)"
TRAEFIK_NAME="$(docker ps --format '{{.Names}}' | grep -i traefik | head -n1 || true)"
echo "traefik container: ${TRAEFIK_NAME:-<not found by name>}"
if [ -n "${TRAEFIK_NAME:-}" ]; then
  docker inspect "$TRAEFIK_NAME" --format '{{json .Config.Labels}}' | tr ',' '\n' || true
  echo
  echo "--- traefik mounts (find the static config: traefik.yml / traefik.toml) ---"
  docker inspect "$TRAEFIK_NAME" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' || true
  echo
  echo "--- traefik networks (this is likely the external network to join) ---"
  docker inspect "$TRAEFIK_NAME" --format '{{range $n, $v := .NetworkSettings.Networks}}{{println $n}}{{end}}' || true
fi

hr "parkshare-backend: networks"
docker inspect parkshare-backend --format '{{json .NetworkSettings.Networks}}' 2>/dev/null || echo "(container not found)"

hr "parkshare-backend: published ports"
docker inspect parkshare-backend --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || echo "(container not found)"

hr "parkshare-backend: mounts (is uploads persisted?)"
docker inspect parkshare-backend --format '{{range .Mounts}}{{.Type}}  {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null || echo "(container not found)"

hr "parkshare-backend: env var NAMES only (values redacted)"
docker inspect parkshare-backend --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | cut -d= -f1 || echo "(container not found)"

hr "parkshare-backend: image + working dir + entrypoint"
docker inspect parkshare-backend \
  --format 'Image={{.Config.Image}}
WorkingDir={{.Config.WorkingDir}}
Entrypoint={{json .Config.Entrypoint}}
Cmd={{json .Config.Cmd}}' 2>/dev/null || echo "(container not found)"

hr "parkshare-db: networks + service/container name"
docker inspect parkshare-db --format '{{json .NetworkSettings.Networks}}' 2>/dev/null || echo "(container not found)"

hr "done"
echo "Send the full output back for final label values."
