# kit-ar fork of cruizba/ubuntu-dind

This repository is a fork of [cruizba/ubuntu-dind](https://github.com/cruizba/ubuntu-dind),
with extra tools for our CI pipelines (Azure DevOps). The upstream files are kept
as unchanged as possible, so that syncing with upstream is a plain `git merge`.

## What the fork adds

All changes are in the block marked `kit-ar additions` near the end of the `Dockerfile`:

| Tool | Why | Version source |
|---|---|---|
| git, git-lfs | repository checkouts | Ubuntu archive |
| less, zip, unzip | Azure Pipelines tasks | Ubuntu archive |
| .NET SDK | GitVersion | Ubuntu archive, see below |
| Helm (v3) | chart packaging and deployment | `HELM_VERSION` ARG |
| yq | YAML editing | `YQ_VERSION` ARG |
| ORAS | pushing and pulling OCI artifacts | `ORAS_VERSION` ARG |
| AWS CLI v2 | AWS access | `AWS_CLI_VERSION` ARG |

.NET packages per Ubuntu release (from the Ubuntu archive):

| Ubuntu | SDK | Extra runtimes |
|---|---|---|
| 22.04 | 8.0 | — |
| 24.04 | 10.0 | 8.0 (for tools that target `net8.0`, for example older GitVersion) |
| 26.04 | 10.0 | — |

On 26.04 a tool that targets only `net8.0` does not start. Use a tool version that
targets `net10.0`, or set `DOTNET_ROLL_FORWARD=Major` for that step.

Other fork files:

- `kit/aws-cli-team.asc`: public key of the AWS CLI team, used to verify the
  AWS CLI download. Fingerprint `FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C`,
  expires 2027-07-01. Source: [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
- `kit/test-tools.sh`: smoke test for the tools above.
- `.github/workflows/build-and-push-to-ghcr.yml`: our CI (see below).
- The upstream workflows have one added line,
  `if: github.repository == 'cruizba/ubuntu-dind'`, so they do not run in this fork.

## Images

`ghcr.io/kit-ar/cruizba--ubuntu-dind`, for `linux/amd64` and `linux/arm64`:

| Tag | Content |
|---|---|
| `22.04`, `24.04`, `26.04` | newest build for that Ubuntu release |
| `<ubuntu>-<docker>` (for example `24.04-29.8.2`) | newest build with that Docker version |
| `<ubuntu>-<docker>-r<build>` | one fixed build |
| `latest` | same as `24.04` |

## CI

`.github/workflows/build-and-push-to-ghcr.yml`:

- **Pull request:** builds every Ubuntu release on native amd64 and arm64 runners,
  then runs upstream's `test.sh` (Docker-in-Docker, privileged mode) and
  `kit/test-tools.sh`. Nothing is pushed.
- **Published release or manual run:** the same, then pushes to GHCR.

The Docker version in the tags is read from `DOCKER_VERSION` in the `Dockerfile`.
`BUILD_NUMBER` in the workflow is ours: increase it to rebuild the same Docker
version, and reset it to `0` when the Docker version changes.

## Sync with upstream

```bash
git remote add upstream https://github.com/cruizba/ubuntu-dind.git
```

```bash
git fetch upstream master
```

```bash
git merge upstream/master
```

Conflicts can occur only near the `kit-ar additions` block or the guard lines
in the upstream workflows. Keep both sides. Then build and test locally:

```bash
docker build --build-arg UBUNTU_VERSION=24.04 -t kit-dind:24.04 .
```

```bash
./test.sh --mode privileged --use-systemd false --image-name kit-dind:24.04
```

```bash
kit/test-tools.sh kit-dind:24.04
```

If upstream adds a new Ubuntu release, add it to the matrix in
`build-and-push-to-ghcr.yml` and check the .NET packages for it.

## Bump a tool version

Change the version ARG and both SHA-256 ARGs in the same commit. The build fails
if a checksum does not match. Get the checksums from the release assets:

```bash
for a in amd64 arm64; do curl -fsSL "https://get.helm.sh/helm-v3.22.1-linux-$a.tar.gz.sha256sum"; done
```

```bash
curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.54.1/checksums-bsd | grep -E '^SHA256 \(yq_linux_(amd64|arm64)\)'
```

```bash
curl -fsSL https://github.com/oras-project/oras/releases/download/v1.3.6/oras_1.3.6_checksums.txt | grep -E 'linux_(amd64|arm64)\.tar\.gz$'
```

The AWS CLI has no checksum ARGs: the build verifies its PGP signature with
`kit/aws-cli-team.asc`. When AWS publishes a new key, replace that file with
the key from the AWS CLI install guide.
