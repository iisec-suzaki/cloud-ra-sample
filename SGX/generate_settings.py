#!/usr/bin/env python3
"""
Interactive script to generate settings_client.ini with user input
"""

import sys
import subprocess
import re
from pathlib import Path

# Get the project root
PROJECT_ROOT = Path(__file__).parent
SETTINGS_FILE = PROJECT_ROOT / "settings_client.ini"
MREXTRACT_PATH = PROJECT_ROOT / "subtools" / "mr-extract" / "mr-extract"


def get_user_input(prompt, required=False, default=None):
    """Get user input with optional default value"""
    if default is not None:
        prompt_with_default = f"{prompt} [{default}]: "
    else:
        prompt_with_default = f"{prompt}: "
    
    while True:
        value = input(prompt_with_default).strip()
        
        if value:
            return value
        elif default is not None:
            return default
        elif not required:
            return ""
        else:
            print("This field is required. Please enter a value.")


def try_extract_measurements():
    """Try to extract MRENCLAVE and MRSIGNER from signed enclave image"""
    if not MREXTRACT_PATH.exists():
        return None, None
    
    # mr-extract needs to be run from its directory
    mr_extract_dir = MREXTRACT_PATH.parent
    
    try:
        result = subprocess.run(
            ["./mr-extract"],
            capture_output=True,
            text=True,
            cwd=mr_extract_dir,
            timeout=30
        )
        
        if result.returncode != 0:
            return None, None
        
        # Remove ANSI escape sequences
        ansi_escape = re.compile(r'\x1b\[[0-9;]*m')
        clean_output = ansi_escape.sub('', result.stdout)
        
        # Extract measurements
        mrenclave_pattern = r'MRENCLAVE value\s*->\s*([0-9a-f]{64})'
        mrsigner_pattern = r'MRSIGNER value\s*->\s*([0-9a-f]{64})'
        
        mrenclave_match = re.search(mrenclave_pattern, clean_output)
        mrsigner_match = re.search(mrsigner_pattern, clean_output)
        
        if mrenclave_match and mrsigner_match:
            return mrenclave_match.group(1), mrsigner_match.group(1)
    except Exception:
        pass
    
    return None, None


def generate_settings_file():
    """Generate settings_client.ini interactively"""
    print("=" * 60)
    print("Settings Client Configuration Generator")
    print("=" * 60)
    print()
    
    # Get MAA_URL (required)
    print("Please enter the following configuration values:")
    print()
    maa_url = get_user_input("MAA_URL (required)", required=True)
    
    # Get MAA_API_VERSION (default: 2025-06-01)
    maa_api_version = get_user_input("MAA_API_VERSION", default="2025-06-01")
    
    # Get CLIENT_ID (default: 0)
    client_id = get_user_input("CLIENT_ID", default="0")
    
    # Get MINIMUM_ISVSVN (default: 0)
    minimum_isvsvn = get_user_input("MINIMUM_ISVSVN", default="0")
    
    # Get REQUIRED_ISV_PROD_ID (default: 0)
    required_isv_prod_id = get_user_input("REQUIRED_ISV_PROD_ID", default="0")
    
    # Get SKIP_MRENCLAVE_CHECK (default: 0)
    skip_mrenclave_check = get_user_input("SKIP_MRENCLAVE_CHECK", default="0")
    
    # Try to extract MRENCLAVE and MRSIGNER automatically
    print()
    print("Attempting to extract MRENCLAVE and MRSIGNER from signed enclave image...")
    mrenclave, mrsigner = try_extract_measurements()
    
    if mrenclave and mrsigner:
        print(f"Successfully extracted MRENCLAVE: {mrenclave}")
        print(f"Successfully extracted MRSIGNER:  {mrsigner}")
        use_auto = get_user_input("Use these values? (Y/n)", default="Y")
        if use_auto.upper() not in ['Y', 'YES', '']:
            mrenclave = None
            mrsigner = None
    else:
        print("WARNING: Could not automatically extract measurements.")
        print("  (This is normal if enclave.signed.so doesn't exist yet)")
    
    # Get MRENCLAVE and MRSIGNER if not auto-extracted
    if not mrenclave or not mrsigner:
        print()
        print("Please enter MRENCLAVE and MRSIGNER manually:")
        mrenclave = get_user_input("REQUIRED_MRENCLAVE (64 hex characters)", required=True)
        mrsigner = get_user_input("REQUIRED_MRSIGNER (64 hex characters)", required=True)
        
        # Validate hex strings
        if len(mrenclave) != 64 or not all(c in '0123456789abcdefABCDEF' for c in mrenclave):
            print("WARNING: MRENCLAVE should be 64 hexadecimal characters", file=sys.stderr)
        
        if len(mrsigner) != 64 or not all(c in '0123456789abcdefABCDEF' for c in mrsigner):
            print("WARNING: MRSIGNER should be 64 hexadecimal characters", file=sys.stderr)
    
    # Generate the settings file content
    settings_content = f"""[client]
MAA_URL = {maa_url}
MAA_API_VERSION = {maa_api_version}
CLIENT_ID = {client_id}
MINIMUM_ISVSVN = {minimum_isvsvn}
REQUIRED_ISV_PROD_ID = {required_isv_prod_id}
REQUIRED_MRENCLAVE = {mrenclave}
REQUIRED_MRSIGNER = {mrsigner}
SKIP_MRENCLAVE_CHECK = {skip_mrenclave_check}
"""
    
    # Check if file already exists
    if SETTINGS_FILE.exists():
        overwrite = get_user_input(f"\n{SETTINGS_FILE} already exists. Overwrite? (y/N)", default="N")
        if overwrite.upper() not in ['Y', 'YES']:
            print("Cancelled. Settings file was not modified.")
            return 1
    
    # Write the settings file
    try:
        with open(SETTINGS_FILE, 'w', encoding='utf-8') as f:
            f.write(settings_content)
        print()
        print(f"Successfully generated {SETTINGS_FILE}")
        return 0
    except Exception as e:
        print(f"ERROR: Failed to write settings file: {e}", file=sys.stderr)
        return 1


def main():
    try:
        return generate_settings_file()
    except KeyboardInterrupt:
        print("\n\nCancelled by user.")
        return 1
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

