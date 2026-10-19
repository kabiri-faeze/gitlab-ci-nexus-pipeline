# GitLab CI/CD + Nexus pipeline (client side)

> This is a **GitLab** pipeline (`.gitlab-ci.yml`); GitHub does not run it. Host names such as `server.example.com`
> and `gitlab.example.com` are placeholders: replace them with your own server and GitLab address.

The programs and scripts that get built and published to **Nexus**. Container images stay in Harbor; the web page
and its deploy are in the separate `hello-pipeline` project.

| Path | What |
|---|---|
| `nexus/` | `deploy.sh` runs the Nexus container; `setup.sh` creates the repository, the upload user and anonymous download |
| `hello.sh` (any `*.sh` in the root) | shell scripts, published by the `publish-sh` job |
| `app/hello.py` | sample Python program |
| `app/build.bat [version]` | builds `app\dist\hello.exe` natively on Windows (PyInstaller) |
| `app/build.sh [version]` | builds `app/dist/hello` on the machine you run it on (Linux) |
| `app/Dockerfile.build` | builds the Linux binary inside `ubuntu:<version>`; used by the `build-linux` matrix |
| `app/Dockerfile.build-exe` | builds `hello.exe` under Wine, so CI needs no Windows machine |

## Where the files go

Nexus raw repository `releases-raw`, at `http://server.example.com:8081/repository/releases-raw/hello/v1.<n>/<file>`,
where `v1.<n>` is the GitLab release number (`v1.` + the pipeline number), plus a `latest` folder that is overwritten on every merge.

## Pipeline

| Job | When | What |
|---|---|---|
| `nexus` | `main`, manual | (re)creates the Nexus container on the server (data kept in the volume `nexus-data`) |
| `build-linux` | MR and `main` | 3 parallel jobs (Ubuntu 20.04, 22.04, 24.04); on `main` uploads `hello-ubuntu<ver>` |
| `build-exe` | MR and `main` | `hello.exe`; on `main` uploads it |
| `publish-sh` | `main` | uploads `*.sh` |
| `release` | `main` | GitLab release `v1.<n>` linking the files in Nexus |

Add or remove an Ubuntu version by editing the `UBUNTU` list in `.gitlab-ci.yml` and the links in `release`.

## One-time setup

1. On the server, pre-pull the image if Docker Hub is blocked: `podman pull docker.io/sonatype/nexus3:3.70.4`.
2. Run the `nexus` job by hand (pipeline page, play button). Wait 1-3 minutes, then open
   <http://server.example.com:8081/>. The admin password is in `docker exec nexus cat /nexus-data/admin.password`.
3. Create the repository and the upload user (from any machine that can reach Nexus):
   ```bash
   NEXUS_URL=http://server.example.com:8081 NEXUS_ADMIN_PASSWORD='...' NEXUS_CI_PASSWORD='choose-one' sh nexus/setup.sh
   ```
   Then change the admin password in the Nexus UI.
4. Add CI/CD variables to this project: `NEXUS_USER` = `ci` and `NEXUS_PASSWORD` = the `NEXUS_CI_PASSWORD` you chose
   (masked).
5. The Linux and exe jobs run on the runner on server.example.com (Podman socket, see hello-pipeline `docs/SETUP.md`); it
   must be able to pull `ubuntu:20.04`, `22.04` and `24.04`, and its image needs `curl`.

Back up the volume `nexus-data` (`podman volume inspect nexus-data` shows where it is). Cleanup of old versions:
Nexus UI -> Settings -> Repository -> Cleanup Policies, then attach one to `releases-raw`.

## Use on Ubuntu

```bash
curl -O http://server.example.com:8081/repository/releases-raw/hello/latest/hello-ubuntu22.04 && chmod +x hello-ubuntu22.04 && ./hello-ubuntu22.04
```

A binary built on an older Ubuntu also runs on newer ones, but not the other way round.
