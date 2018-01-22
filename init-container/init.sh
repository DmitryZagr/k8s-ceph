#!/bin/bash

DEBIAN_VERSION=$(grep "VERSION=" /etc/os-release |awk -F= {' print $2'}|sed s/\"//g |sed s/[0-9]//g | sed s/\)$//g |sed s/\(//g)
TMP_USER=sky
TMP_USER_PASSWORD=123
TMP_HOST_NAME=spark-master

echo "DEBIAN_VERSION="$DEBIAN_VERSION

# echo deb https://download.ceph.com/debian-luminous/ $DEBIAN_VERSION main | sudo tee /etc/apt/sources.list.d/ceph.list

apt update && apt install -y wget  sshpass whois &&  \
    echo deb https://download.ceph.com/debian-luminous/ $DEBIAN_VERSION main | tee /etc/apt/sources.list.d/ceph.list && \
    apt install apt-transport-https && \
    wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add - && \
    apt update && apt install -y ceph-deploy openssh-server

cat /dev/zero | ssh-keygen -q -N "" &&  service ssh start && \
    useradd $TMP_USER -d /home/$TMP_USER  -m -p `mkpasswd $TMP_USER_PASSWORD` && sshpass -p "$TMP_USER_PASSWORD"  ssh-copy-id $TMP_USER@$TMP_HOST_NAME && \
    printf "%s\n    %s\n    %s\n" "Host $TMP_HOST_NAME" "Hostname $TMP_HOST_NAME" "User $TMP_USER"  >> ~/.ssh/config

ceph-deploy install --release luminous $TMP_HOST_NAME
