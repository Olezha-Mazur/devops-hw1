#!/usr/bin/env bash

set -euo pipefail

readonly provider_version="4.6.0"
readonly provider_root="plugins/registry.terraform.io/kreuzwerker/docker/${provider_version}"

case "$(uname -m)" in
  x86_64|amd64)
    platform="linux_amd64"
    checksum="866046fa4938ac1ed5cc58b3c4d36e27433dac1aae50256911e6f28184dcf82e"
    ;;
  aarch64|arm64)
    platform="linux_arm64"
    checksum="d60fc2d42da1d567f28b6267dde57af03d7333033d8246c6880944f24d641556"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

archive="terraform-provider-docker_${provider_version}_${platform}.zip"
url="https://github.com/kreuzwerker/terraform-provider-docker/releases/download/v${provider_version}/${archive}"
destination="${provider_root}/${platform}"
temporary_archive="$(mktemp)"
trap 'rm -f "$temporary_archive"' EXIT

mkdir -p "$destination"
curl --fail --location --show-error --output "$temporary_archive" "$url"
printf '%s  %s\n' "$checksum" "$temporary_archive" | sha256sum --check --status
python3 -m zipfile -e "$temporary_archive" "$destination"
chmod +x "${destination}/terraform-provider-docker_v${provider_version}"

echo "Installed Docker provider v${provider_version} for ${platform} in ${destination}."
