import 'package:flutter/services.dart';

class FileTransferService {
  FileTransferService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('morixterm/windows_rdp');

  final MethodChannel _channel;

  Future<void> upload(String localPath, String remotePath) => _channel.invokeMethod<void>('uploadFile', {'localPath': localPath, 'remotePath': remotePath});

  Future<void> download(String remotePath, String localPath) => _channel.invokeMethod<void>('downloadFile', {'remotePath': remotePath, 'localPath': localPath});
}
