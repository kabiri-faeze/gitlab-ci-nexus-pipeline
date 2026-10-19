#!/bin/sh
# One-time Nexus setup through its REST API: raw repository, upload-only CI role and user, anonymous download.
# Usage: NEXUS_URL=http://server.example.com:8081 NEXUS_ADMIN_PASSWORD=... NEXUS_CI_PASSWORD=... sh nexus/setup.sh
# NEXUS_ADMIN_PASSWORD: the admin password (first start: docker exec nexus cat /nexus-data/admin.password).
# NEXUS_CI_PASSWORD: the password to give the `ci` user; put the same value in the CI variable NEXUS_PASSWORD.
set -eu
: "${NEXUS_URL:?}" "${NEXUS_ADMIN_PASSWORD:?}" "${NEXUS_CI_PASSWORD:?}"
api() { curl -fsS -u "admin:$NEXUS_ADMIN_PASSWORD" -H 'Content-Type: application/json' "$@"; }

api -X POST "$NEXUS_URL/service/rest/v1/repositories/raw/hosted" -d '{
  "name":"releases-raw","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false,"writePolicy":"allow"},
  "raw":{"contentDisposition":"ATTACHMENT"}}'

api -X POST "$NEXUS_URL/service/rest/v1/security/roles" -d '{
  "id":"ci-publisher","name":"ci-publisher","description":"upload to releases-raw",
  "privileges":["nx-repository-view-raw-releases-raw-browse","nx-repository-view-raw-releases-raw-read",
                "nx-repository-view-raw-releases-raw-add","nx-repository-view-raw-releases-raw-edit"],
  "roles":[]}'

api -X POST "$NEXUS_URL/service/rest/v1/security/users" -d "{
  \"userId\":\"ci\",\"firstName\":\"CI\",\"lastName\":\"Publisher\",\"emailAddress\":\"ci@example.com\",
  \"password\":\"$NEXUS_CI_PASSWORD\",\"status\":\"active\",\"roles\":[\"ci-publisher\"]}"

# Anyone on the network may download without a login.
api -X PUT "$NEXUS_URL/service/rest/v1/security/anonymous" -d '{
  "enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}'

echo "done: repository releases-raw, user ci, anonymous download enabled"
