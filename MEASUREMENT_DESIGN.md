# Measurement design before implementation

Status: proposal for review. No calculation or storage code has changed yet.
The pre-redesign version is tag `pre-redesign-2026-09-22`.

## What the app knows today

- A lease plan contains allowance, odometer at lease start, latest saved
  odometer, planned commute distance and weekdays, and return date. It does
  **not** contain the lease start date.
- The app saves only one current odometer value on each device. Previous values
  and their times are lost when that value is replaced.
- A Volvo response includes an odometer value and Volvo's update timestamp.
  The time when the app received it can be later.
- Manual input has no measurement timestamp beyond when it is entered.
- The app does not know which trips were commuting. The selected weekdays and
  round-trip distance describe a plan, not measured trip purpose.
- The phone and car can each have their own locally saved lease plan.

## Keep three concepts separate

1. **Contract balance:** total kilometres remaining under the lease. Preserve
   the current calculation and display.
2. **Rolling suggestion:** the existing even distribution of the current
   leisure balance across the remaining calendar days. Preserve this function
   and expose its month/week/day values during comparison.
3. **Period balance:** a new allowance for this calendar day/week/month, less
   **all** driving observed in that period. This is the user's initial choice.
   It needs dated readings and carries a data-quality label.

These are separate values. A negative day balance can coexist with positive
total kilometres left until return.

## Proposed data model

- A period-budget baseline has a stable plan ID, effective date, odometer,
  remaining contract distance, return date and commute schedule. One simple
  option is to start this baseline when the new feature is activated, because
  the current app does not know the lease start date. An edit to allowance,
  return date or commute schedule creates a new revision, so old readings are
  not silently reinterpreted without notice.
- `OdometerReading` is an immutable record with plan ID, car ID when known,
  kilometres, source (`manual` or `Volvo`), `measuredAt`, and `receivedAt`.
  Save both times in UTC; use the user's local calendar zone for day/week/month.
- Volvo's update timestamp is `measuredAt`. An identical stale Volvo response
  is not a new measurement. A manual entry uses entry time unless the user
  explicitly supplies a different measurement time.
- Keep readings for different cars apart. Do not calculate a distance between
  the odometers of two cars. A car change starts a separate measurement series.
- Storage of readings is separate from plan storage and calculation. A pure
  calculator consumes a plan revision and readings, returning numbers plus
  quality states. No UI widget should infer the quality itself.

## Calendar and quality rules

- The day starts at local midnight, the week on Monday, and the month on its
  first day. The return date is exclusive, matching the current calculator.
- Prefer a reading at the period boundary. If none exists, we cannot know
  precisely how many kilometres were driven after that boundary. Merely
  collecting more readings later does not reconstruct the missing boundary.
- The new period result therefore says either `measured`, `estimated`, or
  `missing basis`. A result must state the readings and assumptions that led
  to it. No guessed value receives the `measured` label.
- While the basis is missing, the UI shows the existing rolling `Suggested
  today` value **and** `Missing start-of-day reading`. This also applies to
  week and month. Existing numbers never disappear during the redesign.
- The new balance subtracts the **whole odometer change**. It never guesses
  which kilometres were commuting. The existing leisure calculation continues
  to reserve planned commuting separately.

## Candidate period allowance formula

At the chosen measurement start, take the remaining *contract* distance. For
each remaining calendar day, assign an even share of distance beyond planned
commuting, plus that day's planned commute distance. Thus a planned commute
day receives more total-driving room than a non-commute day, and all assigned
days add up to the remaining contract distance. A week/month allowance is the
sum of its days. Subtract the total odometer increase in that period, with no
attempt to classify individual trips.

This is a proposal, not an implemented or approved formula. In particular,
the first partial day/week/month has no historic start reading and must show
its missing basis alongside the existing rolling suggestion.

## Questions that affect the formula or storage

1. Should the new period baseline begin when tracking is enabled, with no new
   input and no invented history, or should users enter the actual lease start
   date? The latter still cannot reconstruct old boundary odometer readings.
2. If the car is not read at midnight, should the new period balance show a
   clearly marked approximation based on nearby readings, or remain unknown?
   The rolling suggestion remains visible either way.
3. Should period history be shared across phone and car? Local history is
   simplest but can produce different period results on the two devices.
   Shared history requires a deliberate server and account design, especially
   for users who enter readings manually without connecting Volvo.

## Verification before replacing any presentation

- Check migrations with an existing saved plan and no history.
- Check two cars with very different odometers, stale Volvo timestamps,
  duplicate readings, app offline, manual override, and plan edits.
- Check a day with no reading at midnight, a missed week, month boundary,
  daylight-saving change, and return date inside a period.
- Compare old and new values side by side in tests and on phone, car emulator,
  and browser. Keep the baseline tag and `main` untouched while iterating.
