#!/bin/sh
# (Re)create the Nexus container on the Podman host. Run by the manual CI job `nexus`, or by hand on the server.
# Data lives in the named volume nexus-data, so it survives redeploys. Run nexus/setup.sh once afterwards.
set -eu
NEXUS_IMAGE="${NEXUS_IMAGE:-docker.io/sonatype/nexus3:3.70.4}"   # pre-pull on the server if Docker Hub is blocked
NEXUS_PORT="${NEXUS_PORT:-8081}"

docker pull "$NEXUS_IMAGE" || echo "pull failed, using the local copy if there is one"
docker rm -f nexus >/dev/null 2>&1 || true
docker run -d --name nexus --network bridge --restart unless-stopped \
  -p "$NEXUS_PORT:8081" \
  -v nexus-data:/nexus-data \
  -e INSTALL4J_ADD_VM_PARAMS="-Xms1g -Xmx2g -XX:MaxDirectMemorySize=2g" \
  "$NEXUS_IMAGE"
echo "Nexus starting at http://server.example.com:$NEXUS_PORT/ (first start takes 1-3 minutes)"
echo "Admin password: docker exec nexus cat /nexus-data/admin.password"
