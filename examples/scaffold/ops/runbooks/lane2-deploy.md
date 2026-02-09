# Lane 2 deploy runbook (template)

Purpose: deploy contracts and capture addresses using lane2 rules.

Prereqs:
- Lane2 policy is configured for this network.
- Deployer keystore is available in signing context.

Steps:
1. Run plan to generate intents.
2. Run checks and confirm required checks pass.
3. Human approves the intent meaning.
4. Apply in signing context only.
5. Record tx hashes and post-deploy snapshots.

Stop conditions:
- Any required check fails.
- Intent hash changes after approval.
- You are not in the correct OPSEC compartment.
