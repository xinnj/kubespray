#! /bin/bash
set -euao pipefail
base=$(dirname "$0")

DOWNLOAD_MIRROR="${DOWNLOAD_MIRROR:-true}"

sudo dnf install -y python3-pip podman podman-docker
sudo touch /etc/containers/nodocker

if [ "${DOWNLOAD_MIRROR}" == "true" ]; then
    sudo pip3 install -U -r "${base}/../requirements-2.12.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
else
    sudo pip3 install -U -r "${base}/../requirements-2.12.txt"
fi
