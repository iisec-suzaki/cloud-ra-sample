#!/bin/bash
# Terminate the Nitro Enclave PoC

set -e

echo "Terminating Nitro Enclave..."

# Check if any enclaves are running
if ! nitro-cli describe-enclaves > /dev/null 2>&1; then
    echo "No enclaves are currently running"
    exit 0
fi

# Get the enclave ID for CID 16
ENCLAVE_ID=$(nitro-cli describe-enclaves | jq -r '.[] | select(.State == "RUNNING" and .EnclaveCID == 16) | .EnclaveID')

if [ "$ENCLAVE_ID" = "null" ] || [ -z "$ENCLAVE_ID" ]; then
    echo "ℹ️  No running enclave found with CID 16"
    exit 0
fi

echo "Terminating enclave: $ENCLAVE_ID"

# Terminate the enclave
nitro-cli terminate-enclave --enclave-id "$ENCLAVE_ID"

echo "✅ Enclave terminated successfully!"
