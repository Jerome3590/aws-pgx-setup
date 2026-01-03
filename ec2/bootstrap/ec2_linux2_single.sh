#!/bin/bash
set -euxo pipefail

yum groupinstall "Development Tools" -y

# Idempotent AWS CLI Installation
if ! command -v aws &>/dev/null; then
    echo "Installing AWSCLI2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm awscliv2.zip
    rm -rf aws/
fi

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
SENDER="jerome@mushinsolutions.com"
RECIPIENT="dixonrj@vcu.edu"
AWS_REGION="us-east-1"

send_email() {
    local SUBJECT="$1"
    local BODY="$2"
    aws ses send-email \
        --from "$SENDER" \
        --destination "ToAddresses=$RECIPIENT" \
        --message "Subject={Data=$SUBJECT},Body={Text={Data=$BODY}}" \
        --region "$AWS_REGION"
}

send_email_on_error() {
    local subject="$1"
    local message="$2"
    send_email "$subject" "$message"
}

error_handler() {
    send_email_on_error "Install Failed on $INSTANCE_ID" "The installation failed at: $BASH_COMMAND"
    exit 1
}

trap 'error_handler' ERR

send_email "Script Started on $INSTANCE_ID" "The bootstrap script has successfully started execution on instance: $INSTANCE_ID."

# OpenSSL Setup
if [ ! -d "/usr/local/openssl" ]; then
    cd /usr/local
    wget https://www.openssl.org/source/openssl-1.1.1q.tar.gz
    tar xzf openssl-1.1.1q.tar.gz
    cd openssl-1.1.1q
    ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib
    make
    make install
    echo "/usr/local/openssl/lib" | tee -a /etc/ld.so.conf.d/openssl-1.1.1q.conf
    ldconfig
    rm /usr/local/openssl-1.1.1q.tar.gz
    rm -rf /usr/local/openssl-1.1.1q
fi

send_email "OpenSSL Installed on $INSTANCE_ID" "Starting R/RStudio install..."

# Create and set permissions for DUCKDB Local Directory if not already exists
if [ ! -d "/home/.duckdb/" ]; then
    mkdir -p /home/.duckdb/
    chmod 777 /home/.duckdb/
fi


# Install DuckDB
curl https://install.duckdb.org | sh


export PATH=/usr/local/openssl/bin:/root/.duckdb/cli/latest:$PATH
export LD_LIBRARY_PATH=/usr/local/openssl/lib
export CPPFLAGS="-I/usr/local/openssl/include"
export LDFLAGS="-L/usr/local/openssl/lib"

# R Installation/Setup
cd /usr/local
rver=4.4.3
rspkg=rstudio-server-rhel-2023.12.0-369-x86_64.rpm
rspasswd=Trick90**ZX#
USER="pgx3874"
TARGET_DIR="/home/$USER/"
adduser $USER
mkdir -p $TARGET_DIR
chmod -R 777 $TARGET_DIR
chown -R $USER:$USER $TARGET_DIR
sh -c "echo '$rspasswd' | passwd pgx3874 --stdin"
usermod -aG wheel "$USER"
yum update -y
yum install -y bzip2-devel cairo-devel \
     gcc gcc-c++ gcc-gfortran libXt-devel cmake \
     libcurl-devel libjpeg-devel libpng-devel \
     pango-devel pango libicu-devel wget git \
     libtiff-devel pcre2-devel readline-devel jq \
     texinfo texlive-collection-fontsrecommended \
	   xz-devel libxml2-devel zlib-devel libcurl-devel
