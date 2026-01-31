#!/bin/bash

set -x -e

# Desired R release version
rver=4.3.2

# Desired R Studio package
rspkg=rstudio-server-rhel-2023.12.0-369-x86_64.rpm

# Password for R Studio user "hadoop"
rspasswd=Trick90**ZX#

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

# Compile R from source; install to /usr/local/*
mkdir /tmp/R-build
cd /tmp/R-build
curl -OL https://cran.r-project.org/src/base/R-4/R-$rver.tar.gz
tar -xzf R-$rver.tar.gz
cd R-$rver
./configure --with-readline=yes --enable-R-profiling=no --enable-memory-profiling=no --enable-R-shlib --with-pic --prefix=/usr/local --with-x --with-libpng --with-jpeglib --with-cairo --enable-R-shlib --with-recommended-packages=yes
make -j 8
sudo make install

# Set some R environment variables for EMR
cat << 'EOF' > /tmp/Renvextra
JAVA_HOME="/etc/alternatives/jre"
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
PYSPARK_PYTHON="/usr/local/bin/python3.9"
EOF
cat /tmp/Renvextra | sudo tee -a /usr/local/lib64/R/etc/Renviron

# Reconfigure R Java support before installing packages
sudo /usr/local/bin/R CMD javareconf

# Download, verify checksum, and install RStudio Server
# Only install / start RStudio on the main node
if [ "$main_node" = true ]; then
    curl -OL https://download2.rstudio.org/server/centos7/x86_64/$rspkg
    sudo mkdir -p /etc/rstudio
    sudo sh -c "echo 'auth-minimum-user-id=100' >> /etc/rstudio/rserver.conf"
    sudo yum install -y $rspkg
    sudo rstudio-server start
	sudo chmod -R 777 /home/hadoop/
    sudo aws s3 sync s3://pgx-terraform/projects/pgx/PGx_Predictive_Model/ADE_Risk_Model/ /home/hadoop/

fi

# Set password for hadoop user for R Studio
sudo sh -c "echo '$rspasswd' | passwd hadoop --stdin"

# Install R packages
sudo /usr/local/bin/R --no-save <<R_SCRIPT
Sys.setenv(TZ='Etc/UCT')
install.packages(c('tidyverse','aws.s3','aws.signature','aws.ec2metadata','here','stringr','magrittr'),
repos="http://cran.rstudio.com")
install.packages(c('reticulate','rmarkdown','jsonlite','dplyr'), 
repos="http://cran.rstudio.com")
install.packages(c('sparklyr','DBI','dbplot','scales','ggplot2'),
repos="http://cran.rstudio.com")
R_SCRIPT

# Python environment
wget https://www.python.org/ftp/python/3.9.16/Python-3.9.16.tgz
tar xzf Python-3.9.16.tgz

# Install Python 3.9.16
cd Python-3.9.16
./configure --enable-optimizations --prefix=/usr/local --enable-shared
sudo make altinstall

export PATH="/usr/local/bin:$PATH"
echo '/usr/local/lib' | sudo tee /etc/ld.so.conf.d/python3.9.conf
sudo ldconfig

PYTHON="$(which python3.9)"
# Setup Python 3.9 Pip to install future dependencies added
sudo $PYTHON -m pip install --upgrade pip
sudo $PYTHON -m pip install boto3 ec2-metadata pyarrow pyspark pandas shap catboost matplotlib scikit-learn optuna awswrangler