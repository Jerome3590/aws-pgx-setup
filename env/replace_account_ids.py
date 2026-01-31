#!/usr/bin/env python3
"""
replace_account_ids.py - Replace hardcoded AWS account IDs with placeholders
This script replaces account IDs in QuickSight JSON files with a placeholder format
that can be substituted with environment variables at runtime.
"""

import json
import os
import re
from pathlib import Path

# Mapping of account IDs to environment variable names
ACCOUNT_ID_MAPPING = {
    "535362115856": "${AWS_ACCOUNT_ID_PRIMARY}",
    "650251715690": "${AWS_ACCOUNT_ID_LAMBDA}",
}

def replace_account_ids_in_file(file_path):
    """Replace account IDs in a JSON file"""
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        original_content = content
        
        # Replace each account ID
        for old_id, new_id in ACCOUNT_ID_MAPPING.items():
            content = content.replace(old_id, new_id)
        
        if content != original_content:
            with open(file_path, 'w') as f:
                f.write(content)
            print(f"✓ Updated {file_path}")
            return True
        else:
            print(f"- No changes needed in {file_path}")
            return False
    except Exception as e:
        print(f"✗ Error processing {file_path}: {e}")
        return False

def main():
    """Main function to replace account IDs in all QuickSight files"""
    quicksight_dir = Path(__file__).parent.parent / "quicksight"
    
    if not quicksight_dir.exists():
        print(f"✗ QuickSight directory not found: {quicksight_dir}")
        return
    
    json_files = list(quicksight_dir.glob("*.json"))
    
    if not json_files:
        print(f"✗ No JSON files found in {quicksight_dir}")
        return
    
    print(f"Found {len(json_files)} JSON files to process\n")
    
    updated_count = 0
    for json_file in json_files:
        if replace_account_ids_in_file(json_file):
            updated_count += 1
    
    print(f"\n✓ Updated {updated_count} files")

if __name__ == "__main__":
    main()
