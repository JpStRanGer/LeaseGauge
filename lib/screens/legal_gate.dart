import 'package:flutter/material.dart';
import 'package:leasegauge/data/legal_acceptance_storage.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const termsUrl = 'https://leasegauge.jonaspettersen.no/leasegauge/terms';
const privacyUrl = 'https://leasegauge.jonaspettersen.no/leasegauge/privacy';

class LegalGate extends StatefulWidget {
  const LegalGate({super.key, required this.store, required this.child});

  final LegalAcceptanceStore store;
  final Widget child;

  @override
  State<LegalGate> createState() => _LegalGateState();
}

class _LegalGateState extends State<LegalGate> {
  bool? _accepted;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final accepted = await widget.store.hasAcceptedCurrentTerms();
      if (mounted) setState(() => _accepted = accepted);
    } catch (_) {
      if (mounted) {
        setState(() {
          _accepted = false;
          _error = 'Could not check local acceptance. Please try again.';
        });
      }
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.acceptCurrentTerms();
      if (mounted) setState(() => _accepted = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save your choice. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == true) return widget.child;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to LeaseGauge')),
      body: _accepted == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Before you start',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'LeaseGauge is a planning aid, not your lease contract. Check important figures against your car and your contract. Manual use does not require a Volvo connection.',
                    ),
                    const SizedBox(height: 24),
                    const LegalDocumentLinks(),
                    const SizedBox(height: 18),
                    const Text(
                      'Please read the Terms of Use before continuing. The Privacy Notice explains what information is handled and stays available in the app. Connecting Volvo is a separate, optional choice.',
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        key: const Key('legalAcceptanceError'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: const Key('acceptTermsButton'),
                        onPressed: _busy ? null : _accept,
                        child: Text(
                          _busy ? 'Saving…' : 'I agree to the Terms of Use',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your choice is saved on this device only. If you use LeaseGauge on another device, you will be asked there too. If you are in a car, read and respond only while parked.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class LegalDocumentLinks extends StatelessWidget {
  const LegalDocumentLinks({super.key});

  Future<void> _open(BuildContext context, String url, String title) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      // Some car systems have no browser. A QR code remains available below.
    }
    if (!launched && context.mounted) _showQr(context, url, title);
  }

  void _showQr(BuildContext context, String url, String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan this code with your phone to read the document.',
              ),
              const SizedBox(height: 16),
              QrImageView(data: url, size: 200),
              const SizedBox(height: 8),
              SelectableText(url),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const Key('openTermsButton'),
          onPressed: () => _open(context, termsUrl, 'Terms of Use'),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Terms of Use'),
        ),
        OutlinedButton.icon(
          key: const Key('openPrivacyButton'),
          onPressed: () => _open(context, privacyUrl, 'Privacy Notice'),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Privacy Notice'),
        ),
        TextButton.icon(
          key: const Key('legalQrButton'),
          onPressed: () => _showQr(context, termsUrl, 'Terms of Use'),
          icon: const Icon(Icons.qr_code_rounded),
          label: const Text('Open on phone'),
        ),
      ],
    );
  }
}
