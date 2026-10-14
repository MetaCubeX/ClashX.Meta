#!/bin/bash
set -euo pipefail

version="1.19.32"
base="https://github.com/MetaCubeX/mihomo/releases/download/v${version}"
amd_name="mihomo-darwin-amd64-compatible-v${version}.gz"
arm_name="mihomo-darwin-arm64-v${version}.gz"
amd_sha="18b382df77bded2ad0fb3db27db5636cb15b20729d5ba995a357eeb9b46bf507"
arm_sha="3312a6780652c622890fd4357c6a853bbf865464fd047ac7b7f52dab8de18652"
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"
output_dir="${repo_dir}/ClashX/Resources/MihomoCore"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

curl -fL "${base}/${amd_name}" -o "${work_dir}/${amd_name}"
curl -fL "${base}/${arm_name}" -o "${work_dir}/${arm_name}"

printf '%s  %s\n' "${amd_sha}" "${work_dir}/${amd_name}" | shasum -a 256 -c -
printf '%s  %s\n' "${arm_sha}" "${work_dir}/${arm_name}" | shasum -a 256 -c -

gunzip "${work_dir}/${amd_name}"
gunzip "${work_dir}/${arm_name}"
mkdir -p "${output_dir}"
lipo -create \
  "${work_dir}/${amd_name%.gz}" \
  "${work_dir}/${arm_name%.gz}" \
  -output "${output_dir}/mihomo"
chmod 0755 "${output_dir}/mihomo"
lipo "${output_dir}/mihomo" -verify_arch x86_64 arm64
"${output_dir}/mihomo" -v
