#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status
sudo mkdir -p /usr/lib/spark/jars
sudo chmod -R 777 /usr/lib/spark/jars

# Define directories
DEST_DIR="/usr/lib/spark/jars"

# Install Python dependencies
echo "Installing Python packages..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
unzip awscliv2.zip && \
sudo ./aws/install

# Install Python dependencies
echo "Installing Python packages..."
sudo python3 -m pip install numpy seaborn plotly boto3 ec2-metadata catboost matplotlib shap pyarrow fsspec s3fs kneed || echo "Failed to install some Python packages"

# Download Apache Spark CatBoost JAR dependencies
echo "Downloading Apache Spark CatBoost JAR dependencies..."
JAR_URLS=(
  "https://repo1.maven.org/maven2/ai/catboost/catboost-spark_3.5_2.12/1.2.7/catboost-spark_3.5_2.12-1.2.7.jar"
  "https://repo1.maven.org/maven2/ai/catboost/catboost-prediction/1.2.7/catboost-prediction-1.2.7.jar"
  "https://repo1.maven.org/maven2/ai/catboost/catboost-common/1.2.7/catboost-common-1.2.7.jar"
  "https://repo1.maven.org/maven2/io/github/classgraph/classgraph/4.8.139/classgraph-4.8.139.jar"
  "https://repo1.maven.org/maven2/ai/catboost/catboost-spark-macros_2.12/1.2.7/catboost-spark-macros_2.12-1.2.7.jar"
)

for url in "${JAR_URLS[@]}"; do
  sudo wget $url -P "$DEST_DIR" || echo "Failed to download $url"
done

# Verify downloads
echo "Verifying JAR installations..."
for url in "${JAR_URLS[@]}"; do
  jar_name=$(basename "$url")
  if [[ -f "$DEST_DIR/$jar_name" ]]; then
    echo "$jar_name installed successfully."
  else
    echo "Failed to install $jar_name." >&2
    exit 1
  fi
done

echo "All installations completed successfully!"