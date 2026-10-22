#!/bin/bash
# Build the official docker-library php images (fpm + cli, alpine) locally for the host architecture.
# Needed when Docker Hub has not yet published a manifest for the host arch
# (e.g. linux/arm64 right after a PHP point release — only amd64 is pushed first).
# The result carries the same tags the base Dockerfiles use (php:<ver>-fpm-alpine / php:<ver>-cli-alpine),
# so a later `docker pull` simply replaces it with the Hub build.
#
# usage: scripts/build-upstream-php.sh <php-version> [alpine-version]
#   e.g. scripts/build-upstream-php.sh 8.5.12 3.24
set -euo pipefail

VER=${1:?php version required, e.g. 8.5.12}
ALP=${2:-3.24}
MINOR=${VER%.*}
UPSTREAM="https://raw.githubusercontent.com/docker-library/php/master/${MINOR}/alpine${ALP}"
HELPERS="docker-php-entrypoint docker-php-ext-configure docker-php-ext-enable docker-php-ext-install docker-php-source"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for variant in fpm cli; do
    mkdir -p "$WORK/$variant"
    for f in Dockerfile $HELPERS; do
        curl -fsSL -o "$WORK/$variant/$f" "$UPSTREAM/$variant/$f"
    done
    chmod +x "$WORK/$variant"/docker-php-*
    got=$(awk '/^ENV PHP_VERSION /{print $3}' "$WORK/$variant/Dockerfile")
    if [ "$got" != "$VER" ]; then
        echo "ERROR: upstream ${MINOR}/alpine${ALP}/${variant} is at PHP ${got}, not ${VER}" >&2
        exit 1
    fi
    echo "==> building php:${VER}-${variant}-alpine for $(uname -m)"
    docker build -t "php:${VER}-${variant}-alpine" -f "$WORK/$variant/Dockerfile" "$WORK/$variant"
done

docker run --rm "php:${VER}-cli-alpine" php -v | head -1
