import 'package:flutter_test/flutter_test.dart';
import 'package:leasegauge/data/period_tracking_storage.dart';
import 'package:leasegauge/domain/period_tracking.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('history round-trips locally without touching the lease plan', () async {
    final preferences = SharedPreferencesAsync();
    await preferences.setDouble('lease.currentOdometerKm', 7857);
    final store = LocalPeriodTrackingStore(preferences: preferences);
    final start = DateTime(2026, 9, 22, 11);
    final session = PeriodTrackingSession(
      id: 'first-revision',
      baseline: PeriodTrackingBaseline(
        carKey: 'car-a',
        startedAt: start,
        odometerKm: 7857,
        remainingContractKm: 20000,
        returnDate: DateTime(2029, 2, 16),
        commuteRoundTripKm: 36,
        commuteWeekdays: const {DateTime.monday, DateTime.friday},
        planSignature: 'plan-terms-v1',
      ),
      readings: [
        DatedOdometerReading(
          carKey: 'car-a',
          kilometers: 7857,
          source: OdometerReadingSource.manual,
          measuredAt: start,
          receivedAt: start,
        ),
      ],
    );

    await store.save([session]);
    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.baseline.carKey, 'car-a');
    expect(loaded.single.baseline.planSignature, 'plan-terms-v1');
    expect(loaded.single.baseline.commuteWeekdays, {
      DateTime.monday,
      DateTime.friday,
    });
    expect(loaded.single.readings.single.kilometers, 7857);
    expect(await preferences.getDouble('lease.currentOdometerKm'), 7857);
  });

  test('same Volvo measurement is stored only once and cars stay separate', () {
    final measuredAt = DateTime.utc(2026, 9, 22, 8);
    final reading = DatedOdometerReading(
      carKey: 'car-a',
      kilometers: 8000,
      source: OdometerReadingSource.volvo,
      measuredAt: measuredAt,
      receivedAt: measuredAt.add(const Duration(minutes: 10)),
    );
    final session = PeriodTrackingSession(
      id: 'one',
      baseline: PeriodTrackingBaseline(
        carKey: 'car-a',
        startedAt: measuredAt,
        odometerKm: 8000,
        remainingContractKm: 1000,
        returnDate: DateTime(2026, 10),
        commuteRoundTripKm: 0,
        commuteWeekdays: const {},
      ),
      readings: [],
    );
    expect(
      session.withReading(reading).withReading(reading).readings,
      hasLength(1),
    );
    expect(
      () => session.withReading(
        DatedOdometerReading(
          carKey: 'car-b',
          kilometers: 10,
          source: OdometerReadingSource.volvo,
          measuredAt: measuredAt,
          receivedAt: measuredAt,
        ),
      ),
      throwsArgumentError,
    );
  });
}
