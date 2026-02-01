#!/bin/bash
set -euo pipefail

# Setup script for Tailscale VPN, Tinybird CLI, S2 CLI, DuckDB, and Doppler
# Two-phase setup: Doppler first (for secrets), then remaining tools

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat << EOF
Sprite Setup - Install and configure development tools

Usage:
  ./setup.sh [phase1|phase2]

Phases:
  phase1    Install Doppler/GitHub CLI and authenticate
  phase2    Install remaining tools (Tailscale, Tinybird, S2, DuckDB)
            Requires: doppler setup and .env generation first

Workflow:
  1. ./setup.sh phase1
  2. doppler setup
  3. doppler secrets substitute .env.example > .env
  4. ./setup.sh phase2

Environment Variables (loaded from .env if present):
  GH_TOKEN           GitHub Personal Access Token (optional, for non-interactive login)
                     If not set, will use web-based authentication

  TAILSCALE_AUTHKEY  Tailscale auth key for non-interactive login (required for phase2)

  TINYBIRD_HOST      Tinybird API host (optional, for non-interactive auth)
  TINYBIRD_TOKEN     Tinybird admin token (optional, for non-interactive auth)

Installs:
  Phase 1:
    - Doppler      Secrets and environment variable management
    - GitHub CLI   Authenticated via PAT or web login

  Phase 2:
    - Tailscale    VPN client (authenticated via auth key)
    - Tinybird     CLI for data analytics
    - S2           CLI
    - DuckDB       In-process SQL database
    - Docker       Container runtime (includes Docker Compose)

Options:
  -h, --help     Show this help message
EOF
}

phase1_doppler() {
    echo "=== Phase 1: Doppler Setup ==="
    echo ""

    # Source .env if it exists (for GH_TOKEN, etc.)
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        echo "Loading .env file..."
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
        echo ""
    fi

    # Check if Doppler is already installed
    if command -v doppler &> /dev/null; then
        echo "Doppler CLI already installed:"
        doppler --version
    else
        echo "Installing Doppler CLI..."
        curl -fsSL https://cli.doppler.com/install.sh | sudo sh
        echo ""
        echo "Verifying Doppler..."
        doppler --version
    fi

    # Check if GitHub CLI is already installed
    echo ""
    if command -v gh &> /dev/null; then
        echo "GitHub CLI already installed:"
        gh --version
    else
        echo "Installing GitHub CLI..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh -y
        echo ""
        echo "Verifying GitHub CLI..."
        gh --version
    fi

    # Check if GitHub CLI is already authenticated
    echo ""
    if gh auth status &> /dev/null; then
        echo "GitHub CLI already authenticated:"
        gh auth status
    else
        echo "Authenticating GitHub CLI..."
        if [[ -n "${GH_TOKEN:-}" ]]; then
            echo "Using provided GH_TOKEN for authentication..."
            echo "$GH_TOKEN" | gh auth login --with-token
        else
            echo "No GH_TOKEN provided, using web authentication..."
            gh auth login --web --git-protocol https
        fi
        echo ""
        echo "Verifying GitHub authentication..."
        gh auth status
    fi

    # Check if Doppler is already authenticated
    echo ""
    if doppler me &> /dev/null; then
        echo "Doppler already authenticated:"
        doppler me
    else
        echo "Authenticating Doppler..."
        doppler login
    fi

    echo ""
    echo "=== Phase 1 Complete ==="
    echo ""
    echo "Next steps:"
    echo "  1. Run 'doppler setup' to configure project/config"
    echo "  2. Run 'doppler secrets substitute .env.example > .env' to generate .env"
    echo "  3. Run './setup.sh phase2' to install remaining tools"
    echo ""
}