amazon-linux-extras install -y epel
yum install -y https://apache.jfrog.io/artifactory/arrow/amazon-linux/2/apache-arrow-release-latest.rpm
yum install -y --enablerepo=epel arrow-devel 
yum install -y --enablerepo=epel arrow-glib-devel 
yum install -y --enablerepo=epel arrow-dataset-devel 
yum install -y --enablerepo=epel arrow-dataset-glib-devel 
yum install -y --enablerepo=epel parquet-devel 
yum install -y --enablerepo=epel parquet-glib-devel 
yum install -y --enablerepo=epel udunits2-devel
amazon-linux-extras enable corretto8
yum install -y java-1.8.0-amazon-corretto-devel
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-amazon-corretto/
mkdir /tmp/R-build
cd /tmp/R-build
curl -OL https://cran.r-project.org/src/base/R-4/R-$rver.tar.gz
tar -xzf R-$rver.tar.gz
cd R-$rver
./configure --with-readline=yes --enable-R-profiling=no --enable-memory-profiling=no \
  --enable-R-shlib --with-pic --prefix=/usr/local --with-x --with-libpng --with-jpeglib \
  --with-cairo --with-recommended-packages=yes
make -j 8
make install
cat << 'EOF' > /tmp/Renvextra
JAVA_HOME="/usr/lib/jvm/java-1.8.0-amazon-corretto/"
GITHUB_PAT="ghp_[REMOVED]"
LD_LIBRARY_PATH=$OPENSSL_PREFIX/lib:$LD_LIBRARY_PATH
PKG_CONFIG_PATH=$OPENSSL_PREFIX/lib/pkgconfig
PATH="${PWD}:/usr/local/bin:${PATH}"
EOF
cat /tmp/Renvextra |  tee -a /usr/local/lib64/R/etc/Renviron
/usr/local/bin/R CMD javareconf

send_email "R Installed on $INSTANCE_ID" "R version $rver has been successfully compiled and installed on instance: $INSTANCE_ID."

# Install/Start RStudio Server
curl -OL https://download2.rstudio.org/server/centos7/x86_64/$rspkg
mkdir -p /etc/rstudio
sh -c "echo 'auth-minimum-user-id=100' >> /etc/rstudio/rserver.conf"
yum install -y $rspkg
rstudio-server start
/usr/local/bin/R --no-save <<R_SCRIPT
Sys.setenv(TZ='Etc/UCT')
install.packages(c('reticulate','rmarkdown','caret','purrr','dplyr','tidyr','here', 'deSolve','ggplot2'), repos="http://cran.rstudio.com")
install.packages('bupaverse')
R_SCRIPT

send_email "RStudio Server Installed on $INSTANCE_ID" "RStudio Server has been successfully installed and started on instance: $INSTANCE_ID."


# AWS CLI Installation
if ! command -v aws &>/dev/null; then
    echo "Installing AWSCLI2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm awscliv2.zip
    rm -rf aws/
fi

# Set AWS CLI v2 as default if not already
if [ -f "/usr/local/bin/aws" ]; then
    sudo ln -sf /usr/local/bin/aws /bin/aws
fi


# Python Installation/Setup
cd /usr/local
sudo yum -y install sqlite-devel gdbm-devel libdb-devel libffi-devel bzip2-devel xz-devel ncurses-devel readline-devel tk-devel
wget https://www.python.org/ftp/python/3.11.9/Python-3.11.9.tgz
tar xzf Python-3.11.9.tgz
cd Python-3.11.9
./configure --with-openssl=/usr/local/openssl --enable-optimizations --prefix=/usr/local --enable-shared
make
sudo make altinstall
export PATH="/usr/local/bin:$PATH"
echo '/usr/local/lib' |  tee /etc/ld.so.conf.d/python3.11.conf
ldconfig
PYTHON="$(which python3.11)"
$PYTHON -m pip install --upgrade pip
$PYTHON -m pip install boto3 ec2-metadata pyarrow pandas==2.2.3 scikit-learn dtaidistance tslearn 
$PYTHON -m pip install duckdb fsspec s3fs kneed numpy==1.26.4 opencv-python optuna Pillow catboost 
$PYTHON -m pip install anytree imblearn jupyterlab minds-kit namedlist notebook
$PYTHON -m pip install pysmt python-sat scipy torch torchvision tqdm tslearn wittgenstein xgboost
$PYTHON -m pip install matplotlib shap lime mlxtend
$PYTHON -m ipykernel install --name python311 --display-name "Python 3.11"

