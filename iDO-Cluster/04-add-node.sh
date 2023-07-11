#! /bin/bash
set -euao pipefail
base=$(dirname $(realpath "$0"))

if [ "$(/usr/bin/id -u)" != "0" ]; then
  echo -e "Script must run as root or as sudoer."
  exit 1
fi

export CONFIG_FILE="${base}/../inventory/idocluster/hosts.yaml"
if ! [ -f "${CONFIG_FILE}" ]; then
    echo -e "Can't find inventory file: ${CONFIG_FILE}"
    exit 1
fi
# Restore the original inventory file if last run is failed
if [ -f "${CONFIG_FILE}.original" ]; then
    mv -f "${CONFIG_FILE}.original" "${CONFIG_FILE}"
fi

export ANSIBLE_ROLES_PATH="${base}/../roles"
mkdir -p "${base}/logs"

function add_control_node() {
    # add control plane / etcd node
    /usr/local/bin/ansible-playbook -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
        -e @"${base}/.parameters" \
        --limit=etcd,kube_control_plane -e ignore_assert_errors=yes -e etcd_retries=10 \
        --skip-tags=multus \
        "${base}/../cluster.yml" | tee "${base}/logs/add-control-node.log"

    /usr/local/bin/ansible-playbook -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
        -e @"${base}/.parameters" \
        --limit=etcd,kube_control_plane -e ignore_assert_errors=yes -e etcd_retries=10 \
        --skip-tags=multus \
        "${base}/../upgrade-cluster.yml" | tee "${base}/logs/add-control-node.log"
}

function add_work_node() {
    # add work node
    /usr/local/bin/ansible-playbook -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
        "${base}/../facts.yml"

    /usr/local/bin/ansible-playbook -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
        -e @"${base}/.parameters" \
        --limit="${work_node}" \
        "${base}/../scale.yml" | tee "${base}/logs/add-work-node.log"
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
cp -f "${CONFIG_FILE}" "${CONFIG_FILE}.original"
python3 "${base}/../contrib/inventory_builder/inventory.py" add "${IPS[@]}"

echo "------------------------------------------------------------------"
echo Following is the content of updated inventory file: "${CONFIG_FILE}"
echo
cat "${CONFIG_FILE}"
echo
read -p 'Is the data correct? (y/n)?' -r confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo Please update inventory file: "${CONFIG_FILE}"
    echo And execute the script again.
    exit
fi

# Copy ssh key to new nodes
echo "------------------------------------------------------------------"
read -p "Input root password on each host: " -r USERPASS
for ip in "${IPS[@]}"; do
    echo "$USERPASS" | sshpass ssh-copy-id -i "${base}/../inventory/idocluster/ansible-key" -o StrictHostKeyChecking=no -p 22 root@${ip}
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

# Set firewall rules for all nodes
/usr/local/bin/ansible -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
    k8s_cluster --module-name include_role --args name="${base}/../roles/firewall-rules"

# Restart all nginx-proxy
/usr/local/bin/ansible -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
    kube_control_plane[0] -m shell -a "kubectl get pod -n kube-system | grep nginx-proxy | awk '{print \$1}' | xargs -r kubectl delete pod -n kube-system"

# Restart all nginx ingress controller
/usr/local/bin/ansible -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
    kube_control_plane[0] -m shell -a "kubectl delete pod --all -n ingress-nginx"

rm -f "${CONFIG_FILE}.original"