# Nexus Start-up Runbook (server.example.com)

Nexus runs as the rootless Podman container `nexus` under the user `deploy` on server.example.com, port 8081, data in the volume `nexus-data`. After a server reset it does not come back on its own until you add the boot units in section 3.

## 1. Check whether Nexus is up

From Windows (PowerShell). `200` = ready; `000` or an error = down or still starting:

```powershell
curl.exe -s -o NUL -w "%{http_code}" http://server.example.com:8081/service/rest/v1/status
```

Container state on the server:

```powershell
ssh deploy@server.example.com "podman ps -a --filter name=nexus --format '{{.Names}} {{.Status}} {{.Ports}}'"
```

| Status shown | Meaning | Go to |
| --- | --- | --- |
| `Up ...` and HTTP 200 | Healthy | Nothing to do |
| `Up ...` but HTTP `000` | Still booting, wait 1 to 3 minutes | Section 4, logs |
| `Created` or `Exited` | Container exists but is stopped | Section 2, option A |
| `no container with name or ID` | Container was removed | Section 2, option B |

When did the server last boot:

```powershell
ssh deploy@server.example.com "uptime -s; uptime -p"
```

## 2. Start Nexus after a reset

**Option A: container exists but is stopped** (keeps all data and settings):

```powershell
ssh deploy@server.example.com "podman start nexus"
```

Wait 1 to 3 minutes, then repeat the HTTP check.

**Option B: container is gone.** Recreate it from the repo; the volume `nexus-data` keeps repositories and users, so do not run `setup.sh` again. From the repo folder:

```powershell
Get-Content nexus/deploy.sh -Raw | ssh deploy@server.example.com "sh -s"
```

Git Bash:

```bash
ssh deploy@server.example.com "sh -s" < nexus/deploy.sh
```

Alternatively press play on the manual `nexus` job in a `main` pipeline in GitLab.

Only on a brand-new volume do you also need `nexus/setup.sh` (see `ci-pipeline-setup.md`, Step 2).

**Start everything after a reset in one go:**

```powershell
ssh deploy@server.example.com "podman ps -a --format '{{.Names}} {{.Status}}'; podman start nexus hello-pipeline gitlab-runner"
```

Harbor is started by its own user service. If it is down:

```powershell
ssh deploy@server.example.com "systemctl --user start harbor.service"
```

## 3. Start automatically at boot (one-time setup)

The containers are rootless, so `--restart unless-stopped` does nothing after a reboot: no restart service is enabled at user level on this server. Harbor and `gitlab-runner` come back because each has its own systemd user unit; `nexus` and `hello-pipeline` do not. `deploy` already has lingering enabled (`Linger=yes`), so user units start at boot without a login.

`ssh deploy@server.example.com`, then run on the server. These units were not tested before this guide was written, so check the result in the last step.

If a container is already running, stop it first (`podman stop nexus`), otherwise `podman start -a` finds it running and the unit can flap.

```bash
mkdir -p ~/.config/systemd/user
for c in nexus hello-pipeline; do
cat > ~/.config/systemd/user/container-$c.service <<EOF
[Unit]
Description=Podman container $c
Wants=network-online.target
After=network-online.target

[Service]
Restart=on-failure
RestartSec=10
TimeoutStopSec=70
ExecStart=/usr/bin/podman start -a $c
ExecStop=/usr/bin/podman stop -t 30 $c

[Install]
WantedBy=default.target
EOF
done
systemctl --user daemon-reload
systemctl --user enable --now container-nexus.service container-hello-pipeline.service
```

The units refer to the container by name, so they keep working when `deploy.sh` removes and recreates it.

Verify:

```bash
systemctl --user is-enabled container-nexus.service container-hello-pipeline.service
systemctl --user status container-nexus.service --no-pager | head -8
loginctl show-user deploy -p Linger
```

Then a real test: `sudo reboot`, wait about 3 minutes, run the HTTP check from section 1. On failure: `journalctl --user -u container-nexus.service -n 30 --no-pager`.

To cover other containers repeat the loop with their names (for example the containers of other apps, if no compose unit manages them). List existing units: `systemctl --user list-unit-files | grep -E 'container-|harbor'`.

## 4. Logs, passwords and quick reference

```powershell
ssh deploy@server.example.com "podman logs --tail 40 nexus"
```

Nexus is ready when the log shows it started and the HTTP check returns `200`. Repeated `java.util.prefs ... Couldn't get file lock` warnings are harmless.

Initial admin password (only until you change it in the web wizard; the file is then removed):

```powershell
ssh deploy@server.example.com "podman exec nexus cat /nexus-data/admin.password"
```

Never delete the `nexus-data` volume: it holds your repositories and users.

| What | Value |
| --- | --- |
| Server | server.example.com, user `deploy` |
| Nexus web and API | http://server.example.com:8081/ |
| Nexus image | `docker.io/sonatype/nexus3:3.70.4` |
| Nexus data | Podman volume `nexus-data` |
| Raw repository | `releases-raw` |
| Upload user | `ci`, role `ci-publisher` |
| Harbor | https://server.example.com:4444, started by `harbor.service` |
| Deploy script | `nexus/deploy.sh` |
| One-time setup script | `nexus/setup.sh` |
