use std::io::Result;

fn main() -> Result<()> {
    // Use tonic-build to generate both protobuf messages and gRPC client/server code
    tonic_build::configure()
        .build_server(false) // Agent only needs client
        .build_client(true)
        .out_dir("src/generated")
        .compile(&["../sdk/protocol/nanolink.proto"], &["../sdk/protocol/"])?;

    // Also compile with prost for backward compatibility with WebSocket
    prost_build::compile_protos(&["../sdk/protocol/nanolink.proto"], &["../sdk/protocol/"])?;

    Ok(())
}
