# GCP TDX RA Tutorial
[Index](./index.md)

This document explains how to set up a TDX enabled CVM on Google Cloud Platform and perform RA.

### Note: Test Environment
This tutorial has been tested in the following environment:

- Instance: Google Compute Engine — c3-standard-4
- CPU: Intel 4th Gen Xeon (Sapphire Rapids)
- Memory: 16 GiB
- OS: Ubuntu Ubuntu 24.04.1
- Kernel: 6.14.0-1017-gcp
- Storage Size: 32 GiB

This tutorial has also been verified to work on Ubuntu 22.04.1 (with Linux Kernel 6.8.0-1042-gcp).

## Deploy a TDX CVM
This section explains how to set up a TDX enabled VM instance on GCP and confirm that TDX is enabled. The following information is based on the state as of August 2025.

The machine type **C3** (Intel Sapphire Rapids) supports TDX. We will create a TDX enabled C3 instance in `us-central1-c`. We will use **Ubuntu 24.04** as the OS.

### Create a VM instance from the CLI

You can create an instance with the following command. Adjust the boot disk size and other parameters as needed.

```bash
gcloud compute instances create [instance-name] \
	--zone=us-central1-c \
	--machine-type=c3-standard-4 \
	--image-family=ubuntu-pro-2404-lts-amd64 \
	--image-project=ubuntu-os-pro-cloud \
	--boot-disk-size=32GB \
	--confidential-compute-type=TDX \
	--shielded-secure-boot \
	--maintenance-policy=Terminate \
	--enable-nested-virtualization \
	--metadata=enable-oslogin=false
```

If you want to configure and check network settings and other details later, create an instance template and use it. Note that if you do not specify the boot disk size when creating an instance using a template, it will default to the minimum of 10GB.

```bash
gcloud compute instance-templates create [template-name] \
	--instance-template-region=us-central1 \
	--machine-type=c3-standard-4 \
	--image-family=ubuntu-pro-2404-lts-amd64 \
	--image-project=ubuntu-os-pro-cloud \
	--confidential-compute-type=TDX \
	--shielded-secure-boot \
	--maintenance-policy=Terminate \
	--enable-nested-virtualization \
	--metadata=enable-oslogin=false
```

Be aware of the following when using this instance template in the Web Console.
1. "Confidential VM service" in "Security" section will be displayed as "Disabled", but TDX is enabled internally, so do not change this setting.
2. When you go to the instance creation screen, the "Secure Boot" checkbox in "Security" section will be unchecked and it will be disabled internally, so re-enable it if necessary (this issue has also been confirmed when creating a template in the Web Console).
3. Confirm that `--confidential-compute-type=TDX` is included in the "Equivalent code".

### Create a VM instance from the Web Console
Before August 2025, the Web Console was implemented with only legacy SEV in mind, and it was not possible to create a TDX machine. An update in August made it possible to create one via the GUI in the Web Console.

#### Machine Configuration
1. Region/Zone — Only some regions (such as **us-central1-a/b/c**) support TDX.
2. Machine type — C3
3. Advanced configuration — Optional

#### Security
1. Confidential VM service — Press "Enable" will pop up a TEE type selection screen, select "Intel TDX".
2. Shielded VM — It is generally good to enable everything. This is especially necessary if you are also performing vTPM attestation.

#### OS and storage
Enabling SEV-SNP in the security settings will change the OS image/version item to "Confidential images".

1. Confidential images — For example, the following images are available:
   - Ubuntu 24.04 LTS NVIDIA version: 570
   - Ubuntu 24.04 LTS
2. Other settings — Optional

#### Data protection/Networking/Observability/Advanced
Optional. However, for networking only, enabling TDX will automatically fix the "Network interface card" to "gVNIC".

## Check if TDX is enabled
You can check whether the correctly set up VM has TDX enabled by following the instructions in [How to Check if TDX is Enabled](./Check-TDX-Enabled.md).

You can also check via the `gcloud` CLI on a GCP CVM. Run the following command remotely.

```bash
gcloud compute instances describe [instance-name] \
    --zone=[zone] \
    --format="yaml(confidentialInstanceConfig)"
```

If the output is as follows, TDX is enabled.

