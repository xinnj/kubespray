#! /bin/bash
set -euao pipefail

base=$(dirname "$0")

# reset cluster
sudo /usr/local/bin/ansible-playbook -i "${base}/../inventory/mycluster/hosts.yaml"  -u root --private-key="${base}/../inventory/mycluster/ansible-key" \
-e "{download_run_once: True}" -e "{download_localhost: True}" -e "{download_force_cache: True}"  -e "{download_keep_remote_cache: True}" -e download_cache_dir="/tmp/ido-cluster-cache" \
-e container_manager_on_localhost="docker" -e image_command_tool_on_localhost="docker" \
"${base}/../reset.yml" | tee remove-cluster.log