# TaskFlow — Multi-Agent Coordination File

## Project goal
Build an MVP of **TaskFlow**, a real-time collaborative task board (lightweight Trello):
email/password auth with JWT; boards → lists → cards with CRUD; drag-and-drop card
reordering that syncs live to all clients viewing the same board; comments on cards; a
per-board activity feed. Postgres for storage. Web frontend. Deployable to a single cloud VM
via Docker. Built by a solo developer running two parallel working instances.

## Decomposition rationale
**Two working instances: `backend` and `frontend`.** Reasoning:
- **Real-time folds into the backend, not its own instance.** The WebSocket server shares the
  same process, data model, and JWT auth as the REST API, and a card move must persist *and*
  broadcast together. Splitting realtime out would force two instances to fight over the data
  model and auth — the worst merge-conflict surface. REST + WS + auth + comments + activity +
  DB schema are therefore ONE domain.
- **Frontend is the one real seam.** It only *consumes* the API and WS contracts, so it can be
  built end-to-end against stubs/fixtures with zero dependency on the backend's real output.
- **Per-service Dockerfiles** belong to each instance. The cross-service deployment glue
  (compose + nginx + VM env) is small and is handled as a **human merge-time artifact** built
  against Contract 5 — not worth a third instance for an MVP.
- **Nothing is sequenced.** Every cross-boundary dependency is a frozen contract the frontend
  stubs against, so both instances start simultaneously. The deep coupling (drag-drop
  ordering) is neutralized by making the ordering scheme an explicit contract (Contract 4).

**ASSUMED — stack:** TypeScript end-to-end (NestJS backend + React frontend), chosen so both
instances can literally share the contract type definitions and because NestJS has first-class
WS gateways. Brief left language open; Postgres/web/Docker are fixed. **Confirm before freeze.**

**Alternative the human may choose:** add a 3rd lightweight `platform` instance (devops-engineer)
owning compose/nginx/VM instead of folding deployment into the merge step.

## Status legend
IN PROGRESS · PENDING · BLOCKED · DONE · ASSUMED · WAITING ON <who/what>

---

## INTERFACE CONTRACTS  —  STATUS: PROPOSED
<!-- Becomes FROZEN only on human ratification. After that: no edits without the human. -->
<!-- ASSUMED stack (TypeScript/NestJS/React) underlies these; revisit if stack changes. -->

### Contract 1: Database schema (source of truth for all data shapes)
- Producer: Instance 1 (backend) — owns and migrates it
- Consumer(s): Instance 2 (frontend) — reads shapes only, never the DB
- Shape / format:
  ```
  users        (id uuid pk, email text unique, password_hash text, created_at timestamptz)
  boards       (id uuid pk, owner_id uuid fk users, title text, created_at timestamptz)
  lists        (id uuid pk, board_id uuid fk boards, title text, position text)  -- position = fractional index, see Contract 4
  cards        (id uuid pk, list_id uuid fk lists, title text, description text, position text, created_at timestamptz)
  comments     (id uuid pk, card_id uuid fk cards, author_id uuid fk users, body text, created_at timestamptz)
  activity     (id uuid pk, board_id uuid fk boards, actor_id uuid fk users, verb text, target_type text, target_id uuid, created_at timestamptz)
  ```

### Contract 2: REST API
- Producer: Instance 1 (backend)
- Consumer(s): Instance 2 (frontend)
- Shape / format:
  ```
  Base: /api/v1   Auth: Authorization: Bearer <jwt>   Errors: { error: { code: string, message: string } } + HTTP status

  POST   /auth/register   {email,password} -> 201 {user:{id,email}, token}
  POST   /auth/login      {email,password} -> 200 {user:{id,email}, token}
  GET    /boards                            -> 200 {boards:[{id,title,owner_id,created_at}]}
  POST   /boards          {title}           -> 201 {board}
  GET    /boards/:id                         -> 200 {board, lists:[{...,cards:[...]}]}  (full board hydrate)
  POST   /lists           {board_id,title,position} -> 201 {list}
  PATCH  /lists/:id       {title?,position?} -> 200 {list}
  POST   /cards           {list_id,title,position}  -> 201 {card}
  PATCH  /cards/:id       {title?,description?,list_id?,position?} -> 200 {card}   (move = change list_id and/or position)
  DELETE /cards/:id                          -> 204
  POST   /cards/:id/comments {body}          -> 201 {comment}
  GET    /cards/:id/comments                 -> 200 {comments:[...]}
  GET    /boards/:id/activity                -> 200 {activity:[...]}
  ```

### Contract 3: WebSocket / live-sync protocol
- Producer: Instance 1 (backend) — emits + authorizes
- Consumer(s): Instance 2 (frontend) — connects + renders
- Shape / format:
  ```
  Transport: Socket.IO (or native WS) at /ws. Auth on connect: { token: <jwt> } -> reject if invalid.
  Rooms: one per board, id = board:<boardId>. Client emits "board.join" {boardId} after connect.

  Server -> client events (payload mirrors REST entity shapes from Contracts 1/2):
    card.created   {card}
    card.updated   {card}          // covers move: new list_id + position
    card.deleted   {cardId}
    list.created   {list}
    list.updated   {list}
    comment.created{comment}
    activity.appended {activityItem}

  Echo rule: the originating client applies an optimistic update locally, then reconciles
  against the authoritative server event (server event always wins).
  ```

