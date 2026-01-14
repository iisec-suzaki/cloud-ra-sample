# TDX RA Sample
This repository contains sample code and tutorials for performing Remote Attestation (RA) on Intel TDX enabled CVMs for Azure and GCP.

## Requirements
### General
* Golang ≥ 1.18
* Rust ≥ 1.88.0
* GCC ≥ 13.3.0
* jq ≥ 1.7

### TDX tools
* [SGX-DCAP](https://github.com/intel/SGXDataCenterAttestationPrimitives) ≥ 1.23
* [go-tdx-guest](https://github.com/google/go-tdx-guest) ≥ 0.3.1
* [Trust Authority Client for Go](https://github.com/intel/trustauthority-client-for-go) == 1.8.0
  * Unavailable after v1.9.0
* [tdx-quote-parser](https://github.com/MoeMahhouk/tdx-quote-parser) ≥ 0.1.0

### TPM tools
* [tpm2-tools](https://github.com/tpm2-software/tpm2-tools) ≥ 5.7

## Installation
For instructions on how to install the prerequisite software, see [CVM Environment Setup](/TDX/Documents/Preparation.md).

## Directory Structure

```plaintext
.
├── TDX
│  ├── Azure
│  ├── GCP
│  └── Documents
...
```

For a complete list of TDX related documents, see [index.md](/TDX/Documents/index.md).

## Sample Script Overview

The correspondence between the sample code and CSPs is as follows:

| Script | CSP | Quote Generation | Verification |
| :--- | :--- | :--- | :--- |
| `azure/azure-tdx-ra-by-maa.sh` | Azure CVM only | `trustauthority-cli` | MAA |
| `azure/azure-tdx-ra-by-go-tdx-guest.sh` | Azure CVM only | `trustauthority-cli` | `go-tdx-guest` |
| `azure/azure-tdx-ra-by-dcap-qvl.sh` | Azure CVM only | `trustauthority-cli` | `DCAP-QVL` |
| `gcp/gcp-tdx-ra-by-go-tdx-guest.sh` | GCP | `go-tdx-guest` | `go-tdx-guest` |
| `gcp/gcp-tdx-ra-by-sgx-dcap-qvl.sh` | GCP | `go-tdx-guest` | `DCAP-QVL` |

The Attester (Guest OS on the CVM) proves to the Relying Party (remote user) that it is running in a TDX-protected VM. In these samples the verification phase is executed locally for simplicity, but the Verifier side can also run off-platform.

### `azure/azure-tdx-ra-by-maa.sh`
1. Generate 64-byte user-data and nonce
2. Write `HASH(nonce || user-data)` to the vTPM NV index `0x01400002`
3. Read the *Azure-specific format Attestation Report* (HCL Report) from NV index `0x01400001`
4. Extract the TD Quote from the HCL Report via `trustauthority-cli`
5. Extract Runtime Claims JSON from the HCL Report
6. Send `Quote + RuntimeClaims + nonce` to Microsoft Azure Attestation (MAA) and receive an attestation result in JWT format
7. Decode and display the JWT
8. Compare the hash `H(nonce || user-data)` with the value embedded in Runtime Claims

### `azure/azure-tdx-ra-by-go-tdx-guest.sh`
1. Perform steps (1)-(4) in the MAA sample
2. Extract Runtime Claims and calculate `HASH(RuntimeClaims)`
3. Verify the TD Quote locally with `go-tdx-guest`, passing `HASH(RuntimeClaims)` as REPORT_DATA
4. Compare `H(nonce || user-data)` with the field in Runtime Claims

### `azure/azure-tdx-ra-by-dcap-qvl.sh`
1. Perform steps (1)-(4) in the MAA sample
2. Configure Intel DCAP QvL (`/etc/sgx_default_qcnl.conf`)
3. Verify the TD Quote with SGX-DCAP-QvL
4. Extract Runtime Claims, compute `HASH(RuntimeClaims)` and verify it against the Quote REPORT_DATA with `go-tdx-guest`

### `gcp/gcp-tdx-ra-by-go-tdx-guest.sh`
1. Generate 64-byte random REPORT_DATA
2. Request a TD Quote with the chosen REPORT_DATA
3. Verify the TD Quote locally with `go-tdx-guest` (optionally fetching Intel collateral)

### `gcp/gcp-tdx-ra-by-sgx-dcap-qvl.sh`
1. Same as the previous sample to obtain a TD Quote
2. Configure Intel DCAP QvL
3. Verify the TD Quote with SGX-DCAP-QvL

## Usage
1. Clone this repository on your CVM
2. Install the dependencies (see [CVM Environment Setup](./Documents/Preparation.md))
3. Copy the shell script you wish to run to a working directory
4. Adjust environment variables in the script to match your environment
5. Execute
   ```bash
   bash <script-file>
   ```

If you encounter permission errors for files generated with root privileges, either adjust their ownership/permissions or run the entire script with `sudo`.

