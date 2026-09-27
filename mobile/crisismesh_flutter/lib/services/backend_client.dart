import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/sos_packet.dart';

class SubmissionResult {
  const SubmissionResult({required this.success, this.remoteId});

  final bool success;
  final int? remoteId;
}

class BackendClient {
  static const String _endpoint = 'http://127.0.0.1:5249/api/incidents';

  Future<SubmissionResult> submitIncident(SosPacket packet) async {
    final payload = packet.toJson();
    if (packet.photoPath != null && !File(packet.photoPath!).existsSync()) {
      payload['photoPath'] = null;
    }

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        return SubmissionResult(
          success: true,
          remoteId: body is Map<String, dynamic> ? body['id'] as int? : null,
        );
      }
    } on IOException {
      return const SubmissionResult(success: false);
    } on FormatException {
      return const SubmissionResult(success: false);
    }

    return const SubmissionResult(success: false);
  }
}
