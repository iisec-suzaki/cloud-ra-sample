#!/usr/bin/env python3
"""
Generate Client's ECDSA key pair and automatically hardcode the public and private keys
"""

import subprocess
import re
import sys
from pathlib import Path

# Get the project root
PROJECT_ROOT = Path(__file__).parent
KEYGEN_PATH = PROJECT_ROOT / "subtools" / "client-ecdsa-keygen" / "keygen"
PUBKEY_FILE = PROJECT_ROOT / "Server_Enclave" / "client_pubkey.hpp"
PRIVKEY_FILE = PROJECT_ROOT / "Client_App" / "client_app.cpp"

# Line numbers (1-based) for key insertion
PUBKEY_GX_LINES = [12, 13, 14, 15]  # Lines 12-15 for gx
PUBKEY_GY_LINES = [18, 19, 20, 21]  # Lines 18-21 for gy
PRIVKEY_LINES = [30, 31, 32, 33]    # Lines 30-33 for private key


def run_keygen():
    """Generate Client's ECDSA key pair with keygen"""
    if not KEYGEN_PATH.exists():
        print(f"ERROR: {KEYGEN_PATH} not found", file=sys.stderr)
        sys.exit(1)
    
    print("Generating Client's ECDSA key pair with keygen...")
    result = subprocess.run(
        [str(KEYGEN_PATH)],
        capture_output=True,
        text=True,
        cwd=PROJECT_ROOT
    )
    
    if result.returncode != 0:
        print("ERROR: Failed to execute keygen", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    
    return result.stdout


def extract_public_key(output):
    """Extract the public key (g_x, g_y) from the output"""
    pattern = r'Copy the following public keys.*?\n\n\t\{' \
              r'((?:\s*0x[0-9a-f]{2},.*?\n)*?)\s*\},' \
              r'\s*\{' \
              r'((?:\s*0x[0-9a-f]{2},.*?\n)*?)\s*\}'
    
    match = re.search(pattern, output, re.DOTALL)
    if not match:
        print("ERROR: Failed to extract the public key", file=sys.stderr)
        sys.exit(1)
    
    gx_block = match.group(1).strip()
    gy_block = match.group(2).strip()
    
    # Extract all hex bytes and format as 4 lines of 8 bytes each
    gx_bytes = re.findall(r'0x[0-9a-f]{2}', gx_block)
    gy_bytes = re.findall(r'0x[0-9a-f]{2}', gy_block)
    
    if len(gx_bytes) != 32 or len(gy_bytes) != 32:
        print(f"ERROR: Expected 32 bytes for each key, got gx={len(gx_bytes)}, gy={len(gy_bytes)}", file=sys.stderr)
        sys.exit(1)
    
    # Format as 4 lines of 8 bytes each
    gx_lines = []
    for i in range(0, 32, 8):
        line_bytes = gx_bytes[i:i+8]
        line = ', '.join(line_bytes)
        if i + 8 < 32:
            line += ','
        gx_lines.append('            ' + line)
    
    gy_lines = []
    for i in range(0, 32, 8):
        line_bytes = gy_bytes[i:i+8]
        line = ', '.join(line_bytes)
        if i + 8 < 32:
            line += ','
        gy_lines.append('            ' + line)
    
    return gx_lines, gy_lines


def extract_private_key(output):
    """Extract the private key from the output"""
    key_start = output.find("Copy the following private key")
    if key_start < 0:
        print("ERROR: Could not find 'Copy the following private key' in output", file=sys.stderr)
        sys.exit(1)
    
    section = output[key_start:]
    blank_line_pos = section.find('\n\n\t')
    if blank_line_pos < 0:
        print("ERROR: Could not find private key data section", file=sys.stderr)
        sys.exit(1)
    
    privkey_section = section[blank_line_pos + 3:]
    end_pos = privkey_section.find('\n\n')
    if end_pos >= 0:
        privkey_text = privkey_section[:end_pos]
    else:
        privkey_text = privkey_section.rstrip('\n')
    
    bytes_list = re.findall(r'0x[0-9a-f]{2}', privkey_text)
    
    if len(bytes_list) != 32:
        print(f"ERROR: Expected 32 bytes, got {len(bytes_list)}", file=sys.stderr)
        sys.exit(1)
    
    # Format as 4 lines of 8 bytes each
    lines = []
    for i in range(0, 32, 8):
        line_bytes = bytes_list[i:i+8]
        line = ', '.join(line_bytes)
        if i + 8 < 32:
            line += ','
        lines.append('        ' + line)
    
    return lines


def update_public_key_file(gx_lines, gy_lines):
    """Update the public key in Server_Enclave/client_pubkey.hpp at lines 12-15 and 18-21"""
    if not PUBKEY_FILE.exists():
        print(f"ERROR: {PUBKEY_FILE} not found", file=sys.stderr)
        sys.exit(1)
    
    with open(PUBKEY_FILE, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    if len(lines) < max(PUBKEY_GY_LINES):
        print(f"ERROR: File has only {len(lines)} lines, need at least {max(PUBKEY_GY_LINES)}", file=sys.stderr)
        sys.exit(1)
    
    # Update gx lines (12-15, 0-indexed: 11-14)
    for i, line_num in enumerate(PUBKEY_GX_LINES):
        lines[line_num - 1] = gx_lines[i] + '\n'
    
    # Update gy lines (18-21, 0-indexed: 17-20)
    for i, line_num in enumerate(PUBKEY_GY_LINES):
        lines[line_num - 1] = gy_lines[i] + '\n'
    
    with open(PUBKEY_FILE, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    
    print(f"✓ Updated {PUBKEY_FILE} (lines {PUBKEY_GX_LINES[0]}-{PUBKEY_GX_LINES[-1]} and {PUBKEY_GY_LINES[0]}-{PUBKEY_GY_LINES[-1]})")
    return True


def update_private_key_file(privkey_lines):
    """Update the private key in Client_App/client_app.cpp at lines 30-33"""
    if not PRIVKEY_FILE.exists():
        print(f"ERROR: {PRIVKEY_FILE} not found", file=sys.stderr)
        sys.exit(1)
    
    with open(PRIVKEY_FILE, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    if len(lines) < max(PRIVKEY_LINES):
        print(f"ERROR: File has only {len(lines)} lines, need at least {max(PRIVKEY_LINES)}", file=sys.stderr)
        sys.exit(1)
    
    # Update private key lines (30-33, 0-indexed: 29-32)
    for i, line_num in enumerate(PRIVKEY_LINES):
        lines[line_num - 1] = privkey_lines[i] + '\n'
    
    with open(PRIVKEY_FILE, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    
    print(f"✓ Updated {PRIVKEY_FILE} (lines {PRIVKEY_LINES[0]}-{PRIVKEY_LINES[-1]})")
    return True


def main():
    print("ECDSA key pair generation and automatic hardcode script")
    print("=" * 50)
    
    # Execute keygen
    output = run_keygen()
    
    # Extract the public and private keys
    print("Extracting key information...")
    gx_lines, gy_lines = extract_public_key(output)
    privkey_lines = extract_private_key(output)
    
    # Update the files
    print("\nUpdating files...")
    update_public_key_file(gx_lines, gy_lines)
    update_private_key_file(privkey_lines)
    
    print("\n✓ All updates completed successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