phase2_tools() {
    echo "=== Phase 2: Tools Setup ==="
    echo ""

    # Check if .env exists and source it
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        echo "Loading .env file..."
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    else
        echo "Error: .env file not found"
        echo ""
        echo "Run these commands first:"
        echo "  1. doppler setup"
        echo "  2. doppler secrets substitute .env.example > .env"
        exit 1
    fi

    # Check for required environment variable
    if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
        echo "Error: TAILSCALE_AUTHKEY not found in .env"
        echo ""
        echo "Make sure TAILSCALE_AUTHKEY is set in Doppler and regenerate .env:"
        echo "  doppler secrets substitute .env.example > .env"
        exit 1
    fi

    # Install Tailscale
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh

    # Start tailscaled daemon if not running (no systemd on Fly.io)
    echo ""
    if ! pgrep -x tailscaled > /dev/null; then
        echo "Starting tailscaled daemon..."
        sudo tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
        sleep 5  # Give daemon time to start
    else
        echo "tailscaled already running"
    fi

    # Prompt for Tailscale hostname
    echo ""
    read -rp "Enter hostname for this Tailscale machine: " TAILSCALE_HOSTNAME
    if [[ -z "$TAILSCALE_HOSTNAME" ]]; then
        echo "Error: hostname cannot be empty"
        exit 1
    fi

    # Authenticate Tailscale
    echo ""
    echo "Authenticating Tailscale..."
    sudo tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="$TAILSCALE_HOSTNAME"

    # Verify Tailscale connection
    echo ""
    echo "Verifying Tailscale connection..."
    tailscale status

    # Install Tinybird CLI
    echo ""
    echo "Installing Tinybird CLI..."
    curl -fsSL https://tinybird.co | sh

    # Add ~/.local/bin to PATH (where Tinybird installs)
    export PATH="$HOME/.local/bin:$PATH"

    # Verify Tinybird CLI installation
    echo ""
    echo "Verifying Tinybird CLI..."
    tb --version

    # Verify Tinybird authentication if credentials provided
    if [[ -n "${TINYBIRD_TOKEN:-}" && -n "${TINYBIRD_HOST:-}" ]]; then
        echo ""
        echo "Verifying Tinybird authentication..."
        tb --cloud --host "$TINYBIRD_HOST" --token "$TINYBIRD_TOKEN" auth info
        echo "Tinybird credentials configured via environment variables"
    fi

    # Install S2 CLI
    echo ""
    echo "Installing S2 CLI..."
    curl -fsSL https://s2.dev/install.sh | bash

    # Add ~/.s2/bin to PATH (where S2 installs)
    export PATH="$HOME/.s2/bin:$PATH"

    # Verify S2 CLI installation
    echo ""
    echo "Verifying S2 CLI..."
    s2 --version

    # Install DuckDB
    echo ""
    echo "Installing DuckDB..."
    curl -fsSL https://install.duckdb.org | sh

    # Add ~/.duckdb/cli/latest to PATH (where DuckDB installs)
    export PATH="$HOME/.duckdb/cli/latest:$PATH"

    # Verify DuckDB installation
    echo ""
    echo "Verifying DuckDB..."
    duckdb --version

    # Install Docker and Docker Compose
    echo ""
    if command -v docker &> /dev/null; then
        echo "Docker already installed:"
        docker --version
    else
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com | sh

        # Add current user to docker group to run without sudo
        sudo usermod -aG docker "$USER"
        echo "Added $USER to docker group (may need to log out/in for effect)"
    fi

    # Verify Docker installation
    echo ""
    echo "Verifying Docker..."
    docker --version

    # Verify Docker Compose (included as plugin in modern Docker)
    echo ""
    echo "Verifying Docker Compose..."
    docker compose version

    echo ""
    echo "=== Phase 2 Complete ==="
    echo ""
    echo "Add these to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"\$HOME/.local/bin:\$HOME/.s2/bin:\$HOME/.duckdb/cli/latest:\$PATH\""
    echo ""
    if [[ -z "${TINYBIRD_TOKEN:-}" ]]; then
        echo "Then run 'tb login' to authenticate with Tinybird"
        echo ""
    fi
}

# Handle --help flag
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

# Determine which phase to run
case "${1:-phase1}" in
    phase1)
        phase1_doppler
        ;;
    phase2)
        phase2_tools
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
