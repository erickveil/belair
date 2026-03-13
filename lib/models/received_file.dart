import 'dart:io';

class ReceivedFile {
  const ReceivedFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  File get file => File(path);

  factory ReceivedFile.fromFile(File file, FileStat stat) {
    return ReceivedFile(
      name: file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path,
      path: file.path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
    );
  }
}
