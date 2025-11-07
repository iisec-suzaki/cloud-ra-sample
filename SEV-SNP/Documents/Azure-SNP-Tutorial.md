# Azure SEV-SNP RA Tutorial
[Index](./index.md)

This document explains the procedure for setting up an SEV-SNP enabled CVM on Microsoft Azure and performing SEV-SNP RA. This tutorial uses `tpm2-tools` to fetch the SEV-SNP AR, and `snpguest` to fetch the VCEK certificate chain and verify the AR.

### Note: Test Environment
This tutorial has been tested in the following environments:

- Instance: Microsoft Azure — Standard DC2asv5 or DC2asv6
- CPU: AMD 3rd Gen EPYC (Milan) or AMD 4th Gen EPYC (Genoa)
- Memory: 8 GiB
- OS: Ubuntu 24.04.1
- Kernel: 6.11.0-1018-azure
- Storage Size: 32 GiB

## Deploy an SEV-SNP CVM
This section explains how to set up an SEV-SNP enabled VM instance on Azure and confirm that SEV-SNP is enabled. The following information is based on the state as of September 2025.

### Create a VM instance from the Web Console

#### Region/Availability zone
Select a region/zone that allows you to choose a [size family that supports SEV-SNP](#size-family). You can search from the Azure CLI with the following command (for DC2asv5).

```bash
az vm list-skus \
  --size Standard_DC2as_v5 \
  --all \
  --query "[?name=='Standard_DC2as_v5']"
```

This tutorial has been confirmed to work in **Japan East**.

#### Security type
- Confidential virtual machines
  - Secure boot: Enabled \[default: Enabled\] 
  - vTPM: Enabled (fixed)
  - Integrity monitoring: Enabled or Disabled \[default: Disabled\]

#### Image (OS image)
Press "See all images". You can narrow down the OS images that can be used with CVMs by applying the "Security Type: Confidential" filter. Here, we will use one of the following OSes.
- Ubuntu 24.04 LTS - all plans including Ubuntu Pro
	- Ubuntu Server 24.04 LTS (Confidential VM) - x64 Gen 2
	- Ubuntu Pro 24.04 LTS (Confidential VM) - x64 Gen 2

#### Size family
The following size families support SEV-SNP.

| Size Family | Processor | SEV-SNP Capable |
| :--- | :--- | :--- |
| DCasv5 | AMD 3rd Gen EPYC (Milan) | ✅ |
| DCadsv5 | AMD 3rd Gen EPYC (Milan) | ✅ |
| ECasv5 | AMD 3rd Gen EPYC (Milan) | ✅ |
| ECadsv5 | AMD 3rd Gen EPYC (Milan) | ✅ |
| DCasv6 | AMD 4th Gen EPYC (Genoa) | ✅ |
| DCadsv6 | AMD 4rd Gen EPYC (Genoa) | ✅ |
| ECasv6 | AMD 4rd Gen EPYC (Genoa) | ✅ |
| ECadsv6 | AMD 4rd Gen EPYC (Genoa) | ✅ |

Here, we will use **DC2asv5** (AMD Milan with 2 vCPUs).

#### Disks
- Confidential OS disk encryption>VM disk encryption: enabled

#### Other Settings
These do not affect the enabling of SEV-SNP, so you can configure them as you like.

## Check if SEV-SNP is enabled
In an Azure CVM, SEV-SNP interfaces such as the device node `/dev/sev-guest` are hidden from the guest OS. Therefore, the methods described in [How to Check if SEV-SNP is Enabled](./Check-SNP-Enabled.md) cannot be used. The enabling of SEV-SNP is directly confirmed by performing SEV-SNP RA.

For example, to check the kernel messages for enabled status, running

```bash
sudo dmesg | grep -i sev
```

will display a result like the following, which seems to indicate that "SEV-SNP is supported but only SEV is enabled".

```plaintext
[    0.450742] Memory Encryption Features active: AMD SEV
[    0.450742] SEV: Status: vTom 
[    1.050103] kvm-guest: setup_efi_kvm_sev_migration : EFI live migration variable not found
[    1.349801] systemd[1]: Detected confidential virtualization sev-snp.
[    2.931231] systemd[1]: Detected confidential virtualization sev-snp.
```

Also, to check for the existence of the device node `/dev/sev-guest`, running

```bash
ll /dev/sev-guest
```

will return an error because the device node does not exist.

### Check for the existence of the vTPM device nodes
Azure CVMs are designed with a Remote Attestation flow via vTPM in mind. Therefore, we will check if the vTPM is enabled. Run the following on the CVM.

```bash
ll /dev/tpm*
```

If the output is as follows, the vTPM is enabled.

```plaintext
crw-rw---- 1 tss root  10,   224 Jun 26 06:58 /dev/tpm0
crw-rw---- 1 tss tss  253, 65536 Jun 26 06:58 /dev/tpmrm0
```

## Install necessary tools
Install the necessary software on the guest OS of the CVM. For details, see [CVM Environment Setup](./Preparation.md).

Alternatively, you can use the included Dockerfile.

```bash
sudo apt update
sudo apt install -y docker.io
sudo docker build . -t <image-name> --build-arg AZURE_CVM=true
sudo docker run -it --rm \
    --device /dev/tpm0 \
    --device /dev/tpmrm0 \
    <image-name> /bin/bash
```

If you run the Docker container with the above command, you will have root privileges by default, so `sudo` is not necessary in the following steps.

## Remote Attestation
For details on the Remote Attestation protocol, see [About SEV-SNP Remote Attestation](./About-SEV-SNP-Remote-Attestation.md).

In this tutorial, we will verify the CoT: ARK→ASK→VCEK→AR→AK→vTPM Quote.

### 0. Set variables
We need to extract the necessary data from the Azure-specific format Attestation Report, so we will name their offsets and sizes.

```bash
# vTPM NVS Indices
AR_NV_INDEX=0x01400001
USER_DATA_NV_INDEX=0x01400002
AKPUB_NV_INDEX=0x81000003

# OFFSETS & SIZES
REPORT_OFFSET=32
REPORT_SIZE=1184
RUNTIME_DATA_SIZE_OFFSET=1216
RUNTIME_DATA_OFFSET=1216
RUNTIME_CLAIM_HASH_TYPE_OFFSET=12
RUNTIME_CLAIM_SIZE_OFFSET=16
RUNTIME_CLAIM_OFFSET=20
```

### 1. Send 64-byte user data to vTPM
Prepare 64 bytes of User Data to be bound to the Report Data of the AR. This will be packaged in a Runtime Claims JSON and then hashed. Here, we will simply pass a nonce by writing it tovTPM NV index `0x01400002`.

```bash
openssl rand 64 > user-data.bin
sudo tpm2_nvdefine -C o $USER_DATA_NV_INDEX -s 64
sudo tpm2_nvwrite -C o $USER_DATA_NV_INDEX -i user-data.bin
```

The Paravisor detects this write, re-fetches an AR from the AMD-SP based on the written User Data, stores it in an Azure-specific format Attestation Report (HCL Report), and writes it to the vTPM NV index `0x01400001`. In the initial state, the AR generated at VM boot time (with User Data treated as zero-filled) is written.

Note that if you skip this step, you will be verifying the report generated at VM boot time in the following steps.

### 2. Read Azure Attestation Report from vTPM NV index

Read the Azure-specific format Attestation Report written to the vTPM NV index at VM boot time.

```bash
sudo tpm2_nvread -C o $AR_NV_INDEX > ./stored-report.bin
```

The report has the following structure.

| FIELD          | OFFSET | LENGTH | Note |
| :- | :- | :- | :- |
| HEADER         | 0      | 32 | — |
| REPORT_PAYLOAD | 32     | 1184 | SEV-SNP AR or TD Report + 0 padding |
| RUNTIME_DATA   | 1216   | variable length | Runtime Claims + Header |

### 3. Extract SEV-SNP AR from Azure AR

The Azure AR has a structure of Header + Hardware Report Payload + Runtime Data. We will extract the SEV-SNP AR from this.

```bash
dd if=./stored-report.bin \
	skip=$REPORT_OFFSET \
	bs=1 \
	count=$REPORT_SIZE \
	of=./report.bin \
	status=none
```

### 4. Fetch VCEK Cert Chain

Fetch the VCEK certificate chain from AMD KDS.

```bash
snpguest fetch ca pem certs -r report.bin -e vcek
snpguest fetch vcek pem certs report.bin
```

Note that if you want to fetch from the host via **Microsoft Azure Instance Metadata Service (IMDS)**, you can do so as follows. (Run this inside the guest OS of the Azure CVM.) You will get a PEM file that bundles the VCEK certificate chain.

```bash
curl -H Metadata:true http://169.254.169.254/metadata/THIM/amd/certification \
	> imds-response.json
(jq -r '.vcekCert , .certificateChain' < imds-response.json) \
	> vcek-cert-chain.pem
```

`169.254.169.254` is an IP address that can only be accessed from within the VM, and you can interact with the host through it.

However, to verify using `snpguest`, you need to separate the VCEK/ASK/ARK. Here, we will use the VCEK certificate chain obtained individually from AMD KDS.

### 5. Verify VCEK Cert Chain

Verify that the ARK is a self-signed certificate, that the ARK signs the ASK, and that the ASK signs the VCEK.

```bash
snpguest verify certs certs
```

### 6. Verify signature of AR by VCEK

Verify the signature of the SEV-SNP AR with the VCEK certificate.

```bash
snpguest verify attestation certs report.bin
```

### 7. Verify Report Data in SEV-SNP AR

#### 7.1. Extract Report Data in SEV-SNP AR

First, extract the Report Data (offset: 80 bytes, size: 64 bytes) from the AR.

```bash
dd if=./report.bin \
  skip=80 \
  bs=1 \
  count=64 \
  of=./report-data.bin \
  status=none
```

#### 7.2. Extract Runtime Data in Azure AR
Next, extract the Runtime Data from the Azure AR.

```bash
# Read the size of the Runtime Data
RUNTIME_DATA_SIZE=$(od -An -tu4 -N4 -j $RUNTIME_DATA_SIZE_OFFSET stored-report.bin | tr -d ' ')

# Extract the Runtime Data
dd if=stored-report.bin \
	bs=1 \
	skip=$RUNTIME_DATA_OFFSET \
	count=$RUNTIME_DATA_SIZE \
	of=runtime-data.bin \
	status=none
```

The Runtime Data has the following structure.

| FIELD          | OFFSET | LENGTH | Note |
| :- | :- | :- | :- |
| DATA_SIZE      | 0      | 4 | Runtime Data Size
| VERSION        | 4      | 4 | Azure Report Version
| REPORT_TYPE    | 8      | 4 | TEE type: 2 (SEV-SNP) or 4 (TDX)
| HASH_TYPE      | 12     | 4 | Hash algo: 1 (SHA-256), 2 (SHA-384), 3 (SHA-512)
| CLAIM_SIZE     | 16     | 4 | Runtime Claims Size
| RUNTIME_CLAIMS | 20     | variable length | JSON(AKPub + EKPub + VMconfig + UserData)

#### 7.3. Extract Runtime Claims in Runtime Data
Extract the Runtime Claims JSON from this.

```bash
# Read the size of the Runtime Claims
RUNTIME_CLAIM_SIZE=$(od -An -tu4 -N4 -j $RUNTIME_CLAIM_SIZE_OFFSET runtime-data.bin | tr -d ' ')

# Extract the Runtime Claims
dd if=runtime-data.bin \
	bs=1 \
	skip=$RUNTIME_CLAIM_OFFSET \
	count=$RUNTIME_CLAIM_SIZE \
	of=runtime-claims.json \
	status=none
```

#### 7.4. Hash Runtime Claims
Next, hash the Runtime Claims.

```bash
# Read the hash algorithm
RUNTIME_CLAIM_HASH_TYPE=$(od -An -tu4 -N4 -j $RUNTIME_CLAIM_HASH_TYPE_OFFSET runtime-data.bin | tr -d ' ')

case $RUNTIME_CLAIM_HASH_TYPE in
1) HASH="sha256sum";;
2) HASH="sha384sum";;
3) HASH="sha512sum";;
*) echo "Unknown hash algorithm ($RUNTIME_CLAIM_HASH_TYPE)"; exit 1 ;;
esac
echo "Runtime-Claims hash algorithm = $RUNTIME_CLAIM_HASH_TYPE ($HASH)"

# Hash the Runtime Claims
$HASH runtime-claims.json \
	| awk '{print $1}' \
	| xxd -r -p \
	| (dd bs=64 count=1 conv=sync of=runtime-digest.bin status=none)
```

#### 7.5. Compare
Compare this with the Report Data of the SEV-SNP AR.

```bash
diff -s runtime-digest.bin report-data.bin
```

### 8. Fetch vTPM Quote

Fetch the vTPM Quote. Following the Azure official documentation, we will reflect PCRs: 15, 16, 22.

```bash
openssl rand -hex 32 | tr -d '\n' > nonce.txt

sudo tpm2_quote \
	-c $AKPUB_NV_INDEX \
	-l sha256:15,16,22 \
	-q "$(< nonce.txt)" \
	-m message.msg \
	-s signature.sig \
	-o pcr.pcrs \
	-g sha256
```

### 9. Read AK Pub from vTPM NV index

Read the AK public key written to from the vTPM NV index.

```bash
sudo tpm2_readpublic -c $AKPUB_NV_INDEX -f pem -o ak-pub.pem
sudo chmod +r ak-pub.pem
```

The AK public key is also included in the Runtime Claims. (This binds the AKPub to the SEV-SNP AR.) Extract this as well.

```bash
jq -r '.keys[] | select(.kid=="HCLAkPub")' runtime-claims.json > ak-pub-rc.jwk
jwker ak-pub-rc.jwk ak-pub-rc.pem
```

Compare them.

```bash
diff -s ak-pub-rc.pem ak-pub.pem
```

### 10. Verify vTPM Quote

Verify the vTPM using the AK public key.

```bash
sudo tpm2_checkquote \
	-u ak-pub.pem \
	-m message.msg \
	-s signature.sig \
	-f pcr.pcrs \
	-g sha256 \
	-q "$(< nonce.txt)"
```

This completes the verification of the Chain of Trust: ARK→ASK→VCEK→SEV-SNP AR→Runtime Claims→AK Pub→vTPM Quote.

## Verifying an SEV-SNP Report with Microsoft Azure Attestation
This section describes how to verify an AR with Microsoft Azure Attestation (MAA). This allows you to verify an AR without using external tools like `snpguest` or `go-sev-guest`.

For details, see [How to Deploy an MAA Provider](/Documents/Deploy-MAA-Provider).

### 0-a. Preparation (MAA)
Set up the MAA provider to be used for AR verification. In a production environment, it is recommended to deploy and use an MAA provider, but in this tutorial, we will use the default provider in the **Japan East** region. We will use the available stable API Version 2022-08-01.

```bash
VERIFIER_URL="https://sharedjpe.jpe.attest.azure.net" 
TEE_TYPE="SevSnpVm"
API_VERSION="2022-08-01"
MAA_REQUEST_URL="$VERIFIER_URL/attest/$TEE_TYPE?api-version=$API_VERSION"
```

### 0-b. Preparation (Collecting Evidence)
Prepare the SEV-SNP AR and Runtime Claims according to the Workflow in the previous section. Also, fetch the VCEK certificate chain from IMDS.
- `./report.bin`: SEV-SNP AR
- `./runtime-claims.json`: Runtime Claims
- `./vcek-cert-chain.pem`: VCEK Cert Chain PEM (VCEK + ASK + ARK)

### 1. Nonce
Create a nonce for the freshness of the JWT returned by MAA. However, this is not a required parameter for verification, so it can be omitted.

```bash
NONCE=$(openssl rand -hex 32)
```

### 2. Encode SEV-SNP Report & VCEK Cert Chain in Base64URL

```bash
REPORT_B64URL=$(base64 -w 0 report.bin | tr '+/' '-_' | tr -d '=')
VCEK_CERT_B64URL=$(base64 -w 0 vcek-cert-chain.pem | tr '+/' '-_' | tr -d '=')
```

### 3. Make *Extended* Report JSON
Create a JSON that combines the AR and the VCEK certificate chain (a pseudo-Extended AR).

```bash
jq -n \
	--arg report "$REPORT_B64URL" \
	--arg vcekCertChain "$VCEK_CERT_B64URL" \
	'{
	  "SnpReport" : $report,
	  "VcekCertChain" : $vcekCertChain
	}' \
	> report-payload.json
```

### 4. Encode Extended Report JSON in Base64URL
You need to further Base64URL encode this.

```bash
REPORT_JSON_B64URL=$(base64 -w 0 report-payload.json | tr '+/' '-_' | tr -d '=')
```

### 5. Encode Runtime Claims JSON in Base64URL
```bash
RUNTIME_CLAIMS_B64URL=$(base64 -w 0 runtime-claims.json | tr '+/' '-_' | tr -d '=')
```

### 6. Make Request JSON
Use the above data to create a JSON like the following.

```bash
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
```

In addition to `report` (hardware report + certificate chain), `runtimeData` (source of Report Data), and `nonce`, you can also specify the parameters `initTimeData` and `draftPolicyForAttestation`.

### 7. Send Request
Send the created Request JSON to the `Attest Sev Snp Vm` endpoint of the MAA provider.

```bash
curl -s -X POST "$MAA_REQUEST_URL" \
	-H "Content-Type: application/json" \
	-d "$(< maa-request-payload.json)" \
	> maa-response.json
```

If the verification is successful, a JSON containing a token (JWT) will be returned. If it fails, an error message including the cause of the failure will be returned.

```bash
jq < maa-response.json
```

### Side Note
This procedure is not currently described in the MAA documentation, and the only clue is the Sample request JSON in the [documentation](https://learn.microsoft.com/en-us/rest/api/attestation/attestation/attest-sev-snp-vm?view=rest-attestation-2025-06-01&tabs=HTTP). By Base64URL decoding the strings in the report and `runtimeData.data` fields in this sample, you can get the JSON created in this procedure, so you have to reverse-engineer the procedure. Also, note that although the field name is `runtimeData`, the data that should be put there is the Runtime *Claims*.
