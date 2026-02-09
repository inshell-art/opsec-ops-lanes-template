# CI examples

These files are examples only. Copy them into `.github/workflows/` in your downstream repo and customize.

Recommended CI behavior:
- Run plan and check only (lane0 and lane1).
- Do not run apply in CI.
- Use manual approvals and a signing OS for lane2+.

Files:
- `github-actions.plan-check.yml` - manual workflow to run plan and check.
- `github-actions.bundle.yml` - example workflow to build/test and create a bundle (optional).
