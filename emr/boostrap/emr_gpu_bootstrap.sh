#!/bin/bash

set -x -e

sudo mkdir -p /spark-rapids-cgroup/devices
sudo mount -t cgroup -o devices cgroupv1-devices /spark-rapids-cgroup/devices
sudo chmod a+rwx -R /spark-rapids-cgroup

sudo pip install numpy requests networkx boto3 pandas matplotlib
