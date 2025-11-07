# How to Check if SEV-SNP is Enabled
[Index](./index.md)

This section explains how to confirm that SEV-SNP is enabled on a deployed VM. However, this is not a true confirmation, but merely a check for kernel messages and interfaces that should exist if SEV-SNP is enabled. These can be forged or tampered with, so a true confirmation must be done through Remote Attestation.

### Note
In Azure CVMs, SEV-SNP interfaces such as the device file `/dev/sev-guest` are hidden from the guest OS. Therefore, the methods described below cannot be used to confirm that SEV-SNP is enabled.

## Check Kernel Messages (AWS/GCP)
Run the following command on the CVM.

```bash
sudo dmesg | grep -i sev
```

Although there may be slight differences depending on the environment, you should see a message similar to the following (the example below was run on a GCP N2D instance).

```plaintext
[    0.658618] Memory Encryption Features active: AMD SEV SEV-ES SEV-SNP
[    0.658784] SEV: Status: SEV SEV-ES SEV-SNP 
[    1.225789] SEV: APIC: wakeup_secondary_cpu() replaced with wakeup_cpu_via_vmgexit()
[    1.300916] SEV: Using SNP CPUID table, 57 entries present.
[    1.303793] SEV: SNP running at VMPL0.
[    2.061364] SEV: SNP guest platform device initialized.
[    2.406820] sev-guest sev-guest: Initialized SEV guest driver (using vmpck_id 0)
```

If `SEV-SNP` is present in the `Memory Encryption Features active` line, then SEV-SNP is enabled. If this item is missing, with some exceptions (like Azure CVMs), it means that `SEV-SNP` is not enabled.

The integer value after `using vmpck_id` represents the Virtual Machine Privilege Level (VMPL). In AWS/GCP CVMs, the VMPL of the guest OS is 0.

## Directly Check for the Existence of the Device node `/dev/sev-guest` (AWS/GCP)

Run the following command on the CVM.

```bash
ll /dev/sev-guest
```

If it is found, SEV-SNP is enabled. With some exceptions (like Azure CVMs), if it is not found, it means that SEV-SNP is not enabled or the device node has not been created.

### If SEV-SNP is enabled but the device node is not created

If you have confirmed that SEV-SNP is enabled through kernel messages or other means, but the device file is not found, it is possible that the device node has not been created.

#### Load sev-guest module

```bash
sudo modprobe sev-guest
```

If this command fails, the `sev-guest` module does not exist. The Linux kernel may not support SEV-SNP.

You can check the Linux kernel version with the following command. If it is a version that does not support SEV-SNP, you need to update the kernel.

```bash
uname -r
```

#### Check the major & minor of the sev-guest device

```bash
cat /sys/class/misc/sev-guest/dev
# MAJOR:MINOR (e.g. 10:123)
```

#### Create the sev-guest device node

```bash
sudo mknod /dev/sev-guest c $MAJOR $MINOR
```