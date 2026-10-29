ARG UBUNTU_VERSION="26.04"
FROM ubuntu:${UBUNTU_VERSION}

ARG UBUNTU_VERSION
ENV DOCKER_CHANNEL=stable \
    DOCKER_VERSION=29.8.2 \
    DOCKER_COMPOSE_VERSION=v5.5.1 \
    BUILDX_VERSION=v0.37.2 \
    DEBUG=false

# Install common dependencies
RUN set -eux; \
    apt-get update && apt-get install -y \
    ca-certificates wget curl iptables supervisor \
    && rm -rf /var/lib/apt/lists/*

# Set iptables backend per Ubuntu version:
#  - 22.04, 24.04: legacy backend (kept for compatibility)
#  - 26.04+: nft backend (iptables-legacy can't initialise the nat table on
#    iptables 1.8.11 shipped in 26.04)
RUN set -eux; \
    case "${UBUNTU_VERSION}" in \
        20.04) ;; \
        22.04|24.04) update-alternatives --set iptables /usr/sbin/iptables-legacy ;; \
        *) update-alternatives --set iptables /usr/sbin/iptables-nft ;; \
    esac

# Install Docker
RUN apt-get update && apt-get install -y wget curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh --version ${DOCKER_VERSION} \
    && rm get-docker.sh \
    && docker --version

# Install buildx
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) dockerArch='x86_64' ; buildx_arch='linux-amd64' ;; \
        armhf) dockerArch='armel' ; buildx_arch='linux-arm-v6' ;; \
        armv7) dockerArch='armhf' ; buildx_arch='linux-arm-v7' ;; \
        aarch64) dockerArch='aarch64' ; buildx_arch='linux-arm64' ;; \
        *) echo >&2 "error: unsupported architecture ($arch)"; exit 1 ;; \
    esac && \
    wget -O docker-buildx "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.${buildx_arch}" && \
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    chmod +x docker-buildx && \
    mv docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx && \
    docker buildx version

COPY modprobe start-docker.sh entrypoint.sh /usr/local/bin/
COPY supervisor/ /etc/supervisor/conf.d/
COPY logger.sh /opt/bash-utils/logger.sh

RUN chmod +x /usr/local/bin/start-docker.sh \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/modprobe

VOLUME /var/lib/docker

# Install Docker Compose
RUN set -eux; \
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose && \
    docker-compose version && \
    ln -s /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# ---------------------------------------------------------------------------
# kit-ar additions (not in upstream cruizba/ubuntu-dind)
#
# Keep every fork-specific change inside this block so that
# `git merge upstream/master` stays conflict-free. See kit/README.md.
# ---------------------------------------------------------------------------

# git/git-lfs for checkouts, zip/unzip for Azure Pipelines tasks, .NET SDK for
# GitVersion. .NET packages differ per Ubuntu release:
#  - 22.04: SDK 8.0 is the newest .NET in the Ubuntu archive
#  - 24.04: SDK 10.0, plus runtime 8.0 so net8.0 tools (GitVersion) keep working
#  - 26.04+: SDK 10.0 only
RUN set -eux; \
    case "${UBUNTU_VERSION}" in \
        22.04) dotnetPkgs='dotnet-sdk-8.0' ;; \
        24.04) dotnetPkgs='dotnet-sdk-10.0 dotnet-runtime-8.0' ;; \
        *) dotnetPkgs='dotnet-sdk-10.0' ;; \
    esac; \
    apt-get update; \
    apt-get install -y git git-lfs less zip unzip ${dotnetPkgs}; \
    rm -rf /var/lib/apt/lists/*; \
    git lfs version; \
    dotnet --list-sdks; \
    dotnet --list-runtimes

# Helm, yq, ORAS and AWS CLI. Downloads are verified against the SHA-256 sums
# below (AWS CLI: against its PGP signature). Bump version and sums together.
ARG HELM_VERSION=v3.22.1 \
    HELM_SHA256_AMD64=896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea \
    HELM_SHA256_ARM64=4c29e286b279d170fa048ddfc3e4e83dcd069ca9c52102766ba672d7149e694d \
    YQ_VERSION=v4.54.1 \
    YQ_SHA256_AMD64=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f \
    YQ_SHA256_ARM64=189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b \
    ORAS_VERSION=1.3.6 \
    ORAS_SHA256_AMD64=66fb0ad7206f3f6fa77ed5b552049d364ccf4b50b1684554f731f76302b52ca0 \
    ORAS_SHA256_ARM64=b84269e78dfc2d5329a4aab373da3200de95e6c138338cf6c66c10c0a3f248c1 \
    AWS_CLI_VERSION=2.39.0

RUN --mount=type=bind,source=kit/aws-cli-team.asc,target=/tmp/aws-cli-team.asc \
    set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) goArch='amd64'; awsArch='x86_64'; \
            helmSha="${HELM_SHA256_AMD64}"; yqSha="${YQ_SHA256_AMD64}"; orasSha="${ORAS_SHA256_AMD64}" ;; \
        aarch64) goArch='arm64'; awsArch='aarch64'; \
            helmSha="${HELM_SHA256_ARM64}"; yqSha="${YQ_SHA256_ARM64}"; orasSha="${ORAS_SHA256_ARM64}" ;; \
        *) echo >&2 "error: unsupported architecture ($arch)"; exit 1 ;; \
    esac; \
    tmp="$(mktemp -d)"; \
    cd "$tmp"; \
    \
    curl -fsSLo helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${goArch}.tar.gz"; \
    echo "${helmSha}  helm.tar.gz" | sha256sum -c -; \
    tar -xzf helm.tar.gz --no-same-owner --strip-components=1 -C /usr/local/bin "linux-${goArch}/helm"; \
    \
    curl -fsSLo yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${goArch}"; \
    echo "${yqSha}  yq" | sha256sum -c -; \
    install -m 0755 yq /usr/local/bin/yq; \
    \
    curl -fsSLo oras.tar.gz "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${goArch}.tar.gz"; \
    echo "${orasSha}  oras.tar.gz" | sha256sum -c -; \
    tar -xzf oras.tar.gz --no-same-owner -C /usr/local/bin oras; \
    \
    curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${awsArch}-${AWS_CLI_VERSION}.zip"; \
    curl -fsSLo awscliv2.sig "https://awscli.amazonaws.com/awscli-exe-linux-${awsArch}-${AWS_CLI_VERSION}.zip.sig"; \
    grep -Ev '^(-----|=|$)' /tmp/aws-cli-team.asc | base64 -d > aws-cli-team.gpg; \
    gpgv --keyring ./aws-cli-team.gpg awscliv2.sig awscliv2.zip; \
    unzip -q awscliv2.zip; \
    ./aws/install; \
    \
    cd /; \
    rm -rf "$tmp"; \
    helm version --short; \
    yq --version; \
    oras version; \
    aws --version

# ------------------------- end of kit-ar additions -------------------------

ENTRYPOINT ["entrypoint.sh"]
CMD ["bash"]
