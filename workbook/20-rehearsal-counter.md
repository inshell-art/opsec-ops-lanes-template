# Rehearsal: Counter flow

## Preparation

- [ ] Multisig + Counter deployed on the target network.
- [ ] Signer A and Signer B accounts funded.
- [ ] Fresh salt available (scripts/salt.sh).

## Step-by-step (devnet example)

1) Load env + set real values:

```bash
source scripts/env.example.sh
# Update: ACCOUNT, ACCOUNTS_FILE, SIGNERS, SIGNER_A, SIGNER_B, RPC
```

2) Deploy the example counter (writes `artifacts/<network>/counter.json`):

```bash
./scripts/deploy_example_counter.sh
```

3) Deploy the multisig (writes `artifacts/<network>/multisig.<label>.json`):

```bash
./scripts/deploy_multisig.sh --label primary
```

4) Run the rehearsal flow (writes `artifacts/<network>/rehearsal.counter.json`):

```bash
./scripts/rehearse_counter_flow.sh --label primary
```

5) Copy the tx hashes + final counter value into the checklist below.

## Submit -> confirm -> execute

- [ ] Submit tx hash: ______________________________
- [ ] Transaction ID (hash): _______________________ 
- [ ] Confirm tx (Signer A): _______________________
- [ ] Confirm tx (Signer B): _______________________
- [ ] Execute tx hash: _____________________________
- [ ] Final Counter value: _________________________

Expected:
- State transitions: Pending -> Confirmed -> Executed
- `submit_transaction` does not auto-confirm in OZ v2.0.0

## Negative tests

- [ ] Non-signer cannot submit (expect revert: "Multisig: not a signer")
- [ ] Non-signer cannot confirm (expect revert: "Multisig: not a signer")
- [ ] Non-signer cannot execute (expect revert: "Multisig: not a signer")
