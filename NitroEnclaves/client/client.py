import cbor2
import base64
import socket
import json
import secrets
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.backends import default_backend

from cose.messages import CoseMessage
from cose.keys import EC2Key
from cose.keys.keyparam import KpKty, EC2KpX, EC2KpY, EC2KpCurve
from cose.keys.keytype import KtyEC2
from cose.keys.curves import P384

CID = 16
VSOCK_PORT = 5000

# AWS Nitro Enclaves Root Certificate (embedded)
AWS_NITRO_ROOT_CERT_PATH = "root.pem"
EXPECTED_MEASUREMENTS_PATH = "expected-measurements.json"

"""
Get attestation document from enclave
@param user_data_b64: User data in base64
@param nonce_b64: Nonce in base64
@return: Attestation document in base64
"""
def get_attestation_document(user_data_b64, nonce_b64):
    print(f"Connecting to enclave CID {CID} on port {VSOCK_PORT}...")
    
    with socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM) as vsock:
        try:
            vsock.settimeout(10)  # 10 second timeout
            vsock.connect((CID, VSOCK_PORT))
            print("Connected to enclave successfully")
            
            request = {'user-data': user_data_b64, 'nonce': nonce_b64}
            request_json = json.dumps(request)
            print("Sending request")
            
            vsock.sendall(request_json.encode())
            print("Request sent, waiting for response...")
            
            response_bytes = vsock.recv(8192)
            if not response_bytes:
                raise Exception("No response received from enclave")
                
            response_json = json.loads(response_bytes.decode())
            print("Received response")
            
            if 'error' in response_json:
                raise Exception(f"Enclave error: {response_json['error']}")
                
            document = response_json['document']
            return document
            
        except socket.timeout:
            raise Exception("Connection timeout - enclave may not be running")
        except ConnectionRefusedError:
            raise Exception("Connection refused - check if enclave is running and CID is correct")
        except Exception as e:
            raise Exception(f"Connection error: {e}")

"""
Extract JSON report from CBOR-formatted attestation document
@param attestation_document_b64: Attestation document in base64
@return: JSON report
"""
def extract_report_from_cbor(attestation_document_b64):
    try:
        # Base64 decode the attestation document into CBOR
        attestation_document_cbor = base64.b64decode(attestation_document_b64)
        print(f"Decoded CBOR document size: {len(attestation_document_cbor)} bytes")
        
        # CBOR parse the attestation document
        cbor_data = cbor2.loads(attestation_document_cbor)
        print(f"CBOR structure: {type(cbor_data)}")
        
        # COSE Sign1 structure parse the attestation document
        if isinstance(cbor_data, list) and len(cbor_data) >= 4:
            # COSE Sign1 format: [protected, unprotected, payload, signature]
            protected_header = cbor_data[0]
            unprotected_header = cbor_data[1] 
            payload = cbor_data[2]
            signature = cbor_data[3]
            
            print(f"Protected header: {protected_header}")
            print(f"Unprotected header: {unprotected_header}")
            print(f"Payload type: {type(payload)}")
            print(f"Signature length: {len(signature) if signature else 0}")
            
            # Parse payload as CBOR
            if isinstance(payload, bytes):
                try:
                    report_data = cbor2.loads(payload)
                    print(f"Report data type: {type(report_data)}")
                    return report_data, protected_header, signature, attestation_document_cbor
                except Exception as e:
                    print(f"Failed to parse payload as CBOR: {e}")
                    return payload, protected_header, signature, attestation_document_cbor
            else:
                return payload, protected_header, signature, attestation_document_cbor
        else:
            print(f"Unexpected CBOR structure: {cbor_data}")
            return cbor_data, None, None, attestation_document_cbor
            
    except Exception as e:
        print(f"Error extracting report from CBOR: {e}")
        raise Exception(f"Failed to extract report from CBOR: {e}")

