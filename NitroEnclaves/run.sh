#!/bin/bash
# Run Nitro Enclave script

set -e


# Check if EIF file exists
echo "Checking if the EIF file exists..."
if [ ! -f "server/attestation.eif" ]; then
    echo "❌ EIF file not found. Please run './build.sh' first."
    exit 1
fi

# Start the enclave
echo "Starting the enclave..."
nitro-cli run-enclave \
    --eif-path server/attestation.eif \
    --memory 512 \
    --cpu-count 2 \
    --enclave-cid 16

echo "✅ Enclave started successfully!"
echo "Enclave is running on CID 16"
echo "You can now run './attest.sh' to test the attestation"
echo "Run './cleanup.sh' to terminate the enclave when done"
