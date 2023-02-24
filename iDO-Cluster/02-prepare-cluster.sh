#! /bin/bash
set -euao pipefail
base=$(dirname "$0")

DOWNLOAD_MIRROR="${DOWNLOAD_MIRROR:-true}"

# Copy ``inventory/sample`` as ``inventory/mycluster``
if [ -d "${base}/../inventory/mycluster" ]; then
    sudo rm -rf "${base}/../inventory/mycluster.bak"
    mv "${base}/../inventory/mycluster" "${base}/../inventory/mycluster.bak"
fi
cp -rfp "${base}/../inventory/sample" "${base}/../inventory/mycluster"

# Update Ansible inventory file with inventory builder
confirm='n'
while [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; do
    echo Please input IP of each host, separated by space, e.g. "10.184.101.50 10.184.101.51 10.184.101.52".
    read -p 'IPs: ' -r ip_string
    read -ra IPS <<<"$ip_string"

    if [ "${#IPS[@]}" != "0" ]; then
        n=1
        for ip in "${IPS[@]}"; do
            echo "node${n}: ${ip}"
            ((n++)) || true
        done
        read -p 'Is the data correct? (y/n)?' -r confirm
    fi
done

CONFIG_FILE="${base}/../inventory/mycluster/hosts.yaml"
python3 "${base}/../contrib/inventory_builder/inventory.py" "${IPS[@]}"

# Generate ssh key
if [ -e "${base}/../inventory/mycluster/ansible-key" ] && [ -e "${base}/../inventory/mycluster/ansible-key.pub" ]; then
    echo Find existing SSH key: "${base}/../inventory/mycluster/ansible-key"
    echo Do you want to use the existing one, or generate a new one?
    read -p 'use existing (y), generate new (n): ' -r use_existing_key
    if [ "$use_existing_key" != "y" ] && [ "$use_existing_key" != "Y" ]; then
        ssh-keygen -q -N '' -f "${base}/../inventory/mycluster/ansible-key"
    fi
else
    ssh-keygen -q -N '' -f "${base}/../inventory/mycluster/ansible-key"
fi

for ip in "${IPS[@]}"; do
    sudo ssh-copy-id -i "${base}/../inventory/mycluster/ansible-key" -f -p 22 root@${ip}
done

# Use the download mirror
if [ "$DOWNLOAD_MIRROR" == "true" ]; then
    cp -f "${base}/../inventory/mycluster/group_vars/all/offline.yml" "${base}/../inventory/mycluster/group_vars/all/mirror.yml"
    sed -i -E '/# .*\{\{ files_repo/s/^# //g' "${base}/../inventory/mycluster/group_vars/all/mirror.yml"
    tee -a "${base}/../inventory/mycluster/group_vars/all/mirror.yml" <<EOF
gcr_image_repo: "gcr.m.daocloud.io"
kube_image_repo: "k8s.m.daocloud.io"
docker_image_repo: "docker.m.daocloud.io"
quay_image_repo: "quay.m.daocloud.io"
github_image_repo: "ghcr.m.daocloud.io"
files_repo: "https://files.m.daocloud.io"
EOF
fi
