# Swarm — Parallel Multi-Agent Development with Claude Code

Run several Claude Code instances as one coordinated team. A planner carves the project into
the *minimum* number of independent tracks, freezes the interfaces between them, and a human
gates every decision. Each track builds in its own git worktree against frozen contracts; a
final merge phase proves those contracts actually held. The payoff is throughput — a solo
developer ships in a fraction of the usual time without losing control or clarity.

This repo is the design plus a ready-to-use prompt suite. Everything is plain files and prompts
— no framework, nothing beyond standard Claude Code and git.

## The idea in one breath

The filesystem is the only thing the parallel instances share. They coordinate through one
sectioned markdown file (`CLAUDE.md`); each instance writes only to its own section, so their
updates never collide. Interface contracts are agreed and **frozen** before any code is written,
which removes the hardest problem in parallel work — timing and ordering dependencies. Every
instance builds against a stub of the frozen contract, so no one waits on anyone. A human ratifies
the plan, resolves escalations, and owns the final merge.

Read [`multi-agent-workflow.md`](multi-agent-workflow.md) for the full rationale.

## The three phases (and the prompt for each)

| Phase | What happens | Prompt / skill |
|-------|--------------|----------------|
| **1. Plan** | One planning agent digests the brief, decomposes to the fewest instances, assigns each a role + skills, and proposes the interface contracts → a pre-populated `CLAUDE.md`. The human ratifies; contracts become `FROZEN`. | `swarm-initialiser` · [`initialiser-prompt.md`](initialiser-prompt.md) |
| **2. Execute** | The human spawns one instance per worktree. Each builds its domain against frozen-contract stubs, writing only to its own section, never idling, escalating (not negotiating) when a contract is wrong. | `swarm-worker` · [`worker-prompt.md`](worker-prompt.md) |
| **3. Merge** | A merge agent audits the coordination file, merges branches in dependency order, and **proves every frozen contract holds between each producer's real code and each consumer's real code**, then integration-tests the whole. | `swarm-reconciler` · [`reconciler-prompt.md`](reconciler-prompt.md) |

Each phase ships in two forms: a **skill** (auto-invoked, installed under `~/.claude/skills/`)
and a **copy-pasteable `.md`** (paste into a fresh instance) — identical content, your choice.

## Quickstart

1. **Bootstrap the project repo.** From the Swarm folder:
   ```powershell
   .\new-swarm-project.ps1 -Name <Name>
   ```
   Creates `<Container>/<Name>` — default container `PORTFOLIO`, a sibling of Swarm — as its own
   git repo with a starter `.gitignore` and an **initial commit**, then prints your next commands.
   Both halves are load-bearing: a project that isn't its own repo gets its worktrees cut from the
   Swarm container repo and inherits the wrong `CLAUDE.md`, and a bare `git init` with no commit
   leaves `main` unborn, so every `git worktree add ... main` later dies on
   `fatal: invalid reference: main`. Then `cd` in and confirm
   `git rev-parse --show-toplevel` prints the project, not Swarm.
2. **Plan.** In a fresh Claude Code instance *in the project folder*:
   `/swarm-initialiser <your project brief>` (or paste `initialiser-prompt.md` then the brief).
   Review the `CLAUDE.md` it produces. If the stack or anything foundational is unstated, it will
   ask first. Approve or send it back.
3. **Freeze + spawn.** Once you approve, mark the contracts `FROZEN`, commit `CLAUDE.md`, and create
   one git worktree per instance — sibling layout, scratch copies beside the project:
   ```
   git worktree add -b instance/<x> ../<Name>-<x> main
   ```
4. **Execute.** In each worktree's instance: paste `worker-prompt.md` (or rely on the
   `swarm-worker` skill) and tell it "You are Instance N". It builds against stubs and commits to
   its own branch. Launch workers with `claude --model sonnet` and keep Opus for the planning and
   merge phases, which are the reasoning-heavy ones.
5. **Merge.** When all sections read `STATUS: DONE`, run `/swarm-reconciler` (or paste
   `reconciler-prompt.md`) from a clean clone with access to every branch. Resolve any surfaced
   contract mismatches, then ship.

## What's in this repo

- [`multi-agent-workflow.md`](multi-agent-workflow.md) — the design doc.
- [`new-swarm-project.ps1`](new-swarm-project.ps1) — bootstraps a project as its own git repo
  inside the container (`-Container`, default `PORTFOLIO`), with the starter `.gitignore` and the
  initial commit that makes worktrees resolvable.
