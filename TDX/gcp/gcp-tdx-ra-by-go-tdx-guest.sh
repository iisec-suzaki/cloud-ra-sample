#!/bin/bash
# GCP TDX Remote Attestation using go-tdx-guest (Quote Generation and Verification)

set -e
set -o pipefail

# Generate 64-byte nonce
echo "Prepare 64-byte report data"
openssl rand 64 > report-data.bin
xxd -p report-data.bin | tr -d '\n' > report-data.txt

# Request TD quote
echo "Request TD Quote"
sudo go-tdx-guest-attest \
	-inform hex \
	-in "$(< report-data.txt)" \
	-outform bin \
	-out quote.bin

# Verify TD Quote by go-tdx-guest
echo "Verify TD Quote by go-tdx-guest"
go-tdx-guest-check \
	-inform bin \
	-in quote.bin \
	-report_data "$(< report-data.txt)" \
	-get_collateral true \
	-verbosity 1

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
