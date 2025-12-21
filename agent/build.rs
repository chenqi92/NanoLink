use std::io::Result;
use std::path::Path;

fn main() -> Result<()> {
    // Check if we should skip protobuf generation (e.g., in CI without proto files)
    if std::env::var("SKIP_PROTOBUF").is_ok() {
        println!("cargo:warning=Skipping protobuf generation (SKIP_PROTOBUF is set)");
        return Ok(());
    }

    // Use CARGO_MANIFEST_DIR for reliable path resolution
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let proto_path = Path::new(&manifest_dir).join("../sdk/protocol/nanolink.proto");
    let proto_dir = Path::new(&manifest_dir).join("../sdk/protocol");

    // Tell cargo to rerun if proto file changes
    println!("cargo:rerun-if-changed={}", proto_path.display());
    println!("cargo:rerun-if-changed={}", proto_dir.display());

    if !proto_path.exists() {
        println!(
            "cargo:warning=Proto file not found at {:?}, skipping protobuf generation",
            proto_path
        );
        return Ok(());
    }

    // Use tonic-build to generate both protobuf messages and gRPC client/server code
    // Output goes to OUT_DIR by default
    tonic_build::configure()
        .build_server(false) // Agent only needs client
        .build_client(true)
        .compile(&[proto_path.to_str().unwrap()], &[proto_dir.to_str().unwrap()])?;

    Ok(())
}