- [`move-projects.ps1`](move-projects.ps1) — relocates the container and runs `git worktree repair`
  afterwards, since worktrees store absolute paths and a plain move silently breaks them.
- [`initialiser-prompt.md`](initialiser-prompt.md) / [`worker-prompt.md`](worker-prompt.md) /
  [`reconciler-prompt.md`](reconciler-prompt.md) — the three phase prompts (skills mirror these
  under `~/.claude/skills/swarm-*`).
- [`taskflow-CLAUDE.md`](taskflow-CLAUDE.md) — a worked example: the coordination file the
  Initialiser produced for a real-time Trello clone (decomposition, six frozen contracts, two
  slimmed role prompts).
- `swarm-dryrun/` — a complete end-to-end dry run on a tiny "Quotebook" project: real worktrees,
  real code, real git history (`plan → 2 parallel instances → dependency-ordered merge →
  reconciliation`). Its history shows the Reconciler catching a planted contract drift that both
  workers' own tests missed — the whole point of the pattern, demonstrated.

## Why it works

- **Frozen contracts kill ordering dependencies.** Everyone builds against the same fixed
  interface from minute one; integration is deferred, not blocking.
- **Sectioned ownership kills merge conflicts.** Disjoint paths + own-section-only writes mean the
  branches — and even the shared coordination file — merge cleanly.
- **The conformance check is the safety net.** Frozen contracts prevent *most* integration pain;
  the one residual failure — "the producer implemented it slightly differently than the consumer
  assumed" — is exactly what the Reconciler hunts for, on both sides' real code.
- **A human stays in the loop.** The coordination logic is visible files and prompts, not a black
  box — transparent and steerable end to end.

## Relationship to automated tools

This mirrors what systems like DevSwarm and Claude Code's experimental Agent Teams do — a planner
coordinating parallel workers — but with a deliberate human gate and a one-shot planner instead of
a persistent live lead. It trades some automation for full control and visibility, and doubles as a
clear mental model for what those tools do under the hood. Individual pieces can be handed off to
native features (subagents, Agent Teams) as they mature.

## Every step, in order

The whole run, from nothing to shipped. Replace `<Name>` with the project name throughout.

**Setup — before any agent runs**

| # | Step | Command |
|---|------|---------|
| 1 | Bootstrap the project as its own repo | `cd <Swarm folder>`<br>`.\new-swarm-project.ps1 -Name <Name>` |
| 2 | Move in | `cd ..\PORTFOLIO\<Name>` |
| 3 | Verify the repo root is the project, not Swarm | `git rev-parse --show-toplevel` |
| 4 | Verify `main` is born (worktrees need a real ref) | `git rev-list --count HEAD` → must be ≥ 1 |
| 5 | Create the cloud copy | `gh repo create <Name> --private --source=. --remote=origin --push` |

**Plan — one agent, human-gated**

| # | Step | Command |
|---|------|---------|
| 6 | Open a session in the project (keep Opus here) | `claude` |
| 7 | Run the planner with your brief | `/swarm-initialiser <brief>` |
| 8 | Review the decomposition and proposed contracts | — approve, or send it back |
| 9 | Freeze and commit the coordination file | mark contracts `FROZEN`, then `git add CLAUDE.md && git commit` |

**Execute — one instance per worktree, in parallel**

| # | Step | Command |
|---|------|---------|
| 10 | Create one worktree per instance | `git worktree add -b instance/<x> ../<Name>-<x> main` |
| 11 | Launch each worker in its own worktree | `cd ..\<Name>-<x>` then `claude --model sonnet` |
| 12 | Assign the role | `/swarm-worker` (or paste `worker-prompt.md`), then "You are Instance N" |
| 13 | Resolve escalations as they surface | amend the frozen block yourself; instances propose, never edit |
| 14 | Back up every branch before merging | `git push -u origin --all` (from the project root) |

**Merge — one agent, after every section reads `DONE`**

| # | Step | Command |
|---|------|---------|
| 15 | Run the reconciler from a clean clone with all branches | `/swarm-reconciler` |
| 16 | Resolve any contract mismatches it surfaces | — |
| 17 | Integration-test, then ship | — |

Steps 1–5 collapse into step 1 alone: `new-swarm-project.ps1` does the repo creation, `.gitignore`,
initial commit, and root check, then prints steps 2, 5, 6 and 10 for you to paste.

Two rules worth repeating, because breaking either is what makes a run go wrong: **nothing is
spawned before you ratify the plan**, and **no instance ever edits the frozen block or another
instance's section** — it proposes, you decide.
