#!/bin/bash
# AWS SEV-SNP Extended Remote Attestation by snpguest (Report Generation and Verification)

set -e

# Please change the following variable to your own environment
PROCESSOR_MODEL='milan'
VMPL_VALUE=0

# Prepare 64-byte nonce
echo "Prepare 64-byte nonce"
openssl rand 64 > request-file.bin

# Request SEV-SNP Report
echo "Request SEV-SNP Report"
sudo snpguest report report.bin request-file.bin -v $VMPL_VALUE

# Fetch ARK->ASVK Certs from AMD KDS
echo "Fetch ARK->ASVK Certs from AMD KDS"
snpguest fetch ca pem certs $PROCESSOR_MODEL -e vlek

# Get VLEK Cert from host's memory
echo "Get VLEK Cert from host's memory"
sudo snpguest certificates pem certs

# Verify Cert Chain ARK->ASVK->VLEK
echo "Verify Cert Chain ARK->ASVK->VLEK"
snpguest verify certs certs

# Verify Signature VLEK->AR
echo "Verify Signature VLEK->AR"
snpguest verify attestation certs report.bin

# Extract Report Data from SEV-SNP Report
echo "Extract Report Data from SEV-SNP Report"
REPORT_DATA_OFFSET=80
REPORT_DATA_SIZE=64

dd if=./report.bin \
  skip=$REPORT_DATA_OFFSET \
  bs=1 \
  count=$REPORT_DATA_SIZE \
  of=./report-data.bin \
  status=none

# Verify Report Data
echo "Verify Report Data"
diff -s request-file.bin report-data.bin

# Parse SEV-SNP AR
echo "Parse SEV-SNP AR"
snpguest display report report.bin
