# Deploy checklist

## Inputs (fill before running scripts)

- [ ] Network: __________________________
- [ ] RPC: ______________________________
- [ ] Deployer account: _________________
- [ ] Accounts file: ____________________
- [ ] Multisig label: ___________________
- [ ] Quorum: ________
- [ ] Signers (comma-separated): ________
- [ ] Counter initial value: ____________

## Checks (pre-deploy)

- [ ] Chain id matches target network.
- [ ] Signers list is correct and funded.
- [ ] Quorum <= signers count.
- [ ] Class hashes match expected Cairo/Scarb version.

## Declare classes

- [ ] Multisig class hash: ______________________________
- [ ] Multisig declare tx: ______________________________
- [ ] Counter class hash: _______________________________
- [ ] Counter declare tx: _______________________________

## Deploy instances

Multisig instance:
- [ ] Label: ______________________________
- [ ] Address: ____________________________
- [ ] Deploy tx: __________________________
- [ ] Quorum: ________
- [ ] Signers: ____________________________

Optional additional multisig instance:
- [ ] Label: ______________________________
- [ ] Address: ____________________________
- [ ] Deploy tx: __________________________
- [ ] Quorum: ________
- [ ] Signers: ____________________________

Example Counter:
- [ ] Address: ______________________________
- [ ] Deploy tx: ____________________________
- [ ] Initial value: ________

## Post-deploy verification

- [ ] On-chain multisig signers list matches expected.
- [ ] On-chain quorum matches expected.
- [ ] Example Counter `get()` returns the initial value.

## Artifacts

- [ ] `artifacts/<network>/multisig.class.json` updated
- [ ] `artifacts/<network>/multisig.<label>.json` updated
- [ ] (if applicable) additional `artifacts/<network>/multisig.<label>.json` updated
- [ ] `artifacts/<network>/counter.class.json` updated
- [ ] `artifacts/<network>/counter.json` updated
