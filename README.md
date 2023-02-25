# A fork of [Kubespray](README-Kubespray.md) project

### With following enhancements:

- Add necessary firewall rules when variable `set_firewall_rules` is true.
- Install NFS client for NFS provisioner when variable `install_nfs_client` is true.
- Offer a serial of scripts to help create / maintain k8s cluster.
- Enable download mirror to make the public resources download quickly in some areas of the world (such as China), 
when set system environment `export DOWNLOAD_MIRROR=true` 

### Scripts Explaining
All scripts are located on `iDO-Cluster` folder.
- **01-prepare-installer.sh**   
Install ansible and other packages required on `installer host`. 
`Installer host` can be any member host of k8s cluster, or a separated host which can access the cluster through SSH.
Right now, `installer host` can only be `RedHat` OS family, including Centos and AlmaLinux.
- **02-prepare-cluster.sh**   
The script collects IP address of each member host of k8s cluster, and generates inventory file used by ansible.
The role of each member host will be set automatically based on the order of IP provided. The table below can give more 
details. An SSH key will be generated and copy to cluster member hosts. Download mirror will be configured if system environment
  `DOWNLOAD_MIRROR=true` is found.

|  Cluster Size  |           node1           |         node2         |       node3       |  node4 and others  |
|:--------------:|:-------------------------:|:---------------------:|:-----------------:|:------------------:|
|       1        |   control-plane<br>etcd   |
|       2        |   control-plane<br>etcd   |    control-plane      |
|       3        |   control-plane<br>etcd   | control-plane<br>etcd | work node<br>etcd |
| 4<br>and above |   control-plane<br>etcd   | control-plane<br>etcd | work node<br>etcd | work node |

- **03-setup-cluster.sh**   
This script will set up a new k8s cluster according to the inventory file created by previous step.
- **04-add-node.sh**   
Use this script to add new nodes to an existing cluster. The role of new added nodes will be set using the same method 
as the table above described.
- **99-remove-cluster.sh**   
Remove the cluster.
