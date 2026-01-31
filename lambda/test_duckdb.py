import json
import duckdb
import os
import numpy
import pandas

# Define paths using LAMBDA_TASK_ROOT
LAMBDA_TASK_ROOT = os.getenv("LAMBDA_TASK_ROOT", "/var/task")
EXTENSION_PATH = f"{LAMBDA_TASK_ROOT}/extensions"

# S3 bucket and path configuration
S3_BUCKET = "flis-db"
S3_PREFIX = "p_cage"
INPUT_PATH = f"s3://{S3_BUCKET}/{S3_PREFIX}/*.parquet"

def lambda_handler(event, context):
    try:
        # Set DuckDB home directory and extension directory
        duckdb.sql(f"SET home_directory='{LAMBDA_TASK_ROOT}'")
        duckdb.sql(f"SET extension_directory='{EXTENSION_PATH}'")

        # Load HTTPFS extension (preinstalled in Docker)
        duckdb.sql("LOAD httpfs;")

        AWS_REGION = os.getenv("AWS_REGION", "us-east-2")
        duckdb.sql(f"SET s3_region='{AWS_REGION}';")

        # Check schema by selecting zero rows from Parquet files in S3
        schema = duckdb.sql(f"SELECT * FROM read_parquet('{INPUT_PATH}') LIMIT 0").df()

        return {
            'statusCode': 200,
            'body': json.dumps({
                "message": "DuckDB successfully connected to S3",
                "os_release": os.popen("cat /etc/os-release").read(),
                "uname": os.popen("uname -a").read(),
                "schema": schema.to_dict()
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                "error": str(e),
                "message": "Failed to connect DuckDB to S3"
            })
        }
