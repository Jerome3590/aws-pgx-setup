#!/bin/bash

set -x -e

# Check whether we're running on the main node
main_node=false
if grep isMaster /mnt/var/lib/info/instance.json | grep true;
then
  main_node=true
fi

# update everything
sudo yum update -y

# install some additional R and R package dependencies
sudo yum install -y bzip2-devel cairo-devel \
     gcc gcc-c++ gcc-gfortran libXt-devel cmake \
     libcurl-devel libjpeg-devel libpng-devel \
     pango-devel pango libicu-devel wget git \
     libtiff-devel pcre2-devel readline-devel jq \
     texinfo texlive-collection-fontsrecommended 

# making sure all system packages install correctly before changing to aws yum repository     
if [ $? -ne 0 ]; then
  echo "An error occurred while installing the R dependencies. Exiting."
  exit 1
fi

# install arrow for AWS Linux 2
sudo amazon-linux-extras install -y epel
sudo yum install -y https://apache.jfrog.io/artifactory/arrow/amazon-linux/2/apache-arrow-release-latest.rpm
sudo yum install -y --enablerepo=epel arrow-devel # For C++
sudo yum install -y --enablerepo=epel arrow-glib-devel # For GLib (C)
sudo yum install -y --enablerepo=epel arrow-dataset-devel # For Apache Arrow Dataset C++
sudo yum install -y --enablerepo=epel arrow-dataset-glib-devel # For Apache Arrow Dataset GLib (C)
sudo yum install -y --enablerepo=epel parquet-devel # For Apache Parquet C++
sudo yum install -y --enablerepo=epel parquet-glib-devel # For Apache Parquet GLib (C)
sudo yum install -y --enablerepo=epel udunits2-devel # For Geospatial R 'sf' library



# Set some R environment variables for EMR
cat << 'EOF' > /tmp/Renvextra
HADOOP_HOME_WARN_SUPPRESS="true"
HADOOP_HOME="/usr/lib/hadoop"
HADOOP_PREFIX="/usr/lib/hadoop"
HADOOP_MAPRED_HOME="/usr/lib/hadoop-mapreduce"
HADOOP_YARN_HOME="/usr/lib/hadoop-yarn"
HADOOP_COMMON_HOME="/usr/lib/hadoop"
HADOOP_HDFS_HOME="/usr/lib/hadoop-hdfs"
YARN_HOME="/usr/lib/hadoop-yarn"
HADOOP_CONF_DIR="/usr/lib/hadoop/etc/hadoop/"
YARN_CONF_DIR="/usr/lib/hadoop/etc/hadoop/"
HIVE_HOME="/usr/lib/hive"
HIVE_CONF_DIR="/usr/lib/hive/conf"
HBASE_HOME="/usr/lib/hbase"
HBASE_CONF_DIR="/usr/lib/hbase/conf"
SPARK_HOME="/usr/lib/spark"
SPARK_CONF_DIR="/usr/lib/spark/conf"
# GITHUB_PAT should be set via environment variables from secure sources
PATH="${PWD}:/usr/local/bin:${PATH}"
EOF


# Download, verify checksum, and install RStudio Server
# Only install / start RStudio on the main node
if [ "$main_node" = true ]; then
	  sudo chmod -R 777 /home
    sudo aws s3 sync s3://pgx-repository/ade-risk-model/ /home/hadoop/

fi

# Set password for hadoop user for R Studio
sudo sh -c "echo '$rspasswd' | passwd hadoop --stdin"


PYTHON="$(which python3)"
sudo $PYTHON -m pip install --upgrade pip
sudo $PYTHON -m pip install boto3 ec2-metadata pyarrow pyspark
sudo $PYTHON -m pip install fuzzywuzzy[speedup]
sudo $PYTHON -m pip install plotly
sudo chmod -R 777 /home
