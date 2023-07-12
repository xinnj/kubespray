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

export ANSIBLE_ROLES_PATH="${base}/../roles"
export ANSIBLE_LIBRARY="${base}/../library"
mkdir -p "${base}/logs"

# reset cluster
/usr/local/bin/ansible-playbook -i "${CONFIG_FILE}" -u root --private-key="${base}/../inventory/idocluster/ansible-key" \
  -e @"${base}/.parameters" \
  "${base}/../playbooks/reset.yml" | tee "${base}/logs/remove-cluster.log"
