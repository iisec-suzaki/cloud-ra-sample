# AWS SEV-SNP RA Tutorial
[Index](./index.md)

This document explains the procedure for setting up an SEV-SNP enabled CVM on Amazon Web Services (AWS) and performing SEV-SNP RA. This tutorial uses `snpguest`.

### Note: Test Environment
This tutorial has been tested in the following environment:

- Instance: AWS — c6a.large
- CPU: AMD EPYC 7R13 Processor (Milan)
- Memory: 4 GiB
- OS: Ubuntu 24.04.1
- Kernel: 6.14.0-1010-aws
- Storage Size: 16 GiB

## Deploy an SEV-SNP CVM
This section explains how to set up an SEV-SNP enabled EC2 instance on AWS and confirm that SEV-SNP is enabled. The following information is based on the state as of September 2025.

### Create an EC2 instance from the Web Console
On AWS, you can set up an SEV-SNP enabled CVM just by performing operations on the Web Console.

#### Region/Zone
Select a region/zone where instances that can use AMD SEV-SNP are available. Currently, SEV-SNP enabled EC2 instances are available in the following regions/zones.

1. us-east-2: Ohio
2. eu-west-1: Ireland

#### Application and OS Images (Amazon Machine Image) 
- AMI: Ubuntu Server 24.04 LTS
- Architecture: 64-bit (x86)

#### Instance type
The SEV-SNP support status of instance types equipped with AMD EPYC CPUs is as follows.

| Type | Processor | SEV-SNP Capable |
| :--- | :--- | :--- |
| m6a | AMD EPYC 7R13 − Milan | ✅ |
| c6a | AMD EPYC 7R13 − Milan | ✅ |
| r6a | AMD EPYC 7R13 − Milan | ✅ |
| m7a | AMD EPYC 9R14 − Genoa | ❌ |
| c7a | AMD EPYC 9R14 − Genoa | ❌ |
| r7a | AMD EPYC 9R14 − Genoa | ❌ |

Select an instance type that supports SEV-SNP.

#### Key Pair/Network/Storage
Configure as usual.

Note that if you are using SSH to connect to the VM, the connection may fail if the file access permissions of the generated SSH private key are left as they were at the time of download. You can resolve this by tightening the access permissions with the following command.

```bash
chmod 400 $YOUR_PRIVATE_KEY
```

#### Advanced details (Important)
If you have selected the correct region, zone, OS image, and instance type, the setting item

- AMD SEV-SNP

will be displayed. Set this to

- AMD SEV-SNP: Enabled

## Check if SEV-SNP is enabled
You can check whether the correctly set up VM has SEV-SNP enabled by following the instructions in [How to Check if SEV-SNP is Enabled](./Check-SNP-Enabled.md).

For AWS, you can also check from the Web Console. You can check the "Instance details" at "EC2 > Instances > [instance-id]" in the Web Console. The "AMD SEV-SNP" item should be "enabled".

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

Here, we will explain the steps for eXtended Remote Attestation (XRA) using `snpguest` step-by-step. The following procedure is mostly the same as for [GCP](./GCP-SNP-Tutorial.md), so explanations are omitted except for the differing parts.

The basic flow is as follows.
1. Generate a nonce
2. Request an AR with the nonce bound to the Report Data from AMD-SP
3. Fetch the VLEK certificate chain
4. Verify the certificate chain ARK→ASVK→VLEK
5. Verify the signature VLEK→AR
6. Verify the nonce

### 0. Set variables
In this tutorial, we will use a machine with AMD Milan. In AWS, the guest OS is placed at VMPL0. We will set these as environment variables.

```bash
PROCESSOR_MODEL='milan'
VMPL_VALUE=0
```

### 1. Prepare 64-byte report data
```bash
openssl rand 64 > request-file.bin
```

### 2. Request AR from AMD-SP

```bash
sudo snpguest report report.bin request-file.bin -v $VMPL_VALUE
```

The AR is signed with a VLEK private key (ECDSA P-384 with SHA-384).

### 3. Fetch VLEK Cert Chain
Fetch the ARK and ASVK certificates corresponding to the processor model from AMD KDS. In an AWS CVM, the Chip ID field of the AR may be hidden (zero-filled). Therefore, specifying the processor model is mandatory.

```bash
snpguest fetch ca pem certs $PROCESSOR_MODEL -e vlek
```

Get the VLEK certificate from the HV via the AMD-SP.

```bash
sudo snpguest certificates pem certs
```

### 4. Verify VCEK Cert Chain (ARK→ASVK→VLEK)

```bash
snpguest verify certs certs
```

### 5. Verify signature of AR by VLEK
```bash
snpguest verify attestation certs report.bin
```

This completes the verification of the Chain of Trust: ARK→ASVK→VLEK→AR.

### 6. Verify Report Data in AR
```bash
dd if=./report.bin \
  skip=80 \
  bs=1 \
  count=64 \
  of=./report-data.bin \
  status=none
diff -s request-file.bin report-data.bin
```
