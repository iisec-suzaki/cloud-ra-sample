# How to Deploy an MAA Provider

Microsoft Azure Attestation (MAA) provides an API for verifying Attestation Reports and generate attestation tokens (signed by Azure CA). By deploying a server that acts as a Verifier (an MAA Provider) and sending the necessary evidence to it, it will automatically perform the verification. This makes it possible to verify an AR without low-level knowledge of RA.

You can set a user-specified "attestation policy" for each TEE type in the MAA provider. However, the verification logic of MAA is not fully public, and it is not clear exactly what kind of verification is performed.

When performing Report/Quote verification with MAA, it is necessary to prepare an MAA provider in advance. You can use the default providers offered in each region, but you cannot change the "attestation policy" with the default providers. This section explains how to set up your own.

The following information is based on the state as of September 2025.

## TEE/API Version Compatibility Table

The supported TEE types differ depending on the API Version. Only those whose support status can be confirmed from the API documentation are listed.

|                    | 2020-10-01 | 2022-08-01 | 2025-06-01 |
| :--                | :--        | :--        | :--        |
| TPM                | ✅ | ✅ | ✅ | 
| SGX                | ✅ | ✅ | ✅ |
| Open Enclave (SGX) | ✅ | ✅ | ✅ |
| SEV-SNP            | ❓ | ✅ | ✅ |
| TDX                | ❌ | ❌ | ✅ |
| Azure Guest        | ❌ | ❌ | ✅ |

SGX has been officially supported since `2020-10-01` (stable), and both default providers and self-deployed providers offer this API Version.

SEV-SNP has been officially supported since `2022-08-01` (stable), and both default providers and self-deployed providers offer this API Version. Note that the `Attest Sev Snp Vm` endpoint of API Version `2020-10-01` (stable) also works, but it is not described in the official documentation. Not limited to SEV-SNP, there is a possibility that TEE types are supported from a Version earlier than the API Version listed in the table.

TDX has been officially supported since API Version `2025-06-01` (stable), and general availability of this version began in early August 2025.

## Checking API Availability
Check which MAA APIs are available in which regions.

```bash
az provider show --namespace Microsoft.Attestation
```

However, the information displayed here does not reflect the actual situation. In fact, API Version `2022-08-01` is available in multiple regions including Japan West/East and US West/East, but the above command displays it as if there are no regions corresponding to that API Version (as of August 1, 2025).

Furthermore, even if a provider is assigned an older API Version, it may be updated internally and a newer API may be available. Ultimately, *you cannot determine whether a particular API is usable until you actually deploy it and try to hit the API endpoint.*

## Deploy an MAA Provider

### Using the Portal
1. Select `Microsoft Azure Attestation` from the search form in the portal and go to the "Create attestation provider" screen.
2. Set the resource group, instance name, instance location (region), etc. as appropriate.
3. The "Policy signer certificates" setting is optional.
    - You can sign the attestation policy settings.
    - By verifying signatures, the relying party can confirm the authenticity of the verification policy settings.
4. Deploy

This creates the MAA provider. Take note of the provider URI listed on the overview page.

### Deploying using an ARM template
You can also create an ARM template like the one below and deploy from the template via the portal or CLI. This has the advantage of being able to explicitly specify the API Version. Deployment will fail if you specify an unavailable region or API Version.

```json
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "resources": [
      {
        "type": "Microsoft.Attestation/attestationProviders",
        "apiVersion": "API_VERSION",
        "name": "ATTESTATION_PROVIDER_NAME",
        "location": "LOCATION",
        "properties": {}
      }
    ]
}
```

### Using the Azure CLI
As of August 1, 2025, note that the Attestation-related commands in the Azure CLI are in an experimental version, so their operation is not guaranteed.

```bash
az attestation create \
    --name "$ATTESTATION_PROVIDER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION"
```

### About the MAA Provider's Region
In the protocol where the Attester (CVM) sends its Attestation Evidence to the MAA provider to receive an Attestation JWT, which is then sent to the Relying Party for verification with the Azure CA, it is desirable for the CVM and the MAA provider to be in close network proximity. Therefore, it is recommended to place them in the same region.

In the protocol where the Attester passes the Attestation Evidence to the Relying Party, and the Relying Party sends it to MAA for verification, it is best to place the MAA provider in a region that is in close network proximity to the Relying Party.

## Checking API Endpoints

### Checking from the Portal
From the Web Console, select the created MAA provider, go to the overview page, and select "Policy" or "Attestation Policy" to go to the attestation policy confirmation/configuration page. You can check the supported TEE types from the "Attestation Type" dropdown list here.

Also, clicking "JSON view" on the overview page will display a JSON like the one below.

```json
{
    "id": "PROVIDER_ID",
    "name": "PROVIDER_NAME",
    "type": "Microsoft.Attestation/attestationProviders",
    "location": "LOCATION",
    "properties": {
        "trustModel": "AAD",
        "status": "Ready",
        "attestUri": "PROVIDER_URI"
    },
    "apiVersion": "API_VERSION"
}
```

You can find out the API Version from here. However, [as mentioned before](#checking-api-availability), there is a discrepancy between this API Version and the API Version that the provider actually offers.

### Checking with the API
You can also check using the following endpoint. However, this endpoint is only available in API Version `2025-06-01` and later. Therefore, it can currently only be used to check whether it is compatible with `2025-06-01`.

```bash
VERIFIER_URL="Your MAA Provider URI"
TEE_TYPE="TdxVm"
API_VERSION="2025-06-01"
MAA_REQUEST_URL="$VERIFIER_URL/tcbbaselines/$TEE_TYPE?api-version=$API_VERSION"

curl -s -X POST "$MAA_REQUEST_URL" > maa-baselines-response.json
```

### Checking with the Azure CLI
```bash
az attestation show \
    --name "$ATTESTATION_PROVIDER_NAME" \
    --resource-group "$RESOURCE_GROUP"
```

## About Default Providers

You can easily try out MAA by using an MAA default provider. Default providers are generally named in the format `shared$SHORT_LOCATION` Below are examples of default provider URIs.
- `https://sharedjpw.jpw.attest.azure.net` — Japan West
- `https://sharedjpe.jpe.attest.azure.net` — Japan East
- `https://sharedwus.wus.attest.azure.net` — West US
- `https://sharedeus.eus.attest.azure.net` — East US

You can search for available default providers using the Azure CLI as follows. (This is done on the remote user side.) However, since the `az attestation` command is in an experimental version, normal operation is not guaranteed. In fact, the default providers mentioned above are not found even if you run the following command.

```bash
# Search by specifying location
az attestation get-default-by-location --location $LOCATION

# Search by specifying location
az attestation list-default
```


## References
1. Microsoft: [Azure REST API Specifications — Azure Attestation — Data Plane](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/attestation/data-plane)
2. Microsoft: [Learn/Azure Attestation/Data Plane/Tcb Baselines - Get](https://learn.microsoft.com/en-us/rest/api/attestation/tcb-baselines/get?view=rest-attestation-2025-06-01)
3. Microsoft: [What are ARM templates?](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/overview)
4. Microsoft: [Quickstart: Create and deploy ARM templates by using the Azure portal](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/quickstart-create-templates-use-the-portal)
5. Microsoft: [How to author an attestation policy](https://learn.microsoft.com/en-us/azure/attestation/author-sign-policy)
6. Microsoft: [az attestation](https://learn.microsoft.com/ja-jp/cli/azure/attestation?view=azure-cli-latest)
