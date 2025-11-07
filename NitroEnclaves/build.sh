#!/bin/bash
# Build Nitro Enclave script

set -e

# Build the enclave
echo "Building the enclave..."
cd ./server
docker build -t attestation-enclave .

# Create the EIF file
echo "Creating EIF file..."
nitro-cli build-enclave \
    --docker-uri attestation-enclave \
    --output-file attestation.eif

echo "✅ Enclave build completed successfully"
echo "EIF file created: attestation.eif"
echo "Run './run.sh' to start the enclave"
