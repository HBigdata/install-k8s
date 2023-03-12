#!/usr/bin/env bash

### 安装helm
# 下载包
wget https://get.helm.sh/helm-v3.7.1-linux-amd64.tar.gz -O /tmp/helm-v3.7.1-linux-amd64.tar.gz
# 解压压缩包
tar -xf /tmp/helm-v3.7.1-linux-amd64.tar.gz -C /root/
# 制作软连接
rm -rf /usr/local/bin/helm
ln -s /root/linux-amd64/helm /usr/local/bin/helm

# 判断是否已经部署
helm list -n nfs-provisioner|grep -q nfs-provisioner
if [ $? -eq 0 ];then
   exit 0
fi

### 开始安装nfs-provisioner
# 添加helm仓库源
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

#### 安装nfs
yum -y install  nfs-utils rpcbind

# 服务端
mkdir -p /opt/nfsdata
# 授权共享目录
chmod 666 /opt/nfsdata
cat > /etc/exports<<EOF
/opt/nfsdata *(rw,no_root_squash,no_all_squash,sync)
EOF
# 配置生效
exportfs -r

systemctl enable --now rpcbind
systemctl enable --now nfs-server

# 客户端
for line in `cat /tmp/hosts`
do
    ip=`echo $line|awk '{print $1}'`
    master_ip=`head -1 /tmp/hosts|awk '{print $1}'`
    if [ "$ip" != "$master_ip" and "$ip" != {{ vip }} ];then
       ssh $ip "yum -y install rpcbind nfs-utils"
       ssh $ip "systemctl enable --now rpcbind"
    fi
done

echo "====================k8s install nfs-provisioner=======================" | tee -a /tmp/k8s.log

# 重试三次
for i in `seq 3`
do

# 查看
kubectl get pods,deploy,sc -n nfs-provisioner 2>/dev/null|grep -q 'provisioner'
if [ $? -eq 0 ];then
   break
fi

### helm安装nfs provisioner
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace=nfs-provisioner \
  --create-namespace \
  --set image.repository=willdockerhub/nfs-subdir-external-provisioner \
  --set image.tag=v4.0.2 \
  --set replicaCount=2 \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true \
  --set nfs.server={{ vip }} \
  --set nfs.path=/opt/nfsdata | tee -a /tmp/k8s.log

sleep 1

done

# 查看
kubectl get pods,deploy,sc -n nfs-provisioner 2>/dev/null|grep -q 'provisioner'
if [ ! $? -eq 0 ];then
  echo "install nfs-provisioner failed!!!"; exit 1
fi

echo "====================k8s install nfs-provisioner end=======================" | tee -a /tmp/k8s.log
