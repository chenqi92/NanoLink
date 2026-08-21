use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::Path;
use std::time::Duration;

use ssh2::{CheckResult, KnownHostFileKind, Session};

const MAX_REMOTE_OUTPUT_BYTES: u64 = 1024 * 1024;

pub(super) struct RemoteSession {
    session: Session,
    use_sudo: bool,
}

impl RemoteSession {
    pub(super) fn connect(
        params: &HashMap<String, String>,
        timeout: Duration,
    ) -> Result<Self, String> {
        let host = required(params, "ssh_host")?;
        validate_host(&host)?;
        let port = params
            .get("ssh_port")
            .map(String::as_str)
            .unwrap_or("22")
            .parse::<u16>()
            .map_err(|_| "Invalid SSH port".to_string())?;
        let username = required(params, "ssh_username")?;
        validate_username(&username)?;
        let auth_type = required(params, "ssh_auth_type")?;
        // Passwords and PEM payloads are opaque secrets. Do not trim them: a
        // leading/trailing space can legitimately be part of a password, and
        // rewriting a PEM payload makes authentication failures hard to audit.
        let credential = required_raw(params, "ssh_credential")?;
        if credential.len() > 128 * 1024 || credential.contains('\0') {
            return Err("Invalid SSH credential".to_string());
        }
        let known_hosts = params
            .get("ssh_known_hosts")
            .map(|value| value.trim().to_string())
            .unwrap_or_default();
        let allow_unknown = bool_param(params, "ssh_allow_unknown_host", false)?;
        let use_sudo = bool_param(params, "ssh_use_sudo", false)?;

        let connect_timeout = timeout.min(Duration::from_secs(30));
        let address = (host.as_str(), port)
            .to_socket_addrs()
            .map_err(|e| format!("Resolve SSH target failed: {e}"))?
            .find_map(|address| TcpStream::connect_timeout(&address, connect_timeout).ok())
            .ok_or_else(|| format!("Connect to SSH target {host}:{port} failed"))?;
        address
            .set_read_timeout(Some(timeout))
            .map_err(|e| format!("Configure SSH read timeout failed: {e}"))?;
        address
            .set_write_timeout(Some(timeout))
            .map_err(|e| format!("Configure SSH write timeout failed: {e}"))?;

        let mut session = Session::new().map_err(|e| format!("Create SSH session failed: {e}"))?;
        session.set_timeout(timeout.as_millis().min(u32::MAX as u128) as u32);
        session.set_tcp_stream(address);
        session
            .handshake()
            .map_err(|e| format!("SSH handshake failed: {e}"))?;

        if !allow_unknown {
            if known_hosts.is_empty() {
                return Err("SSH host verification data is missing".to_string());
            }
            verify_host_key(&session, &host, port, &known_hosts)?;
        }

        match auth_type.as_str() {
            "password" => session
                .userauth_password(&username, &credential)
                .map_err(|e| format!("SSH password authentication failed: {e}"))?,
            "private_key" => session
                .userauth_pubkey_memory(&username, None, &credential, None)
                .map_err(|e| format!("SSH private-key authentication failed: {e}"))?,
            _ => return Err("SSH auth type must be password or private_key".to_string()),
        }
        if !session.authenticated() {
            return Err("SSH authentication was not accepted".to_string());
        }
        Ok(Self { session, use_sudo })
    }

    pub(super) fn upload_file(&self, local: &Path, remote: &str) -> Result<(), String> {
        validate_remote_temp_path(remote)?;
        let mut input =
            File::open(local).map_err(|e| format!("Open staged artifact failed: {e}"))?;
        let sftp = self
            .session
            .sftp()
            .map_err(|e| format!("Open SFTP channel failed: {e}"))?;
        let mut output = sftp
            .create(Path::new(remote))
            .map_err(|e| format!("Create remote artifact failed: {e}"))?;
        std::io::copy(&mut input, &mut output)
            .map_err(|e| format!("Upload remote artifact failed: {e}"))?;
        output
            .flush()
            .map_err(|e| format!("Flush remote artifact failed: {e}"))?;
        Ok(())
    }

    pub(super) fn upload_content(&self, content: &[u8], remote: &str) -> Result<(), String> {
        validate_remote_temp_path(remote)?;
        let sftp = self
            .session
            .sftp()
            .map_err(|e| format!("Open SFTP channel failed: {e}"))?;
        let mut output = sftp
            .create(Path::new(remote))
            .map_err(|e| format!("Create remote script failed: {e}"))?;
        output
            .write_all(content)
            .map_err(|e| format!("Upload remote script failed: {e}"))?;
        output
            .flush()
            .map_err(|e| format!("Flush remote script failed: {e}"))?;
        Ok(())
    }

    pub(super) fn exec(&self, command: &str) -> Result<String, String> {
        self.exec_inner(command, false)
    }

    pub(super) fn exec_privileged(&self, command: &str) -> Result<String, String> {
        self.exec_inner(command, self.use_sudo)
    }

