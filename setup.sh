#!/bin/bash
set -euo pipefail

# Setup script for Tailscale VPN, Tinybird CLI, S2 CLI, DuckDB, and Doppler

show_help() {
    cat << EOF
Sprite Setup - Install and configure development tools

Usage:
  TAILSCALE_AUTHKEY=tskey-xxx ./setup.sh

Environment Variables:
  TAILSCALE_AUTHKEY  (required)  Tailscale auth key for non-interactive login
                                 Generate at: https://login.tailscale.com/admin/settings/keys

Installs:
  - Tailscale    VPN client (authenticated via auth key)
  - Tinybird     CLI for data analytics
  - S2           CLI
  - DuckDB       In-process SQL database
  - Doppler      Secrets and environment variable management

Post-install:
  Run 'tb login' to authenticate with Tinybird (requires browser)
  Run 'doppler login' to authenticate with Doppler (requires browser)

Options:
  -h, --help     Show this help message
EOF
}

# Handle --help flag
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

echo "=== Sprite Setup ==="
echo ""

# Check for required environment variable
if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
    echo "Error: TAILSCALE_AUTHKEY environment variable is not set"
    echo ""
    echo "Usage:"
    echo "  TAILSCALE_AUTHKEY=tskey-xxx ./setup.sh"
    exit 1
fi

# Install Tailscale
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Authenticate Tailscale
echo ""
echo "Authenticating Tailscale..."
sudo tailscale up --authkey="$TAILSCALE_AUTHKEY"

# Verify Tailscale connection
echo ""
echo "Verifying Tailscale connection..."
tailscale status

# Install Tinybird CLI
echo ""
echo "Installing Tinybird CLI..."
curl -fsSL https://tinybird.co | sh

# Verify Tinybird CLI installation
echo ""
echo "Verifying Tinybird CLI..."
tb --version

# Install S2 CLI
echo ""
echo "Installing S2 CLI..."
curl -fsSL s2.dev/install.sh | bash

# Verify S2 CLI installation
echo ""
echo "Verifying S2 CLI..."
s2 --version

# Install DuckDB
echo ""
echo "Installing DuckDB..."
curl -fsSL https://install.duckdb.org | sh

# Verify DuckDB installation
echo ""
echo "Verifying DuckDB..."
duckdb --version

# Install Doppler CLI
echo ""
echo "Installing Doppler CLI..."
curl -fsSL https://cli.doppler.com/install.sh | sudo sh

# Verify Doppler installation
echo ""
echo "Verifying Doppler..."
doppler --version

# Print next steps
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run 'doppler login' to authenticate with Doppler (requires browser)"
echo "  2. Run 'tb login' to authenticate with Tinybird (requires browser)"
echo ""
