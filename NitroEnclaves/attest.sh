#!/bin/bash
# Test script for Nitro Enclave Attestation Verification

set -e


# Check if any enclaves are running
echo "Checking enclave status..."
echo "Current enclave status:"
if ! nitro-cli describe-enclaves; then
    echo "❌ No enclaves running or nitro-cli not available"
    echo "   Please run ./build.sh and ./run.sh first to start the enclave"
    exit 1
fi

echo ""

# Check if virtual environment exists
echo "Testing enclave connection and attestation verification..."
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found"
    echo "   Please run ./setup-client.sh first to create the virtual environment (venv)"
    exit 1
fi

# Check if required files exist
echo "Checking if AWS Root Certificate exist..."
if [ ! -f "client/root.pem" ]; then
    echo "❌ Root certificate not found at client/root.pem"
    echo "   Please ensure the AWS Nitro Enclaves root certificate is available"
    exit 1
fi

echo "Checking if expected measurements file exists..."
if [ ! -f "client/expected-measurements.json" ]; then
    echo "❌ Expected measurements file not found at client/expected-measurements.json"
    echo "   Please ensure the expected PCR measurements are available"
    exit 1
fi

# Test the client connection
cd ./client
source ../venv/bin/activate

echo "Running attestation verification client..."
if python3 client.py; then
    echo ""
    echo "✅ Attestation verification completed successfully!"
    echo ""
else
    echo ""
    echo "❌ Attestation verification failed!"
    echo "   Check the output above for details"
    exit 1
fi
