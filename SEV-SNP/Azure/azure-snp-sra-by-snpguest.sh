#!/bin/bash
# Azure SEV-SNP Remote Attestation using snpguest (Report Generation and Verification)

set -e

# Read SEV-SNP AR from vTPM NV index 0x01400001
echo "Read SEV-SNP AR from vTPM NV index 0x01400001"
sudo snpguest report report.bin request-file.bin -p -v 0

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

# Parse SEV-SNP AR
echo "Parse SEV-SNP AR"
snpguest display report report.bin

# Report Data cannot be verified with snpguest solely
# Please use tpm2-tools to fetch Runtime Claims
