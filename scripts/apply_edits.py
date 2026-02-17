#!/usr/bin/env python3
import sys
import os
import re

def apply_edits(content):
    # Regex to find <file path="...">...</file> blocks
    pattern = re.compile(r'<file path="([^"]+)">\s*(.*?)\s*</file>', re.DOTALL)
    matches = pattern.findall(content)
    
    if not matches:
        print("⚠️  No file blocks found in LLM response.")
        return False
        
    for path, code in matches:
        # Resolve path relative to current directory (which is services/SERVICE_NAME)
        # Ensure path doesn't go outside
        if '..' in path or path.startswith('/'):
            print(f"❌ ERROR: Invalid path '{path}'. Only relative paths within the service are allowed.")
            continue
            
        dir_name = os.path.dirname(path)
        if dir_name:
            os.makedirs(dir_name, exist_ok=True)
            
        with open(path, 'w') as f:
            f.write(code)
        print(f"✅ Applied changes to {path}")
        
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: apply_edits.py <llm_response_file>")
        sys.exit(1)
        
    with open(sys.argv[1], 'r') as f:
        response_content = f.read()
        
    if apply_edits(response_content):
        sys.exit(0)
    else:
        sys.exit(0) # Non-fatal if no changes found, agent might have just returned analysis
