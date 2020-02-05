#!/bin/bash

set -e

NODE_IP="$1"

# Global configuration

sudo bash -c 'cat > /etc/hosts <<EOF
127.0.0.1	localhost
192.168.50.10	k8s-1
192.168.50.11	k8s-2
192.168.50.12	k8s-3
EOF'

# Install Docker
sudo yum install -y apt-transport-https ca-certificates curl software-properties-common
sudo yum install -y yum-utils device-mapper-persistent-data lvm2
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce-19.03.5
sudo mkdir -p /etc/docker
sudo bash -c 'cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF'
sudo systemctl daemon-reload
sudo systemctl enable docker.service
sudo systemctl restart docker

# Add vagrant user to docker group for easy debuging
sudo usermod -aG docker vagrant

# Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Run prerequisites
sudo bash -c 'cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF'
sudo sysctl --system
sudo sysctl -p
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Install Kubernetes
sudo bash -c 'cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF'

sudo yum install -y kubelet-1.17.2 kubeadm-1.17.2 kubectl-1.17.2 --disableexcludes=kubernetes

sudo bash -c "cat <<EOF | sudo tee /etc/sysconfig/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP
EOF"

sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl enable --now kubelet

# Initialize K8S
sudo kubeadm init --token vag3nt.nos3curebutlocal --pod-network-cidr=172.16.0.0/16 --apiserver-advertise-address=192.168.50.10 > kubeinit.log

# Move K8S config to vagrant user and create K8S
mkdir -p /home/vagrant/.kube
sudo cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config
# Install CNI : Flannel
su - vagrant -c "kubectl apply -f https://docs.projectcalico.org/v3.11/manifests/calico.yaml"
