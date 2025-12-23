//! Windows-specific implementations
//!
//! Provides Windows Service integration for running the agent as a background service.

use std::ffi::OsString;
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

use windows_service::{
    define_windows_service,
    service::{
        ServiceAccess, ServiceControl, ServiceControlAccept, ServiceErrorControl, ServiceExitCode,
        ServiceInfo, ServiceStartType, ServiceState, ServiceStatus, ServiceType,
    },
    service_control_handler::{self, ServiceControlHandlerResult},
    service_dispatcher,
    service_manager::{ServiceManager, ServiceManagerAccess},
};

const SERVICE_NAME: &str = "NanoLinkAgent";
const SERVICE_DISPLAY_NAME: &str = "NanoLink Agent";
const SERVICE_DESCRIPTION: &str = "Lightweight server monitoring agent for NanoLink";

/// Install the NanoLink Agent as a Windows Service
pub fn install_service(config_path: Option<PathBuf>) -> Result<(), String> {
    let manager = ServiceManager::local_computer(
        None::<&str>,
        ServiceManagerAccess::CONNECT | ServiceManagerAccess::CREATE_SERVICE,
    )
    .map_err(|e| format!("Failed to connect to service manager: {e}"))?;

    // Get the path to the current executable
    let exe_path =
        std::env::current_exe().map_err(|e| format!("Failed to get executable path: {e}"))?;

    // Build service arguments
    let mut args = vec![OsString::from("service"), OsString::from("run")];
    if let Some(config) = config_path {
        args.push(OsString::from("--config"));
        args.push(config.into_os_string());
    }

    let service_info = ServiceInfo {
        name: OsString::from(SERVICE_NAME),
        display_name: OsString::from(SERVICE_DISPLAY_NAME),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::AutoStart,
        error_control: ServiceErrorControl::Normal,
        executable_path: exe_path,
        launch_arguments: args,
        dependencies: vec![],
        account_name: None, // LocalSystem account
        account_password: None,
    };

    let service = manager
        .create_service(
            &service_info,
            ServiceAccess::CHANGE_CONFIG | ServiceAccess::START,
        )
        .map_err(|e| format!("Failed to create service: {e}"))?;

    // Set service description
    service
        .set_description(SERVICE_DESCRIPTION)
        .map_err(|e| format!("Failed to set service description: {e}"))?;

    println!("Service '{}' installed successfully.", SERVICE_DISPLAY_NAME);
    println!("Use 'sc start {}' to start the service.", SERVICE_NAME);
    Ok(())
}

/// Uninstall the NanoLink Agent Windows Service
pub fn uninstall_service() -> Result<(), String> {
    let manager = ServiceManager::local_computer(
        None::<&str>,
        ServiceManagerAccess::CONNECT | ServiceManagerAccess::CREATE_SERVICE,
    )
    .map_err(|e| format!("Failed to connect to service manager: {e}"))?;

    let service = manager
        .open_service(
            SERVICE_NAME,
            ServiceAccess::DELETE | ServiceAccess::QUERY_STATUS,
        )
        .map_err(|e| format!("Failed to open service: {e}"))?;

    // Check if service is running
    let status = service
        .query_status()
        .map_err(|e| format!("Failed to query service status: {e}"))?;

    if status.current_state != ServiceState::Stopped {
        return Err(format!(
            "Service is still running. Stop it first with 'sc stop {}'",
            SERVICE_NAME
        ));
    }

    service
        .delete()
        .map_err(|e| format!("Failed to delete service: {e}"))?;

    println!(
        "Service '{}' uninstalled successfully.",
        SERVICE_DISPLAY_NAME
    );
    Ok(())
}

/// Start the service
pub fn start_service() -> Result<(), String> {
    let manager =
        ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT).unwrap();

    let service = manager
        .open_service(SERVICE_NAME, ServiceAccess::START)
        .map_err(|e| format!("Failed to open service: {e}"))?;

    service
        .start::<String>(&[])
        .map_err(|e| format!("Failed to start service: {e}"))?;

    println!("Service '{}' started.", SERVICE_DISPLAY_NAME);
    Ok(())
}

