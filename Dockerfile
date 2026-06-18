# Pi Coding Agent Dockerfile
# Base: Ubuntu 24.04 LTS
FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Increase file descriptor limits
RUN echo "* soft nofile 65536" >> /etc/security/limits.conf && \
    echo "* hard nofile 65536" >> /etc/security/limits.conf && \
    echo "root soft nofile 65536" >> /etc/security/limits.conf && \
    echo "root hard nofile 65536" >> /etc/security/limits.conf && \
    echo "ulimit -n 65536" >> /root/.bashrc && \
    echo "ulimit -n 65536" >> /etc/profile

# Pi agent defaults
ENV PI_OFFLINE=1
ENV COLORTERM=truecolor

# -------------------------------------------------------------------
# System dependencies + core tools
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials and toolchain
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    make \
    unzip \
    xz-utils \
    # Python build dependencies (for uv to compile packages if needed)
    libssl-dev \
    libffi-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses-dev \
    zlib1g-dev \
    tk-dev \
    liblzma-dev \
    # JSON processor (for update cmds)
    jq \
    # Rust build accelerators: sccache (compilation cache), mold (fast linker)
    sccache \
    mold \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Node.js (LTS 22.x via NodeSource)
# -------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Python 3.12
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# -------------------------------------------------------------------
# uv (Python package manager)
# -------------------------------------------------------------------
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# -------------------------------------------------------------------
# ripgrep (rg), fd (fd-find), fzf - fast search tools
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep \
    fd-find \
    fzf \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Rust toolchain (rustup, cargo, rustc, clippy, rustfmt)
# -------------------------------------------------------------------
# Place CARGO_HOME in /tmp so registry/git caches land on persistent volumes
ENV CARGO_HOME=/tmp/cargo
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/tmp/cargo/bin:$PATH"

# --- Rust build accelerators (ephemeral sandbox optimizations) ---
# sccache: wraps rustc to cache compiled .o/.rlib objects locally or in cloud
# storage (S3/GCS). Set SCCACHE_BUCKET to use a cloud bucket instead of local.
ENV RUSTC_WRAPPER=sccache
ENV SCCACHE_DIR=/tmp/sccache

# Disable incremental compilation (adds I/O overhead for zero benefit in
# throwaway sandbox environments).
ENV CARGO_INCREMENTAL=0

# Use mold for near-instant linking (massively parallel, drop-in ld replacement).
ENV RUSTFLAGS="-C link-arg=-fuse-ld=mold"

# --- npm cache in /tmp (persistent volume, survives sandbox teardown) ---
ENV npm_config_cache=/tmp/npm-cache

# -------------------------------------------------------------------
# just - command runner (prebuilt binary, faster than cargo install)
# -------------------------------------------------------------------
RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# -------------------------------------------------------------------
# cargo-binstall — prebuilt binary installer for Rust tools
# -------------------------------------------------------------------
RUN set -e; \
    ARCH=$(uname -m); \
    case "$ARCH" in \
    x86_64) TARGET="x86_64-unknown-linux-gnu" ;; \
    aarch64) TARGET="aarch64-unknown-linux-gnu" ;; \
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-${TARGET}.tgz" \
    | tar xz -C /tmp && \
    install /tmp/cargo-binstall /usr/local/bin/cargo-binstall && \
    rm /tmp/cargo-binstall

# Useful cargo utilities (prebuilt, no compilation)
RUN cargo binstall --no-confirm cargo-watch cargo-edit cargo-nextest

# -------------------------------------------------------------------
# Install pi coding agent globally
# -------------------------------------------------------------------
RUN npm --prefix /usr install -g --ignore-scripts @earendil-works/pi-coding-agent

# -------------------------------------------------------------------
# ctx7 - documentation lookup (used by find-docs skill)
# -------------------------------------------------------------------
RUN npm install -g ctx7@latest

# -------------------------------------------------------------------
# pi-acp - ACP (Agent Client Protocol) adapter for pi
#   Exposes pi as an ACP agent over stdio, allowing editors like Zed
#   to connect to it as an AI agent backend.
# -------------------------------------------------------------------
RUN npm install -g pi-acp@latest

# -------------------------------------------------------------------
# Working directory
# -------------------------------------------------------------------
WORKDIR /workspace

# Default entrypoint - drop into pi interactive mode
ENTRYPOINT ["pi", "--approve"]