```plaintext
confidentialInstanceConfig:
  confidentialInstanceType: TDX
```

However, depending on how the instance was set up, it may contain the line:

```plaintext
  enableConfidentialCompute: false
```

We have confirmed that this line is added when deploying from the Web Console based on an instance template created from the CLI. This can be ignored as it is a flag that is linked to the enable/disable display of the "Confidential VM service" in the Web Console. (It was linked to the deprecated flag `--confidential-compute`.)

## Install necessary tools
Install the necessary software on the guest OS of the CVM. For details, see [CVM Environment Setup](./Preparation.md).

## Remote Attestation

### 1. Prepare 64-byte report data
Prepare a 64-byte request to be bound as Report Data in the TD Quote. Here, we will simply pass a nonce.

```bash
openssl rand 64 > report-data.bin
xxd -p report-data.bin | tr -d '\n' > report-data.txt
```

### 2. Get TD Quote
The TD Quote has a PCK certificate chain (in PEM format) appended to the end. (This is similar to an extended report in SEV-SNP.)

```bash
sudo go-tdx-guest-attest \
	-inform hex \
	-in "$(< report-data.txt)" \
	-outform bin \
	-out quote.bin
```

### 3. Verify TD Quote by `go-tdx-guest`
This step includes verifying the signature of the TD Quote, verifying the PCK certificate chain, checking for certificate revocation, comparing the Report Data in the TD Quote with the Runtime Claims, and comparing the `user_data` in the Runtime Claims.

```bash
go-tdx-guest-check \
	-inform bin \
	-in quote.bin \
	-report_data "$(< report-data.txt)" \
	-get_collateral true \
	-verbosity 1
```

If you pass the Report Data, it will also perform a verification of the Report Data

You can specify the Cert Chain (in PEM format) to be used for verification with the `-trusted_roots <string>` option. If not specified, it will use the certificate chain appended to the end of the TD Quote. (This is similar to the Attestation of an Extended Report in SEV-SNP.)

By specifying `-get_collateral true`, you can also get the Attestation Collateral from Intel PCS and use it for verification. It switches between the shared SGX/TDX endpoint (`/sgx`) and the dedicated TDX endpoint (`/tdx`) depending on the contents of the Quote.

However, as described below, fetching from Intel PCS every time violates the terms of service, so it is not recommended for use in a production environment.

### 3'. Verify TD Quote by `SGX-DCAP-QvL`
Get the Collateral from the Provisioning Certificate Service (PCS), or the Provisioning Certificate Caching Service (PCCS) which caches the Collateral fetched from the PCS, and use it to verify the TD Quote.

The complex procedure for reading a TD Quote and getting the appropriate Collateral is encapsulated. It is easier to understand if you think of it as a combination of `snpguest fetch` and `snpguest verify` in SEV-SNP.

#### i. Configure PCS

You need to prepare a JSON file at `/etc/sgx_default_qcnl.conf` that describes the settings for the PCS/PCCS server URL and the retention time of the local cache (e.g., `$HOME/.dcap-qcnl/*`) to be used in DCAP RA.

Here, we will configure it to fetch the Collateral from Intel PCS.

```bash
wget https://raw.githubusercontent.com/intel/SGXDataCenterAttestationPrimitives/main/QuoteGeneration/qcnl/linux/sgx_default_qcnl_without_pccs.conf 
sudo cp sgx_default_qcnl_without_pccs.conf /etc/sgx_default_qcnl.conf
```

This will configure it as follows.

- PCS: Intel PCS <https://api.trustedservices.intel.com/sgx/certification/v4/>
- PCCS: None
- Local PCK URL: None
- Local cache retention time: 168 hours

If you are setting up your own PCCS server, adjust the settings accordingly.

Note that sending a request to the PCS every time is prohibited (to reduce load), and caching is required, so **you must use a PCCS server in a production environment.**

#### ii. Verify
Get the Attestation Collateral from the Collateral Server based on the settings in the Config JSON `sgx_default_qcnl.conf`, and use it to verify `quote.bin`.

```bash
sgx-dcap-qvl-app -quote quote.bin
```

This tool does not verify the Report Data, so you need to extract and verify it manually separately, or you can verify it with `go-tdx-guest`.
