# Deeclaud Setup Guide

This guide walks through setting up Apple's container tool and using Deeclaud to run Claude Code in a sandboxed GNU/Linux environment.

## Table of Contents

- [Installing Apple Container](#installing-apple-container)
- [Architecture Overview](#architecture-overview)
- [OAuth Token Setup](#oauth-token-setup)
- [Building the Container Image](#building-the-container-image)
- [Running Claude Code](#running-claude-code)
  - [Managing Worktrees](#managing-worktrees)
- [Creating Custom Variants](#creating-custom-variants)
- [Troubleshooting](#troubleshooting)

---

## Installing Apple Container

Apple's container tool provides lightweight GNU/Linux VMs on Apple Silicon. It's similar to Docker but native to macOS.

### Download and Install

1. Download `container-installer-signed.pkg` from [Apple container releases](https://github.com/apple/container/releases)
2. Run the installer
3. Verify installation:

```bash
which container
# /usr/local/bin/container
```

### Start the Service

```bash
container system start
```

On first run, it will prompt to install a kernel:

```
Verifying apiserver is running...
No default kernel configured.
Install the recommended default kernel? [Y/n]:
```

Answer **Y** to install the default kernel.

### Verify Status

```bash
container system status
```

You should see:

```
apiserver is running
application data root: ~/Library/Application Support/com.apple.container/
container-apiserver version: container-apiserver version 0.7.1
```

### Optional: DNS Setup

For friendly container hostnames (e.g., `my-container.test`):

```bash
sudo container system dns create test
container system property set dns.domain test
```

---

## Architecture Overview

### How Deeclaud Works

```
┌─────────────────────────────────────────────────────────────┐
│                        macOS Host                           │
│  ┌──────────────┐    ┌──────────────────────────────────┐   │
│  │  Your Repo   │    │     ~/Containers/                │   │
│  │  (original)  │    │     claude-dev-myrepo-home/      │   │
│  └──────┬───────┘    │     (persistent home)            │   │
│         │            └──────────────┬───────────────────┘   │
│         │ git worktree              │                       │
│         ▼                           │                       │
│  ┌──────────────┐                   │                       │
│  │  Worktree    │                   │                       │
│  │  myrepo-wt-  │                   │                       │
│  │  branch      │                   │                       │
│  └──────┬───────┘                   │                       │
└─────────┼───────────────────────────┼───────────────────────┘
          │ mount as /workspace       │ mount as /home/claude
          ▼                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    GNU/Linux Container (VM)                 │
│  ┌──────────────┐    ┌──────────────────────────────────┐   │
│  │  /workspace  │    │  /home/claude                    │   │
│  │  (your code) │    │  - .claude/                      │   │
│  │              │    │  - .local/ (installed tools)     │   │
│  └──────────────┘    │  - .config/gh/ (read-only)       │   │
│                      │  - .ssh/ (read-only)             │   │
│                      └──────────────────────────────────┘   │
│                                                             │
│  Claude Code runs here with --dangerously-skip-permissions  │
│  Has sudo access for apt-get, etc.                          │
└─────────────────────────────────────────────────────────────┘
```

### Key Concepts

**Git Worktrees**: Each branch gets an isolated checkout. Your main repo stays untouched.

**Persistent Home**: Claude's home directory (`/home/claude`) persists across container restarts. Installed tools, settings, and Claude's memory survive.

**Home Directory Naming**: `~/Containers/{variant}-{repo}-home`
- Same repo, different branches → share the same home
- Different repos → separate homes
- Different variants → separate homes

**OAuth via Environment**: Your Claude token is passed as an environment variable, never written to disk inside the container.

**Note on token visibility**: The token is visible to all processes inside the container via the `env` command or `/proc/*/environ`. This is a tradeoff for simplicity—since the container is isolated and disposable, this is generally acceptable for development use.

### Container Environment Variables

Inside the container, these environment variables are set:

| Variable | Value | Description |
|----------|-------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Your token | Authentication for Claude Code |
| `HOME` | `/home/claude` | Container user's home directory |
| `PATH` | Includes `/opt/claude/bin` | Claude binaries available globally |

### Configuration

Set these environment variables on the host to customize behavior:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEECLAUD_MEMORY` | `4G` | Container memory limit (e.g., `8G`, `2G`) |

---

## OAuth Token Setup

Deeclaud stores your Claude OAuth token in macOS Keychain for security.

### Get Your OAuth Token

1. Log into [claude.ai](https://claude.ai)
2. Open browser developer tools (F12)
3. Go to Application → Cookies
4. Find the OAuth token (starts with `sk-ant-oat01-`)

### Store in Keychain

```bash
security add-generic-password \
  -s "claude-code-container" \
  -a "oauth-token" \
  -w "sk-ant-oat01-YOUR-TOKEN-HERE"
```

### Update Token

If your token expires, delete the old one first:

```bash
security delete-generic-password \
  -s "claude-code-container" \
  -a "oauth-token"

# Then add the new one
security add-generic-password \
  -s "claude-code-container" \
  -a "oauth-token" \
  -w "sk-ant-oat01-NEW-TOKEN-HERE"
```

### Verify Token
You can verify that the token was saved correctly by running the same script `deeclaud.sh` uses:
```bash
./get-claude-token.sh
# Should output your token (but not when run via deeclaud.sh)
```
You'll want to close or clear that terminal after running this.

---

## Building the Container Image

### First Build

```bash
./manage-container.sh setup
```

This will:
1. Pull the Ubuntu 22.04 base image
2. Install Node.js, Git, and common tools
3. Download and install Claude Code
4. Create a non-root `claude` user with sudo access

First build takes 5-30 minutes depending on network speed.

### Rebuild (with cache)

Use when you've modified the Dockerfile:

```bash
./manage-container.sh setup
```

Docker layer caching makes this fast if only later layers changed.

### Rebuild (without cache)

Use when Claude Code has a new version:

```bash
./manage-container.sh --debug setup
```

This forces a fresh download of the Claude installer.

### Check Image Status

```bash
./manage-container.sh check
```

Shows image metadata including build timestamp.

---

## Running Claude Code

### Basic Usage

```bash
./deeclaud.sh <repo-dir> <branch> [variant]
```

### Examples

```bash
# Work on main branch
./deeclaud.sh ~/Projects/my-app main

# Work on a feature branch (creates it if needed)
./deeclaud.sh ~/Projects/my-app feature/new-api

# Use a custom variant (you need to create and build this first)
./deeclaud.sh ~/Projects/my-app main Dockerfile.my-variant

# Use more memory for large projects
DEECLAUD_MEMORY=8G ./deeclaud.sh ~/Projects/big-app main
```

### Automatic Branch Creation

If you specify a branch that doesn't exist, Deeclaud creates it automatically:

```bash
# This creates the 'feature/new-feature' branch if it doesn't exist
./deeclaud.sh ~/Projects/my-app feature/new-feature
```

The new branch is created from the current HEAD of the repository.

### What Happens

1. Creates git worktree at `~/Projects/my-app-wt-main`
2. Initializes submodules (if any)
3. Retrieves OAuth token from Keychain
4. Launches container with:
   - Worktree mounted at `/workspace`
   - Persistent home at `/home/claude`
   - GitHub config and SSH keys (read-only)
5. Starts Claude Code with `--dangerously-skip-permissions`

### Inside the Container

Claude Code starts automatically. You can:
- Install packages: `sudo apt-get install cmake`
- The `claude` command is available globally
- Exit with `/exit` or Ctrl+D

### Simultaneous Sessions

You can run multiple containers for different repos/branches:

```bash
# Terminal 1
./deeclaud.sh ~/Projects/app-a main

# Terminal 2
./deeclaud.sh ~/Projects/app-b feature/test
```

### Managing Worktrees

Deeclaud creates git worktrees for each branch you work on. These persist after the container exits so you can review changes.

**List all worktrees** for a repository:

```bash
git -C ~/Projects/my-app worktree list
```

Example output:
```
/Users/you/Projects/my-app           abc1234 [main]
/Users/you/Projects/my-app-wt-dev    def5678 [dev]
/Users/you/Projects/my-app-wt-fix    789abcd [feature/fix]
```

**Remove a worktree** when you're done with it:

```bash
git -C ~/Projects/my-app worktree remove ~/Projects/my-app-wt-dev
```

If the worktree has uncommitted changes, git will refuse. Use `--force` to remove anyway:

```bash
git -C ~/Projects/my-app worktree remove --force ~/Projects/my-app-wt-dev
```

**Clean up stale worktrees** (if you manually deleted a worktree directory):

```bash
git -C ~/Projects/my-app worktree prune
```

Using `git worktree remove` is preferred over `rm -rf` because it properly updates git's internal tracking, keeping tools like GitHub Desktop and `gh` in sync.

---

## Creating Custom Variants

Copy the default Dockerfile and customize:

```bash
cp Dockerfile.claude-dev Dockerfile.my-variant
```

### Example: Add Python and Build Tools

```dockerfile
# In your custom Dockerfile, add to the 'base' stage:

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*
```

### Example: Rust Development

```dockerfile
# Add after the node stage:

FROM node AS rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
```

Build your variant:

```bash
./manage-container.sh setup Dockerfile.my-variant
```

Use it:

```bash
./deeclaud.sh ~/Projects/my-rust-app main Dockerfile.my-variant
```

---

## Troubleshooting

### Container Stuck "Dialing"

The container service may get stuck. Reset it:

```bash
container system stop
```

If that hangs, force kill the processes:

```bash
ps ax -o "pid,comm" | grep Virtualization
# Note the PID, then:
kill -9 <pid>

# Kill related services
killall container-apiserver
killall container-runtime-linux
killall container-core-images
killall container-network-vmnet
```

Restart:

```bash
container system start
```

### Build Timeout

If builds timeout or fail:

1. Check network connectivity
2. Try again (transient failures are common)
3. Use `--debug` for verbose output:
   ```bash
   ./manage-container.sh --debug setup
   ```

### "Image not found" Error

Build the image first:

```bash
./manage-container.sh setup
```

### OAuth Token Not Working

1. Verify token is stored:
   ```bash
   ./get-claude-token.sh
   ```

2. Check token hasn't expired (get a fresh one from claude.ai)

3. Re-add to keychain:
   ```bash
   security delete-generic-password -s "claude-code-container" -a "oauth-token"
   security add-generic-password -s "claude-code-container" -a "oauth-token" -w "NEW_TOKEN"
   ```

### Permission Denied on Claude Binary

Rebuild the image:

```bash
./manage-container.sh setup
```

The Dockerfile includes permission fixes for the Claude installation.

### Remove Unused Containers

List all containers:

```bash
container list --all
```

Remove specific container:

```bash
container rm <container-id>
```

### Clean Up Everything

```bash
./manage-container.sh teardown
```

This removes the image and any containers using it.

---

## Container Commands Reference

```bash
# List running containers
container ls

# List all containers (including stopped)
container list --all

# Stop a container
container stop <name-or-id>

# Remove a container
container rm <name-or-id>

# List images
container image list

# Remove an image
container image rm <name>

# Container stats
container stats <name>

# Execute command in running container
container exec <name> <command>

# Interactive shell
container exec -it <name> bash

# Stop the container service
container system stop

# Start the container service
container system start

# Check service status
container system status
```

---

## Further Reading

- [Apple container documentation](https://github.com/apple/container/tree/main/docs)
- [Claude Code documentation](https://code.claude.com/docs/en/overview)