"""
Convert an EC public key to a COSE EC2 key
@param ec_public_key: EC public key
@return: COSE EC2 key
"""
def convert_pubkey_to_cosekey(ec_public_key):
    pt = ec_public_key.public_numbers()
    x = pt.x.to_bytes(48, byteorder='big')
    y = pt.y.to_bytes(48, byteorder='big')
    cose_key = EC2Key.from_dict({KpKty: KtyEC2, EC2KpCurve: P384, EC2KpX: x, EC2KpY: y})
    return cose_key

"""
Convert the COSE data to a COSE message
@param cose_data: COSE data
@return: COSE message
"""
def convert_cosedata_to_cosemsg(cose_data):
    # Load the COSE data as a list
    cose_list = cbor2.loads(cose_data)
    # Add the COSE Sign1 tag to the COSE list
    cose_tagged = cbor2.CBORTag(18, cose_list)
    # Convert the COSE tagged to bytes
    tagged_bytes = cbor2.dumps(cose_tagged)
    # Convert the bytes to a COSE message
    return CoseMessage.decode(tagged_bytes)

"""
Verify the COSE signature
@param cose_msg: COSE message
@return: True if the signature is valid, False otherwise
"""
def verify_signature(cose_msg):
    try:
        # Load the COSE message payload as a dictionary
        att_doc_data = cbor2.loads(cose_msg.payload)
        # Load the certificate from the COSE message payload
        cert = x509.load_der_x509_certificate(att_doc_data["certificate"], default_backend())
        # Convert the certificate public key to a COSE EC2 key
        cose_key = convert_pubkey_to_cosekey(cert.public_key())
        # Set the COSE key to the COSE message
        cose_msg.key = cose_key
        # Verify the signature
        return cose_msg.verify_signature()
    except Exception as e:
        print(f"❌ Signature verification failed: {e}")
        return False

"""
Verify the certificate signature
@param cert_to_verify: Certificate to verify
@param signing_cert: Signing certificate
@return: True if the signature is valid, False otherwise
"""
def verify_certificate_signature_ecdsa_sha384(cert_to_verify, signing_cert):
    try:
        # Get the public key from the signing certificate
        signing_public_key = signing_cert.public_key()
        
        # Verify the signature (ECDSA-SHA384)
        signing_public_key.verify(
            cert_to_verify.signature,
            cert_to_verify.tbs_certificate_bytes,
            ec.ECDSA(hashes.SHA384())
        )

        return True
        
    except Exception as e:
        print(f"❌ Certificate signature verification failed: {e}")
        print(f"   Error type: {type(e)}")
        return False

"""
Verify the certificate chain
@param attestation_cert: Attestation certificate
@param root_cert: Root certificate
@param cabundle: Cabundle (list of intermediate certificates)
@return: True if the certificate chain is valid, False otherwise
"""
def verify_certificate_chain(attestation_cert, root_cert, cabundle):
    try:
        print("Verifying certificate chain...")
        
        print("Root certificate (Cert 0):")
        print(f"   Subject: {root_cert.subject}")
        print(f"   Issuer: {root_cert.issuer}")
        
        print(f"Intermediate certificates: {len(cabundle)} certificates")
        
        # Load all intermediate certificates from the cabundle
        cert_chain = [root_cert]
        for i, cert_bytes in enumerate(cabundle):
            # Parse the certificate from the cabundle
            cert = x509.load_der_x509_certificate(cert_bytes, default_backend())
            # Add the certificate to the list of intermediate certificates
            cert_chain.append(cert)
            print(f"   Cert {i+1}:")
            print(f"       Subject: {cert.subject}")
            print(f"       Issuer:  {cert.issuer}")

        cert_chain.append(attestation_cert)

        print(f"Leaf certificate (Cert {len(cabundle) + 1}):")
        print(f"   Subject: {attestation_cert.subject}")
        print(f"   Issuer:  {attestation_cert.issuer}")

        for i in range(len(cert_chain) - 1):  # Reverse order
            current_cert = cert_chain[i+1]
            signing_cert = cert_chain[i]
            if verify_certificate_signature_ecdsa_sha384(current_cert, signing_cert):
                print(f"✅ Cert {i} is signed by Cert {i + 1}")
            else:
                print(f"❌ Cert {i} is not signed by Cert {i + 1}")
                return False
            
            current_cert = signing_cert
        
        return True
        
    except Exception as e:
        print(f"❌ Certificate chain verification failed: {e}")
        return False

