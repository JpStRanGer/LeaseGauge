# LeaseGauge: budget and home-screen redesign

Status: working plan on `codex/leasegauge-redesign`. No existing release behavior
has been changed by this document.

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

The proposed new period cards show: allowance assigned to this calendar
month/week/day, less leisure driving within that period. The total remaining
until return stays a separate figure. Negative period balances mean the user
is over that period's allowance; they do not mean the whole lease is exhausted.

To calculate a period balance, we need a starting date, an odometer reading
at the start of the period, and a later reading. The app currently persists
only the latest odometer reading and has no lease start date or reading history.
Volvo may also provide an odometer timestamp that does not fall on a calendar
boundary. We must not label an estimated balance as an exact measured one.

## Proposed implementation sequence

1. Define the period rules and data model: lease start, dated readings, and
   clear handling of missing boundary readings and planned commuting.
2. Implement and test the calculation independently of the UI, including
   month/week changes, negative balances, missed readings, and car changes.
3. Persist readings locally without losing existing plans. Show an honest
   suggested value while measured period data is insufficient.
4. Redesign the home hierarchy: daily figure first, a small view switch,
   total-to-return below, and restrained week/month details.
5. Review real screenshots on phone, car emulator, and browser; adjust the
   layout with the user's feedback. Keep Volvo and manual flows working.
6. Verify tests and compare the redesign branch with the baseline. Merge only
   after the numbers and interaction make sense in real use.

## Decisions to finish with the user

- Should the optional personal comparison be shown automatically when useful,
  or behind a `What does this mean?` action?
- For the first incomplete day/week/month, should the card show an explicitly
  labelled suggestion until a boundary reading exists, or a `Not enough data`
  state? Both choices must make the source of the number clear.
