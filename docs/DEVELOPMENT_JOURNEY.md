# Development Journey

← Back to [README](../README.md)

How the project went from a problem statement to a live product in about ten days, and what we learned along the way.

## Context

The **T3 Foundation AI Creathon 2026** asked teams to pick one problem from a booklet and turn it into a working, deployed prototype together with a business model. We chose **Problem 5: TEKNOFEST / UAV FAQ & Chatbot Assistant**. The brief listed six mandatory requirements (verified source pool, RAG-based Q&A, source citation, confidence level, competition context and human hand-off), and stated that **missing any one of them meant elimination**. Judging gave the largest weight (30 points) to *"MVP flow integrity: mandatory requirements demonstrated end-to-end in a working prototype"*.

That shaped our main principle: **show it working, don't describe it.**

## Timeline

| Date (2026) | Milestone |
|---|---|
| **Aug 15–16** | Organizer's *"From Idea to Live Product"* workshop on Cloudflare Workers, D1 and Vectorize. We studied the recordings and the Caka sample project. |
| **Aug 17** | Problem selected. Studied the brief, the official UAV specification and four guideline documents. |
| **Aug 23** | **v1 prototype live.** Worker + D1 + Vectorize; UAV specification chunked (317 chunks) and embedded. Chat with source badges, confidence threshold, automatic ticket creation, appeal form, reviewer panel. |
| **Aug 24** | Long iteration day, **migrations v2 → v8**: team/application IDs on appeals, 👍/👎 feedback, FAQ pool, real password auth and the Content Manager role, browser-side PDF upload and indexing, and **4 more competitions** (5G & AI Road Safety, Biotechnology, Blockchain, Chip Design). That made 533 chunks and 50 hand-verified FAQs in total. |
| **Aug 24** | **UI redesign** to match the festival's visual identity: deep-space gradient, brand colors, competition cards with per-field icons, and one design language across all five role screens. |
| **Aug 24–25** | Team-wide "try to break it" testing session, then the bug-fix pass (below). |
| **Aug 25** | Business model canvas, pitch deck, demo video script, and jury Q&A preparation. |
| **Aug 26** | **Submission**: live prototype + pitch deck + business model canvas + demo video. |
| **Sep 5–6** | Post-submission improvements, **migrations v9 → v13**: reviewers scoped to competitions, clickable source badges that open the PDF on the cited page, a per-competition question analytics view, FAQs that keep their sources, and a fix for a missing column in production. |

## Where it stands today (November 2026)

The prototype is still live on the same deployment (last code deploy: 6 September 2026). Figures from the production database and index:

| Metric | Value |
|---|---|
| Competitions with an indexed knowledge base | 5 |
| Vectors in the Vectorize index | 569 (533 from the initial batch ingest + PDFs uploaded through the Content Manager panel) |
| Curated FAQ entries | 53 across 5 competitions |
| Questions logged | 63 |
| Support tickets / appeals created | 28 |

These are prototype-scale numbers from the jury, the team and demo testing, not production traffic.

## Notable problems we solved

**1. Infinite request loop during PDF processing.**
The client called `process-batch` in a `while (!done)` loop. When the server returned an error, `done` never became true and the browser kept hitting the endpoint. *Fix:* treat non-2xx responses as terminal and surface the error.

**2. Turkish words silently bypassing the guardrail.**
`"bana bir şiir yaz"` ("write me a poem") passed the off-topic filter. In JavaScript regex, `\b` is defined only for `[A-Za-z0-9_]`, so `/\bşiir\b/` can never match a word that starts with `ş`. *Fix:* custom Unicode-aware boundaries `(?<![\p{L}\p{N}])` plus root-plus-suffix patterns for Turkish inflection. We also took care that the root `rap` would not block legitimate questions about a *rapor* (report).

**3. Opaque "cannot reach server" errors.**
Unhandled exceptions made Workers return an HTML error page. The frontend could not parse it and showed a generic message for every failure. *Fix:* a global `app.onError` that always returns JSON with the real cause, plus a `/api/health` diagnostics endpoint that lists which tables and secrets are missing.

**4. White-screen crashes.**
Two cases: the admin dashboard treated an error object as data (`stats.top_questions.length`), and a malformed session in `localStorage` crashed every page load, which also made logging out impossible. *Fix:* defensive parsing and validated session restore.

**5. Fragile migrations against production.**
Running `wrangler d1 execute` by hand from the wrong folder or skipping a file left the remote database half-migrated. One `ALTER TABLE` (v3) never reached production, so thumbs-up/down feedback was silently dropped. *Fix:* the idempotent `/api/setup` endpoint, which lets the Worker complete its own schema, and migration v13 to repair the missing column.

**6. Misleading UI states.**
Very short questions produced an empty bubble labelled "AI answer", and low-confidence answers still showed a confidence percentage. *Fix:* when the system does not answer, it no longer shows the confidence percentage or source badges, so the user is not misled.

## What we deliberately did *not* claim

Before the jury we wrote down the claims we could not support with evidence and agreed not to make them:

- The 0.45 threshold is an **engineering starting value**, not a calibrated result. The plan is to tune it from the hand-off rate measured in the admin dashboard.
- There is **no automatic source precedence** (addendum overriding the specification), only active/passive status managed by a person.
- The KPIs in the pitch deck are **pilot targets**, not measured results.

Saying "this isn't there yet, here's how we'd do it" is better engineering than an overclaim that falls apart under a technical question.

## Lessons learned

- **Gate generation on retrieval quality.** The most reliable hallucination defense in this project was not calling the model at all.
- **Metadata is a feature.** Clause numbers and competition IDs stored at chunking time are what make citations and context isolation possible.
- **Build diagnostics early.** `/api/health` would have saved hours if it had existed on day one.
- **Language matters at the regex level.** Tools tested mostly on English can fail silently on Turkish.
- **Ship, then break it as a team.** Our most valuable QA was one evening of teammates deliberately trying to break the live site.
