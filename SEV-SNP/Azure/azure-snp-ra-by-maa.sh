#!/bin/bash
# Azure SEV-SNP Remote Attestation using Microsoft Azure Attestation (Report Verification)

set -e
set -o pipefail

# Microsoft Azure Attestation URL
VERIFIER_URL="https://sharedjpe.jpe.attest.azure.net" 
TEE_TYPE="SevSnpVm"
API_VERSION="2022-08-01"
MAA_REQUEST_URL="$VERIFIER_URL/attest/$TEE_TYPE?api-version=$API_VERSION"

# Set the NV Index to read the Azure Attestation Report from vTPM
AR_NV_INDEX=0x01400001

# Set the offsets to extract the SNP Attestation Report and Runtime Claims from the Azure Attestation Report
## In Azure Attestation Report
REPORT_OFFSET=32
REPORT_SIZE=1184
RUNTIME_DATA_SIZE_OFFSET=1216
RUNTIME_DATA_OFFSET=1216
## In Runtime Data
RUNTIME_CLAIM_SIZE_OFFSET=16
RUNTIME_CLAIM_OFFSET=20

# Read the Azure Attestation Report from vTPM NV Index 0x01400001
echo "Read the Azure Attestation Report from vTPM NV Index 0x01400001"
(sudo tpm2_nvread -C o $AR_NV_INDEX) > ./stored-report.bin

# Extract SEV-SNP AR from the Azure AR
echo "Extract SEV-SNP AR from the Azure AR"
dd if=./stored-report.bin \
	skip=$REPORT_OFFSET \
	bs=1 \
	count=$REPORT_SIZE \
	of=./report.bin \
	status=none

# Fetch the VCEK Certificate Chain PEM from Microsoft Azure IMDS
echo "Fetch VCEK Certificate Chain PEM from Microsoft Azure IMDS"
curl -H Metadata:true http://169.254.169.254/metadata/THIM/amd/certification \
	> imds-response.json
(jq -r '.vcekCert , .certificateChain' < imds-response.json) \
	> vcek-cert-chain.pem

# Extract the Runtime Claims from the Azure AR
echo "Extract the Runtime Claims from the Azure AR"
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

# Build the MAA Request Payload
echo "Build the MAA Request Payload"

## Generate nonce
NONCE=$(openssl rand -hex 32)

## Convert the SEV-SNP AR, VCEK Certificate Chain, and Runtime Claims to Base64URL
REPORT_B64URL=$(basenc --base64url -w 0 < report.bin)
VCEK_CERT_B64URL=$(basenc --base64url -w 0 < vcek-cert-chain.pem)
RUNTIME_CLAIMS_B64URL=$(basenc --base64url -w 0 < runtime-claims.json)

## Build the Report Payload
jq -n \
	--arg report "$REPORT_B64URL" \
	--arg vcekCertChain "$VCEK_CERT_B64URL" \
	'{
	  "SnpReport" : $report,
	  "VcekCertChain" : $vcekCertChain
	}' \
	> report-payload.json

REPORT_JSON_B64URL=$(basenc --base64url < report-payload.json | tr -d '\n')

## Build the MAA Request Payload
jq -n \
	--arg report "$REPORT_JSON_B64URL" \
	--arg runtimeData "$RUNTIME_CLAIMS_B64URL" \
	--arg nonce "$NONCE" \
	'{
	  "report" : $report,
	  "runtimeData" : {
			"data" : $runtimeData,
			"dataType" : "JSON"
		},
	  "nonce" : $nonce
	}' \
	> maa-request-payload.json

# Send the MAA Request Payload to Microsoft Azure Attestation
echo "Send the MAA Request Payload to Microsoft Azure Attestation"
curl -s -X POST "$MAA_REQUEST_URL" \
	-H "Content-Type: application/json" \
	-d "$(< maa-request-payload.json)" \
	> maa-response.json
	
# Display the MAA Response
echo "Display the MAA Response"
jq < maa-response.json

# Display the JSON Web Token
echo "Display the JSON Web Token"

(jq -r '.token' < maa-response.json) > token.txt
awk -F. '{print $1}' token.txt \
  | awk '{ s=$0; while (length(s)%4!=0) s=s"="; print s }' \
  | basenc -d --base64url > token-header.json
awk -F. '{print $2}' token.txt \
  | awk '{ s=$0; while (length(s)%4!=0) s=s"="; print s }' \
  | basenc -d --base64url > token-payload.json

echo "Header:"
jq < token-header.json
echo "Payload:"
jq < token-payload.json

# Parse SEV-SNP AR
echo "Parse SEV-SNP AR"
snpguest display report report.bin
