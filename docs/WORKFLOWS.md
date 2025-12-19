# NanoLink GitHub Workflows 使用指南

[English](#english) | [中文](#中文)

---

## 中文

### 概述

NanoLink 项目包含三个 GitHub Actions 工作流：

| 工作流 | 文件 | 触发条件 | 用途 |
|--------|------|----------|------|
| Test | `test.yml` | PR/Push到main | 运行测试 |
| Release Agent | `release.yml` | Tag推送/手动触发 | 发布Agent二进制 |
| SDK Release | `sdk-release.yml` | VERSION文件变更/手动触发 | 发布SDK包 |

### 版本管理

项目使用根目录下的 `VERSION` 文件作为版本的唯一来源：

```
0.1.0
```

### 发布SDK (Java/Go)

#### 方式一：修改VERSION文件（推荐）

1. 修改 `VERSION` 文件中的版本号：
   ```bash
   echo "0.2.0" > VERSION
   ```

2. 提交并推送：
   ```bash
   git add VERSION
   git commit -m "chore: bump version to 0.2.0"
   git push origin main
   ```

3. 工作流会自动：
   - 读取VERSION文件中的版本号
   - 构建Java SDK (Maven)
   - 构建Go SDK
   - 生成Protocol Buffers文件
   - 创建GitHub Release并上传所有产物

#### 方式二：手动触发

1. 访问 GitHub 仓库的 **Actions** 页面
2. 选择 **SDK Release** 工作流
3. 点击 **Run workflow**
4. 可选：输入版本号（留空则使用VERSION文件中的版本）
5. 点击 **Run workflow** 按钮

### 发布Agent

#### 方式一：创建Tag（推荐）

```bash
# 创建并推送tag
git tag v0.2.0
git push origin v0.2.0
```

工作流会自动：
- 构建多平台Agent二进制文件：
  - Linux x86_64
  - Linux ARM64
  - macOS x86_64
  - macOS ARM64 (Apple Silicon)
  - Windows x86_64
- 构建Dashboard静态文件
- 创建GitHub Release

#### 方式二：手动触发

1. 访问 **Actions** → **Release Agent**
2. 点击 **Run workflow**
3. 输入版本号（例如：`0.2.0`）
4. 点击运行

### 工作流详情

#### Test 工作流 (`test.yml`)

```yaml
触发条件:
  - Pull Request 到 main 分支
  - Push 到 main 分支

执行内容:
  1. Rust Agent 测试
     - cargo fmt --check (格式检查)
     - cargo clippy (代码检查)
     - cargo test (单元测试)

  2. Java SDK 测试
     - mvn test

  3. Go SDK 测试
     - go test ./...

  4. Dashboard 构建测试
     - npm ci
     - npm run build
```

#### SDK Release 工作流 (`sdk-release.yml`)

```yaml
触发条件:
  - VERSION 文件变更 (push 到 main)
  - 手动触发 (workflow_dispatch)

执行内容:
  1. 准备阶段
     - 读取版本号
     - 检查tag是否已存在

  2. 构建 Java SDK
     - 更新 pom.xml 版本
     - mvn clean package
     - 生成 sources jar

  3. 构建 Go SDK
     - 更新版本常量
     - go build & test
     - 打包源码

  4. 构建 Protocol Buffers
     - 生成 Go proto 代码
     - 打包 proto 文件

  5. 创建 Release
     - 上传所有产物
     - 生成 SHA256 校验和
```

#### Release Agent 工作流 (`release.yml`)

```yaml
触发条件:
  - Tag 推送 (v*)
  - 手动触发 (workflow_dispatch)

执行内容:
  1. 准备阶段
     - 解析版本号

  2. 构建 Agent (并行)
     - Linux x86_64
     - Linux ARM64 (使用交叉编译)
     - macOS x86_64
     - macOS ARM64
     - Windows x86_64

  3. 构建 Dashboard
     - npm ci
     - npm run build
     - 打包为 tar.gz

  4. 创建 Release
     - 上传所有二进制文件
     - 上传 Dashboard 包
     - 生成安装说明
```

### 产物说明

#### SDK Release 产物

| 文件 | 说明 |
|------|------|
| `nanolink-sdk-{version}.jar` | Java SDK JAR包 |
| `nanolink-sdk-{version}-sources.jar` | Java 源码包 |
| `nanolink-go-sdk-{version}.tar.gz` | Go SDK 源码包 |
| `nanolink_sdk-{version}.tar.gz` | Python SDK 源码包 |
| `nanolink_sdk-{version}-py3-none-any.whl` | Python SDK Wheel包 |
| `nanolink-proto-{version}.tar.gz` | Protocol Buffers 定义文件 |
| `SHA256SUMS.txt` | 校验和文件 |

#### Agent Release 产物

| 文件 | 平台 |
|------|------|
| `nanolink-agent-linux-x86_64` | Linux x86_64 |
| `nanolink-agent-linux-aarch64` | Linux ARM64 |
| `nanolink-agent-macos-x86_64` | macOS Intel |
| `nanolink-agent-macos-aarch64` | macOS Apple Silicon |
| `nanolink-agent-windows-x86_64.exe` | Windows x64 |
| `nanolink-dashboard-{version}.tar.gz` | Dashboard 静态文件 |

### 版本号规范

建议使用语义化版本 (Semantic Versioning)：

- `MAJOR.MINOR.PATCH` (例如: `1.2.3`)
- `MAJOR.MINOR.PATCH-SUFFIX` (例如: `1.0.0-beta`, `2.0.0-rc1`)

预发布版本（包含 `alpha`、`beta`、`rc`）会自动标记为 **Pre-release**。

### 常见问题

**Q: 如何同时发布Agent和SDK？**

A: 先更新VERSION文件并推送，等SDK Release完成后，再创建对应的tag触发Agent Release。

**Q: 构建失败怎么办？**

A: 查看Actions页面的构建日志，常见问题：
- Rust编译错误：检查cargo.toml依赖
- Java构建失败：检查pom.xml配置
- Go构建失败：检查go.mod依赖

**Q: 如何取消正在运行的工作流？**

A: 在Actions页面找到对应的运行，点击 **Cancel workflow**。

---

## English

### Overview

NanoLink project includes three GitHub Actions workflows:

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| Test | `test.yml` | PR/Push to main | Run tests |
| Release Agent | `release.yml` | Tag push/Manual | Release Agent binaries |
| SDK Release | `sdk-release.yml` | VERSION change/Manual | Release SDK packages |

### Version Management

The project uses the `VERSION` file in the root directory as the single source of truth:

```
0.1.0
```

### Releasing SDK (Java/Go)

#### Method 1: Modify VERSION file (Recommended)

1. Update the version in `VERSION` file:
   ```bash
   echo "0.2.0" > VERSION
   ```

2. Commit and push:
   ```bash
   git add VERSION
   git commit -m "chore: bump version to 0.2.0"
   git push origin main
   ```

3. The workflow will automatically:
   - Read version from VERSION file
   - Build Java SDK (Maven)
   - Build Go SDK
   - Generate Protocol Buffers files
   - Create GitHub Release with all artifacts

#### Method 2: Manual Trigger

1. Go to **Actions** page on GitHub
2. Select **SDK Release** workflow
3. Click **Run workflow**
4. Optional: Enter version number (leave empty to use VERSION file)
5. Click **Run workflow** button

### Releasing Agent

#### Method 1: Create Tag (Recommended)

```bash
# Create and push tag
git tag v0.2.0
git push origin v0.2.0
```

The workflow will automatically:
- Build multi-platform Agent binaries:
  - Linux x86_64
  - Linux ARM64
  - macOS x86_64
  - macOS ARM64 (Apple Silicon)
  - Windows x86_64
- Build Dashboard static files
- Create GitHub Release

#### Method 2: Manual Trigger

1. Go to **Actions** → **Release Agent**
2. Click **Run workflow**
3. Enter version number (e.g., `0.2.0`)
4. Click run

### Workflow Details

#### Test Workflow (`test.yml`)

```yaml
Triggers:
  - Pull Request to main branch
  - Push to main branch

Steps:
  1. Rust Agent tests
     - cargo fmt --check (format check)
     - cargo clippy (lint)
     - cargo test (unit tests)

  2. Java SDK tests
     - mvn test

  3. Go SDK tests
     - go test ./...

  4. Dashboard build test
     - npm ci
     - npm run build
```

#### SDK Release Workflow (`sdk-release.yml`)

```yaml
Triggers:
  - VERSION file changes (push to main)
  - Manual trigger (workflow_dispatch)

Steps:
  1. Prepare
     - Read version number
     - Check if tag exists

  2. Build Java SDK
     - Update pom.xml version
     - mvn clean package
     - Generate sources jar

  3. Build Go SDK
     - Update version constant
     - go build & test
     - Package source code

  4. Build Protocol Buffers
     - Generate Go proto code
     - Package proto files

  5. Create Release
     - Upload all artifacts
     - Generate SHA256 checksums
```

#### Release Agent Workflow (`release.yml`)

```yaml
Triggers:
  - Tag push (v*)
  - Manual trigger (workflow_dispatch)

Steps:
  1. Prepare
     - Parse version number

  2. Build Agent (parallel)
     - Linux x86_64
     - Linux ARM64 (cross-compile)
     - macOS x86_64
     - macOS ARM64
     - Windows x86_64

  3. Build Dashboard
     - npm ci
     - npm run build
     - Package as tar.gz

  4. Create Release
     - Upload all binaries
     - Upload Dashboard package
     - Generate install instructions
```

### Artifacts

#### SDK Release Artifacts

| File | Description |
|------|-------------|
| `nanolink-sdk-{version}.jar` | Java SDK JAR |
| `nanolink-sdk-{version}-sources.jar` | Java source JAR |
| `nanolink-go-sdk-{version}.tar.gz` | Go SDK source archive |
| `nanolink_sdk-{version}.tar.gz` | Python SDK source archive |
| `nanolink_sdk-{version}-py3-none-any.whl` | Python SDK wheel |
| `nanolink-proto-{version}.tar.gz` | Protocol Buffers definitions |
| `SHA256SUMS.txt` | Checksums file |

#### Agent Release Artifacts

| File | Platform |
|------|----------|
| `nanolink-agent-linux-x86_64` | Linux x86_64 |
| `nanolink-agent-linux-aarch64` | Linux ARM64 |
| `nanolink-agent-macos-x86_64` | macOS Intel |
| `nanolink-agent-macos-aarch64` | macOS Apple Silicon |
| `nanolink-agent-windows-x86_64.exe` | Windows x64 |
| `nanolink-dashboard-{version}.tar.gz` | Dashboard static files |

### Version Naming Convention

Use Semantic Versioning:

- `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)
- `MAJOR.MINOR.PATCH-SUFFIX` (e.g., `1.0.0-beta`, `2.0.0-rc1`)

Pre-release versions (containing `alpha`, `beta`, `rc`) are automatically marked as **Pre-release**.

### FAQ

**Q: How to release both Agent and SDK?**

A: First update VERSION file and push. After SDK Release completes, create corresponding tag to trigger Agent Release.

**Q: What if build fails?**

A: Check build logs on Actions page. Common issues:
- Rust compile error: Check cargo.toml dependencies
- Java build failure: Check pom.xml configuration
- Go build failure: Check go.mod dependencies

**Q: How to cancel a running workflow?**

A: Find the run on Actions page, click **Cancel workflow**.
