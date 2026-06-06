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

1. **Plan.** In a fresh Claude Code instance: `/swarm-initialiser <your project brief>`
   (or paste `initialiser-prompt.md` then the brief). Review the `CLAUDE.md` it produces. If the
   stack or anything foundational is unstated, it will ask first. Approve or send it back.
2. **Freeze + spawn.** Once you approve, mark the contracts `FROZEN`, commit `CLAUDE.md`, and create
   one git worktree per instance:
   ```
   git worktree add -b instance/<name> ../<name> main
   ```
3. **Execute.** In each worktree's instance: paste `worker-prompt.md` (or rely on the
   `swarm-worker` skill) and tell it "You are Instance N". It builds against stubs and commits to
   its own branch.
4. **Merge.** When all sections read `STATUS: DONE`, run `/swarm-reconciler` (or paste
   `reconciler-prompt.md`) from a clean clone with access to every branch. Resolve any surfaced
   contract mismatches, then ship.

## What's in this repo

- [`multi-agent-workflow.md`](multi-agent-workflow.md) — the design doc.
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
