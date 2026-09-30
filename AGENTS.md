# Agent instructions

## Reading

- Read `README.md`, `docs/RUNBOOK.md`, and the consuming project's current
  plan and handoff. Read its ignored `.local/ENVIRONMENT.md` only when present
  and needed for local endpoints.
- Do not preload other docs, `.local/`, or `results/`. Open a reference page
  only when the task needs it:

| Need | Read |
| --- | --- |
| Launch or close a title | [docs/CONTROLLERS.md](docs/CONTROLLERS.md) |
| Ports, debuggers, or helper scripts | [docs/TOOLS.md](docs/TOOLS.md) |
| Remote Play, input, screenshots, or audio | [docs/CHIAKI_INPUT.md](docs/CHIAKI_INPUT.md) |
| A new project | [docs/PROJECT_PLAN_TEMPLATE.md](docs/PROJECT_PLAN_TEMPLATE.md) |
| Continuing another agent's work | [docs/HANDOFF_TEMPLATE.md](docs/HANDOFF_TEMPLATE.md) |

## Working

- Save raw logs to files; return only bounded, title-specific excerpts.
- No diary or duplicate summaries: use the runbook's one-line milestone record
  and link existing plans, hashes, and evidence.
- Keep user updates to outcomes, blockers, or the next action.
- Use WSL or Linux for builds and command-line console traffic.
- Never change console Settings or approve an update.
- Acquire the environment lock only during a bounded shared-console case.
- Commit the exact candidate before hardware testing and every proven
  milestone.
- Never commit hosts, credentials, personal paths, or raw evidence.
