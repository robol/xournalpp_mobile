import 'dart:typed_data';

Future<List<String>> listInternalFiles() async => [];
Future<List<String>> listInternalBlobs() async => [];
Future<Uint8List> readInternalFile(String name) async =>
    throw UnsupportedError('Internal storage is unavailable');
Future<void> writeInternalFile(String name, Uint8List data) async =>
    throw UnsupportedError('Internal storage is unavailable');
Future<void> deleteInternalFile(String name) async =>
    throw UnsupportedError('Internal storage is unavailable');

Future<T> withInternalLock<T>(Future<T> Function() action) => action();