# Set Python 3.11 as default
sudo ln -sf /usr/local/bin/python3.11 /usr/bin/python3
sudo ln -sf /usr/local/bin/pip3.11 /usr/bin/pip3

send_email "Python Installed on $INSTANCE_ID" "Python 3.11 with AWSCLI V2 successfully installed on instance: $INSTANCE_ID."

# CloudWatch Setup
if [ ! -f /opt/aws/amazon-cloudwatch-agent/bin/config.json ]; then
    yum install -y amazon-cloudwatch-agent
    chmod 777 /opt/aws/amazon-cloudwatch-agent/bin/
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
    cat <<EOF > /opt/aws/amazon-cloudwatch-agent/bin/config.json
    {
        "agent": {
            "metrics_collection_interval": 60,
            "run_as_user": "cwagent"
        },
        "metrics": {
            "append_dimensions": {
                "InstanceId": "$INSTANCE_ID",
                "InstanceType": "$INSTANCE_TYPE"
            },
            "metrics_collected": {
                "cpu": {
                    "measurement": [
                        "cpu_usage_idle",
                        "cpu_usage_iowait",
                        "cpu_usage_user",
                        "cpu_usage_system",
                        "cpu_usage_steal",
                        "cpu_usage_nice",
                        "cpu_usage_guest",
                        "cpu_usage_guest_nice",
                        "cpu_usage_irq",
                        "cpu_usage_softirq"
                    ],
                    "metrics_collection_interval": 60,
                    "totalcpu": true
                },
                "disk": {
                    "measurement": [
                        "used_percent",
                        "inodes_free"
                    ],
                    "metrics_collection_interval": 60,
                    "resources": [
                        "/"
                    ]
                },
                "diskio": {
                    "measurement": [
                        "io_time",
                        "write_bytes",
                        "read_bytes",
                        "writes",
                        "reads"
                    ],
                    "metrics_collection_interval": 60,
                    "resources": [
                        "/"
                    ]
                },
                "mem": {
                    "measurement": [
                        "mem_used_percent",
                        "active",
                        "available",
                        "available_percent",
                        "total",
                        "used",
                        "buffered",
                        "cached",
                        "free"
                    ],
                    "metrics_collection_interval": 60
                },
                "swap": {
                    "measurement": [
                        "swap_used_percent"
                    ],
                    "metrics_collection_interval": 60
                }
            }
        }
    }
EOF
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
    id cwagent || useradd cwagent
fi

# Sync files from S3 to local directory
aws s3 sync s3://pgx-repository/opioid-ed-visit-risk-model/ "$TARGET_DIR/opioid-ed-visit-risk-model/"
aws s3 sync s3://pgx-repository/ade-risk-model/ "$TARGET_DIR/ade-risk-model/"
aws s3 sync s3://pgx-repository/pgx-datasets/ "$TARGET_DIR/pgx-datasets/"

sudo chmod -R 777 "$TARGET_DIR/"

send_email "Notebook Files synced to $TARGET_DIR" "Allocating IP address..."

# Allocate Elastic IP
allocation_id=$(aws ec2 describe-addresses \
  --query "Addresses[?AssociationId==null].[AllocationId]" \
  --output text \
  --region "$AWS_REGION" | awk '{print $1}')
  
instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  
aws ec2 associate-address \
  --instance-id "$instance_id" \
  --allocation-id "$allocation_id" \
  --allow-reassociation \
  --region "$AWS_REGION"
  
elastic_ip=$(aws ec2 describe-addresses \
  --allocation-ids "$allocation_id" \
  --query "Addresses[0].PublicIp" \
  --output text \
  --region "$AWS_REGION")

# Send email if RStudio is active
if systemctl is-active --quiet rstudio-server; then
    send_email "Bootstrap Completed on $instance_id" "RStudio Server is fully running and ready for analysis at: http://$elastic_ip:8787"
fi
