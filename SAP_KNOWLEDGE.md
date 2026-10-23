# SAP Knowledge Base

Location: `backend/app/knowledge/data/`

```
data/
├── functional/          # module_type: FUNCTIONAL
│   ├── sd/              # pricing condition technique, billing→accounting
│   ├── mm/              # valuation & automatic account determination
│   ├── fi/              # posting periods, G/L posting errors
│   └── co/              # cost elements, CO assignments
├── technical/           # module_type: TECHNICAL
│   ├── abap/            # Open SQL performance
│   ├── st22/            # dump analysis method
│   └── debugging/       # diagnosis transaction toolbox
├── integration/         # module_type: CROSS_MODULE (SD→FI chain)
├── cross_module/        # module_type: CROSS_MODULE (MM→FI chain)
├── metadata/            # schema documentation (not ingested)
├── sd/vf032.json        # legacy JSON runbooks (SD/MM/FI errors + T-codes)
├── mm/obyc-m8147.json
├── fi/fb350.json
└── tcodes/core-tcodes.json
```

## Document format

Markdown with YAML front-matter:

```yaml
---
domain: SD
subdomain: Pricing
module_type: FUNCTIONAL
topic: Condition Technique
system: S4HANA
version: S4HANA
verification: VERIFIED
source_type: verified_sap_fundamentals
related_domains: [MM, FI]   # optional
---
```

## Verification states

| State | Meaning |
|-------|---------|
| `VERIFIED` | reviewed against standard SAP customizing/transaction names (`verified_sap_fundamentals`) |
| `USER_PROVIDED` | supplied by the customer; valid for their system only |
| `INTERNAL_KNOWLEDGE` | internal runbooks/patterns, not SAP-official |
| `INFERRED` | conclusion derived from evidence by the consultant; never a verified SAP fact |
| `RECOMMENDED` | advisory suggestion by the consultant (plans/steps); never a verified SAP fact |
| `UNVERIFIED` | captured for investigation; never presented as fact |

The two Phase 1 states `INFERRED` and `RECOMMENDED` (spec §8) are produced by
the reasoning/planning layer — the validator never silently converts them
into verified SAP facts (hallucination control, spec §9).

## Content rules (hallucination prevention)

1. Never add an SAP Note / OSS number that was not personally opened in the
   SAP Support Portal. The validator flags any note number not present in
   the knowledge base.
2. Never add SPRO paths beyond standard IMG customizing names.
3. T-codes must be standard and widely known; the reason for trust belongs
   in the document.
4. Prefer describing mechanisms and verification steps over exact values
   that vary per system.

## Adding knowledge

1. Create `data/<area>/<domain>/<topic>.md` with front-matter.
2. Run ingestion (`python -m app.knowledge.ingestion.ingest`).
3. The retriever and keyword layers pick the document up automatically —
   no application code changes.

The domain keyword tables in `backend/app/knowledge/intent.py` are the only
place where a genuinely new domain needs a code change (keyword signals for
routing). Existing domains need nothing.
