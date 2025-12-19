use std::io::Result;
use std::path::Path;

fn main() -> Result<()> {
    // Check if we should skip protobuf generation (e.g., in CI without proto files)
    if std::env::var("SKIP_PROTOBUF").is_ok() {
        println!("cargo:warning=Skipping protobuf generation (SKIP_PROTOBUF is set)");
        return Ok(());
    }

    let proto_file = Path::new("../sdk/protocol/nanolink.proto");

    // Tell cargo to rerun if proto file changes
    println!("cargo:rerun-if-changed=../sdk/protocol/nanolink.proto");
    println!("cargo:rerun-if-changed=../sdk/protocol/");

    if !proto_file.exists() {
        println!(
            "cargo:warning=Proto file not found at {:?}, skipping protobuf generation",
            proto_file
        );
        return Ok(());
    }

    // Use tonic-build to generate both protobuf messages and gRPC client/server code
    // Output goes to OUT_DIR by default
    tonic_build::configure()
        .build_server(false) // Agent only needs client
        .build_client(true)
        .compile(&["../sdk/protocol/nanolink.proto"], &["../sdk/protocol/"])?;

    Ok(())
}
