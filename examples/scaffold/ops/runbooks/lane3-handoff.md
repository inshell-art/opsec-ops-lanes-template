# Lane 3 handoff and lockdown runbook (template)

Purpose: transfer ownership and revoke deployer privileges.

Prereqs:
- Governance multisig is deployed and verified.
- Lane3 policy is configured for this network.

Steps:
1. Run plan to generate handoff intents.
2. Run checks for current ownership and target identity.
3. Human approves the intent meaning.
4. Apply in signing context only.
5. Verify postconditions that deployer has zero privilege.

Stop conditions:
- Ownership or roles do not match expected preconditions.
- Any required check fails.
