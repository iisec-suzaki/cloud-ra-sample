#!/bin/bash
# GCP SEV-SNP Remote Attestation using snpguest (Report Generation and Verification)

set -e

# Please change the following variable to your own environment
VMPL_VALUE=0

# Prepare Report Data
echo "Prepare 64-byte report data"
openssl rand 64 > request-file.bin

# Request SEV-SNP AR
echo "Request SEV-SNP AR"
sudo snpguest report report.bin request-file.bin -v $VMPL_VALUE

# Fetch Cert Chain ARK->ASK->VCEK from AMD KDS
echo "Fetch Cert Chain ARK->ASK->VCEK from AMD KDS"
snpguest fetch ca pem certs -r report.bin -e vcek
snpguest fetch vcek pem certs report.bin

# Verify Cert Chain ARK->ASK->VCEK
echo "Verify Cert Chain ARK->ASK->VCEK"
snpguest verify certs certs

# Verify Signature VCEK->SEV-SNP AR
echo "Verify Signature VCEK->SEV-SNP AR"
snpguest verify attestation certs report.bin

# Extract Report Data from SEV-SNP AR
echo "Extract Report Data from SEV-SNP AR"
REPORT_DATA_OFFSET=80
REPORT_DATA_SIZE=64

dd if=report.bin \
  skip=$REPORT_DATA_OFFSET \
  bs=1 \
  count=$REPORT_DATA_SIZE \
  of=report-data.bin \
  status=none

# Verify Report Data
echo "Verify Report Data"
diff -s request-file.bin report-data.bin

# Parse SEV-SNP AR
echo "Parse SEV-SNP AR"
snpguest display report report.bin
