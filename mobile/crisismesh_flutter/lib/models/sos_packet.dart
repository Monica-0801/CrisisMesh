class SosPacket {
  const SosPacket({
    this.id,
    required this.message,
    required this.createdAt,
    this.voiceTranscript,
    this.latitude,
    this.longitude,
    this.photoPath,
    this.clientEventId,
    this.deviceId = 'crisismesh-android',
    this.relayMode = 'network',
    this.status = 'pending',
    this.retryCount = 0,
    this.lastAttemptAt,
    this.remoteId,
  });

  final int? id;
  final String message;
  final String createdAt;
  final String? voiceTranscript;
  final double? latitude;
  final double? longitude;
  final String? photoPath;
  final String? clientEventId;
  final String deviceId;
  final String relayMode;
  final String status;
  final int retryCount;
  final String? lastAttemptAt;
  final int? remoteId;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'message': message,
      'voiceTranscript': voiceTranscript,
      'latitude': latitude,
      'longitude': longitude,
      'photoPath': photoPath,
      'clientEventId': clientEventId,
      'relayMode': relayMode,
      'status': status,
      'createdAt': createdAt,
    };
  }

  factory SosPacket.fromDbMap(Map<String, dynamic> map) {
    return SosPacket(
      id: map['id'] as int?,
      message: map['message'] as String? ?? 'Emergency alert',
      createdAt: map['createdAt'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      voiceTranscript: map['voiceTranscript'] as String?,
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      photoPath: map['photoPath'] as String?,
      clientEventId: map['clientEventId'] as String?,
      deviceId: map['deviceId'] as String? ?? 'crisismesh-android',
      relayMode: map['relayMode'] as String? ?? 'mesh',
      status: map['status'] as String? ?? 'pending',
      retryCount: map['retryCount'] as int? ?? 0,
      lastAttemptAt: map['lastAttemptAt'] as String?,
      remoteId: map['remoteId'] as int?,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'message': message,
      'createdAt': createdAt,
      'voiceTranscript': voiceTranscript,
      'latitude': latitude,
      'longitude': longitude,
      'photoPath': photoPath,
      'clientEventId': clientEventId,
      'deviceId': deviceId,
      'relayMode': relayMode,
      'status': status,
      'retryCount': retryCount,
      'lastAttemptAt': lastAttemptAt,
      'remoteId': remoteId,
    };
  }

  SosPacket copyWith({
    int? id,
    String? status,
    int? retryCount,
    String? lastAttemptAt,
    int? remoteId,
    String? photoPath,
  }) {
    return SosPacket(
      id: id ?? this.id,
      message: message,
      createdAt: createdAt,
      voiceTranscript: voiceTranscript,
      latitude: latitude,
      longitude: longitude,
      photoPath: photoPath ?? this.photoPath,
      clientEventId: clientEventId,
      deviceId: deviceId,
      relayMode: relayMode,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      remoteId: remoteId ?? this.remoteId,
    );
  }
}
