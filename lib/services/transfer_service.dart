import 'dart:async';
import 'dart:io';
import 'package:belair/models/received_file.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:belair/models/device_model.dart';
import 'package:flutter/foundation.dart';

class TransferService {
  HttpServer? _server;
  final int _port;
  final Future<void> Function(ReceivedFile file)? _onFileReceived;
  final StreamController<List<ReceivedFile>> _receivedFilesController =
      StreamController<List<ReceivedFile>>.broadcast();
  List<ReceivedFile> _receivedFiles = const [];

  TransferService({
    int port = 8080,
    Future<void> Function(ReceivedFile file)? onFileReceived,
  }) : _port = port,
       _onFileReceived = onFileReceived;

  int get port => _server?.port ?? _port;
  Stream<List<ReceivedFile>> get receivedFilesStream =>
      _receivedFilesController.stream;
  List<ReceivedFile> get receivedFiles => List.unmodifiable(_receivedFiles);

  Future<void> initialize() async {
    await _refreshReceivedFiles();
  }

  Future<void> startServer() async {
    final router = Router();

    router.post('/upload', (Request request) async {
      final filename =
          request.headers['x-filename'] ??
          'received_file_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('Incoming file: $filename');

      try {
        final directory = await _getReceivedFilesDirectory();

        final filePath = '${directory.path}${Platform.pathSeparator}$filename';
        debugPrint('Saving to: $filePath');

        final file = File(filePath);
        final sink = file.openWrite();

        try {
          await sink.addStream(request.read());
          await sink.close();
          final receivedFile = await _refreshReceivedFiles(
            changedPath: file.path,
          );
          if (receivedFile != null) {
            await _onFileReceived?.call(receivedFile);
          }
          debugPrint('File saved successfully: $filename');
          return Response.ok('File received');
        } catch (streamError) {
          debugPrint('Error during stream processing: $streamError');
          await sink.close();
          return Response.internalServerError(
            body: 'Error during stream processing: $streamError',
          );
        }
      } catch (e, stack) {
        debugPrint('General error in /upload: $e\n$stack');
        return Response.internalServerError(body: 'Error saving file: $e');
      }
    });

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
    debugPrint('Serving at http://${_server!.address.host}:${_server!.port}');
  }

  Future<void> stopServer() async {
    await _server?.close();
  }

  Future<void> dispose() async {
    await _receivedFilesController.close();
  }

  Future<String?> sendFile(File file, Device target) async {
    final uri = Uri.parse('http://${target.ip}:${target.port}/upload');
    final filename = file.path.split(Platform.pathSeparator).last;

    final request = http.StreamedRequest('POST', uri);
    request.headers['x-filename'] = filename;
    request.contentLength = await file.length();

    // Open file stream
    final fileStream = file.openRead();
    fileStream.listen(
      (chunk) => request.sink.add(chunk),
      onDone: () => request.sink.close(),
      onError: (e) => request.sink.addError(e),
    );

    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        return null; // Success
      } else {
        final errorBody = await response.stream.bytesToString();
        debugPrint('Server error during send: $errorBody');
        return errorBody.isNotEmpty
            ? errorBody
            : 'Server error ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('Error sending file: $e');
      return 'Connection error: $e';
    }
  }

  Future<void> deleteReceivedFile(ReceivedFile file) async {
    final target = File(file.path);
    if (await target.exists()) {
      await target.delete();
      await _refreshReceivedFiles();
    }
  }

  Future<ReceivedFile?> _refreshReceivedFiles({String? changedPath}) async {
    final directory = await _getReceivedFilesDirectory();
    final entries = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();

    final receivedFiles = <ReceivedFile>[];
    for (final file in entries) {
      final stat = await file.stat();
      receivedFiles.add(ReceivedFile.fromFile(file, stat));
    }

    receivedFiles.sort(
      (left, right) => right.modifiedAt.compareTo(left.modifiedAt),
    );
    _receivedFiles = receivedFiles;
    _receivedFilesController.add(List.unmodifiable(_receivedFiles));

    if (changedPath == null) {
      return null;
    }

    for (final file in _receivedFiles) {
      if (file.path == changedPath) {
        return file;
      }
    }

    return null;
  }

  Future<Directory> _getReceivedFilesDirectory() async {
    if (Platform.isAndroid) {
      final directory = await getApplicationSupportDirectory();
      return Directory(
        '${directory.path}${Platform.pathSeparator}received_files',
      ).create(recursive: true);
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      return Directory(
        '${directory.path}${Platform.pathSeparator}received_files',
      ).create(recursive: true);
    } else {
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        return directory.create(recursive: true);
      }

      final fallback = await getApplicationSupportDirectory();
      return Directory(
        '${fallback.path}${Platform.pathSeparator}received_files',
      ).create(recursive: true);
    }
  }
}
