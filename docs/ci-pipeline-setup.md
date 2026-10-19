# hello-scripts CI Pipeline Setup Guide

Every push to `main` builds `hello.exe` (Windows, under Wine) and three Ubuntu binaries on the GitLab runner at server.example.com, uploads them with the `*.sh` files to Nexus, and creates a GitLab release. Merge requests build only and upload nothing.

## Overview

| Job | Stage | What it produces | Runs on |
| --- | --- | --- | --- |
| `nexus` | nexus | (Re)creates the Nexus container on the server | `main`, manual |
| `build-linux` (3 jobs) | build | `hello-ubuntu20.04`, `hello-ubuntu22.04`, `hello-ubuntu24.04` | merge requests and `main` |
| `build-exe` | build | `hello.exe` (PyInstaller under Wine) | merge requests and `main` |
| `publish-sh` | publish | Uploads every `*.sh` in the repo root | `main` only |
| `release` | release | GitLab release `v1.<pipeline number>` linking the files in Nexus | `main` only |

Files land in the Nexus raw repository `releases-raw`, under `hello/v1.<n>/` for each release (`v1.` + the pipeline number, the same as the GitLab release and tag) and `hello/latest/` for the newest one. Container images stay in Harbor and are not part of this pipeline.

## Prerequisites

Everything runs on one server, server.example.com, under the user `deploy` with rootless Podman.

| Item | Needed state | How to check |
| --- | --- | --- |
| SSH access | `ssh deploy@server.example.com` works without a password prompt | `ssh deploy@server.example.com hostname` |
| Podman and docker shim | `docker` and `podman` installed on the server | `ssh deploy@server.example.com "which docker podman"` |
| GitLab runner | Container `gitlab-runner` running, Podman socket mounted at `/var/run/docker.sock` | `podman ps --filter name=gitlab-runner` |
| Runner network | Can pull `ubuntu:20.04/22.04/24.04` and the Wine base image; has `curl` | Run a pipeline, read the job log |
| Repo files | `.gitlab-ci.yml`, `app/Dockerfile.build`, `app/Dockerfile.build-exe`, `app/hello.py`, `app/requirements.txt`, `nexus/deploy.sh`, `nexus/setup.sh` | `git ls-files app nexus` |
| Harbor (optional) | Healthy on port 4444, only for container images | `curl -k https://server.example.com:4444/api/v2.0/health` |

The pipeline sets `DOCKER_HOST` to `unix:///var/run/docker.sock` and `DOCKER_BUILDKIT` to `0`, because Podman 3.x has no BuildKit.

## Step 1: Deploy Nexus on the server

Nexus 3.70.4 runs as the Podman container `nexus` on port 8081, data in the named volume `nexus-data` (redeploying keeps your repositories).

PowerShell:

```powershell
Get-Content nexus/deploy.sh -Raw | ssh deploy@server.example.com "sh -s"
```

Git Bash:

```bash
ssh deploy@server.example.com "sh -s" < nexus/deploy.sh
```

First start takes 1 to 3 minutes. A harmless `: not found` line at the end comes from a Windows line ending. Ready when this returns `200`:

```powershell
curl.exe -s -o NUL -w "%{http_code}" http://server.example.com:8081/service/rest/v1/status
```

Initial admin password (user `admin`):

```powershell
ssh deploy@server.example.com "podman exec nexus cat /nexus-data/admin.password"
```

## Step 2: Create the repository and the ci user

