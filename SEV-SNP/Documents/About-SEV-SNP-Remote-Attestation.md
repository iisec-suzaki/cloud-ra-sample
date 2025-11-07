# About SEV-SNP Remote Attestation
[Index](./index.md)

AMD SEV-SNP (Secure Encrypted Virtualization - Secure Nested Paging) protects a virtual machine (VM) by encrypting not only its disk but the entire VM, including memory and registers. This prevents even the host administrator from stealing data or code within the VM.

Remote Attestation (RA) is a process where the guest OS (Attester) cryptographically proves to a remote user (Relying Party) that it is running in a correctly protected environment. By trusting the chip vendor (AMD), the Relying Party can be assured through RA that the target VM is running in a genuine AMD SEV-SNP environment.

## Chain of Trust
The Remote Attestation of an SEV-SNP CVM consists of verifying the following Chain of Trust (CoT). There are two types of CoT depending on the type of private key used to sign the Attestation Report (AR).

```mermaid
graph TD
    ARK("AMD Root Key (ARK)<br/>(RoT)")
    ARK -->|"signs"| ASK
    ARK -->|"signs"| ASVK

    subgraph "VCEK Cert Chain (GCP)"
        ASK("AMD SEV (Signing) Key (ASK)")
        VCEK("Versioned Endorsement Key (VCEK)")
        ASK -->|"signs"| VCEK
    end
    VCEK -->|"signs"| AR

    subgraph "VLEK Cert Chain (AWS)"
        ASVK("AMD SEV-VLEK Key (ASVK)")
        VLEK("Versioned Loaded Endorsement Key (VLEK)")
        ASVK -->|"signs"| VLEK
    end

    AR("SEV-SNP Attestation Report (AR)")

    VLEK -->|"signs"| AR
```

Unlike other SEV-SNP CVMs, Azure CVMs presuppose a unique RA workflow using a vTPM. The CoT is as follows.

```mermaid
graph TD
    %% Azure side
    AzureCA["Azure Root CA<br/>(RoT)"]
    AKCert["AK Certificate"]
    AK["Attestation Key (HCLAk)"]
    vQuote["vTPM Quote"]

    %% AMD side
    ARK["ARK (RoT)"]
    ASK["ASK"]
    VCEK["VCEK"]
    AR["SEV-SNP AR"]

    %% Edges – Azure branch
    AzureCA -->|certifies| AKCert
    AKCert -->|certifies| AK
    AK -->|signs| vQuote

    %% Edges – AMD branch
    ARK -->|signs| ASK
    ASK -->|signs| VCEK
    VCEK -->|signs| AR

    %% Binding between branches
    AR --> |binds| AK
```

## Remote Attestation Protocol
The Relying Party verifies the authenticity of the AR presented by the CVM based on the VEK certificate chain distributed by AMD. (This reduces the trust to the AMD RoT.) Then, by verifying the contents of the AR such as the Measurement (hash value), Report Data, and SVN, the Relying Party confirms requirements including integrity. (Also, by including a nonce in the Report Data, the freshness of the AR is ensured.)

```mermaid
sequenceDiagram
    participant KDS as AMD KDS
    participant RP as Relying Party
    participant AT as Attester (Guest CVM)
    participant SP as AMD SP

    RP->>AT: Request AR with Report Data
    AT->>SP: Request AR with Report Data
    SP->>SP: Issue AR (signed by VCEK)
    SP-->>AT: AR
    AT-->>RP: AR

    RP->>KDS: Request VCEK Cert Chain w.r.t. AR
    KDS-->>RP: ARK, ASK, VCEK Certs

    RP->>RP: Verify CoT (ARK→ASK→VCEK→AR)
    RP->>RP: Verify AR contents (incl. Report Data)
```


## Extended Remote Attestation Protocol
In Extended Attestation, the host caches a part or the whole of the VEK certificate chain, and the Relying Party uses the host-cached VEK certificate chain for verification.

