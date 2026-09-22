# LeaseGauge: budget and home-screen redesign

Status: working plan on `codex/leasegauge-redesign`. No existing release behavior
has been changed by this document. See `MEASUREMENT_DESIGN.md` before changing
budget calculations or reading storage.

## Safe starting point

- The current, working app is commit `09b254f650478af8ab78ea8fdc5c7d3979a8b10d`.
- `main` and tag `pre-redesign-2026-09-22` point to that commit.
- All redesign work stays on `codex/leasegauge-redesign` until reviewed.

## What we agreed before Volvo work paused the design discussion

- A calm, clean, car-inspired interface without decorative dashboard elements.
- A large daily figure on the home screen, with restrained status color.
- `Remaining today` as the default view and `Driven today` as a secondary view.
- Total leisure kilometres until return, and week/month figures, still available
  below the daily figure.
- A short, personal comparison may explain the daily figure, but should not
  create visual noise. Whether it appears automatically is still undecided.
- Volvo connection and odometer controls remain available, but visually quiet
  when healthy. Manual odometer entry remains explicit and accessible.

## Budget meaning

The present month/week/day numbers divide the *current total remaining*
evenly over the days left. They are rolling suggestions, not the balance of
an allowance assigned at the start of each calendar period.

**Preservation rule:** keep every existing number and the existing
`calculateLeisureBudgets` calculation available in the redesign. Add new
period figures beside them for comparison. Do not replace or delete a legacy
figure while the new interpretation is being tested.

The proposed new period cards show: allowance assigned to this calendar
month/week/day, less **all driving** within that period. This is the user's
initial choice for the redesign. The existing leisure balance and rolling
leisure suggestions remain alongside these new numbers. Negative period
balances mean the user is over that period's allowance; they do not mean the
whole lease is exhausted.

To calculate a period balance, we need a starting date, an odometer reading
at the start of the period, and a later reading. The app currently persists
only the latest odometer reading and has no lease start date or reading history.
Volvo may also provide an odometer timestamp that does not fall on a calendar
boundary. We must not label an estimated balance as an exact measured one.
The baseline begins when tracking is activated, and dated readings are stored
only on that device. There will be no server, database, or cross-device sync
for this feature. The phone and car may consequently show different period
histories.

When a period-start reading is missing, show both the existing, clearly
labelled `Suggested today` figure and a `Missing start-of-day reading` status.
The same principle applies to week and month. Neither message hides the other.
This is approved: do not estimate a missing start reading from nearby data.
Manual readings update the existing total and rolling calculations exactly as
before. They become timestamped local readings for the new calculation, but a
value entered during the day is not retroactively a midnight reading. Only the
new exact period balance waits for the missing data; its card stays visible
with a plain explanation. We will not require manual date/time entry yet.

## Small test releases

Introduce one visible change at a time. Before moving to the next slice,
exercise the current slice on phone, car emulator, and browser, compare its
figures with the baseline, and fix regressions. Do not publish to Play or
merge into `main` merely because a branch test passes.

1. **Presentation only:** make the existing rolling daily suggestion easier
   to see and label it clearly. Keep the total balance and the existing
   month/week/day numbers, Volvo controls, and manual entry. No new tracking
   or new period number is active in this test release.
2. **Local reading history:** connect the already-isolated local store to
   successful manual updates first, with a small read-only status. Test that
   an app restart preserves the history and a storage error does not break
   the existing budget. Connect Volvo updates in a later, separate test slice,
   then test offline use and switching cars. Preserve old plan keys and all
   old calculations throughout.
3. **New daily comparison:** show the approved commute-aware assigned daily
   allowance alongside the old rolling suggestion. Show a measured balance
   only with a true boundary reading; otherwise show the approved missing
   start-reading message. Review actual behaviour before extending it.
4. **Week/month and layout:** add those period comparisons only after the day
   is understood. Then refine the calm daily-first hierarchy and optional
   personal explanation without removing any old figures.

Each slice is separately reversible. The existing `main` and baseline tag
remain untouched until the user reviews and approves a merge.

## Decisions to finish with the user

- Should the optional personal comparison be shown automatically when useful,
  or behind a `What does this mean?` action?
