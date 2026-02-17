#!/usr/bin/env python3
import sys
import os
import re

def apply_edits(content):
    # Regex to find <file path="...">...</file> blocks
    pattern = re.compile(r'<file path="([^"]+)">\s*(.*?)\s*</file>', re.DOTALL)
    matches = pattern.findall(content)
    
    if not matches:
        return False
        
    for path, code in matches:
        if '..' in path or path.startswith('/'):
            print(f"❌ ERROR: Invalid path '{path}'")
            continue
            
        # Strip markdown fences if present
        code = code.strip()
        if code.startswith("```"):
            # Remove first line (e.g., ```go)
            lines = code.splitlines()
            if lines[0].startswith("```"):
                lines = lines[1:]
            # Remove last line if it's ```
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            code = "\n".join(lines).strip()
            
        dir_name = os.path.dirname(path)
        if dir_name:
            os.makedirs(dir_name, exist_ok=True)
            
        with open(path, 'w') as f:
            f.write(code + "\n")
        print(f"✅ Applied changes to {path}")
        
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
        
    with open(sys.argv[1], 'r') as f:
        response_content = f.read()
        
    apply_edits(response_content)
    sys.exit(0)
