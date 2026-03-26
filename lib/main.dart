import 'dart:async';
import 'dart:io';

import 'package:belair/models/device_model.dart';
import 'package:belair/models/received_file.dart';
import 'package:belair/services/android_downloads_service.dart';
import 'package:belair/services/discovery_service.dart';
import 'package:belair/services/notification_service.dart';
import 'package:belair/services/permission_service.dart';
import 'package:belair/services/transfer_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
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
  final TextEditingController _ipController = TextEditingController();
  final Map<String, Device> _rememberedDevicesByEndpoint = <String, Device>{};
  late final DiscoveryService _discoveryService;
  late final TransferService _transferService;
  late final PermissionService _permissionService;
  late final NotificationService _notificationService;
  late final AndroidDownloadsService _androidDownloadsService;

  String? _myIp;
  Device? _myDevice;
  List<Device> _discoveredDevices = [];
  List<Device> _devices = [];
  List<ReceivedFile> _receivedFiles = [];
  bool _isDiscovering = false;
  bool _isRefreshingDiscovery = false;
  String? _statusMessage;
  bool _isTransferring = false;
  StreamSubscription<List<ReceivedFile>>? _receivedFilesSubscription;
  Set<String> _busyReceivedFilePaths = <String>{};
  String _appVersion = '-';

  @override
  void initState() {
    super.initState();
    _discoveryService = DiscoveryService();
    _permissionService = PermissionService();
    _notificationService = NotificationService();
    _androidDownloadsService = AndroidDownloadsService();
    _transferService = TransferService(
      onFileReceived: (file) async {
        await _notificationService.showDownloadComplete(file);
        if (!mounted) {
          return;
        }

        setState(() {
          _statusMessage = 'Received ${file.name}';
        });
      },
      onDeviceContact: (device) async {
        _rememberDevice(device);
      },
    );
    _initServices();
  }

  Future<void> _initServices() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = packageInfo.version;

    await _notificationService.initialize();
    await _permissionService.requestPermissions();
    await _transferService.initialize();
    _receivedFiles = _transferService.receivedFiles;
    _receivedFilesSubscription = _transferService.receivedFilesStream.listen((
      files,
    ) {
      if (!mounted) {
        return;
      }

      setState(() {
        _receivedFiles = files;
      });
    });

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
    unawaited(_setDiscoveryEnabled(true));

    // Listen to devices
    _discoveryService.devicesStream.listen((devices) {
      if (!mounted) {
        return;
      }

      setState(() {
        _discoveredDevices = devices;
        _devices = _mergeDevices(_discoveredDevices);
      });
    });
  }

  String _deviceEndpointKey(Device device) => '${device.ip}:${device.port}';

  Device _manualDeviceFromIp(String ip) {
    final trimmedIp = ip.trim();
    return Device(
      id: 'manual:$trimmedIp:8080',
      name: 'Device at $trimmedIp',
      ip: trimmedIp,
      port: 8080,
    );
  }

  List<Device> _mergeDevices(List<Device> discoveredDevices) {
    final mergedByEndpoint = <String, Device>{
      for (final device in _rememberedDevicesByEndpoint.values)
        _deviceEndpointKey(device): device,
    };

    for (final device in discoveredDevices) {
      mergedByEndpoint[_deviceEndpointKey(device)] = device;
    }

    final mergedDevices = mergedByEndpoint.values.toList();
    mergedDevices.sort(
      (left, right) => left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return mergedDevices;
  }

  void _rememberDevice(Device device) {
    if (_myDevice != null && device.id == _myDevice!.id) {
      return;
    }

    final endpointKey = _deviceEndpointKey(device);
    final existingDevice = _rememberedDevicesByEndpoint[endpointKey];
    final resolvedDevice = existingDevice == null ||
            existingDevice.name.startsWith('Device at ')
        ? device
        : existingDevice;

    _rememberedDevicesByEndpoint[endpointKey] = resolvedDevice;

    if (!mounted) {
      return;
    }

    setState(() {
      _devices = _mergeDevices(_discoveredDevices);
    });
  }

  Future<void> _toggleDiscovery() async {
    await _setDiscoveryEnabled(!_isDiscovering);
  }

  Future<void> _setDiscoveryEnabled(bool enabled) async {
    if (_myDevice == null) return;

    if (!enabled) {
      _discoveryService.stopDiscovery();
    } else {
      await _discoveryService.startDiscovery(_myDevice!);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isDiscovering = enabled;
      _statusMessage = enabled
          ? 'Discovery active. Broadcasting every 2 seconds.'
          : 'Discovery stopped.';
    });
  }

  Future<void> _refreshDiscovery() async {
    if (_myDevice == null || _isRefreshingDiscovery) {
      return;
    }

    setState(() {
      _isRefreshingDiscovery = true;
      _statusMessage = 'Refreshing discovery...';
    });

    try {
      if (_isDiscovering) {
        await _discoveryService.refreshDiscovery();
      } else {
        await _setDiscoveryEnabled(true);
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingDiscovery = false;
          _isDiscovering = true;
          _statusMessage =
              'Discovery refreshed. Waiting for nearby devices to announce.';
        });
      }
    }
  }

  Future<void> _pickAndSendFile(Device target) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      setState(() {
        _isTransferring = true;
        _statusMessage = "Sending ${result.files.single.name}...";
      });

      String? error = await _transferService.sendFile(
        file,
        target,
        senderDevice: _myDevice,
      );

      setState(() {
        _isTransferring = false;
        _statusMessage = error == null
            ? "File sent successfully!"
            : "Failed: $error";
      });

      if (!mounted) return;

      if (error == null) {
        _rememberDevice(target);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File Sent!')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send file: $error')));
      }
    }
  }

  Future<void> _sendToManualIp() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    final target = _manualDeviceFromIp(ip);

    await _pickAndSendFile(target);
  }

  @override
  void dispose() {
    _receivedFilesSubscription?.cancel();
    _discoveryService.stopDiscovery();
    _transferService.stopServer();
    _transferService.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _openReceivedFile(ReceivedFile file) async {
    final result = await OpenFilex.open(file.path);
    if (!mounted || result.type == ResultType.done) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open ${file.name}: ${result.message}')),
    );
  }

  Future<void> _shareReceivedFile(ReceivedFile file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: file.name),
    );
  }

  Future<void> _saveReceivedFileToDownloads(ReceivedFile file) async {
    if (!Platform.isAndroid) {
      return;
    }

    setState(() {
      _busyReceivedFilePaths = {..._busyReceivedFilePaths, file.path};
    });

    try {
      await _androidDownloadsService.saveToDownloads(file);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${file.name} to Downloads.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save ${file.name}: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyReceivedFilePaths = {..._busyReceivedFilePaths}
            ..remove(file.path);
        });
      }
    }
  }

  Future<void> _deleteReceivedFile(ReceivedFile file) async {
    await _transferService.deleteReceivedFile(file);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Deleted ${file.name}.')));
  }

  String _formatBytes(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex += 1;
    }

    final value = suffixIndex == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
    return '$value ${suffixes[suffixIndex]}';
  }

  void _showReceivedFilesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SingleChildScrollView(
              child: _buildReceivedFilesContent(constrainHeight: false),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceivedFilesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildReceivedFilesContent(constrainHeight: true),
      ),
    );
  }

  Widget _buildReceivedFilesContent({required bool constrainHeight}) {
    final fileList = _receivedFiles.isEmpty
        ? const Text('No received files yet.')
        : Column(
            children: [
              for (int index = 0; index < _receivedFiles.length; index++) ...[
                if (index > 0) const Divider(height: 16),
                _buildReceivedFileRow(_receivedFiles[index]),
              ],
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Received Files', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          _receivedFiles.isEmpty
              ? 'Files received on Android stay here until you open, share, delete, or save them to Downloads.'
              : '${_receivedFiles.length} file${_receivedFiles.length == 1 ? '' : 's'} ready.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (constrainHeight)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(child: fileList),
          )
        else
          fileList,
      ],
    );
  }

  Widget _buildReceivedFileRow(ReceivedFile file) {
    final isBusy = _busyReceivedFilePaths.contains(file.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(file.name, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          '${_formatBytes(file.sizeBytes)} • ${file.modifiedAt.toLocal()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _openReceivedFile(file),
              child: const Text('Open'),
            ),
            FilledButton.tonal(
              onPressed: isBusy
                  ? null
                  : () => _saveReceivedFileToDownloads(file),
              child: Text(isBusy ? 'Saving...' : 'Save to Downloads'),
            ),
            OutlinedButton(
              onPressed: () => _shareReceivedFile(file),
              child: const Text('Share'),
            ),
            OutlinedButton(
              onPressed: () => _deleteReceivedFile(file),
              child: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Belair'),
        actions: [
          if (Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.inbox_outlined),
              onPressed: _showReceivedFilesSheet,
              tooltip: 'Inbox',
            ),
          IconButton(
            icon: Icon(_isDiscovering ? Icons.radar : Icons.radar_outlined),
            onPressed: _toggleDiscovery,
            tooltip: _isDiscovering ? 'Stop Discovery' : 'Start Discovery',
          ),
          IconButton(
            icon: _isRefreshingDiscovery
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshingDiscovery ? null : _refreshDiscovery,
            tooltip: 'Refresh discovery',
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
                    Text(
                      'My Device',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      _myDevice?.name ?? 'Loading...',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      _myIp ?? 'No Connection',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      'Version $_appVersion',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Icon(
                  Icons.perm_device_information,
                  size: 40,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),

          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _isTransferring ? Colors.blue : Colors.black,
                ),
              ),
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

          if (Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildReceivedFilesCard(),
            ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Nearby Devices',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),

          // Device List
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.devices_other,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isDiscovering
                              ? 'Scanning for devices...'
                              : 'Discovery stopped.',
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
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
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
