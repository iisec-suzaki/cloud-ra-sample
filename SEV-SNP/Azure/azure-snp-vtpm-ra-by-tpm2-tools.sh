#!/bin/bash
# Azure SEV-SNP and vTPM Remote Attestation using tpm2_tools (Report Generation, Quote Generation and Quote Verification) and snpguest (Report Verification)

set -e
set -o pipefail

# vTPM NVS Indices
AR_NV_INDEX=0x01400001
AKPUB_NV_INDEX=0x81000003

# Read the Azure Attestation Report from vTPM NV Index 0x01400001
echo "Read the Azure AR from vTPM NV Index 0x01400001"
(sudo tpm2_nvread -C o $AR_NV_INDEX) > ./stored-report.bin

# AZURE ATTESTATION REPORT FORMAT
# FIELD          | OFFSET | LENGTH
# HEADER         | 0      | 32
# REPORT_PAYLOAD | 32     | 1184
# RUNTIME_DATA   | 1216   | variable length
#
# RUNTIME DATA FORMAT
# FIELD          | OFFSET | LENGTH
# DATA_SIZE      | 0      | 4
# VERSION        | 4      | 4
# REPORT_TYPE    | 8      | 4
# HASH_TYPE      | 12     | 4
# CLAIM_SIZE     | 16     | 4
# RUNTIME_CLAIMS | 20     | variable length
#
# RUNTIME CLAIMS FORMAT
# JSON FIELD       | DESCRIPTION
# keys             | HCLAkPub (AKPub) and HCLEKPub (EKPub) in JWK format
# vm_configuration | Selective Azure confidential VM configuration
# user_data        | 64-byte data (HEX string) read from NV index 0x01400002

# SET OFFSETS
REPORT_OFFSET=32
REPORT_SIZE=1184

RUNTIME_DATA_SIZE_OFFSET=1216
RUNTIME_DATA_OFFSET=1216

RUNTIME_CLAIM_HASH_TYPE_OFFSET=12

RUNTIME_CLAIM_SIZE_OFFSET=16
RUNTIME_CLAIM_OFFSET=20

# Extract SEV_SNP AR
echo "Extract SEV-SNP AR from the Azure AR"
dd if=./stored-report.bin \
	skip=$REPORT_OFFSET \
	bs=1 \
	count=$REPORT_SIZE \
	of=./report.bin \
	status=none

# Fetch ARK->ASK Certs from AMD KDS
echo "Fetch ARK->ASK Certs from AMD KDS"
snpguest fetch ca pem certs -r report.bin -e vcek

# Fetch VCEK Cert from AMD KDS
echo "Fetch VCEK Cert from AMD KDS"
snpguest fetch vcek pem certs report.bin

# Verify Cert Chain ARK->ASK->VCEK
echo "Verify Cert Chain ARK->ASK->VCEK"
snpguest verify certs certs

# Verify Signature VCEK->SEV-SNP AR
echo "Verify Signature VCEK->SEV-SNP AR"
snpguest verify attestation certs report.bin

# Verify Report Data of SEV-SNP AR
echo "Verify Report Data of SEV-SNP AR"

## Fetch Runtime Claims from vTPM NVS
echo "1. Extract Runtime Claims from the Azure AR"
RUNTIME_DATA_SIZE=$(od -An -tu4 -N4 -j $RUNTIME_DATA_SIZE_OFFSET stored-report.bin | tr -d ' ')

dd if=stored-report.bin \
	bs=1 \
	skip=$RUNTIME_DATA_OFFSET \
	count="$RUNTIME_DATA_SIZE" \
	of=runtime-data.bin \
	status=none

RUNTIME_CLAIM_SIZE=$(od -An -tu4 -N4 -j $RUNTIME_CLAIM_SIZE_OFFSET runtime-data.bin | tr -d ' ')

dd if=runtime-data.bin \
	bs=1 \
	skip=$RUNTIME_CLAIM_OFFSET \
	count="$RUNTIME_CLAIM_SIZE" \
	of=runtime-claims.json \
	status=none

## Check hash algorithm of Runtime Claims
echo "2. Check hash algorithm of Runtime Claims"
RUNTIME_CLAIM_HASH_TYPE=$(od -An -tu4 -N4 -j $RUNTIME_CLAIM_HASH_TYPE_OFFSET runtime-data.bin | tr -d ' ')

case $RUNTIME_CLAIM_HASH_TYPE in
1) HASH="sha256sum";;
2) HASH="sha384sum";;
3) HASH="sha512sum";;
*) echo "Unknown hash algorithm ($RUNTIME_CLAIM_HASH_TYPE)"; exit 1 ;;
esac
echo "Runtime-Claims hash algorithm = $RUNTIME_CLAIM_HASH_TYPE ($HASH)"

## Compute HASH(Runtime Claims) and expand it to 64 bytes
echo "3. Compute HASH(Runtime Claims) and expand it to 64 bytes"
$HASH runtime-claims.json \
	| awk '{print $1}' \
	| xxd -r -p \
	| (dd bs=64 count=1 conv=sync of=runtime-digest.bin status=none)

## Extract REPORT_DATA from SEV-SNP AR
echo "4. Extract REPORT_DATA from SEV-SNP AR"
dd if=./report.bin \
  skip=80 \
  bs=1 \
  count=64 \
  of=./report-data.bin \
  status=none

## Verify Report Data
echo "5. Verify Report Data"
diff -s runtime-digest.bin report-data.bin

# Fetch vTPM Quote
echo "Fetch vTPM Quote"
openssl rand -hex 32 | tr -d '\n' > nonce.txt

sudo tpm2_quote \
	-c $AKPUB_NV_INDEX \
	-l sha256:15,16,22 \
	-q "$(< nonce.txt)" \
	-m message.msg \
	-s signature.sig \
	-o pcr.pcrs \
	-g sha256

# Fetch AKPub from vTPM NV index 0x81000003
echo "Fetch AKPub from vTPM NV index 0x81000003"
sudo tpm2_readpublic -c $AKPUB_NV_INDEX -f pem -o ak-pub.pem
sudo chmod +r ak-pub.pem

# Verify Signature AK->TPM Quote
echo "Verify Signature AK->TPM Quote"
sudo tpm2_checkquote \
	-u ak-pub.pem \
	-m message.msg \
	-s signature.sig \
	-f pcr.pcrs \
	-g sha256 \
	-q "$(< nonce.txt)" \

# Compare AKPub in Runtime Claims with ak-pub.pem
echo "Verify that AKPub is bound in Runtime Claims"
jq -r '.keys[] | select(.kid=="HCLAkPub")' runtime-claims.json > ak-pub-rc.jwk
jwker ak-pub-rc.jwk ak-pub-rc.pem
diff -s ak-pub-rc.pem ak-pub.pem

# Parse SEV-SNP AR
echo "Parse SEV-SNP AR"
snpguest display report report.bin
