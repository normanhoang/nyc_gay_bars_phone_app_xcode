# NYC gay-bar roster monthly monitor — design

Date: 2026-10-12
Revised: 2026-10-14 — cadence changed from every Wednesday to the first Wednesday of each
month (Norman's call). Roster counts below are as of the original date.
Topic: monthly cron monitor for bar closures, additions, moves, renames, and stale labels
Repo: `nyc_gay_bars_phone_app_xcode` (remote `xcode`, branch `main`)
Evidence standard inherited from: `docs/nyc-bar-roster-audit-2026-08-20.md`

## Intent and the why

The roster in `NYCGayBars/Data/Resources/bars.json` only changes when Norman happens to
hear about it — word of mouth or social media — and then decides to archive or add a
record. The August 2026 audit proved the work is doable but it was a one-off manual pass:
83 records checked by desk research, candidates written up with sources, zero data changes
made until he confirmed. The roster is now 93 records (84 active, 9 archived) and the last
refresh was 2026-08-22.

This project replaces "he happened to hear about it" with a monthly automated noticing pass
that reaches him as a text message he can act on from his phone.

The app is a personal tracker, not a directory, so the failure that costs the most is
listing a bar he cannot visit. That is what this design optimizes against: **calling a live,
operating bar closed.**

## Shape

A Hermes cron job on the Raspberry Pi, first Wednesday of each month, 18:00
America/New_York, that:

1. runs a research pass over the active roster and the NYC queer-venue landscape,
2. writes every finding, with sources, to an artifact file on the Pi,
3. delivers the digest to Norman's phone via Photon as a short series of texts, one per item,
   every month, including months with nothing to report,
4. stops there. The job never touches the repo.

Norman replies to the text ("1 yes, 3 no"). That reply arrives as an ordinary agent turn in
the routed Photon DM session on the Pi (verified: `agent:main:photon:dm:any;-;+171…9010`
resolves to a live session), which reads the digest artifact, does the data work (geocode,
neighborhood, tags, ids, archive flags), then commits and pushes to `main` on `origin`. Human
judgment is the gate on every change; the automation only does the noticing and the typing.

## Goals

- Surface real closures of bars on the active roster, with defensible evidence and a date.
- Surface qualifying NYC queer venues that are not on the roster yet.
- Surface moves, renames, and stale display labels on active records.
- Deliver readable digest texts on the first Wednesday of every month, including empty months.
- Keep the false-closure rate at effectively zero, even at the cost of missing a real one.
- Once Norman approves, land the change on `main` with no further ceremony.

## Non-goals

- No automatic repo changes. Ever. Not even a high-confidence closure.
- Not a complete re-audit of all 84 bars every month (see the cohort rotation under "The
  monthly run" — every bar still gets eyes, just on a cycle).
- Not a review of the 9 archived records, or of whether archived records should come back.
- Not a re-litigation of the inclusion rule for existing records (e.g. whether House of YES
  really belongs) — that was explicitly out of scope in the August audit and stays out.
- No legal/permit forensics beyond what is needed to corroborate a closure or opening.

## Anti-goals — how this project fails

Listed most important first, because the ordering is the design.

1. **A live bar gets called closed.** Norman archives an operating venue, stops going, or
   loses trust in the texts. This is the failure to defend against hardest.
2. **It nags.** The same six candidates every month because the research keeps
   re-finding the same listings. He stops reading the texts even though they still arrive.
3. **It goes quiet.** The job dies, or the text arrives with findings that were never
   verified, and the silence is indistinguishable from a clean month.
4. **It drifts.** A bad geocode or an unlisted neighborhood silently counts a bar as
   Manhattan, which corrupts the boroughs badge rather than failing loudly.

## Defending against a false closure

This is the heart of the design. The rules below are part of the job's prompt, not
aspirations.

### What counts as evidence a bar is still operating

Any current, dated, operational signal:

- first-party hours/events page with a date in the last ~90 days
- a scheduled event carrying a **future** date at that venue
- recent independent reporting that describes it as operating
- a current government record (liquor-permit renewal, inspection, community-board item)

### What is NOT evidence of closure — never, on its own

- a missing or stale listing on a directory
- a venue website that has not been updated
- social media going quiet
- a maps/directory "closed" badge (means closed *at query time*, per the August audit's own
  note on The Rosemont)
- no events on the calendar on a given night
- an aggregator's or a single community post's closure claim
- a stale address or a rebrand that looks like disappearance
- anything sourced only from a page the job could not actually read

The August audit's method line governs: **a missing or stale listing is not proof of
closure.**

### The four gates a closure must pass to appear in the CLOSE section

1. **Two independent sources**, and at least one is first-party (the venue or its operators
   saying so) or an authoritative dated closure record from an outlet that covers venues.
2. **A date.** The claim carries the closing date if one exists, and the publication date of
   each source. A source older than about six months is not current evidence.
3. **A positive-direction cross-check.** Before proposing a closure, the job actively looks
   for a current operational signal (above). If one exists, the closure is **not** a CLOSE
   item — it becomes a CONFLICT item for Norman to adjudicate, with both sides and their
   dates shown.
4. **Temporary is not permanent.** "Temporarily closed", "closed for renovations", or a
   planned move never appears in CLOSE. It is at most a label or move item.

Anything that passes 1–2 but fails to be clean on 3–4 goes to a separate **NEEDS YOUR LOOK**
section, phrased as a conflict, never as a finding.

### Structural guards

- The job is **read-only** on the repo. `archived` is only set in the reply turn, by Norman's
  approval.
- **Zero closures is the expected outcome most months.** The prompt states that a run
  reporting no closures is a successful run, so the model has no incentive to find one.
- Archiving **never deletes** a record. The row stays decodable so past visits still resolve
  to a name in History (the existing `archived: true` mechanism).
- A closure item names the venue, the source, and the date — no "reports suggest".

## Findings taxonomy

Four kinds, each with an intended data action:

| Kind | Trigger | Action when approved |
|---|---|---|
| **CLOSE** | passes all four closure gates | set `"archived": true` on the existing record |
| **ADD** | a qualifying venue absent from `bars.json` | append a new record with a new id |
| **MOVE** | operating, but at a different address | update `address`/`latitude`/`longitude` **and re-derive `neighborhood`**, keep id |
| **LABEL** | operating, but the name or display text is stale | update `name`, **never** the id |

Every approved change to `bars.json` is accompanied by an update to the pinned expectations
in `NYCGayBarsTests/LogicTests.swift` (`testArchivedBarsResolveForHistoryButStayOutOfActiveRoster`
pins the archived id list; `testApprovedRosterChangesAreActive` pins id → name, neighborhood,
address for the recently approved records). A data change that leaves those stale is an
incomplete change. See "Verification" for what can and cannot be run on the Pi.

### A MOVE that crosses a neighborhood or borough line

`neighborhood` is re-derived from the new address, not left alone. This is a visible event,
not a detail: `neighborhood` drives filtering and badge progress, and moving a bar across a
borough line changes the boroughs badge. The digest item says so in as many words, so a MOVE
is never approved as "just an address fix".

Point-in-polygon against `neighborhoods.json` decides it, with one standing exception: an
explicit user override is allowed when the pin falls just outside its neighborhood, the way
BASEMENT NY → Williamsburg and Sandy Jack's → Park Slope already do. An override is stated in
the digest item.

### An ADD in a neighborhood the app does not have yet

The roster covers 19 neighborhoods. A qualifying venue can legitimately land outside all of
them (Greenpoint, Fort Greene, LIC, Ridgewood). When that happens the neighborhood is built
**properly**, as part of that approval:

1. a new simplified polygon from NYC's Neighborhood Tabulation Areas / Pediacities GeoJSON,
   through the existing shapely pipeline (buffer(0) → unary_union/difference → simplify →
   set_precision → largest exterior ring) that CLAUDE.md documents;
2. the name added to `meta.json`'s `neighborhoods` list;
3. the polygon added to `neighborhoods.json`;
4. the name added to the right set in `Stats.borough()` (`brooklynHoods`, `queensHoods`, or
   the Bronx set).

Skipping any of the four is the anti-goal #4 failure: an unlisted neighborhood silently counts
as Manhattan and corrupts the boroughs badge. Because this is a materially bigger job than a
one-line ADD, **the digest item says so on its face** — "needs a new neighborhood (map
polygon + borough classification)" — so it is never approved by surprise.

MOVE and LABEL keep the existing id on purpose: `id` is the persistence key in
`@gaybars/visits` and `@gaybars/visited`, so renaming an id orphans visit history. The one
exception is a revived venue under new operators where the roster's identity no longer
describes it (the Club Rawhide case) — that is a **new record with a new id**, and it is
presented to Norman as an ADD plus a CLOSE, not as a rename.

## The inclusion rule for ADD

Inherited verbatim from the August audit, and it stays the bar:

> A venue qualifies when it is explicitly LGBTQ-focused, **or** a general venue with
> sustained queer-focused programming. "Gay-popular", a one-off event, or a welcoming
> framing does not qualify.

No dedicated qualifying venue has been found in Staten Island; a gay-popular general bar
there does not qualify.

## The monthly run

Three legs, each producing candidates. The prompt runs them in this order.

**Leg A — roster news sweep (closures, moves, renames, labels).** Scan current NYC queer
press, event calendars, and neighborhood newsletters for any signal touching one of the 84
active records. This is the leg that catches real closures, and it is driven by news rather
than by re-checking each bar.

**Leg B — additions sweep.** Look for qualifying venues not in `bars.json`: recent openings,
recently resurfaced concepts, longstanding venues the roster missed.

**Leg C — cohort re-verification.** A quarter of the active bars (21 of 84 at writing),
rotating, so the whole roster is re-checked every four months. This is what catches a stale
address or a dead website when no news exists. The cohort is chosen deterministically from the
roster order by a month counter, not by the model, and the script names it in the context
block. (Not the ISO week: it advances by 4 or 5 between first Wednesdays, so week % 4 would
re-check the same cohort two months running.)

### Sources

Priority order: first-party venue pages and event calendars → NYC queer press and closure
reporting (Gay City News, Eater NY, Time Out, W42ST, The Village Sun, BK Reader, Bronx
Times, amNY) → neighborhood newsletters (W42ST for Hell's Kitchen, EV Grieve for the East
Village/LES, Astoria Post / Jackson Heights Post / Queens Post, Brooklyn Paper, Bronx Times)
→ community event listings (Thotyssey, gayout, thegaycalendar, OutXOut, GayCities) →
government records (SLA permits, DOHMH inspections, community-board filings).

Instagram and other bot-walled first-party sources are a known gap: the August audit could
not read them. When a first-party source is blocked, try the `agent-reach` CLI
(`~/.agent-reach-venv/bin/agent-reach`); if it is still unreadable, record the item as
"not independently verified" and say so in the digest rather than implying it was read.

## The message

The digest goes out as a short series of texts, one per item, in send order (Norman's call
on 2026-10-12: "list the bar/decision per text bubble"). The first text carries the header and
the reply hint, each item gets its own text with its section label on top, and the last text
carries the closing counts. Sections run in this order: CLOSE, NEEDS YOUR LOOK, ADD,
MOVE / LABEL. Numbering runs across the whole series, so "1 yes, 3 no" resolves the same way
it would against a single message.

The iMessage sidecar has no multi-bubble send, so each text is one POST. The script
(`bar-roster-tool.py digest send`) renders the texts, writes the number → item map to
`last-digest.json` and sends them, all in one deterministic step. The text that went out and
the map the reply resolves against are therefore one product. The job's own delivery target
is `local`, so the run's receipt ("Sent 6 text(s) to photon - 4 item(s) to answer, cap 8.") lands in a
file instead of becoming a duplicate text.

Example, as rendered by `bar_roster_lib.render_bubbles()`:

```
--- text 1
NYC GAY BARS ROSTER - Wed Nov 4, 6:00 PM

4 items need your call. Reply like "1 yes, 2 no" and I'll do the rest.
--- text 2
CLOSE (archive, keep row for history)
1. VV Bar & Kitchen - Chelsea
   W42ST + GayTravelr both list closed; venue site's last
   event is Jun 2025.
   Confidence: high.
--- text 3
NEEDS YOUR LOOK (conflicting evidence, not acted on)
2. Alibi Lounge - Harlem
   Eater venue page says permanently closed; a Jun 2024
   license renewal is the only contrary signal.
--- text 4
ADD (new record, geocoded)
3. Dave's Lesbian Bar - 116 MacDougal St, West Village
   Site now lists a permanent address and hours; was
   pop-up only in the Aug audit.
   Confidence: high.
--- text 5
MOVE / LABEL
4. Rawhide -> Club Rawhide - 250 W 26th St
   New operators under the old name.
   Confidence: high.
--- text 6
Repo untouched. 84 active bars checked, cohort 21 re-verified.
Next check: Wed Dec 2.
```

Rules for the texts:

- Hard cap of 8 items; the rest stay in the artifact file and the header text says how many.
- No URLs in the texts, outlet names only. Full sources, with URLs and dates, go in the
  artifact.
- The last text always states the roster size, how many bars were checked, that the repo is
  untouched, and the next check date, so an empty month and a broken month are
  distinguishable.
- **The texts are sent even when there is nothing to report.** `[SILENT]` is explicitly
  forbidden in the prompt.

Empty-month form (three texts):

```
--- text 1
NYC GAY BARS ROSTER - Wed Dec 2, 6:00 PM
--- text 2
Nothing new. No closure, addition, move, or stale label met the
evidence bar this month, and the sweep for unlisted venues found
nothing qualifying.
--- text 3
Repo untouched. 84 active bars checked, cohort 21 re-verified.
Next check: Wed Jan 6.
```

## Not nagging

The job keeps state at `~/.hermes/state/bar-roster-monitor/`:

**Seeded on day one, not started empty.** The August audit already adjudicated a pile of items
the sweeps will re-find: rejected leads (Dave's Lesbian Bar, Grotto, HAGS, 4West Lounge, Macri
Park, Club Lambda, Black Flamingo, every Staten Island lead) and open status questions already
sitting on the roster. State is pre-seeded from that audit with each item's evidence
fingerprint, so the first run does not re-surface all of it as fresh news. Because the fingerprint
is part of the record, a rejected lead whose evidence has since changed (Dave's Lesbian Bar
publishing a permanent address, say) still gets one fresh airing.

- `state.json` — one record per venue ever surfaced: `{venue_id_or_slug, kind, first_reported,
  last_reported, times_reported, disposition, evidence_fingerprint}`. `disposition` is
  `pending`, `rejected`, or `applied`. `evidence_fingerprint` is a normalized hash of the
  source set (domain + date + claim), so "same sources again" is detectable.
- `last-digest.json` — the item list from the most recent text: number → venue, kind,
  evidence, intended action, artifact path. This is what makes a texted "1 yes" resolve
  deterministically in the reply turn.
- `digests/YYYY-MM-DD.md` — the full artifact: every item, every source with URL and date,
  confidence, the cohort that was checked, and what was considered and dropped.

Re-report rules:

- **applied** → never reported again (and it is no longer a candidate).
- **rejected** by Norman → suppressed, **unless** the new evidence fingerprint differs from
  the one he rejected. New evidence gets one fresh airing, marked "you said no in <month>;
  this source is new."
- **pending** (no reply) → re-reported at most once every 14 days (at the monthly
  cadence, that is every run), and after three
  appearances it collapses to a single summary line. **The collapsed line keeps its number**,
  stays inside the 8-item cap, and stays in `last-digest.json`, so it is still resolvable with
  "4 yes". A collapsed item that lost its number could never be answered.

## Verification of an approved change

**What the Pi cannot do: run the XCTest suite.** The Pi is Linux; `xcodebuild` is Mac-only.
Norman's answer — update the pinned expectations and run the suite before pushing — is only
half-satisfiable here, and saying so is better than pretending otherwise.

So an approved change is verified in two layers:

1. **On the Pi, before the push:** a stdlib-only validator at
   `~/.hermes/scripts/bar_roster_validate.py` checks the roster against the same rules the
   Swift tests encode — ids unique across all 93+ records including archived ones; every
   active record's `neighborhood` present in `meta.json` and in the polygon set; every
   neighborhood covered by a `Stats.borough()` set (nothing silently falling through to
   Manhattan); latitude/longitude present and inside the NYC bounding box; `tags` drawn from
   the 15-value vocabulary; the archived id list in `LogicTests.swift` matching the archived
   ids in `bars.json`; the pinned id → name/neighborhood/address triples matching the file.
   Non-zero exit blocks the push.
2. **On the Mac, when he next builds:** `xcodebuild … test`. The pinned expectations have
   already been updated in the same commit, so this is expected to be green; the Pi-side
   validator exists so that the things it can check are caught before the push rather than
   after.

The first layer is the builder's addition, not something Norman asked for; it exists because
his "run the suite" answer cannot be honored on this host.

## Constraints

- Runs on the Raspberry Pi. Cron expressions are host-local; `timedatectl` confirms
  `America/New_York`, so `0 18 * * 3` is Wed 18:00 ET. Existing sibling jobs confirm the
  convention (NFL pool card is `0 17 * * 3`). Cron cannot express "first Wednesday" (day-of-month
  and day-of-week are OR'd), so the job ticks every Wednesday and a monitor gate,
  `~/.hermes/scripts/bar-roster-first-wednesday.py`, prints the current month's first-Wednesday
  date; the agent runs only when that value changes. A first Wednesday missed during a gateway
  outage is therefore picked up by the next Wednesday that month.
- **The Pi checkout's remote is `origin`**, which is the same GitHub repo CLAUDE.md calls
  `xcode` (`normanhoang/nyc_gay_bars_phone_app_xcode`); `main` tracks `origin/main`. There is
  no remote named `xcode` on the Pi and none is to be added — CLAUDE.md's `xcode` remote is a
  Mac-side naming difference for the same repository. The reply turn pushes `origin main`.
- **Single writer for roster data: the Pi.** The context script brings the checkout
  up to date (fast-forward only) and the context block states whether it could; if the
  checkout is diverged or dirty, the run reports that fact instead of researching a stale
  roster, and the reply turn resolves it before editing.
- Delivery target is the Photon DM already used by the other alert jobs, derived at creation
  time from `~/.hermes/channel_directory.json` rather than retyped.
- **The job only fires while the Hermes gateway is alive** — the scheduler ticker is a child
  of that process — and Photon delivery goes through a sidecar the gateway supervises. A
  gateway outage on the first Wednesday delays the text to the next Wednesday the gateway is up
  (the gate catches up); one lasting the rest of the month means no text that month, silently. This is a real limitation of any Photon
  job on this host and is accepted here, not worked around; the reply path has the same
  dependency.
- Data edits must respect existing invariants: `meta.json`'s `neighborhoods` list, the
  neighborhood polygon set, and `Stats.borough()`'s `brooklynHoods`/`queensHoods`/Bronx sets.
  An unlisted neighborhood silently counts as Manhattan and corrupts the boroughs badge.
- New coordinates are geocoded (OSM), never copied from an aggregator. A bar may sit just
  outside its neighborhood polygon by deliberate override — `bar.neighborhood` drives
  filtering and badges, polygon containment only drives map tap.
- Tags come from the existing 15-value vocabulary (`bear`, `cabaret`, `cocktails`, `country`,
  `dance`, `dive`, `drag`, `historic`, `karaoke`, `latin`, `leather`, `lesbian`, `lounge`,
  `piano`, `sports`). New tags are a separate conversation.
- Ids are lowercase-hyphen slugs derived from the name, unique against the whole 93-record
  file including archived rows.
- The job stores its prompt in the cron job's `prompt` field, authored from
  `~/.hermes/scripts/bar-roster-prompt.txt` (the host's existing convention, alongside
  `nfl-pool-prompt.txt` and `news-briefing-prompt.txt`).
- A context script emits the roster and state as the run's context, using the cron `script`
  field so its stdout is injected into the prompt.

## Decisions made, and by whom

Norman's decisions, as he made them:

- The first Wednesday of each month at 6:00 PM (originally every Wednesday; changed
  2026-10-14).
- Delivery by Photon text with numbered items. Originally one digest text; changed
  2026-10-12 to one text per item (header first, closing counts last).
- A text arrives every month, including months with nothing new.
- Scope includes potential additions, closures, **and** moves, renames, and stale labels.
- Neighborhood newsletters are a desired source.
- On his yes, commit and push straight to `main`.
- Defend hardest against calling a live bar closed.
- A qualifying venue in a neighborhood the app lacks gets its neighborhood built properly
  (polygon + meta + borough classification) as part of that approval, with the extra cost
  stated in the text.
- An approved MOVE re-derives `neighborhood` and says so in the text, since it moves badge
  progress.
- An approved change updates the pinned test expectations and runs the suite before pushing.

The builder's calls (the author's, open to veto):

- The job is read-only; all writes happen in the reply turn. Keeps an unattended research
  agent away from the repo and keeps human approval as the only gate.
- The evidence standard and inclusion rule are imported from the August audit rather than
  reinvented.
- Three legs including a 4-month cohort rotation, so the roster is fully re-verified on a
  cycle without an 84-bar research bill every run.
- Confidence is stated per item, and closures are split into CLOSE (high confidence) vs
  NEEDS YOUR LOOK (conflict) so low-confidence claims can never read as findings.
- No URLs in the text; full sources in the artifact.
- 8-item cap on the text.
- The Pi pushes `origin main`; no `xcode` remote exists there and none is added.
- The Pi is the single writer for roster data; the context script fast-forwards the checkout
  and reports if it cannot.
- State is pre-seeded from the August audit's already-adjudicated items, with evidence
  fingerprints, so the first run does not nag.
- A collapsed pending item keeps its number so it stays answerable.
- `bar_roster_validate.py` runs before every push, because `xcodebuild` cannot run on the Pi.

## Left to the builder

- Exact wording of `bar-roster-prompt.txt`.
- Schema details of the state file and the context script's output format.
- The cohort rotation's exact seeding (must be deterministic and stable across runs).
- Whether the reply turn is handled by the existing session or a dedicated prompt file.
- How to phrase the "you said no in August" nudge.
- Artifact retention (how long `digests/` keeps files).
