# Bar Roster Weekly Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Wednesday-18:00-ET Hermes cron job on the Raspberry Pi that researches closes, additions, moves, renames, and stale labels against the active NYC gay-bar roster, and texts Norman one numbered digest via Photon, without ever touching the repo.

**Architecture:** Judgment stays in the model, mechanics stay in tested Python. A stdlib-only library (`bar_roster_lib.py`) owns roster loading, cohort selection, the nag state, digest rendering, and roster validation. Two thin entry points wrap it: `bar-roster-context.py` (the job's `script`, whose stdout becomes the run's context block) and `bar-roster-tool.py` (subcommands the agent and the reply turn call). The cron job researches and prints the digest text; the state file and the digest artifact are written by the deterministic renderer, not by the model. All repo writes happen later, in the reply turn, after Norman approves individual items.

**Tech Stack:** Python 3 stdlib only (`/usr/bin/python3`), Hermes cron (`cronjob_manage`), Photon sidecar delivery, git fast-forward sync, XCTest/Swift data invariants enforced by a Pi-side validator.

**Spec:** `docs/superpowers/specs/2026-10-12-bar-roster-weekly-monitor-design.md`

## Global Constraints

- **All Pi-side code lives in `~/.hermes/scripts/`.** The repo (`/home/normanman/repos/nyc_gay_bars_phone_app_xcode`) receives only this plan and the design doc. Never write Pi paths into the repo, never write repo code from the Pi.
- **Python 3 stdlib only**, run as `/usr/bin/python3`. No pip installs. `zoneinfo` is available.
- **The Pi cannot run `xcodebuild`** (Linux). Swift-side expectations are updated in the same commit and verified by `bar-roster-tool.py validate`; the real XCTest suite runs on the Mac.
- **The job never writes to the repo.** No exceptions, not even for a high-confidence closure. The job's run is research + one text.
- **Repo edits happen only in the reply turn**, after Norman approves numbered items.
- **`id` is a persistence key** in `@gaybars/visits` and `@gaybars/visited`. A LABEL changes `name` only. A MOVE keeps `id`. A revived venue under new operators is a new `id` (ADD + CLOSE, never a rename).
- **Archiving never deletes a record.** Set `"archived": true` and leave the row. Past visits must still resolve to a name in History.
- **Neighborhood invariants (anti-goal #4):** an active record's `neighborhood` must exist in `meta.json`, have a polygon in `neighborhoods.json`, and be present in exactly one of `Stats.swift`'s `brooklynHoods` / `queensHoods` / `bronxHoods`; anything unlisted silently counts as Manhattan and corrupts the boroughs badge. An ADD in a neighborhood the app lacks requires all four: new polygon (shapely pipeline per CLAUDE.md), `meta.json` entry, `neighborhoods.json` entry, borough set entry.
- **Tags** come from the fixed 15-value vocabulary: `bear cabaret cocktails country dance dive drag historic karaoke latin leather lesbian lounge piano sports`.
- **Evidence standard** is imported verbatim from `docs/nyc-bar-roster-audit-2026-08-20.md`: a missing or stale listing is not proof of closure.
- **Coexists with the user's pending data work.** The checkout is clean on `main` at the time of writing; the reply turn must `git pull --ff-only` and refuse to edit if the tree is dirty. Never overwrite uncommitted work, never create a commit Norman did not approve.
- **Delivery:** `deliver` is the existing Photon DM, derived from `~/.hermes/channel_directory.json` at creation time (`PHOTON_TARGET=$(python3 -c "import json;print('photon:'+json.load(open('$HOME/.hermes/channel_directory.json'))['platforms']['photon'][0]['id'])")`).
- **Schedule is host-local:** `timedatectl` reads `America/New_York`, so the cron expr is `0 18 * * 3`. First run: Wed 2026-10-14, ISO week 42 → cohort 2.
- **Do not pin the job's model.** It follows the main agent model by default; a pin is Norman's call, not the builder's.
- **The scheduler ticker and the Photon sidecar are children of the Hermes gateway.** No gateway, no text, silently. State this limit, do not engineer around it.
- **No `xcode` remote on the Pi.** `origin` is the same GitHub repo; `main` tracks `origin/main`. Push `origin main`.

## Review Focus

Five input classes and failure modes the spec implies but only some tasks' tests exercise directly, most likely to bite first:

1. **The Pi checkout is dirty or diverged when a run fires.** A reasonable person expects the run to say so rather than research a stale roster. Pinned in Task 5 (`test_context_refuses_dirty_checkout`, `test_context_reports_diverged_checkout`).
2. **State is missing, truncated, or written by an older schema.** A reasonable person expects the digest to still arrive, degrade to "no history", and never crash to silence. Pinned in Task 3 (`test_missing_state_is_empty_not_fatal`, `test_unknown_state_version_is_reported_and_ignored`).
3. **`bars.json` and `meta.json`/`neighborhoods.json` disagree** (a neighborhood with no polygon, or a polygon with no meta entry). A reasonable person expects a hard failure, not a 93rd bar silently counting as Manhattan. Pinned in Task 2 (`test_validator_flags_meta_polygon_mismatch`, `test_validator_flags_unclassified_neighborhood`).
4. **More than 8 candidate items.** A reasonable person expects the text to cap, say how many were withheld, and leave every printed number resolvable against the artifact. Pinned in Task 3 (`test_render_caps_at_eight_and_states_the_remainder`, `test_render_numbers_are_contiguous`).
5. **A newly archived bar is missing from `LogicTests.swift`'s pinned archived literal.** A reasonable person expects the forgotten test update to be caught before the push. Pinned in Task 2 (`test_validator_flags_archived_id_absent_from_swift_test`).

---

### Task 1: Roster loading, borough sets, and cohort selection

**Files:**
- Create: `~/.hermes/scripts/bar_roster_lib.py`
- Create: `~/.hermes/scripts/tests/test-bar-roster-lib.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `REPO: Path` (env `BAR_ROSTER_REPO` overrides; default `/home/normanman/repos/nyc_gay_bars_phone_app_xcode`)
  - `TAG_VOCAB: set[str]`, `NYC_BBOX: tuple[float, float, float, float]` (lat_min, lat_max, lon_min, lon_max)
  - `load_json(repo: Path, name: str) -> Any` — reads `NYCGayBars/Data/Resources/<name>.json`
  - `load_bars(repo: Path) -> list[dict]`, `active_bars(bars: list[dict]) -> list[dict]`, `archived_bars(bars: list[dict]) -> list[dict]`
  - `neighborhood_names(repo: Path) -> set[str]`, `polygon_names(repo: Path) -> set[str]`
  - `borough_sets(repo: Path) -> dict[str, set[str]]` — keys `"Brooklyn"`, `"Queens"`, `"Bronx"`; Manhattan is the implicit remainder
  - `cohort(active: list[dict], isoweek: int) -> list[dict]` — ids sorted, `index % 4 == isoweek % 4`

- [ ] **Step 1: Write the failing test**

Convention on this host: standalone test scripts with a `check(label, actual, expected)` helper, printing `ALL PASS` and exiting 1 on failure (see `~/.hermes/scripts/tests/test-nfl-pool-range.py`). Load the library with `importlib.util.spec_from_file_location`.

```python
# ~/.hermes/scripts/tests/test-bar-roster-lib.py
LIB = "/home/normanman/.hermes/scripts/bar_roster_lib.py"

def test_roster_shapes():
    bars = m.load_bars(m.REPO)
    active = m.active_bars(bars)
    archived = m.archived_bars(bars)
    check("93 records", len(bars), 93)
    check("84 active", len(active), 84)
    check("9 archived", len(archived), 9)
    check("splits are disjoint and complete", len(active) + len(archived), len(bars))
    check("archived all carry the flag", all(b.get("archived") is True for b in archived), True)

def test_borough_sets_parsed_from_swift():
    sets = m.borough_sets(m.REPO)
    check("brooklyn", "Williamsburg" in sets["Brooklyn"], True)
    check("brooklyn count", len(sets["Brooklyn"]), 7)
    check("queens", sets["Queens"], {"Astoria", "Jackson Heights"})
    check("bronx", sets["Bronx"], {"Mott Haven-Port Morris"})

def test_cohort_covers_everything_in_four_weeks():
    active = m.active_bars(m.load_bars(m.REPO))
    seen, sizes = set(), []
    for wk in range(4):
        c = m.cohort(active, 42 + wk)
        sizes.append(len(c))
        seen |= {b["id"] for b in c}
    check("every active bar checked once per 4 weeks", seen, {b["id"] for b in active})
    check("cohorts are equal-sized", sorted(sizes), [21, 21, 21, 21])
    check("no bar repeats within a cohort", len(m.cohort(active, 42)), len({b["id"] for b in m.cohort(active, 42)}))

def test_cohort_is_deterministic():
    active = m.active_bars(m.load_bars(m.REPO))
    check("same week, same cohort", [b["id"] for b in m.cohort(active, 42)], [b["id"] for b in m.cohort(active, 42)])

def test_repo_env_override(tmp=None):
    # BAR_ROSTER_REPO must be read at call time, not at import
    os.environ["BAR_ROSTER_REPO"] = "/tmp/nope"
    check("env override honored", str(m.resolve_repo()), "/tmp/nope")
    del os.environ["BAR_ROSTER_REPO"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-lib.py`
Expected: FAIL — `FileNotFoundError` on `bar_roster_lib.py`.

- [ ] **Step 3: Implement `bar_roster_lib.py`**

`borough_sets` reads `NYCGayBars/Logic/Stats.swift` and pulls the three literals off the `private static let <name>Hoods: Set = [...]` declarations with one regex per name (the Brooklyn literal wraps across two lines), returning python `set`s. It must raise `ValueError` naming the missing set if any of the three declarations is absent — a silently empty Brooklyn set would reclassify every Brooklyn bar as Manhattan.

`cohort` sorts by `id` and keeps `index % 4 == isoweek % 4`. Sorted-index modulo is used rather than a hash so that four consecutive weeks provably cover every active bar exactly once (asserted in Step 1) while staying deterministic for a fixed roster.

- [ ] **Step 4: Run test to verify it passes**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-lib.py`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

Pi-side scripts are not in a repo. No commit; the file is the deliverable.

---

### Task 2: Roster validator

**Files:**
- Modify: `~/.hermes/scripts/bar_roster_lib.py`
- Create: `~/.hermes/scripts/bar-roster-tool.py`
- Create: `~/.hermes/scripts/tests/test-bar-roster-validate.py`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces:
  - `validate_repo(repo: Path) -> list[str]` — empty list means valid; each entry is one human-readable violation naming the offending record
  - `pinned_archived_ids(repo: Path) -> set[str]`, `pinned_map(repo: Path) -> dict[str, tuple[str, str, str]]` — parsed from `NYCGayBarsTests/LogicTests.swift`
  - `bar-roster-tool.py validate [--repo PATH]` → prints violations, exits 1 if any

- [ ] **Step 1: Write the failing test**

Fixture-based: write a minimal repo tree into a `tempfile.TemporaryDirectory()` (a `Data/Resources/{bars,meta,neighborhoods}.json`, `Logic/Stats.swift`, `NYCGayBarsTests/LogicTests.swift`) and assert one violation per rule. The valid fixture must produce `[]`.

```python
# each case: build a valid fixture, break exactly one thing, assert the violation is reported
check("valid fixture has no violations", m.validate_repo(good), [])
check("duplicate ids", any("duplicate id" in v for v in m.validate_repo(bad_dup_ids)), True)
check("active neighborhood absent from meta", any("not in meta.json" in v, ...), True)
check("meta entry with no polygon", any("no polygon" in v for v in m.validate_repo(bad_meta_only)), True)
check("polygon with no meta entry", any("not listed in meta.json" in v for v in m.validate_repo(bad_poly_only)), True)
check("neighborhood unclassified by borough sets", any("no borough" in v for v in m.validate_repo(bad_unclassified)), True)
check("neighborhood in two borough sets", any("two borough" in v for v in m.validate_repo(bad_double)), True)
check("missing coordinates", any("missing latitude/longitude" in v, ...), True)
check("coordinates outside NYC", any("outside NYC" in v for v in m.validate_repo(bad_geo)), True)
check("tag outside vocabulary", any("unknown tag" in v for v in m.validate_repo(bad_tag)), True)
check("archived id absent from LogicTests.swift", any("absent from LogicTests" in v for v in m.validate_repo(bad_archived_unpinned)), True)
check("pinned id missing from bars.json", any("missing from bars.json" in v for v in m.validate_repo(bad_pinned_missing)), True)
check("pinned name/neighborhood/address drift", any("pinned" in v and "differs" in v for v in m.validate_repo(bad_pinned_drift)), True)
```

Two tests run against the real repo (they must pass as-is, before any data change):

```python
check("real repo validates clean", m.validate_repo(m.REPO), [])
check("all 9 real archived ids are pinned in the Swift test",
      m.pinned_archived_ids(m.REPO), {b["id"] for b in m.archived_bars(m.load_bars(m.REPO))})
```

Falling out of the second test: the parsed `pinned_archived_ids` must contain `mb-bar-boutique-closed-temporarily` or not, exactly as the file says — the parse is pinned by the real file, so a shape change in `LogicTests.swift` fails loudly here rather than silently disabling the check.

- [ ] **Step 2: Run test to verify it fails**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-validate.py`
Expected: FAIL — `validate_repo` not defined.

- [ ] **Step 3: Implement `validate_repo` and `bar-roster-tool.py validate`**

Rules, in this order, one violation string each: duplicate ids across all records → active neighborhood not in `meta.json` → `meta.json`/polygon set symmetric difference → neighborhood in zero or two borough sets → lat/lon missing or outside `NYC_BBOX` → tag not in `TAG_VOCAB` → archived id absent from the Swift pinned literal → pinned id absent from `bars.json` → pinned tuple drift.

`bar-roster-tool.py` dispatches on `sys.argv[1]`; `validate` prints one violation per line and exits 1 when the list is non-empty. Add a `fingerprint` subcommand now (`fingerprint <text>` → prints `fingerprint(text)`), because the prompt needs it in Task 6; keep the function in the library.

- [ ] **Step 4: Run test to verify it passes**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-validate.py`
Expected: `ALL PASS`, exit 0, including `real repo validates clean`.

- [ ] **Step 5: Verify the CLI end to end against the real repo**

Run: `/usr/bin/python3 ~/.hermes/scripts/bar-roster-tool.py validate`
Expected: no output, exit 0.

---

### Task 3: State, nag rules, and the digest renderer

**Files:**
- Modify: `~/.hermes/scripts/bar_roster_lib.py`
- Modify: `~/.hermes/scripts/bar-roster-tool.py`
- Create: `~/.hermes/scripts/tests/test-bar-roster-state.py`

**Interfaces:**
- Consumes: Task 1–2 interfaces.
- Produces:
  - `STATE_DIR: Path` (`~/.hermes/state/bar-roster-monitor`), `state_path(dir)`, `digest_dir(dir)`, `last_digest_path(dir)`
  - `load_state(dir: Path) -> dict` — `{"version": 1, "updated_at": str, "items": {slug: record}}`; missing file or unreadable JSON returns the empty state and appends a note to a module-level `warnings` list
  - `save_state(dir: Path, state: dict) -> None` (atomic: write `.tmp`, then `os.replace`)
  - `fingerprint(sources: str) -> str` — sha256 hex of lowercased, whitespace-collapsed text with trailing slashes stripped
  - `decide(record: dict | None, new_fingerprint: str, today: date) -> str` — `"report" | "suppress" | "collapse"`
  - `apply_report(state: dict, item: dict, today: date) -> dict` — mutates `times_reported`/`last_reported`/`first_reported`, returns the updated record
  - `render_digest(when: datetime, items: list[dict], active_count: int, cohort_size: int, withheld: int) -> str`
  - `write_digest(dir: Path, when: datetime, items: list[dict], rendered: str) -> dict` — writes `digests/YYYY-MM-DD.md` and `last-digest.json`, returns the number→item map
  - `bar-roster-tool.py` gains `state show`, `state record --file F`, `state seed`, `digest render --items F [--apply] [--when ISO]`

`item` fields the renderer consumes: `slug`, `kind` (`CLOSE|ADD|MOVE|LABEL|LOOK`), `venue_name`, `where` (neighborhood or address line), `evidence` (list of short strings, no URLs), `confidence` (`high|medium`), `flags` (list, e.g. `"needs a new neighborhood (map polygon + borough classification)"`, `"moves badge progress"`), `intended_action` (free text for the artifact).

- [ ] **Step 1: Write the failing test**

```python
# ~/.hermes/scripts/tests/test-bar-roster-state.py — all against a tempdir
def test_missing_state_is_empty_not_fatal():
    st = m.load_state(Path(tmp) / "nope")
    check("empty items", st["items"], {})
    check("version stamped", st["version"], 1)
    check("warning recorded", any("state" in w for w in m.warnings), True)

def test_unknown_state_version_is_reported_and_ignored():
    write(state.json, {"version": 99, "items": {"x": {}}})
    st = m.load_state(tmp)
    check("old items not trusted", st["items"], {})
    check("version reported", any("99" in w for w in m.warnings), True)

def test_corrupt_state_is_empty_not_fatal():
    write(state.json, "{not json")
    check("empty items", m.load_state(tmp)["items"], {})

def test_nag_rules():
    applied = {"disposition": "applied", "evidence_fingerprint": "aaa"}
    check("applied never reported", m.decide(applied, "bbb", today), "suppress")
    rejected = {"disposition": "rejected", "evidence_fingerprint": "aaa"}
    check("rejected, same evidence", m.decide(rejected, "aaa", today), "suppress")
    check("rejected, new evidence", m.decide(rejected, "bbb", today), "report")
    pending = {"disposition": "pending", "evidence_fingerprint": "aaa",
               "times_reported": 3, "last_reported": "2026-10-07"}
    check("pending, 3rd appearance collapses", m.decide(pending, "bbb", today), "collapse")
    pending2 = {"disposition": "pending", "evidence_fingerprint": "aaa",
               "times_reported": 1, "last_reported": "2026-10-07"}
    check("pending, reported last week", m.decide(pending2, "bbb", today), "suppress")
    pending3 = {"disposition": "pending", "evidence_fingerprint": "aaa",
                "times_reported": 1, "last_reported": "2026-09-23"}
    check("pending, two weeks quiet", m.decide(pending3, "bbb", today), "report")
    check("never seen", m.decide(None, "bbb", today), "report")

def test_fingerprint_normalizes():
    check("case and spacing ignored", m.fingerprint("A  B\n"), m.fingerprint("a b"))
    check("different sources differ", m.fingerprint("a b") == m.fingerprint("a c"), False)

def test_render_numbers_are_contiguous():
    text = m.render_digest(WHEN, items_5, 84, 21, 0)
    check("numbers 1..5", re.findall(r"^(\d+)\.", text, re.M), ["1", "2", "3", "4", "5"])

def test_render_caps_at_eight_and_states_the_remainder():
    text = m.render_digest(WHEN, items_11, 84, 21, 3)
    check("only 8 numbered items", len(re.findall(r"^\d+\.", text, re.M)), 8)
    check("remainder stated", "3 more" in text, True)

def test_render_empty_week_is_the_exact_contract():
    text = m.render_digest(WHEN, [], 84, 21, 0)
    check("says nothing new", text.startswith("NYC GAY BARS ROSTER"), True)
    check("names the check count", "84 active bars checked" in text, True)
    check("names the cohort", "cohort 21 re-verified" in text, True)
    check("says the repo is untouched", "untouched" in text, True)
    check("points at the next check", "Next check:" in text, True)
    check("NEVER silent", text.strip(), text.strip())  # and: never equals "[SILENT]"
    check("no SILENT token", "[SILENT]" in text, False)

def test_render_sections_are_ordered_and_headers_only_when_used():
    text = m.render_digest(WHEN, mixed_items, 84, 21, 0)
    order = [text.index(h) for h in ("CLOSE", "NEEDS YOUR LOOK", "ADD", "MOVE / LABEL")]
    check("section order", order, sorted(order))
    only_close = m.render_digest(WHEN, [close_item], 84, 21, 0)
    check("unused section omitted", "ADD" in only_close, False)

def test_render_has_no_urls():
    check("no http in the text", "http" in m.render_digest(WHEN, items_5, 84, 21, 0), False)

def test_write_digest_maps_numbers_to_slugs():
    mapping = m.write_digest(tmp, WHEN, items_3, text)
    check("keys are the printed numbers", sorted(mapping), ["1", "2", "3"])
    check("artifact written", (m.digest_dir(tmp) / "2026-10-14.md").exists(), True)
    check("cap 8 excludes the rest from the map", len(m.write_digest(tmp, WHEN, items_11, t)), 8)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-state.py`
Expected: FAIL — `load_state` not defined.

- [ ] **Step 3: Implement state, `decide`, and the renderer**

`decide` implements the spec's re-report rules exactly: applied → suppress; rejected → suppress unless the fingerprint changed; pending → suppress if reported within 14 days, collapse once `times_reported >= 3`, else report. A collapsed item keeps its number (the renderer emits one line for it, numbered like any other).

`render_digest` owns the whole skeleton — title line with the local date and time, the opening count line, section headers in the fixed order, numbering, the 8-item cap with the `N more in the notes` line, the closing line with active count / cohort size / `Repo untouched.`, and the `Next check:` line. The model supplies item bodies only. Sections with no items are omitted entirely.

`write_digest` writes the artifact and `last-digest.json` (`{"date", "delivered_at", "artifact", "items": {"<number>": {...}}}`), and `--apply` additionally records each item's fingerprint and `times_reported` into `state.json`.

- [ ] **Step 4: Run test to verify it passes**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-state.py`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Verify the renderer by eye against the spec's example**

Run: `/usr/bin/python3 ~/.hermes/scripts/bar-roster-tool.py digest render --items /tmp/sample-items.json --when 2026-10-14T18:00:00-04:00`
Expected: a text matching the shape in the spec's "The message" section.

---

### Task 4: Seed the nag state from the August audit

**Files:**
- Modify: `~/.hermes/scripts/bar_roster_lib.py`
- Modify: `~/.hermes/scripts/bar-roster-tool.py`
- Create: `~/.hermes/scripts/tests/test-bar-roster-seed.py`

**Interfaces:**
- Consumes: Task 3's state interfaces.
- Produces: `SEED_ITEMS: list[dict]` (`{slug, kind, venue_name, disposition, evidence_note}`) and `seed_state(dir: Path, today: date) -> dict`.

- [ ] **Step 1: Write the failing test**

```python
SEEDED = ["daves-lesbian-bar", "grotto", "hags", "4west-lounge", "macri-park",
          "club-lambda-brooklyn", "black-flamingo", "eve-ultra-lounge",
          "paddys-of-park-slope"]

def test_seed_covers_the_audits_rejections():
    st = m.seed_state(tmp, date(2026, 10, 14))
    for slug in SEEDED:
        check(f"{slug} seeded", slug in st["items"], True)
        check(f"{slug} rejected", st["items"][slug]["disposition"], "rejected")
        check(f"{slug} carries a fingerprint", bool(st["items"][slug]["evidence_fingerprint"]), True)

def test_seeded_items_are_not_reported_again():
    st = m.seed_state(tmp, date(2026, 10, 14))
    for slug in SEEDED:
        rec = st["items"][slug]
        check(f"{slug} suppressed", m.decide(rec, rec["evidence_fingerprint"], date(2026, 10, 14)), "suppress")

def test_seeded_items_air_again_on_new_evidence():
    rec = m.seed_state(tmp, date(2026, 10, 14))["items"]["daves-lesbian-bar"]
    check("new evidence reports", m.decide(rec, "different", date(2026, 10, 14)), "report")

def test_seed_is_idempotent():
    a = m.seed_state(tmp, date(2026, 10, 14))
    b = m.seed_state(tmp, date(2026, 10, 14))
    check("same items", sorted(a["items"]), sorted(b["items"]))
    check("no duplicate report counters", [r["times_reported"] for r in b["items"].values()], [r["times_reported"] for r in a["items"].values()])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-seed.py`
Expected: FAIL — `seed_state` not defined.

- [ ] **Step 3: Implement the seed table and `seed_state`**

Slugs and dispositions come from the audit's "Rejected or insufficient-evidence leads" table: `daves-lesbian-bar`, `grotto`, `hags`, `4west-lounge`, `macri-park`, `club-lambda-brooklyn`, `black-flamingo`, `eve-ultra-lounge`, `paddys-of-park-slope` — all `rejected`. The audit's four unchanged-but-uncertain roster records (`MB Bar Boutique`, `VV Bar & Kitchen`, `Alibi Lounge`, `PRIDE Bar & Lounge`) are **not** seeded: the job should surface them on evidence, and their current status is exactly what the sweeps are for.

Each seeded fingerprint is computed from a short fixed evidence note naming what the audit found, so the same evidence is suppressed and different evidence re-reports. `seed_state` merges rather than overwrites: an existing item's `disposition` and counters win.

- [ ] **Step 4: Run test to verify it passes**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-seed.py`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Seed for real and confirm**

Run: `/usr/bin/python3 ~/.hermes/scripts/bar-roster-tool.py state seed && /usr/bin/python3 ~/.hermes/scripts/bar-roster-tool.py state show`
Expected: 9 items, all `rejected`, `~/.hermes/state/bar-roster-monitor/state.json` on disk.

---

### Task 5: The context script

**Files:**
- Modify: `~/.hermes/scripts/bar_roster_lib.py`
- Create: `~/.hermes/scripts/bar-roster-context.py`
- Create: `~/.hermes/scripts/tests/test-bar-roster-context.py`

**Interfaces:**
- Consumes: Task 1–4 interfaces.
- Produces:
  - `sync_repo(repo: Path) -> tuple[str, str]` — returns `("ok"|"dirty"|"diverged"|"offline", detail)`; `ok` means the working tree was clean and a fast-forward pull succeeded or was unnecessary
  - `context_block(repo: Path, when: datetime, state_dir: Path) -> str`
  - `bar-roster-context.py` prints the block to stdout (this becomes the run's context) and always exits 0

- [ ] **Step 1: Write the failing test**

```python
def test_context_refuses_dirty_checkout():
    repo = git_fixture_with_uncommitted_edit()
    status, detail = m.sync_repo(repo)
    check("dirty detected", status, "dirty")
    check("detail names the file", "uncommitted" in detail, True)
    block = m.context_block(repo, WHEN, tmp_state)
    check("block tells the model not to trust the roster", "NOT VERIFIED AGAINST origin/main" in block, True)

def test_context_reports_diverged_checkout():
    repo = git_fixture_diverged()
    check("diverged detected", m.sync_repo(repo)[0], "diverged")

def test_context_reports_offline():
    repo = git_fixture_with_dead_remote()
    check("offline detected", m.sync_repo(repo)[0], "offline")

def test_context_block_contents():
    block = m.context_block(m.REPO, WHEN, seeded_state)
    for needed in ("ROSTER:", "ACTIVE:", "ARCHIVED IDS:", "COHORT THIS WEEK (21 bars)",
                   "STATE:", "SUPPRESSED (do not re-report unless evidence changed):",
                   "ARTIFACT DIR:", "REPO:"):
        check(f"block has {needed}", needed in block, True)
    check("cohort count matches", block.count("cohort-line"), 21)
    check("all 84 active bars listed", len(re.findall(r"^- ", block, re.M)) >= 84, True)

def test_context_block_states_the_sync_result():
    block = m.context_block(m.REPO, WHEN, tmp_state)
    check("sync status present", "SYNC: ok" in block, True)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-context.py`
Expected: FAIL — `sync_repo` not defined.

- [ ] **Step 3: Implement `sync_repo` and `context_block`**

`sync_repo` runs `git status --porcelain` (dirty), `git fetch origin` (offline on non-zero), then compares `main` against `origin/main` with `git rev-list --left-right --count` — ahead-and-behind or behind-with-local-commits is `diverged`; behind-only is fast-forwarded with `git merge --ff-only origin/main`. No `git reset`, no `git stash`, no `git checkout` — a dirty tree is reported, never cleaned.

`context_block` emits, in order: the run timestamp in `America/New_York` with the weekday and ISO week, `SYNC:`, `REPO:`, `ARTIFACT DIR:`, `ROSTER:` counts, the 84 active bars as one compact line each (`id | name | neighborhood | address`), `ARCHIVED IDS:` (so the model never proposes one it may not re-open), `COHORT THIS WEEK (N bars):` with the same compact lines, `STATE:` with per-disposition counts, and the suppressed slugs with their dispositions. No URLs, no JSON blobs, no nesting.

- [ ] **Step 4: Run test to verify it passes**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-context.py`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Run it for real**

Run: `/usr/bin/python3 ~/.hermes/scripts/bar-roster-context.py`
Expected: the block on stdout, `SYNC: ok`, 84 active lines, cohort 2's 21 bars, the seeded state summary. Exit 0.

---

### Task 6: The cron prompt

**Files:**
- Create: `~/.hermes/scripts/bar-roster-prompt.txt`
- Modify: `~/.hermes/scripts/bar-roster-tool.py`
- Create: `~/.hermes/scripts/tests/test-bar-roster-prompt.py`

**Interfaces:**
- Consumes: the tool subcommands from Tasks 2–4 (`fingerprint`, `digest render`, `state record`) and the context block from Task 5.
- Produces: `check_prompt(text: str) -> list[str]` (empty = acceptable) and `bar-roster-tool.py check-prompt [PATH]`.

- [ ] **Step 1: Write the failing test**

```python
# ~/.hermes/scripts/tests/test-bar-roster-prompt.py
PROMPT = Path("/home/normanman/.hermes/scripts/bar-roster-prompt.txt")

def test_prompt_passes_its_own_checker():
    check("no violations", m.check_prompt(PROMPT.read_text()), [])

def test_checker_reports_every_mandatory_phrase_when_absent():
    text = PROMPT.read_text()
    for phrase in m.REQUIRED_PROMPT_PHRASES:
        check(f"present: {phrase}", m.check_prompt(text), [])
        check(f"flagged when removed: {phrase}",
              [v for v in m.check_prompt(text.replace(phrase, "REMOVED")) if phrase in v] != [], True)
```

`REQUIRED_PROMPT_PHRASES` is the module constant the checker iterates, so the test and the checker cannot drift apart.

- [ ] **Step 2: Run test to verify it fails**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-prompt.py`
Expected: FAIL — prompt file missing, `check_prompt` not defined.

- [ ] **Step 3: Write `bar-roster-prompt.txt` and `check_prompt`**

House style matches `~/.hermes/scripts/events-research-prompt.txt`: an opening line naming the task and the repo path, a line that the briefing is included above, then ALL-CAPS sections of terse rules. Required content, which `check_prompt` enforces by substring:

1. **Scope** — the four kinds plus `NEEDS YOUR LOOK`; the job proposes, never acts; repo is read-only, and naming that violation explicitly.
2. **The evidence bar** — the phrase `not proof of closure`; the operation list; the four gates; `TWO INDEPENDENT SOURCES`; a date is required; the positive-direction cross-check; temporary is not permanent.
3. **Inclusion rule for ADD** — verbatim from the audit (LGBTQ-focused, or sustained queer programming; gay-popular or a one-off event does not qualify).
4. **Three legs** — news sweep, additions sweep, cohort re-verification, in that order.
5. **Sources** — first-party, NYC queer press, neighborhood newsletters, event calendars, government records; the `agent-reach` CLI and `blocked-page-recovery` skill for blocked first-party pages; unreadable sources are reported as not independently verified.
6. **Output contract** — write candidates to `incoming.json`, then run `bar-roster-tool.py digest render --items <path> --apply`; the final response must be **exactly** the printed text, verbatim, because the printed text is what gets delivered; never hand-write the digest or the closing lines; `[SILENT]` is FORBIDDEN and a run with nothing to report still sends the empty-week text.
7. **Nag rules** — the `SUPPRESSED` list is not re-reported unless the evidence changed; run `bar-roster-tool.py fingerprint` on the new evidence to check.
8. **Caps and format** — 8 items, no URLs, one line of confidence per item, sections in order.
9. **Flags that must appear in the item body** — `needs a new neighborhood (map polygon + borough classification)` for an ADD outside the 19; `moves badge progress` for a MOVE that crosses a neighborhood or borough line.
10. **Failure honesty** — if a source cannot be read, say so in the item; if the briefing says the checkout is not verified against `origin/main`, say that in the text instead of presenting findings from a possibly stale roster.

`check_prompt` returns one violation string per absent mandatory phrase; the required phrase list is a module constant so the test and the checker cannot drift.

- [ ] **Step 4: Run test to verify it passes**

Run: `/usr/bin/python3 ~/.hermes/scripts/tests/test-bar-roster-prompt.py`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Read the prompt end to end and check it against the spec's taxonomy**

Read `~/.hermes/scripts/bar-roster-prompt.txt` next to the spec's "Defending against a false closure", "The weekly run", and "The message" sections. Every rule there must appear as a rule here; anything missing is a bug in the prompt, not an oversight in the spec.

---

### Task 7: Create the cron job and prove the delivery path

**Files:**
- No files created. Configures the existing runtime.

**Interfaces:**
- Consumes: `bar-roster-context.py` (Task 5), `bar-roster-prompt.txt` (Task 6).
- Produces: a live cron job whose id is recorded in the skill (Task 8).

- [ ] **Step 1: Confirm the target and the schedule facts**

Run: `timedatectl | head -3` and `python3 -c "import json;print('photon:'+json.load(open('$HOME/.hermes/channel_directory.json'))['platforms']['photon'][0]['id'])"`
Expected: `America/New_York`; a `photon:any;-;+1…` target. The target is derived into a shell variable and reused, never retyped.

- [ ] **Step 2: Prove the model the job will use is reachable**

The job follows the main agent model unless pinned. Run one live one-shot: `hermes -z "Reply with exactly: OK"` and confirm it prints `OK`. A pin is not created here; if this call fails, stop and report rather than creating a job that reports success and delivers nothing.

- [ ] **Step 3: Create the job**

`cronjob_manage` with `action=create`:
- `name`: `NYC bar roster monitor (Wed 6:00 PM NYC)`
- `schedule`: `0 18 * * 3`
- `prompt`: the exact contents of `~/.hermes/scripts/bar-roster-prompt.txt`
- `script`: `bar-roster-context.py`
- `deliver`: the derived Photon target
- `attach_to_session`: `true` — the digest must be reply-able, so Norman's "1 yes, 2 no" lands in the same conversation with the brief in context
- `enabled_toolsets`: `["web", "terminal", "file", "skills"]`
- `continuity`: `false` (state lives in `state.json`, not in the previous output)
- `no_agent`: `false`

Do **not** pass `pinned`.

- [ ] **Step 4: Verify the SAVED job, not the create summary**

Run: `python3 -c "import json;d=json.load(open('$HOME/.hermes/cron/jobs.json'));[print(json.dumps({k:j.get(k) for k in ('id','name','script','deliver','enabled_toolsets','attach_to_session','no_agent','schedule')},indent=2)) for j in d['jobs'] if j['name'].startswith('NYC bar roster')]"`
Then compare the stored prompt length against the file: `wc -c ~/.hermes/scripts/bar-roster-prompt.txt` versus `len(record['prompt'].encode())` — expect the stored size a few bytes under the file (a trailing newline is stripped by `"$(cat file)"`).

Expected: `script=bar-roster-context.py`, the Photon target, `attach_to_session: true`, expr `0 18 * * 3`, `next_run_at` on a Wednesday at 18:00 ET.

- [ ] **Step 5: Fire one real run and read what actually landed**

Run: `cronjob_manage` with `action=run` (returns a handle immediately — do not poll). When the outcome returns, check delivery separately from run status:

`python3 -c "import sqlite3,os;c=sqlite3.connect(os.path.expanduser('~/.hermes/cron/executions.db'));print(c.execute('select job_id,status,delivery_outcome from executions order by rowid desc limit 3').fetchall())"`

Expected: `status=completed` and `delivery_outcome` in (`delivered`, `queued`). Then read the delivered text from `~/.hermes/cron/output/<job id>/` and confirm it matches the spec's shape, that the artifact exists under `~/.hermes/state/bar-roster-monitor/digests/`, that `last-digest.json` maps its numbers, and that `state.json` picked up the reported items with fingerprints.

A run whose text is thin or whose items ignore the evidence bar is a **prompt** problem: fix Task 6 and re-run. Do not paper over it by editing state.

- [ ] **Step 6: Report the outcome with the real evidence**

State the job id, the stored schedule, the first real `next_run_at`, the delivery outcome row, and the verbatim text that arrived. If anything in that chain is missing, say which step failed rather than reporting the job as working.

---

### Task 8: Reply-turn skill and prompt visibility

**Files:**
- Create: `~/.hermes/skills/automation/nyc-bar-roster-monitor/SKILL.md`

**Interfaces:**
- Consumes: the job id from Task 7, the tool subcommands, the validator.
- Produces: the documented reply-turn procedure.

- [ ] **Step 1: Write the skill**

Frontmatter: `name: nyc-bar-roster-monitor`, `description: "Use when Norman replies to the weekly NYC bar-roster digest text, or when maintaining that monitor job."` Body sections:

- **What it is** — the job id, the schedule, the digest artifact and `last-digest.json` paths, the state dir.
- **The reply turn, in order:** read `last-digest.json` (fall back to the newest `digests/*.md` if it is missing) → map Norman's numbers to items → `git -C <repo> status --porcelain` and `git pull --ff-only`; **stop and report if the tree is dirty** → `bar-roster-tool.py validate` before editing, so a pre-existing violation is not misattributed → apply each approved item → `bar-roster-tool.py validate` again → commit and `git push origin main` → mark the items `applied` in `state.json` via `bar-roster-tool.py state record` → confirm to Norman in one short message.
- **Applying each kind:** CLOSE sets `"archived": true` and updates the pinned archived literal in `NYCGayBarsTests/LogicTests.swift`; ADD geocodes from OpenStreetMap (never an aggregator), uses a lowercase-hyphen slug unique against all records including archived, tags from the 15-value vocabulary, and needs the four-step neighborhood build when the neighborhood is new; MOVE updates address/lat/lon, re-derives the neighborhood by point-in-polygon, and updates the pinned tuple; LABEL updates `name` only and never `id`.
- **Pitfalls, each earned:** a pin just outside its neighborhood ring may be a deliberate override (BASEMENT NY, Sandy Jack's) — do not "fix" it; `Stats.borough()` falls through to Manhattan for an unknown neighborhood, so a missing borough-set entry is silent corruption, not a visible error; the `id` is the persistence key in `@gaybars/visits`, so renaming one orphans visit history; the app bundles the JSON at build time, so a push does not change the phone until a rebuild; `xcodebuild` runs on the Mac only.
- **Verification before claiming it works:** `validate` clean, the pinned expectations updated, the commit pushed (`git rev-list --left-right --count main...origin/main` reads `0 0`), and — after his next Mac build — the XCTest suite green.
- **Maintenance:** changing the schedule or prompt, re-seeding state, and the gateway dependency (no gateway, no text).

- [ ] **Step 2: Verify the skill loads**

Run: `skill_view(name="nyc-bar-roster-monitor")`
Expected: the full body. If not found, the file path or frontmatter name is wrong.

- [ ] **Step 3: Make it visible to the gateway sessions**

A new skill is invisible to existing sessions until their prompts are repaired and the gateway restarts. Run `hermes sessions repair-prompts <id> --apply` for the Photon DM session, then `systemctl --user restart hermes-gateway`, then confirm the gateway is back with `systemctl --user is-active hermes-gateway`.
Expected: `active`. State plainly that the repair applies to the sessions repaired now; other sessions pick the skill up on their next prompt build.

- [ ] **Step 4: Confirm the loop end to end**

Ask Norman to reply to the Task 7 digest with a "no" for one item. Confirm: the reply arrives as a turn in the Photon session, the skill is in context, the item flips to `rejected` in `state.json`, no repo change is made, and the next digest does not re-report it.

---

## Self-Review

**Spec coverage.** Every spec section maps: shape → Tasks 5–8; goals/non-goals/anti-goals → the evidence bar and gates in Task 6, the nag rules in Tasks 3–4, the neighborhood invariants in Tasks 1–2; the four gates → Task 6 rules 2 and its checker; taxonomy → Task 3's `kind` handling and Task 8's apply procedure; inclusion rule → Task 6 rule 3; the weekly run's three legs and sources → Task 6 rules 4–5 and the cohort in Tasks 1/5; the message → Task 3's renderer with its exact empty-week test; not nagging → Tasks 3–4; constraints → Global Constraints and Tasks 5, 7; verification of an approved change → Task 2's validator plus Task 8's ordering; decisions and left-to-builder → the plan's tasks fill each one.

**Gaps found and closed.** The spec left the reply turn's home open; Task 7's `attach_to_session: true` plus Task 8's skill close it. The spec's "run the suite before pushing" cannot run on the Pi; Task 2's validator is what makes that half-real, and Task 8 states the Mac-side half. The spec does not mention that `bars.json` carries no venue website; Task 6's source rules make the model find first-party pages by search, which is the consequence.

**Type consistency.** `validate_repo`, `sync_repo`, `context_block`, `load_state`, `decide`, `render_digest`, `write_digest`, `fingerprint`, `seed_state`, `cohort`, `borough_sets`, `pinned_archived_ids`, `pinned_map`, `check_prompt` are used with one spelling and one signature throughout. `STATE_DIR`/`digest_dir`/`last_digest_path` are the only path helpers any task calls.

**Review Focus closed.** All five lines name the task and test that pins them.

**Proportion.** The plan's code is the test assertions and the interfaces; bodies are specified only where the tests do not determine them (`borough_sets`' regex, `decide`'s thresholds, `sync_repo`'s git sequence, the renderer's skeleton).
