# ABAP Analysis

VAYRA's ABAP consultant combines **deterministic static analysis** with LLM
reasoning. The analyzer produces evidence; the LLM explains, prioritizes,
and drafts corrections. The LLM never silently modifies user code — original
and suggested code are always separated.

## Input types

- ABAP source code (reports, classes, forms)
- Code snippets
- ST22 dump text (pasted)
- Performance problem descriptions
- Any consultant request containing recognizable ABAP constructs

The intent router detects ABAP code (`REPORT`, `SELECT`, `LOOP AT`, `DATA(...)`,
…) and dump names (`UPPER_SNAKE_CASE` runtime-error style) and activates the
analyzers automatically. Mode `ABAP` forces the ABAP consultant.

## ABAPAnalyzer (deterministic rules)

| Rule | Meaning | Default risk |
|------|---------|--------------|
| `select_star` | full-field read without `UP TO n ROWS` bound | medium |
| `fae_no_guard` | `FOR ALL ENTRIES` without emptiness guard on the driver table | high |
| `nested_loops` | multiple `LOOP AT` over tables — quadratic pattern | medium |
| `delete_in_loop` | `DELETE` while looping | high |
| `select_single_no_where` | `SELECT SINGLE` without full key restriction | high |
| `package_size` | memory/commit-scope tradeoff to verify | low |
| `unfiltered_read` | read on a known high-volume table without `WHERE` | medium |

Context matters: a `SELECT *` over a small config table with full field
consumption is acceptable. The analyzer flags; the consultant weighs —
assumed data volume is always stated as an assumption (spec §27: do not
blindly call every `SELECT *` incorrect).

## ST22Parser

Extracts from pasted dump text: runtime error, exception, program, include,
line, error message, transaction, user. Reports:

- `missing_sections` — fields not present in the extract
- `insufficient_evidence` — true when ≥4 sections are missing

Insufficient evidence is surfaced honestly: the consultant asks for the full
dump instead of fabricating details (spec §18).

## Debugging / performance workflow

The debugging toolbox knowledge document (`technical/debugging/toolbox.md`)
grounds tool recommendations (ST22, ST05, SAT, SM37, SM21, SLG1, SU53, ST01,
SE38/SE80/SE24, SE11/SE16N, ATC). The consultant names the tool, the reason,
and the expected evidence — only tools present in the verified catalog.

## Extending

- New analyzer rule: add a check in `backend/app/abap/analyzer.py` + tests
  (`tests/test_abap_analyzer.py`).
- New dump field: extend `ST22Parser._PATTERNS` and the
  `ST22Analysis` schema in `consultant_models.py`.
- Known high-volume tables: pass `known_tables` to `ABAPAnalyzer`.
