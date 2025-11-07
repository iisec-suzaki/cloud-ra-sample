# GCP SEV-SNP RA Tutorial
[Index](./index.md)

This document explains how to set up an SEV-SNP enabled CVM on Google Cloud Platform (GCP) and perform SEV-SNP RA. This tutorial uses `snpguest`.

### Note: Test Environment
This tutorial has been tested in the following environment:

- Instance: Google Compute Engine — n2d-standard-2
- CPU: AMD EPYC 7B13 Processor (Milan)
- Memory: 8 GiB
- OS: Ubuntu 24.04.1
- Kernel: 6.14.0-1017-gcp
- Storage Size: 32 GiB

## Deploy an SEV-SNP CVM
This section explains how to set up an SEV-SNP enabled VM instance on GCP and confirm that SEV-SNP is enabled. The following information is based on the state as of September 2025.

Only N2D (AMD Milan) machines support SEV-SNP. Other machines with AMD EPYC CPUs do not support SEV-SNP.

| Type | Processor | SEV-SNP Capable |
| :--- | :--- | :--- |
| N2D (Milan) | AMD Milan | ✅ |
| N2D (Rome) | AMD Rome  | ❌ |
| C2D | AMD Milan | ❌ |
| C3D | AMD Genoa | ❌ |
| C4D | AMD Turin | ❌ |

Note that N2D has machines with both AMD Rome and AMD Milan. Rome only supports SEV, while Milan supports SEV/SEV-SNP.

Here, we will create an SEV-SNP enabled N2D (AMD Milan) instance in `us-central1-a`. We will use **Ubuntu 24.04** as the OS.

### Create a VM instance from the CLI

You can create an instance with the following command. Adjust the boot disk size and other parameters as needed.

```bash
gcloud compute instances create [instance-name] \
	--zone=us-central1-a \
	--machine-type=n2d-standard-2 \
  --min-cpu-platform="AMD Milan" \
	--image-family=ubuntu-pro-2404-lts-amd64 \
	--image-project=ubuntu-os-pro-cloud \
	--boot-disk-size=32GB \
	--confidential-compute-type=SEV_SNP \
	--shielded-secure-boot \
	--maintenance-policy=Terminate \
	--enable-nested-virtualization \
	--metadata=enable-oslogin=false
```

If you want to configure and check network settings and other details later, create an instance template and use it. Note that if you do not specify the boot disk size when creating an instance using a template, it will default to the minimum of 10GB.

```bash
gcloud compute instance-templates create [template-name] \
    --instance-template-region=us-central1 \
    --machine-type=n2d-standard-2 \
    --min-cpu-platform="AMD Milan" \
    --image-family=ubuntu-pro-2404-lts-amd64 \
    --image-project=ubuntu-os-pro-cloud \
    --confidential-compute-type=SEV_SNP \
    --shielded-secure-boot \
    --maintenance-policy=Terminate \
    --enable-nested-virtualization \
    --metadata=enable-oslogin=false
```

Be aware of the following when using an instance template created from the CLI in the Web Console.

1. "Confidential VM service" in "Security" section will be displayed as "Disabled", but SEV-SNP is enabled internally, so do not change this setting.
2. When you go to the instance creation screen, the "Secure Boot" checkbox in "Security" section will be unchecked and it will be disabled internally, so re-enable it if necessary (this issue has also been confirmed when creating a template in the Web Console).
3. Confirm that `--confidential-compute-type=SEV_SNP` is included in the "Equivalent code".

### Create a VM instance from the Web Console
Before August 2025, the Web Console was implemented with only legacy SEV, and it was not possible to create an SEV-SNP machine. An update in August made it possible to create one via the GUI in the Web Console.

#### Machine Configuration
1. Region/Zone — Only some regions (such as **us-central1-a/b/c**) support SEV-SNP.
2. Machine type — **N2D**
3. Advanced configuration
   1. CPU platform — **AMD Milan or later**
   2. Other settings — Optional

#### Security
1. Confidential VM service — Press "Enable" will pop up a TEE type selection screen, select "AMD SEV-SNP".
2. Shielded VM — It is generally good to enable everything. This is especially necessary if you are also performing vTPM attestation.

#### OS and storage
Enabling SEV-SNP in the security settings will change the OS image/version item to "Confidential images".

1. Confidential images — For example, the following images are available:
   - Ubuntu 24.04 LTS NVIDIA version: 570
   - Ubuntu 24.04 LTS
2. Other settings — Optional

#### Data protection/Networking/Observability/Advanced
Optional. However, for networking only, enabling SEV-SNP will automatically fix the "Network interface card" to "gVNIC".

## Check if SEV-SNP is enabled
You can check whether the correctly set up VM has SEV-SNP enabled by following the instructions in [How to Check if SEV-SNP is Enabled](./Check-SNP-Enabled.md).

You can also check via the `gcloud` CLI on a GCP CVM. Run the following command on your local machine.

```bash
gcloud compute instances describe [instance-name] \
    --zone=[zone] \
    --format="yaml(confidentialInstanceConfig)"
```

If the output is as follows, SEV-SNP is enabled.

```plaintext
confidentialInstanceConfig:
  confidentialInstanceType: SEV_SNP
```

However, depending on how the instance was set up, it may contain the line:

```plaintext
  enableConfidentialCompute: false
```

We have confirmed that this line is added when deploying from the Web Console based on an instance template created from the CLI. This can be ignored as it is a flag that is linked to the enable/disable display of the "Confidential VM service" in the Web Console. (It was linked to the deprecated flag `--confidential-compute`.)

