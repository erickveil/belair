import 'dart:async';
import 'dart:io';

import 'package:belair/models/device_model.dart';
import 'package:belair/services/discovery_service.dart';
import 'package:belair/services/permission_service.dart';
import 'package:belair/services/transfer_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Belair',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DiscoveryService _discoveryService = DiscoveryService();
  final TransferService _transferService = TransferService(); // Port 8080 by default
  final PermissionService _permissionService = PermissionService();
  final TextEditingController _ipController = TextEditingController();
  
  String? _myIp;
  Device? _myDevice;
  List<Device> _devices = [];
  bool _isDiscovering = false;
  String? _statusMessage;
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _permissionService.requestPermissions();
    
    // Get IP
    final info = NetworkInfo();
    _myIp = await info.getWifiIP();
    
    if (_myIp == null) {
      // Fallback or retry
      setState(() {
        _statusMessage = "Could not determine IP address. Connect to Wi-Fi.";
      });
    }

    // Get Device Name
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String deviceName = 'Unknown Device';
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      deviceName = androidInfo.model;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      deviceName = iosInfo.name;
    } else if (Platform.isMacOS) {
      final macInfo = await deviceInfo.macOsInfo;
      deviceName = macInfo.computerName;
    } else if (Platform.isWindows) {
      final winInfo = await deviceInfo.windowsInfo;
      deviceName = winInfo.computerName;
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      deviceName = linuxInfo.name;
    }

    // Start Server
    await _transferService.startServer();

    // Create Device Profile
    const uuid = Uuid();
    _myDevice = Device(
      id: uuid.v4(),
      name: deviceName,
      ip: _myIp ?? '0.0.0.0',
      port: _transferService.port,
    );

    setState(() {});

    // Start Discovery automatically
    _toggleDiscovery();
    
    // Listen to devices
    _discoveryService.devicesStream.listen((devices) {
      setState(() {
        _devices = devices;
      });
    });
  }

  void _toggleDiscovery() {
    if (_myDevice == null) return;

    if (_isDiscovering) {
      _discoveryService.stopDiscovery();
    } else {
      _discoveryService.startDiscovery(_myDevice!);
    }
    setState(() {
      _isDiscovering = !_isDiscovering;
    });
  }

  Future<void> _pickAndSendFile(Device target) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      setState(() {
        _isTransferring = true;
        _statusMessage = "Sending ${result.files.single.name}...";
      });

      String? error = await _transferService.sendFile(file, target);

      setState(() {
        _isTransferring = false;
        _statusMessage = error == null ? "File sent successfully!" : "Failed: $error";
      });
      
      if (!mounted) return;

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File Sent!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: $error')),
        );
      }
    }
  }

  Future<void> _sendToManualIp() async {
    final ip = _ipController.text;
    if (ip.isEmpty) return;
    
    // Create a temporary device target
    // Default port 8080 if not specified
    // Ideally we should allow port input too, but assuming 8080 for manual entry for now
    final target = Device(id: 'manual', name: 'Manual IP', ip: ip, port: 8080);
    
    await _pickAndSendFile(target);
  }

  @override
  void dispose() {
    _discoveryService.stopDiscovery();
    _transferService.stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Belair'),
        actions: [
          IconButton(
            icon: Icon(_isDiscovering ? Icons.radar : Icons.radar_outlined),
            onPressed: _toggleDiscovery,
            tooltip: _isDiscovering ? 'Stop Discovery' : 'Start Discovery',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Device', style: Theme.of(context).textTheme.labelLarge),
                    Text(
                      _myDevice?.name ?? 'Loading...',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      _myIp ?? 'No Connection',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                Icon(Icons.perm_device_information, size: 40, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ],
            ),
          ),
          
          if (_statusMessage != null)
             Padding(
               padding: const EdgeInsets.all(8.0),
               child: Text(_statusMessage!, style: TextStyle(color: _isTransferring ? Colors.blue : Colors.black)),
             ),

          const Divider(),

          // Manual Entry
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Receiver IP',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sendToManualIp,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),

          const Divider(),
          
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Nearby Devices', style: Theme.of(context).textTheme.titleMedium),
          ),

          // Device List
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.devices_other, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _isDiscovering ? 'Scanning for devices...' : 'Discovery stopped.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.computer),
                          title: Text(device.name),
                          subtitle: Text(device.ip),
                          trailing: IconButton(
                            icon: const Icon(Icons.upload_file),
                            onPressed: () => _pickAndSendFile(device),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
