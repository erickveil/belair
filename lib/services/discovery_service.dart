import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belair/models/device_model.dart';
import 'package:flutter/foundation.dart';

class DiscoveryService {
  static const int _port = 45454;
  static const Duration _broadcastInterval = Duration(seconds: 2);
  static const Duration _deviceTimeout = Duration(seconds: 6);
  RawDatagramSocket? _socket;
  final StreamController<List<Device>> _devicesController =
      StreamController<List<Device>>.broadcast();
  final Map<String, Device> _discoveredDevices = {};
  final Map<String, DateTime> _lastSeenAt = {};
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  Device? _myDevice;
  bool _isDiscovering = false;

  Stream<List<Device>> get devicesStream => _devicesController.stream;

  Future<void> startDiscovery(Device myDevice) async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _myDevice = myDevice;
    _discoveredDevices.clear();
    _lastSeenAt.clear();
    _devicesController.add(const []);
    
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port);
      _socket!.broadcastEnabled = true;
      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleIncomingData(datagram);
          }
        }
      });

      _startBroadcasting(myDevice);
      _startPruning();
    } catch (e) {
      debugPrint('Error starting discovery: $e');
      _isDiscovering = false;
    }
  }

  Future<void> refreshDiscovery() async {
    final myDevice = _myDevice;
    if (myDevice == null) {
      return;
    }

    stopDiscovery(clearDevices: true);
    await startDiscovery(myDevice);
  }

  void stopDiscovery({bool clearDevices = false}) {
    _broadcastTimer?.cancel();
    _pruneTimer?.cancel();
    _socket?.close();
    _socket = null;
    _isDiscovering = false;

    if (clearDevices) {
      _discoveredDevices.clear();
      _lastSeenAt.clear();
      _devicesController.add(const []);
    }
  }

  void _startBroadcasting(Device myDevice) {
    _broadcastPresence(myDevice);
    _broadcastTimer = Timer.periodic(_broadcastInterval, (timer) {
      _broadcastPresence(myDevice);
    });
  }

  void _startPruning() {
    _pruneTimer = Timer.periodic(_broadcastInterval, (timer) {
      final cutoff = DateTime.now().subtract(_deviceTimeout);
      final staleIds = _lastSeenAt.entries
          .where((entry) => entry.value.isBefore(cutoff))
          .map((entry) => entry.key)
          .toList();

      if (staleIds.isEmpty) {
        return;
      }

      for (final id in staleIds) {
        _lastSeenAt.remove(id);
        _discoveredDevices.remove(id);
      }

      _devicesController.add(_discoveredDevices.values.toList());
    });
  }

  void _broadcastPresence(Device myDevice) {
    if (_socket == null) return;
    try {
      final data = jsonEncode(myDevice.toJson());
      _socket!.send(
        utf8.encode(data),
        InternetAddress('255.255.255.255'),
        _port,
      );
    } catch (e) {
      debugPrint('Error broadcasting: $e');
    }
  }

  void _handleIncomingData(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final data = jsonDecode(message);
      final device = Device.fromJson(data);

      // Filter out self if possible, though checking ID is better
      // But we update IP from the packet address just in case
      // (The advertised IP in JSON might be stale if they changed networks, 
      // but usually the sender puts their current IP. 
      // Actually, relying on the source address of the packet is safer for connection.)
      
      final realIp = datagram.address.address;
      
      // If the device is me (checked by ID usually, but here checking IP might be tricky if loopback)
      // We will rely on the ID being unique.
      
      // Update the device with the source IP to be sure we can reach it
      final updatedDevice = Device(
        id: device.id,
        name: device.name,
        ip: realIp,
        port: device.port,
      );

      if (updatedDevice.id == _myDevice?.id) {
        return;
      }
      
      _discoveredDevices[updatedDevice.id] = updatedDevice;
      _lastSeenAt[updatedDevice.id] = DateTime.now();
      _devicesController.add(_discoveredDevices.values.toList());
      
    } catch (e) {
      debugPrint('Error parsing broadcast: $e');
    }
  }
}
