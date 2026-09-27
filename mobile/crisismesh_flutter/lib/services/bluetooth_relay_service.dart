import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/sos_packet.dart';

class BluetoothRelayService {
  static final Guid serviceUuid = Guid('8b7f0001-4f2a-4d3a-9c52-6f5c5f1a0001');
  static final Guid packetCharacteristicUuid =
      Guid('8b7f0002-4f2a-4d3a-9c52-6f5c5f1a0001');
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  Stream<Uint8List> get receivedPackets => _peripheral.onDataReceived;

  Future<bool> startAdvertising() async {
    final state = await _peripheral.start(
      advertiseData: AdvertiseDataCore(
        serviceUuid: serviceUuid.str,
        localName: 'CrisisMesh Relay',
      ),
      gattServer: GattServerSettings(
        characteristics: [
          GattCharacteristic.write(packetCharacteristicUuid.str),
        ],
      ),
    );
    return state == PeripheralBluetoothState.ready ||
        state == PeripheralBluetoothState.granted;
  }

  Future<void> stopAdvertising() => _peripheral.stop();

  Future<List<ScanResult>> scanRelayNodes({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final results = <ScanResult>[];
    final subscription = FlutterBluePlus.scanResults.listen((items) {
      for (final item in items) {
        if (item.advertisementData.serviceUuids
            .map((uuid) => uuid.toString().toLowerCase())
            .contains(serviceUuid.str.toLowerCase())) {
          if (!results.any((existing) =>
              existing.device.remoteId == item.device.remoteId)) {
            results.add(item);
          }
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [serviceUuid],
        timeout: timeout,
      );
      await Future<void>.delayed(timeout);
      return results;
    } finally {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  Future<bool> relayPacket(
    BluetoothDevice device,
    SosPacket packet,
  ) async {
    BluetoothCharacteristic? packetCharacteristic;

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 8),
      );
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid != serviceUuid) {
          continue;
        }
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == packetCharacteristicUuid &&
              (characteristic.properties.write ||
                  characteristic.properties.writeWithoutResponse)) {
            packetCharacteristic = characteristic;
            break;
          }
        }
      }

      if (packetCharacteristic == null) {
        return false;
      }

      final encoded = utf8.encode(jsonEncode(packet.toJson()));
      final chunks = <List<int>>[];
      for (var start = 0; start < encoded.length; start += 180) {
        final end = (start + 180 < encoded.length)
            ? start + 180
            : encoded.length;
        chunks.add(encoded.sublist(start, end));
      }

      for (final chunk in chunks) {
        await packetCharacteristic.write(
          Uint8List.fromList(chunk),
          withoutResponse: packetCharacteristic.properties.writeWithoutResponse,
        );
      }

      return true;
    } finally {
      await device.disconnect();
    }
  }
}
