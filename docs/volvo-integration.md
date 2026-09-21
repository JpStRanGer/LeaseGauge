# Volvo integration status

The Flutter client and owner-specific server pairing use the deployed
LeaseGauge domain. The current app keeps manual odometer entry active.

The Volvo UI is hidden by default. Builds for Volvo testing enable it with
`--dart-define=LEASEGAUGE_VOLVO_ENABLED=true`. The internal Play test track
uses this flag; public release requires a separate review.

Each person connects using their own Volvo ID. The app first tries to open the
Volvo sign-in in an external browser. If the device has no browser, such as a
parked AAOS system, it shows a QR code containing the same short-lived Volvo
authorization URL. The owner scans it on their phone, completes the Volvo
sign-in there, and the original device receives its own LeaseGauge device
token while polling for completion. The QR code does not contain a Volvo
password, access token, or device-pairing secret.

The server stores Volvo tokens
encrypted under that owner's Volvo subject. The phone receives a separate
LeaseGauge device token, saved with `flutter_secure_storage`, and only receives
kilometers plus the vehicle's data timestamp. No VIN or Volvo token is sent to
the phone. Automatic updates never lower a manually saved odometer reading;
manual entry remains available if connection fails or the car reports stale
data. If a Volvo ID has multiple cars, the app explains that explicit car
selection is still needed and keeps manual entry available without deleting
the connection. Pairing expires after ten minutes and device credentials after
90 days of inactivity.

The server-side work is in the `codex/leasegauge-volvo` branch of the
`hjemmeside` repository. Its `Server/LEASEGAUGE_VOLVO.md` lists the remaining
deployment and security checks. The Flutter repository uses
`https://github.com/JpStRanGer/LeaseGauge.git` as its Git remote.