"""
Verify the report contents. This includes verifying the PCR values (specified in expected_measurements.json), user data, and nonce.
@param report_data: Report data
@param user_data: User data
@param nonce: Nonce
@return: True if the report contents are valid, False otherwise
"""
def verify_report_contents(report_data, user_data, nonce):
    try:
        # expected_measurements.json load
        with open(EXPECTED_MEASUREMENTS_PATH, 'r') as f:
            expected_measurements = json.load(f)
        
        expected_pcrs = expected_measurements['Measurements']
        print(f"Expected PCR values loaded from {EXPECTED_MEASUREMENTS_PATH}")
        
        # Get PCR values from report
        if 'pcrs' not in report_data:
            raise Exception("No PCR values found in attestation document")
        
        report_pcrs = report_data['pcrs']
        
        # Verify PCR 0-2 values
        for pcr_id in [0, 1, 2]:
            expected_key = f"PCR{pcr_id}"
            if expected_key not in expected_pcrs:
                print(f"⚠️  Warning: {expected_key} not found in expected measurements")
                continue
            
            expected_hex = expected_pcrs[expected_key]
            expected_bytes = bytes.fromhex(expected_hex)
            
            if pcr_id not in report_pcrs:
                raise Exception(f"PCR{pcr_id} not found in attestation document")
            
            actual_bytes = report_pcrs[pcr_id]
            
            if expected_bytes == actual_bytes:
                print(f"✅ PCR{pcr_id}: MATCH")
                print(f"   Expected: {expected_hex}")
                print(f"   Actual:   {actual_bytes.hex()}")
            else:
                print(f"❌ PCR{pcr_id}: MISMATCH")
                print(f"   Expected: {expected_hex}")
                print(f"   Actual:   {actual_bytes.hex()}")
                return False
        
        # Verify user data and nonce
        if 'user_data' in report_data:
            if report_data['user_data'] == user_data:
                print("✅ User data: MATCH")
                print(f"   Expected: {user_data}")
                print(f"   Actual:   {report_data['user_data']}")
            else:
                print("❌ User data: MISMATCH")
                print(f"   Expected: {user_data}")
                print(f"   Actual:   {report_data['user_data']}")
                return False
        
        if 'nonce' in report_data:
            if report_data['nonce'] == nonce:
                print("✅ Nonce: MATCH")
                print(f"   Expected: {nonce.hex()}")
                print(f"   Actual:   {report_data['nonce'].hex()}")
            else:
                print("❌ Nonce: MISMATCH")
                print(f"   Expected: {nonce.hex()}")
                print(f"   Actual:   {report_data['nonce'].hex()}")
                return False
        
        return True
        
    except FileNotFoundError:
        print("Warning: expected-measurements.json not found, skipping PCR verification")
        return False
    except Exception as e:
        print(f"❌ Report contents verification failed: {e}")
        return False

