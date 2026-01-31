#!/bin/bash
# load_env.sh - Load AWS environment variables for bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file if it exists, otherwise load .env.example
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(cat "$SCRIPT_DIR/.env" | grep -v '^#' | xargs)
    echo "✓ Loaded environment variables from .env"
elif [ -f "$SCRIPT_DIR/.env.example" ]; then
    export $(cat "$SCRIPT_DIR/.env.example" | grep -v '^#' | xargs)
    echo "✓ Loaded environment variables from .env.example (using defaults)"
else
    echo "✗ Error: No .env or .env.example file found in $SCRIPT_DIR"
    return 1
fi

# Verify critical variables are set
if [ -z "$AWS_ACCOUNT_ID_PRIMARY" ] || [ -z "$AWS_ACCOUNT_ID_LAMBDA" ]; then
    echo "✗ Error: AWS account IDs not properly set"
    return 1
fi

echo "✓ Environment loaded successfully"
echo "  Primary Account: $AWS_ACCOUNT_ID_PRIMARY"
echo "  Lambda Account: $AWS_ACCOUNT_ID_LAMBDA"
echo "  Region (Primary): $AWS_REGION_PRIMARY"
echo "  Region (Lambda): $AWS_REGION_LAMBDA"