`nexus/setup.sh` creates the raw repository `releases-raw`, the role `ci-publisher` (browse, read, add, edit on that repository only), the user `ci`, and enables anonymous download. Choose a password for `ci` first (avoid `$`, `"` and `\`); it becomes `NEXUS_PASSWORD` in GitLab. Run this before you change the admin password in the web wizard.

PowerShell:

```powershell
$env:NEXUS_URL="http://server.example.com:8081"; $env:NEXUS_ADMIN_PASSWORD="<admin password from Step 1>"; $env:NEXUS_CI_PASSWORD="<password you choose for ci>"; & "C:\Program Files\Git\bin\sh.exe" nexus/setup.sh
```

Git Bash:

```bash
NEXUS_URL=http://server.example.com:8081 NEXUS_ADMIN_PASSWORD='<admin password>' NEXUS_CI_PASSWORD='<ci password>' sh nexus/setup.sh
```

It prints `done: repository releases-raw, user ci, anonymous download enabled`. Then open http://server.example.com:8081/, sign in as `admin` and set a new admin password.

## Step 3: Add the GitLab CI/CD variables

Settings, CI/CD, Variables:

| Key | Value | Options |
| --- | --- | --- |
| `NEXUS_USER` | `ci` | Visible |
| `NEXUS_PASSWORD` | the `ci` password from Step 2 | Masked. Tick Protected only if `main` is a protected branch |

Without them the upload steps on `main` fail with HTTP 401. Merge request pipelines do not need them.

## Step 4: Make sure the runner can build

1. The runner is registered to this project and online; the jobs use no tags.
2. The Podman socket is mounted into the runner as `/var/run/docker.sock`; the user service `podman.socket` is enabled for `deploy`.
3. The server can reach Docker Hub for the `ubuntu:*` and Wine base images, or you pre-pull them on the server.
4. `curl` exists in the job environment.

```powershell
ssh deploy@server.example.com "podman ps --filter name=gitlab-runner; systemctl --user is-enabled podman.socket"
```

## Step 5: How `.gitlab-ci.yml` works

Stages run in order: nexus, build, publish, release. `workflow` rules start a pipeline only for merge requests and the default branch.

1. **`build-linux`** runs three times in parallel, one per Ubuntu release. It builds `app/Dockerfile.build` with `UBUNTU` and `VERSION` (short sha), copies `/out/hello` out as `dist/hello-ubuntu<release>`, and on `main` uploads it to Nexus under `v1.<n>` and under `latest`.
2. **`build-exe`** does the same with `app/Dockerfile.build-exe` (PyInstaller under Wine) and produces `dist/hello.exe`.
3. **`publish-sh`** uploads every `*.sh` in the repo root to the same two Nexus paths, `main` only.
4. **`release`** waits for all of the above and calls the GitLab Releases API with the job token to create tag `v1.<pipeline number>` linking the five files in Nexus.
5. **`nexus`** is manual: press play on `main` to recreate the Nexus container.

Build jobs also keep `dist/` as GitLab artifacts for one week.

## Step 6: Run it and verify

1. Push to `main` (or merge a merge request) and watch CI/CD, Pipelines.
2. A merge request pipeline shows only the four build jobs and uploads nothing.
3. After a `main` pipeline, open Nexus, Browse, `releases-raw`, `hello`: a folder named after the release (for example `v1.12`) and a `latest` folder, each holding `hello.exe`, three `hello-ubuntu*` files and the `.sh` files.
4. Deployments, Releases in GitLab shows `v1.<n>` with the five links.

## Step 7: Download the files

Anonymous download is enabled. Replace `latest` with a release number (for example `v1.12`) for a specific build. Folders from before this change are named after the commit (`bc83ae07`).

| File | URL |
| --- | --- |
| Windows exe | `http://server.example.com:8081/repository/releases-raw/hello/latest/hello.exe` |
| Ubuntu 24.04 | `http://server.example.com:8081/repository/releases-raw/hello/latest/hello-ubuntu24.04` |
| Ubuntu 22.04 | `http://server.example.com:8081/repository/releases-raw/hello/latest/hello-ubuntu22.04` |
| Ubuntu 20.04 | `http://server.example.com:8081/repository/releases-raw/hello/latest/hello-ubuntu20.04` |
| Shell script | `http://server.example.com:8081/repository/releases-raw/hello/latest/hello.sh` |

On Linux run `chmod +x hello-ubuntu24.04` after downloading; Nexus does not keep the executable bit.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `curl: (22) ... 401` in an upload step | `NEXUS_USER` / `NEXUS_PASSWORD` missing or wrong | Re-check Step 3 and the `ci` password from Step 2 |
| `curl: (7)` or `(28)` to server.example.com:8081 | Nexus not running, still starting, or firewall | See `nexus-startup-runbook.md`; wait 1 to 3 minutes after a start |
| `curl: (22) ... 404` on upload | Repository `releases-raw` missing | Run `nexus/setup.sh` (Step 2) |
| Build cannot connect to the Docker daemon | Podman socket not mounted, or `podman.socket` disabled | Step 4 |
| `build-exe` fails pulling a base image | Server cannot reach the registry for the Wine image | Pre-pull on the server, or fix network/proxy |
| `release` fails with 401 or 403 | Job token cannot create releases/tags | Check job token permissions and the API response in the log |
| Release links return 404 | Uploads did not finish before the release | Re-run the failed upload job, then `release` |
| Nexus gone after a server reboot | No systemd user unit for `nexus` | See `nexus-startup-runbook.md`, section 3 |
| Runner log: `Checking for jobs... failed ... jobs/request: EOF` | The VPN on the server routes GitLab traffic too | See below, Known issues 5 |

## Known issues and fixes

Problems met while bringing this pipeline up (October 2026), newest last, with how each was confirmed.

### 1. `pip` cannot download PyInstaller: `Temporary failure in name resolution`

- **Seen in:** all three `build-linux` jobs: `HTTPSConnectionPool(host='files.pythonhosted.org', port=443) ... Failed to establish a new connection: [Errno -3] Temporary failure in name resolution`.
- **Cause:** on this network the DNS servers of the server (8.8.8.8, 1.1.1.1) give no answer for `files.pythonhosted.org`, the host PyPI serves the files from. `pypi.org` itself works, so pip finds the package but cannot download it. The host is reachable by IP.
- **Check:**
  ```bash
  getent hosts files.pythonhosted.org
  curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 https://files.pythonhosted.org/
  ```
- **Fix used:** a VPN on the server (Happ / xray). Before that, a hosts entry worked as a stopgap; it pins one CDN address, so remove it once the VPN is reliable:
  ```bash
  echo '151.101.0.223 files.pythonhosted.org' | sudo tee -a /etc/hosts     # stopgap
  sudo sed -i '/files.pythonhosted.org/d' /etc/hosts                       # remove it again
  ```
  The VPN needs a bypass rule for GitLab, see issue 5.

### 2. PyInstaller: `Python library not found: libpython3.X.so.1.0` (fixed)

- **Seen in:** all three `build-linux` jobs, after pip worked: `PyInstaller.exceptions.PythonLibraryNotFoundError: Python library not found: libpython3.10.so.1.0, libpython3.10.so`.
- **Cause:** `app/Dockerfile.build` installed `python3` without Python's shared library, which PyInstaller packs into the binary.
- **Fix:** `libpython3-dev` added to the `apt-get install` line in `app/Dockerfile.build`. Tested on the server: 20.04 (Python 3.8.10), 22.04 (3.10.12) and 24.04 (3.12.3) build and run.

### 3. `docker create`: `unable to find network configuration for default: network not found` (fixed)

- **Seen in:** `build-linux`, right after a successful `docker build`.
- **Cause:** the `docker` CLI asks for the network `default`. Podman 3.4 has no network with that name (`podman network ls` lists `podman`, `harbor_harbor`, `other_app_network`).
- **Fix:** `docker create --network none ...` in `build-linux` and `build-exe`. The container is never started, it only exists so `docker cp` can copy `/out/hello` out, so it needs no network. Tested through the runner's own `docker` CLI.

### 4. `build-exe`: `Failed to load Python DLL ... python312.dll` (worked around)

- **Seen in:** `build-exe`: PyInstaller reports `Building EXE from EXE-00.toc completed successfully`, then the test-run `wine /out/hello.exe` fails with `[PYI-...:ERROR] Failed to load Python DLL 'C:\users\root\AppData\Local\Temp\_MEI...\python312.dll'. LoadLibrary: DLL initialization failed.` and the job stops (exit status 255).
- **Cause:** the exe is built, but Wine in the image `tobix/pywine:3.12` cannot start Python 3.12 from a one-file exe. This points to Wine, not to a broken exe; not yet confirmed on real Windows.
- **Workaround:** in `app/Dockerfile.build-exe` the build now fails only if `/out/hello.exe` is missing or empty (`test -s`). The Wine test-run is a separate step that prints `WARNING: hello.exe did not run under Wine; test it on Windows` instead of failing.
- **Still to do:** run `hello.exe` on a real Windows PC after each change to the build. If it fails there too, try another Python/Wine image version, for example `tobix/pywine:3.11`.

### 5. Runner cannot reach GitLab after the VPN was turned on (`EOF`)

- **Seen in:** the runner log: `WARNING: Checking for jobs... failed ... couldn't execute POST against https://gitlab.example.com/api/v4/jobs/request: ... EOF`. No job starts.
- **Cause:** the VPN (interface `happ-xray`) becomes the default route for everything. GitLab (`gitlab.example.com` = `<GITLAB_PUBLIC_IP>`) is not reachable through it; through the normal card `enp2s0` it answers in 0.2 s.
- **Fix:** route GitLab past the VPN. Quick, lost at reboot:
  ```bash
  sudo ip route add <GITLAB_PUBLIC_IP>/32 via <GATEWAY_IP> dev enp2s0
  ```
  Permanent: a direct/bypass rule for `gitlab.example.com`, `<GITLAB_PUBLIC_IP>` in the VPN client's routing settings. Details: `gitlab-runner.md`, Known issues.

### 6. Runner restarted every ~90 seconds (fixed)

- **Cause and fix:** a broken systemd unit (stale `PIDFile`) restarted the runner container and would have killed long jobs. Replaced by a hand-written unit. Details: `gitlab-runner.md`, Known issues.

### 7. Nexus down after a server reboot

- **Cause:** rootless Podman ignores `--restart unless-stopped` after a reboot, and `nexus` had no systemd unit. Start it with `podman start nexus`; the boot unit is in `nexus-startup-runbook.md`, section 3.

### 8. Upload to Nexus fails: `curl: (22) The requested URL returned error: 401` (fixed)

- **Seen in:** all four build jobs on `main`, after a successful build: `$ if [ "$CI_COMMIT_BRANCH" = "$CI_DEFAULT_BRANCH" ]; then ...` then `curl: (22) The requested URL returned error: 401`. Merge request pipelines don't upload, so they stay green.
- **Cause:** the `ci` password in the GitLab variable `NEXUS_PASSWORD` didn't match the password of user `ci` in Nexus (it had been changed on one side only). A 401 means the login was refused; a 403 would mean the login worked but the role lacks a privilege.
- **Check which side is wrong** (type the password yourself; `201` = Nexus accepts it, `401` = it doesn't):
  ```powershell
  curl.exe -s -o NUL -w "%{http_code}`n" -u "ci:<ci password>" -T README.md http://server.example.com:8081/repository/releases-raw/test/README.md
  ```
  Delete the test file afterwards in Nexus (Browse, `releases-raw`, `test`).
- **Fix:** set the same password in Nexus (Settings, Security, Users, `ci`, Change password) and in GitLab (Settings, CI/CD, Variables, `NEXUS_PASSWORD`). Then retry the failed `main` pipeline.
- **Also check:** if `NEXUS_USER` / `NEXUS_PASSWORD` are Protected, `main` must be a protected branch, otherwise the job gets empty values and also fails with 401.
