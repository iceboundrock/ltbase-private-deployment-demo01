#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
infra_dir="$(cd "${script_dir}/.." && pwd)"
pulumi_project_file="${infra_dir}/Pulumi.yaml"
pulumi_project_backup="${pulumi_project_file}.bak"
binary_path="${infra_dir}/.pulumi/bin/ltbase-infra"

restore_pulumi_project() {
  if [[ -f "${pulumi_project_backup}" ]]; then
    mv "${pulumi_project_backup}" "${pulumi_project_file}"
  fi
}

trap restore_pulumi_project EXIT

cd "${infra_dir}"
mkdir -p .pulumi/bin

if [[ ! -x .pulumi/bin/ltbase-infra ]]; then
  CGO_ENABLED=0 go build -buildvcs=false -o .pulumi/bin/ltbase-infra ./cmd/ltbase-infra
fi

sed -i.bak "s|binary: \./.pulumi/bin/ltbase-infra|binary: ${binary_path}|" "${pulumi_project_file}"
pulumi "$@"
