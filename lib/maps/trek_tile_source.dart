import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';

/// Supplies tile bytes independently of projection or Flutter rendering.
abstract interface class TrekTileSource {
  /// Fetches one image or throws when the resource is unavailable.
  Future<Uint8List> fetch(Uri uri);

  /// Releases source-owned resources at app shutdown.
  void close();
}

/// Uses NASA's HTTPS resource URLs and a bounded in-memory byte cache.
final class HttpTrekTileSource implements TrekTileSource {
  final HttpClient _client = HttpClient()..connectionTimeout = _timeout;
  final _cache = <Uri, Uint8List>{};
  final _pending = <Uri, Future<Uint8List>>{};
  int _cacheBytes = 0;
  static const _timeout = Duration(seconds: 8);
  static const _maxTileBytes = 2 * 1024 * 1024;
  static const _maxCacheBytes = 16 * 1024 * 1024;

  @override
  Future<Uint8List> fetch(Uri uri) {
    if (uri.scheme != 'https') {
      return Future.error(const FormatException('HTTPS required'));
    }
    if (_cache.remove(uri) case final cached?) {
      _cache[uri] = cached;
      return SynchronousFuture(cached);
    }
    return _pending.putIfAbsent(
      uri,
      () => _download(uri).whenComplete(() {
        _pending.remove(uri);
      }),
    );
  }

  /// Reads only image data and rejects oversized or mislabeled HTTP responses.
  Future<Uint8List> _download(Uri uri) async {
    final request = await _client.getUrl(uri).timeout(_timeout);
    request.followRedirects = false;
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok ||
        response.headers.contentType?.primaryType != 'image' ||
        response.contentLength > _maxTileBytes) {
      await response.drain<void>().timeout(_timeout);
      throw const HttpException('Mars Trek tile unavailable');
    }
    final buffer = BytesBuilder();
    await for (final chunk in response.timeout(_timeout)) {
      if (buffer.length + chunk.length > _maxTileBytes) {
        request.abort();
        throw const HttpException('Mars Trek tile exceeds the size limit');
      }
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    _cache[uri] = bytes;
    _cacheBytes += bytes.length;
    while (_cacheBytes > _maxCacheBytes || _cache.length > 320) {
      _cacheBytes -= _cache.remove(_cache.keys.first)!.length;
    }
    return bytes;
  }

  @override
  void close() {
    _client.close(force: true);
    _cache.clear();
  }
}
