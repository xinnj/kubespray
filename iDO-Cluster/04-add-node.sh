#! /bin/bash
set -euao pipefail

base=$(dirname "$0")

export CONFIG_FILE="${base}/../inventory/mycluster/hosts.yaml"

function add_control_node() {
    # add control plane / etcd node
    sudo /usr/local/bin/ansible-playbook -i "${base}/../inventory/mycluster/hosts.yaml" -u root --private-key="${base}/../inventory/mycluster/ansible-key" \
        -e "{download_run_once: True}" -e "{download_localhost: True}" -e "{download_force_cache: True}" -e "{download_keep_remote_cache: True}" -e download_cache_dir="/tmp/ido-cluster-cache" \
        -e container_manager_on_localhost="docker" -e image_command_tool_on_localhost="docker" \
        -e "{helm_enabled: True}" \
        -e "{ingress_nginx_enabled: True}" \
        -e "{metrics_server_enabled: True}" \
        -e "{krew_enabled: True}" \
        -e "{install_nfs_client: True}" \
        -e "{set_firewall_rules: True}" \
        --limit=etcd,kube_control_plane -e ignore_assert_errors=yes -e etcd_retries=10 \
        "${base}/../cluster.yml" | tee setup-cluster.log

    sudo /usr/local/bin/ansible-playbook -i "${base}/../inventory/mycluster/hosts.yaml" -u root --private-key="${base}/../inventory/mycluster/ansible-key" \
        -e "{download_run_once: True}" -e "{download_localhost: True}" -e "{download_force_cache: True}" -e "{download_keep_remote_cache: True}" -e download_cache_dir="/tmp/ido-cluster-cache" \
        -e container_manager_on_localhost="docker" -e image_command_tool_on_localhost="docker" \
        -e "{helm_enabled: True}" \
        -e "{ingress_nginx_enabled: True}" \
        -e "{metrics_server_enabled: True}" \
        -e "{krew_enabled: True}" \
        -e "{install_nfs_client: True}" \
        -e "{set_firewall_rules: True}" \
        --limit=etcd,kube_control_plane -e ignore_assert_errors=yes -e etcd_retries=10 \
        "${base}/../upgrade-cluster.yml" | tee upgrade-cluster.log

    sudo /usr/local/bin/ansible -i "${base}/../inventory/mycluster/hosts.yaml" -u root --private-key="${base}/../inventory/mycluster/ansible-key" \
        k8s_cluster -m shell -a "nerdctl ps | grep k8s_nginx-proxy_nginx-proxy | awk '{print $1}' | xargs nerdctl restart"
}

function add_work_node() {
    # add work node
    sudo /usr/local/bin/ansible-playbook -i "${base}/../inventory/mycluster/hosts.yaml" -u root --private-key="${base}/../inventory/mycluster/ansible-key" \
        "${base}/../facts.yml"

    sudo /usr/local/bin/ansible-playbook -i "${base}/../inventory/mycluster/hosts.yaml" -u root --private-key="${base}/../inventory/mycluster/ansible-key" \
        -e "{download_run_once: True}" -e "{download_localhost: True}" -e "{download_force_cache: True}" -e "{download_keep_remote_cache: True}" -e download_cache_dir="/tmp/cache" \
        -e container_manager_on_localhost="docker" -e image_command_tool_on_localhost="docker" \
        -e "{helm_enabled: True}" \
        -e "{ingress_nginx_enabled: True}" \
        -e "{metrics_server_enabled: True}" \
        -e "{krew_enabled: True}" \
        -e "{install_nfs_client: True}" \
        -e "{set_firewall_rules: True}" \
        --limit="${work_node}" \
        "${base}/../scale.yml" | tee scale-cluster.log
}

# Get original hosts
read -ra original_hosts <<<$(python3 "${base}/../contrib/inventory_builder/inventory.py" print_hostnames)
original_hosts_num=${#original_hosts[@]}

# Update Ansible inventory file with inventory builder
confirm='n'
while [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; do
    echo Please input IP of each host to be added, separated by space, e.g. "10.184.101.53 10.184.101.54".
    read -p 'IPs: ' -r ip_string
    read -ra IPS <<<"$ip_string"

    if [ "${#IPS[@]}" != "0" ]; then
        (( n=original_hosts_num + 1 ))
        for ip in "${IPS[@]}"; do
            echo "node${n}: ${ip}"
            ((n++)) || true
        done
        read -p 'Is the data correct? (y/n)?' -r confirm
    fi
done

python3 "${base}/../contrib/inventory_builder/inventory.py" add "${IPS[@]}"

echo Following is the content of updated inventory file: "${base}/../inventory/mycluster/hosts.yaml"
echo
cat "${base}/../inventory/mycluster/hosts.yaml"
echo
read -p 'Is the data correct? (y/n)?' -r confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo Please update inventory file: "${base}/../inventory/mycluster/hosts.yaml"
    echo And execute the script again.
    exit
fi

# Copy ssh key to new nodes
for ip in "${IPS[@]}"; do
    sudo ssh-copy-id -i "${base}/../inventory/mycluster/ansible-key" -f -p 22 root@${ip}
done

# Get updated hosts
read -ra updated_hosts <<<$(python3 "${base}/../contrib/inventory_builder/inventory.py" print_hostnames)
updated_hosts_num=${#updated_hosts[@]}

# Only add control/etcd nodes
if [ $updated_hosts_num -le 3 ]; then
    add_control_node
fi

# Add both control/etcd and work nodes
if [ $updated_hosts_num -gt 3 ] && [ $original_hosts_num -lt 3 ]; then
    add_control_node

    work_node=''
    for (( c=3; c<updated_hosts_num; c++ )); do
        work_node="${work_node},${updated_hosts[c]}"
    done
    work_node="${work_node:1}"
    echo "work_node: ${work_node}"
    add_work_node
fi

# Add only work nodes
if [ $original_hosts_num -ge 3 ]; then
    work_node=''
    for (( c=original_hosts_num; c<updated_hosts_num; c++ )); do
        work_node="${work_node},${updated_hosts[c]}"
    done
    work_node="${work_node:1}"
    echo "work_node: ${work_node}"
    add_work_node
fi
