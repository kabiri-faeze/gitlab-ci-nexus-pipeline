# GitLab Runner

## What is it

GitLab itself only stores code and schedules pipelines. A **runner** is the program that actually executes the jobs: it asks GitLab for work, runs the job script, and sends the log back.

## What it does in our project

Both pipelines (`hello-scripts` and `hello-pipeline`) are executed by one runner on server.example.com. Its job scripts call `docker build`, `docker push`, `docker run` and `curl`; those commands reach the server's Podman, which builds and runs the containers.

| Item | Value |
| --- | --- |
| GitLab | https://gitlab.example.com (Docker Desktop on a Windows host) |
| Runner container | `gitlab-runner`, image `localhost/gitlab-runner-shell:19.4.1` |
| Runner name | `server-podman` |
| Executor | `shell` (jobs run inside the runner container) |
| Concurrency | 1 job at a time |
| Podman socket | `/run/user/1000/podman/podman.sock`, mounted as `/var/run/docker.sock` |
| Config | `/home/deploy/gitlab-runner/config/config.toml` on the server (holds the runner token) |
| Tools in the container | `docker` CLI, `git`, `bash`, `curl`, `wget` |
| Boot | systemd user unit `container-gitlab-runner.service` |

## Which runner is in use: new or old

The **new** one, `gitlab-runner`, is running. `gitlab-runner-old` (image `docker.io/gitlab/gitlab-runner:alpine`) has been stopped since 2026-10-14 and nothing uses it.

Why the old one was replaced: it used the **docker executor**. On this server Podman is 3.4.4, whose Docker API refuses the runner's attach call, so every job failed with `unable to upgrade to tcp, received 500`. The new runner uses the **shell executor**, which does not attach, and its image has the docker CLI added.

Both containers mount the same config folder, so do not start the old one while the new one runs. Going back to the old one only works after Podman is upgraded to 4.9 or newer.

## How to set it up

All on server.example.com as `deploy` (`ssh deploy@server.example.com`).

1. **Podman socket and lingering:**
   ```bash
   systemctl --user enable --now podman.socket
   sudo loginctl enable-linger deploy
   ```
2. **Build the runner image** (official runner plus docker CLI):
   ```bash
   mkdir -p ~/gitlab-runner/image
   printf 'FROM docker.io/gitlab/gitlab-runner:alpine-v19.4.1\nRUN apk add --no-cache docker-cli bash git\n' > ~/gitlab-runner/image/Containerfile
   podman build -t localhost/gitlab-runner-shell:19.4.1 ~/gitlab-runner/image
   ```
3. **Create the runner in GitLab:** Admin, CI/CD, Runners, New instance runner (or Settings, CI/CD, Runners in a project). Tick **Run untagged jobs**, copy the `glrt-...` token.
4. **Register it:**
   ```bash
   podman run --rm -it -v /home/deploy/gitlab-runner/config:/etc/gitlab-runner \
     localhost/gitlab-runner-shell:19.4.1 register \
     --url https://gitlab.example.com --token glrt-XXXX \
     --executor shell --name server-podman
   ```
5. **Start the container:**
   ```bash
   podman run -d --name gitlab-runner --restart always \
     --security-opt label=disable \
     --add-host registry.example.com:server.example.com \
     --add-host app.example.com:server.example.com \
     -v /home/deploy/gitlab-runner/config:/etc/gitlab-runner \
     -v /run/user/1000/podman/podman.sock:/var/run/docker.sock \
     localhost/gitlab-runner-shell:19.4.1 \
     run --working-directory=/home/gitlab-runner
   ```
   Do **not** add `--user=gitlab-runner`: that user gets permission denied on the socket.
6. **Check:** GitLab shows the runner Online with a recent Last contact, and
   ```bash
   podman exec gitlab-runner docker version --format 'server {{.Server.Version}}'
   podman exec gitlab-runner getent hosts registry.example.com
   ```
