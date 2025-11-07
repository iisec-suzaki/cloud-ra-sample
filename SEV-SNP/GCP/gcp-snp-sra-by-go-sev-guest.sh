#!/bin/bash
# GCP SEV-SNP Remote Attestation using go-sev-guest (Report Generation and Verification)

set -e
set -o pipefail

# Please change the following variable to your own environment
GUEST_POLICY=0x030000

# Prepare Report Data
echo "Prepare 64-byte report data"
openssl rand 64 > request-file.bin
xxd -p request-file.bin | tr -d '\n' > request-file.txt

# Request SEV-SNP AR
echo "Request SEV-SNP AR"
sudo go-sev-guest-attest \
	-inform bin \
	-infile request-file.bin \
	-outform bin \
	-out report.bin

# Verify SEV-SNP AR
echo "Verify SEV-SNP AR"
set +e
go-sev-guest-check \
	-inform bin \
	-in report.bin \
	-guest_policy $GUEST_POLICY \
	-provisional true \
	-report_data "$(< request-file.txt)"
CHECK_EXIT_CODE=$?
set -e

# Check the exit code
case $CHECK_EXIT_CODE in
0) echo "Verification Success";;
1) echo "Verification Failure due to tool misuse"; exit 1 ;;
2) echo "Verification Failure due to invalid signature"; exit 1 ;;
3) echo "Verification Failure due to certificate fetch failure"; exit 1 ;;
4) echo "Verification Failure due to certificate revocation list download failure"; exit 1 ;;
5) echo "Verification Failure due to policy"; exit 1 ;;
*) echo "Verification Unknown error"; exit 1 ;;
esac

# Parse SEV-SNP AR
echo "Parse SEV-SNP AR"
go-sev-guest-show -inform bin -in report.bin -outform textproto
