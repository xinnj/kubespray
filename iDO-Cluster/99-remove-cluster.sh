#! /bin/bash
set -euao pipefail
base=$(dirname "$0")

if [ "$(/usr/bin/id -u)" != "0" ]; then
  echo -e "Script must run as root or as sudoer."
  exit 1
fi

export CONFIG_FILE="${base}/../inventory/idocluster/hosts.yaml"
if ! [ -f "${CONFIG_FILE}" ]; then
    echo -e "Can't find inventory file: ${CONFIG_FILE}"
    exit 1
fi

# reset cluster
/usr/local/bin/ansible-playbook -i "${CONFIG_FILE}"  -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
-e "{download_run_once: True}" -e "{download_localhost: True}" -e "{download_force_cache: True}"  -e "{download_keep_remote_cache: True}" -e download_cache_dir="/tmp/ido-cluster-cache" \
-e container_manager_on_localhost="docker" -e image_command_tool_on_localhost="docker" \
"${base}/../reset.yml" | tee remove-cluster.log