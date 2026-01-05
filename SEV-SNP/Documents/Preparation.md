# CVM Environment Setup
[Index](./index.md)

## Core build chain
```bash
sudo apt update
sudo apt install -y build-essential git cmake clang
```

## Core utility tools
```bash
sudo apt update
sudo apt install -y coreutils
```

## Go ≥ 1.19
Used to build `go-sev-guest` and `jwker`.

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
Used to build `snpguest`.

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## snpguest ≥ 0.9.2
Used to get/verify SEV-SNP AR and VEK certs.

When using the report subcommand in an Azure CVM, the `--platform` flag must be set. To enable this flag, you need to build with the `--features hyperv` option.

### AWS/GCP/Sakura/Local Verifier
```bash
git clone https://github.com/virtee/snpguest 
cd snpguest
cargo build -r
sudo mv target/release/snpguest /usr/local/bin/
```

### Azure CVM
```bash
sudo apt update
sudo apt install -y pkg-config libtss2-dev
git clone https://github.com/virtee/snpguest -b v0.9.2
cd snpguest
cargo build -r --features hyperv
sudo mv target/release/snpguest /usr/local/bin/
cd ..
```

## go-sev-guest ≥ 0.14.1
Alternative to `snpguest`. It provides richer verification function.

The CLI name is too simple, so it is renamed.

```bash
git clone https://github.com/google/go-sev-guest.git
cd go-sev-guest
go get ./client

go build ./tools/attest
go build ./tools/check
go build ./tools/show

sudo mv attest /usr/local/bin/go-sev-guest-attest
sudo mv check /usr/local/bin/go-sev-guest-check
sudo mv show /usr/local/bin/go-sev-guest-show
cd ..
```

## tpm2-tools
Used to get SEV-SNP AR (and vTPM Quote) in an Azure CVM.

```bash
sudo apt update
sudo apt install -y tpm2-tools
```

## jwker
Used to convert keys from JWK to PEM.

```bash
go install github.com/jphastings/jwker/cmd/jwker@latest
```

## jq
Used to handle JSON. It is usually pre-installed.

```bash
sudo apt update
sudo apt install -y jq
```

## Docker image

You can use the included Dockerfile `./Dockerfile` to build a clean work environment with all the necessary packages installed.

### Install Docker
```bash
sudo apt update
sudo apt install -y docker.io
```

### Build the Dockerfile
```bash
# AWS/GCP
sudo docker build . -t <image-name>

# Azure CVM
sudo docker build . -t <image-name> --build-arg AZURE_CVM=true
```

### Start the Docker container

```bash
# AWS/GCP
sudo docker run -it --rm \
    --device /dev/sev-guest \
    -v <script-file>:/workspace/<script-file> \
    <image-name> /bin/bash

# Azure CVM
sudo docker run -it --rm \
    --device /dev/tpm0 \
    --device /dev/tpmrm0 \
    -v <sample-code-or-dir>:/workspace/<destination-file-or-dir> \
    <image-name> /bin/bash
```

When you run the Docker container with the above command, you have root privileges by default, so `sudo` in the sample scripts is not necessary. (However, since the `sudo` command is installed, the samples will work without modification.)