### Caching the entire VCEK certificate chain (GCP)
```mermaid
sequenceDiagram
    participant RP as Relying Party
    participant AT as Attester (Guest CVM)
    participant SP as AMD SP
    participant HV as Hypervisor
    participant H as Host

    Note over SP, H: Cache VCEK Cert Chain
    H->>SP: VCEK Cert Chain (ARK, ASK, VCEK Certs)
    SP->>HV: VCEK Cert Chain

    Note over RP, SP: Fetch AR
    RP->>AT: Request AR with Report Data
    AT->>SP: Request AR with Report Data
    SP->>SP: Issue AR (signed by VCEK)
    SP-->>AT: AR
    AT-->>RP: AR

    Note over RP, HV: Fetch VCEK Cert Chain
    RP->>AT: Request VCEK Cert Chain
    AT->>SP: Request VCEK Cert Chain
    SP->>HV: Read VCEK Cert Chain
    HV-->>SP: VCEK Cert Chain
    SP-->>AT: VCEK Cert Chain
    AT-->>RP: VCEK Cert Chain

    Note over RP: Verify AR
    RP->>RP: Verify CoT (ARK→ASK→VCEK→AR)
    RP->>RP: Verify AR contents (incl. Report Data)
```

### Caching only the VLEK certificate (AWS)
```mermaid
sequenceDiagram
    participant KDS as AMD KDS
    participant RP as Relying Party
    participant AT as Attester (Guest CVM)
    participant SP as AMD SP
    participant HV as Hypervisor
    participant H as Host

    Note over SP, H: Cache VLEK Cert
    H->>SP: VLEK Cert
    SP->>HV: VLEK Cert

    Note over RP, HV: Fetch AR
    RP->>AT: Request AR with Report Data
    AT->>SP: Request AR with Report Data
    SP->>SP: Issue AR (signed by VLEK)
    SP-->>AT: AR
    AT-->>RP: AR

    Note over KDS, HV: Fetch VLEK Cert Chain
    RP->>KDS: Request ARL, ASVK
    KDS-->>RP: ARK, ASVK

    RP->>AT: Request Chip Endorsement Key Cert
    AT->>SP: Request VLEK Cert
    SP->>HV: Read VLEK Cert
    HV-->>SP: VLEK Cert
    SP-->>AT: VLEK Cert
    AT-->>RP: VLEK Cert

    Note over RP: Verify AR
    RP->>RP: Verify CoT (ARK→ASVK→VLEK→AR)
    RP->>RP: Verify AR contents (incl. Report Data)
```

### Note
An Extended AR is an AR with the host-cached VEK certificate (or certificate chain) appended to the end, which can be retrieved from the AMD-SP for verification in Extended Attestation.

However, the current `snpguest` does not implement a function to fetch an Extended AR in a single step, so the AR and the VEK certificate (chain) must be retrieved separately. Therefore, in the sequence diagrams above, the fetching of the AR and the VEK certificate (chain) are shown as separate actions.

Note that `go-sev-guest` supports getting an Extended AR, so the AR and the VEK certificate (chain) can be fetched at once.

## Remote Attestation for Azure CVM via vTPM
In Azure CVMs, the AMD-SP is hidden from the guest OS, and it is not possible to obtain an SEV-SNP AR (directly) from the AMD-SP at runtime. Instead, a Remote Attestation Workflow using a vTPM is assumed.

In an Azure CVM, a paravisor (OpenHCL) is placed at VMPL0 of the guest VM, and the guest OS is placed at a lower privilege level. (This protects the paravisor from malicious **guests**.) A vTPM is included as a module within the paravisor. The guest OS cannot interact directly with the SEV-SNP guest device and must do so through the vTPM.

When the CVM is launched, the paravisor requests a SEV-SNP AR from the AMD-SP and stores it in the vTPM's non-volatile storage (NVS) at NV index `0x01400001`. A hash of the Runtime Claims is bound to the AR as Report Data. The Runtime Claims is a JSON object consisting of the AK public key (used for vTPM Quote signature verification), the EK public key (encryption key), VM configuration information, and User Data (zero-filled by default). The Runtime Claims itself is also stored at NV index `0x01400001`.


The following sequence diagram shows the RA from SEV-SNP to vTPM when using the AR generated at boot time.