### Contract 4: Card/list ordering scheme  (the deep-coupling contract — read carefully)
- Producer: Instance 1 (backend) — validates + persists `position`
- Consumer(s): Instance 2 (frontend) — computes new `position` on drag-drop
- Shape / format:
  ```
  position is a FRACTIONAL INDEX stored as a lexicographically-sortable string (LexoRank-style).
  Ordering of a list/board = items sorted ascending by position string.
  On drag-drop, the frontend computes a new position BETWEEN the two neighbors:
     position = midpoint(prevItem.position, nextItem.position)
  using a shared helper. Insert at start: midpoint(null, first). Insert at end: midpoint(last, null).
  Both instances MUST use the same midpoint algorithm — published as a shared module
  `shared/ordering.ts` (exports `midpoint(a: string|null, b: string|null): string`).
  Backend re-validates monotonicity; on collision it reassigns and broadcasts via card.updated.
  ```

### Contract 5: Deployment / service contract
- Producer: human (merge-time) — writes docker-compose + nginx
- Consumer(s): both instances — each provides a working Dockerfile honoring these values
- Shape / format:
  ```
  backend:  container listens on :8000, reads env DATABASE_URL, JWT_SECRET, PORT; exposes /api + /ws
  frontend: static build served by nginx; calls API at /api and WS at /ws (same origin, proxied)
  postgres: official image, volume-backed; DATABASE_URL = postgres://taskflow:<pw>@db:5432/taskflow
  nginx:    reverse proxy 80 -> frontend static + /api,/ws -> backend:8000 (WS upgrade headers set)
  Each instance ships: ./Dockerfile + documents required env vars in its work log.
  ```

### Contract 6: JWT / auth token
- Producer: Instance 1 (backend)
- Consumer(s): Instance 2 (frontend)
- Shape / format:
  ```
  JWT HS256, payload { sub: userId, email, iat, exp }; exp = 7 days (MVP, no refresh token).
  Frontend stores token (httpOnly cookie preferred; localStorage acceptable for MVP — ASSUMED),
  sends Authorization: Bearer <token> on REST and { token } on WS connect.
  401 -> frontend redirects to login.
  ```

---

## ESCALATIONS & PROPOSED AMENDMENTS
<!-- Instances write structured requests + *proposed* amendments here. Never edit the
     frozen block or another instance's section directly. Human resolves. -->
(empty at start)

---

## INSTANCE 1 — Backend & Realtime  ·  STATUS: PENDING
**Owns:** the entire server — `/server` (NestJS app), DB schema + migrations, REST API,
WebSocket gateway, auth, comments, activity feed, `shared/ordering.ts`, and `server/Dockerfile`.
**Does NOT touch:** any frontend code (`/web`), nginx/compose (human merge artifact), or
another instance's section of this file.
**Assigned skills:** nestjs-expert, api-designer, websocket-engineer, postgres-pro, sql-pro,
typescript-pro, security-reviewer, test-master

**Role prompt:**
You are the **Backend & Realtime** instance for TaskFlow. You own everything server-side in
`/server`: the Postgres schema + migrations, the REST API, the WebSocket live-sync gateway, JWT
auth, comments, the activity feed, the shared ordering helper (`shared/ordering.ts`), and your
own `server/Dockerfile`. You must NOT touch `/web` or the deployment compose/nginx.
**Produces:** Contracts 1, 2, 3, 4 (the `midpoint()` helper), 5 (your Dockerfile), 6.
**Consumes:** none (you are the upstream producer).
**Assigned skills:** nestjs-expert + api-designer (HTTP surface), websocket-engineer (gateway),
postgres-pro + sql-pro (schema/queries), security-reviewer (auth), test-master (coverage).
**Domain-specific note:** implement the `card.updated` broadcast so it fires on every persisted
card move; the server event is authoritative over client optimism.
Follow the `swarm-worker` runtime protocol for all shared-file, escalation, and git rules.

**Work log:**
(instance writes only here)

---

## INSTANCE 2 — Web Frontend  ·  STATUS: PENDING
**Owns:** the entire web client — `/web` (React + TypeScript app), all UI (auth screens, board
view, lists, cards, drag-and-drop, comments panel, activity feed), the WS client, optimistic
update + reconciliation logic, and `web/Dockerfile` (Contract 5).
**Does NOT touch:** any server code (`/server`), the DB, nginx/compose, `shared/ordering.ts`
(consume it as published; propose amendments rather than edit), or another instance's section.
**Assigned skills:** react-expert, ui-ux-pro-max, frontend-design, typescript-pro,
websocket-engineer, playwright-expert, test-master

**Role prompt:**
You are the **Web Frontend** instance for TaskFlow. You own everything in `/web`: a React +
TypeScript SPA covering login/register, the board view with drag-and-drop card reordering,
comments, and the activity feed, plus the WS client, the optimistic-update/reconciliation logic,
and your own `web/Dockerfile`. You must NOT touch `/server`, the DB, the deployment glue, or
`shared/ordering.ts` (consume it as published).
**Produces:** Contract 5 (your Dockerfile).
**Consumes (stub against these):** Contracts 1, 2, 3, 4, 6. Stand up a mock API matching
Contract 2 and a mock WS emitter matching Contract 3 so you can build the full UI immediately —
do not wait for the backend.
**Assigned skills:** react-expert + ui-ux-pro-max + frontend-design (interface),
websocket-engineer (live-sync client), playwright-expert + test-master (tests).
**Domain-specific note:** for drag-drop, compute `position` with the shared `midpoint()` from
Contract 4 and apply optimistic updates that reconcile to the authoritative server event.
Follow the `swarm-worker` runtime protocol for all shared-file, escalation, and git rules.

**Work log:**
(instance writes only here)
