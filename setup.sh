#!/bin/bash
if [ x$1 = x"precustomization" ]; then
echo "Started doing pre-customization steps..."
echo "Finished doing pre-customization steps."
elif [ x$1 = x"postcustomization" ]; then
echo "Started doing post-customization steps... $(date)"
echo "Adding user: ${username}"
useradd -m ${username}
echo ${userpassword} | passwd --stdin ${username}

SSH_DIR=~${username}/.ssh
KEY_FILE=$SSH_DIR/authorized_keys
echo "ssh dir: $SSH_DIR"
echo "key file: $KEY_FILE"

mkdir $SSH_DIR
touch $KEY_FILE
chown ${username} $KEY_FILE
chgrp ${username} $KEY_FILE
chmod 600 $KEY_FILE
chown ${username} $SSH_DIR
chgrp ${username} $SSH_DIR
chmod 700 $SSH_DIR
echo "${sshkey}" >> $KEY_FILE
echo "${username}  ALL=(ALL:ALL) ALL" >> /etc/sudoers
hostname ${hostname}
sed -i 's/dev-centos/${hostname}/g' /etc/hosts
sed -i 's/dev-centos/${hostname}/g' /etc/hostname

#Reset kubeadm
systemctl stop kubelet docker
cd /etc/
# backup old kubernetes data
mv /etc/kubernetes /etc/kubernetes-backup
mv /var/lib/kubelet /var/lib/kubelet-backup

# restore certificates
mkdir -p /etc/kubernetes
cp -r /etc/kubernetes-backup/pki /etc/kubernetes
rm -f /etc/kubernetes/pki/{apiserver.*,etcd/peer.*}

systemctl start docker
sleep 4
docker container rm $(docker container ls -aq)
kubeadm init --ignore-preflight-errors=DirAvailable--var-lib-etcd
rm -f /root/.kube/config
cp /etc/kubernetes/admin.conf /root/.kube/config
mkdir -p ~${username}/.kube
cp kubernetes/admin.conf ~${username}/.kube/config
chown -R ${username} ~${username}/.kube
chgrp -R ${username} ~${username}/.kube

delete_node=`kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes | grep -v ${hostname} | grep -v NAME | cut -f 1 -d ' '`
echo "Deleting old kubernetes node $delete_node"
kubectl --kubeconfig /etc/kubernetes/admin.conf delete node $delete_node

echo "Finished doing post-customization steps $(date)"
fi
