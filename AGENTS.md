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
| More than one console run ahead | [docs/FAST_CYCLES.md](docs/FAST_CYCLES.md) |
| Ports, debuggers, or helper scripts | [docs/TOOLS.md](docs/TOOLS.md) |
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
- Freeze the built folder before a cycle and run the cycle as one script file
  (`scripts/ps5-cycle.sh`); never rebuild a folder a queued cycle will read.
- Never launch over, or close, a title someone else left running.
- Say what a run could not verify (feel, motion, sound): hand it to a person
  with steps and what each outcome means.
- A console that stops answering ends the session: no retry. Report what ran.
- Never commit hosts, credentials, personal paths, or raw evidence.
