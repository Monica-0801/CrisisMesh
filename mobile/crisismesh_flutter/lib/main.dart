import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/sos_packet.dart';
import 'services/backend_client.dart';
import 'services/bluetooth_relay_service.dart';
import 'services/sos_database.dart';

void main() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const CrisisMeshApp());
}

class CrisisMeshApp extends StatelessWidget {
  const CrisisMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrisisMesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101214),
        fontFamily: 'sans',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Connectivity _connectivity = Connectivity();
  final TextEditingController _messageController = TextEditingController();
  final SpeechToText _speechToText = SpeechToText();
  final BackendClient _backendClient = BackendClient();
  final BluetoothRelayService _relayService = BluetoothRelayService();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<BluetoothAdapterState>? _bluetoothSubscription;
  StreamSubscription<List<ScanResult>>? _bluetoothScanSubscription;
  CameraController? _cameraController;

  bool _sosActivated = false;
  bool _voiceSelected = false;
  bool _isOnline = false;
  bool _connectivityReady = false;
  bool _locationLoading = false;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _cameraReady = false;
  bool _sending = false;
  bool _bluetoothReady = false;
  bool _syncInProgress = false;
  bool _photoCaptureStarted = false;
  bool _voiceCaptureStarted = false;
  Position? _position;
  String _locationStatus = 'Location not captured';
  String? _locationError;
  String _voiceTranscript = 'Voice is being captured automatically...';
  String? _photoPath;
  int _nearbyRelayCount = 0;
  List<ScanResult> _relayNodes = [];
  String _relayStatus = 'Scanning for relay nodes...';
  String _dangerClassification = 'Assessing emergency type...';
  String _statusMessage = 'Prepared for offline and online dispatch.';
  Timer? _photoCaptureTimer;
  Timer? _riskAssessmentTimer;
  Timer? _outboxRetryTimer;
  bool _riskAssessmentComplete = false;

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
    _initializeSpeech();
    _initializeCamera();
    _initializeBluetooth();
    _syncQueuedPackets();
    _outboxRetryTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _syncQueuedPackets(),
    );
  }

  Future<void> _initializeConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!mounted) {
        return;
      }
      _updateConnectivity(results);
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _updateConnectivity,
        onError: (_) {
          if (mounted) {
            setState(() {
              _connectivityReady = false;
            });
          }
        },
      );
    } on Exception {
      if (mounted) {
        setState(() {
          _connectivityReady = false;
        });
      }
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    if (!mounted) {
      return;
    }

    final isOnline = results.any((result) => result != ConnectivityResult.none);
    setState(() {
      _isOnline = isOnline;
      _connectivityReady = true;
      _statusMessage = isOnline
          ? 'Network available. Outbox will sync automatically.'
          : 'Offline mode active. SOS packets will queue for later.';
    });

    if (isOnline) {
      _syncQueuedPackets();
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speechToText.initialize();
      if (!mounted) {
        return;
      }
      setState(() {
        _speechAvailable = available;
      });
      if (available && _sosActivated) {
        await _beginEmergencyCapture();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _speechAvailable = false;
          _voiceTranscript = 'Voice capture unavailable on this device.';
        });
      }
    }
  }

  Future<void> _initializeBluetooth() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        if (!mounted) {
          return;
        }
        setState(() {
          _bluetoothReady = false;
          _nearbyRelayCount = 0;
          _statusMessage = 'Bluetooth relay is not supported on this device.';
        });
        return;
      }

      _bluetoothSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (!mounted) {
          return;
        }
        setState(() {
          _bluetoothReady = state == BluetoothAdapterState.on;
        });
      });

      final state = await FlutterBluePlus.adapterState.first;
      if (!mounted) {
        return;
      }
      setState(() {
        _bluetoothReady = state == BluetoothAdapterState.on;
      });

      if (state == BluetoothAdapterState.on) {
        await _relayService.startAdvertising();
        _bluetoothScanSubscription = FlutterBluePlus.scanResults.listen((results) {
          if (!mounted) {
            return;
          }
          final uniqueDevices = results.where((result) {
            return result.advertisementData.serviceUuids
                .map((uuid) => uuid.toString().toLowerCase())
                .contains(BluetoothRelayService.serviceUuid.str.toLowerCase());
          }).toList();
          setState(() {
            _nearbyRelayCount = uniqueDevices.length;
            _relayNodes = uniqueDevices;
            _relayStatus = uniqueDevices.isEmpty
                  ? 'Relay mode active; no other nodes detected'
                : '${uniqueDevices.length} relay node(s) available';
            _statusMessage = uniqueDevices.isEmpty
                  ? 'This phone is advertising as a CrisisMesh relay.'
                : 'Bluetooth relay ready. ${uniqueDevices.length} nearby relay node(s) detected.';
          });
        });

        await FlutterBluePlus.startScan(
          withServices: [BluetoothRelayService.serviceUuid],
          timeout: const Duration(seconds: 8),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bluetoothReady = false;
          _nearbyRelayCount = 0;
          _statusMessage = 'Bluetooth relay is unavailable on this device.';
        });
      }
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      setState(() {
        _voiceTranscript = 'Voice capture is not available on this device.';
      });
      return;
    }

    if (_isListening) {
      await _speechToText.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
      });
      return;
    }

    final available = await _speechToText.listen(
      onResult: (result) {
        if (!mounted) {
          return;
        }
        final transcript = result.finalResult || result.recognizedWords.isNotEmpty
            ? result.recognizedWords
            : 'Tap the microphone and speak a short report.';

        setState(() {
          _voiceTranscript = transcript;
        });
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
      ),
    );

    if (mounted) {
      setState(() {
        _isListening = available;
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return;
      }
      final camera = cameras.firstWhere(
        (entry) => entry.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      if (!mounted) {
        return;
      }

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();

      if (!mounted) {
        return;
      }
      setState(() {
        _cameraReady = true;
      });
      if (_sosActivated) {
        await _beginEmergencyCapture();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Camera permissions or hardware not available on the current device.';
        });
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() {
        _statusMessage = 'Camera is not ready. Try again in a moment.';
      });
      return;
    }

    try {
      final file = await _cameraController!.takePicture();
      if (!mounted) {
        return;
      }
      setState(() {
        _photoPath = file.path;
        _statusMessage = 'Photo captured and attached to the emergency record.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Unable to capture a photo from this device.';
        });
      }
    }
  }

  String _classifyFromPhoto() {
    return 'Visual evidence emergency (photo review required)';
  }

  bool _hasSpeechTranscript() {
    final transcript = _voiceTranscript.trim();
    return transcript.isNotEmpty &&
        !transcript.startsWith('Voice capture') &&
        !transcript.startsWith('Tap the microphone') &&
        transcript != 'Voice is being captured automatically...';
  }

  void _completeRiskAssessment() {
    if (!mounted || _riskAssessmentComplete) {
      return;
    }

    _riskAssessmentComplete = true;
    final transcript = _voiceTranscript.trim();
    final hasSpeech = _hasSpeechTranscript();

    setState(() {
      _dangerClassification = hasSpeech
          ? _classifyDanger(transcript)
          : _photoPath != null
              ? _classifyFromPhoto()
              : 'General emergency (insufficient evidence)';
      _statusMessage = hasSpeech
          ? '60-second voice assessment complete. Risk assigned from the victim speech.'
          : _photoPath != null
              ? 'No speech detected for 60 seconds. Risk assigned from the captured image for rescue review.'
              : 'No speech or image evidence was available. General emergency priority assigned.';
    });
  }

  Future<void> _captureLocation() async {
    if (_locationLoading) {
      return;
    }

    setState(() {
      _locationLoading = true;
      _locationError = null;
      _locationStatus = 'Checking location permission...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const _LocationFailure('Location services are disabled.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationFailure('Location permission was denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationFailure('Location permission is permanently denied.');
      }

      setState(() {
        _locationStatus = 'Fetching GPS coordinates...';
      });

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
        _locationStatus = 'Location captured';
      });
    } on _LocationFailure catch (error) {
      _setLocationError(error.message);
    } on TimeoutException {
      await _useLastKnownLocation();
    } on Exception catch (error) {
      _setLocationError('Location unavailable: $error');
    } finally {
      if (mounted) {
        setState(() {
          _locationLoading = false;
        });
      }
    }
  }

  Future<void> _useLastKnownLocation() async {
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (!mounted) {
      return;
    }
    if (lastKnown == null) {
      _setLocationError('No prior location is available.');
      return;
    }
    setState(() {
      _position = lastKnown;
      _locationStatus = 'Using last known location';
    });
  }

  void _setLocationError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _locationError = message;
      _locationStatus = 'Location unavailable';
    });
  }

  Future<void> _syncQueuedPackets() async {
    if (_syncInProgress) {
      return;
    }

    _syncInProgress = true;
    var sentCount = 0;
    try {
      await SosDatabase.instance.resetSendingPackets();
      final queued = await SosDatabase.instance.fetchPendingPackets();
      for (final packet in queued) {
        if (packet.id == null) {
          continue;
        }

        final sendingPacket = await SosDatabase.instance.markSending(packet);
        final result = await _backendClient.submitIncident(sendingPacket);
        if (result.success) {
          sentCount++;
          await SosDatabase.instance.markSent(
            packet.id!,
            remoteId: result.remoteId,
          );
        } else {
          await SosDatabase.instance.markFailed(packet.id!);
        }
      }
      if (sentCount > 0 && mounted) {
        setState(() {
          _statusMessage =
              '$sentCount offline SOS packet${sentCount == 1 ? '' : 's'} delivered to the rescue backend.';
        });
      }
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _submitSos() async {
    final messageText = _messageController.text.trim();
    final hasTranscript = _hasSpeechTranscript();
    final finalMessage = messageText.isNotEmpty
        ? messageText
        : (_voiceSelected && hasTranscript)
            ? _voiceTranscript
            : 'Emergency alert generated from CrisisMesh. '
                'Visual evidence captured for rescue review.';

    final dangerLabel = hasTranscript
        ? _classifyDanger(finalMessage)
        : (_photoPath != null ? _classifyFromPhoto() : _dangerClassification);
    setState(() {
      _dangerClassification = dangerLabel;
    });

    final packet = SosPacket(
      message: finalMessage,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      voiceTranscript: _voiceSelected ? _voiceTranscript : null,
      latitude: _position?.latitude,
      longitude: _position?.longitude,
      photoPath: _photoPath,
      clientEventId:
          'crisismesh-android-${DateTime.now().microsecondsSinceEpoch}',
      relayMode: _isOnline ? 'network' : 'offline-queue',
      status: 'pending',
    );

    setState(() {
      _sending = true;
      _statusMessage = 'Preparing the emergency packet...';
    });

    try {
      final localId = await SosDatabase.instance.insertPacket(packet);
      final storedPacket = packet.copyWith(id: localId);
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'SOS protected offline. Evidence saved before delivery attempt.';
      });

      if (!_isOnline) {
        final relayed = await _relayQueuedPacket(storedPacket);
        if (relayed) {
          await SosDatabase.instance.markSent(localId);
          if (mounted) {
            setState(() {
              _statusMessage =
                  'SOS relayed to a nearby CrisisMesh node over Bluetooth.';
            });
          }
          return;
        }
        setState(() {
          _statusMessage =
              'Offline SOS active. Evidence saved securely on the device and will be delivered automatically when a connection is available.';
        });
        return;
      }

      final result = await _backendClient.submitIncident(storedPacket);
      if (!mounted) {
        return;
      }

      if (result.success) {
        await SosDatabase.instance.markSent(localId, remoteId: result.remoteId);
        setState(() {
          _statusMessage = 'SOS transmitted to the rescue backend successfully.';
        });
      } else {
        await SosDatabase.instance.markFailed(localId);
        final relayed = await _relayQueuedPacket(storedPacket);
        if (relayed) {
          await SosDatabase.instance.markSent(localId);
          setState(() {
            _statusMessage = 'SOS relayed to a nearby CrisisMesh node over Bluetooth.';
          });
          return;
        }
        setState(() {
          _statusMessage =
              'SOS saved, but transmission failed. It will be retried automatically.';
        });
      }

    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<bool> _relayQueuedPacket(SosPacket packet) async {
    for (final result in _relayNodes) {
      try {
        if (await _relayService.relayPacket(result.device, packet)) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  String _classifyDanger(String text) {
    final normalized = text.toLowerCase();

    if (normalized.contains('fire') ||
        normalized.contains('smoke') ||
        normalized.contains('burn') ||
        normalized.contains('explosion')) {
      return 'Fire / smoke emergency';
    }
    if (normalized.contains('medical') ||
        normalized.contains('injury') ||
        normalized.contains('pain') ||
        normalized.contains('bleeding') ||
        normalized.contains('unconscious') ||
        normalized.contains('sick')) {
      return 'Medical emergency';
    }
    if (normalized.contains('accident') ||
        normalized.contains('crash') ||
        normalized.contains('hit') ||
        normalized.contains('vehicle') ||
        normalized.contains('fall')) {
      return 'Accident / crash';
    }
    if (normalized.contains('flood') ||
        normalized.contains('storm') ||
        normalized.contains('earthquake') ||
        normalized.contains('landslide') ||
        normalized.contains('tornado') ||
        normalized.contains('wind') ||
        normalized.contains('rain')) {
      return 'Natural disaster';
    }
    if (normalized.contains('attack') ||
        normalized.contains('robbery') ||
        normalized.contains('thief') ||
        normalized.contains('danger') ||
        normalized.contains('stalking') ||
        normalized.contains('abuse') ||
        normalized.contains('gun')) {
      return 'Security threat';
    }
    if (normalized.contains('trapped') ||
        normalized.contains('stuck') ||
        normalized.contains('lost') ||
        normalized.contains('stranded') ||
        normalized.contains('help')) {
      return 'Rescue / trapped situation';
    }

    return 'General emergency';
  }

  Future<void> _beginEmergencyCapture() async {
    if (!_sosActivated) {
      return;
    }

    if (!_cameraReady && !_speechAvailable) {
      if (mounted) {
        setState(() {
          _statusMessage =
              'Waiting for camera and microphone permissions. Evidence capture will start automatically.';
        });
      }
      return;
    }

    if (!_photoCaptureStarted &&
        _cameraController != null &&
        _cameraReady &&
        _cameraController!.value.isInitialized) {
      _photoCaptureStarted = true;
      _photoCaptureTimer = Timer(const Duration(seconds: 5), () async {
        if (_cameraController != null &&
            _cameraReady &&
            _cameraController!.value.isInitialized &&
            _photoPath == null) {
          await _capturePhoto();
        }
      });
    }

    if (!_voiceCaptureStarted && _speechAvailable && !_isListening) {
      _voiceCaptureStarted = true;
      await _toggleListening();
    }

    if (mounted) {
      setState(() {
        _dangerClassification = 'Listening for 60 seconds...';
        _statusMessage =
            'Voice recognition is active for 60 seconds. Photo capture is scheduled in 5 seconds.';
      });
    }

    _riskAssessmentTimer?.cancel();
    _riskAssessmentTimer = Timer(const Duration(seconds: 60), () async {
      if (_isListening) {
        await _speechToText.stop();
        if (mounted) {
          setState(() {
            _isListening = false;
          });
        }
      }
      _completeRiskAssessment();
    });
  }

  Future<void> _activateSos() async {
    if (_sosActivated) {
      return;
    }
    setState(() {
      _sosActivated = true;
      _voiceSelected = true;
      _dangerClassification = 'Assessing emergency type...';
      _statusMessage = 'Emergency mode is active. Starting automatic voice and photo capture...';
    });
    await _beginEmergencyCapture();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _bluetoothSubscription?.cancel();
    _bluetoothScanSubscription?.cancel();
    _relayService.stopAdvertising();
    _photoCaptureTimer?.cancel();
    _riskAssessmentTimer?.cancel();
    _outboxRetryTimer?.cancel();
    FlutterBluePlus.stopScan();
    _cameraController?.dispose();
    _messageController.dispose();
    _speechToText.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Header(),
                    const SizedBox(height: 16),
                    _ConnectivityCard(
                      isOnline: _isOnline,
                      isReady: _connectivityReady,
                    ),
                    const SizedBox(height: 8),
                    _LocationCard(
                      position: _position,
                      status: _locationStatus,
                      error: _locationError,
                      loading: _locationLoading,
                      onCapture: _captureLocation,
                    ),
                    const SizedBox(height: 8),
                    _BluetoothCard(
                      ready: _bluetoothReady,
                      nearbyCount: _nearbyRelayCount,
                      status: _relayStatus,
                    ),
                    const SizedBox(height: 8),
                    _RelayCard(
                      online: _isOnline,
                      relayMode: _isOnline
                          ? 'network relay + bluetooth mesh scan'
                          : 'offline mesh queue + bluetooth relay ready',
                    ),
                    const SizedBox(height: 16),
                    _SosButton(
                      activated: _sosActivated,
                      onTap: _activateSos,
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _sosActivated
                          ? _EmergencyPanel(
                              isListening: _isListening,
                              voiceTranscript: _voiceTranscript,
                              photoPath: _photoPath,
                              cameraReady: _cameraReady,
                              onSubmit: _submitSos,
                              sending: _sending,
                              statusMessage: _statusMessage,
                              dangerClassification: _dangerClassification,
                            )
                          : const _ActivationHint(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE53935).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.hub_outlined, color: Color(0xFFFF625D)),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CRISISMESH',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Communication beyond connectivity',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConnectivityCard extends StatelessWidget {
  const _ConnectivityCard({
    required this.isOnline,
    required this.isReady,
  });

  final bool isOnline;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final color = !isReady
        ? Colors.white54
        : isOnline
            ? const Color(0xFF66BB6A)
            : const Color(0xFFFFB74D);
    final label = !isReady
        ? 'CHECKING CONNECTION'
        : isOnline
            ? 'ONLINE'
            : 'OFFLINE READY';
    final description = !isReady
        ? 'Checking available network transports...'
        : isOnline
            ? 'A network transport is available'
            : 'SOS can be prepared without a network';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.position,
    required this.status,
    required this.error,
    required this.loading,
    required this.onCapture,
  });

  final Position? position;
  final String status;
  final String? error;
  final bool loading;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final hasLocation = position != null;
    final statusColor = error != null
        ? const Color(0xFFFF8A80)
        : hasLocation
            ? const Color(0xFF72D995)
            : Colors.white60;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: statusColor, size: 21),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'LOCATION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (hasLocation)
                const Icon(Icons.check_circle, color: Color(0xFF72D995), size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasLocation
                ? '${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'
                : status,
            style: TextStyle(color: statusColor, fontSize: 12),
          ),
          if (error != null) ...[
            const SizedBox(height: 5),
            Text(
              error!,
              style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading ? null : onCapture,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded, size: 18),
            label: Text(loading ? 'CAPTURING...' : 'CAPTURE GPS LOCATION'),
          ),
        ],
      ),
    );
  }
}

