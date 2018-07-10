# k8s-ceph

# Setup

## Install k8s with flannel network
 - [Setup kubeadm](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/)
 - [Setup k8s](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/)

## Install ceph
 - [Single node installation](http://palmerville.github.io/2016/04/30/single-node-ceph-install.html) - params for single node and fixe permission on *keyring file
 - [Installing specific version of ceph](http://docs.ceph.com/docs/master/rados/deployment/ceph-deploy-install/#install)
 - [Official installation guide](http://docs.ceph.com/docs/master/start/quick-ceph-deploy/)
 - [Ceph cheatsheet](http://rebirther.ru/blog/ceph-spargalka)

## Ceph setting
 - [Allow ceph's dasboard](http://docs.ceph.com/docs/master/mgr/dashboard/)
 - [Add osds with ceph-deploy](http://docs.ceph.com/docs/master/rados/deployment/ceph-deploy-osd/) Warning! **Whole disk is used**
 - [Prepare OSDs manually with ceph-volume](http://docs.ceph.com/docs/master/ceph-volume/lvm/prepare/)
 - [Activate OSDs manually with ceph-volume](http://docs.ceph.com/docs/master/ceph-volume/lvm/activate/)
 - [Create and mount CephFS](http://docs.ceph.com/docs/master/start/quick-cephfs/#create-a-filesystem)

## LVM
 - [info about lvm](https://habrahabr.ru/post/67283/)

## NTP

#### Install
```bash
sudo apt-get update
sudo apt-get install ntpdate ntp
```

#### Configuration
- [conf](https://www.thegeekstuff.com/2014/06/linux-ntp-server-client/)

#### Extra commands
```bash
ntpdate -u <host> #The ntpdate command can be used to set the local date and time by polling the NTP server. Typically, you’ll have to do this only one time.
```

****

## k8s + ceph
### RBD storage
#### Working links

 - [bug zilla](https://bugzilla.redhat.com/show_bug.cgi?id=1460275) 
 befort create ceph image run this command on ceph-mon node
```bash
rbd create --image ceph-image --size 2G --image-feature layering
```
 - [example](https://access.redhat.com/documentation/en-us/openshift_container_platform/3.5/html-single/installation_and_configuration/#using-ceph-rbd-installing-the-ceph-common-package)

#### Installing the ceph-common

Installing the ceph-common Package The ceph-common library must be installed on all schedulable OpenShift Container Platform nodes: 
```bash
yum install -y ceph-common
```

#### Creating the Ceph Secret 
The **ceph auth get-key** command is run on a Ceph **MON** node to display the key value for the **client.admin user**: 

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ceph-secret
data:
  key: QVFBOFF2SlZheUJQRVJBQWgvS2cwT1laQUhPQno3akZwekxxdGc9PQ== #1
```
**1** 
This base64 key is generated on one of the Ceph MON nodes using the **ceph auth get-key client.admin | base64** command, then copying the output and pasting it as the secret key’s value. 

Save the secret definition to a file, for example ceph-secret.yaml, then create the secret:
```bash
$ oc create -f ceph-secret.yaml
secret "ceph-secret" created
```

Verify that the secret was created: 
```bash
# oc get secret ceph-secret
NAME          TYPE      DATA      AGE
ceph-secret   Opaque    1         23d
```
#### Creating the Persistent Volume 

Next, before creating the PV object in OpenShift Container Platform, define the persistent volume file: 
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ceph-pv     #1
spec:
  capacity:
    storage: 2Gi    #2
  accessModes:
    - ReadWriteOnce #3
  rbd:              #4
    monitors:       #5
      - 192.168.122.133:6789
    pool: rbd
    image: ceph-image
    user: admin
    secretRef:
      name: ceph-secret #6
    fsType: ext4        #7
    readOnly: false
  persistentVolumeReclaimPolicy: Recycle
```

**1**
    The name of the PV, which is referenced in pod definitions or displayed in various oc volume commands.

**2**
    The amount of storage allocated to this volume.

**3**
    accessModes are used as labels to match a PV and a PVC. They currently do not define any form of access control. All block storage is defined to be single user (non-shared storage).

**4**
    This defines the volume type being used. In this case, the rbd plug-in is defined.

**5**
    This is an array of Ceph monitor IP addresses and ports.

**6**
    This is the Ceph secret, defined above. It is used to create a secure connection from OpenShift Container Platform to the Ceph server.

**7**
    This is the file system type mounted on the Ceph RBD block device.

Save the PV definition to a file, for example ceph-pv.yaml, and create the persistent volume: 
```bash
# oc create -f ceph-pv.yaml
persistentvolume "ceph-pv" created
```

Verify that the persistent volume was created: 
```bash
# oc get pv
NAME                     LABELS    CAPACITY     ACCESSMODES   STATUS      CLAIM     REASON    AGE
ceph-pv                  <none>    2147483648   RWO           Available                       2s
```

####  Creating the Persistent Volume Claim

Creating the Persistent Volume Claim A persistent volume claim (PVC) specifies the desired access mode and storage capacity. Currently, based on only these two attributes, a PVC is bound to a single PV. Once a PV is bound to a PVC, that PV is essentially tied to the PVC’s project and cannot be bound to by another PVC. There is a one-to-one mapping of PVs and PVCs. However, multiple pods in the same project can use the same PVC. 
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ceph-claim
spec:
  accessModes:     #1
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi #2
```
**1**
    As mentioned above for PVs, the accessModes do not enforce access right, but rather act as labels to match a PV to a PVC.

**2**
    This claim will look for PVs offering 2Gi or greater capacity.


Save the PVC definition to a file, for example ceph-claim.yaml, and create the PVC: 

```bash
# oc create -f ceph-claim.yaml
persistentvolumeclaim "ceph-claim" created

#and verify the PVC was created and bound to the expected PV:
# oc get pvc
NAME         LABELS    STATUS    VOLUME    CAPACITY   ACCESSMODES   AGE
ceph-claim   <none>    Bound     ceph-pv   1Gi        RWX           21s
```

#### Creating the Pod
Creating the Pod A pod definition file or a template file can be used to define a pod. Below is a pod specification that creates a single container and mounts the Ceph RBD volume for read-write access: 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ceph-pod1           #1
spec:
  containers:
  - name: ceph-busybox
    image: busybox          #2
    command: ["sleep", "60000"]
    volumeMounts:
    - name: ceph-vol1       #3
      mountPath: /usr/share/busybox #4
      readOnly: false
  volumes:
  - name: ceph-vol1         #5
    persistentVolumeClaim:
      claimName: ceph-claim #6
```
**1**
    The name of this pod as displayed by oc get pod.

**2**
    The image run by this pod. In this case, we are telling busybox to sleep.

**3** **5**
    The name of the volume. This name must be the same in both the containers and volumes sections.

**4**
    The mount path as seen in the container.

**6**
    The PVC that is bound to the Ceph RBD cluster.


Save the pod definition to a file, for example ceph-pod1.yaml, and create the pod: 

```bash
# oc create -f ceph-pod1.yaml
pod "ceph-pod1" created

#verify pod was created
# oc get pod
NAME        READY     STATUS    RESTARTS   AGE
ceph-pod1   1/1       Running   0          2m
```

### CephFS

[k8s official example](https://github.com/kubernetes/examples/tree/master/staging/volumes/cephfs/)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cephfs2
spec:
  containers:
  - name: cephfs-rw
    image: kubernetes/pause
    volumeMounts:
    - mountPath: "/mnt/cephfs" #1
      name: cephfs
  volumes:
  - name: cephfs
    cephfs:
      monitors: #2
      - 10.16.154.78:6789
      - 10.16.154.82:6789
      - 10.16.154.83:6789
      user: admin #3
      secretRef: #4
        name: ceph-secret
      readOnly: true #5
      path: "/" #6
```

**1**
Path inside container

**2**
Array of Ceph monitors.

**3**
The RADOS user name. If not provided, default admin is used.

**4**
Reference to Ceph authentication secrets. If provided, secret overrides secretFile.

**5**
Whether the filesystem is used as readOnly.

**6**
Used as the mounted root, rather than the full Ceph tree. If not provided, default / is used.

Optional param: **secretFile**: The path to the keyring file. If not provided, default /etc/ceph/user.secret is used.

Now you can see pod with name **cephfs-rw**
```bash
kubectl get pods
```

#### CephFS + StatefulSet(k8s API)

[StatefulSet k8s example](https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/)

##### Prerequisite
You must create storage class from this [kubernetes/examples/staging/volumes/cephfs](https://github.com/kubernetes-incubator/external-storage/tree/master/ceph/cephfs) repo. Use rbac [deployment](https://github.com/kubernetes-incubator/external-storage/tree/master/ceph/cephfs/deploy/rbac) for k8s >= 1.9. Ensure that all components are in the **same namespace**.

#####  Constraints
 - Critical
   - Ensure that all components are in the **same namespace**

##### StatefulSet Example

For example we use namespace **cephfs**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: cephfs #1
spec:
  selector:
    matchLabels:
      app: mysql
  serviceName: mysql
  replicas: 2 #2
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: busybox
        command: ["sleep", "60000"]
        volumeMounts:
        - name: data
          mountPath: /usr/share/busybox
  volumeClaimTemplates: #3
  - metadata:
      name: data
    spec:
      storageClassName: cephfs #4
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

**1**
Use the same namespace that you use in **Prerequisite** section.

**2**
Two instances of service will be created.

**3**
In this section you can see dynamic creating of ceph's volumes for k8s containers.

**4**
StorageClass was created in **Prerequisite** section.

****

## Ceph 12.2.x

#### Constraints
 - Critical
   - Ceph's user can't be named with username **ceph**

#### Allow application to use poll
After creating a pool you must allow application that can access to this pool
Applications:
- cephfs
- rdb
- rgw
```bash
ceph osd pool application enable <app> <pool>
```
#### Allow dashboard
```bash
# allow dasboard
ceph mgr module enable dashboard

# ip adn port
ceph config-key set mgr/dashboard/server_addr $IP
ceph config-key set mgr/dashboard/server_port $PORT

# reverse proxes
ceph config-key set mgr/dashboard/url_prefix $PREFIX
```

#### Deploy Ceph's OSDs on disk partition with ceph-volume(for 12.2.x +)
```bash
# install lvm packages
apt-get install lvm2

# copy ceph's client.bootstrap-osd key from file ceph.bootstrap-osd.keyring to /var/lib/ceph/bootstrap-osd/ceph.keyring
# For example:
pwd
#output:
#    /home/zagrebaev/my-cluster
cp ceph.bootstrap-osd.keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
```
For example, we have unused /dev/sdd device. Let's create OSDs on /dev/sdd2.
Firstly, we need to parted this device:

[Prepare. Official doc](http://docs.ceph.com/docs/master/ceph-volume/lvm/prepare/)
```bash
# create GPT partition table on /dev/sdd device
parted --script /dev/sdd mklabel gpt

# create /dev/sdd1
parted --script /dev/sdd mkpart primary 1 20%

# create /dev/sdd2
parted --script /dev/sdd mkpart primary 20% 100%

#prepare osd
ceph-volume lvm prepare --bluestore --data /dev/sdd2
```

Secondly, we need to activate OSD. For example, the above command created osd.2

[Activate. Official doc](http://docs.ceph.com/docs/master/ceph-volume/lvm/activate/)
```bash
# get  OSD uuid from file osd_fsid
cat /var/lib/ceph/osd/ceph-2/fsid
# Example output:
    7e6a5fdd-e0d4-4b4b-b21b-0b72d41177c1

# Activate osd.2. Coomand: ceph-volume lvm activate --bluestore $OSD_ID  $OSD_UIID
ceph-volume lvm activate --bluestore 2 7e6a5fdd-e0d4-4b4b-b21b-0b72d41177c1
```
We created OSD!

****

## Monitoring cluster

Deploy [monitoring server](https://github.com/kubernetes-incubator/metrics-server/blob/master/README.md)
 ```bash
git clone https://github.com/kubernetes-incubator/metrics-server.git
cd metrics-server
kubectl create -f deploy/
```

Deploy [Heapster](https://github.com/kubernetes/heapster)

**Note:**
 - Check manually latest images in yaml files.
 - Check file [deploy/kube-config/influxdb/grafana.yaml](https://github.com/DmitryZagr/heapster/blob/cephfs_storage/deploy/kube-config/influxdb/grafana.yaml) to access grafana dashboard.You can access grafana dashboard on 3000 host port.
 ```bash
git clone https://github.com/DmitryZagr/heapster.git
cd heapster
git checkout cephfs_storage
kubectl create -f deploy/kube-config/rbac/
kubectl create -f deploy/kube-config/influxdb/
```

****

## Extra Info

### Ubuntu 16.04
 [**Update kernel to latest version**](https://askubuntu.com/questions/944842/kernel-4-10-in-ubuntu-16-04-3-update/944955)
 ```bash
sudo apt install --install-recommends linux-image-generic-hwe-16.04
```

### Docker

[**How do I change the Docker image installation directory?**](https://forums.docker.com/t/how-do-i-change-the-docker-image-installation-directory/1169)

Using a symlink is another method to change image storage.

Caution - These steps depend on your current ```/var/lib/docker``` being an actual directory (not a symlink to another location).

Stop docker: ```service docker stop```. Verify no docker process is running ```ps faux```
Double check docker really isn’t running. Take a look at the current docker directory: ```ls /var/lib/docker/```
2b) Make a backup - ```tar -zcC /var/lib docker > /mnt/pd0/var_lib_docker-backup-$(date +%s).tar.gz```
Move the ```/var/lib/docker``` directory to your new partition: ```mv /var/lib/docker /mnt/pd0/docker```
Make a symlink:  ``` ln -s /mnt/pd0/docker /var/lib/docker ```
Take a peek at the directory structure to make sure it looks like it did before the mv: ```ls /var/lib/docker/``` (note the trailing slash to resolve the symlink)
Start docker back up ```service docker start```
restart your containers

****

## Testing env

### Single node

| OC                 |      ceph     |  k8s    |k8s pod network|  kernel version |
|:------------------:|:-------------:|:-------:|:-------------:|:---------------:|
| Ubuntu 16.04 LTS   |     10.2.10   | 1.9.0   |     Calico    |                 |
| Ubuntu 16.04 LTS   |     12.2.2    | 1.9.1   |     Calico    |4.13.0-32-generic|
| Ubuntu 16.04 LTS   |     12.2.2    | 1.9.2   |     Calico    |4.13.0-32-generic|
| Ubuntu 16.04 LTS   |     12.2.2    | 1.9.3   |     Calico    |4.13.0-32-generic|

### Multi node
| OC                 |      ceph     |  k8s    |k8s pod network |  kernel version |
|:------------------:|:-------------:|:-------:|:--------------:|:---------------:|
| Ubuntu 16.04 LTS   |     12.2.2    | 1.9.2   |Flannel v.0.10.0|4.13.0-32-generic|
| Ubuntu 16.04 LTS   |     12.2.2    | 1.9.3   |Flannel v.0.10.0|4.13.0-32-generic|
| Ubuntu 16.04 LTS   |     12.2.4    | 1.9.6   |Flannel v.0.10.0|4.13.0-37-generic|
