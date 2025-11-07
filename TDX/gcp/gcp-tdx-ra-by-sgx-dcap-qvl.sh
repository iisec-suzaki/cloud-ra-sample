#!/bin/bash
# GCP TDX Remote Attestation using go-tdx-guest (Quote Generation) and SGX-DCAP-QvL (Quote Verification)

set -e
set -o pipefail

# Generate 64-byte nonce
echo "Prepare 64-byte report data"
openssl rand 64 > report-data.bin
xxd -p report-data.bin | tr -d '\n' > report-data.txt

# Request TD Quote
echo "Request TD Quote"
sudo go-tdx-guest-attest \
	-inform hex \
	-in "$(< report-data.txt)" \
	-outform bin \
	-out quote.bin

# Configure DCAP-QvL
echo "Configure DCAP-QvL"
wget https://raw.githubusercontent.com/intel/SGXDataCenterAttestationPrimitives/main/QuoteGeneration/qcnl/linux/sgx_default_qcnl_without_pccs.conf 
sudo mv sgx_default_qcnl_without_pccs.conf /etc/sgx_default_qcnl.conf

# Verify TD Quote by SGX-DCAP-QvL
echo "Verify TD Quote by SGX-DCAP-QvL"
sgx-dcap-qvl-app -quote quote.bin

# Check TD Quote Version and parse accordingly
echo "Check TD Quote Version"
# Read first 2 bytes (little endian) to get version
QUOTE_VERSION=$(od -An -tu2 -N2 -j 0 quote.bin | tr -d ' ')

echo "Quote Version: $QUOTE_VERSION"

if [ "$QUOTE_VERSION" -eq 4 ]; then
    echo "Parse TD quote by parserV4"
    parserV4 quote.bin
elif [ "$QUOTE_VERSION" -eq 5 ]; then
    echo "Parse TD quote by parserV5"
    parserV5 quote.bin
else
    echo "Could not parse Quote other than V4 or V5"
fi