7. **Boot unit** (starts the container at boot and restarts it if it crashes). Don't use `podman generate systemd` without `--new`: its `PIDFile` points at one container id and breaks once the container is recreated (see Known issues). Write the unit by hand:
   ```bash
   cat > ~/.config/systemd/user/container-gitlab-runner.service <<'EOF'
   [Unit]
   Description=Podman container gitlab-runner
   Wants=network-online.target
   After=network-online.target

   [Service]
   Restart=always
   RestartSec=10
   TimeoutStopSec=70
   ExecStart=/usr/bin/podman start -a gitlab-runner
   ExecStop=/usr/bin/podman stop -t 10 gitlab-runner

   [Install]
   WantedBy=default.target
   EOF
   systemctl --user daemon-reload
   systemctl --user enable container-gitlab-runner.service
   systemctl --user restart container-gitlab-runner.service
   systemctl --user status container-gitlab-runner.service --no-pager | head -5   # must say active (running)
   ```

## What a new user should know

- **Security:** the runner can control every container on the server through the Podman socket, including Harbor, Nexus and any other app containers. Only run trusted projects on it.
- **Token:** the `token` line in `config.toml` is a secret. Never paste the file into chat or commit it.
- **Online is not proof:** the Online badge stays green for up to 2 hours. Look at Last contact.
- **Logs:** `podman logs --since 5m gitlab-runner` (`-f` returns immediately on Podman 3.4). `log_level` is `debug` right now, which is very noisy; set it to `info`.
- **Pipelines need the network:** the job pulls base images from Docker Hub. Pre-pull on the server if Docker Hub blocks you (`podman pull docker.io/library/nginx:alpine` was needed once).
- **Variables:** Harbor credentials (`HARBOR_USER`, `HARBOR_PASSWORD`) and Nexus credentials (`NEXUS_USER`, `NEXUS_PASSWORD`) live in GitLab CI/CD variables, not in the runner.
- **One job at a time:** `concurrent = 1`. The three Ubuntu builds queue behind each other.
- **Back up** `~/gitlab-runner/config/config.toml` with the GitLab backups.

## Known issues and fixes

### Runner restarted every ~90 seconds (fixed 2026-10-17)

- **Seen:** `podman ps` always showed the runner `Up` for only a few seconds. `systemctl --user status container-gitlab-runner.service` stayed in `activating (start)`, and the journal showed `Failed with result 'timeout'` and `Can't open PID file .../90b49a45.../conmon.pid`. It restarted 23 times in 30 minutes, which kills any job longer than about a minute.
- **Cause:** the unit made by `podman generate systemd` (without `--new`) had `Type=forking` and a `PIDFile` for an older container id. The container had been recreated since then, so the PID file never appeared; systemd timed out after 90 s and restarted it.
- **Fix:** replace the unit with the hand-written one in step 7 (`podman start -a`, no `PIDFile`). The old unit is kept as `~/.config/systemd/user/container-gitlab-runner.service.bak`.
- **Check:** this should print 0 or 1:
  ```bash
  journalctl --user -u container-gitlab-runner.service --since "-30min" --no-pager | grep -c "container start "
  ```

### Runner cannot reach GitLab after the VPN was turned on (`EOF`)

- **Seen:** the runner log fills with
  `WARNING: Checking for jobs... failed ... couldn't execute POST against https://gitlab.example.com/api/v4/jobs/request: ... EOF`
  and pipelines stay pending.
- **Cause:** the VPN client on the server (Happ / xray, interface `happ-xray`) becomes the default route for **all** traffic. `gitlab.example.com` resolves to `<GITLAB_PUBLIC_IP>`, which the VPN can't reach. Forced through the normal network card, GitLab answers at once:
  ```bash
  ip route get <GITLAB_PUBLIC_IP>        # shows which device is used
  curl -s -o /dev/null -w "%{http_code}\n" --interface enp2s0 https://gitlab.example.com/api/v4/version   # 401 = reachable
  ```
- **Quick fix (lost at reboot):** route GitLab past the VPN through the LAN gateway:
  ```bash
  sudo ip route add <GITLAB_PUBLIC_IP>/32 via <GATEWAY_IP> dev enp2s0
  ```
- **Permanent fix:** in the VPN client's routing settings, add a direct (bypass) rule for `gitlab.example.com` and `<GITLAB_PUBLIC_IP>`. Harbor and Nexus are on the server itself and aren't affected.
- **Why the VPN is there:** without it, `files.pythonhosted.org` (PyPI downloads) doesn't resolve on this network. See `ci-pipeline-setup.md`, Known issues.

Fuller background, with diagrams and every problem met so far: `hello-pipeline/docs/SETUP.md`.
