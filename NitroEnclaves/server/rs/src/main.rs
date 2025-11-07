use anyhow::{Result, anyhow};
use base64::{Engine as _, engine::general_purpose};
use serde::{Deserialize, Serialize};
use serde_json;
use std::io::{Read, Write};
use vsock::{VsockAddr, VsockStream};

use aws_nitro_enclaves_nsm_api::{
    api::{Request, Response},
    driver,
};

const VSOCK_PORT: u32 = 5000;

#[derive(Deserialize)]
struct AttestationRequest {
    #[serde(rename = "user-data")]
    user_data: String,
    #[serde(rename = "nonce")]
    nonce: String,
}

#[derive(Serialize)]
struct AttestationResponse {
    document: String,
}

fn main() -> Result<()> {
    println!("Enclave: Starting Nitro Enclave...");
    println!("Enclave: Starting vsock server on port {}...", VSOCK_PORT);

    let addr = VsockAddr::new(vsock::VMADDR_CID_ANY, VSOCK_PORT);
    let listener = vsock::VsockListener::bind(&addr)?;
    println!("Enclave: Vsock server listening on port {}", VSOCK_PORT);

    for stream in listener.incoming() {
        match stream {
            Ok(mut stream) => {
                println!("Enclave: Accepted connection from parent VM");
                handle_connection(&mut stream)?;
            }
            Err(e) => {
                eprintln!("Enclave: Error accepting connection: {}", e);
            }
        }
    }

    Ok(())
}

fn handle_connection(stream: &mut vsock::VsockStream) -> Result<()> {
    let mut buffer = [0; 8192];
    loop {
        match stream.read(&mut buffer) {
            Ok(0) => {
                println!("Enclave: Connection closed by parent");
                break;
            }
            Ok(n) => {
                println!("Enclave: Received {} bytes from parent", n);

                // Parse the received data as an attestation request
                let request_data = String::from_utf8_lossy(&buffer[..n]);
                println!("Enclave: Received request: {}", request_data);

                // Parse JSON request
                match serde_json::from_str::<AttestationRequest>(&request_data) {
                    Ok(attestation_request) => {
                        println!("Enclave: Parsed attestation request successfully");

                        // Decode the base64 encoded data
                        let user_data = match general_purpose::STANDARD
                            .decode(&attestation_request.user_data)
                        {
                            Ok(data) => {
                                println!(
                                    "Enclave: Successfully decoded report-data ({} bytes)",
                                    data.len()
                                );
                                data
                            }
                            Err(e) => {
                                println!("Enclave: Failed to decode report-data: {:?}", e);
                                let error_response = serde_json::json!({
                                    "error": "Invalid report-data encoding",
                                    "message": e.to_string()
                                });
                                if let Ok(error_json) = serde_json::to_string(&error_response) {
                                    let _ = stream.write_all(error_json.as_bytes());
                                }
                                continue;
                            }
                        };

                        let nonce =
                            match general_purpose::STANDARD.decode(&attestation_request.nonce) {
                                Ok(data) => {
                                    println!(
                                        "Enclave: Successfully decoded nonce ({} bytes)",
                                        data.len()
                                    );
                                    data
                                }
                                Err(e) => {
                                    println!("Enclave: Failed to decode nonce: {:?}", e);
                                    let error_response = serde_json::json!({
                                        "error": "Invalid nonce encoding",
                                        "message": e.to_string()
                                    });
                                    if let Ok(error_json) = serde_json::to_string(&error_response) {
                                        let _ = stream.write_all(error_json.as_bytes());
                                    }
                                    continue;
                                }
                            };

                        // Fetch attestation document from NSM
                        match fetch_document_from_nsm(user_data, nonce) {
                            Ok(doc) => {
                                let encoded_doc = general_purpose::STANDARD.encode(doc);
                                let response = AttestationResponse {
                                    document: encoded_doc,
                                };

                                if let Ok(response_json) = serde_json::to_string(&response) {
                                    println!(
                                        "Enclave: Sending attestation response ({} bytes)",
                                        response_json.len()
                                    );
                                    if let Err(e) = stream.write_all(response_json.as_bytes()) {
                                        eprintln!("Enclave: Error writing response: {}", e);
                                        break;
                                    }
                                } else {
                                    eprintln!("Enclave: Failed to serialize response");
                                }
                            }
                            Err(e) => {
                                eprintln!("Enclave: Failed to get attestation document: {:?}", e);
                                let error_response = serde_json::json!({
                                    "error": "NSM device not available",
                                    "message": e.to_string(),
                                    "status": "NSM_UNAVAILABLE"
                                });
                                if let Ok(error_json) = serde_json::to_string(&error_response) {
                                    let _ = stream.write_all(error_json.as_bytes());
                                }
                            }
                        }
                    }
                    Err(e) => {
                        println!("Enclave: Failed to parse JSON request: {:?}", e);
                        let error_response = serde_json::json!({
                            "error": "Invalid JSON request",
                            "message": e.to_string()
                        });
                        if let Ok(error_json) = serde_json::to_string(&error_response) {
                            let _ = stream.write_all(error_json.as_bytes());
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("Enclave: Error reading from stream: {}", e);
                break;
            }
        }
    }

    Ok(())
}

fn fetch_document_from_nsm(user_data: Vec<u8>, nonce: Vec<u8>) -> Result<Vec<u8>> {
    let nsm_fd = driver::nsm_init();

    // Create the attestation request with user data as nonce for this PoC
    println!("Enclave: Sending attestation request to NSM...");
    println!("Enclave: NSM file descriptor: {}", nsm_fd);
    println!("Enclave: Request user_data length: {}", user_data.len());
    println!("Enclave: Request nonce length: {}", nonce.len());

    // Create the attestation request
    // Note: NSM automatically includes PCRs 0-2 in the attestation document
    let request = Request::Attestation {
        user_data: Some(user_data.clone().into()),
        nonce: Some(nonce.clone().into()),
        public_key: None,
    };

    // Process the request through the NSM driver
    let response = driver::nsm_process_request(nsm_fd, request);
    println!("Enclave: Received response from NSM");

    // Exit the NSM driver
    driver::nsm_exit(nsm_fd);

    // Return the document
    match response {
        Response::Attestation { document } => {
            println!(
                "Enclave: Successfully obtained attestation document ({} bytes)",
                document.len()
            );
            Ok(document)
        }
        Response::Error(err) => {
            eprintln!("Enclave: NSM Error: {:?}", err);
            Err(anyhow!("NSM Error: {:?}", err))
        }
        _ => {
            eprintln!("Enclave: Unexpected response type from NSM");
            Err(anyhow!("NSM Error: Unexpected response type returned"))
        }
    }
}