class _BluetoothCard extends StatelessWidget {
  const _BluetoothCard({
    required this.ready,
    required this.nearbyCount,
    required this.status,
  });

  final bool ready;
  final int nearbyCount;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = ready ? const Color(0xFF5DA9FF) : const Color(0xFFFFB74D);
    final label = ready
        ? (nearbyCount > 0 ? 'BLUETOOTH ACTIVE' : 'BLUETOOTH READY')
        : 'BLUETOOTH OFF';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ready
                      ? status
                      : 'Bluetooth scan is unavailable or disabled',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayCard extends StatelessWidget {
  const _RelayCard({
    required this.online,
    required this.relayMode,
  });

  final bool online;
  final String relayMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.sync_rounded : Icons.device_hub_rounded,
            color: online ? const Color(0xFF72D995) : const Color(0xFFFFB74D),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RELAY MODE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  relayMode,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationFailure implements Exception {
  const _LocationFailure(this.message);

  final String message;
}

class _SosButton extends StatelessWidget {
  const _SosButton({
    required this.activated,
    required this.onTap,
  });

  final bool activated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activated ? const Color(0xFF2EAA61) : const Color(0xFFE53935);
    final shadowColor = activated ? const Color(0x662EAA61) : const Color(0x66E53935);

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 0,
                  spreadRadius: 14,
                ),
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 36,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  activated ? Icons.check_rounded : Icons.priority_high_rounded,
                  size: 52,
                  color: Colors.white,
                ),
                const SizedBox(height: 6),
                Text(
                  activated ? 'SOS ACTIVE' : 'SOS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  activated ? 'Emergency capture active' : 'Tap once to activate',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          activated
              ? 'Emergency mode is active'
              : 'Tap once to capture voice, photo, and danger details',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: activated ? const Color(0xFF72D995) : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ActivationHint extends StatelessWidget {
  const _ActivationHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, color: Colors.white54, size: 18),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'One tap starts automatic voice and photo capture. No separate controls are required.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyPanel extends StatelessWidget {
  const _EmergencyPanel({
    required this.isListening,
    required this.voiceTranscript,
    required this.photoPath,
    required this.cameraReady,
    required this.onSubmit,
    required this.sending,
    required this.statusMessage,
    required this.dangerClassification,
  });

  final bool isListening;
  final String voiceTranscript;
  final String? photoPath;
  final bool cameraReady;
  final VoidCallback onSubmit;
  final bool sending;
  final String statusMessage;
  final String dangerClassification;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2EAA61).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'EMERGENCY DETAILS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111315),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Detected risk: $dangerClassification',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111315),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: isListening
                          ? const Color(0xFF72D995)
                          : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isListening
                            ? 'Voice is being captured automatically'
                            : 'Voice capture is preparing',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isListening)
                      const Icon(
                        Icons.fiber_manual_record,
                        color: Color(0xFFE53935),
                        size: 12,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  voiceTranscript,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (cameraReady)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111315),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    photoPath == null
                        ? Icons.camera_alt_outlined
                        : Icons.check_circle,
                    color: photoPath == null
                        ? Colors.white54
                        : const Color(0xFF72D995),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      photoPath == null
                          ? 'Photo capture is preparing automatically'
                          : 'Photo captured and attached',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (photoPath != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(photoPath!),
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: sending ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(sending ? 'TRANSMITTING...' : 'SEND SOS'),
          ),
          const SizedBox(height: 12),
          Text(
            statusMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
