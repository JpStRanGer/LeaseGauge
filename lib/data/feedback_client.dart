import 'dart:convert';

import 'package:http/http.dart' as http;

enum FeedbackKind { idea, bug }

class FeedbackException implements Exception {
  const FeedbackException(this.message);
  final String message;
}

/// The app carries no email credential. Only the fixed server endpoint can
/// submit a bounded message, and the server chooses the sole recipient.
class FeedbackClient {
  FeedbackClient({http.Client? httpClient, Uri? baseUrl})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null,
      _baseUrl = baseUrl ?? Uri.parse('https://leasegauge.jonaspettersen.no');

  final http.Client _http;
  final bool _ownsHttp;
  final Uri _baseUrl;

  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<void> send({
    required FeedbackKind kind,
    required String message,
    String replyEmail = '',
  }) async {
    final cleaned = message.trim();
    final email = replyEmail.trim();
    if (cleaned.length < 8 || cleaned.length > 1500 || email.length > 254) {
      throw const FeedbackException('Check the message length and try again.');
    }
    try {
      final response = await _http
          .post(
            _baseUrl.resolve('/leasegauge/api/feedback'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'kind': kind.name,
              'message': cleaned,
              'reply_email': email,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['status'] == 'sent') {
          return;
        }
      }
      if (response.statusCode == 429) {
        throw const FeedbackException(
          'Too many messages were sent recently. Please try again later.',
        );
      }
      if (response.statusCode == 400) {
        throw const FeedbackException('Please check your message and email.');
      }
      throw const FeedbackException(
        'Feedback could not be sent right now. Your text is still here; try again later.',
      );
    } on FeedbackException {
      rethrow;
    } on Exception {
      throw const FeedbackException(
        'Feedback could not be sent right now. Your text is still here; try again later.',
      );
    }
  }
}
