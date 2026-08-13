# NanoOps Project Console

All operator-facing project commands are consolidated behind one multifunction
entry point. Internal implementations live in `scripts/tasks/` and normally do
not need to be called directly.

## Interactive mode

Windows users can double-click `scripts\nanoops.bat`, or run:

```powershell
.\scripts\nanoops.bat
```

Linux/macOS users can run:

```bash
./scripts/nanoops.sh
```

The menu provides:

1. Start development environment
2. Stop development environment
3. Deploy Server to production
4. Validate deployment without remote changes
5. Bump the project version
6. Install Git hooks
7. Scan and remove UTF-8 BOM

Production deployment requires typing `DEPLOY` before any upload or rollout.

## Direct commands

Interactive mode is optional. The same entry point supports automation:

| Task | Windows | Linux/macOS |
|---|---|---|
| Start development | `.\scripts\nanoops.bat start` | `./scripts/nanoops.sh start` |
| Stop development | `.\scripts\nanoops.bat stop` | `./scripts/nanoops.sh stop` |
| Deployment DryRun | `.\scripts\nanoops.bat deploy-dry-run -SkipChecks` | `./scripts/nanoops.sh deploy-dry-run --skip-checks` |
| Production deploy | `.\scripts\nanoops.bat deploy` | `./scripts/nanoops.sh deploy` |
| Bump version | `.\scripts\nanoops.bat version -Version 0.5.0` | `./scripts/nanoops.sh version 0.5.0` |
| Install hooks | `.\scripts\nanoops.bat install-hooks` | `./scripts/nanoops.sh install-hooks` |
| Remove BOM | `.\scripts\nanoops.bat remove-bom` | `./scripts/nanoops.sh remove-bom` |

Deployment options:

- Windows: `-AllowDirty`, `-SkipChecks`, `-DryRun`, `-ConfigPath path`
- Linux/macOS: `--allow-dirty`, `--skip-checks`, `--dry-run`, `--config path`

`DEPLOY_HOST_HTTP_PORT` controls the host port used by post-rollout checks and
defaults to `8080`. `DEPLOY_LOCAL_HEALTH_URL` may override the derived endpoint,
but is restricted to `http://127.0.0.1:PORT/api/health` and must use the same
validated port.

For intentional non-interactive production automation, Windows supports
`-Yes` and Linux/macOS supports `--yes`. Avoid these flags for normal manual
deployments so the production confirmation remains active.

Copy `.env.deploy.example` to the ignored local `.env.deploy` file before the
first deployment. SSH authentication uses the normal OpenSSH key/agent lookup;
no SSH password or private key is stored in this configuration.

## Layout

```text
scripts/
├── nanoops.bat       Windows double-click entry
├── nanoops.ps1       Windows interactive console
├── nanoops.sh        Linux/macOS interactive console
├── tasks/            Internal task implementations
├── hooks/            Git hook templates
└── version.json      Version update configuration
```
