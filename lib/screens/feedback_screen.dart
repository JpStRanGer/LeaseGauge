import 'package:flutter/material.dart';
import 'package:leasegauge/data/feedback_client.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.client});

  final FeedbackClient? client;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _replyEmail = TextEditingController();
  late final FeedbackClient _client = widget.client ?? FeedbackClient();
  FeedbackKind _kind = FeedbackKind.idea;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    _message.dispose();
    _replyEmail.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _client.send(
        kind: _kind,
        message: _message.text,
        replyEmail: _replyEmail.text,
      );
      if (mounted) setState(() => _sent = true);
    } on FeedbackException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send feedback')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_sent) ...[
                const Icon(Icons.check_circle_rounded, size: 44),
                const SizedBox(height: 12),
                Text(
                  'Thank you — your message was sent.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to LeaseGauge'),
                ),
              ] else ...[
                Text(
                  'Tell us what could be better',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A suggestion or a problem report goes directly to the developer. You can use LeaseGauge without sending anything.',
                ),
                const SizedBox(height: 22),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<FeedbackKind>(
                        segments: const [
                          ButtonSegment(
                            value: FeedbackKind.idea,
                            icon: Icon(Icons.lightbulb_outline_rounded),
                            label: Text('Suggestion'),
                          ),
                          ButtonSegment(
                            value: FeedbackKind.bug,
                            icon: Icon(Icons.bug_report_outlined),
                            label: Text('Report a problem'),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: _sending
                            ? null
                            : (selection) =>
                                  setState(() => _kind = selection.first),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('feedbackMessage'),
                        controller: _message,
                        maxLength: 1500,
                        minLines: 5,
                        maxLines: 9,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Your message',
                          hintText: 'What happened, or what would you like to change?',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 8
                            ? 'Write at least 8 characters.'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        key: const Key('feedbackReplyEmail'),
                        controller: _replyEmail,
                        maxLength: 254,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Your email (optional)',
                          helperText: 'Only if you want a reply.',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return null;
                          if (!RegExp(r'^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$')
                              .hasMatch(email)) {
                            return 'Enter a valid email address or leave it blank.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Please do not include passwords, Volvo login details or other sensitive information. No car data, location or diagnostics are attached automatically. Only your message and optional reply address are sent.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'If you are in a car, only write and send feedback while parked.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('feedbackError'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const Key('sendFeedbackButton'),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_sending ? 'Sending…' : 'Send feedback'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
