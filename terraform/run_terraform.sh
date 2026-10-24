#!/usr/bin/env bash

set -euo pipefail

case "${1:-}" in
  init)
    terraform_args=(init -plugin-dir=/work/plugins)
    ;;
  apply)
    terraform_args=(apply -auto-approve)
    ;;
  state-list)
    terraform_args=(state list)
    ;;
  *)
    echo "Usage: $0 {init|apply|state-list}" >&2
    exit 64
    ;;
esac

workdir="$(cd "$(dirname "$0")" && pwd)"
exec docker run --rm \
  -v "${workdir}:/work" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /work \
  hashicorp/terraform:1.12.2 "${terraform_args[@]}"
