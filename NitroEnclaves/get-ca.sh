#!/bin/bash
# Get the CA certificate

wget https://aws-nitro-enclaves.amazonaws.com/AWS_NitroEnclaves_Root-G1.zip
unzip -j AWS_NitroEnclaves_Root-G1.zip -d client/
rm AWS_NitroEnclaves_Root-G1.zip

echo "✅ CA certificate downloaded and extracted to client/root.pem"
