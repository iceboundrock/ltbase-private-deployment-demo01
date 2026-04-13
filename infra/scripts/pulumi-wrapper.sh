#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
infra_dir="$(cd "${script_dir}/.." && pwd)"
binary_path="${infra_dir}/.pulumi/bin/ltbase-infra"
blueprint_dir="$(cd "${infra_dir}/.." && pwd)"
blueprint_binary_dir="${blueprint_dir}/.pulumi/bin"
blueprint_binary_path="${blueprint_binary_dir}/ltbase-infra"

cd "${infra_dir}"
mkdir -p .pulumi/bin "${blueprint_binary_dir}"

if [[ ! -x .pulumi/bin/ltbase-infra ]]; then
  CGO_ENABLED=0 go build -buildvcs=false -o .pulumi/bin/ltbase-infra ./cmd/ltbase-infra
fi

ln -sf "${binary_path}" "${blueprint_binary_path}"

exec pulumi "$@"
