# How to Check if TDX is Enabled
[Index](./index.md)

This section explains how to confirm that TDX is enabled on a deployed VM. However, this is not a true confirmation, but merely a check for kernel messages and interfaces that should exist if TDX is enabled. These can be forged or tampered with, so a true confirmation must be done through Remote Attestation.

## Check Kernel Messages (Azure/GCP)
Run the following command on the CVM.

```bash
sudo dmesg | grep -i tdx
```

Although there may be slight differences depending on the environment, you should see a message similar to the following (the example below was run on an Azure DC2esv6 instance).

```plaintext
[    0.688685] Memory Encryption Features active: Intel TDX
```

If `Intel TDX` is present in the `Memory Encryption Features active` line, then TDX is enabled.

## Directly Check for the Existence of the `/dev/tdx_guest` Device Node (GCP)
Run the following command on the CVM.

```bash
ll /dev/tdx_guest
```

If it is found, TDX is enabled. With some exceptions (like Azure CVMs), if it is not found, it means that TDX is not enabled or the device node has not been created.

### Note
In Azure CVMs, the TDX guest device is hidden from the guest OS, so the device node `/dev/tdx_guest` does not exist. The above method therefore cannot be used to confirm that TDX is enabled.

### If TDX is enabled but the device file is not created
If you have confirmed that TDX is enabled through kernel messages or other means, but the device node is not found, it is possible that the device node has not been created.

#### Load tdx_guest module

```bash
sudo modprobe tdx_guest
```

If this command fails, the tdx_guest module does not exist. The Linux kernel may not support TDX.

You can check the Linux kernel version with the following command. If it is a version that does not support TDX, you need to update the kernel.

```bash
uname -r
```

#### Check major & minor of tdx_guest device

```bash
cat /sys/class/misc/tdx_guest/dev
# MAJOR:MINOR (e.g. 10:122)
```

#### Create tdx_guest device file

```bash
sudo mknod /dev/tdx_guest c $MAJOR $MINOR
```
