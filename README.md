# Cloud Remote Attestation Sample
This project provides comprehensive sample code and tutorials for implementing Remote Attestation across different isolation technologies in cloud environments. Remote Attestation is a cryptographic protocol that allows a remote user (a relying party) to verify the integrity and authenticity of a computing environment (an attester).

## News
- Add [Sakura Internet](https://www.sakura.ad.jp/) [Confidential Computing (AMD SEV-SNP)](https://cloud.sakura.ad.jp/products/server/confidential-vm/) RA samples.
- Presentation at [FOSDEM2025 Confidential Computing Devroom](https://fosdem.org/2026/schedule/track/confidential-computing/) entitled "[Lesson from Cloud Confidential Computing Remote Attestation Sample](https://fosdem.org/2026/schedule/event/RVSEMG-cloud-ra-sample/)"  

## Detial

### Supported Technologies
- **AMD SEV-SNP** (Secure Encrypted Virtualization - Secure Nested Paging) - Hardware-based, VM-level isolation
- **Intel SGX** (Software Guard Extensions) - Hardware-based, Process-level isolation
- **Intel TDX** (Trust Domain Extensions) - Hardware-based, VM-level isolation
- **AWS Nitro Enclaves** - Software (Hypervisor)-based, Container-level isolation

### Supported Cloud Providers
- **Amazon Web Services (AWS)**
- **Microsoft Azure**
- **Google Cloud Platform (GCP)**
- **Sakura Internet (Sakura)**

### Support Matrix Table

| | SEV-SNP | SGX | TDX | Nitro Enclaves |
| :- | :-: | :-: | :-: | :-: |
| AWS | ✅ | | | ✅ |
| Azure | ✅ | ✅ | ✅ | |
| GCP | ✅ | | ✅ | |
| Sakura | ✅ | | | |

## Directory Structure

```
.
├── SEV-SNP/        # AMD SEV-SNP RA samples and docs
├── SGX/            # Intel SGX RA sample and docs
├── TDX/            # Intel TDX RA samples and docs
├── NitroEnclaves/  # AWS Nitro Enclaves RA samples and docs
└── Documents/      # General documentation
```

## Getting Started
Choose your target technology and follow the specific documentation:
- For **SEV-SNP**: See [SEV-SNP Documentation](./SEV-SNP/Documents/)
- For **TDX**: See [TDX Documentation](./TDX/Documents/)
- For **SGX**: See [SGX Documentation](./SGX/README.md)
- For **Nitro Enclaves**: See [Nitro Enclaves Documentation](./NitroEnclaves/README.md)

## Acknowledgment
This work is supported by JST K Program Grant Number JPMJKP24U4, Japan.
