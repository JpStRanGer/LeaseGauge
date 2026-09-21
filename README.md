# LeaseGauge

A lease-distance planner with reserved commuting and leisure-distance budgets.
Built with Flutter for Android, iOS and web. Odometer readings can be entered
manually or fetched from a connected Volvo account in enabled builds.

## Commute map prototype

In Plan details, choose **Choose route on map**, tap home and then work, and
confirm the calculated round-trip driving distance. If the proposed road is
wrong, tap one or more roads to add ordered via points; remove the last point
or start over as needed. You can edit the number
manually before saving the plan. The map starts in Oslo; pan or zoom to your
area first. The chosen locations are not saved; only the distance is saved.

The map uses OpenStreetMap tiles and the public FOSSGIS/OSRM routing demo.
Selecting the two points sends their coordinates to that routing server.
This endpoint is for local, non-commercial testing only. Replace it with a
production routing provider or self-hosted service before distributing this
feature commercially; its availability is not guaranteed.

## Android and Volvo testing

See [the Android testing and signing guide](docs/android-testing.md) for local
emulator testing, a password-prompted release build, and the remaining Google
Play car-category/distribution checks. No release is published automatically.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
