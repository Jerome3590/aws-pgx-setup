#!/bin/bash
# Compile R + RStudio Server + bupaverse. Run only when a job calls R
# (BupaR / r_helpers). Default pgx sessions skip this (INSTALL_R=0).
#
#   sudo bash install_r_rstudio.sh
#   INSTALL_R=1 AWS_PROFILE=mushin bash launch_pgx_session.sh
#
# Optional: RSTUDIO_PASSWORD=... for the pgx3874 RStudio login.
set -euxo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id || echo unknown)}"
SENDER="${SENDER:-jerome@mushinsolutions.com}"
RECIPIENT="${RECIPIENT:-dixonrj@vcu.edu}"

if [[ -x /usr/local/bin/R ]] && command -v rstudio-server >/dev/null 2>&1; then
  echo "R and RStudio already installed; skipping"
  exit 0
fi

if ! declare -F send_email >/dev/null; then
  send_email() {
    local SUBJECT="$1"
    local BODY="$2"
    aws ses send-email \
      --from "$SENDER" \
      --destination "ToAddresses=$RECIPIENT" \
      --message "Subject={Data=$SUBJECT},Body={Text={Data=$BODY}}" \
      --region "$AWS_REGION" || true
  }
fi

rver=4.4.3
rspkg=rstudio-server-rhel-2023.12.0-369-x86_64.rpm
USER_NAME="pgx3874"
if ! id "$USER_NAME" >/dev/null 2>&1; then
  adduser "$USER_NAME"
  mkdir -p "/home/$USER_NAME"
  chmod -R 777 "/home/$USER_NAME"
  chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME"
  usermod -aG wheel "$USER_NAME"
fi
if [[ -n "${RSTUDIO_PASSWORD:-}" ]]; then
  echo "$RSTUDIO_PASSWORD" | passwd "$USER_NAME" --stdin
fi

send_email "Starting R/RStudio on $INSTANCE_ID" "Compiling R $rver because this session called R scripts (BupaR / r_helpers)."

yum update -y
yum install -y bzip2-devel cairo-devel \
     gcc gcc-c++ gcc-gfortran libXt-devel cmake \
     libcurl-devel libjpeg-devel libpng-devel \
     pango-devel pango libicu-devel wget git \
     libtiff-devel pcre2-devel readline-devel jq \
     texinfo texlive-collection-fontsrecommended \
     xz-devel libxml2-devel zlib-devel libuv-devel
amazon-linux-extras install -y epel
yum install -y https://apache.jfrog.io/artifactory/arrow/amazon-linux/2/apache-arrow-release-latest.rpm
yum install -y --enablerepo=epel arrow-devel \
     arrow-glib-devel arrow-dataset-devel arrow-dataset-glib-devel \
     parquet-devel parquet-glib-devel udunits2-devel
amazon-linux-extras enable corretto8
yum install -y java-1.8.0-amazon-corretto-devel
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-amazon-corretto/

if [[ ! -x /usr/local/bin/R ]]; then
  mkdir -p /tmp/R-build
  cd /tmp/R-build
  curl -OL "https://cran.r-project.org/src/base/R-4/R-$rver.tar.gz"
  tar -xzf "R-$rver.tar.gz"
  cd "R-$rver"
  ./configure --with-readline=yes --enable-R-profiling=no --enable-memory-profiling=no \
    --enable-R-shlib --with-pic --prefix=/usr/local --with-x --with-libpng --with-jpeglib \
    --with-cairo --with-recommended-packages=yes
  make -j "$(nproc)"
  make install
  cat << 'EOF' > /tmp/Renvextra
JAVA_HOME="/usr/lib/jvm/java-1.8.0-amazon-corretto/"
LD_LIBRARY_PATH=$OPENSSL_PREFIX/lib:$LD_LIBRARY_PATH
PKG_CONFIG_PATH=$OPENSSL_PREFIX/lib/pkgconfig
PATH="${PWD}:/usr/local/bin:${PATH}"
EOF
  tee -a /usr/local/lib64/R/etc/Renviron < /tmp/Renvextra
  /usr/local/bin/R CMD javareconf
  send_email "R Installed on $INSTANCE_ID" "R $rver compiled on $INSTANCE_ID."
fi

if ! command -v rstudio-server >/dev/null 2>&1; then
  cd /tmp
  curl -OL "https://download2.rstudio.org/server/centos7/x86_64/$rspkg"
  mkdir -p /etc/rstudio
  grep -q 'auth-minimum-user-id=100' /etc/rstudio/rserver.conf 2>/dev/null \
    || echo 'auth-minimum-user-id=100' >> /etc/rstudio/rserver.conf
  yum install -y "$rspkg"
  rstudio-server start
fi

/usr/local/bin/R --no-save <<'R_SCRIPT'
Sys.setenv(TZ='Etc/UCT')
install.packages(c('reticulate','rmarkdown','caret','purrr','dplyr','tidyr','here', 'deSolve','ggplot2'), repos="http://cran.rstudio.com")
install.packages('bupaverse', repos="http://cran.rstudio.com")
R_SCRIPT

send_email "RStudio Server Installed on $INSTANCE_ID" "RStudio Server is up. Use only when a job calls R (BupaR / r_helpers)."
