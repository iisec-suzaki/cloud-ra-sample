FROM rust:1.90-bookworm as builder

WORKDIR /app

COPY rs/ ./rs/

RUN cd rs && cargo build --release

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/rs/target/release/sample-enclave /app/rs/target/release/sample-enclave

RUN chmod +x /app/rs/target/release/sample-enclave

CMD ["/app/rs/target/release/sample-enclave"]
