#!/usr/bin/env bash
# Example environment configuration for the scripts in this repo.
# Copy to `.env` and `source` it, or export variables in your shell.

# Network: devnet | sepolia | mainnet
export NETWORK=devnet

# RPC endpoint (required)
export RPC=http://127.0.0.1:5050/rpc

# sncast account name and accounts file used for declare/deploy steps
export ACCOUNT=deployer
export ACCOUNTS_FILE="$HOME/.starknet_accounts/devnet_oz_accounts.json"

# Output directory for artifacts (leave empty to default to artifacts/$NETWORK)
export OUT_DIR=""

# Multisig deploy inputs
# Use --label to name the instance (used in artifact filenames).
export SIGNERS="0xabc,0xdef"
export QUORUM=2

# Rehearsal signers (account names) - must match the signer addresses above
export SIGNER_A=signer_a
export SIGNER_B=signer_b

# Optional label used by deploy/rehearsal scripts
export MULTISIG_LABEL=primary
