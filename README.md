# gitlab-ci-nexus-pipeline
GitLab CI/CD pipeline that builds a Python app for Windows (.exe via Wine) and Ubuntu 20.04/22.04/24.04, uploads the binaries to a self-hosted Nexus raw repository, and creates versioned releases (v1.&lt;n>). Includes Nexus deploy/setup scripts and docs.
