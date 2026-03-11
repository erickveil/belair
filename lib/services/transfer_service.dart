import 'dart:io';
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

  TransferService({int port = 8080}) : _port = port;

  int get port => _server?.port ?? _port;

  Future<void> startServer() async {
    final router = Router();
    
    router.post('/upload', (Request request) async {
      final filename = request.headers['x-filename'] ?? 'received_file_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('Incoming file: $filename');
      
      try {
        final directory = await _getDownloadDirectory();
        if (directory == null) {
          debugPrint('Error: Could not access downloads directory');
          return Response.internalServerError(body: 'Could not access downloads directory');
        }

        final filePath = '${directory.path}${Platform.pathSeparator}$filename';
        debugPrint('Saving to: $filePath');
        
        final file = File(filePath);
        final sink = file.openWrite();
        
        try {
          await sink.addStream(request.read());
          await sink.close();
          debugPrint('File saved successfully: $filename');
          return Response.ok('File received');
        } catch (streamError) {
          debugPrint('Error during stream processing: $streamError');
          await sink.close();
          return Response.internalServerError(body: 'Error during stream processing: $streamError');
        }
      } catch (e, stack) {
        debugPrint('General error in /upload: $e\n$stack');
        return Response.internalServerError(body: 'Error saving file: $e');
      }
    });

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
    debugPrint('Serving at http://${_server!.address.host}:${_server!.port}');
  }

  Future<void> stopServer() async {
    await _server?.close();
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
         return errorBody.isNotEmpty ? errorBody : 'Server error ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('Error sending file: $e');
      return 'Connection error: $e';
    }
  }

  Future<Directory?> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
       // Request storage permission
       // Note: Managing permissions usually happens in UI layer, but we can check status here
       // For Android 10+ scoped storage might not need explicit permission for downloads folder if using MediaStore,
       // but direct file access often requires MANAGE_EXTERNAL_STORAGE or simpler READ/WRITE_EXTERNAL_STORAGE.
       // However, path_provider's getDownloadsDirectory is simpler.
       return await getDownloadsDirectory(); 
    } else if (Platform.isIOS) {
       return await getApplicationDocumentsDirectory(); // iOS doesn't have a public downloads folder easily accessible
    } else {
       return await getDownloadsDirectory();
    }
  }
}
