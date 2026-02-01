# StarkNet OZ Multisig

A minimal Cairo workspace that wraps OpenZeppelin's `MultisigComponent` into a deployable
multisig wallet contract, plus scripts + a workbook to rehearse submit/confirm/execute.

## What this is

- A **regular StarkNet contract** that enforces quorum through on-chain
  submit/confirm/execute calls.
- A minimal wrapper around OpenZeppelin's `MultisigComponent` (v2.0.0) with no additional logic.
- A reusable workspace with scripts and artifact templates for deployments.

## What this is not

- Not a multisig **account** contract.
- Not governance tooling or a policy layer (no timelock, roles, or upgrades).

## Versions (pinned)

This workspace targets Cairo/Scarb **2.12.x** and pins OpenZeppelin to avoid
version drift.

- `openzeppelin_governance = "=2.0.0"`
- `openzeppelin_utils = "=2.0.0"`

These pins keep the dependency graph compatible with Cairo 2.12.0.

## Quickstart

Build:

```bash
scarb build
```

Set env vars (see `scripts/env.example.sh`):

```bash
source scripts/env.example.sh
```

Deploy the example Counter (devnet or testnet):

```bash
./scripts/deploy_example_counter.sh
```

Deploy a multisig instance:

```bash
./scripts/deploy_multisig.sh --label primary
```

Rehearse the flow against the Counter:

```bash
./scripts/rehearse_counter_flow.sh --label primary
```

Artifacts are written to `artifacts/<network>` (default: `artifacts/devnet`).
## Lifecycle (submit -> confirm -> execute)

Each action is a separate on-chain transaction:

1. Submit: a signer proposes a call (target + selector + calldata + salt).
2. Confirm: other signers confirm the proposal.
3. Execute: any signer executes once quorum is met.

## Security notes

- Signers should be **independent account contracts**.
- 2-of-2 maximizes safety but reduces availability (both must be online).
- Always verify the target address, selector, calldata, and salt before execution.

## Docs

- Runbook: `workbook/00-runbook.md`
- Deploy checklist: `workbook/10-deploy.md`
- Rehearsal checklist: `workbook/20-rehearsal-counter.md`
- Run logs template: `workbook/runs/run-YYYYMMDD.md`
