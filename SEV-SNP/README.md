# SEV SNP RA Sample
This repository contains sample code and tutorials for performing Remote Attestation (RA) on AMD SEV-SNP enabled CVMs from major Cloud Service Providers (CSPs).

## Requirements
### General
- Golang ≥ 1.18
- Rust ≥ 1.88.0
- GCC ≥ 13.3.0
- [jwker](https://github.com/jphastings/jwker) ≥ 0.2.1
- jq ≥ 1.7

### SEV-SNP tools
- [go-sev-guest](https://github.com/google/go-sev-guest) ≥ 0.14.1
   - v0.14.1 does not support Turin's TCB_VERSION ([Issue #153](https://github.com/google/go-sev-guest/issues/153))
   - v0.14.1 does not *fully* support SEV-SNP ABI ver. 1.58 / attestation reports of version 5  (see [PR #175](https://github.com/google/go-sev-guest/pull/175))
- [snpguest](https://github.com/virtee/snpguest) ≥ 0.9.2

### TPM tools
- [tpm2-tools](https://github.com/tpm2-software/tpm2-tools) ≥ 5.7

## Installation
For instructions on how to install dependencies, see [CVM Environment Setup](/SEV-SNP/Documents/Preparation.md).

Clone this repository on your CVM. No build is required as it only contains scripts.

```bash
git clone https://github.com/acompany-develop/cloud-ra-sample
```

## Directory Structure

```plaintext
.
├── SEV-SNP
│  ├── AWS
│  ├── Azure
│  ├── GCP
│  ├── Sakura
│  ├── common
│  └── Documents
...
```

For an overview of all SEV-SNP related documents, see [index.md](/SEV-SNP/Documents/index.md).

## Sample Script Overview

The correspondence between the sample code and CSPs is as follows:

| Script | CSP | Endorsement Key | Report Generation | Verification |
| :-- | :-- | :-- | :-- | :-- |
| `AWS/aws-snp-xra-by-snpguest.sh` | AWS | VLEK | `snpguest` | `snpguest` |
| `Azure/azure-snp-ra-by-maa.sh` | Azure CVM only | VCEK |`tpm2-tools` | MAA |
| `Azure/azure-snp-sra-by-snpguest.sh` | Azure CVM only | VCEK | `snpguest` | `snpguest` |
| `Azure/azure-snp-sra-by-tpm2-tools.sh` | Azure CVM only | VCEK | `tpm2-tools` | `snpguest` |
| `GCP/gcp-snp-sra-by-go-sev-guest.sh` | GCP | VCEK | `go-sev-guest` | `go-sev-guest` |
| `GCP/gcp-snp-sra-by-snpguest.sh` | GCP | VCEK | `snpguest` | `snpguest` |
| `Sakura/sakura-snp-sra-by-go-sev-guest.sh` | Sakura | VCEK | `go-sev-guest` | `go-sev-guest` |
| `Sakura/sakura-snp-sra-by-snpguest.sh` | Sakura | VCEK | `snpguest` | `snpguest` |
| `GCP/gcp-snp-xra-by-snpguest.sh` | GCP | VCEK | `snpguest` | `snpguest` |
| `common/common-snp-xra-by-go-sev-guest.sh` | AWS & GCP | VCEK & VLEK | `go-sev-guest` | `go-sev-guest` |
|
| `Azure/azure-snp-vtpm-ra-by-tpm2-tools.sh` | Azure CVM only | VCEK | `tpm2-tools` | `tpm2-tools` (vTPM) + `snpguest` (SNP) |

The Attester (Guest OS on the CVM) cryptographically proves to the Relying Party (remote user) that it is running in an SEV-SNP environment. The Relying Party has the received evidence verified by a Verifier.

Note that in the sample codes, the steps for the Relying Party/Verifier are also executed on the Attester side, but the verification part can also be executed by a Relying Party/Verifier outside the SEV-SNP environment.

With the exception of the scripts for Azure CVMs, they are compatible with other CSPs and on-premises SEV-SNP CVMs (as long as no special modifications have been made to the configuration). However, when performing XRA, it is necessary to cache some or all of the VEK certificate chain on the host side (for example, using the `import` subcommand of the `snphost` tool). In AWS and GCP, the host side is already cached, so no host-side operations are required. (And of course, users cannot perform host-side operations.)

Only `azure-snp-vtpm-ra-by-tpm2-tools.sh` consistently performs verification of not only the SNP Report but also the vTPM Quote.

### `AWS/aws-snp-xra-by-snpguest.sh`
1. Generate nonce
2. Request Standard Attestation Report from AMD-SP
3. Get host-cached VLEK certificate via AMD-SP
4. Fetch ASVK, ARK certificates from AMD KDS
5. Verify the Chain of Trust: ARK→ASVK→VLEK→AR
6. Verify REPORT_DATA against the nonce

Compatible with AWS. Also usable in other environments as long as the AR is signed with VLEK and an Extended AR (a normal Attestation Report with the VCEK/VLEK certificate or certificate chain cached in the HV's memory appended to the end) can be fetched by accessing `/dev/sev-guest`.

### `Azure/azure-snp-ra-by-maa.sh`
1. At VM startup the paravisor obtains an SNP Attestation Report (AR) from AMD-SP, builds an *Azure-specific format Attestation Report* (**HCL Report**), and writes it to the vTPM NV index `0x01400001`
2. Read the HCL Report from the vTPM NV index
3. Extract the SNP AR and Runtime Claims JSON from the HCL Report (Runtime Claims → source of REPORT_DATA)
4. Fetch the host-cached VCEK certificate chain via Azure Instance Metadata Service (IMDS)
5. Send `AR + RuntimeClaims + VCEK chain` to Microsoft Azure Attestation (MAA) for verification
6. Receive an Attestation Token (JWT) and decode it
7. Compare `HASH(nonce || user-data)` with the value embedded in Runtime Claims

In this sample script only, the roles of Relying Party and Verifier are separated.

- Relying Party: Remote User
- Verifier: MAA Provider

For Azure CVM only.

### `Azure/azure-snp-sra-by-snpguest.sh`
0. At VM startup, the paravisor gets an SNP AR from the AMD-SP, builds HCL report, and writes it to the vTPM NV index
1. Read the HCL Report written at VM startup from the vTPM NV index and then extract the SNP report from it
2. Fetch VCEK, ASK, ARK certificates from AMD KDS
3. Verify the Chain of Trust: ARK→ASK→VCEK→AR

For Azure CVM only.

### `Azure/azure-snp-sra-by-tpm2-tools.sh`
1. Generate nonce
2. Write the nonce to the vTPM NV index `0x01400002`
3. Paravisor detects the write, obtains a **new** SNP AR with the nonce in REPORT_DATA, builds HCL Report, and stores it to NV `0x01400001`
4. Read the fresh SNP AR + Runtime Claims JSON from the vTPM NV index
5. Fetch VCEK, ASK, ARK certificates from AMD KDS
6. Verify the Chain of Trust `ARK → ASK → VCEK → AR`
7. Verify REPORT_DATA equals `HASH(RuntimeClaims JSON)`
8. Verify `RuntimeClaims["user-data"]` equals the nonce

For Azure CVM only.

### `Azure/azure-snp-vtpm-ra-by-tpm2-tools.sh`
0. At VM startup, the paravisor gets an SNP AR from the AMD-SP, builds HCL report, and writes it to the vTPM NV index
1. Read the SNP Report + Runtime Claims JSON from the vTPM NV index
2. Fetch VCEK, ASK, ARK certificates from AMD KDS
3. Verify the Chain of Trust: ARK→ASK→VCEK→AR
4. Verify that the hash of the Runtime Claims matches the Report Data of the SNP AR
5. Generate nonce
6. vTPM generates a Quote from the nonce
7. Get the TPM Quote and AK Pub from the vTPM
8. Verify the TPM Quote with the AK Pub and nonce
9. Verify that the AK Pub is bound within the Runtime Claims

(0) to (4) are SNP Attestation, (5) to (8) are TPM Attestation, and (9) connects the Chain of Trust between TPM and SNP.

For Azure CVM only.

### `GCP/gcp-snp-sra-by-go-sev-guest.sh`
1. Generate nonce
2. Request Attestation Report from AMD-SP with nonce as REPORT_DATA
3. Fetch VCEK, ASK, ARK certificates from AMD KDS
4. Verify the Chain of Trust ARK→ASK→VCEK→AR and nonce

Compatible with GCP. Also usable in other environments as long as the AR is signed with `VCEK` and an AR can be fetched by accessing `/dev/sev-guest`.

### `GCP/gcp-snp-sra-by-snpguest.sh`
1. Generate nonce
2. Request Attestation Report from AMD-SP with nonce as REPORT_DATA
3. Fetch VCEK, ASK, ARK certificates from AMD KDS
4. Verify the Chain of Trust ARK→ASK→VCEK→AR and nonce

Compatible with GCP. Also usable in other environments as long as the AR is signed with VCEK and an AR can be fetched via `/dev/sev-guest`.

### `GCP/gcp-snp-xra-by-snpguest.sh`
1. Generate nonce
2. Request Attestation Report from AMD-SP with nonce as REPORT_DATA
3. Get host-cached VCEK, ASK, ARK certificates via AMD-SP
4. Verify the Chain of Trust ARK→ASK→VCEK→AR and nonce

Compatible with GCP. Also usable in other environments as long as the AR is signed with VCEK and an Extended AR (with the whole VCEK cert chain) can be fetched via `/dev/sev-guest`.

### `Sakura/sakura-snp-sra-by-go-sev-guest.sh`
1. Generate nonce
2. Request Attestation Report from AMD-SP with nonce as REPORT_DATA
3. Fetch VCEK, ASK, ARK certificates from AMD KDS
4. Verify the Chain of Trust ARK→ASK→VCEK→AR and nonce

Compatible with Sakura. Also usable in other environments as long as the AR is signed with `VCEK` and an AR can be fetched by accessing `/dev/sev-guest`.

### `Sakura/sakura-snp-sra-by-snpguest.sh`
1. Generate nonce
2. Request Attestation Report from AMD-SP with nonce as REPORT_DATA
3. Fetch VCEK, ASK, ARK certificates from AMD KDS
4. Verify the Chain of Trust ARK→ASK→VCEK→AR and nonce

Compatible with Sakura. Also usable in other environments as long as the AR is signed with VCEK and an AR can be fetched via `/dev/sev-guest`.

### `common/common-snp-xra-by-go-sev-guest.sh`
1. Generate nonce
2. Request Extended Attestation Report from AMD-SP with nonce as REPORT_DATA
3. Fetch missing VEK certs from AMD-SP
4. Verify the Chain of Trust ARK→ASK(ASVK)→VCEK(VLEK)→AR and nonce

Compatible with AWS/GCP. Also usable in other environments as long as an Extended AR can be fetched via `/dev/sev-guest`.

## Usage
### Direct Execution
1. Clone this repository on your CVM
2. Install the necessary dependencies (see [CVM Environment Setup](./Documents/Preparation.md))
3. Copy the shell script you want to run to a working directory
4. Modify the environment variables in the shell script according to your execution environment
5. Execute
   ```bash
   bash <script-file>
   ```

If you get an error related to the permissions of files generated during the process (files generated with root privileges), either grant the appropriate permissions or run the entire script with root privileges.

### Execution within a Docker container
1. Clone this repository on your CVM
2. Modify the environment variables in the shell script according to your execution environment
3. Build the Docker image, specifying the directory where the Dockerfile for the target environment is located
   ```bash
   # AWS/GCP
   sudo docker build . -t <image-name>

   # Azure CVM
   sudo docker build . -t <image-name> --build-arg AZURE_CVM=true
   ```
4. Start the Docker container, passing through the necessary devices + passing the script you want to run (can be a single file or a directory)
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
5. Execute in the Docker container
   ```bash
   bash <script-file>
   ```
