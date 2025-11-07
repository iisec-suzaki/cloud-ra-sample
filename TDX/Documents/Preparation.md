# CVM Environment Setup
[Index](./index.md)

## Core build chain
```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y build-essential git clang
```

## Core utility tools
```bash
sudo apt update
sudo apt install -y coreutils
```

## Go ≥ v1.19
Used to build `go-tdx-guest`.

The version of `golang` installed using `apt` may be too old. We recommend using the latest binary distributed on the official website (currently v1.25.0).

```bash
wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz
rm go1.25.0.linux-amd64.tar.gz
export GOPATH="$HOME/go"
export PATH=$PATH:"$GOPATH/bin":"/usr/local/go/bin"
echo "export GOPATH="$HOME/go"" >> ~/.bashrc
echo "export PATH=$PATH:"$GOPATH/bin":"/usr/local/go/bin"" >> ~/.bashrc
```

## Rust ≥ 1.88.0
Used to build `tdx-quote-parser`.

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## SGX-DCAP-QvL
Used to get a TDX Quote on a plain TDX CVM and verify it. The CLI name is too simple, so it is renamed to `sgx-dcap-qvl-app` for use.

```bash
# dependencies
sudo apt update
sudo apt install -y lsb-release

# Set Intel GPG key
wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | \
sudo gpg --dearmor -o /usr/share/keyrings/intel-sgx-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-sgx-keyring.gpg] https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/intel-sgx.list

# Update apt package index
sudo apt update

# Intel SGX DCAP and TDX SDK
sudo apt install -y tdx-qgs libsgx-dcap-ql-dev libsgx-dcap-quote-verify-dev \
	libsgx-dcap-default-qpl-dev libtdx-attest-dev libssl-dev \
	libcurl4-openssl-dev libprotobuf-dev

# Build SGX-DCAP-QvL
git clone https://github.com/intel/SGXDataCenterAttestationPrimitives
cd SGXDataCenterAttestationPrimitives
git submodule update --init --recursive

cd SampleCode/QuoteVerificationSample
make QVL_ONLY=1

sudo mv app /usr/local/bin/sgx-dcap-qvl-app
cd ../../..
```

## go-tdx-guest
Used to get a TDX Quote on a plain TDX CVM and verify it. The CLI name is too simple, so it is renamed to the format `go-tdx-guest-*` for use.

```bash
# Build go-tdx-guest
git clone https://github.com/google/go-tdx-guest
cd go-tdx-guest

go build ./tools/attest
go build ./tools/check

sudo mv attest /usr/local/bin/go-tdx-guest-attest
sudo mv check /usr/local/bin/go-tdx-guest-check
cd ..
```

## Trust Authority Client for Go v1.8.0
Used to get a TDX Quote on an Azure TDX CVM. The complex interactions with vTPM and IMDS are encapsulated. Since the feature to get only a TDX Quote was deprecated in v1.9.0, we use v1.8.0 where this feature is available. (It has now been replaced by a feature to get the whole Attestation Evidence including Collateral, but an Intel PCS API key is required to use this.)

```bash
curl -sL https://raw.githubusercontent.com/intel/trustauthority-client-for-go/main/release/install-tdx-cli.sh \
	| sudo CLI_VERSION=v1.8.0 bash -
```

## tdx-quote-parser ≥ v0.1.0
Used to parse and pretty-print a TDX Quote.

```bash
git clone https://github.com/MoeMahhouk/tdx-quote-parser
cd tdx-quote-parser
cargo build -r
sudo mv ./target/release/parserV4 /usr/local/bin/
sudo mv ./target/release/parserV5 /usr/local/bin/
cd ..
```

## tpm2-tools
```bash
sudo apt update
sudo apt install -y tpm2-tools
```
