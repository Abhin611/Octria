import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'drive.dart';

const _scope = 'https://www.googleapis.com/auth/drive.file';
const _folderType = 'application/vnd.google-apps.folder';

/// The person's real Google Drive. Access comes from their Google account
/// through Firebase sign-in, asked for the first time they add a file, and is
/// kept only in memory for the hour Google allows.
class GoogleDrive implements DriveStore {
  GoogleDrive(this._auth, {http.Client? client})
    : _http = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _http;
  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  String? _tokenFor;
  final Map<String, String> _folders = {};

  Future<String> _access() async {
    final user = _auth.currentUser;
    if (user == null) throw const DriveFailure('Please sign in first.');
    if (_token != null &&
        _tokenFor == user.uid &&
        DateTime.now().isBefore(_expires)) {
      return _token!;
    }
    final google = user.providerData
        .where((p) => p.providerId == 'google.com')
        .firstOrNull;
    final provider = GoogleAuthProvider()..addScope(_scope);
    final hint = google?.email;
    if (hint != null && hint.isNotEmpty) {
      provider.setCustomParameters({'login_hint': hint});
    }
    final UserCredential got;
    try {
      if (google != null) {
        got = kIsWeb
            ? await user.reauthenticateWithPopup(provider)
            : await user.reauthenticateWithProvider(provider);
      } else {
        // Someone who signed in with email or GitHub links a Google account,
        // whose Drive then holds their files.
        got = kIsWeb
            ? await user.linkWithPopup(provider)
            : await user.linkWithProvider(provider);
      }
    } on FirebaseAuthException catch (e) {
      throw switch (e.code) {
        'popup-closed-by-user' ||
        'cancelled-popup-request' ||
        'web-context-canceled' ||
        'canceled' => const DriveFailure('', cancelled: true),
        'popup-blocked' => const DriveFailure(
          'The Google window was blocked. Allow pop-ups for Octria and try '
          'again.',
        ),
        'credential-already-in-use' => const DriveFailure(
          'That Google account already belongs to another Octria account. '
          'Pick a different one, or sign in with it instead.',
        ),
        'user-mismatch' => const DriveFailure(
          'Pick the same Google account you signed in with.',
        ),
        _ => DriveFailure('Google didn’t give access to Drive (${e.code}).'),
      };
    }
    final token = got.credential?.accessToken;
    if (token == null || token.isEmpty) {
      throw const DriveFailure('Google didn’t give access to Drive.');
    }
    _token = token;
    _tokenFor = user.uid;
    // Google's tokens last an hour; ask again a little before that.
    _expires = DateTime.now().add(const Duration(minutes: 55));
    return token;
  }

  Future<http.Response> _call(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var response = await send({'Authorization': 'Bearer ${await _access()}'});
    if (response.statusCode == 401) {
      _token = null;
      response = await send({'Authorization': 'Bearer ${await _access()}'});
    }
    if (response.statusCode >= 400) {
      final reason = _reason(response.body);
      if (reason == 'accessNotConfigured' || reason == 'SERVICE_DISABLED') {
        throw const DriveFailure(
          'Google Drive isn’t switched on for Octria yet. Whoever runs this '
          'Octria needs to enable the Drive API.',
        );
      }
      if (reason == 'storageQuotaExceeded') {
        throw const DriveFailure('Your Google Drive is full.');
      }
      if (response.statusCode == 403) {
        throw const DriveFailure(
          'Octria wasn’t allowed into your Drive. Try again and tick the box '
          'that lets it add files.',
        );
      }
      throw DriveFailure(
        'Drive said no (${response.statusCode}). Please retry.',
      );
    }
    return response;
  }

  static String? _reason(String body) {
    try {
      final error = (jsonDecode(body) as Map)['error'] as Map?;
      final errors = error?['errors'] as List?;
      final first = errors?.firstOrNull as Map?;
      return (first?['reason'] ?? error?['status']) as String?;
    } on Object {
      return null;
    }
  }

  static String _quoted(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  Future<String> _folder(String name, String? parent) async {
    final key = '${parent ?? ''}/$name';
    final known = _folders[key];
    if (known != null) return known;
    final q = [
      'name = ${_quoted(name)}',
      "mimeType = '$_folderType'",
      'trashed = false',
      if (parent != null) '${_quoted(parent)} in parents',
    ].join(' and ');
    final found = await _call(
      (h) => _http.get(
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': q,
          'fields': 'files(id)',
          'spaces': 'drive',
        }),
        headers: h,
      ),
    );
    final files = (jsonDecode(found.body) as Map)['files'] as List? ?? const [];
    String id;
    if (files.isNotEmpty) {
      id = (files.first as Map)['id'] as String;
    } else {
      final made = await _call(
        (h) => _http.post(
          Uri.https('www.googleapis.com', '/drive/v3/files', {'fields': 'id'}),
          headers: {...h, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'mimeType': _folderType,
            if (parent != null) 'parents': [parent],
          }),
        ),
      );
      id = (jsonDecode(made.body) as Map)['id'] as String;
    }
    _folders[key] = id;
    return id;
  }

  @override
  Future<DriveUpload> upload({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required String folder,
    required bool anyoneWithLink,
  }) async {
    if (bytes.length > kMaxUploadBytes) throw const DriveFailure(tooBig);
    final root = await _folder('Octria', null);
    final room = await _folder(
      folder.trim().isEmpty ? 'Classroom' : folder.trim(),
      root,
    );
    final part = multipartBody(
      {
        'name': name,
        'parents': [room],
      },
      mimeType,
      bytes,
    );
    final sent = await _call(
      (h) => _http.post(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
          'uploadType': 'multipart',
          'fields': 'id,name,mimeType,size,webViewLink',
        }),
        headers: {
          ...h,
          'Content-Type': 'multipart/related; boundary=${part.boundary}',
        },
        body: part.body,
      ),
    );
    final d = jsonDecode(sent.body) as Map;
    final id = d['id'] as String;
    if (anyoneWithLink) await setLinkSharing(id, on: true);
    return DriveUpload(
      id: id,
      name: (d['name'] as String?) ?? name,
      mimeType: (d['mimeType'] as String?) ?? mimeType,
      size: int.tryParse('${d['size']}') ?? bytes.length,
      url:
          (d['webViewLink'] as String?) ??
          'https://drive.google.com/file/d/$id/view',
    );
  }

  @override
  Future<void> setLinkSharing(String fileId, {required bool on}) async {
    if (on) {
      await _call(
        (h) => _http.post(
          Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/$fileId/permissions',
          ),
          headers: {...h, 'Content-Type': 'application/json'},
          body: jsonEncode({'role': 'reader', 'type': 'anyone'}),
        ),
      );
      return;
    }
    try {
      await _call(
        (h) => _http.delete(
          Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/$fileId/permissions/anyoneWithLink',
          ),
          headers: h,
        ),
      );
    } on DriveFailure {
      // Already private, or gone from Drive: nothing left to stop.
    }
  }
}
