# Deeclaud

**Contain the beast!** Run Claude Code in a sandboxed GNU/Linux container on Apple Silicon.

Deeclaud uses [Apple's container tool](https://github.com/apple/container) to run Claude Code in an isolated environment. Your projects stay safe while Claude gets the freedom to install packages, run builds, and execute code.

## Why?

Claude Code's `--dangerously-skip-permissions` flag is powerful but risky on your main system. Deeclaud provides:

- **Isolation**: Claude runs in a GNU/Linux VM, can't touch your macOS files
- **Git worktrees**: Each branch gets its own workspace, main repo stays clean
- **Persistent home**: Claude's installed tools survive container restarts
- **OAuth via Keychain**: Secure token storage, never written to disk

## Prerequisites

- Apple Silicon Mac (M1/M2/M3/M4)
- [Apple container tool](https://github.com/apple/container/releases) (v0.7.1+)
- Claude Code OAuth token (from your Claude subscription)
- `git` command-line tool
- `python3` (optional, for `./manage-container.sh check` metadata display)

## Quick Start

### 1. Install Apple container

```bash
# Download container-installer-signed.pkg from:
# https://github.com/apple/container/releases

# After installing:
container system start
```

### 2. Store your OAuth token

```bash
security add-generic-password \
  -s "claude-code-container" \
  -a "oauth-token" \
  -w "YOUR_OAUTH_TOKEN_HERE"
```

### 3. Build the container image

```bash
./manage-container.sh setup
```

### 4. Run Claude Code on a project

```bash
./deeclaud.sh /path/to/your/repo branch-name
```

That's it! Claude Code launches in an isolated container with full permissions.

**Important**: Deeclaud uses **git worktrees** to create an isolated copy of your branch. Your original repository remains untouched on the host—you can continue editing it with your favorite tools while Claude works in the container. Changes Claude makes appear in the worktree directory (`<repo>-wt-<branch>`), which you can review, commit, or discard from your host machine.

## Usage

```bash
# Basic usage
./deeclaud.sh <repo-dir> <branch> [variant]

# Examples
./deeclaud.sh ~/Projects/my-app main
./deeclaud.sh ~/Projects/my-app feature/new-feature
./deeclaud.sh ~/Projects/my-app main Dockerfile.claude-dev
```

## Variant Dockerfiles

The default `Dockerfile.claude-dev` provides a general-purpose environment. You can create custom variants for specific needs by copying and modifying the default Dockerfile.

**Included:**

| Variant | Use Case |
|---------|----------|
| `Dockerfile.claude-dev` | Default: Ubuntu 22.04, Node.js, Git, common tools |

**Example variants you might create:**

| Variant | Use Case |
|---------|----------|
| `Dockerfile.node-alpine` | Minimal Node.js environment |
| `Dockerfile.rustup-ubuntu` | Rust development |
| `Dockerfile.headless-chromium` | Browser automation, E2E testing |

See [GUIDE.md](GUIDE.md#creating-custom-variants) for instructions on creating custom variants.

## Management Commands

```bash
# Build/rebuild the container image
./manage-container.sh setup [Dockerfile.variant]

# Rebuild without cache (for Claude Code updates)
./manage-container.sh --debug setup

# Check image status and metadata
./manage-container.sh check

# Remove image and containers
./manage-container.sh teardown

# Show help
./manage-container.sh --help
./deeclaud.sh --help
```

## Configuration

Set these environment variables to customize behavior:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEECLAUD_MEMORY` | `4G` | Container memory limit (e.g., `8G`, `2G`) |

Example:
```bash
DEECLAUD_MEMORY=8G ./deeclaud.sh ~/Projects/big-app main
```

## How It Works

1. **Git worktree**: Creates an isolated checkout at `<repo>-wt-<branch>` next to your original repo. If the branch doesn't exist, it's created automatically.
2. **Container launch**: Starts a GNU/Linux VM with Claude Code pre-installed
3. **Persistent home**: `~/Containers/<variant>-<repo>-home` survives container restarts
4. **OAuth injection**: Token passed via environment variable, not filesystem

### Container Environment Variables

Inside the container, these environment variables are set:

| Variable | Value | Description |
|----------|-------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Your token | Authentication for Claude Code |
| `HOME` | `/home/claude` | Container user's home directory |
| `PATH` | Includes `/opt/claude/bin` | Claude binaries available globally |

### What Gets Mounted

| Host Path | Container Path | Access |
|-----------|----------------|--------|
| `<repo>-wt-<branch>/` | `/workspace` | read-write |
| `~/Containers/<variant>-<repo>-home/` | `/home/claude` | read-write |
| `~/.ssh/` | `/home/claude/.ssh` | read-only |
| `~/.config/gh/` | `/home/claude/.config/gh` | read-only |

Your original repository is **never mounted**—only the worktree. This means you can safely continue working in your main repo on the host while Claude operates in the container.

See [GUIDE.md](GUIDE.md) for detailed architecture and troubleshooting.

## Security Notes

- Claude has `sudo` access *inside* the container (for apt-get, npm global installs, etc.)
- The container cannot access your macOS filesystem (except mounted volumes)
- SSH keys and GitHub credentials are mounted read-only
- OAuth token exists only in memory/environment, never on disk

**Token visibility**: The OAuth token is passed as an environment variable (`CLAUDE_CODE_OAUTH_TOKEN`), which means it's visible to all processes running inside the container via the `env` command or `/proc/*/environ`. This is a tradeoff for simplicity—the token never touches the filesystem, but any code running in the container can read it. Since the container is isolated and disposable, this is generally acceptable for development use.

## License

MIT License - see [LICENSE](LICENSE)

---

*The name "Deeclaud" is a playful reference. We want to be clear that we don't support the practice of declawing cats or other animals.*
