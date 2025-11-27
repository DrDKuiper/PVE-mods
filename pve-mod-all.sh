#!/usr/bin/env bash

set -euo pipefail

# This script's working directory
SCRIPT_CWD="$(dirname "$(readlink -f "$0")")"

# List of mod scripts to execute
MODS=(
	"pve-mod-gui-sensors.sh"
	"pve-mod-nag-screen.sh"
)

ACTION="${1:-install}"

echo "[info] Running PVE mods with action: ${ACTION}" >&2

for m in "${MODS[@]}"; do
	script_path="${SCRIPT_CWD}/${m}"
	if [[ ! -x "${script_path}" ]]; then
		echo "[error] Script not found or not executable: ${script_path}" >&2
		exit 1
	fi

	echo "[info] Executing: ${script_path} ${ACTION}" >&2
	"${script_path}" "${ACTION}"
done

echo "[info] All requested mods executed successfully." >&2

