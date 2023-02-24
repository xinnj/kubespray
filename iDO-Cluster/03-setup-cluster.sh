#! /bin/bash
set -euao pipefail

base=$(dirname "$0")

# Setup cluster
sudo /usr/local/bin/ansible-playbook -i "${base}/../inventory/mycluster/hosts.yaml"  -u root --private-key="${base}/../inventory/mycluster/ansible-key" \
-e "{download_run_once: True}" -e "{download_localhost: True}" -e "{download_force_cache: True}"  -e "{download_keep_remote_cache: True}" -e download_cache_dir="/tmp/ido-cluster-cache" \
-e container_manager_on_localhost="docker" -e image_command_tool_on_localhost="docker" \
-e "{helm_enabled: True}" \
-e "{ingress_nginx_enabled: True}" \
-e "{metrics_server_enabled: True}" \
-e "{krew_enabled: True}" \
-e "{install_nfs_client: True}" \
-e "{set_firewall_rules: True}" \
"${base}/../cluster.yml" | tee setup-cluster.log