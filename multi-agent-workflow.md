# Parallel Multi-Agent Development with Claude Code

## Overview

A manual orchestration pattern for running several Claude Code instances as a single coordinated development team. Instead of one assistant working through a project sequentially, multiple instances work in parallel — each owning a distinct part of the codebase — coordinated through plans and contracts agreed before work begins. A dedicated planning instance does the heavy upfront thinking, a human holds final decision power, and the filesystem serves as the only shared medium at runtime. The aim is to compress work that would normally take weeks into days or hours, without giving up control or clarity over what each agent is doing.

## Architecture

Each working instance runs in its own git worktree (or branch), giving it an isolated copy of the repository. This isolation is the foundation of the whole approach: instances can read, edit, build, and commit freely without stepping on one another, because they operate on separate file trees that merge cleanly later through a normal git workflow. There is no shared live process and no shared memory — only shared files on disk.

Every working instance is initialized with a role prompt that establishes:

- Its identity and domain ownership — what it is responsible for, and explicitly what it is *not* to touch
- The location and purpose of the shared coordination file
- The protocol for when and how to read and write updates
- How to handle dependencies and when to escalate to the human

## The initialiser instance

Before any working instance is spawned, a single **initialiser** runs first. It is a one-shot planning agent, not a live coordinator: it digests the project description and supporting documents, then proposes a complete plan and exits. It does not stay running to manage the others — keeping it one-shot preserves the filesystem-only architecture and avoids reintroducing live inter-process coordination.

Its job is to decide how many separate instances the work genuinely needs, assign each one a role by reusing an existing personality template or drafting a new one where none fits, and propose the interface contracts between them. Critically, it is biased toward the *minimum* number of instances: more agents is not better, since each adds coordination and merge cost. Two pieces that are tightly coupled belong in one instance, not two. It must also justify its decomposition — why these domains, why this count — so the reasoning can be checked before anything runs.

The initialiser produces a concrete, reviewable artifact: a pre-populated shared coordination file, with one section per proposed instance, the role-prompt assignments, and a proposed interface-contract block. Nothing is spawned until the human reviews this plan. The human can approve it, or send it back for revision — a deliberate planning loop rather than a rubber stamp. Final decision power always rests with the human.

## Coordination layer

Because the filesystem is the only medium the working instances share, runtime coordination happens through a single shared markdown file — an extended `CLAUDE.md`, which Claude Code reads automatically at startup. The file is divided into one dedicated section per instance, and each instance writes only to its own section. This sectioned ownership is the core safeguard against concurrent-write conflicts: since no two instances ever touch the same lines, their updates cannot collide.

Each section carries a lightweight status protocol so teammates can read state at a glance — flags such as `IN PROGRESS`, `PENDING`, `BLOCKED`, and `DONE`, plus `ASSUMED` for any case where an instance has built against a best-guess assumption that still needs confirmation.

## Interface contracts, frozen after approval

The interface contracts — API response shapes, data formats, component props, anything one instance produces and another consumes — are the highest-leverage part of the plan. The initialiser proposes them, but they only become `FROZEN` once the human ratifies the plan. From that point they are fixed for the duration of the run.

Freezing contracts before work begins removes the hardest problem in parallel development: timing and ordering dependencies. Because every instance starts with a complete, agreed contract to build against, no instance has to wait for another to finish or guess at an interface that does not exist yet. One instance implements a contract while another consumes it, and both build toward the same fixed assumptions — the same way strong engineering teams settle architecture before splitting the work, rather than discovering incompatibilities at integration time.

## Handling dependencies at runtime

When one instance needs something another has not yet supplied, the design treats it primarily as a prevented problem rather than one to engineer around, handled in layers from the lightest intervention up:

1. **Build against the contract, not the implementation.** An instance does not need a teammate's real output to proceed — it builds against the frozen interface using a stub or fixture that matches the contract, and real integration happens at merge time. Because the contract is already frozen, the information an instance needs is available from the start.
2. **Flag and reorder, never idle.** If an instance genuinely needs a teammate's actual artifact and it is still `PENDING`, it records a `WAITING ON` note in its own section, switches to other work within its own domain, and re-reads the shared file at defined checkpoints. It does not block.
3. **Escalate, never negotiate.** For a real gap, or when an instance discovers a frozen contract is wrong, it writes a structured request or a *proposed* amendment in a dedicated area — never by editing the frozen block or another instance's section — and stops that thread for the human to resolve. Instances never settle contract ambiguity unilaterally, since two agents independently "fixing" the same ambiguity in different ways is the most damaging failure mode.
4. **Amend through the human.** Contract changes are a human-gated event: an instance proposes, the human ratifies and updates the frozen block, and the affected instances pick up the change on their next read. The freeze is not permanent law — it simply means no changes without the orchestrator.

The case that fits none of these — where an instance genuinely cannot produce anything without a teammate's real output and cannot stub it — is a signal those pieces were never independent enough to parallelize. The initialiser is responsible for catching this at planning time and either sequencing them or folding them into a single instance. Recognizing what *should not* run in parallel is part of the planning job.

## The human orchestrator

The human works hand in hand with the initialiser and retains final authority throughout. They ratify or revise the plan, approve the freezing of contracts, resolve escalations and contract amendments during execution, and handle the final merge and reconciliation across branches. Keeping a person in this role keeps the system transparent and steerable — the coordination logic is visible and editable rather than hidden inside a black box.

## Relationship to existing tools

Structurally, this mirrors what automated systems such as DevSwarm and Claude Code's experimental Agent Teams do — a planner coordinating parallel workers — but performed with a deliberate human gate and a one-shot planner rather than a persistent live lead. The approach trades some automation for full control and visibility: it makes the coordination mechanics explicit, works with nothing beyond standard Claude Code and git, and serves as a clear mental model for what the automated tools do under the hood. Individual pieces can later be handed off to native features such as subagents or Agent Teams as they mature.

## Outcome

The practical payoff is throughput: a single developer can run several focused agents at once and ship in a fraction of the usual time, while git, frozen contracts, and a human gate keep the result coherent. Beyond personal productivity, the pattern is straightforward to teach — the moving parts are all plain files and prompts — which makes it a useful way to show other student builders, concretely, what AI-accelerated development actually looks like.
