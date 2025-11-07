FROM ubuntu:24.04

ARG AZURE_CVM=false

# Install basic tools
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    bash \
    cmake \
    coreutils \
    diffutils \
    git \
    sudo \
    wget \
    xxd \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | bash -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

# Install Go
RUN wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz && \
    rm go1.25.0.linux-amd64.tar.gz

ENV GOPATH="$HOME/go"
ENV PATH=$PATH:"$GOPATH/bin"
ENV PATH=$PATH:"/usr/local/go/bin"

# Install jq/jwker/tpm2-tools/pkg-config/libtss2-dev (if AZURE_CVM is true)
RUN if [ "$AZURE_CVM" = "true" ]; then \
      apt-get update && \
      apt-get install -y jq tpm2-tools pkg-config libtss2-dev && \
      rm -rf /var/lib/apt/lists/* && \
      go install github.com/jphastings/jwker/cmd/jwker@latest; \
    else \
      echo "Skipping jq/jwker/tpm2-tools/pkg-config/libtss2-dev install"; \
    fi

# Clone and build snpguest
RUN git clone https://github.com/virtee/snpguest && \
    cd snpguest && \
    if [ "$AZURE_CVM" = "true" ]; then \
        cargo build --release --features hyperv; \
    else \
        cargo build --release; \
    fi && \
    mv target/release/snpguest /usr/local/bin/snpguest && \
    rm -rf /snpguest

# Install go-sev-guest
RUN git clone https://github.com/google/go-sev-guest.git && \
    cd go-sev-guest && \
    go build ./tools/attest && \
    go build ./tools/check && \
    go build ./tools/show && \
    mv attest /usr/local/bin/go-sev-guest-attest && \
    mv check /usr/local/bin/go-sev-guest-check && \
    mv show /usr/local/bin/go-sev-guest-show && \
    rm -rf /go-sev-guest

WORKDIR /workspace
