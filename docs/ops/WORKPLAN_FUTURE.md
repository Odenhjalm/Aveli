# Future Work Plan

## Checklist
1. Start from a clean worktree (never /home/oden/Aveli).
2. Run `./ops/hygiene_check.sh` before any commit.
3. Keep commits atomic and scoped.
4. After running system tests, update the relevant docs (`docs/ops/DB_REPAIR_REPORT.md` or `docs/audit/*`).

## Definition of done
- Hygiene check passes.
- No tracked noise artifacts or secrets.
- Documentation is updated for any test runs or system changes.

## Standard command sequence
```bash
# Create a clean worktree
cd /home/oden/repo-db-repair

git worktree add -b fix/your-task /home/oden/repo-your-task
cd /home/oden/repo-your-task

# Verify hygiene before work
./ops/hygiene_check.sh

# Do work, then verify again before commit
./ops/hygiene_check.sh

git status -sb

git commit -m "your message"
```
