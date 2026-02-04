# Runbook: OZ Multisig Wallet

This runbook is the **execution checklist**. The **lane policy** lives in `opsec-ops-lanes-template/docs/ops-lanes-agent.md`.

## Lane selection (first decision)

- [ ] Choose the lane (Observe / Plan / Deploy / Handoff / Operate / Govern / Emergency).
- [ ] Confirm the **signer account** matches the lane policy.
- [ ] Confirm the **network** and **RPC** match the lane policy.

## Preflight checklist

- [ ] Confirm `NETWORK`, `RPC`, `ACCOUNT`, `ACCOUNTS_FILE` are set and correct.
- [ ] Verify signer addresses are correct and funded.
- [ ] Confirm the expected quorum (e.g., 2-of-2).
- [ ] Confirm you are on the intended chain (devnet/sepolia/mainnet).
- [ ] Confirm the multisig **label** and artifacts path `artifacts/<network>`.

## Intent flow (Plan → Check → Approve → Apply → Postconditions)

1) **Plan**: produce a clear, semantic intent (what should happen).
2) **Check**: verify chain id, signer, target identity, and preconditions.
3) **Approve**: human approves the semantic intent.
4) **Apply**: execute from intent only (no manual args).
5) **Postconditions**: read back state and verify expected result.

## Stop and verify (before each critical step)

- [ ] Re-check **chain id** and RPC endpoint.
- [ ] Re-check **target identity** (class hash / known address).
- [ ] Re-check the **target address** and function selector.
- [ ] Re-check **calldata** and **salt**.
- [ ] Ensure the current signer is authorized for the multisig.

## Recovery steps

- If a submit or confirm fails:
  - [ ] Verify signer is in the multisig signer set.
  - [ ] Verify the transaction ID matches the call + salt.
  - [ ] If `tx already exists`, use a new salt.
- If execute fails:
  - [ ] Check the transaction state (`Pending`, `Confirmed`, `Executed`).
  - [ ] Ensure quorum is reached.
  - [ ] Ensure the target call is valid and does not revert.

## Signer rotation (high-level)

1. Submit a multisig transaction to add or remove signers.
2. Confirm with quorum.
3. Execute the signer update.
4. Verify the signer list and quorum values on-chain.
