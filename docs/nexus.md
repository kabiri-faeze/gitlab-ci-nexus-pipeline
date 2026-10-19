# Nexus

## What is it

Sonatype Nexus Repository 3 is an artifact store: a web server that keeps files and packages and gives each a stable download URL. In this project it is a **raw** repository, which means plain files with no package format.

## What it does in our project

The `hello-scripts` pipeline builds `hello.exe` (Windows, built under Wine) and three Ubuntu binaries, then uploads them and the `*.sh` files to Nexus. Anyone on the network can download them from a fixed URL, and the GitLab release links to those URLs.

| Item | Value |
| --- | --- |
| Where it runs | Podman container `nexus` on server.example.com (rootless, user `deploy`) |
| Address | http://server.example.com:8081/ |
| Image | `docker.io/sonatype/nexus3:3.70.4` |
| Data | Podman volume `nexus-data` (never delete it) |
| Repository | `releases-raw` (raw, hosted) |
| Upload user | `ci`, role `ci-publisher` (browse, read, add, edit on `releases-raw` only) |
| Download | anonymous, no login |
| Paths | `hello/v1.<n>/<file>` per release (same number as the GitLab release), `hello/latest/<file>` for the newest |

Container images do not go here, they go to Harbor (see `harbor.md`).

## How to set it up

1. **Deploy** the container from the repo (PowerShell; in Git Bash use `ssh deploy@server.example.com "sh -s" < nexus/deploy.sh`):
   ```powershell
   Get-Content nexus/deploy.sh -Raw | ssh deploy@server.example.com "sh -s"
   ```
   First start takes 1 to 3 minutes. Ready when this returns `200`:
   ```powershell
   curl.exe -s -o NUL -w "%{http_code}" http://server.example.com:8081/service/rest/v1/status
   ```
2. **Get the initial admin password** (user `admin`):
   ```powershell
   ssh deploy@server.example.com "podman exec nexus cat /nexus-data/admin.password"
   ```
3. **Create the repository and the `ci` user** with `nexus/setup.sh`. Choose a password for `ci` (no `$`, `"` or `\`):
   ```powershell
   $env:NEXUS_URL="http://server.example.com:8081"; $env:NEXUS_ADMIN_PASSWORD="<admin password>"; $env:NEXUS_CI_PASSWORD="<ci password>"; & "C:\Program Files\Git\bin\sh.exe" nexus/setup.sh
   ```
4. **Change the admin password** in the web UI (the wizard asks on first login). Do this after step 3.
5. **GitLab variables** (Settings, CI/CD, Variables): `NEXUS_USER` = `ci`, `NEXUS_PASSWORD` = the `ci` password (masked).
6. **Start at boot.** The containers are rootless, so `--restart unless-stopped` is not enough on this server. Add a systemd user unit; see `nexus-startup-runbook.md`, section 3.

## What a new user should know

- **After a reboot Nexus is down** until the boot unit exists. Check with the HTTP command above, then `podman start nexus` on the server.
- **Redeploying** (`deploy.sh`) removes and recreates the container but keeps the volume, so repositories and users survive. Running `setup.sh` a second time fails because the repository and user already exist.
- **Never delete the `nexus-data` volume.** It holds all artifacts, users and settings.
- **The executable bit is lost** on upload. After downloading a Linux binary run `chmod +x`.
- **Logs:** `ssh deploy@server.example.com "podman logs --tail 40 nexus"`. The `java.util.prefs ... file lock` warnings are harmless.
- **Memory:** `deploy.sh` gives Nexus a 1 GB to 2 GB heap. The server has about 8 GB shared with Harbor, GitLab runner and other app containers.
- **Plain HTTP:** Nexus is served over HTTP on port 8081. Anyone on the network can read it, and the `ci` password travels unencrypted on the LAN.
- **Passwords never go in the repo or in chat.** Keep them in GitLab masked variables.
- Full check, start and boot steps: `nexus-startup-runbook.md`. Pipeline walk-through: `ci-pipeline-setup.md`.
