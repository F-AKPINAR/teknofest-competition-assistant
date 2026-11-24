# Architecture

← Back to [README](../README.md)

## 1. Overview

The application is a single Cloudflare Worker. It serves the static React frontend and a JSON API, and it uses four Cloudflare services through bindings:

| Binding | Service | Purpose |
|---|---|---|
| `AI` | Workers AI | Query/document embeddings (`bge-m3`) and answer generation (`Llama 3.3 70B`) |
| `VECTORIZE_INDEX` | Vectorize | Semantic search over specification chunks (1024-dim, cosine) |
| `DB` | D1 (SQLite) | Users, tickets, FAQs, documents, question log |
| `DOCS_BUCKET` | R2 | Raw PDFs uploaded by the Content Manager |
| `ASSETS` | Static assets | `public/` (React SPA, logo, source PDFs) |

## 2. Question-answering pipeline

```mermaid
flowchart TD
    Q[User question + selected competition] --> F1{Regex guardrail<br/>off-topic / injection?}
    F1 -- yes --> R1[Reject: out of scope<br/>no model call]
    F1 -- no --> F2{Similar curated FAQ?<br/>similarity ≥ 0.62}
    F2 -- yes --> R2[Return FAQ answer + its sources<br/>no LLM call]
    F2 -- no --> E[Embed query with bge-m3<br/>follow-ups merged with previous question]
    E --> S[Vectorize top-5<br/>filter: competition_id]
    S --> T1{top score < 0.28?}
    T1 -- yes --> R3[Reject: unrelated to this competition]
    T1 -- no --> T2{top score < 0.45?}
    T2 -- yes --> X{Better match in another<br/>competition's documents?}
    X -- yes --> R4[Suggest the right competition]
    X -- no --> R5[No answer generated<br/>open support ticket → human]
    T2 -- no --> L[Llama 3.3 70B<br/>system prompt: answer ONLY from these chunks,<br/>cite clause numbers]
    L --> A[Answer + source badges<br/>document · page · clause]
    R1 & R2 & R3 & R4 & R5 & A --> LOG[(question_log)]
```

### Key design decisions

- **Gate the LLM, don't just instruct it.** Prompt instructions like "don't make things up" can be bypassed. A similarity threshold that decides whether the model is called at all cannot. When evidence is weak, no text is generated.
- **Clause-aware chunking.** `chunker.ts` detects numbered headings such as `5.2. Görev Videosu` and attaches `madde_no` / `madde_title` metadata to each chunk (40–1800 characters), so citations point to a specific clause rather than just a page.
- **Metadata-filtered retrieval.** Every vector carries `competition_id`, and queries are filtered on it, which isolates contexts between competitions.
- **FAQ-first.** Human-approved answers are checked before RAG. This is faster and cheaper, and the answers are guaranteed correct.
- **Turkish-aware guardrails.** JavaScript's `\b` only works on `[A-Za-z0-9_]`, so a pattern like `/\bşiir\b/` never matches. `rag.ts` builds its own Unicode boundaries (`(?<![\p{L}\p{N}])`) and root-plus-suffix patterns to cover Turkish inflection.

## 3. Data model (D1)

```mermaid
erDiagram
    users ||--o{ tickets : creates
    users ||--o{ tickets : "assigned to"
    tickets ||--o{ ticket_events : has
    documents ||--o{ document_chunks : "split into"
    users {
        int id PK
        text email UK
        text role "yarisci | hakem | koordinator | admin | icerik_yoneticisi"
        text competitions "reviewer scope, comma-separated"
        text password_hash
        text password_salt
    }
    tickets {
        int id PK
        text type "soru (question) | itiraz (appeal)"
        text question
        text ai_answer
        real ai_confidence
        text ai_sources "JSON"
        text status "ai_cevapladi → insana_yonlendirildi → atandi → cevaplandi"
        text human_answer
        int helpful "thumbs up/down"
    }
    faqs {
        int id PK
        text competition_id
        text question
        text answer
        text sources "JSON"
    }
    documents {
        int id PK
        text competition_id
        text title
        text version
        text status "isleniyor | aktif | pasif | hata"
        text r2_key
    }
    document_chunks {
        int id PK
        text vector_id
        int page
        text madde_no
        text text
    }
    question_log {
        int id PK
        text competition_id
        text question
        text outcome
        real confidence
    }
    source_files {
        int id PK
        text source_title
        text r2_key
    }
```

The schema evolved through 13 migrations (`scripts/migrations/`) applied to the live database without losing data. Because running migrations by hand turned out to be fragile, the `/api/setup` endpoint can also bring an older database up to the current schema idempotently.

## 4. Roles

| Role | Screen | Capabilities |
|---|---|---|
| Competitor (`yarisci`) | Home + chat | Choose a competition, ask questions, rate answers, open a ticket or appeal, track ticket status |
| Reviewer (`hakem`) | Staff panel | See escalated tickets **for assigned competitions only**, answer, promote to FAQ |
| Coordinator (`koordinator`) | Staff panel | Same as reviewer, across all competitions |
| Content Manager (`icerik_yoneticisi`) | Content panel | Upload specification PDFs, track processing, activate/deactivate sources |
| System Admin (`admin`) | Admin dashboard | Answer-quality stats, hand-off rate, most-asked topics, specification gaps |

## 5. API reference (main endpoints)

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/api/chat` | – | Ask a question (`question`, `competition`, optional history) |
| `POST` | `/api/itiraz` | – | Submit an appeal / feedback ticket |
| `GET` | `/api/my-tickets` | – | Track a ticket by number |
| `POST` | `/api/tickets/:id/feedback` | – | 👍 / 👎 on an AI answer |
| `GET` | `/api/faqs` | – | FAQ pool for a competition |
| `GET` | `/api/ready-competitions` | – | Competitions with an indexed knowledge base |
| `POST` | `/api/auth/login` | – | Staff login → signed token (24 h) |
| `GET` | `/api/tickets` | staff | Ticket queue (scoped by reviewer competitions) |
| `POST` | `/api/tickets/:id/assign` · `/answer` | reviewer+ | Assign / answer a ticket |
| `POST` | `/api/tickets/:id/promote-to-faq` | staff | Turn an answered ticket into an FAQ |
| `POST` | `/api/admin/documents` | content mgr / admin | Upload a PDF (stored in R2) |
| `POST` | `/api/admin/documents/:id/process-batch` | content mgr / admin | Chunk + embed + index in batches (stays within the Worker CPU limit) |
| `POST` | `/api/admin/documents/:id/toggle-status` | content mgr / admin | Activate / deactivate a source |
| `GET` | `/api/admin/stats` · `/api/admin/analiz` | admin / staff | Dashboard metrics and per-competition analysis |
| `GET` | `/api/health` | – | Deployment diagnostics (missing tables / secrets) |
| `GET` | `/api/setup?key=` | `SETUP_KEY` | Idempotent one-time schema completion + demo account seeding |

## 6. Security notes

- Passwords: salted SHA-256 (Web Crypto). Tokens: HMAC-SHA256 signed with the `AUTH_SECRET` secret.
- No secrets are committed. `AUTH_SECRET`, `SETUP_KEY` and `DEMO_PASSWORD` are Worker secrets, and the demo account hashes were removed from the public migrations.
- Role checks are enforced server-side by the `requireAuth([...roles])` middleware, not only in the UI.
- Known prototype simplification: Team ID / Application ID on tickets are not verified against an identity provider.
