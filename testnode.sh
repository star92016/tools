#!/bin/bash

set -e

function split(){
   echo "-------------------$1---------------------"
}

# cpu info
split "CPU Basic Info"
lscpu
modelname=$(lscpu |grep -E 'Model name'|awk -F ':' '{print $NF}')
cpus=$(lscpu |grep '^CPU(s):'|awk -F ':' '{print $NF}')
tpercore=$(lscpu |grep Thread|awk -F ':' '{print $NF}')
split "CPU Summary Info"
echo "CPU: $modelname"
echo "NUMs: $cpus"
echo "Thread(s) per core: $tpercore"

split "Mem Basic Info"
free -h
dmidecode -t memory
if ! which numactl >/dev/null 2>&1 ; then
  apt install -y numactl
fi
numactl --hardware

split "GPU Info"
nvidia-smi
nvidia-smi topo -m

split "GPU Lnk"
for i in `nvidia-smi |grep -oE '[0-9A-F]*:[0-9A-F]{2}:[0-9A-F]{2}\.[0-9A-F]'`; do
  lspci -vvv -s $i| grep LnkSta
done

split "Extra Info"
lspci -t -vv -nn
ip l

split "Mellanox Info"
lspci |grep -i mel || true
definf=$(ip r | grep default|awk '{print $5}')
ethtool $definf
ibdev2netdev || true
ibv_devices || true

if ! which sysbench >/dev/null 2>&1 ; then
  apt install -y sysbench
fi

split "CPU Test"
sysbench cpu --cpu-max-prime=20000 --threads=96 run

split "Mem seq Test"
sysbench --test=memory --memory-block-size=1M --memory-total-size=100G --memory-access-mode=seq run
split "Mem rnd Test"
sysbench --test=memory --memory-block-size=1M --memory-total-size=100G --memory-access-mode=rnd run

testacs(){
    for BDF in $(lspci -d "*:*:*" | awk '{print $1}'); do
    # skip if it doesn't support ACS
    if ! setpci -v -s "${BDF}" ECAP_ACS+0x6.w > /dev/null 2>&1; then
        continue
    fi

    NEW_VAL=$(setpci -v -s "${BDF}" ECAP_ACS+0x6.w | awk '{print $NF}')
    if [ "${NEW_VAL}" != "0000" ]; then
        echo "ACS is on for $(lspci | grep ${BDF})"
        continue
    fi
    done
}

split "Check ACS"
testacs

split "install docker"
installdocker(){
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    apt-get install docker-ce -y
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt update
    apt install -y nvidia-container-toolkit
    cat <<EOF >/etc/docker/daemon.json
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "registry-mirrors": ["https://docker.mirrors.tuna.tsinghua.edu.cn"]
}
EOF
    systemctl restart docker
    docker info
}
if ! which docker >/dev/null 2>&1 ; then
  installdocker
fi

if ! docker images | grep -q 3f0b23af1f4f; then
  docker pull ngc.nju.edu.cn/nvidia/pytorch:24.04-py3
  docker tag ngc.nju.edu.cn/nvidia/pytorch:24.04-py3 nvcr.io/nvidia/pytorch:24.04-py3
fi

if ! docker ps | grep -q uniontest; then
  mkdir -p /root/uniontest
  # TODO need download
  tar xf /root/uniontest.tar.gz -C /root/uniontest
  docker run --name uniontest --gpus all -itd --rm --privileged -v /dev/shm:/dev/shm -v /root/uniontest:/root/uniontest --network host --device=/dev/infiniband/rdma_cm --device=/dev/infiniband/uverbs0 nvcr.io/nvidia/pytorch:24.04-py3
  docker exec uniontest pip3 install py-libnuma
fi

split "Run H2D Test"
docker exec uniontest /root/uniontest/h2d.py

split "Run D2H Test"
docker exec uniontest /root/uniontest/d2h.py

split "Run P2P Test"
docker exec uniontest /root/uniontest/p2pBandwidthLatencyTest

split "Run mulmat"
for i in `seq 0 7`; do
  docker exec uniontest /root/uniontest/matrixMulCUBLAS --device=$i --sizemult=10
done

split "Run all_reduce_perf"
docker exec uniontest /root/uniontest/all_reduce_perf -b 1g -e 1g -g 8

split "Run all_gather_perf"
docker exec uniontest /root/uniontest/all_gather_perf -g 8 -b 1g -e 1g