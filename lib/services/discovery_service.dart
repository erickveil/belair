import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belair/models/device_model.dart';
import 'package:flutter/foundation.dart';

class DiscoveryService {
  static const int _port = 45454;
  RawDatagramSocket? _socket;
  final StreamController<List<Device>> _devicesController =
      StreamController<List<Device>>.broadcast();
  final Map<String, Device> _discoveredDevices = {};
  Timer? _broadcastTimer;
  bool _isDiscovering = false;

  Stream<List<Device>> get devicesStream => _devicesController.stream;

  Future<void> startDiscovery(Device myDevice) async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _discoveredDevices.clear();
    
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
    } catch (e) {
      debugPrint('Error starting discovery: $e');
      _isDiscovering = false;
    }
  }

  void stopDiscovery() {
    _broadcastTimer?.cancel();
    _socket?.close();
    _isDiscovering = false;
  }

  void _startBroadcasting(Device myDevice) {
    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
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
    });
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

      // Assuming we pass "myDevice" ID to filter self out in UI or here?
      // Let's filter in UI or Service if we know our ID. 
      // For now, just add everyone.
      
      _discoveredDevices[updatedDevice.id] = updatedDevice;
      _devicesController.add(_discoveredDevices.values.toList());
      
    } catch (e) {
      debugPrint('Error parsing broadcast: $e');
    }
  }
}
