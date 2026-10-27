# ParkShare — Pre-existing issues found while working (NOT fixed)

These were noticed during the responsive pass. They are outside the responsive scope and
were deliberately left untouched (the responsive task forbade unrelated fixes). Listed
separately so they are not lost.

---

## 1. Duplicate “COD Pending” stat card on the owner dashboard (medium)

- File: `lib/modules/owner/home/owner_dashboard_screen.dart`
- Lines: `_StatCard(label: 'COD Pending', value: '${dash.codPendingCount}', …)` appears
  **twice** — once in the “Pending / COD Pending / Active” row (~L225–230) and again in
  the “COD Pending / UPI To Verify / …” row (~L246–251). Both read the same
  `dash.codPendingCount`, so owners see the same number on two tiles.
- Suggested fix: delete the second tile (the one in the row with “UPI To Verify”), i.e.
  keep the tile that sits with “Pending / Active”.
- Not a responsive issue; not fixed here.

## 2. Stale `ASSET_MAPPING.md`

- `ASSET_MAPPING.md` at the repo root documents assets/layouts that no longer match the
  app (removed logo flow, old screen names). Users onboarding into the codebase will be
  misled. Needs a refresh against `assets/images/…`, `lib/` screen paths and the
  splash→onboarding flow.
- Not touched (out of scope).

## 3. Stale integration tests

- `integration_test/ux_verification_test.dart`, `e2e_flow_test.dart`,
  `auth_flow_test.dart` reference old UI strings and require the live backend. They were
  not run or updated in this pass (they need a device with backend + real credentials).
- Recommend re-baselining them against the current screens/strings and the new adaptive
  navigation before using them as release gates.

## 4. Deliberate test update (not a bug, recorded for transparency)

- `test/widget/ui_changes_test.dart` previously asserted the removed fixed
  `GridView.count(2)` amenities layout. It was updated to assert the new adaptive grid
  (max cross-axis extent 200, tile height 84, 2-column-on-phone flow). This is the only
  pre-existing test that encoded the old implementation detail; all other 161 tests are
  unchanged and pass.

## 5. Environment notes (not app bugs)

- The AOSP API-36 emulator never delivered a GPS fix to the location plugin, so
  nearby-parking fetch and downstream booking screens couldn’t be exercised on-device
  (see `RESPONSIVE_READY_REPORT.md` §8).
- flutter_map tiles require network; they render blank on a fresh offline emulator while
  overlays render correctly.