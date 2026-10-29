#!/bin/bash
# Smoke test for the kit-ar additions in the Dockerfile.
# Usage: kit/test-tools.sh <image-name>
#
# Docker-in-Docker itself is covered by upstream's test.sh.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <image-name>" >&2
    exit 1
fi

# Skip the entrypoint: these checks don't need dockerd.
docker run --rm --entrypoint bash "$1" -euxo pipefail -c '
    git --version
    git lfs version
    less --version | head -n 1
    zip -v | head -n 2
    unzip -v | head -n 1
    dotnet --list-sdks | grep .
    dotnet --list-runtimes | grep .
    helm version --short
    yq --version
    oras version
    aws --version

    # Binaries must match the image architecture, not just exist.
    machine="$(uname -m)"
    case "$machine" in
        x86_64) want="x86-64" ;;
        aarch64) want="aarch64" ;;
        *) echo "unsupported architecture: $machine" >&2; exit 1 ;;
    esac
    for bin in /usr/local/bin/helm /usr/local/bin/yq /usr/local/bin/oras; do
        [ "$(stat -c %U:%G "$bin")" = "root:root" ]
        od -An -tx1 -N20 "$bin" | tr -d " \n" | grep -q "^7f454c46"
        case "$want" in
            x86-64) od -An -tx1 -j18 -N2 "$bin" | tr -d " \n" | grep -qx "3e00" ;;
            aarch64) od -An -tx1 -j18 -N2 "$bin" | tr -d " \n" | grep -qx "b700" ;;
        esac
    done

    # yq must actually work, not just print its version.
    [ "$(echo "a: 1" | yq ".a")" = "1" ]
'

echo "kit-ar tools test passed for $1"
