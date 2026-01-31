# Runbook: OZ Multisig Wallet

## Preflight checklist

- [ ] Confirm `NETWORK`, `RPC`, `ACCOUNT`, `ACCOUNTS_FILE` are set and correct.
- [ ] Verify signer addresses are correct and funded.
- [ ] Confirm the expected quorum (e.g., 2-of-2).
- [ ] Confirm you are on the intended chain (devnet/sepolia/mainnet).

## Stop and verify (before each critical step)

- [ ] Re-check the **target address** and function selector.
- [ ] Re-check **calldata** and **salt**.
- [ ] Ensure the current signer is authorized for the multisig.

## Recovery steps

- If a submit or confirm fails:
  - [ ] Verify signer is in the multisig signer set.
  - [ ] Verify the transaction ID matches the call + salt.
- If execute fails:
  - [ ] Check the transaction state (`Pending`, `Confirmed`, `Executed`).
  - [ ] Ensure quorum is reached.
  - [ ] Ensure the target call is valid and does not revert.

## Signer rotation (high-level)

1. Submit a multisig transaction to add or remove signers.
2. Confirm with quorum.
3. Execute the signer update.
4. Verify the signer list and quorum values on-chain.