/// Stop the service
pub fn stop_service() -> Result<(), String> {
    let manager =
        ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT).unwrap();

    let service = manager
        .open_service(
            SERVICE_NAME,
            ServiceAccess::STOP | ServiceAccess::QUERY_STATUS,
        )
        .map_err(|e| format!("Failed to open service: {e}"))?;

    service
        .stop()
        .map_err(|e| format!("Failed to stop service: {e}"))?;

    println!("Service '{}' stopped.", SERVICE_DISPLAY_NAME);
    Ok(())
}

/// Query service status
pub fn query_service_status() -> Result<String, String> {
    let manager =
        ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT).unwrap();

    let service = manager
        .open_service(SERVICE_NAME, ServiceAccess::QUERY_STATUS)
        .map_err(|e| format!("Failed to open service: {e}"))?;

    let status = service
        .query_status()
        .map_err(|e| format!("Failed to query status: {e}"))?;

    let state = match status.current_state {
        ServiceState::Stopped => "Stopped",
        ServiceState::StartPending => "Starting...",
        ServiceState::StopPending => "Stopping...",
        ServiceState::Running => "Running",
        ServiceState::ContinuePending => "Resuming...",
        ServiceState::PausePending => "Pausing...",
        ServiceState::Paused => "Paused",
    };

    Ok(format!("Service '{}': {}", SERVICE_DISPLAY_NAME, state))
}

// Define the Windows service entry point
define_windows_service!(ffi_service_main, service_main);

/// Entry point called by the Windows Service Control Manager
fn service_main(_arguments: Vec<OsString>) {
    if let Err(e) = run_service() {
        eprintln!("Service error: {e}");
    }
}

/// Run as a Windows service
pub fn run_as_service() -> Result<(), String> {
    service_dispatcher::start(SERVICE_NAME, ffi_service_main)
        .map_err(|e| format!("Failed to start service dispatcher: {e}"))
}

/// Internal service runner
fn run_service() -> Result<(), String> {
    // Create a channel to receive stop events
    let (shutdown_tx, shutdown_rx) = mpsc::channel();

    // Define the service control handler
    let event_handler = move |control_event| -> ServiceControlHandlerResult {
        match control_event {
            ServiceControl::Stop => {
                let _ = shutdown_tx.send(());
                ServiceControlHandlerResult::NoError
            }
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };

    // Register the service control handler
    let status_handle = service_control_handler::register(SERVICE_NAME, event_handler)
        .map_err(|e| format!("Failed to register service control handler: {e}"))?;

    // Set service as running
    status_handle
        .set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Running,
            controls_accepted: ServiceControlAccept::STOP,
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        })
        .map_err(|e| format!("Failed to set service status: {e}"))?;

    // Create tokio runtime and run the agent
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|e| format!("Failed to create tokio runtime: {e}"))?;

    runtime.block_on(async {
        // Find config file (check common locations)
        let config_path = find_config_path();

        // Start agent in a task
        let agent_handle = tokio::spawn(async move {
            if let Err(e) = crate::run_agent(config_path).await {
                eprintln!("Agent error: {e}");
            }
        });

        // Wait for shutdown signal
        let _ = tokio::task::spawn_blocking(move || {
            let _ = shutdown_rx.recv();
        })
        .await;

        // Abort the agent task
        agent_handle.abort();
    });

    // Set service as stopped
    status_handle
        .set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Stopped,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        })
        .map_err(|e| format!("Failed to set service status: {e}"))?;

    Ok(())
}

/// Find configuration file in common locations
fn find_config_path() -> PathBuf {
    let candidates = [
        // Same directory as executable
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|p| p.join("nanolink.yaml"))),
        // ProgramData directory
        std::env::var("ProgramData")
            .ok()
            .map(|p| PathBuf::from(p).join("NanoLink").join("nanolink.yaml")),
        // Current directory
        Some(PathBuf::from("nanolink.yaml")),
    ];

    for candidate in candidates.into_iter().flatten() {
        if candidate.exists() {
            return candidate;
        }
    }

    // Default to nanolink.yaml in current directory
    PathBuf::from("nanolink.yaml")
}