```mermaid
sequenceDiagram
    participant KDS as AMD KDS or IMDS
    participant RP as Relying Party
    participant AT as Attester (Guest CVM)
    participant vTPM
    participant PV as Paravisor
    participant SP as AMD SP

    Note over vTPM, SP: Launch CVM
    PV->>SP: Request SEV-SNP AR with H(RuntimeClaims) as Report Data
    SP->>SP: Issue SEV-SNP AR (signed by VCEK)
    SP-->>PV: SEV-SNP AR
    PV->>vTPM: NVWrite Azure AR (incl. SEV-SNP AR & RuntimeClaims)

    Note over KDS, vTPM: SEV-SNP Attestation
    RP->>AT: Request SEV-SNP AR & RuntimeClaims
    AT->>vTPM: NVRead SEV-SNP AR & RuntimeClaims
    vTPM-->>AT: AR, RuntimeClaims
    AT-->>RP: AR, RuntimeClaims

    RP->>KDS: Request VCEK Cert Chain w.r.t. SEV-SNP AR
    KDS-->>RP: ARK, ASK, VCEK Certs

    RP->>RP: Verify CoT (ARK→ASK→VCEK→SEV-SNP AR)
    RP->>RP: Verify CoT (SEV-SNP AR→RuntimeClaims)
    Note right of RP: Check H(RuntimeClaims) == AR.ReportData?

    Note over RP, vTPM: vTPM Attestation
    RP->>AT: Request vTPM Quote with nonce
    AT->>vTPM: Request Quote(PCRs, Nonce)
    vTPM->>vTPM: Issue vTPM Quote (signed by AK) 
    vTPM-->>AT: vTPM Quote
    AT-->>RP: vTPM Quote
    RP->>AT: Request AK Pub
    AT->>vTPM: NVRead AKPub
    vTPM-->>AT: AKPub
    AT-->>RP: AKPub

    RP->RP: Verify CoT (AK→vTPM Quote)
    RP->>RP: Verify CoT (RuntimeClaims→AK)
    Note right of RP: Check RuntimeClaims.AKPub == AKPub?

    RP->>RP: Verify vTPM Quote contents (incl. PCRs)
```

This first extends the TCB from the AMD-SP to the paravisor (including the vTPM) by verifying the SEV-SNP AR, and then extends it to the entire workload by verifying the vTPM Quote (including PCR verification).

Since the SEV-SNP AR generated at CVM boot time cannot bind Report Data specified by the Relying Party or Attester, performing only this RA does not eliminate the possibility of replay attacks. On the other hand, since a nonce can be bound to the vTPM Quote, the vTPM Quote cannot be replayed.

Note that writing 64 bytes of data to NV index `0x01400002` will be detected by the paravisor, which will then read NV index `0x01400002`, use this as User Data in the new Runtime Claims to re-fetch an SEV-SNP AR, and overwrite NV index `0x01400001`. Therefore, when performing SEV-SNP RA alone, you can bind the Report Data to the SEV-SNP AR via the vTPM to ensure freshness.

```mermaid
sequenceDiagram
    participant KDS as AMD KDS or IMDS
    participant RP as Relying Party
    participant AT as Attester (Guest CVM)
    participant vTPM
    participant PV as Paravisor
    participant SP as AMD SP

    RP->>AT: Request AR with User Data
    AT->>vTPM: NVWrite User Data
    PV-->vTPM: Detect NVWrite
    PV->>vTPM: NVRead User Data 
    vTPM-->>PV: User Data
    PV->>SP: Request SEV-SNP AR with H(RuntimeClaims) as Report Data
    Note right of PV: RuntimeClaims incl. User Data
    SP->>SP: Issue SEV-SNP AR (signed by VCEK)
    SP-->>PV: SEV-SNP AR
    PV->>vTPM: NVWrite Azure AR (incl. SEV-SNP AR & RuntimeClaims)

    RP->>AT: Request SEV-SNP AR & RuntimeClaims
    AT->>vTPM: NVRead SEV-SNP AR & RuntimeClaims
    vTPM-->>AT: AR, RuntimeClaims
    AT-->>RP: AR, RuntimeClaims

    RP->>KDS: Request VCEK Cert Chain w.r.t. SEV-SNP AR
    KDS-->>RP: ARK, ASK, VCEK Certs

    RP->>RP: Verify CoT (ARK→ASK→VCEK→SEV-SNP AR)
    RP->>RP: Verify CoT (SEV-SNP AR→RuntimeClaims)
    Note right of RP: Check H(RuntimeClaims) == AR.ReportData?
    RP->>RP: Verify RuntimeClaims contents (incl. User Data)
```

However, it is important to note that this only actually guarantees that the paravisor is running in an SEV-SNP environment and that the guest VM is a proxy for the paravisor. It does not guarantee that the guest VM itself is in an SEV-SNP environment.