"""
Verify the attestation document. This includes verifying the COSE signature, certificate chain, and report contents.
@param attestation_doc_data: Attestation document data in JSON format
@param attestation_doc_bytes: Attestation document bytes in CBOR format
@param user_data: User data in bytes
@param nonce: Nonce in bytes
@return: True if the attestation document is valid, False otherwise
"""
def verify_attestation_document(attestation_doc_data, attestation_doc_bytes, user_data, nonce):
    try:
        print("Starting attestation document verification...")
        print("-" * 50)
        
        # Step 1: Load attestation certificate
        print("Step 1: Extracting leaf certificate from attestation document...")
        if 'certificate' not in attestation_doc_data:
            raise Exception("No certificate found in attestation document")
        
        attestation_cert_bytes = attestation_doc_data['certificate']
        attestation_cert = x509.load_der_x509_certificate(
            attestation_cert_bytes,
            default_backend()
        )
        print("Leaf certificate extracted")
        print(f"   Subject: {attestation_cert.subject}")
        print(f"   Issuer:  {attestation_cert.issuer}")
        print("-" * 50)

        # Step 2: Verify COSE signature
        print("Step 2: Verifying COSE signature...")
        cose_msg = convert_cosedata_to_cosemsg(attestation_doc_bytes)
        
        if verify_signature(cose_msg):
            print("✅ COSE Signature is valid.")
        else:
            print("❌ COSE Signature is invalid.")
            return False
        print("-" * 50)
        
        # Step 3: Verify certificate chain
        print("Step 3: Verifying certificate chain...")
        with open(AWS_NITRO_ROOT_CERT_PATH, "r") as f:
            root_cert = x509.load_pem_x509_certificate(
                f.read().encode(),
                default_backend()
            )
        
        # Get intermediate certificates from cabundle
        cabundle = attestation_doc_data.get('cabundle', None)

        # Verify the certificate chain
        if verify_certificate_chain(attestation_cert, root_cert, cabundle):
            print("✅ Certificate chain is valid.")
        else:
            print("❌ Certificate chain is invalid.")
            return False
        print("-" * 50)

        # Step 4: Verify PCR values, user data, and nonce
        print("Step 4: Verifying PCR values, user data, and nonce...")
        if verify_report_contents(attestation_doc_data, user_data, nonce):
            print("✅ Report contents are valid.")
        else:
            print("❌ Report contents are invalid.")
            return False
        print("-" * 50)

        return True
        
    except Exception as e:
        print(f"❌ Attestation document verification failed: {e}")
        return False

def main():
    user_data = b'hello'
    nonce = secrets.token_bytes(64)
    user_data_b64 = base64.b64encode(user_data).decode()
    nonce_b64 = base64.b64encode(nonce).decode()

    print("="*50)
    print("REQUESTING ATTESTATION DOCUMENT FROM ENCLAVE")
    print("="*50)

    print(f"User data: {user_data}")
    print(f"Nonce:     {nonce_b64}")
    
    # Get attestation document
    attestation_document_b64 = get_attestation_document(user_data_b64, nonce_b64)
    print(f"Attestation document length: {len(attestation_document_b64)} characters")
    
    # Save raw attestation document to file
    document_filename = "attestation-document.dat"
    with open(document_filename, "w") as f:
        f.write(attestation_document_b64)
    print(f"Raw attestation document saved to: {document_filename}")
    
    # Parse CBOR document
    print("\n" + "="*50)
    print("PARSING ATTESTATION DOCUMENT")
    print("="*50)
    print("Extracting report from CBOR document...")
    attestation_doc_data, protected_header, signature, attestation_doc_bytes = extract_report_from_cbor(attestation_document_b64)
    
    # Save parsed JSON data
    if isinstance(attestation_doc_data, dict):
        document_filename = "attestation-document-json.json"
        with open(document_filename, "w") as f:
            f.write(str(attestation_doc_data))
        print(f"Attestation document JSON saved to: {document_filename}")
    
    # Verify attestation document
    print("\n" + "="*50)
    print("VERIFYING ATTESTATION DOCUMENT")
    print("="*50)
        
    if verify_attestation_document(attestation_doc_data, attestation_doc_bytes, user_data, nonce):
        print("\n✅ Attestation verification successful.")
    else:
        print("\n❌ Attestation verification failed.")
    print("-" * 50)

if __name__ == "__main__":
    main()
