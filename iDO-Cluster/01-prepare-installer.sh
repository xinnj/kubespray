#! /bin/bash
set -euao pipefail
base=$(dirname "$0")

if [ "$(/usr/bin/id -u)" != "0" ]; then
  echo -e "Script must run as root or as sudoer."
  exit 1
fi

DOWNLOAD_MIRROR="${DOWNLOAD_MIRROR:-false}"

yum install -y python3-pip podman podman-docker sshpass
touch /etc/containers/nodocker

if [ "${DOWNLOAD_MIRROR}" == "true" ]; then
    pip3 install -U -r "${base}/../requirements-2.12.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
else
    pip3 install -U -r "${base}/../requirements-2.12.txt"
fi
