# based on cruizba/ubuntu-dind, with addition of git, dotnet-runtime (for AZDO GitVersion) and less (of course)
#
FROM ubuntu:24.04

RUN apt update \
    && apt install -y ca-certificates \
    wget curl iptables supervisor \
    less \
    git git-lfs \
    unzip \
    dotnet-sdk-8.0 \	
    && rm -rf /var/lib/apt/list/* \
    && update-alternatives --set iptables /usr/sbin/iptables-legacy

# we also need YQ and Helm in our pipelines 
ENV HELM_VERSION=v3.17.1 \
    YQ_VERSION=v4.45.1

RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) helmArch='amd64' ; yqArch='amd64' ;; \
        aarch64) helmArch='arm64' ; yqArch='arm64' ;; \
        *) echo >&2 "error: unsupported architecture ($arch)"; exit 1 ;; \
    esac; \
    wget -O helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${helmArch}.tar.gz" \
    && tar -xzf helm.tar.gz \
    && mv linux-${helmArch}/helm /usr/local/bin/helm \
    && rm -rf linux-${helmArch} helm.tar.gz \
    && wget -O /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yqArch}" \
    && chmod +x /usr/local/bin/yq \
    && helm version --short \
    && yq --version


# Install AWS CLI
ENV AWS_CLI_VERSION=2.24.5

RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) awsArch='x86_64' ;; \
        aarch64) awsArch='aarch64' ;; \
        *) echo >&2 "error: unsupported architecture ($arch)"; exit 1 ;; \
    esac; \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${awsArch}-${AWS_CLI_VERSION}.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Install Azure CLI
ENV AZURE_CLI_VERSION=2.69.0
RUN apt-get update \
    && apt-get install -y gpg lsb-release \
    && curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null \
    && AZ_REPO=$(lsb_release -cs) \
    && echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update \
    && apt-get install -y azure-cli=${AZURE_CLI_VERSION}-1~$(lsb_release -cs) \
    && rm -rf /var/lib/apt/lists/*


ENV DOCKER_CHANNEL=stable \
	DOCKER_VERSION=25.0.3 \
	DOCKER_COMPOSE_VERSION=v2.24.5 \
	BUILDX_VERSION=v0.12.1 \
	DEBUG=false

# Docker and buildx installation
RUN set -eux; \
	\
	arch="$(uname -m)"; \
	case "$arch" in \
        # amd64
		x86_64) dockerArch='x86_64' ; buildx_arch='linux-amd64' ;; \
        # arm32v6
		armhf) dockerArch='armel' ; buildx_arch='linux-arm-v6' ;; \
        # arm32v7
		armv7) dockerArch='armhf' ; buildx_arch='linux-arm-v7' ;; \
        # arm64v8
		aarch64) dockerArch='aarch64' ; buildx_arch='linux-arm64' ;; \
		*) echo >&2 "error: unsupported architecture ($arch)"; exit 1 ;;\
	esac; \
	\
	if ! wget -O docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${dockerArch}/docker-${DOCKER_VERSION}.tgz"; then \
		echo >&2 "error: failed to download 'docker-${DOCKER_VERSION}' from '${DOCKER_CHANNEL}' for '${dockerArch}'"; \
		exit 1; \
	fi; \
	\
	tar --extract \
		--file docker.tgz \
		--strip-components 1 \
		--directory /usr/local/bin/ \
	; \
	rm docker.tgz; \
	if ! wget -O docker-buildx "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.${buildx_arch}"; then \
		echo >&2 "error: failed to download 'buildx-${BUILDX_VERSION}.${buildx_arch}'"; \
		exit 1; \
	fi; \
	mkdir -p /usr/local/lib/docker/cli-plugins; \
	chmod +x docker-buildx; \
	mv docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx; \
	\
	dockerd --version; \
	docker --version; \
	docker buildx version

COPY modprobe start-docker.sh entrypoint.sh /usr/local/bin/
COPY supervisor/ /etc/supervisor/conf.d/
COPY logger.sh /opt/bash-utils/logger.sh

RUN chmod +x /usr/local/bin/start-docker.sh \
	/usr/local/bin/entrypoint.sh \
	/usr/local/bin/modprobe

VOLUME /var/lib/docker

# Docker compose installation
RUN curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
	&& chmod +x /usr/local/bin/docker-compose && docker-compose version

# Create a symlink to the docker binary in /usr/local/lib/docker/cli-plugins
# for users which uses 'docker compose' instead of 'docker-compose'
RUN ln -s /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

ENTRYPOINT ["entrypoint.sh"]
CMD ["bash"]
