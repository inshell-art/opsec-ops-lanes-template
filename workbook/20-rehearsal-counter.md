# Rehearsal: Counter flow

## Preparation

- [ ] Multisig + Counter deployed on the target network.
- [ ] Signer A and Signer B accounts funded.
- [ ] Fresh salt available (scripts/salt.sh).

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
