# NanoLink Scripts

Utility scripts for NanoLink project management.

## Version Bump Script

One-click version update for all project files.

### Usage

**Linux/macOS:**
```bash
cd scripts
chmod +x bump-version.sh
./bump-version.sh 0.2.0
```

**Windows (PowerShell):**
```powershell
cd scripts
.\bump-version.ps1 0.2.0
```

### What it updates

The script automatically updates version numbers in:

| Component | File |
|-----------|------|
| Agent | `agent/Cargo.toml`, `agent/src/main.rs` |
| Java SDK | `sdk/java/pom.xml` |
| Go SDK | `sdk/go/nanolink/version.go` |
| Python SDK | `sdk/python/pyproject.toml`, `sdk/python/nanolink/__init__.py` |
| Dashboard | `dashboard/package.json` |
| Server App | `apps/server/cmd/main.go`, `apps/server/web/package.json` |
| Desktop App | `apps/desktop/package.json`, `apps/desktop/src-tauri/Cargo.toml`, `apps/desktop/src-tauri/tauri.conf.json` |
| Demo | `demo/spring-boot/pom.xml` |

### Version Format

Uses [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
```

Examples:
- `1.0.0` - Stable release
- `1.0.0-alpha.1` - Alpha release
- `1.0.0-beta.2` - Beta release
- `1.0.0-rc.1` - Release candidate

### Configuration

Version tracking is stored in `version.json`:

```json
{
  "version": "0.1.0",
  "files": [...]
}
```

### Workflow

1. Run the bump script with new version
2. Review changes: `git diff`
3. Commit: `git commit -am "chore: bump version to x.x.x"`
4. Tag: `git tag vx.x.x`
5. Push: `git push && git push --tags`
6. GitHub Actions will automatically build and release

## Other Scripts

| Script | Description |
|--------|-------------|
| `bump-version.sh` | Version bump (Linux/macOS) |
| `bump-version.ps1` | Version bump (Windows) |
| `version.json` | Version configuration |
