#!/bin/bash
# Azure TDX Remote Attestation using Trust Authority CLI (Quote Generation) and Microsoft Azure Attestation (Quote Verification)

set -e
set -o pipefail

# Microsoft Azure Attestation URL
VERIFIER_URL="https://sharedeus.eus.attest.azure.net"
TEE_TYPE="TdxVm"
API_VERSION="2025-06-01"
MAA_REQUEST_URL="$VERIFIER_URL/attest/$TEE_TYPE?api-version=$API_VERSION"

# Prepare 64-byte user data and nonce
echo "Prepare 64-byte user data and nonce"
openssl rand 64 > user-data.bin
openssl rand 64 > nonce.bin
base64 -w 0 user-data.bin > user-data.txt
base64 -w 0 nonce.bin > nonce.txt

# Request TD Quote
# 1. Write H(nonce||user-data) to NV index 0x01400002
# 2. Read Azure Attestation Report from NV index 0x01400001
# 3. Extract TD Report from Azure Attestation Report
# 4. Request TD Quote from Host's TD Quoting Enclave (169.254.169.254/acc/tdquote)
echo "Request TD Quote:"
echo "	1. Write H(nonce||user-data) to NV index 0x01400002"
echo "	2. Read Azure Attestation Report from NV index 0x01400001"
echo "	3. Extract TD Report from Azure Attestation Report"
echo "	4. Request TD Quote from Host's TD Quoting Enclave (169.254.169.254/acc/tdquote)"
(sudo trustauthority-cli quote --nonce "$(< nonce.txt)" --user-data "$(< user-data.txt)" --aztdx) > ta-out.txt
grep "Quote: " ta-out.txt | sed "s/Quote: //g" | base64 -d > quote.bin

# Read Runtime Claims
## Set the NV Index and Offsets for Azure Attestation Report
AR_NV_INDEX=0x01400001
RUNTIME_DATA_SIZE_OFFSET=1216
RUNTIME_DATA_OFFSET=1216
RUNTIME_CLAIM_SIZE_OFFSET=16
RUNTIME_CLAIM_OFFSET=20

## Read the Azure Attestation Report
echo "Read the Azure AR from vTPM NV Index 0x01400001"
(sudo tpm2_nvread -C o $AR_NV_INDEX) > ./stored-report.bin

## Extract Runtime Data
RUNTIME_DATA_SIZE=$(od -An -tu4 -N4 -j $RUNTIME_DATA_SIZE_OFFSET stored-report.bin | tr -d ' ')

dd if=stored-report.bin \
	bs=1 \
	skip=$RUNTIME_DATA_OFFSET \
	count="$RUNTIME_DATA_SIZE" \
	of=runtime-data.bin \
	status=none

## Extract Runtime Claims
echo "Extract Runtime Claims from Azure AR"
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

## Convert the TDX Quote and Runtime Claims to Base64URL
QUOTE_B64URL=$(basenc --base64url -w 0 < ./quote.bin)
RUNTIME_CLAIMS_B64URL=$(basenc --base64url -w 0 < ./runtime-claims.json)

## Build the MAA Request Payload
jq -n \
	--arg quote "$QUOTE_B64URL" \
	--arg runtimeData "$RUNTIME_CLAIMS_B64URL" \
	--arg nonce "$NONCE" \
	'{
	  "quote" : $quote,
	  "runtimeData" : {
			"data" : $runtimeData,
			"dataType" : "JSON"
		},
	  "nonce" : $nonce
	}' \
	> maa-request-payload.json

# Send the MAA Request Payload to Microsoft Azure Attestation
echo "Sending the MAA Request Payload to Microsoft Azure Attestation $MAA_REQUEST_URL"
curl -s -X POST "$MAA_REQUEST_URL" \
	-H "Content-Type: application/json" \
	-d "$(< maa-request-payload.json)" \
	> maa-response.json
	
# Display the MAA Response
echo "Displaying the MAA Response"
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

# Compare H(nonce || rawUserData) with the user-data in the runtime-claims.json
echo "Compare H(nonce || rawUserData) with the user-data in the runtime-claims.json"
jq -r '."user-data"' runtime-claims.json > runtime-claims-user-data.txt
cat nonce.bin user-data.bin | sha512sum | awk '{print $1}' > user-data-hash.txt

diff --ignore-case -s user-data-hash.txt runtime-claims-user-data.txt

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
