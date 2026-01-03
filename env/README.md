# Environment Variables Setup

This directory contains scripts to manage AWS environment variables for the project.

## Quick Start

### Bash/Shell

Source the environment loader in your scripts or terminal:

```bash
source env/load_env.sh
```

This will:
- Load variables from `.env` if it exists
- Fall back to `.env.example` if `.env` is missing
- Validate that all required variables are set
- Display the loaded configuration

### Python

Import and run the environment loader in your Python scripts:

```python
import sys
sys.path.insert(0, 'env')
from load_env import load_env

load_env()

# Now you can access environment variables
import os
account_id = os.environ.get('AWS_ACCOUNT_ID_PRIMARY')
```

### R

Source the environment loader in your R scripts:

```r
source('env/load_env.R')
load_env()

# Now you can access environment variables
account_id <- Sys.getenv("AWS_ACCOUNT_ID_PRIMARY")
```

## Configuration

### .env File

Copy `.env.example` to `.env` and update with your actual values:

```bash
cp env/.env.example env/.env
```

Then edit `env/.env` with your AWS account IDs:

```env
# AWS Account IDs
AWS_ACCOUNT_ID_PRIMARY=YOUR_PRIMARY_ACCOUNT_ID
AWS_ACCOUNT_ID_LAMBDA=YOUR_LAMBDA_ACCOUNT_ID

# AWS Regions
AWS_REGION_PRIMARY=us-east-1
AWS_REGION_LAMBDA=us-east-2

# AWS Profiles
AWS_PROFILE=your-profile-name

# ACM Certificate
ACM_CERTIFICATE_ID=your-certificate-id

# ECR Repository
ECR_REPOSITORY_NAME=test_duckdb
ECR_IMAGE_TAG=latest

# Lambda Function
LAMBDA_FUNCTION_NAME=duckdb-os-tester
LAMBDA_ROLE_ARN=arn:aws:iam::YOUR_LAMBDA_ACCOUNT_ID:role/afrl-lambda
```

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ACCOUNT_ID_PRIMARY` | Primary AWS account ID for Route53/QuickSight | `535362115856` |
| `AWS_ACCOUNT_ID_LAMBDA` | AWS account ID for Lambda/ECR | `650251715690` |
| `AWS_REGION_PRIMARY` | Primary AWS region | `us-east-1` |
| `AWS_REGION_LAMBDA` | Lambda AWS region | `us-east-2` |
| `AWS_PROFILE` | AWS CLI profile to use | `default` |
| `ACM_CERTIFICATE_ID` | ACM certificate ID | `59a5f2eb-4880-...` |
| `ECR_REPOSITORY_NAME` | ECR repository name | `test_duckdb` |
| `ECR_IMAGE_TAG` | Docker image tag | `latest` |
| `LAMBDA_FUNCTION_NAME` | Lambda function name | `duckdb-os-tester` |
| `LAMBDA_ROLE_ARN` | Lambda IAM role ARN | `arn:aws:iam::...` |

## Scripts

### `load_env.sh` - Bash Environment Loader

Loads environment variables for bash scripts and terminal sessions.

**Usage in scripts:**
```bash
#!/bin/bash
source ../env/load_env.sh

# Use variables
aws ecr get-login-password --region ${AWS_REGION_LAMBDA} | ...
```

**Usage in terminal:**
```bash
source env/load_env.sh
```

### `load_env.py` - Python Environment Loader

Loads environment variables for Python scripts.

**Usage:**
```python
from env.load_env import load_env
load_env()

import os
print(os.environ['AWS_ACCOUNT_ID_PRIMARY'])
```

### `load_env.R` - R Environment Loader

Loads environment variables for R scripts.

**Usage:**
```r
source('env/load_env.R')
load_env()

print(Sys.getenv("AWS_ACCOUNT_ID_PRIMARY"))
```

### `replace_account_ids.py` - Account ID Replacer

One-time utility script to replace hardcoded account IDs in JSON files with environment variable placeholders.

**Usage:**
```bash
python env/replace_account_ids.py
```

## Security Notes

⚠️ **Important:**

- **Never commit `.env` file** - it contains sensitive AWS account information
- `.env` files are automatically ignored by `.gitignore`
- Always use `.env.example` as a template
- Store real `.env` files securely and share via secure channels only
- Rotate AWS credentials regularly
- Use IAM roles instead of long-term credentials when possible

## Files Modified

The following files have been updated to use environment variables instead of hardcoded account IDs:

### Quarto Documents (.qmd)
- `route53/route53.qmd` - Route 53 and ACM setup
- `lambda/aws_lambda_duckdb.qmd` - Lambda and ECR commands

### JSON Configuration Files
- `quicksight/analysis.json`
- `quicksight/dashboard_definition1.json`
- `quicksight/dashboard_definition2.json`
- `quicksight/full_dashboard_def1.json`
- `quicksight/full_dashboard_def2.json`
- `quicksight/permissions1.json`
- `quicksight/permissions2.json`
- `quicksight/placeholders.json`
- `quicksight/source_entity.json`
- `quicksight/source_entity1.json`
- `quicksight/source_entity2.json`

## Troubleshooting

### Variables not loading

Check that `.env` or `.env.example` exists:
```bash
ls -la env/
```

### "Missing required environment variables" error

Ensure all required variables are defined in `.env`:
```bash
grep -E "AWS_ACCOUNT_ID|AWS_REGION" env/.env
```

### Permission denied on scripts

Make scripts executable:
```bash
chmod +x env/load_env.sh
chmod +x env/replace_account_ids.py
```
