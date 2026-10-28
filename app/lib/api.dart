import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The SideProof backend. The web build talks to the host it was served from; the APK gets
/// the address at build time: --dart-define=API_BASE=https://...
class Api {
  Api._(this.base, this.device);

  final String base;
  final String device;

  static Future<Api> open() async {
    const configured = String.fromEnvironment('API_BASE');
    final base = configured.isNotEmpty ? configured : (kIsWeb ? Uri.base.origin : '');
    final prefs = await SharedPreferences.getInstance();
    var device = prefs.getString('device');
    if (device == null) {
      final r = Random.secure();
      device = base64Url.encode(List.generate(18, (_) => r.nextInt(256)));
      await prefs.setString('device', device);
    }
    return Api._(base, device);
  }

  Map<String, String> get _headers => {'X-Device': device};

  Uri _u(String path) => Uri.parse('$base$path');

  dynamic _decode(http.Response r) {
    final body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      throw ApiError(body is Map && body['detail'] is String ? body['detail'] : 'Server error ${r.statusCode}');
    }
    return body;
  }

  Future<List<dynamic>> trials() async => _decode(await http.get(_u('/api/trials'), headers: _headers));

  Future<Trial> trial(String id) async => Trial(_decode(await http.get(_u('/api/trials/$id'), headers: _headers)));

  Future<Trial> demo([String id = '']) async => Trial(_decode(await http.get(_u('/api/demo${id.isEmpty ? '' : '?id=$id'}'))));

  /// The finished demo trials, newest first.
  Future<List<Trial>> demos() async {
    final list = _decode(await http.get(_u('/api/demos'))) as List;
    return Future.wait([for (final d in list) demo(d['id'] as String)]);
  }

  Future<Map<String, dynamic>> product(String code) async => _decode(await http.get(_u('/api/products/$code')));

  Future<Trial> create({String product = '', String listing = '', String code = '', Uint8List? label}) async {
    final req = http.MultipartRequest('POST', _u('/api/trials'))
      ..headers.addAll(_headers)
      ..fields.addAll({'product': product, 'listing': listing, 'code': code});
    if (label != null) req.files.add(http.MultipartFile.fromBytes('label', label, filename: 'label.jpg'));
    return Trial(_decode(await http.Response.fromStream(await req.send())));
  }

  /// A Trial, or a Retake when the photo can't be measured fairly (no units spent).
  Future<Object> scan(String id, Uint8List photo) async {
    final req = http.MultipartRequest('POST', _u('/api/trials/$id/scans'))
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes('photo', photo, filename: 'scan.jpg'));
    final body = _decode(await http.Response.fromStream(await req.send()));
    return body['retake'] != null ? Retake(List<String>.from(body['retake'])) : Trial(body);
  }

  /// The claims' promise: YouCam AI Skin Simulation on the baseline photo (JPEG bytes).
  Future<Uint8List> promise(String id, Uint8List photo) async {
    final req = http.MultipartRequest('POST', _u('/api/trials/$id/promise'))
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes('photo', photo, filename: 'baseline.jpg'));
    final body = _decode(await http.Response.fromStream(await req.send()));
    return dataUrlBytes(body['image']);
  }

  String url(String path) => '$base$path';

  Future<Trial> start(String id) async => Trial(_decode(await http.post(_u('/api/trials/$id/start'), headers: _headers)));

  Future<Trial> finish(String id) async => Trial(_decode(await http.post(_u('/api/trials/$id/verdict'), headers: _headers)));
}

Uint8List dataUrlBytes(String url) => base64Decode(url.substring(url.indexOf(',') + 1));

class ApiError implements Exception {
  ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Retake {
  Retake(this.reasons);
  final List<String> reasons;
}

/// Read-only view of the trial JSON the backend returns.
class Trial {
  Trial(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'];
  String get product => json['product'];
  String get status => json['status'];
  Map<String, dynamic> get plan => json['plan'] ?? {};
  Map<String, dynamic>? get decision => json['decision'];
  Map<String, dynamic>? get verdict => json['verdict'];
  String? get skinType => json['skin_type'];
  String get treatedSide => json['treated_side'];
  bool get treatedOnImageLeft => json['treated_image_side'] == 'img_left';
  double get hoursIn => (json['hours_in'] as num).toDouble();
  List<dynamic> get scans => json['scans'];
  List<dynamic> get agentLog => json['agent_log'] ?? [];
  Map<String, dynamic>? get media => json['media'];
  Map<String, dynamic> get concerns => json['stats']['concerns'];
  List<dynamic> get harm => json['stats']['harm'];

  int get baselineScans => scans.where((s) => s['phase'] == 'baseline').length;
  int get trialScans => scans.where((s) => s['phase'] == 'trial').length;
  bool get thinking => decision?['state'] == 'thinking';
  bool get canStart => status == 'baseline' && (decision?['allowed'] as List?)?.contains('start') == true;
  bool get measured => concerns.values.any((c) => c['state'] == 'measured');
}