## Install necessary tools
Install the necessary software on the guest OS of the CVM. For details, see [CVM Environment Setup](./Preparation.md).

Alternatively, you can use the included Dockerfile.

```bash
sudo apt update
sudo apt install -y docker.io
sudo docker build -t <image-name> .
sudo docker run -it --rm \
    --device /dev/sev-guest \
    <image-name> /bin/bash
```

If you run the Docker container with the above command, you will have root privileges by default, so `sudo` is not necessary in the following steps.

## Remote Attestation
For details on the Remote Attestation protocol, see [About SEV-SNP Remote Attestation](./About-SEV-SNP-Remote-Attestation.md).

Here, we will explain the steps for Standard Remote Attestation (SRA) and eXtended Remote Attestation (XRA) using `snpguest` step-by-step.

The basic flow is as follows.
1. Generate a nonce
2. Request an AR with the nonce bound to the Report Data from AMD-SP
3. Fetch the VCEK certificate chain from AMD KDS or Host
4. Verify the certificate chain ARK→ASK→VCEK
5. Verify the signature VCEK→AR
6. Verify the nonce

### 0. Set variables
In this tutorial, we will use a machine with an AMD Milan processor. In GCP, the guest OS is placed at VMPL0. We will set these as environment variables.

```bash
PROCESSOR_MODEL='milan'
VMPL_VALUE=0
```

Note that you can set the VMPL value to a higher (less privileged) level than the one you are currently at. In this case, since the actual VMPL is 0, you can specify an arbitrary value from 0 to 3. The specified VMPL will be recorded in the AR.

### 1. Prepare 64-byte report data
Prepare a 64-byte request to be bound as Report Data in the AR. Here, we will simply pass a nonce.

```bash
openssl rand 64 > request-file.bin
```

In a simple RA, the Relying Party (remote user) prepares a nonce and uses it as the Report Data. When performing ECDHKE together with RA between the Relying Party and the Attester (guest OS), you would put the SHA-512 digest of the AT's ephemeral DH public key, or the AT's and RP's ephemeral DH public keys appended together. (You can also add a nonce. After the key exchange, a MAC key is created from the Shared Secret and MACs are exchanged to prevent MITM.)

In any case, it is used to bind information prepared by the RP or AT to the AR and have it signed by the AMD-SP.

### 2. Request AR from AMD-SP
Fetch an SNP AR from the AMD-SP with `request-file.bin` bound as the Report Data.

```bash
sudo snpguest report report.bin request-file.bin -v $VMPL_VALUE
```

The AR is signed with a VCEK private key (ECDSA P-384 with SHA-384).

Normally, in XRA, you fetch an "extended AR" from the AMD-SP with the certificate chain cached in the Hypervisor (HV) appended to the end, and verify it. However, `snpguest` does not provide a function to fetch/verify an extended AR, so XRA is achieved in a slightly roundabout way as described below. `go-sev-guest` supports fetching/verifying an extended AR.

### 3. Fetch VCEK Cert Chain

#### 3.1. from AMD KDS (SRA)
Fetch the ARK and ASK certificates corresponding to the processor model from AMD KDS.

```bash
# Automatically determine the processor model from the Chip ID field of the AR
snpguest fetch ca pem certs -r report.bin -e vcek

# Specify the processor model
snpguest fetch ca pem certs $PROCESSOR_MODEL -e vcek
```

Fetch the VCEK certificate corresponding to the Chip ID/Reported TCB Version from AMD KDS.

```bash
# Automatically determine the processor model from the Chip ID field of the AR
sudo snpguest fetch vcek pem certs report.bin

# Specify the processor model
sudo snpguest fetch vcek pem certs report.bin -p $PROCESSOR_MODEL
```

#### 3.2. from HV's cache (XRA)
Fetch the VCEK Cert Chain from the HV via the AMD-SP.

```bash
sudo snpguest certificates pem certs
```

Internally, `snpguest` generates a random nonce, fetches an extended AR from the AMD-SP, and extracts only the certificate chain appended to the end. In other words, it does the slightly redundant work of re-fetching the AR just to get the certificate chain from the HV. `go-sev-guest` can fetch an Extended AR in one shot, so there is no need to fetch the certificate chain again (this is desirable as it reduces the number of queries to the AMD-SP).

### 4. Verify VCEK Cert Chain (ARK→ASK→VCEK)
Verify that the ARK is a self-signed certificate, that the ARK signs the ASK, and that the ASK signs the VCEK.

```bash
snpguest verify certs certs
```

### 5. Verify signature of AR by VCEK
Verify the signature of the AR with the VCEK.

```bash
snpguest verify attestation certs report.bin
```

More precisely, it performs the following verification. Each can be verified independently by setting the `-t` and `-s` flags.
1. Compare the Reported TCB of the AR with the TCB of the VCEK certificate.
2. Verify the signature of the AR with the VCEK public key.

This completes the verification of the Chain of Trust: ARK→ASK→VCEK→AR.

### 6. Verify Report Data in AR
Extract the Report Data (offset: 80 bytes, size: 64 bytes) from the AR and compare it with the `request-file.bin` prepared at the beginning.

```bash
dd if=./report.bin \
  skip=80 \
  bs=1 \
  count=64 \
  of=./report-data.bin \
  status=none
diff -s request-file.bin report-data.bin
```

Without this, the possibility that "it's just a recycled AR from somewhere else" (Replay Attack) cannot be ruled out.

This guarantees the authenticity and freshness of the contents of the AR by the ARK. If necessary, you can also verify the contents other than the Report Data. The use of `go-sev-guest` is suitable for this purpose.
