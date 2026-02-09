# Lane 5 governance runbook (template)

Purpose: execute governance actions via multisig.

Prereqs:
- Governance and treasury multisigs are configured.
- Lane5 policy is configured for this network.

Steps:
1. Run plan to generate governance intents.
2. Run checks and simulation if supported.
3. Human approves the intent meaning.
4. Apply in signing context only.
5. Verify postconditions for each action.

Stop conditions:
- Any required check fails.
- Simulation results are inconsistent with expected effects.