    fn exec_inner(&self, command: &str, sudo: bool) -> Result<String, String> {
        if command.contains('\0') {
            return Err("Remote command contains NUL".to_string());
        }
        // Merge stderr into stdout on the remote shell. Reading the two SSH
        // streams sequentially can otherwise deadlock when the remote process
        // fills one channel window while the client is draining the other.
        let command = if sudo {
            format!("sudo -n sh -c {} 2>&1", shell_quote(command))
        } else {
            format!("sh -c {} 2>&1", shell_quote(command))
        };
        let mut channel = self
            .session
            .channel_session()
            .map_err(|e| format!("Open SSH command channel failed: {e}"))?;
        channel
            .exec(&command)
            .map_err(|e| format!("Start remote command failed: {e}"))?;
        let mut stdout = Vec::new();
        std::io::Read::by_ref(&mut channel)
            .take(MAX_REMOTE_OUTPUT_BYTES + 1)
            .read_to_end(&mut stdout)
            .map_err(|e| format!("Read remote command output failed: {e}"))?;
        let stdout_truncated = stdout.len() > MAX_REMOTE_OUTPUT_BYTES as usize;
        if stdout_truncated {
            // Keep draining the SSH window after reaching the retained-output
            // limit so a chatty remote process can exit instead of blocking on
            // a full channel buffer.
            std::io::copy(&mut channel, &mut std::io::sink())
                .map_err(|e| format!("Drain remote command output failed: {e}"))?;
        }
        let mut stderr = Vec::new();
        channel
            .stderr()
            .take(MAX_REMOTE_OUTPUT_BYTES + 1)
            .read_to_end(&mut stderr)
            .map_err(|e| format!("Read remote command error failed: {e}"))?;
        let _ = channel.wait_close();
        let status = channel
            .exit_status()
            .map_err(|e| format!("Read remote command status failed: {e}"))?;
        let truncated = stdout_truncated || stderr.len() > MAX_REMOTE_OUTPUT_BYTES as usize;
        stdout.truncate(MAX_REMOTE_OUTPUT_BYTES as usize);
        let remaining = MAX_REMOTE_OUTPUT_BYTES.saturating_sub(stdout.len() as u64) as usize;
        stderr.truncate(remaining);
        let mut output = String::from_utf8_lossy(&stdout).into_owned();
        if !stderr.is_empty() {
            if !output.is_empty() && !output.ends_with('\n') {
                output.push('\n');
            }
            output.push_str(&String::from_utf8_lossy(&stderr));
        }
        if truncated {
            output.push_str("\n[output truncated]");
        }
        if status != 0 {
            return Err(format!(
                "Remote command failed with exit code {status}{}{}",
                if output.trim().is_empty() { "" } else { ": " },
                output.trim()
            ));
        }
        Ok(output)
    }
}

pub(super) fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn verify_host_key(
    session: &Session,
    host: &str,
    port: u16,
    known_hosts_data: &str,
) -> Result<(), String> {
    let (key, _) = session
        .host_key()
        .ok_or_else(|| "SSH server did not provide a host key".to_string())?;
    let mut known_hosts = session
        .known_hosts()
        .map_err(|e| format!("Initialize SSH known_hosts failed: {e}"))?;
    known_hosts
        .read_str(known_hosts_data, KnownHostFileKind::OpenSSH)
        .map_err(|e| format!("Parse SSH known_hosts failed: {e}"))?;
    match known_hosts.check_port(host, port, key) {
        CheckResult::Match => Ok(()),
        CheckResult::Mismatch => Err("SSH host key does not match known_hosts".to_string()),
        CheckResult::NotFound => Err("SSH host key is not present in known_hosts".to_string()),
        CheckResult::Failure => Err("SSH host key verification failed".to_string()),
    }
}

fn required(params: &HashMap<String, String>, name: &str) -> Result<String, String> {
    params
        .get(name)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("Missing remote deployment parameter: {name}"))
}

fn required_raw(params: &HashMap<String, String>, name: &str) -> Result<String, String> {
    params
        .get(name)
        .filter(|value| !value.is_empty())
        .cloned()
        .ok_or_else(|| format!("Missing remote deployment parameter: {name}"))
}

fn bool_param(params: &HashMap<String, String>, name: &str, default: bool) -> Result<bool, String> {
    match params
        .get(name)
        .map(|value| value.trim().to_ascii_lowercase())
    {
        None => Ok(default),
        Some(value) if matches!(value.as_str(), "true" | "1" | "yes") => Ok(true),
        Some(value) if matches!(value.as_str(), "false" | "0" | "no") => Ok(false),
        Some(_) => Err(format!("Invalid remote deployment boolean: {name}")),
    }
}

fn validate_host(host: &str) -> Result<(), String> {
    if host.is_empty()
        || host.len() > 254
        || host.contains("..")
        || !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | ':'))
    {
        return Err("Invalid SSH host".to_string());
    }
    Ok(())
}

fn validate_username(username: &str) -> Result<(), String> {
    if username.is_empty()
        || username.len() > 255
        || !username
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-' | '@'))
    {
        return Err("Invalid SSH username".to_string());
    }
    Ok(())
}

fn validate_remote_temp_path(path: &str) -> Result<(), String> {
    if !path.starts_with("/tmp/nanolink-")
        || path.contains("..")
        || path.contains('\0')
        || path.contains('\n')
        || path.contains('\r')
    {
        return Err("Invalid remote temporary path".to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shell_quote_preserves_single_quotes_without_interpolation() {
        assert_eq!(shell_quote("a'b;$HOME"), "'a'\\''b;$HOME'");
    }

    #[test]
    fn rejects_non_temporary_sftp_destination() {
        assert!(validate_remote_temp_path("/etc/passwd").is_err());
        assert!(validate_remote_temp_path("/tmp/nanolink-ok.jar").is_ok());
    }
}
