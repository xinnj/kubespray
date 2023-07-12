#! /bin/bash
set -euao pipefail
base=$(dirname $(realpath "$0"))

if [ "$(/usr/bin/id -u)" != "0" ]; then
  echo -e "Script must run as root or as sudoer."
  exit 1
fi

DOWNLOAD_MIRROR="${DOWNLOAD_MIRROR:-false}"
echo DOWNLOAD_MIRROR=${DOWNLOAD_MIRROR}

# Copy ``inventory/sample`` as ``inventory/idocluster``
if [ -d "${base}/../inventory/idocluster" ]; then
  rm -rf "${base}/../inventory/idocluster.bak"
  mv "${base}/../inventory/idocluster" "${base}/../inventory/idocluster.bak"
fi
cp -rfp "${base}/../inventory/sample" "${base}/../inventory/idocluster"

# Update Ansible inventory file with inventory builder
confirm='n'
while [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; do
  echo Please input IP of each host, separated by space, e.g. "10.184.101.51 10.184.101.52 10.184.101.53"
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

# Read VIP
echo "------------------------------------------------------------------"
echo "Please input VIP address, e.g. 10.184.101.50"
read -p "VIP: " -r VIP
sed -i '/^kube_vip_address/d' "${base}/../inventory/idocluster/group_vars/all/all.yml"
echo "kube_vip_address: ${VIP}" >>"${base}/../inventory/idocluster/group_vars/all/all.yml"

export CONFIG_FILE="${base}/../inventory/idocluster/hosts.yaml"
python3 "${base}/../contrib/inventory_builder/inventory.py" "${IPS[@]}"

# Generate ssh key
mkdir -p /root/.ssh
ssh-keygen -q -N '' -f "${base}/../inventory/idocluster/ansible-key"

echo "------------------------------------------------------------------"
read -p "Please input root password on each host: " -r USERPASS
for ip in "${IPS[@]}"; do
  echo "$USERPASS" | sshpass ssh-copy-id -i "${base}/../inventory/idocluster/ansible-key" -o StrictHostKeyChecking=no -p 22 root@${ip}
done

# Use the download mirror
if [ "$DOWNLOAD_MIRROR" == "true" ]; then
  cp -f "${base}/../inventory/idocluster/group_vars/all/offline.yml" "${base}/../inventory/idocluster/group_vars/all/mirror.yml"
  sed -i -E '/# .*\{\{ files_repo/s/^# //g' "${base}/../inventory/idocluster/group_vars/all/mirror.yml"
  tee -a "${base}/../inventory/idocluster/group_vars/all/mirror.yml" <<EOF
gcr_image_repo: "gcr.m.daocloud.io"
kube_image_repo: "k8s.m.daocloud.io"
docker_image_repo: "docker.m.daocloud.io"
quay_image_repo: "quay.m.daocloud.io"
github_image_repo: "ghcr.m.daocloud.io"
files_repo: "https://files.m.daocloud.io"
EOF
fi
