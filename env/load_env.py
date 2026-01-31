import os
import sys
from pathlib import Path

def load_env():
    """Load AWS environment variables from .env or .env.example"""
    
    script_dir = Path(__file__).parent
    env_file = script_dir / ".env"
    env_example = script_dir / ".env.example"
    
    # Choose which file to load
    if env_file.exists():
        target_file = env_file
        source = ".env"
    elif env_example.exists():
        target_file = env_example
        source = ".env.example (using defaults)"
    else:
        print(f"✗ Error: No .env or .env.example file found in {script_dir}")
        sys.exit(1)
    
    # Parse and load environment variables
    try:
        with open(target_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                # Parse KEY=VALUE
                if '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key.strip()] = value.strip()
        
        print(f"✓ Loaded environment variables from {source}")
        
        # Verify critical variables
        required_vars = ['AWS_ACCOUNT_ID_PRIMARY', 'AWS_ACCOUNT_ID_LAMBDA']
        missing = [var for var in required_vars if var not in os.environ]
        
        if missing:
            print(f"✗ Error: Missing required environment variables: {', '.join(missing)}")
            sys.exit(1)
        
        print("✓ Environment loaded successfully")
        print(f"  Primary Account: {os.environ.get('AWS_ACCOUNT_ID_PRIMARY')}")
        print(f"  Lambda Account: {os.environ.get('AWS_ACCOUNT_ID_LAMBDA')}")
        print(f"  Region (Primary): {os.environ.get('AWS_REGION_PRIMARY')}")
        print(f"  Region (Lambda): {os.environ.get('AWS_REGION_LAMBDA')}")
        
    except Exception as e:
        print(f"✗ Error loading environment variables: {e}")
        sys.exit(1)


if __name__ == "__main__":
    load_env()
