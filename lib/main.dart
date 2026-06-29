import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http; // 이 줄을 꼭 추가하세요!
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 자동으로 생성된 파일입니다.
import 'package:firebase_storage/firebase_storage.dart'; // 이 줄을 추가하세요!
import 'package:cloud_firestore/cloud_firestore.dart'; // 나중에 DB 저장할 때 필요하니 미리 추가해두세요.
import 'package:permission_handler/permission_handler.dart'; // ◀ 맨 위에 추가
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart' as web_saver;
import 'package:geocoding/geocoding.dart';
import 'package:archive/archive_io.dart';
import 'package:url_launcher/url_launcher.dart'; // ◀ 외부 링크 열기용
import 'package:media_scanner/media_scanner.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'dart:async';
import 'package:url_launcher/link.dart';
import 'models/lat_lng.dart';





// --- [데이터 모델] ---
class MapGroup {
  String name;
  int colorValue;
  bool isVisible;
  MapGroup({required this.name, required this.colorValue, this.isVisible = true});

  Map<String, dynamic> toJson() => {'name': name, 'colorValue': colorValue, 'isVisible': isVisible};
  factory MapGroup.fromJson(Map<String, dynamic> json) => MapGroup(
      name: json['name'], colorValue: json['colorValue'], isVisible: json['isVisible'] ?? true);
  
  Color get color => Color(colorValue);
}

class PhotoItem {
  String filePath;
  String comment;
  PhotoItem({required this.filePath, this.comment = ""});
  Map<String, dynamic> toJson() => {'filePath': filePath, 'comment': comment};
  factory PhotoItem.fromJson(Map<String, dynamic> json) => PhotoItem(filePath: json['filePath'], comment: json['comment'] ?? "");
}

class _CompressedFieldPhoto {
  final XFile source;
  final File file;
  final int sortIndex;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final bool isTemporary;

  _CompressedFieldPhoto({
    required this.source,
    required this.file,
    required this.sortIndex,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.isTemporary,
  });
}

class _FieldPhotoFailure {
  final XFile source;
  final int sortIndex;
  final String message;

  _FieldPhotoFailure({
    required this.source,
    required this.sortIndex,
    required this.message,
  });
}

class _FieldPhotoUploadResult {
  final String batchId;
  final int selectedCount;
  final int compressedCount;
  final int zipEntryCount;
  final int uploadedCount;
  final int failedCount;
  final int originalTotalBytes;
  final int compressedTotalBytes;
  final int oversizedCompressedCount;
  final int elapsedMs;
  final int compressElapsedMs;
  final int uploadElapsedMs;
  final int zipSizeBytes;
  final bool storageVerified;
  final bool firestoreVerified;
  final bool recoverable;
  final String? errorMessage;
  final List<_FieldPhotoFailure> failures;

  _FieldPhotoUploadResult({
    required this.batchId,
    required this.selectedCount,
    required this.compressedCount,
    required this.zipEntryCount,
    required this.uploadedCount,
    required this.failedCount,
    required this.originalTotalBytes,
    required this.compressedTotalBytes,
    required this.oversizedCompressedCount,
    required this.elapsedMs,
    required this.compressElapsedMs,
    required this.uploadElapsedMs,
    required this.zipSizeBytes,
    required this.storageVerified,
    required this.firestoreVerified,
    required this.recoverable,
    this.errorMessage,
    required this.failures,
  });
}

enum _FieldPhotoUploadStatus {
  idle,
  compressing,
  uploading,
  retrying,
  uploaded,
  failed,
}

typedef _FieldPhotoProgress = void Function(
  _FieldPhotoUploadStatus status,
  int compressedCount,
  int uploadedCount,
  int failedCount,
  String message,
);

class _PendingFieldPhotoUpload {
  final String batchId;
  final String zipPath;
  final String zipStoragePath;
  final String zipFileName;
  final String teamName;
  final String date;
  final int createdAtMillis;
  final int photoCount;
  final int uploadedCount;
  final int failedCount;
  final int originalTotalBytes;
  final int compressedTotalBytes;
  final int oversizedCompressedCount;
  final int compressElapsedMs;
  final int zipSizeBytes;
  final int restorePromptIgnoredAtMillis;
  final int selectedCount;
  final int zipEntryCount;
  final bool storageUploaded;
  final bool firestoreSaved;
  final bool recoverable;
  final String errorMessage;

  _PendingFieldPhotoUpload({
    required this.batchId,
    required this.zipPath,
    required this.zipStoragePath,
    required this.zipFileName,
    required this.teamName,
    required this.date,
    required this.createdAtMillis,
    required this.photoCount,
    required this.uploadedCount,
    required this.failedCount,
    required this.originalTotalBytes,
    required this.compressedTotalBytes,
    required this.oversizedCompressedCount,
    required this.compressElapsedMs,
    required this.zipSizeBytes,
    this.restorePromptIgnoredAtMillis = 0,
    this.selectedCount = 0,
    this.zipEntryCount = 0,
    this.storageUploaded = false,
    this.firestoreSaved = false,
    this.recoverable = false,
    this.errorMessage = '',
  });

  Map<String, dynamic> toJson() => {
        'batchId': batchId,
        'zipPath': zipPath,
        'zipStoragePath': zipStoragePath,
        'zipFileName': zipFileName,
        'teamName': teamName,
        'date': date,
        'createdAt': createdAtMillis,
        'photoCount': photoCount,
        'uploadedCount': uploadedCount,
        'failedCount': failedCount,
        'originalTotalBytes': originalTotalBytes,
        'compressedTotalBytes': compressedTotalBytes,
        'oversizedCompressedCount': oversizedCompressedCount,
        'compressElapsedMs': compressElapsedMs,
        'zipSizeBytes': zipSizeBytes,
        'restorePromptIgnoredAtMillis': restorePromptIgnoredAtMillis,
        'selectedCount': selectedCount,
        'zipEntryCount': zipEntryCount,
        'storageUploaded': storageUploaded,
        'firestoreSaved': firestoreSaved,
        'recoverable': recoverable,
        'errorMessage': errorMessage,
      };

  factory _PendingFieldPhotoUpload.fromJson(Map<String, dynamic> json) {
    int readInt(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool readBool(String key) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      final text = value?.toString().toLowerCase().trim() ?? '';
      return text == 'true' || text == '1' || text == 'yes';
    }

    return _PendingFieldPhotoUpload(
      batchId: json['batchId']?.toString() ?? '',
      zipPath: json['zipPath']?.toString() ?? '',
      zipStoragePath: json['zipStoragePath']?.toString() ?? '',
      zipFileName: json['zipFileName']?.toString() ?? '',
      teamName: json['teamName']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      createdAtMillis: readInt('createdAt'),
      photoCount: readInt('photoCount'),
      uploadedCount: readInt('uploadedCount'),
      failedCount: readInt('failedCount'),
      originalTotalBytes: readInt('originalTotalBytes'),
      compressedTotalBytes: readInt('compressedTotalBytes'),
      oversizedCompressedCount: readInt('oversizedCompressedCount'),
      compressElapsedMs: readInt('compressElapsedMs'),
      zipSizeBytes: readInt('zipSizeBytes'),
      restorePromptIgnoredAtMillis: readInt('restorePromptIgnoredAtMillis'),
      selectedCount: readInt('selectedCount'),
      zipEntryCount: readInt('zipEntryCount'),
      storageUploaded: readBool('storageUploaded'),
      firestoreSaved: readBool('firestoreSaved'),
      recoverable: readBool('recoverable'),
      errorMessage: json['errorMessage']?.toString() ?? '',
    );
  }

  _PendingFieldPhotoUpload copyWith({
    int? restorePromptIgnoredAtMillis,
    int? selectedCount,
    int? zipEntryCount,
    bool? storageUploaded,
    bool? firestoreSaved,
    bool? recoverable,
    String? errorMessage,
  }) {
    return _PendingFieldPhotoUpload(
      batchId: batchId,
      zipPath: zipPath,
      zipStoragePath: zipStoragePath,
      zipFileName: zipFileName,
      teamName: teamName,
      date: date,
      createdAtMillis: createdAtMillis,
      photoCount: photoCount,
      uploadedCount: uploadedCount,
      failedCount: failedCount,
      originalTotalBytes: originalTotalBytes,
      compressedTotalBytes: compressedTotalBytes,
      oversizedCompressedCount: oversizedCompressedCount,
      compressElapsedMs: compressElapsedMs,
      zipSizeBytes: zipSizeBytes,
      restorePromptIgnoredAtMillis:
          restorePromptIgnoredAtMillis ?? this.restorePromptIgnoredAtMillis,
      selectedCount: selectedCount ?? this.selectedCount,
      zipEntryCount: zipEntryCount ?? this.zipEntryCount,
      storageUploaded: storageUploaded ?? this.storageUploaded,
      firestoreSaved: firestoreSaved ?? this.firestoreSaved,
      recoverable: recoverable ?? this.recoverable,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SiteData {
  String id;
  double lat, lng;
  String title, description;
  String address; 
  MapGroup group;
  List<PhotoItem> photos;
  String? canonicalMarkerId, originalMarkerId, sourceMarkerId, parentMarkerId;
  bool isChecked; // ✅ 마커 상태 확인용 변수

  SiteData({
    required this.id, 
    required this.lat, 
    required this.lng, 
    required this.title, 
    required this.description, 
    required this.address, 
    required this.group, 
    required this.photos, 
    this.canonicalMarkerId,
    this.originalMarkerId,
    this.sourceMarkerId,
    this.parentMarkerId,
    this.isChecked = false // ✅ 기본값 추가
  });

  // ⭐ [복구] 기존에 있던 위치 좌표(position) 가져오기/설정 코드 (이게 없어서 오류가 났습니다!)
  LatLng get position => LatLng(lat, lng);
  set position(LatLng pos) { 
    lat = pos.latitude; 
    lng = pos.longitude;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'lat': lat, 'lng': lng, 'title': title, 'description': description, 
    'address': address, 'group': group.toJson(), 'photos': photos.map((p) => p.toJson()).toList(),
    if (canonicalMarkerId != null) 'canonicalMarkerId': canonicalMarkerId,
    if (originalMarkerId != null) 'originalMarkerId': originalMarkerId,
    if (sourceMarkerId != null) 'sourceMarkerId': sourceMarkerId,
    if (parentMarkerId != null) 'parentMarkerId': parentMarkerId,
    'isChecked': isChecked // ✅ JSON 저장 시 포함
  };

  factory SiteData.fromJson(Map<String, dynamic> json) => SiteData(
    id: json['id'], lat: json['lat'], lng: json['lng'], 
    title: json['title'], description: json['description'], 
    address: json['address'] ?? "주소 정보 없음", 
    group: MapGroup.fromJson(json['group']), 
    photos: (json['photos'] as List).map((p) => PhotoItem.fromJson(p)).toList(),
    canonicalMarkerId: json['canonicalMarkerId']?.toString(),
    originalMarkerId: json['originalMarkerId']?.toString(),
    sourceMarkerId: json['sourceMarkerId']?.toString(),
    parentMarkerId: json['parentMarkerId']?.toString(),
    isChecked: json['isChecked'] == true || json['isChecked'] == 'true' || json['checked'] == true || json['checked'] == 'true' || json['isOn'] == true || json['isOn'] == 'true' // ✅ JSON 불러올 때 포함
  );
}

class LineData {
  String id, title, description;
  List<String> markerIds;
  List<LatLng> points;
  int colorValue;
  bool isVisible; // ✅ [추가]
  String? canonicalLineId, originalLineId, sourceLineId, parentLineId;

  LineData({
    required this.id, 
    required this.title, 
    required this.description, 
    required this.points, 
    required this.markerIds, 
    required this.colorValue,
    this.isVisible = true, // ✅ [수정] 여기에 ' = true'가 꼭 있어야 합니다!
    this.canonicalLineId,
    this.originalLineId,
    this.sourceLineId,
    this.parentLineId,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 
    'title': title, 
    'description': description, 
    'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(), 
    'markerIds': markerIds, 
    'colorValue': colorValue,
    'isVisible': isVisible, // ✅ 저장 포함
    if (canonicalLineId != null) 'canonicalLineId': canonicalLineId,
    if (originalLineId != null) 'originalLineId': originalLineId,
    if (sourceLineId != null) 'sourceLineId': sourceLineId,
    if (parentLineId != null) 'parentLineId': parentLineId,
  };

  factory LineData.fromJson(Map<String, dynamic> json) => LineData(
    id: json['id'], 
    title: json['title'], 
    description: json['description'], 
    points: (json['points'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList(), 
    markerIds: List<String>.from(json['markerIds'] ?? []), 
    colorValue: json['colorValue'],
    isVisible: json['isVisible'] ?? true, // ✅ 불러오기 포함
    canonicalLineId: json['canonicalLineId']?.toString(),
    originalLineId: json['originalLineId']?.toString(),
    sourceLineId: json['sourceLineId']?.toString(),
    parentLineId: json['parentLineId']?.toString(),
  );
}
// --- [관리자용 팀 데이터 클래스] ---
class TeamData {
  String teamName;
  String teamPw;
  bool isVisible;
  List<MapGroup> groups;
  Map<String, SiteData> markers;
  Map<String, LineData> lines;
  TeamData({required this.teamName, required this.teamPw, this.isVisible = true, required this.groups, required this.markers, required this.lines});
}

// --- [앱 진입 및 로그인 로직] ---
void main() async {
  // 1. 플러터 프레임워크가 준비될 때까지 기다림
  WidgetsFlutterBinding.ensureInitialized(); 

  // ⭐ 2. 하단 상태바(내비게이션 바)와 상단바를 숨김 (몰입 모드)
  // 사용자가 화면 끝을 쓸어올릴 때만 잠시 나타났다가 자동으로 다시 숨겨집니다.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // 3. 구글 Firebase 서버와 내 앱을 연결 (초기화)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 4. 앱 실행
  runApp(const MaterialApp(home: AuthCheck(), debugShowCheckedModeBanner: false));
}

// --- [앱 진입 및 로그인 로직] ---
class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});
  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  bool _isLoggedIn = false, _isAdmin = false;
  String _teamName = "", _teamPw = "";

  @override
  void initState() { 
    super.initState(); 
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!kIsWeb) {
  setLocaleIdentifier("ko_KR"); 
} 
  
  _checkLoginStatus(); 
  _requestPermissions();
}

  // ✅ [수정] 저장소 권한(모든 파일 접근) 요청 추가
  Future<void> _requestPermissions() async {
    // 1. 기본 권한 요청 (위치, 카메라, 저장소)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.camera,
      Permission.storage, // 구버전 안드로이드용
    ].request();

    // 2. 안드로이드 11(API 30) 이상일 경우 '모든 파일 접근' 권한 별도 확인
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }
    }

    if (statuses[Permission.location]!.isDenied || statuses[Permission.camera]!.isDenied) {
      debugPrint("현장 관리를 위해 권한이 꼭 필요합니다.");
    }
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    final teamName = prefs.getString('teamName') ?? "";
    final teamPw = prefs.getString('teamPw') ?? "";

    if (!isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _isLoggedIn = false;
        _isAdmin = false;
        _teamName = "";
        _teamPw = "";
      });
      return;
    }

    if (isAdmin) {
      if (!mounted) return;
      setState(() {
        _isLoggedIn = isLoggedIn;
        _isAdmin = isAdmin;
        _teamName = teamName;
        _teamPw = teamPw;
      });
      return;
    }

    try {
      if (teamName.isEmpty || teamPw.isEmpty) {
        await _clearSavedLogin(prefs);
        if (!mounted) return;
        setState(() {
          _isLoggedIn = false;
          _isAdmin = false;
          _teamName = "";
          _teamPw = "";
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('teams')
          .doc(teamName)
          .get();
      final data = doc.data();
      final storedPw = data?['teamPw']?.toString() ?? '';

      if (!doc.exists || storedPw != teamPw) {
        await _clearSavedLogin(prefs);
        if (!mounted) return;
        setState(() {
          _isLoggedIn = false;
          _isAdmin = false;
          _teamName = "";
          _teamPw = "";
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _isLoggedIn = true;
        _isAdmin = false;
        _teamName = teamName;
        _teamPw = teamPw;
      });
    } catch (e) {
      debugPrint("저장된 로그인 정보 확인 실패: $e");
      await _clearSavedLogin(prefs);
      if (!mounted) return;
      setState(() {
        _isLoggedIn = false;
        _isAdmin = false;
        _teamName = "";
        _teamPw = "";
      });
    }
  }

  Future<void> _clearSavedLogin(SharedPreferences prefs) async {
    await prefs.setBool('isLoggedIn', false);
    await prefs.setBool('isAdmin', false);
    await prefs.remove('teamName');
    await prefs.remove('teamPw');
  }

  void _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSavedLogin(prefs);
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _isAdmin = false;
      _teamName = "";
      _teamPw = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isLoggedIn 
      ? MapSample(isAdmin: _isAdmin, teamName: _teamName, teamPw: _teamPw, onLogout: _performLogout)
      : LoginScreen(
          onLoginSuccess: (admin, name, pw) => setState(() {
            _isAdmin = admin;
            _teamName = name;
            _teamPw = pw;
            _isLoggedIn = true;
          }),
        );
  }
}
// ◀ 여기서 끊고 바로 아래에 LoginScreen 클래스가 오면 됩니다.

class InvalidTeamPasswordException implements Exception {
  const InvalidTeamPasswordException();
}

class LoginScreen extends StatefulWidget {
  final Function(bool, String, String) onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController tCtrl = TextEditingController();
  final TextEditingController pCtrl = TextEditingController();
  
  // ✅ 로딩 상태를 관리하는 변수
  bool _isLoggingIn = false;

  Future<void> _ensureTeamDocumentOnLogin(String teamName, String teamPw) async {
    final docRef = FirebaseFirestore.instance.collection('teams').doc(teamName);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        transaction.set(docRef, {
          'teamName': teamName,
          'teamPw': teamPw,
          'isVisible': true,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
          'groups': <Map<String, dynamic>>[],
          'markers': <Map<String, dynamic>>[],
          'lines': <Map<String, dynamic>>[],
        });
        return;
      }

      final data = snapshot.data();
      final storedPw = data?['teamPw']?.toString() ?? '';

      if (storedPw != teamPw) {
        throw const InvalidTeamPasswordException();
      }

      transaction.set(docRef, {
        'teamName': teamName,
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 메인 로그인 UI
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.map_sharp, size: 80, color: Colors.green),
                    const SizedBox(height: 20),
                    const Text("현장 관리 시스템",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 40),
                    TextField(
                        controller: tCtrl,
                        decoration: const InputDecoration(
                            labelText: "팀명", border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    TextField(
                        controller: pCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: "비밀번호", border: OutlineInputBorder())),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: _isLoggingIn ? null : () async { // ✅ 로딩 중 버튼 클릭 방지
                        final teamName = tCtrl.text.trim();
                        final teamPw = pCtrl.text;
                        if (teamName.isEmpty || teamPw.isEmpty) return;

                        // ✅ 2. 로딩바 시작
                        setState(() { _isLoggingIn = true; });

                        try {
                          final prefs = await SharedPreferences.getInstance();
                          final bool admin = (teamName == "admin" && teamPw == "1234");

                          if (!admin) {
                            await _ensureTeamDocumentOnLogin(teamName, teamPw);

                            List<String> registered = prefs.getStringList('registered_teams') ?? [];
                            String entry = "$teamName|$teamPw";
                            if (!registered.contains(entry)) {
                              registered.add(entry);
                              await prefs.setStringList('registered_teams', registered);
                            }
                          }

                          await prefs.setBool('isLoggedIn', true);
                          await prefs.setBool('isAdmin', admin);
                          await prefs.setString('teamName', teamName);
                          await prefs.setString('teamPw', teamPw);

                          // 약간의 지연 시간을 주어 로딩바가 보이게 함 (선택 사항)
                          await Future.delayed(const Duration(milliseconds: 500));

                          widget.onLoginSuccess(admin, teamName, teamPw);
                        } on InvalidTeamPasswordException {
                          if (!mounted) return;
                          setState(() {
                            _isLoggingIn = false;
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("비밀번호가 올바르지 않습니다."),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _isLoggingIn = false;
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("로그인 정보를 확인하지 못했습니다. 네트워크 연결 후 다시 시도해 주세요."),
                            ),
                          );

                          debugPrint("로그인 에러: $e");
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.green,
                      ),
                      child: const Text("로그인",
                          style: TextStyle(color: Colors.white, fontSize: 18)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. ⭐ [추가] 화면 맨 위 로그인 알림 바
          if (_isLoggingIn)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea( // 노치 영역 침범 방지
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 15),
                      Text("로그인 정보를 확인 중입니다...",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
// --- [지도 메인 화면] ---
class MapSample extends StatefulWidget {
  final bool isAdmin; final String teamName; final String teamPw; final VoidCallback onLogout;
  const MapSample({super.key, required this.isAdmin, required this.teamName, required this.teamPw, required this.onLogout});
  @override
  State<MapSample> createState() => MapSampleState();
}


class MapSampleState extends State<MapSample> with WidgetsBindingObserver {
  static const bool _verboseMapDebug = false;
  static const String _nativeKakaoMapViewType = 'field_manager/native_kakao_map';
  static const MethodChannel _nativeKakaoMapCommands = MethodChannel('field_manager/native_kakao_map_commands');
  static const MethodChannel _nativeKakaoMapEvents = MethodChannel('field_manager/native_kakao_map_events');
  static const bool _enableNativeMarkerPerformanceTest = false;
  static const int _nativeMarkerPerformanceTestCount = 400;
  static const int _nativeFocusedZoomLevel = 18;
  static const int fieldPhotoMaxDimension = 1600;
  static const int fieldPhotoJpegQuality = 80;
  static const int fieldPhotoSkipCompressBytes = 900 * 1024;
  static const String _fieldPhotoPendingUploadPrefsKey = 'field_photo_pending_uploads';
  bool _isGlobalProcessing = false;
  String _processingText = "";    
  // ✅ [추가] 마지막으로 UI(버튼 등)를 터치한 시간을 기록하는 변수
  int _lastUIInteractionTime = 0;
  final Map<String, SiteData> _markerDataMap = {};
  // ... 나머지 기존 코드들 ...
  final Map<String, LineData> _lineDataMap = {};
  final List<MapGroup> _userGroups = [];
  
  // ✅ 관리자 전용: 전체 팀 데이터를 저장할 Map
  final Map<String, TeamData> _allTeamsMap = {};
  final Map<String, int> _pendingMoveAddressSequences = {};
  int _moveAddressSequence = 0;

  final ImagePicker _picker = ImagePicker();
  final List<String> _tempLineMarkerIds = [];
  WebViewController? _webViewController;
  Timer? _markerUpdateTimer;
  Timer? _mapInteractionSafetyTimer;
  bool _isMapInteracting = false;
  bool _hasPendingMarkerUpdate = false;
  bool _didInitialGpsMove = false;
  String? _lastSentMarkersHash;
  String? _lastSentLinesHash;
  String? _lastSentNativeLinesHash;
  bool? _lastSentMarkerMoveMode;
  bool _showAllLineLabels = false;
  bool? _lastSentShowAllLineLabels;
  final Map<String, Map<String, dynamic>> _lastValidNativeLineJsonByDisplayKey = {};
  Timer? _nativeLineRetryTimer;
  String? _pendingNativeLineRetryHash;
    bool _isTappingMode = false, _isMoveMode = false, _isLineMode = false;
  bool _isMapControlActive = true;
  bool _dedupeMapRenderItems = true;
  bool _isSessionInvalidated = false;
  String _lastKakaoMarkerDedupeLogKey = '';
  String _lastKakaoLineDedupeLogKey = '';
  final Map<String, bool> _nativeLineVisibilityOverrides = {};
  bool _isFreeLineMode = false;
  bool _isModalOpen = false;
  bool _isHoveringUI = false;
  bool _spreadsheetEnabled = false;
  bool _isAdminQuickSlotsVisible = false;
  bool _isLineDeleteMode = false;
  Set<String> _selectedLineIds = {};
  List<LatLng> _tempFreeLinePoints = [];
  List<LatLng> _frozenFreeLinePoints = [];
  

  // ------------------------------------------------------------------
  // [추가됨] 보관함 모드 관련 변수
  // ------------------------------------------------------------------
  bool _isArchiveMode = false; // true면 '보관함(archives)'을 보여줌
  StreamSubscription<QuerySnapshot>? _allTeamsSub;
  StreamSubscription<DocumentSnapshot>? _myTeamSub;
  // ------------------------------------------------------------------

  double _currentZoom = 13.0;
  bool get isAdmin => widget.isAdmin;
  bool get isLeader => !isAdmin;
  bool get canManageTeamData => isAdmin || isLeader;
  bool get canUseAdminTools => isAdmin;
  String get _roleLabel => isAdmin ? "관리자" : "팀장";
  String get _adminTeamName => "admin";

  void _invalidateCurrentSession() {
    if (_isSessionInvalidated || !mounted) return;

    _isSessionInvalidated = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("비밀번호가 변경되었습니다. 다시 로그인해 주세요."),
        backgroundColor: Colors.red,
      ),
    );
    widget.onLogout();
  }

  void _clearSelectedLines() {
    _selectedLineIds.clear();
  }

  Future<void> _deleteSelectedLines() async {
    if (_selectedLineIds.isEmpty) return;

    final idsToDelete = Set<String>.from(_selectedLineIds);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete selected lines"),
        content: Text("Delete ${idsToDelete.length} line(s)?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      for (final id in idsToDelete) {
        _lineDataMap.remove(id);
      }
      _clearSelectedLines();
    });
    await _saveData();
    if (mounted) _scheduleMarkerUpdate();
  }

  Future<void> _deleteAllLines() async {
    if (_lineDataMap.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("전체 삭제"),
        content: const Text("모든 선(Line)을 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("삭제", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _lineDataMap.clear();
      _clearSelectedLines();
    });
    await _saveData();
    if (mounted) _scheduleMarkerUpdate();
  }

  Future<bool> _upsertLineInTeamDoc(String teamName, LineData line, {required bool addIfMissing}) async {
    final docRef = FirebaseFirestore.instance.collection('teams').doc(teamName);
    final snap = await docRef.get();
    if (!snap.exists) return false;

    final data = snap.data()!;
    final lines = List<dynamic>.from(data['lines'] ?? []);
    final canonicalId = _lineCanonicalId(line);
    final idx = lines.indexWhere((l) =>
        l is Map &&
        (l['id'] == line.id || (canonicalId.isNotEmpty && _lineCanonicalId(l) == canonicalId)));
    final lineJson = line.toJson();

    if (idx != -1) {
      final existing = lines[idx];
      if (existing is Map && existing.containsKey('isVisible')) {
        lineJson['isVisible'] = existing['isVisible'];
      }
      lines[idx] = lineJson;
    } else if (addIfMissing) {
      lines.add(lineJson);
    } else {
      return false;
    }

    await docRef.update({'lines': lines});
    return true;
  }

  Future<void> _updateDistributedLine(LineData line) async {
    for (final teamName in _allTeamsMap.keys) {
      if (teamName == widget.teamName) continue;
      try {
        final updated = await _upsertLineInTeamDoc(teamName, line, addIfMissing: false);
        if (updated) _allTeamsMap[teamName]?.lines[line.id] = line;
      } catch (e) {
        debugPrint("line update failed ($teamName): $e");
      }
    }
    if (mounted) setState(() {});
  }
  String? _lastSelectedGroupName; // ✅ 마지막으로 선택한 그룹 이름 저장
  String? _quickSelectedGroupName;
  int _quickGroupMode = 0; // 0 none, 1 selected, 2 quick create

bool _isValidMarkerAddress(String? address) {
    final value = (address ?? '').trim();
    return value.isNotEmpty &&
        value != '주소 확인 중...' &&
        value != '주소 정보 없음' &&
        !value.startsWith('위치:') &&
        !RegExp(r'^[-+]?\d+(\.\d+)?\s*,\s*[-+]?\d+(\.\d+)?$').hasMatch(value);
  }

Future<String?> _getKoreanAddressOrNull(double lat, double lng) async {
    try {
      if (kIsWeb) {
        final url = Uri.parse("https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&accept-language=ko&zoom=18&addressdetails=1");
        final response = await http.get(
          url,
          headers: {'User-Agent': 'FlutterApp/1.0'}, 
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['display_name'] != null) {
            // ✅ [개선] 주소를 쉼표(,)로 나누어 뒷부분(대한민국, 우편번호)을 제거합니다.
            List<String> parts = data['display_name'].toString().split(',');
            
            // 보통 뒤에서 1번째: 대한민국, 2번째: 우편번호입니다.
            // 이걸 제외하고 다시 합쳐서 읽기 편하게 만듭니다.
            if (parts.length > 2) {
              // '대한민국', '우편번호'를 제외한 앞부분만 필터링
              final address = parts.take(parts.length - 2).join(',').trim();
              return _isValidMarkerAddress(address) ? address : null;
            }
            final address = data['display_name']?.toString().trim();
            return _isValidMarkerAddress(address) ? address : null;
          }
        }
      } 
      else {
        // 앱(카카오) 로직은 그대로 유지 (이미 깔끔하니까요!) [cite: 103, 109]
        const String kakaoRestApiKey = "27c58a276dde1b122d57155e5f14e3b6";
        String url = "https://dapi.kakao.com/v2/local/geo/coord2address.json?x=$lng&y=$lat&input_coord=WGS84";
        
        final response = await http.get(
          Uri.parse(url),
          headers: { "Authorization": "KakaoAK $kakaoRestApiKey" },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['documents'] != null && (data['documents'] as List).isNotEmpty) {
            final doc = data['documents'][0];
            final road = doc['road_address'];
            final jibun = doc['address'];
            final roadAddress = road is Map ? road['address_name']?.toString().trim() : null;
            final jibunAddress = jibun is Map ? jibun['address_name']?.toString().trim() : null;
            final address = _isValidMarkerAddress(roadAddress) ? roadAddress : jibunAddress;
            return _isValidMarkerAddress(address) ? address : null;
          }
        }
      }
    } catch (e) {
      debugPrint("주소 변환 에러: $e");
    }
    return null;
  }

  String get _sKey => "${widget.teamName}_${widget.teamPw}";
  bool get _shouldUseNativeKakaoMap => !kIsWeb && Platform.isAndroid;

  void _initializeKakaoWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MarkerChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (_verboseMapDebug) debugPrint("MarkerChannel: ${message.message}");
          _handleKakaoMarkerTap(message.message);
        },
      )
      ..addJavaScriptChannel(
        'MarkerDragChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (_verboseMapDebug) debugPrint("MarkerDragChannel: ${message.message}");
          _handleKakaoMarkerMoved(message.message);
        },
      )
      ..addJavaScriptChannel(
        'DebugLogChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (_verboseMapDebug) debugPrint("[KAKAO_MOVE_DEBUG] payload: ${message.message}");
        },
      )
      ..addJavaScriptChannel(
        'debugLog',
        onMessageReceived: (JavaScriptMessage message) {
          if (_verboseMapDebug) debugPrint("[KAKAO_MOVE_DEBUG] ${message.message}");
        },
      )
      ..addJavaScriptChannel(
        'MapTapChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (_verboseMapDebug) debugPrint("MapTapChannel: ${message.message}");
          _handleKakaoMapTap(message.message);
        },
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (_verboseMapDebug) debugPrint("FlutterChannel: ${message.message}");
          if (message.message.contains('mapReady')) {
            _cancelMapInteractionSafetyTimer();
            _isMapInteracting = false;
            _hasPendingMarkerUpdate = true;
            _lastSentMarkerMoveMode = null;
            _lastSentShowAllLineLabels = null;
            _invalidateMarkerRenderHash();
            _scheduleMarkerUpdate(ms: 0);

            _moveToInitialGpsLocation();
          } else if (message.message.startsWith('mapInteractionStart')) {
            _startMapInteractionSafetyTimer();
            if (_isMapInteracting) return;
            _isMapInteracting = true;
          } else if (message.message.startsWith('mapInteractionEnd')) {
            _cancelMapInteractionSafetyTimer();
            if (!_isMapInteracting) return;
            _isMapInteracting = false;
            _flushPendingMarkerUpdateAfterMapIdle();
          }
        },
      )
      ..loadFlutterAsset('assets/kakao_map.html');
  }

  Future<void> _moveTo(double lat, double lng, int level) async {
    if (_shouldUseNativeKakaoMap) {
      try {
        await _nativeKakaoMapCommands.invokeMethod('moveTo', {
          'lat': lat,
          'lng': lng,
          'zoomLevel': level,
        });
      } catch (e) {
        debugPrint('native moveTo failed: $e');
      }
      return;
    }

    final controller = _webViewController;
    if (controller == null) return;

    try {
      await controller.runJavaScript('moveTo($lat, $lng, $level);');
    } catch (e) {
      debugPrint('moveTo failed: $e');
    }
  }

  Future<void> _zoomTo(int level) async {
    final controller = _webViewController;
    if (controller == null) return;

    try {
      await controller.runJavaScript('zoomTo($level);');
    } catch (e) {
      debugPrint('zoomTo failed: $e');
    }
  }

  Future<void> _setMarkerMoveModeOnKakaoMap(bool enabled) async {
    if (_shouldUseNativeKakaoMap) {
      if (_lastSentMarkerMoveMode == enabled) return;
      try {
        await _nativeKakaoMapCommands.invokeMethod('setMarkerMoveMode', {'enabled': enabled});
        _lastSentMarkerMoveMode = enabled;
      } catch (e) {
        debugPrint('native setMarkerMoveMode failed: $e');
      }
      return;
    }

    final controller = _webViewController;
    if (!mounted || controller == null) return;
    if (_lastSentMarkerMoveMode == enabled) return;

    try {
      await controller.runJavaScript('setMarkerMoveMode(${enabled ? 'true' : 'false'});');
      _lastSentMarkerMoveMode = enabled;
    } catch (e) {
      debugPrint('setMarkerMoveMode failed: $e');
    }
  }

  Future<void> _setShowAllLineLabelsOnKakaoMap(bool enabled) async {
    if (_shouldUseNativeKakaoMap) {
      if (_lastSentShowAllLineLabels == enabled) return;
      try {
        await _nativeKakaoMapCommands.invokeMethod('setShowAllLineLabels', {'enabled': enabled});
        _lastSentShowAllLineLabels = enabled;
      } catch (e) {
        debugPrint('native setShowAllLineLabels failed: $e');
      }
      return;
    }

    final controller = _webViewController;
    if (!mounted || controller == null) return;
    if (_lastSentShowAllLineLabels == enabled) return;

    try {
      await controller.runJavaScript('setShowAllLineLabels(${enabled ? 'true' : 'false'});');
      _lastSentShowAllLineLabels = enabled;
    } catch (e) {
      debugPrint('setShowAllLineLabels failed: $e');
    }
  }

    Future<void> _showCurrentLocationOnMap(double lat, double lng) async {
    if (_shouldUseNativeKakaoMap) {
      try {
        await _nativeKakaoMapCommands.invokeMethod('showCurrentLocation', {
          'lat': lat,
          'lng': lng,
          'title': '현재 위치',
          'moveCamera': false,
        });
      } catch (e) {
        debugPrint('native showCurrentLocation failed: $e');
      }
      return;
    }

    final controller = _webViewController;
    if (controller == null) return;

    final payload = jsonEncode({
      'lat': lat,
      'lng': lng,
      'title': '현재 위치',
      'moveCamera': false,
    });

    try {
      await controller.runJavaScript('showCurrentLocation($payload);');
    } catch (e) {
      debugPrint('showCurrentLocation failed: $e');
    }
  }

  Future<void> _moveToInitialGpsLocation() async {
    if (_didInitialGpsMove || !mounted || kIsWeb) return;

    _didInitialGpsMove = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('[INITIAL_GPS] 위치 서비스가 꺼져 있습니다.');
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever
      ) {
        debugPrint('[INITIAL_GPS] 위치 권한이 허용되지 않았습니다.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      await _showCurrentLocationOnMap(
        position.latitude,
        position.longitude,
      );

      await _moveTo(
        position.latitude,
        position.longitude,
        _shouldUseNativeKakaoMap ? _nativeFocusedZoomLevel : 3,
      );
    } catch (e) {
      debugPrint('[INITIAL_GPS] 최초 현재 위치 이동 실패: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _normalizeMarkerNumber(String value) {
    var text = value.trim();
    final match = RegExp(r'\d+').firstMatch(text);
    if (match != null) {
      text = match.group(0) ?? text;
    }
    text = text.replaceFirst(RegExp(r'^0+'), '');
    return text.isEmpty ? '0' : text;
  }

  int? _extractMarkerSortNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value.trim());
    if (match == null) return null;
    return int.tryParse(match.group(0) ?? '');
  }

  int _compareSiteDataByMarkerNumber(SiteData a, SiteData b) {
    final aNumber = _extractMarkerSortNumber(a.title);
    final bNumber = _extractMarkerSortNumber(b.title);

    if (aNumber != null && bNumber != null) {
      final numberCompare = aNumber.compareTo(bNumber);
      if (numberCompare != 0) return numberCompare;
    }

    if (aNumber != null && bNumber == null) return -1;
    if (aNumber == null && bNumber != null) return 1;

    final titleCompare = a.title.compareTo(b.title);
    if (titleCompare != 0) return titleCompare;

    return a.id.compareTo(b.id);
  }

  List<String> _markerNumberCandidates(SiteData marker) {
    final values = <String>[
      marker.title,
    ];

    if (RegExp(r'^\d+$').hasMatch(marker.id.trim())) {
      values.add(marker.id);
    }

    final result = <String>{};

    for (final value in values) {
      final raw = value.trim();
      if (raw.isEmpty) continue;
      result.add(raw);

      final match = RegExp(r'\d+').firstMatch(raw);
      if (match != null && match.group(0) != null) {
        result.add(match.group(0)!);
      }
    }

    return result.toList();
  }

  String _markerSearchDedupeKey(SiteData marker) {
    return (marker.canonicalMarkerId ??
            marker.originalMarkerId ??
            marker.sourceMarkerId ??
            marker.parentMarkerId ??
            marker.id)
        .trim();
  }

  List<SiteData> _findMarkersByNumber(String query) {
    final normalizedQuery = _normalizeMarkerNumber(query);
    final seen = <String>{};
    final matches = <SiteData>[];

    for (final marker in _markerDataMap.values) {
      final matched = _markerNumberCandidates(marker).any(
        (candidate) => _normalizeMarkerNumber(candidate) == normalizedQuery,
      );

      if (!matched) continue;

      final key = _markerSearchDedupeKey(marker);
      if (key.isNotEmpty && seen.contains(key)) continue;
      if (key.isNotEmpty) seen.add(key);

      matches.add(marker);
    }

    matches.sort((a, b) {
      final groupCompare = a.group.name.compareTo(b.group.name);
      if (groupCompare != 0) return groupCompare;
      return a.title.compareTo(b.title);
    });

    return matches;
  }

  Future<void> _showMarkerNumberSearchDialog() async {
    if (!mounted || _isModalOpen) return;

    if (_markerDataMap.isEmpty) {
      _showSnack('검색할 마커 데이터가 없습니다.');
      return;
    }

    setState(() {
      _isModalOpen = true;
    });

    String inputValue = '';
    String? query;

    try {
      query = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('마커번호 검색'),
            content: TextField(
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '마커번호',
                hintText: '예: 12',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                inputValue = value;
              },
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(inputValue);
                },
                child: const Text('검색'),
              ),
            ],
          );
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 80));
    } finally {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
      }
    }

    if (!mounted) return;
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) return;

    await _handleMarkerNumberSearch(trimmed);
  }

  Future<void> _handleMarkerNumberSearch(String query) async {
    if (!mounted) return;

    if (_markerDataMap.isEmpty) {
      _showSnack('검색할 마커 데이터가 없습니다.');
      return;
    }

    if (!RegExp(r'\d+').hasMatch(query)) {
      _showSnack('숫자를 입력하세요.');
      return;
    }

    final matches = _findMarkersByNumber(query);

    if (!mounted) return;

    if (matches.isEmpty) {
      _showSnack('해당 번호의 마커가 없습니다.');
      return;
    }

    if (matches.length == 1) {
      await _focusMarkerFromNumberSearch(matches.first);
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    await _showMarkerNumberDuplicatePicker(matches, query);
  }

  Future<void> _showMarkerNumberDuplicatePicker(
    List<SiteData> matches,
    String query,
  ) async {
    if (!mounted) return;

    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    final selected = await showModalBottomSheet<SiteData>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '마커번호 $query 검색 결과 ${matches.length}개',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (itemContext, index) {
                      final marker = matches[index];
                      final title = marker.title.trim().isEmpty
                          ? '?'
                          : marker.title.trim();
                      final subtitle = marker.address.trim().isNotEmpty
                          ? marker.address.trim()
                          : marker.description.trim();

                      return ListTile(
                        leading: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: marker.group.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                        title: Text('$title번 / ${marker.group.name}'),
                        subtitle: Text(
                          subtitle.isEmpty ? '주소 정보 없음' : subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop(marker);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    await _focusMarkerFromNumberSearch(selected);
  }

  Future<void> _focusMarkerFromNumberSearch(SiteData marker) async {
    if (!mounted) return;

    final lat = marker.lat;
    final lng = marker.lng;

    if (!lat.isFinite || !lng.isFinite) {
      _showSnack('좌표가 없는 마커입니다.');
      return;
    }

    await _moveTo(
      lat,
      lng,
      _shouldUseNativeKakaoMap ? _nativeFocusedZoomLevel : 1,
    );

    if (!mounted) return;

    final markerEntry = _findMarkerEntry(_markerDataMap, marker.id);
    if (markerEntry != null) {
      _showMarkerDetails(markerEntry.key);
    }

    _showSnack('마커번호 ${marker.title}로 이동했습니다.');
  }

  bool _isValidLineFocusCoordinate(double lat, double lng) {
    return lat.isFinite && lng.isFinite && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  List<LatLng> _dedupeLatLngPoints(Iterable<LatLng> points) {
    final seen = <String>{};
    final result = <LatLng>[];
    for (final point in points) {
      final key = '${point.latitude.toStringAsFixed(7)},${point.longitude.toStringAsFixed(7)}';
      if (seen.add(key)) result.add(point);
    }
    return result;
  }

  MapEntry<String, SiteData>? _findMarkerForLineFocus(String markerId, {String? teamName}) {
    final raw = markerId.trim();
    if (raw.isEmpty) return null;

    final candidates = <String>{raw};
    final targetTeamName = teamName?.trim();
    if (targetTeamName != null && targetTeamName.isNotEmpty && raw.startsWith('${targetTeamName}_')) {
      candidates.add(raw.substring(targetTeamName.length + 1));
    }
    final underscore = raw.indexOf('_');
    if (underscore > 0 && underscore < raw.length - 1) {
      candidates.add(raw.substring(underscore + 1));
    }

    Iterable<MapEntry<String, SiteData>?> searchMaps() sync* {
      if (targetTeamName != null && targetTeamName.isNotEmpty && targetTeamName != widget.teamName) {
        final team = _allTeamsMap[targetTeamName];
        if (team != null) {
          for (final candidate in candidates) {
            yield _findMarkerEntry(team.markers, candidate);
          }
        }
      }

      for (final candidate in candidates) {
        yield _findMarkerEntry(_markerDataMap, candidate);
      }

      for (final team in _allTeamsMap.values) {
        if (targetTeamName != null && targetTeamName.isNotEmpty && team.teamName == targetTeamName) continue;
        for (final candidate in candidates) {
          yield _findMarkerEntry(team.markers, candidate);
        }
      }
    }

    for (final entry in searchMaps()) {
      if (entry != null) return entry;
    }
    return null;
  }

  List<LatLng> _collectValidLineFocusPoints(LineData line, {String? teamName}) {
    final points = <LatLng>[];

    for (final point in line.points) {
      if (_isValidLineFocusCoordinate(point.latitude, point.longitude)) {
        points.add(LatLng(point.latitude, point.longitude));
      }
    }

    var deduped = _dedupeLatLngPoints(points);
    if (deduped.length >= 2) return deduped;

    for (final markerId in line.markerIds) {
      final markerEntry = _findMarkerForLineFocus(markerId, teamName: teamName);
      final marker = markerEntry?.value;
      if (marker != null && _isValidLineFocusCoordinate(marker.lat, marker.lng)) {
        points.add(LatLng(marker.lat, marker.lng));
      }
    }

    deduped = _dedupeLatLngPoints(points);
    return deduped;
  }

  int _zoomLevelForLineSpan(double span) {
    if (_shouldUseNativeKakaoMap) {
      int nativeLevel(int delta) => (_nativeFocusedZoomLevel - delta).clamp(_nativeFocusedZoomLevel - 2, _nativeFocusedZoomLevel).toInt();
      if (span <= 0.0005) return _nativeFocusedZoomLevel;
      if (span <= 0.0020) return nativeLevel(1);
      if (span <= 0.0080) return nativeLevel(1);
      return nativeLevel(2);
    }

    if (span <= 0.0008) return 1;
    if (span <= 0.0020) return 2;
    if (span <= 0.0080) return 2;
    return 3;
  }

  Future<void> _focusLineFromList(LineData line, {String? teamName}) async {
    final points = _collectValidLineFocusPoints(line, teamName: teamName);
    if (points.length < 2) {
      _showSnack('이 선의 위치 정보를 찾을 수 없습니다. 연결된 마커 좌표를 확인해 주세요.');
      return;
    }

    final minLat = points.map((p) => p.latitude).reduce(math.min);
    final maxLat = points.map((p) => p.latitude).reduce(math.max);
    final minLng = points.map((p) => p.longitude).reduce(math.min);
    final maxLng = points.map((p) => p.longitude).reduce(math.max);
    final centerLat = (minLat + maxLat) / 2.0;
    final centerLng = (minLng + maxLng) / 2.0;

    if (!_isValidLineFocusCoordinate(centerLat, centerLng)) {
      _showSnack('이 선의 위치 정보를 찾을 수 없습니다. 연결된 마커 좌표를 확인해 주세요.');
      return;
    }

    final span = math.max(maxLat - minLat, maxLng - minLng);
    final zoomLevel = _zoomLevelForLineSpan(span);
    if (_verboseMapDebug) {
      debugPrint('[LINE_FOCUS] title=${line.title} points=${points.length} span=$span center=$centerLat,$centerLng zoom=$zoomLevel');
    }
    await _moveTo(centerLat, centerLng, zoomLevel);
  }

  void _setStateAndRefreshMap(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _scheduleMarkerUpdate();
  }

  void _clearTemporaryMapModes() {
    _isTappingMode = false;
    _isMoveMode = false;
    _isLineMode = false;
    _isFreeLineMode = false;
    _isLineDeleteMode = false;
    _tempLineMarkerIds.clear();
    _tempFreeLinePoints.clear();
    _clearSelectedLines();
  }

  void _enterMarkerCreateMode() {
    setState(() {
      _clearTemporaryMapModes();
      _isTappingMode = true;
      _isMapControlActive = true;
    });
    _setMarkerMoveModeOnKakaoMap(false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("지도에서 마커를 추가할 위치를 선택하세요."), duration: Duration(seconds: 3)),
    );
  }

  void _handleKakaoMarkerTap(String markerId) {
    if (_isModalOpen || _isHoveringUI || !_isMapControlActive) return;
    if (markerId.trim().isEmpty) return;

    String targetMarkerId = markerId;
    TeamData? targetTeam;
    SiteData? site = _markerDataMap[targetMarkerId];

    if (site == null && isAdmin) {
      for (final entry in _allTeamsMap.entries) {
        final prefix = '${entry.key}_';
        if (!markerId.startsWith(prefix)) continue;

        final localId = markerId.substring(prefix.length);
        final candidate = entry.value.markers[localId];
        if (candidate != null) {
          targetMarkerId = localId;
          targetTeam = entry.value;
          site = candidate;
          break;
        }
      }
    }

    if (site == null) return;

    if (_isFreeLineMode) {
      _setStateAndRefreshMap(() => _tempFreeLinePoints.add(site!.position));
    } else if (_isLineMode) {
      _setStateAndRefreshMap(() => _tempLineMarkerIds.add(markerId));
    } else if (_isMoveMode) {
      return;
    } else {
      _showMarkerDetails(targetMarkerId, fromOtherTeam: targetTeam);
    }
  }

  Future<void> _handleNativeKakaoMapEvent(MethodCall call) async {
    if (call.method == 'mapReady') {
      _lastSentMarkerMoveMode = null;
      _lastSentShowAllLineLabels = null;
      _hasPendingMarkerUpdate = true;
      _scheduleMarkerUpdate(ms: 0);
      await _setShowAllLineLabelsOnKakaoMap(_showAllLineLabels);
      _moveToInitialGpsLocation();
      return;
    }

    if (call.method == 'mapTap') {
      final args = call.arguments;
      if (args is! Map) return;
      final lat = (args['lat'] as num?)?.toDouble();
      final lng = (args['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      await _handleKakaoMapTap(jsonEncode({'lat': lat, 'lng': lng}));
      return;
    }

    if (call.method == 'markerDragEnd') {
      final args = call.arguments;
      if (args is! Map) return;
      await _handleNativeMarkerDragEnd(args);
      return;
    }

    if (call.method != 'markerTap') return;
    if (_isModalOpen || _isHoveringUI || !_isMapControlActive) return;

    final args = call.arguments;
    if (args is! Map) return;

    final target = _resolveNativeMarkerTarget(args);
    final entry = target?['entry'] as MapEntry<String, SiteData>?;
    if (entry == null) return;

    final targetTeam = target?['team'] as TeamData?;
    final targetTeamDocId = target?['teamDocId']?.toString() ?? widget.teamName;
    final lineMarkerId = targetTeam == null ? entry.key : '${targetTeamDocId}_${entry.key}';

    if (_isFreeLineMode) {
      _setStateAndRefreshMap(() => _tempFreeLinePoints.add(entry.value.position));
    } else if (_isLineMode) {
      _setStateAndRefreshMap(() => _tempLineMarkerIds.add(lineMarkerId));
    } else if (_isMoveMode) {
      return;
    } else {
      _showMarkerDetails(entry.key, fromOtherTeam: targetTeam);
    }
  }

  Future<void> _handleNativeMarkerDragEnd(Map args) async {
    if (!_isMoveMode || _isModalOpen || !_isMapControlActive) return;

    final lat = (args['lat'] as num?)?.toDouble();
    final lng = (args['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final target = _resolveNativeMarkerTarget(args);
    final entry = target?['entry'] as MapEntry<String, SiteData>?;
    if (entry == null) return;
    final targetTeamDocId = target?['teamDocId']?.toString() ?? widget.teamName;

    setState(() {
      _isGlobalProcessing = true;
      _processingText = "마커 이동 중...";
    });

    try {
      final moved = await _finalizeMovedMarkerCanonicalMutation(
        marker: entry.value,
        point: LatLng(lat, lng),
        initiatingTeamName: targetTeamDocId,
      );
      if (!mounted) return;
      if (moved) {
        _invalidateMarkerRenderHash();
        _scheduleMarkerUpdate(ms: 0);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGlobalProcessing = false;
          _processingText = "";
        });
      }
    }
  }

  bool _updateConnectedLinePoints(Map<String, LineData> lines, String markerId, LatLng point) {
    bool changed = false;

    for (final line in lines.values) {
      for (int i = 0; i < line.markerIds.length && i < line.points.length; i++) {
        if (line.markerIds[i] == markerId) {
          line.points[i] = point;
          changed = true;
        }
      }
    }

    return changed;
  }

  MapEntry<String, SiteData>? _findMarkerEntry(Map<String, SiteData> markers, String markerId) {
    final direct = markers[markerId];
    if (direct != null) return MapEntry(markerId, direct);

    for (final entry in markers.entries) {
      final site = entry.value;
      if (site.id == markerId ||
          site.canonicalMarkerId == markerId ||
          site.originalMarkerId == markerId ||
          site.sourceMarkerId == markerId ||
          site.parentMarkerId == markerId) return entry;
    }

    return null;
  }

  MapEntry<String, TeamData>? _findAdminTeamEntry(String? teamName) {
    final target = teamName?.trim();
    if (target == null || target.isEmpty) return null;

    final direct = _allTeamsMap[target];
    if (direct != null) return MapEntry(target, direct);

    for (final entry in _allTeamsMap.entries) {
      if (entry.value.teamName == target) return entry;
    }

    return null;
  }

  List<String> _nativeMarkerEventCandidates(Map args) {
    final candidates = <String>[];

    void add(dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && !candidates.contains(text)) candidates.add(text);
    }

    add(args['id']);
    add(args['markerId']);
    add(args['displayKey']);
    add(args['canonicalMarkerId']);
    add(args['originalMarkerId']);
    add(args['sourceMarkerId']);
    add(args['parentMarkerId']);

    final displayKey = args['displayKey']?.toString().trim() ?? '';
    final displayParts = displayKey.split(':');
    if (displayParts.length >= 3 && (displayParts.first == 'marker' || displayParts.first == 'own')) {
      add(displayParts.sublist(2).join(':'));
    }

    return candidates;
  }

  String? _nativeMarkerEventTeamName(Map args) {
    final direct = args['teamName']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final displayKey = args['displayKey']?.toString().trim() ?? '';
    final displayParts = displayKey.split(':');
    if (displayParts.length >= 3 && (displayParts.first == 'marker' || displayParts.first == 'own')) {
      final teamName = displayParts[1].trim();
      if (teamName.isNotEmpty) return teamName;
    }

    return null;
  }

  Map<String, Object?>? _resolveNativeMarkerTarget(Map args) {
    final candidates = _nativeMarkerEventCandidates(args);
    if (candidates.isEmpty) return null;

    final explicitTeamName = _nativeMarkerEventTeamName(args);
    if (explicitTeamName == null || explicitTeamName == widget.teamName) {
      for (final candidate in candidates) {
        final ownEntry = _findMarkerEntry(_markerDataMap, candidate);
        if (ownEntry != null) {
          return {
            'entry': ownEntry,
            'team': null,
            'teamDocId': widget.teamName,
          };
        }
      }
    }

    if (!isAdmin) return null;

    final explicitTeam = _findAdminTeamEntry(explicitTeamName);
    if (explicitTeam != null) {
      for (final candidate in candidates) {
        final teamEntry = _findMarkerEntry(explicitTeam.value.markers, candidate);
        if (teamEntry != null) {
          return {
            'entry': teamEntry,
            'team': explicitTeam.value,
            'teamDocId': explicitTeam.key,
          };
        }
      }
    }

    for (final candidate in candidates) {
      for (final team in _allTeamsMap.entries) {
        final prefixes = ['${team.key}_', '${team.value.teamName}_'];
        for (final prefix in prefixes) {
          if (!candidate.startsWith(prefix) || candidate.length <= prefix.length) continue;

          final localId = candidate.substring(prefix.length);
          final teamEntry = _findMarkerEntry(team.value.markers, localId);
          if (teamEntry != null) {
            return {
              'entry': teamEntry,
              'team': team.value,
              'teamDocId': team.key,
            };
          }
        }
      }
    }

    for (final candidate in candidates) {
      for (final team in _allTeamsMap.entries) {
        final teamEntry = _findMarkerEntry(team.value.markers, candidate);
        if (teamEntry != null) {
          return {
            'entry': teamEntry,
            'team': team.value,
            'teamDocId': team.key,
          };
        }
      }
    }

    return null;
  }

  bool _matchesMoveMarker(SiteData site, String mapKey, String markerId) {
    if (markerId.isEmpty) return false;
    return mapKey == markerId ||
        site.id == markerId ||
        site.canonicalMarkerId == markerId ||
        site.originalMarkerId == markerId ||
        site.sourceMarkerId == markerId ||
        site.parentMarkerId == markerId ||
        mapKey.endsWith(markerId) ||
        site.id.endsWith(markerId) ||
        markerId.endsWith(site.id) ||
        (site.canonicalMarkerId != null && markerId.endsWith(site.canonicalMarkerId!)) ||
        (site.originalMarkerId != null && markerId.endsWith(site.originalMarkerId!)) ||
        (site.sourceMarkerId != null && markerId.endsWith(site.sourceMarkerId!));
  }

  MapEntry<String, SiteData>? _findMarkerEntryInGroup(Map<String, SiteData> markers, String? groupName, List<String> markerIds) {
    for (final markerId in markerIds) {
      final direct = markers[markerId];
      if (direct != null && (groupName == null || direct.group.name == groupName)) {
        return MapEntry(markerId, direct);
      }
    }

    for (final entry in markers.entries) {
      final site = entry.value;
      if (groupName != null && site.group.name != groupName) continue;
      for (final markerId in markerIds) {
        if (_matchesMoveMarker(site, entry.key, markerId)) return entry;
      }
    }

    return null;
  }

  List<String> _moveMarkerCandidates(Map data, Map target) {
    final values = [
      data['markerId'],
      data['canonicalMarkerId'],
      data['originalMarkerId'],
      data['sourceMarkerId'],
      target['markerId'],
      target['canonicalMarkerId'],
      target['originalMarkerId'],
      target['sourceMarkerId'],
      target['parentMarkerId'],
      data['actualMarkerId'],
      data['parentMarkerId'],
    ];
    final result = <String>[];

    for (final value in values) {
      final text = value?.toString() ?? '';
      if (text.isNotEmpty && !result.contains(text)) result.add(text);
    }

    return result;
  }

  bool _matchesMoveMarkerJson(Map marker, String markerId) {
    if (markerId.isEmpty) return false;
    final id = marker['id']?.toString() ?? '';
    final markerJsonId = marker['markerId']?.toString() ?? '';
    final canonicalMarkerId = marker['canonicalMarkerId']?.toString() ?? '';
    final originalMarkerId = marker['originalMarkerId']?.toString() ?? '';
    final sourceMarkerId = marker['sourceMarkerId']?.toString() ?? '';
    final parentMarkerId = marker['parentMarkerId']?.toString() ?? '';

    return id == markerId ||
        markerJsonId == markerId ||
        canonicalMarkerId == markerId ||
        originalMarkerId == markerId ||
        sourceMarkerId == markerId ||
        parentMarkerId == markerId ||
        id.endsWith(markerId) ||
        markerJsonId.endsWith(markerId) ||
        canonicalMarkerId.endsWith(markerId) ||
        (id.isNotEmpty && markerId.endsWith(id)) ||
        (originalMarkerId.isNotEmpty && markerId.endsWith(originalMarkerId)) ||
        (sourceMarkerId.isNotEmpty && markerId.endsWith(sourceMarkerId));
  }

  String _syncOriginalMarkerId(String markerId, SiteData site) {
    return site.canonicalMarkerId ?? site.originalMarkerId ?? site.sourceMarkerId ?? site.parentMarkerId ?? markerId;
  }

  bool _isOriginalMarkerForSharedSync(SiteData site) {
    return site.canonicalMarkerId == null && site.originalMarkerId == null && site.sourceMarkerId == null && site.parentMarkerId == null;
  }

  bool _matchesSharedMarkerJson(Map marker, String markerId, String originalMarkerId) {
    if (markerId.isEmpty && originalMarkerId.isEmpty) return false;

    final id = marker['id']?.toString() ?? '';
    final markerJsonId = marker['markerId']?.toString() ?? '';
    final canonicalMarkerId = marker['canonicalMarkerId']?.toString() ?? '';
    final markerOriginalId = marker['originalMarkerId']?.toString() ?? '';
    final sourceMarkerId = marker['sourceMarkerId']?.toString() ?? '';
    final parentMarkerId = marker['parentMarkerId']?.toString() ?? '';

    if (markerId.isNotEmpty &&
        (id == markerId ||
            markerJsonId == markerId ||
            canonicalMarkerId == markerId ||
            markerOriginalId == markerId ||
            sourceMarkerId == markerId ||
            parentMarkerId == markerId)) {
      return true;
    }

    if (originalMarkerId.isEmpty) return false;

    return id == originalMarkerId ||
        markerJsonId == originalMarkerId ||
        canonicalMarkerId == originalMarkerId ||
        markerOriginalId == originalMarkerId ||
        markerJsonId.endsWith(originalMarkerId);
  }

  void _setMarkerCheckFields(Map<String, dynamic> marker, bool isChecked) {
    marker['isChecked'] = isChecked;
    if (marker.containsKey('checked')) marker['checked'] = isChecked;
    if (marker.containsKey('isOn')) marker['isOn'] = isChecked;
  }

  bool _matchesSharedMarkerAddDuplicate(Map marker, String newMarkerId) {
    if (newMarkerId.isEmpty) return false;

    final id = marker['id']?.toString() ?? '';
    final markerJsonId = marker['markerId']?.toString() ?? '';
    final canonicalMarkerId = marker['canonicalMarkerId']?.toString() ?? '';
    final originalMarkerId = marker['originalMarkerId']?.toString() ?? '';
    final sourceMarkerId = marker['sourceMarkerId']?.toString() ?? '';

    return id == newMarkerId ||
        markerJsonId == newMarkerId ||
        canonicalMarkerId == newMarkerId ||
        originalMarkerId == newMarkerId ||
        sourceMarkerId == newMarkerId ||
        (marker['parentMarkerId']?.toString() ?? '') == newMarkerId ||
        id.endsWith(newMarkerId) ||
        markerJsonId.endsWith(newMarkerId);
  }

  Future<bool> _appendNewMarkerToSharedGroups({
    required String sourceTeamName,
    required SiteData marker,
  }) async {
    bool foundTarget = false;
    bool addedAny = false;
    final targetGroupNames = <String>{
      marker.group.name,
      '$sourceTeamName/${marker.group.name}',
    };

    final QuerySnapshot<Map<String, dynamic>> teamsSnapshot;
    try {
      teamsSnapshot = await FirebaseFirestore.instance.collection('teams').get();
    } catch (e) {
      debugPrint('[SYNC_SHARED_MARKER_ADD_NO_TARGET] markerId=${marker.id} groupName=${marker.group.name} error=$e');
      return false;
    }

    for (final doc in teamsSnapshot.docs) {
      if (doc.id == sourceTeamName) continue;

      bool addedDoc = false;
      bool duplicateDoc = false;
      bool targetDoc = false;

      try {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(doc.reference);
          if (!snapshot.exists || snapshot.data() == null) return;

          final data = snapshot.data()!;
          final groups = List<dynamic>.from(data['groups'] ?? []);
          final markers = List<dynamic>.from(data['markers'] ?? []);
          Map<String, dynamic>? targetGroup;
          for (final group in groups) {
            if (group is Map && targetGroupNames.contains(group['name']?.toString() ?? '')) {
              targetGroup = Map<String, dynamic>.from(group);
              break;
            }
          }
          if (targetGroup == null) {
            for (final existingMarker in markers) {
              if (existingMarker is Map &&
                  existingMarker['group'] is Map &&
                  targetGroupNames.contains(existingMarker['group']['name']?.toString() ?? '')) {
                targetGroup = Map<String, dynamic>.from(existingMarker['group'] as Map);
                break;
              }
            }
          }
          if (targetGroup == null) return;

          targetDoc = true;
          final targetGroupName = targetGroup['name']?.toString() ?? marker.group.name;
          final duplicate = markers.any((m) =>
              m is Map &&
              m['group'] is Map &&
              m['group']['name'] == targetGroupName &&
              _matchesSharedMarkerAddDuplicate(Map<String, dynamic>.from(m), marker.id));

          if (duplicate) {
            duplicateDoc = true;
            return;
          }

          final markerJson = marker.toJson();
          markerJson['id'] = marker.id;
          markerJson['originalMarkerId'] ??= marker.id;
          markerJson['group'] = targetGroup;
          markers.add(markerJson);

          transaction.update(doc.reference, {'markers': markers});
          addedDoc = true;
        });
      } catch (e) {
        debugPrint('[SYNC_SHARED_MARKER_ADD_NO_TARGET] team=${doc.id} markerId=${marker.id} groupName=${marker.group.name} error=$e');
        continue;
      }

      if (targetDoc) foundTarget = true;
      if (addedDoc) {
        addedAny = true;
        debugPrint('[SYNC_SHARED_MARKER_ADDED] team=${doc.id} markerId=${marker.id} groupName=${marker.group.name}');
      } else if (duplicateDoc) {
        debugPrint('[SYNC_SHARED_MARKER_ADD_SKIPPED_DUPLICATE] team=${doc.id} markerId=${marker.id} groupName=${marker.group.name}');
      }
    }

    if (!foundTarget) {
      debugPrint('[SYNC_SHARED_MARKER_ADD_NO_TARGET] markerId=${marker.id} groupName=${marker.group.name}');
    }

    return addedAny;
  }

  Future<bool> _updateSharedMarkerCopies({
    required String sourceTeamName,
    required String markerId,
    required String originalMarkerId,
    LatLng? point,
    bool? isChecked,
  }) async {
    bool updatedAny = false;
    final QuerySnapshot<Map<String, dynamic>> teamsSnapshot;

    try {
      teamsSnapshot = await FirebaseFirestore.instance.collection('teams').get();
    } catch (e) {
      debugPrint('[SYNC_SHARED_MARKER_NOT_FOUND] markerId=$markerId originalMarkerId=$originalMarkerId error=$e');
      return false;
    }

    final movedAddress = point == null ? null : await _getKoreanAddressOrNull(point.latitude, point.longitude);
    if (point != null && !_isValidMarkerAddress(movedAddress)) return false;

    for (final doc in teamsSnapshot.docs) {
      if (doc.id == sourceTeamName) continue;

      bool updatedDoc = false;
      try {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(doc.reference);
          if (!snapshot.exists || snapshot.data() == null) return;

          final data = snapshot.data()!;
          final markers = List<dynamic>.from(data['markers'] ?? []);
          bool changed = false;

          for (int i = 0; i < markers.length; i++) {
            if (markers[i] is! Map) continue;

            final marker = Map<String, dynamic>.from(markers[i] as Map);
            if (!_matchesSharedMarkerJson(marker, markerId, originalMarkerId)) continue;

            if (point != null) {
              marker['lat'] = point.latitude;
              marker['lng'] = point.longitude;
              marker['address'] = movedAddress;
            }
            if (isChecked != null) {
              _setMarkerCheckFields(marker, isChecked);
            }

            markers[i] = marker;
            changed = true;
          }

          if (!changed) return;

          transaction.update(doc.reference, {'markers': markers});
          updatedDoc = true;
        });
      } catch (e) {
        debugPrint('[SYNC_SHARED_MARKER_NOT_FOUND] team=${doc.id} markerId=$markerId originalMarkerId=$originalMarkerId error=$e');
        continue;
      }

      if (updatedDoc) {
        updatedAny = true;
        if (point != null) {
          if (_verboseMapDebug) debugPrint('[SYNC_SHARED_MARKER_MOVE_UPDATED] team=${doc.id} markerId=$markerId originalMarkerId=$originalMarkerId');
        }
        if (isChecked != null) {
          if (_verboseMapDebug) debugPrint('[SYNC_SHARED_MARKER_CHECK_UPDATED] team=${doc.id} markerId=$markerId originalMarkerId=$originalMarkerId');
        }
      }
    }

    if (!updatedAny) {
      debugPrint('[SYNC_SHARED_MARKER_NOT_FOUND] markerId=$markerId originalMarkerId=$originalMarkerId');
    }

    return updatedAny;
  }

  String _cleanMarkerId(dynamic value) => value?.toString().trim() ?? '';

  String _lineCanonicalId(dynamic line) {
    if (line is LineData) {
      return _cleanMarkerId(line.canonicalLineId ?? line.originalLineId ?? line.sourceLineId ?? line.parentLineId ?? line.id);
    }
    if (line is Map) {
      return _cleanMarkerId(line['canonicalLineId'] ?? line['originalLineId'] ?? line['sourceLineId'] ?? line['parentLineId'] ?? line['lineId'] ?? line['id']);
    }
    return '';
  }

  String canonicalMarkerIdForOwnedMarker(dynamic marker) {
    if (marker is SiteData) return _cleanMarkerId(marker.id);
    if (marker is Map) return _cleanMarkerId(marker['id'] ?? marker['markerId']);
    return '';
  }

  String canonicalMarkerIdForSharedCopy(dynamic marker) {
    if (marker is SiteData) {
      return _cleanMarkerId(marker.canonicalMarkerId ?? marker.originalMarkerId ?? marker.sourceMarkerId ?? marker.parentMarkerId);
    }
    if (marker is Map) {
      return _cleanMarkerId(marker['canonicalMarkerId'] ?? marker['originalMarkerId'] ?? marker['sourceMarkerId'] ?? marker['parentMarkerId']);
    }
    return '';
  }

  bool isLinkedSharedCopy(dynamic marker, String canonicalSourceId) {
    if (canonicalSourceId.isEmpty) return false;
    if (marker is SiteData) {
      return _cleanMarkerId(marker.originalMarkerId) == canonicalSourceId ||
          _cleanMarkerId(marker.canonicalMarkerId) == canonicalSourceId ||
          _cleanMarkerId(marker.sourceMarkerId) == canonicalSourceId ||
          _cleanMarkerId(marker.parentMarkerId) == canonicalSourceId;
    }
    if (marker is Map) {
      return _cleanMarkerId(marker['originalMarkerId']) == canonicalSourceId ||
          _cleanMarkerId(marker['canonicalMarkerId']) == canonicalSourceId ||
          _cleanMarkerId(marker['sourceMarkerId']) == canonicalSourceId ||
          _cleanMarkerId(marker['parentMarkerId']) == canonicalSourceId;
    }
    return false;
  }

  List<String> _markerOwnIds(dynamic marker) => _markerOwnIdsFromJson(marker);

  List<String> _markerLinkIds(dynamic marker) => _markerLinkIdsFromJson(marker);

  List<String> _markerOwnIdsFromJson(dynamic marker) {
    final values = <dynamic>[];
    if (marker is SiteData) {
      values.addAll([marker.id]);
    } else if (marker is Map) {
      values.addAll([marker['id'], marker['markerId']]);
    }
    return values.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet().toList();
  }

  List<String> _markerLinkIdsFromJson(dynamic marker) {
    final values = <dynamic>[];
    if (marker is SiteData) {
      values.addAll([marker.canonicalMarkerId, marker.originalMarkerId, marker.sourceMarkerId, marker.parentMarkerId]);
    } else if (marker is Map) {
      values.addAll([marker['canonicalMarkerId'], marker['originalMarkerId'], marker['sourceMarkerId'], marker['parentMarkerId']]);
    }
    return values.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet().toList();
  }

  Set<String> _sourceIdsFromMarkers(List<SiteData> markers) {
    final sourceIds = <String>{};
    for (final marker in markers) {
      sourceIds.addAll(_markerOwnIdsFromJson(marker));
      sourceIds.addAll(_markerLinkIdsFromJson(marker));
    }
    sourceIds.removeWhere((id) => id.isEmpty);
    return sourceIds;
  }

  bool _markerHasSourceId(dynamic marker, Set<String> sourceIds) {
    if (sourceIds.isEmpty) return false;
    final markerIds = <String>{
      ..._markerOwnIdsFromJson(marker),
      ..._markerLinkIdsFromJson(marker),
    };
    return markerIds.any(sourceIds.contains);
  }

  bool _matchesGroupName(dynamic value, String oldGroupName, String newGroupName) {
    final name = value?.toString().trim() ?? '';
    return name == oldGroupName || name == newGroupName;
  }

  Set<String> _groupIdentityValues(dynamic value) {
    final values = <dynamic>[];

    if (value is MapGroup) {
      values.add(value.name);
    } else if (value is SiteData) {
      values.add(value.group.name);
    } else if (value is Map) {
      final looksLikeMarker = value.containsKey('group') ||
          value.containsKey('lat') ||
          value.containsKey('lng') ||
          value.containsKey('markerId') ||
          value.containsKey('canonicalMarkerId') ||
          value.containsKey('originalMarkerId') ||
          value.containsKey('sourceMarkerId') ||
          value.containsKey('parentMarkerId');
      final group = value['group'];
      if (group is Map) {
        values.addAll([
          group['id'],
          group['groupId'],
          group['name'],
          group['groupName'],
          group['canonicalGroupId'],
          group['originalGroupId'],
          group['sourceGroupId'],
        ]);
      }
      if (!looksLikeMarker) {
        values.addAll([
          value['id'],
          value['name'],
        ]);
      }
      values.addAll([
        value['groupId'],
        value['groupName'],
        value['canonicalGroupId'],
        value['originalGroupId'],
        value['sourceGroupId'],
      ]);
    }

    return values
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  bool _groupMatchesTarget(dynamic value, MapGroup targetGroup) {
    final targetValues = _groupIdentityValues(targetGroup);
    final values = _groupIdentityValues(value);
    if (targetValues.isEmpty || values.isEmpty) return false;
    return values.any(targetValues.contains);
  }

  bool _rawMarkerInGroup(dynamic marker, MapGroup targetGroup) {
    return _groupMatchesTarget(marker, targetGroup);
  }

  bool _rawGroupHasRemainingMarkers(
    List<dynamic> markers,
    MapGroup targetGroup,
  ) {
    return markers.any((marker) => _rawMarkerInGroup(marker, targetGroup));
  }

  Set<String> _deletedMarkerIdsFromRaw(dynamic marker) {
    return <String>{
      ..._markerOwnIdsFromJson(marker),
      ..._markerLinkIdsFromJson(marker),
    }.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet();
  }

  Set<String> _deletedMarkerIdsFromSite(SiteData marker) {
    return <String>{
      ..._markerOwnIds(marker),
      ..._markerLinkIds(marker),
      marker.id,
    }.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet();
  }

  void _upsertLocalGroupList(
    List<MapGroup> groups, {
    required String oldGroupName,
    required String newGroupName,
    required int newColorValue,
    bool forceAdd = false,
  }) {
    var insertIndex = -1;
    bool? preservedVisible;

    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group.name != oldGroupName && group.name != newGroupName) continue;
      if (insertIndex == -1) insertIndex = i;
      if (group.name == oldGroupName) {
        preservedVisible = group.isVisible;
        break;
      }
      preservedVisible ??= group.isVisible;
    }

    for (var i = groups.length - 1; i >= 0; i--) {
      final group = groups[i];
      if (group.name == oldGroupName || group.name == newGroupName) {
        groups.removeAt(i);
      }
    }

    if (insertIndex == -1 && !forceAdd) return;

    final normalizedGroup = MapGroup(
      name: newGroupName,
      colorValue: newColorValue,
      isVisible: preservedVisible ?? true,
    );
    if (insertIndex == -1 || insertIndex > groups.length) {
      groups.add(normalizedGroup);
    } else {
      groups.insert(insertIndex, normalizedGroup);
    }
  }

  void _applyEditedAdminGroupLocally({
    required String oldGroupName,
    required String newGroupName,
    required int newColorValue,
    required List<SiteData> sourceMarkersBeforeEdit,
  }) {
    final sourceIds = _sourceIdsFromMarkers(sourceMarkersBeforeEdit);

    _upsertLocalGroupList(
      _userGroups,
      oldGroupName: oldGroupName,
      newGroupName: newGroupName,
      newColorValue: newColorValue,
      forceAdd: true,
    );

    for (final marker in _markerDataMap.values) {
      if (_matchesGroupName(marker.group.name, oldGroupName, newGroupName)) {
        marker.group.name = newGroupName;
        marker.group.colorValue = newColorValue;
      }
    }

    for (final team in _allTeamsMap.values) {
      var touchedMarker = false;

      for (final marker in team.markers.values) {
        final shouldUpdate =
            _markerHasSourceId(marker, sourceIds) ||
            _matchesGroupName(marker.group.name, oldGroupName, newGroupName);
        if (!shouldUpdate) continue;

        marker.group.name = newGroupName;
        marker.group.colorValue = newColorValue;
        touchedMarker = true;
      }

      _upsertLocalGroupList(
        team.groups,
        oldGroupName: oldGroupName,
        newGroupName: newGroupName,
        newColorValue: newColorValue,
        forceAdd: touchedMarker,
      );
    }
  }

  Future<int> _syncEditedAdminGroupToDistributedCopies({
    required String oldGroupName,
    required MapGroup editedGroup,
    required List<SiteData> sourceMarkersBeforeEdit,
  }) async {
    if (!isAdmin) return 0;

    final newGroupName = editedGroup.name.trim();
    final oldName = oldGroupName.trim();
    final sourceIds = _sourceIdsFromMarkers(sourceMarkersBeforeEdit);

    final snapshot = await FirebaseFirestore.instance.collection('teams').get();
    final batch = FirebaseFirestore.instance.batch();
    var writes = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final markers = List<dynamic>.from(data['markers'] ?? []);
      final groups = List<dynamic>.from(data['groups'] ?? []);
      final isSourceDoc = doc.id == widget.teamName || doc.id == _adminTeamName;
      final updatedGroups = <dynamic>[];
      Map<String, dynamic>? mergedGroup;
      dynamic oldGroupVisible;
      dynamic newGroupVisible;

      for (final rawGroup in groups) {
        if (rawGroup is! Map) {
          updatedGroups.add(rawGroup);
          continue;
        }

        final groupJson = Map<String, dynamic>.from(rawGroup);
        final groupName = groupJson['name']?.toString() ?? '';
        if (_matchesGroupName(groupName, oldName, newGroupName)) {
          if (groupName == oldName) {
            oldGroupVisible ??= groupJson['isVisible'];
          } else {
            newGroupVisible ??= groupJson['isVisible'];
          }
          mergedGroup ??= groupJson;
          continue;
        }

        updatedGroups.add(rawGroup);
      }

      final preservedIsVisible = oldGroupVisible ?? newGroupVisible;
      var hasLinkedTargetMarker = false;
      dynamic markerVisible;

      for (var i = 0; i < markers.length; i++) {
        final raw = markers[i];
        if (raw is! Map) continue;

        final rawGroup = raw['group'];
        final rawGroupName = rawGroup is Map ? rawGroup['name']?.toString() ?? '' : '';
        final groupMatches = _matchesGroupName(rawGroupName, oldName, newGroupName);
        if (!groupMatches) continue;

        final linkedToSource = _markerHasSourceId(raw, sourceIds);
        final shouldUpdateMarker = isSourceDoc || linkedToSource;
        if (!shouldUpdateMarker) continue;

        if (!isSourceDoc) hasLinkedTargetMarker = true;

        final marker = Map<String, dynamic>.from(raw);
        final groupJson = rawGroup is Map ? Map<String, dynamic>.from(rawGroup) : <String, dynamic>{};
        markerVisible ??= groupJson['isVisible'];
        marker['group'] = {
          ...groupJson,
          'name': newGroupName,
          'colorValue': editedGroup.colorValue,
          'isVisible': groupJson['isVisible'] ?? preservedIsVisible ?? true,
        };
        markers[i] = marker;
      }

      if (!isSourceDoc && !hasLinkedTargetMarker) continue;

      updatedGroups.add({
        ...?mergedGroup,
        'name': newGroupName,
        'colorValue': editedGroup.colorValue,
        'isVisible': preservedIsVisible ?? markerVisible ?? mergedGroup?['isVisible'] ?? true,
      });

      if (writes >= 450) {
        debugPrint('[GROUP_SYNC_TOO_MANY_DOCS] count=${writes + 1}');
        throw StateError('GROUP_SYNC_TOO_MANY_DOCS');
      }

      batch.update(doc.reference, {
        'groups': updatedGroups,
        'markers': markers,
      });
      writes++;
    }

    if (writes == 0) return 0;

    await batch.commit();
    debugPrint(
      '[APP_ADMIN_GROUP_MUTATION] source=${widget.teamName} old=$oldName new=$newGroupName color=${editedGroup.colorValue} docs=$writes',
    );
    return writes;
  }

  bool _rawMarkerMatchesSite(Map<String, dynamic> marker, SiteData site) {
    final rawOwnIds = _markerOwnIdsFromJson(marker);
    final rawLinkIds = _markerLinkIdsFromJson(marker);
    final siteOwnIds = _markerOwnIdsFromJson(site);
    final siteLinkIds = _markerLinkIdsFromJson(site);
    final siteIds = <String>{
      ...siteOwnIds,
      ...siteLinkIds,
      site.id,
    }.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet();

    return rawOwnIds.any(siteIds.contains) ||
        rawLinkIds.any(siteLinkIds.contains) ||
        _matchesMoveMarkerJson(marker, site.id);
  }

  Map<String, dynamic> _resolveMarkerComponent(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    SiteData initiatingMarker,
    String initiatingDocId,
  ) {
    final nodes = <Map<String, dynamic>>[];
    final ownIdToNodes = <String, List<Map<String, dynamic>>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final markers = List<dynamic>.from(data['markers'] ?? const []);
      for (var i = 0; i < markers.length; i++) {
        if (markers[i] is! Map) continue;
        final marker = Map<String, dynamic>.from(markers[i] as Map);
        final node = <String, dynamic>{
          'key': '${doc.id}#$i',
          'doc': doc,
          'docId': doc.id,
          'index': i,
          'marker': marker,
          'ownIds': _markerOwnIdsFromJson(marker),
          'linkIds': _markerLinkIdsFromJson(marker),
          'edges': <String>{},
        };
        nodes.add(node);
        for (final id in node['ownIds'] as List<String>) {
          ownIdToNodes.putIfAbsent(id, () => <Map<String, dynamic>>[]).add(node);
        }
      }
    }

    for (final node in nodes) {
      for (final linkId in node['linkIds'] as List<String>) {
        final linkedNodes = ownIdToNodes[linkId] ?? const <Map<String, dynamic>>[];
        if (linkedNodes.isEmpty) {
          debugPrint('[KAKAO_COMPONENT] unlinked legacy marker doc=${node['docId']} index=${node['index']} linkId=$linkId');
          continue;
        }
        final linkedOwnSignatures = linkedNodes
            .map((n) => List<String>.from(n['ownIds'] as List)..sort())
            .map((ids) => ids.join('|'))
            .toSet();
        if (linkedOwnSignatures.length > 1) {
          debugPrint('[KAKAO_COMPONENT] ambiguous linkId=$linkId matches=${linkedNodes.map((n) => '${n['docId']}#${n['index']}').join(',')}');
          return {'ok': false, 'reason': 'ambiguous', 'nodes': <Map<String, dynamic>>[], 'ids': <String>[]};
        }
        for (final linked in linkedNodes) {
          (node['edges'] as Set<String>).add(linked['key'] as String);
          (linked['edges'] as Set<String>).add(node['key'] as String);
        }
      }
    }

    Map<String, dynamic>? start;
    for (final node in nodes) {
      if (node['docId'] != initiatingDocId) continue;
      if (_rawMarkerMatchesSite(Map<String, dynamic>.from(node['marker'] as Map), initiatingMarker)) {
        start = node;
        break;
      }
    }
    if (start == null) {
      for (final node in nodes) {
        if (_rawMarkerMatchesSite(Map<String, dynamic>.from(node['marker'] as Map), initiatingMarker)) {
          start = node;
          break;
        }
      }
    }

    if (start == null) {
      debugPrint('[KAKAO_COMPONENT] unlinked legacy marker initiatingDoc=$initiatingDocId marker=${initiatingMarker.id}');
      return {'ok': false, 'nodes': <Map<String, dynamic>>[], 'ids': <String>[]};
    }

    final visited = <String>{start['key'] as String};
    final queue = <Map<String, dynamic>>[start];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final edge in current['edges'] as Set<String>) {
        if (!visited.add(edge)) continue;
        final next = nodes.firstWhere((node) => node['key'] == edge);
        queue.add(next);
      }
    }

    final componentNodes = nodes.where((node) => visited.contains(node['key'])).toList();
    final ids = <String>{};
    for (final node in componentNodes) {
      ids.addAll(node['ownIds'] as List<String>);
      ids.addAll(node['linkIds'] as List<String>);
    }
    debugPrint('[KAKAO_COMPONENT] resolved initiatingDoc=$initiatingDocId marker=${initiatingMarker.id} documents=${componentNodes.map((n) => n['docId']).toSet().join(',')} markerCount=${componentNodes.length}');
    return {'ok': true, 'nodes': componentNodes, 'ids': ids.toList(), 'start': start};
  }

  Map<String, dynamic> _resolveLocalMarkerComponent(SiteData initiatingMarker, String initiatingTeamName) {
    final nodes = <Map<String, dynamic>>[];
    final ownIdToNodes = <String, List<Map<String, dynamic>>>{};

    void addMarker(String teamName, String markerKey, SiteData marker, Map<String, LineData> lines) {
      final node = <String, dynamic>{
        'key': '$teamName#${nodes.length}',
        'teamName': teamName,
        'markerKey': markerKey,
        'marker': marker,
        'lines': lines,
        'ownIds': _markerOwnIdsFromJson(marker),
        'linkIds': _markerLinkIdsFromJson(marker),
        'edges': <String>{},
      };
      nodes.add(node);
      for (final id in node['ownIds'] as List<String>) {
        ownIdToNodes.putIfAbsent(id, () => <Map<String, dynamic>>[]).add(node);
      }
    }

    _markerDataMap.forEach((key, marker) => addMarker(widget.teamName, key, marker, _lineDataMap));
    _allTeamsMap.forEach((teamName, team) {
      team.markers.forEach((key, marker) => addMarker(teamName, key, marker, team.lines));
    });

    for (final node in nodes) {
      for (final linkId in node['linkIds'] as List<String>) {
        final linkedNodes = ownIdToNodes[linkId] ?? const <Map<String, dynamic>>[];
        for (final linked in linkedNodes) {
          (node['edges'] as Set<String>).add(linked['key'] as String);
          (linked['edges'] as Set<String>).add(node['key'] as String);
        }
      }
    }

    Map<String, dynamic>? start;
    for (final node in nodes) {
      if (node['teamName'] != initiatingTeamName) continue;
      final marker = node['marker'] as SiteData;
      if (marker.id == initiatingMarker.id ||
          _markerOwnIdsFromJson(marker).any(_markerOwnIdsFromJson(initiatingMarker).contains) ||
          _markerLinkIdsFromJson(marker).any(_markerLinkIdsFromJson(initiatingMarker).contains)) {
        start = node;
        break;
      }
    }
    if (start == null) {
      for (final node in nodes) {
        if ((node['marker'] as SiteData).id == initiatingMarker.id) {
          start = node;
          break;
        }
      }
    }
    if (start == null) return {'ok': false, 'nodes': <Map<String, dynamic>>[], 'ids': <String>[]};

    final visited = <String>{start['key'] as String};
    final queue = <Map<String, dynamic>>[start];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final edge in current['edges'] as Set<String>) {
        if (!visited.add(edge)) continue;
        final next = nodes.firstWhere((node) => node['key'] == edge);
        queue.add(next);
      }
    }

    final componentNodes = nodes.where((node) => visited.contains(node['key'])).toList();
    final ids = <String>{};
    for (final node in componentNodes) {
      ids.addAll(node['ownIds'] as List<String>);
      ids.addAll(node['linkIds'] as List<String>);
    }
    return {'ok': true, 'nodes': componentNodes, 'ids': ids.toList(), 'start': start};
  }

  String _canonicalIdForMutation(SiteData marker) {
    final shared = canonicalMarkerIdForSharedCopy(marker);
    if (shared.isNotEmpty) return shared;
    return canonicalMarkerIdForOwnedMarker(marker);
  }

  List<String> _markerIdCandidatesForRaw(Map marker, String canonicalId) {
    return [
      marker['id'],
      marker['markerId'],
      marker['canonicalMarkerId'],
      marker['originalMarkerId'],
      marker['sourceMarkerId'],
      marker['parentMarkerId'],
      canonicalId,
    ].map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet().toList();
  }

  Map<String, dynamic> _canonicalFieldsFromSite(SiteData marker, Map<String, dynamic> overrides) {
    final fields = <String, dynamic>{
      'lat': overrides['lat'] ?? marker.lat,
      'lng': overrides['lng'] ?? marker.lng,
      'title': overrides['title'] ?? marker.title,
      'description': overrides['description'] ?? marker.description,
      'address': overrides['address'] ?? marker.address,
      'group': overrides['group'] ?? marker.group.toJson(),
      'photos': overrides['photos'] ?? marker.photos.map((p) => p.toJson()).toList(),
      'isChecked': overrides.containsKey('isChecked') ? overrides['isChecked'] == true : marker.isChecked,
    };
    return fields;
  }

  String _moveAddressSequenceKey(SiteData marker, String teamName) {
    final canonicalId = _canonicalIdForMutation(marker);
    if (canonicalId.isNotEmpty) return canonicalId;

    final teamKey = _cleanMarkerId(teamName);
    final markerKey = _cleanMarkerId(marker.id);
    return '$teamKey:$markerKey';
  }

  Future<Map<String, dynamic>?> _buildMovedMarkerCanonicalFields(
    SiteData marker,
    LatLng point,
  ) async {
    final newAddress = await _getKoreanAddressOrNull(point.latitude, point.longitude);
    if (!_isValidMarkerAddress(newAddress)) return null;
    return _canonicalFieldsFromSite(marker, {
      'lat': point.latitude,
      'lng': point.longitude,
      'address': newAddress,
    });
  }

  Future<bool> _finalizeMovedMarkerCanonicalMutation({
    required SiteData marker,
    required LatLng point,
    required String initiatingTeamName,
  }) async {
    final sequenceKey = _moveAddressSequenceKey(marker, initiatingTeamName);
    final sequence = ++_moveAddressSequence;
    _pendingMoveAddressSequences[sequenceKey] = sequence;

    final originalFields = _canonicalFieldsFromSite(marker, {
      'lat': marker.lat,
      'lng': marker.lng,
      'address': marker.address,
    });
    final pendingFields = _canonicalFieldsFromSite(marker, {
      'lat': point.latitude,
      'lng': point.longitude,
      'address': '주소 확인 중...',
    });
    _applyCanonicalMarkerMutationLocally(
      initiatingMarker: marker,
      canonicalFields: pendingFields,
      updateConnectedLines: true,
      initiatingTeamName: initiatingTeamName,
    );

    try {
      final fields = await _buildMovedMarkerCanonicalFields(marker, point);
      if (fields == null) {
        _applyCanonicalMarkerMutationLocally(
          initiatingMarker: marker,
          canonicalFields: originalFields,
          updateConnectedLines: true,
          initiatingTeamName: initiatingTeamName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('새 위치의 주소를 찾지 못해 이동을 저장하지 않았습니다. 다시 시도해 주세요.')),
          );
        }
        return false;
      }
      if (_pendingMoveAddressSequences[sequenceKey] != sequence) {
        if (_verboseMapDebug) debugPrint('[MARKER_MOVE_ADDRESS] skipped stale request canonicalId=$sequenceKey');
        return true;
      }

      _applyCanonicalMarkerMutationLocally(
        initiatingMarker: marker,
        canonicalFields: fields,
        updateConnectedLines: true,
        initiatingTeamName: initiatingTeamName,
      );

      final saved = await _commitCanonicalMarkerMutation(
        initiatingMarker: marker,
        canonicalFields: fields,
        updateConnectedLines: true,
        mutationType: 'move',
        initiatingTeamName: initiatingTeamName,
      );
      if (_verboseMapDebug) {
        debugPrint('[MARKER_MOVE_ADDRESS] resolved canonicalId=$sequenceKey address=${fields['address']}');
      }
      return saved;
    } catch (e) {
      debugPrint('[MARKER_MOVE_ADDRESS] failed canonicalId=$sequenceKey error=$e');
      _applyCanonicalMarkerMutationLocally(
        initiatingMarker: marker,
        canonicalFields: originalFields,
        updateConnectedLines: true,
        initiatingTeamName: initiatingTeamName,
      );
      return false;
    } finally {
      if (_pendingMoveAddressSequences[sequenceKey] == sequence) {
        _pendingMoveAddressSequences.remove(sequenceKey);
      }
    }
  }

  void _applyCanonicalFieldsToSite(SiteData marker, Map<String, dynamic> fields) {
    if (fields.containsKey('lat') && fields.containsKey('lng')) {
      marker.lat = (fields['lat'] as num).toDouble();
      marker.lng = (fields['lng'] as num).toDouble();
    }
    if (fields.containsKey('title')) marker.title = fields['title']?.toString() ?? marker.title;
    if (fields.containsKey('description')) marker.description = fields['description']?.toString() ?? marker.description;
    if (fields.containsKey('address')) marker.address = fields['address']?.toString() ?? marker.address;
    if (fields['group'] is Map) marker.group = MapGroup.fromJson(Map<String, dynamic>.from(fields['group'] as Map));
    if (fields['photos'] is List) {
      marker.photos = (fields['photos'] as List)
          .whereType<Map>()
          .map((p) => PhotoItem.fromJson(Map<String, dynamic>.from(p)))
          .toList();
    }
    if (fields.containsKey('isChecked')) marker.isChecked = fields['isChecked'] == true;
  }

  bool _applyCanonicalFieldsToRawMarker(Map<String, dynamic> marker, Map<String, dynamic> fields) {
    bool changed = false;
    for (final key in ['lat', 'lng', 'title', 'description', 'address', 'group', 'photos']) {
      if (!fields.containsKey(key)) continue;
      if (marker[key] != fields[key]) {
        marker[key] = fields[key];
        changed = true;
      }
    }
    if (fields.containsKey('isChecked')) {
      final next = fields['isChecked'] == true;
      if (marker['isChecked'] != next ||
          (marker.containsKey('checked') && marker['checked'] != next) ||
          (marker.containsKey('isOn') && marker['isOn'] != next)) {
        marker['isChecked'] = next;
        if (marker.containsKey('checked')) marker['checked'] = next;
        if (marker.containsKey('isOn')) marker['isOn'] = next;
        changed = true;
      }
    }
    return changed;
  }

  bool _updateConnectedLinePointsJson(List<dynamic> lines, Iterable<String> markerIds, LatLng point) {
    final ids = markerIds.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return false;

    bool changed = false;
    for (final rawLine in lines) {
      if (rawLine is! Map) continue;
      final markerIdsJson = List<dynamic>.from(rawLine['markerIds'] ?? const []);
      final points = List<dynamic>.from(rawLine['points'] ?? const []);
      if (markerIdsJson.isEmpty || points.length < markerIdsJson.length) continue;

      bool lineChanged = false;
      for (var i = 0; i < markerIdsJson.length && i < points.length; i++) {
        if (!ids.contains(_cleanMarkerId(markerIdsJson[i]))) continue;
        final current = points[i] is Map ? Map<String, dynamic>.from(points[i] as Map) : <String, dynamic>{};
        if ((current['lat'] as num?)?.toDouble() != point.latitude ||
            (current['lng'] as num?)?.toDouble() != point.longitude) {
          points[i] = {...current, 'lat': point.latitude, 'lng': point.longitude};
          lineChanged = true;
        }
      }

      if (lineChanged) {
        rawLine['points'] = points;
        changed = true;
      }
    }
    return changed;
  }

  Map<String, dynamic> _removeDeletedMarkerPointsFromLinesJson(
    List<dynamic> rawLines,
    Set<String> deletedMarkerIds,
  ) {
    final deletedIds = deletedMarkerIds.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet();
    final nextLines = <dynamic>[];
    var changed = false;
    var changedLineCount = 0;

    for (final rawLine in rawLines) {
      if (rawLine is! Map) {
        nextLines.add(rawLine);
        continue;
      }

      final line = Map<String, dynamic>.from(rawLine);
      final markerIds = List<dynamic>.from(line['markerIds'] ?? const []);
      final points = List<dynamic>.from(line['points'] ?? const []);
      var lineChanged = false;

      for (var i = markerIds.length - 1; i >= 0; i--) {
        if (deletedIds.contains(_cleanMarkerId(markerIds[i]))) {
          markerIds.removeAt(i);
          if (i < points.length) points.removeAt(i);
          lineChanged = true;
        }
      }

      if (!lineChanged) {
        nextLines.add(rawLine);
        continue;
      }

      changed = true;
      changedLineCount++;
      if (markerIds.length < 2) continue;

      line['markerIds'] = markerIds;
      line['points'] = points;
      nextLines.add(line);
    }

    return {
      'lines': nextLines,
      'changed': changed,
      'changedLineCount': changedLineCount,
    };
  }

  int _removeDeletedMarkerPointsFromLineMap(
    Map<String, LineData> lines,
    Set<String> deletedMarkerIds,
  ) {
    final deletedIds = deletedMarkerIds.map(_cleanMarkerId).where((id) => id.isNotEmpty).toSet();
    var changedLineCount = 0;

    for (final entry in lines.entries.toList()) {
      final line = entry.value;
      var lineChanged = false;

      for (var i = line.markerIds.length - 1; i >= 0; i--) {
        if (deletedIds.contains(_cleanMarkerId(line.markerIds[i]))) {
          line.markerIds.removeAt(i);
          if (i < line.points.length) line.points.removeAt(i);
          lineChanged = true;
        }
      }

      if (!lineChanged) continue;
      changedLineCount++;
      if (line.markerIds.length < 2) {
        lines.remove(entry.key);
      }
    }

    return changedLineCount;
  }

  void _applyCanonicalMarkerMutationLocally({
    required SiteData initiatingMarker,
    required Map<String, dynamic> canonicalFields,
    required bool updateConnectedLines,
    String? initiatingTeamName,
  }) {
    final sourceTeamName = initiatingTeamName ?? widget.teamName;
    final point = canonicalFields.containsKey('lat') && canonicalFields.containsKey('lng')
        ? LatLng((canonicalFields['lat'] as num).toDouble(), (canonicalFields['lng'] as num).toDouble())
        : null;

    if (!mounted) return;
    final component = _resolveLocalMarkerComponent(initiatingMarker, sourceTeamName);
    if (component['ok'] != true) return;
    final componentIds = List<String>.from(component['ids'] as List);
    final componentNodes = List<Map<String, dynamic>>.from(component['nodes'] as List);

    setState(() {
      for (final node in componentNodes) {
        final marker = node['marker'] as SiteData;
        _applyCanonicalFieldsToSite(marker, canonicalFields);
        if (point != null && updateConnectedLines) {
          final lines = node['lines'] as Map<String, LineData>;
          for (final markerId in <String>{marker.id, ...componentIds}) {
            _updateConnectedLinePoints(lines, markerId, point);
          }
        }
      }
    });

    _invalidateMarkerRenderHash();
    _scheduleMarkerUpdate(ms: 0);
  }

  Future<bool> _commitCanonicalMarkerMutation({
    required SiteData initiatingMarker,
    required Map<String, dynamic> canonicalFields,
    required bool updateConnectedLines,
    required String mutationType,
    String? initiatingTeamName,
  }) async {
    final sourceTeamName = initiatingTeamName ?? widget.teamName;

    final snapshot = await FirebaseFirestore.instance.collection('teams').get();
    final component = _resolveMarkerComponent(snapshot, initiatingMarker, sourceTeamName);
    if (component['ok'] != true) return false;
    final componentNodes = List<Map<String, dynamic>>.from(component['nodes'] as List);
    final componentIds = List<String>.from(component['ids'] as List);
    final targets = <String, Map<String, dynamic>>{};

    void addTarget(QueryDocumentSnapshot<Map<String, dynamic>> doc, int index) {
      if (index < 0) return;
      targets.putIfAbsent(doc.id, () => {
        'doc': doc,
        'indexes': <int>{},
      });
      (targets[doc.id]!['indexes'] as Set<int>).add(index);
    }

    for (final node in componentNodes) {
      addTarget(
        node['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>,
        node['index'] as int,
      );
    }

    if (targets.isEmpty) return false;
    if (targets.length > 450) {
      debugPrint('[CANONICAL_MARKER_MUTATION_TOO_MANY_DOCS] count=${targets.length}');
      return false;
    }

    final WriteBatch batch = FirebaseFirestore.instance.batch();
    var writes = 0;

    for (final target in targets.values) {
      final doc = target['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
      final indexes = target['indexes'] as Set<int>;
      final data = doc.data();
      final markers = List<dynamic>.from(data['markers'] ?? const []);
      final lines = List<dynamic>.from(data['lines'] ?? const []);
      var changed = false;

      for (final index in indexes) {
        if (index < 0 || index >= markers.length || markers[index] is! Map) continue;
        final marker = Map<String, dynamic>.from(markers[index] as Map);
        if (_applyCanonicalFieldsToRawMarker(marker, canonicalFields)) changed = true;
        markers[index] = marker;

        if (updateConnectedLines && canonicalFields.containsKey('lat') && canonicalFields.containsKey('lng')) {
          final point = LatLng((canonicalFields['lat'] as num).toDouble(), (canonicalFields['lng'] as num).toDouble());
          final ids = <String>{
            ..._markerIdCandidatesForRaw(marker, ''),
            ...componentIds,
          };
          if (_updateConnectedLinePointsJson(lines, ids, point)) {
            changed = true;
          }
        }
      }

      if (!changed) continue;
      final payload = <String, dynamic>{'markers': markers};
      if (updateConnectedLines) payload['lines'] = lines;
      batch.update(doc.reference, payload);
      writes++;
    }

    if (writes == 0) return true;
    await batch.commit();
    debugPrint('[CANONICAL_MARKER_MUTATION_COMMIT] type=$mutationType docs=$writes');
    return true;
  }

  Future<bool> _commitCanonicalMarkerDeletion({
    required SiteData initiatingMarker,
    String? initiatingTeamName,
  }) async {
    final sourceTeamName = initiatingTeamName ?? widget.teamName;

    try {
      final snapshot = await FirebaseFirestore.instance.collection('teams').get();
      final component = _resolveMarkerComponent(snapshot, initiatingMarker, sourceTeamName);
      if (component['ok'] != true) {
        final reason = component['reason']?.toString();
        debugPrint('[KAKAO_DELETE_COMPONENT] ${reason == 'ambiguous' ? 'ambiguous' : 'not_found'} marker=${initiatingMarker.id}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reason == 'ambiguous' ? '공유 마커 연결이 모호하여 삭제하지 못했습니다.' : '삭제할 마커를 찾을 수 없습니다.')),
          );
        }
        return false;
      }

      final componentNodes = List<Map<String, dynamic>>.from(component['nodes'] as List);
      final targets = <String, Map<String, dynamic>>{};
      for (final node in componentNodes) {
        final doc = node['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
        final index = node['index'] as int;
        targets.putIfAbsent(doc.id, () => {
          'doc': doc,
          'indexes': <int>{},
        });
        (targets[doc.id]!['indexes'] as Set<int>).add(index);
      }

      if (targets.isEmpty) return false;
      if (targets.length > 450) {
        debugPrint('[KAKAO_DELETE_COMPONENT] too_many_documents count=${targets.length}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('동기화 대상이 너무 많아 삭제를 중단했습니다.')));
        }
        return false;
      }

      debugPrint('[KAKAO_DELETE_COMPONENT] resolved documents=${targets.keys.join(',')} markers=${componentNodes.length}');
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      var writes = 0;
      var removedCount = 0;
      var changedLineCount = 0;
      final componentIds = List<String>.from(component['ids'] as List)
          .map(_cleanMarkerId)
          .where((id) => id.isNotEmpty)
          .toSet();

      for (final target in targets.values) {
        final doc = target['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
        final indexes = List<int>.from(target['indexes'] as Set<int>)..sort((a, b) => b.compareTo(a));
        final data = doc.data();
        final markers = List<dynamic>.from(data['markers'] ?? const []);
        final lines = List<dynamic>.from(data['lines'] ?? const []);
        final deletedIds = <String>{};
        var changed = false;

        for (final index in indexes) {
          if (index < 0 || index >= markers.length) continue;
          deletedIds.addAll(_markerOwnIdsFromJson(markers[index]));
          deletedIds.addAll(_markerLinkIdsFromJson(markers[index]));
          markers.removeAt(index);
          removedCount++;
          changed = true;
        }

        if (!changed) continue;
        for (final rawLine in lines) {
          if (rawLine is! Map) continue;
          final markerIds = List<dynamic>.from(rawLine['markerIds'] ?? const []);
          for (final markerId in markerIds) {
            final cleaned = _cleanMarkerId(markerId);
            if (cleaned.isNotEmpty && componentIds.contains(cleaned)) {
              deletedIds.add(cleaned);
            }
          }
        }

        final lineResult = _removeDeletedMarkerPointsFromLinesJson(lines, deletedIds);
        if (lineResult['changed'] == true) {
          changedLineCount += (lineResult['changedLineCount'] as int? ?? 0);
        }

        final payload = <String, dynamic>{'markers': markers};
        if (lineResult['changed'] == true) payload['lines'] = lineResult['lines'];
        batch.update(doc.reference, payload);
        writes++;
      }

      if (writes == 0 || removedCount == 0) return false;
      await batch.commit();
      debugPrint('[KAKAO_DELETE_COMPONENT] committed documents=$writes markers=$removedCount lines=$changedLineCount');
      return true;
    } catch (e) {
      debugPrint('[KAKAO_DELETE_COMPONENT] failed $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('마커 삭제에 실패했습니다.')));
      }
      return false;
    }
  }

  void _applyCanonicalMarkerDeletionLocally({
    required SiteData initiatingMarker,
    String? initiatingTeamName,
  }) {
    final sourceTeamName = initiatingTeamName ?? widget.teamName;
    final component = _resolveLocalMarkerComponent(initiatingMarker, sourceTeamName);
    if (component['ok'] != true) return;
    final nodes = List<Map<String, dynamic>>.from(component['nodes'] as List);
    final componentIds = List<String>.from(component['ids'] as List)
        .map(_cleanMarkerId)
        .where((id) => id.isNotEmpty)
        .toSet();

    setState(() {
      final deletedIdsByTeam = <String, Set<String>>{};

      for (final node in nodes) {
        final teamName = node['teamName']?.toString() ?? '';
        final markerKey = node['markerKey']?.toString() ?? '';
        final marker = node['marker'] as SiteData;
        deletedIdsByTeam.putIfAbsent(teamName, () => <String>{})
          ..addAll(_markerOwnIds(marker))
          ..addAll(_markerLinkIds(marker))
          ..add(_cleanMarkerId(markerKey));
        if (teamName == widget.teamName) {
          _markerDataMap.remove(markerKey);
          _markerDataMap.remove(marker.id);
        } else {
          final team = _allTeamsMap[teamName];
          if (team != null) {
            team.markers.remove(markerKey);
            team.markers.remove(marker.id);
          }
        }
      }

      deletedIdsByTeam.forEach((teamName, deletedIds) {
        final lines = teamName == widget.teamName ? _lineDataMap : _allTeamsMap[teamName]?.lines;
        if (lines == null) return;
        for (final line in lines.values) {
          for (final markerId in line.markerIds) {
            final cleaned = _cleanMarkerId(markerId);
            if (cleaned.isNotEmpty && componentIds.contains(cleaned)) {
              deletedIds.add(cleaned);
            }
          }
        }
        _removeDeletedMarkerPointsFromLineMap(lines, deletedIds);
      });
    });

    _invalidateMarkerRenderHash();
    _invalidateLineRenderHash();
    _scheduleMarkerUpdate(ms: 0);
  }

  Future<void> _confirmAndDeleteMarker(
    SiteData marker, {
    String? initiatingTeamName,
    BuildContext? detailContext,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        title: const Text('마커 삭제'),
        content: const Text('이 마커를 삭제하면 공유된 모든 화면에서도 함께 삭제됩니다. 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(confirmCtx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final teamName = initiatingTeamName ?? widget.teamName;
    final deleted = await _commitCanonicalMarkerDeletion(
      initiatingMarker: marker,
      initiatingTeamName: teamName,
    );
    if (!deleted || !mounted) return;

    _applyCanonicalMarkerDeletionLocally(
      initiatingMarker: marker,
      initiatingTeamName: teamName,
    );
    if (detailContext != null && detailContext.mounted) {
      Navigator.pop(detailContext);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('마커가 삭제되었습니다.')));
  }

  Future<bool> _saveMarkerCheckToTeamDoc(String teamName, String markerId, String originalMarkerId, bool isChecked, {String? groupName}) async {
    final docRef = FirebaseFirestore.instance.collection('teams').doc(teamName);
    bool updated = false;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists || snapshot.data() == null) return;

      final data = snapshot.data()!;
      final markers = List<dynamic>.from(data['markers'] ?? []);
      final markerIndex = markers.indexWhere((m) =>
          m is Map &&
          (groupName == null ||
              (m['group'] is Map && m['group']['name'] == groupName)) &&
          _matchesSharedMarkerJson(Map<String, dynamic>.from(m), markerId, originalMarkerId));
      if (markerIndex == -1) return;

      final marker = Map<String, dynamic>.from(markers[markerIndex] as Map);
      _setMarkerCheckFields(marker, isChecked);
      markers[markerIndex] = marker;

      transaction.update(docRef, {'markers': markers});
      updated = true;
    });

    return updated;
  }

  Future<bool> _updateMovedMarkerByPath(String teamName, String? groupName, List<String> markerIds, LatLng point, {bool sharedMove = false}) async {
    if (markerIds.isEmpty) return false;

    if (teamName == widget.teamName) {
      final entry = _findMarkerEntryInGroup(_markerDataMap, groupName, markerIds);
      if (entry == null) return false;

      final site = entry.value;
      final actualId = site.id;
      setState(() {
        if (entry.key != actualId) {
          _markerDataMap.remove(entry.key);
          _markerDataMap[actualId] = site;
        }
      });
      return _finalizeMovedMarkerCanonicalMutation(
        marker: site,
        point: point,
        initiatingTeamName: teamName,
      );
    }

    final team = _allTeamsMap[teamName];
    if (team == null) return false;

    final entry = _findMarkerEntryInGroup(team.markers, groupName, markerIds);
    if (entry == null) return false;

    final site = entry.value;
    final actualId = site.id;
    setState(() {
      if (entry.key != actualId) {
        team.markers.remove(entry.key);
        team.markers[actualId] = site;
      }
    });
    return _finalizeMovedMarkerCanonicalMutation(
      marker: site,
      point: point,
      initiatingTeamName: teamName,
    );
  }

  Future<bool> _saveMovedMarkerToTeamDoc(String teamName, String markerId, LatLng point, {String? groupName, List<String>? markerIds}) async {
    final docRef = FirebaseFirestore.instance.collection('teams').doc(teamName);
    bool updated = false;
    final candidates = markerIds == null || markerIds.isEmpty ? [markerId] : markerIds;
    final movedAddress = await _getKoreanAddressOrNull(point.latitude, point.longitude);
    if (!_isValidMarkerAddress(movedAddress)) return false;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final markers = List<dynamic>.from(data['markers'] ?? []);
      final markerIndex = markers.indexWhere((m) =>
          m is Map &&
          (groupName == null ||
              (m['group'] is Map && m['group']['name'] == groupName)) &&
          candidates.any((candidate) => _matchesMoveMarkerJson(Map<String, dynamic>.from(m), candidate)));
      if (markerIndex == -1) return;

      final marker = Map<String, dynamic>.from(markers[markerIndex] as Map);
      final savedMarkerId = marker['id']?.toString() ?? markerId;
      marker['lat'] = point.latitude;
      marker['lng'] = point.longitude;
      marker['address'] = movedAddress;
      markers[markerIndex] = marker;

      final updates = <String, dynamic>{'markers': markers};
      final lines = List<dynamic>.from(data['lines'] ?? []);
      bool lineChanged = false;

      for (int i = 0; i < lines.length; i++) {
        if (lines[i] is! Map) continue;

        final line = Map<String, dynamic>.from(lines[i] as Map);
        final markerIds = List<dynamic>.from(line['markerIds'] ?? []);
        final points = List<dynamic>.from(line['points'] ?? []);
        bool thisLineChanged = false;

        for (int j = 0; j < markerIds.length && j < points.length; j++) {
          if (markerIds[j] == markerId || markerIds[j] == savedMarkerId) {
            points[j] = {'lat': point.latitude, 'lng': point.longitude};
            thisLineChanged = true;
            lineChanged = true;
          }
        }

        if (thisLineChanged) {
          line['points'] = points;
          lines[i] = line;
        }
      }

      if (lineChanged) updates['lines'] = lines;
      transaction.update(docRef, updates);
      updated = true;
    });
    return updated;
  }

  Future<void> _handleKakaoMarkerMoved(String message) async {
    if (_verboseMapDebug) debugPrint('[KAKAO_MOVE_HANDLER] payload=$message');
    if (!_isMoveMode) return;

    try {
      final data = jsonDecode(message);
      if (data is! Map) return;

      final markerId = data['markerId']?.toString() ?? '';
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (markerId.isEmpty || lat == null || lng == null) return;

      final point = LatLng(lat, lng);
      final target = data['updateTarget'] is Map ? Map<String, dynamic>.from(data['updateTarget'] as Map) : <String, dynamic>{};
      final targetTeamName = target['teamName']?.toString();
      final targetGroupName = (target['groupName'] ?? data['groupName'])?.toString();
      final candidates = _moveMarkerCandidates(data, target);
      final scope = (data['scope'] ?? target['scope'])?.toString() ?? '';
      final originalMarkerId = (data['originalMarkerId'] ?? target['originalMarkerId'])?.toString() ?? '';
      final isSharedMove = scope == 'shared' || originalMarkerId.isNotEmpty;

      if (targetTeamName != null && targetTeamName.isNotEmpty) {
        final updated = await _updateMovedMarkerByPath(targetTeamName, targetGroupName, candidates, point, sharedMove: isSharedMove);
        if (updated) {
          _invalidateMarkerRenderHash();
          _scheduleMarkerUpdate(ms: 0);
          if (_verboseMapDebug) debugPrint('[KAKAO_MOVE_FOUND] scope=$scope markerId=$markerId originalMarkerId=$originalMarkerId');
        } else if (isSharedMove) {
          debugPrint('[KAKAO_MOVE_SKIP_CREATE] shared target not found markerId=$markerId originalMarkerId=$originalMarkerId');
        } else {
          debugPrint('[KAKAO_MOVE_SKIP_CREATE] own target not found markerId=$markerId');
        }
        return;
      }

      if (isSharedMove) {
        bool updated = await _updateMovedMarkerByPath(widget.teamName, targetGroupName, candidates, point, sharedMove: true);
        if (!updated && isAdmin) {
          for (final entry in _allTeamsMap.entries) {
            updated = await _updateMovedMarkerByPath(entry.key, targetGroupName, candidates, point, sharedMove: true);
            if (updated) break;
          }
        }
        if (updated) {
          _invalidateMarkerRenderHash();
          _scheduleMarkerUpdate(ms: 0);
          if (_verboseMapDebug) debugPrint('[KAKAO_MOVE_FOUND] scope=$scope markerId=$markerId originalMarkerId=$originalMarkerId');
        } else {
          debugPrint('[KAKAO_MOVE_SKIP_CREATE] shared target not found markerId=$markerId originalMarkerId=$originalMarkerId');
        }
        return;
      }

      final ownEntry = _findMarkerEntry(_markerDataMap, markerId);

      if (ownEntry != null) {
        final ownMarker = ownEntry.value;
        final actualId = ownMarker.id;
        setState(() {
          if (ownEntry.key != actualId) {
            _markerDataMap.remove(ownEntry.key);
            _markerDataMap[actualId] = ownMarker;
          }
        });
        final canonicalSaved = await _finalizeMovedMarkerCanonicalMutation(
          marker: ownMarker,
          point: point,
          initiatingTeamName: widget.teamName,
        );
        if (canonicalSaved) {
          _invalidateMarkerRenderHash();
          _scheduleMarkerUpdate(ms: 0);
          if (_verboseMapDebug) debugPrint('[KAKAO_MOVE_FOUND] scope=$scope markerId=$markerId originalMarkerId=$originalMarkerId');
        } else {
          debugPrint('[KAKAO_MOVE_SKIP_CREATE] own target not found markerId=$markerId');
        }
        return;
      }

      if (!isAdmin) {
        debugPrint('[KAKAO_MOVE_SKIP_CREATE] own target not found markerId=$markerId');
        return;
      }

      for (final entry in _allTeamsMap.entries) {
        final docPrefix = '${entry.key}_';
        final namePrefix = '${entry.value.teamName}_';
        final String localId;
        if (markerId.startsWith(docPrefix)) {
          localId = markerId.substring(docPrefix.length);
        } else if (markerId.startsWith(namePrefix)) {
          localId = markerId.substring(namePrefix.length);
        } else {
          continue;
        }

        final siteEntry = _findMarkerEntry(entry.value.markers, localId);
        if (siteEntry == null) {
          debugPrint('[KAKAO_MOVE_SKIP_CREATE] own target not found markerId=$markerId');
          return;
        }

        final site = siteEntry.value;
        final actualId = site.id;
        setState(() {
          if (siteEntry.key != actualId) {
            entry.value.markers.remove(siteEntry.key);
            entry.value.markers[actualId] = site;
          }
        });
        final canonicalSaved = await _finalizeMovedMarkerCanonicalMutation(
          marker: site,
          point: point,
          initiatingTeamName: entry.key,
        );
        if (canonicalSaved) {
          _invalidateMarkerRenderHash();
          _scheduleMarkerUpdate(ms: 0);
          if (_verboseMapDebug) debugPrint('[KAKAO_MOVE_FOUND] scope=$scope markerId=$markerId originalMarkerId=$originalMarkerId');
        } else {
          debugPrint('[KAKAO_MOVE_SKIP_CREATE] own target not found markerId=$markerId');
        }
        return;
      }
      debugPrint('[KAKAO_MOVE_SKIP_CREATE] own target not found markerId=$markerId');
    } catch (e) {
      debugPrint('MarkerDragChannel parse failed: $e');
    }
  }

  LatLng? _parseKakaoMapTapPoint(String message) {
    try {
      final data = jsonDecode(message);
      if (data is Map<String, dynamic>) {
        return LatLng(
          (data['lat'] as num).toDouble(),
          (data['lng'] as num).toDouble(),
        );
      }
    } catch (_) {
      final parts = message.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }

    return null;
  }

  Future<void> _handleKakaoMapTap(String message) async {
    if (_isModalOpen || !_isMapControlActive) return;

    final point = _parseKakaoMapTapPoint(message);
    if (point == null) {
      debugPrint('MapTapChannel parse failed: $message');
      return;
    }

    if (_isMoveMode) {
      return;
    } else if (_canQuickSlotCreateMarker) {
      await _quickCreateMarkerAt(point);
    } else if (
      isAdmin &&
      _isAdminQuickSlotsVisible &&
      _quickGroupMode == 1 &&
      _quickSelectedGroupName != null &&
      !_isLineMode &&
      !_isFreeLineMode &&
      !_isLineDeleteMode
    ) {
      _showInputSheet(newPoint: point);
    } else if (_isTappingMode) {
      _showInputSheet(newPoint: point);
    } else if (_isFreeLineMode) {
      _setStateAndRefreshMap(() => _tempFreeLinePoints.add(point));
    } else if (_selectedLineIds.isNotEmpty) {
      setState(_clearSelectedLines);
    }
  }

  @override
  void initState() { 
    super.initState(); 
    WidgetsBinding.instance.addObserver(this); // ◀ 이 줄 추가
    if (!_shouldUseNativeKakaoMap) {
      _initializeKakaoWebView();
    } else {
      _nativeKakaoMapEvents.setMethodCallHandler(_handleNativeKakaoMapEvent);
    }
    _loadData().then((_) => _scheduleMarkerUpdate());
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePendingFieldPhotoUploadIfNeeded());
  }

  @override
void dispose() {
  _markerUpdateTimer?.cancel();
  _mapInteractionSafetyTimer?.cancel();
  _nativeLineRetryTimer?.cancel();
  WidgetsBinding.instance.removeObserver(this);
  MockLocationPlugin.stopMockLocation();
  _myTeamSub?.cancel();    // ← 추가
  _allTeamsSub?.cancel();  // ← 추가
  if (_shouldUseNativeKakaoMap) {
    _nativeKakaoMapEvents.setMethodCallHandler(null);
  }
  super.dispose();
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cancelMapInteractionSafetyTimer();
      _isMapInteracting = false;
      _hasPendingMarkerUpdate = true;
      _scheduleMarkerUpdate(ms: 150);
    }
    if (state == AppLifecycleState.detached) {
      MockLocationPlugin.stopMockLocation(); 
      debugPrint("앱이 완전히 종료되어 원래 GPS로 복구했습니다.");
    }
  }

  Future<void> _moveToCurrentLocation() async {
  try {
    // 📍 지도가 완전히 로드될 때까지 0.5초만 기다려줍니다.
    await Future.delayed(const Duration(milliseconds: 500));

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    await _showCurrentLocationOnMap(position.latitude, position.longitude);
    await _moveTo(position.latitude, position.longitude, _shouldUseNativeKakaoMap ? _nativeFocusedZoomLevel : 3);
  } catch (e) {
    debugPrint("위치 이동 에러: $e");
  }
}


void _scheduleMarkerUpdate({int ms = 80}) {
  if (!mounted) return;
  _markerUpdateTimer?.cancel();
  if (_verboseMapDebug) debugPrint('[KAKAO_RENDER] scheduled ms=$ms');

  _markerUpdateTimer = Timer(Duration(milliseconds: ms), () {
    if (mounted) _flushMarkerUpdate();
  });
}

Future<void> _flushMarkerUpdate() async {
  if (!mounted) return;

  if (_isMapInteracting) {
    _hasPendingMarkerUpdate = true;
    if (_verboseMapDebug) debugPrint('[KAKAO_RENDER] blocked while map interacting');
    return;
  }

  _hasPendingMarkerUpdate = false;
  if (_shouldUseNativeKakaoMap) {
    await _renderMarkersOnNativeKakaoMap();
    await _renderLinesOnNativeKakaoMap();
  } else {
    await _renderMarkersOnKakaoMap();
    await _renderLinesOnKakaoMap();
  }
}

void _flushPendingMarkerUpdateAfterMapIdle() {
  if (!mounted) return;
  if (_hasPendingMarkerUpdate) {
    _hasPendingMarkerUpdate = false;
    if (_verboseMapDebug) debugPrint('[KAKAO_RENDER] flushed after map idle');
    _scheduleMarkerUpdate(ms: 150);
  }
}

void _startMapInteractionSafetyTimer() {
  _mapInteractionSafetyTimer?.cancel();
  _mapInteractionSafetyTimer = Timer(const Duration(seconds: 3), () {
    _mapInteractionSafetyTimer = null;
    if (!mounted || !_isMapInteracting) return;
    _isMapInteracting = false;
    _flushPendingMarkerUpdateAfterMapIdle();
  });
}

void _cancelMapInteractionSafetyTimer() {
  _mapInteractionSafetyTimer?.cancel();
  _mapInteractionSafetyTimer = null;
}

void _invalidateMarkerRenderHash() {
  _lastSentMarkersHash = null;
  _lastSentLinesHash = null;
  _lastSentNativeLinesHash = null;
  _pendingNativeLineRetryHash = null;
  _nativeLineRetryTimer?.cancel();
}

void _invalidateLineRenderHash() {
  _lastSentLinesHash = null;
  _lastSentNativeLinesHash = null;
  _pendingNativeLineRetryHash = null;
  _nativeLineRetryTimer?.cancel();
}

String _colorToHex(Color color) {
  return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

String _firstNonEmptyMarkerSource(SiteData site) {
  final canonical = site.canonicalMarkerId?.trim();
  final original = site.originalMarkerId?.trim();
  final source = site.sourceMarkerId?.trim();
  final parent = site.parentMarkerId?.trim();

  if (canonical != null && canonical.isNotEmpty) return canonical;
  if (original != null && original.isNotEmpty) return original;
  if (source != null && source.isNotEmpty) return source;
  if (parent != null && parent.isNotEmpty) return parent;
  return '';
}

bool _isSharedMarkerData(SiteData site) {
  return _firstNonEmptyMarkerSource(site).isNotEmpty;
}

String _markerDisplayKey(SiteData site, String fallbackId, {required String teamName}) {
  final sharedKey = _firstNonEmptyMarkerSource(site);
  if (sharedKey.isNotEmpty) return 'shared:$sharedKey';

  final ownId = site.id.trim().isNotEmpty ? site.id.trim() : fallbackId;
  return 'own:$teamName:$ownId';
}

String _markerCoordHashFromJson(Map<String, dynamic> marker) {
  final lat = (marker['lat'] as num?)?.toDouble() ?? 0;
  final lng = (marker['lng'] as num?)?.toDouble() ?? 0;
  return '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
}

bool _isSameMarkerRenderPosition(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aLat = (a['lat'] as num?)?.toDouble();
  final aLng = (a['lng'] as num?)?.toDouble();
  final bLat = (b['lat'] as num?)?.toDouble();
  final bLng = (b['lng'] as num?)?.toDouble();
  if (aLat == null || aLng == null || bLat == null || bLng == null) return false;

  return (aLat - bLat).abs() <= 0.00001 && (aLng - bLng).abs() <= 0.00001;
}

int _markerRenderPriority(SiteData site, {required String teamName}) {
  if (teamName == widget.teamName) return 0;
  if (teamName == _adminTeamName) return 1;
  if (!_isSharedMarkerData(site)) return 2;
  return 3;
}

List<String> _stableStringList(Iterable<dynamic> values) {
  final result = values
      .where((v) => v != null && v.toString().trim().isNotEmpty)
      .map((v) => v.toString())
      .toSet()
      .toList()
    ..sort();
  return result;
}

void _applyMarkerRenderKey(Map<String, dynamic> marker) {
  marker['renderKey'] = [
    marker['id'] ?? '',
    marker['displayKey'] ?? '',
    marker['lat'] ?? '',
    marker['lng'] ?? '',
    marker['title'] ?? marker['name'] ?? '',
    marker['address'] ?? '',
    marker['groupName'] ?? '',
    marker['color'] ?? '',
    marker['isChecked'] ?? false,
    marker['duplicateCount'] ?? 1,
  ].join('|');
}

Map<String, dynamic> _siteToMarkerJson(
  String id,
  SiteData site,
  MapGroup group, {
  required String scope,
  required String teamName,
}) {
  final groupKey = group.name;
  final color = _colorToHex(group.color);
  final displayKey = _markerDisplayKey(site, id, teamName: teamName);
  final marker = <String, dynamic>{
    'id': id,
    'markerId': site.id,
    'lat': site.lat,
    'lng': site.lng,
    'title': site.title,
    'address': site.address,
    'color': color,
    'colorValue': group.colorValue,
    'groupName': group.name,
    'groupKey': groupKey,
    'scope': scope,
    'teamName': teamName,
    'ownerTeam': teamName,
    'displayKey': displayKey,
    'duplicateCount': 1,
    'duplicateTeams': <String>[teamName],
    'duplicateGroupNames': <String>[group.name],
    'isDeduped': false,
    if (site.canonicalMarkerId != null) 'canonicalMarkerId': site.canonicalMarkerId,
    if (site.originalMarkerId != null) 'originalMarkerId': site.originalMarkerId,
    if (site.sourceMarkerId != null) 'sourceMarkerId': site.sourceMarkerId,
    if (site.parentMarkerId != null) 'parentMarkerId': site.parentMarkerId,
    'updateTarget': {
      'teamName': teamName,
      'groupName': group.name,
      'groupKey': groupKey,
      'markerId': site.id,
      'canonicalMarkerId': site.canonicalMarkerId,
      'originalMarkerId': site.originalMarkerId,
      'sourceMarkerId': site.sourceMarkerId,
      'parentMarkerId': site.parentMarkerId,
      'scope': scope,
    },
    'isChecked': site.isChecked,
    '_baseDisplayKey': displayKey,
    '_renderPriority': _markerRenderPriority(site, teamName: teamName),
  };
  _applyMarkerRenderKey(marker);
  return marker;
}

String _normalizeSharedMarkerId(String id) {
  var value = id.trim();
  if (value.isEmpty) return value;

  final knownPrefixes = <String>{
    widget.teamName,
    _adminTeamName,
    ..._allTeamsMap.keys,
    ..._allTeamsMap.values.map((team) => team.teamName),
  }.where((prefix) => prefix.trim().isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  for (final prefix in knownPrefixes) {
    final token = '${prefix}_';
    if (value.startsWith(token) && value.length > token.length) {
      value = value.substring(token.length);
      break;
    }
  }

  return value;
}

String _linePathHash(LineData line) {
  return line.points
      .map((p) => '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
      .join('>');
}

String _lineDisplayKey(LineData line, {required String ownerTeam}) {
  final canonicalLineId = [
    line.canonicalLineId,
    line.originalLineId,
    line.sourceLineId,
    line.parentLineId,
  ].map((id) => id?.trim() ?? '').firstWhere((id) => id.isNotEmpty, orElse: () => '');
  if (canonicalLineId.isNotEmpty) return 'canonical:$canonicalLineId';

  final id = line.id.trim();
  return 'line:$ownerTeam:${id.isNotEmpty ? id : _linePathHash(line)}';
}

int _lineRenderPriority({required String ownerTeam}) {
  if (ownerTeam == widget.teamName) return 0;
  if (ownerTeam == _adminTeamName) return 1;
  return 3;
}

void _applyLineRenderKey(Map<String, dynamic> line) {
  final markerIdsKey = List<dynamic>.from(line['markerIds'] ?? const [])
      .map((id) => id.toString().trim())
      .where((id) => id.isNotEmpty)
      .join('>');
  line['renderKey'] = [
    line['id'] ?? '',
    line['displayKey'] ?? '',
    line['title'] ?? line['name'] ?? '',
    line['description'] ?? '',
    line['color'] ?? '',
    line['colorValue'] ?? '',
    line['pathHash'] ?? '',
    markerIdsKey,
    line['isVisible'] ?? true,
    line['duplicateCount'] ?? 1,
  ].join('|');
}

Map<String, dynamic> _lineToJson(String id, LineData line, {required String ownerTeam}) {
  final points = line.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
  final color = _colorToHex(Color(line.colorValue));
  final displayKey = _lineDisplayKey(line, ownerTeam: ownerTeam);
  final pathHash = _linePathHash(line);
  final lineJson = <String, dynamic>{
    'id': id,
    'lineId': line.id,
    'title': line.title,
    'description': line.description,
    'color': color,
    'colorValue': line.colorValue,
    'isVisible': line.isVisible,
    'markerIds': line.markerIds,
    'points': points,
    'displayKey': displayKey,
    'pathHash': pathHash,
    'duplicateCount': 1,
    'duplicateTeams': <String>[ownerTeam],
    'duplicateTitles': <String>[line.title],
    'duplicateVisibleStates': <String, bool>{ownerTeam: line.isVisible},
    'isDeduped': false,
    if (line.canonicalLineId != null) 'canonicalLineId': line.canonicalLineId,
    if (line.originalLineId != null) 'originalLineId': line.originalLineId,
    if (line.sourceLineId != null) 'sourceLineId': line.sourceLineId,
    if (line.parentLineId != null) 'parentLineId': line.parentLineId,
    '_baseDisplayKey': displayKey,
    '_renderPriority': _lineRenderPriority(ownerTeam: ownerTeam),
  };
  _applyLineRenderKey(lineJson);
  return lineJson;
}

Map<String, dynamic> _cleanRenderMetadata(Map<String, dynamic> item) {
  item.remove('_baseDisplayKey');
  item.remove('_renderPriority');
  return item;
}

Map<String, dynamic> _mergeMarkerDuplicateMetadata(Map<String, dynamic> existing, Map<String, dynamic> incoming) {
  final duplicateCount = ((existing['duplicateCount'] as num?)?.toInt() ?? 1) + 1;
  final duplicateTeams = _stableStringList([
    ...List<dynamic>.from(existing['duplicateTeams'] ?? const []),
    ...List<dynamic>.from(incoming['duplicateTeams'] ?? const []),
  ]);
  final duplicateGroupNames = _stableStringList([
    ...List<dynamic>.from(existing['duplicateGroupNames'] ?? const []),
    ...List<dynamic>.from(incoming['duplicateGroupNames'] ?? const []),
  ]);

  final existingPriority = (existing['_renderPriority'] as num?)?.toInt() ?? 99;
  final incomingPriority = (incoming['_renderPriority'] as num?)?.toInt() ?? 99;
  final representative = incomingPriority < existingPriority ? incoming : existing;

  representative['duplicateCount'] = duplicateCount;
  representative['duplicateTeams'] = duplicateTeams;
  representative['duplicateGroupNames'] = duplicateGroupNames;
  representative['isDeduped'] = duplicateCount > 1;
  representative['_baseDisplayKey'] = existing['_baseDisplayKey'] ?? incoming['_baseDisplayKey'] ?? representative['displayKey'];
  representative['displayKey'] = existing['displayKey'] ?? incoming['displayKey'] ?? representative['displayKey'];
  _applyMarkerRenderKey(representative);
  return representative;
}

String _cleanRenderId(dynamic value) => value?.toString().trim() ?? '';

List<String> _markerOwnRenderIds(Map<String, dynamic> marker) {
  return [
    marker['rawId'],
    marker['markerId'],
    marker['id'],
  ].map(_cleanRenderId).where((id) => id.isNotEmpty).toSet().toList();
}

List<String> _markerLinkRenderIds(Map<String, dynamic> marker) {
  return [
    marker['canonicalMarkerId'],
    marker['originalMarkerId'],
    marker['sourceMarkerId'],
    marker['parentMarkerId'],
  ].map(_cleanRenderId).where((id) => id.isNotEmpty).toSet().toList();
}

void _logKakaoDedupe(String kind, int rawCount, int renderedCount) {
  final removed = rawCount - renderedCount;
  if (removed <= 0) return;
  final key = '$rawCount:$renderedCount';
  if (kind == 'markers') {
    if (_lastKakaoMarkerDedupeLogKey == key) return;
    _lastKakaoMarkerDedupeLogKey = key;
  } else {
    if (_lastKakaoLineDedupeLogKey == key) return;
    _lastKakaoLineDedupeLogKey = key;
  }
  debugPrint('[KAKAO_DEDUPE] $kind raw=$rawCount rendered=$renderedCount removed=$removed');
}

String _chooseMarkerCanonicalId(List<Map<String, dynamic>> component) {
  final linkIds = component.expand(_markerLinkRenderIds).toSet().toList();
  if (linkIds.isNotEmpty) return linkIds.first;

  final sorted = component.toList()
    ..sort((a, b) {
      final aPriority = (a['_renderPriority'] as num?)?.toInt() ?? 99;
      final bPriority = (b['_renderPriority'] as num?)?.toInt() ?? 99;
      return aPriority.compareTo(bPriority);
    });
  final representative = sorted.first;
  return _cleanRenderId(
    representative['rawId'] ?? representative['markerId'] ?? representative['id'],
  );
}

List<Map<String, dynamic>> _dedupeMarkerJsonList(List<Map<String, dynamic>> rawMarkers) {
  if (!_dedupeMapRenderItems) return rawMarkers.map(_cleanRenderMetadata).toList();

  final parent = List<int>.generate(rawMarkers.length, (index) => index);

  int find(int index) {
    while (parent[index] != index) {
      parent[index] = parent[parent[index]];
      index = parent[index];
    }
    return index;
  }

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootB] = rootA;
  }

  final ownIdToIndexes = <String, List<int>>{};
  final linkIdToIndexes = <String, List<int>>{};

  for (var index = 0; index < rawMarkers.length; index++) {
    final marker = rawMarkers[index];
    for (final id in _markerOwnRenderIds(marker)) {
      ownIdToIndexes.putIfAbsent(id, () => <int>[]).add(index);
    }
    for (final id in _markerLinkRenderIds(marker)) {
      linkIdToIndexes.putIfAbsent(id, () => <int>[]).add(index);
    }
  }

  for (final entry in linkIdToIndexes.entries) {
    final linked = entry.value;
    for (var i = 1; i < linked.length; i++) {
      union(linked.first, linked[i]);
    }
    for (final ownIndex in ownIdToIndexes[entry.key] ?? const <int>[]) {
      union(linked.first, ownIndex);
    }
  }

  final components = <int, List<Map<String, dynamic>>>{};
  for (var index = 0; index < rawMarkers.length; index++) {
    components.putIfAbsent(find(index), () => <Map<String, dynamic>>[]).add(rawMarkers[index]);
  }

  final result = components.values.map((component) {
    final sorted = component.toList()
      ..sort((a, b) {
        final aPriority = (a['_renderPriority'] as num?)?.toInt() ?? 99;
        final bPriority = (b['_renderPriority'] as num?)?.toInt() ?? 99;
        return aPriority.compareTo(bPriority);
      });
    final representative = Map<String, dynamic>.from(sorted.first);
    final canonicalId = _chooseMarkerCanonicalId(component);
    final hasLink = component.any((marker) => _markerLinkRenderIds(marker).isNotEmpty);

    if (hasLink && canonicalId.isNotEmpty) representative['canonicalMarkerId'] ??= canonicalId;
    representative['displayKey'] = hasLink && canonicalId.isNotEmpty
        ? 'canonical:$canonicalId'
        : (representative['_baseDisplayKey'] ?? representative['displayKey'] ?? representative['id']).toString();
    representative['duplicateCount'] = component.length;
    representative['duplicateTeams'] = _stableStringList(
      component.expand((marker) => List<dynamic>.from(marker['duplicateTeams'] ?? [marker['teamName']])),
    );
    representative['duplicateGroupNames'] = _stableStringList(
      component.expand((marker) => List<dynamic>.from(marker['duplicateGroupNames'] ?? [marker['groupName']])),
    );
    representative['componentMarkerIds'] = _stableStringList(
      component.expand((marker) => [..._markerOwnRenderIds(marker), ..._markerLinkRenderIds(marker)]),
    );
    representative['isDeduped'] = component.length > 1;
    _applyMarkerRenderKey(representative);
    return representative;
  }).map(_cleanRenderMetadata).toList();

  _logKakaoDedupe('markers', rawMarkers.length, result.length);
  return result;
}

Map<String, dynamic> _mergeLineDuplicateMetadata(Map<String, dynamic> existing, Map<String, dynamic> incoming) {
  final duplicateCount = ((existing['duplicateCount'] as num?)?.toInt() ?? 1) + 1;
  final duplicateTeams = _stableStringList([
    ...List<dynamic>.from(existing['duplicateTeams'] ?? const []),
    ...List<dynamic>.from(incoming['duplicateTeams'] ?? const []),
  ]);
  final duplicateTitles = _stableStringList([
    ...List<dynamic>.from(existing['duplicateTitles'] ?? const []),
    ...List<dynamic>.from(incoming['duplicateTitles'] ?? const []),
  ]);
  final visibleStates = <String, bool>{
    ...Map<String, bool>.from(existing['duplicateVisibleStates'] ?? const <String, bool>{}),
    ...Map<String, bool>.from(incoming['duplicateVisibleStates'] ?? const <String, bool>{}),
  };

  final existingPriority = (existing['_renderPriority'] as num?)?.toInt() ?? 99;
  final incomingPriority = (incoming['_renderPriority'] as num?)?.toInt() ?? 99;
  final representative = incomingPriority < existingPriority ? incoming : existing;

  representative['duplicateCount'] = duplicateCount;
  representative['duplicateTeams'] = duplicateTeams;
  representative['duplicateTitles'] = duplicateTitles;
  representative['duplicateVisibleStates'] = visibleStates;
  representative['isDeduped'] = duplicateCount > 1;
  representative['_baseDisplayKey'] = existing['_baseDisplayKey'] ?? incoming['_baseDisplayKey'] ?? representative['displayKey'];
  representative['displayKey'] = existing['displayKey'] ?? incoming['displayKey'] ?? representative['displayKey'];
  _applyLineRenderKey(representative);
  return representative;
}

List<String> _lineOwnRenderIds(Map<String, dynamic> line) {
  return [
    line['lineId'],
    line['id'],
  ].map(_cleanRenderId).where((id) => id.isNotEmpty).toSet().toList();
}

List<String> _lineLinkRenderIds(Map<String, dynamic> line) {
  return [
    line['canonicalLineId'],
    line['originalLineId'],
    line['sourceLineId'],
    line['parentLineId'],
  ].map(_cleanRenderId).where((id) => id.isNotEmpty).toSet().toList();
}

String _chooseLineCanonicalId(List<Map<String, dynamic>> component) {
  final linkIds = component.expand(_lineLinkRenderIds).toSet().toList();
  if (linkIds.isNotEmpty) return linkIds.first;

  final sorted = component.toList()
    ..sort((a, b) {
      final aPriority = (a['_renderPriority'] as num?)?.toInt() ?? 99;
      final bPriority = (b['_renderPriority'] as num?)?.toInt() ?? 99;
      return aPriority.compareTo(bPriority);
    });
  return _cleanRenderId(sorted.first['lineId'] ?? sorted.first['id']);
}

List<Map<String, dynamic>> _dedupeLineJsonList(List<Map<String, dynamic>> rawLines) {
  if (!_dedupeMapRenderItems) return rawLines.map(_cleanRenderMetadata).toList();

  final parent = List<int>.generate(rawLines.length, (index) => index);

  int find(int index) {
    while (parent[index] != index) {
      parent[index] = parent[parent[index]];
      index = parent[index];
    }
    return index;
  }

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootB] = rootA;
  }

  final ownIdToIndexes = <String, List<int>>{};
  final linkIdToIndexes = <String, List<int>>{};

  for (var index = 0; index < rawLines.length; index++) {
    final line = rawLines[index];
    for (final id in _lineOwnRenderIds(line)) {
      ownIdToIndexes.putIfAbsent(id, () => <int>[]).add(index);
    }
    for (final id in _lineLinkRenderIds(line)) {
      linkIdToIndexes.putIfAbsent(id, () => <int>[]).add(index);
    }
  }

  for (final entry in linkIdToIndexes.entries) {
    final linked = entry.value;
    for (var i = 1; i < linked.length; i++) {
      union(linked.first, linked[i]);
    }
    for (final ownIndex in ownIdToIndexes[entry.key] ?? const <int>[]) {
      union(linked.first, ownIndex);
    }
  }

  final components = <int, List<Map<String, dynamic>>>{};
  for (var index = 0; index < rawLines.length; index++) {
    components.putIfAbsent(find(index), () => <Map<String, dynamic>>[]).add(rawLines[index]);
  }

  final result = components.values.map((component) {
    final sorted = component.toList()
      ..sort((a, b) {
        final aPriority = (a['_renderPriority'] as num?)?.toInt() ?? 99;
        final bPriority = (b['_renderPriority'] as num?)?.toInt() ?? 99;
        return aPriority.compareTo(bPriority);
      });
    final representative = Map<String, dynamic>.from(sorted.first);
    final canonicalId = _chooseLineCanonicalId(component);
    final hasLink = component.any((line) => _lineLinkRenderIds(line).isNotEmpty);

    if (hasLink && canonicalId.isNotEmpty) representative['canonicalLineId'] ??= canonicalId;
    representative['displayKey'] = hasLink && canonicalId.isNotEmpty
        ? 'canonical:$canonicalId'
        : (representative['_baseDisplayKey'] ?? representative['displayKey'] ?? representative['id']).toString();
    representative['pathHash'] = representative['pathHash'] ?? '';
    representative['duplicateCount'] = component.length;
    representative['duplicateTeams'] = _stableStringList(
      component.expand((line) => List<dynamic>.from(line['duplicateTeams'] ?? const [])),
    );
    representative['duplicateTitles'] = _stableStringList(
      component.expand((line) => List<dynamic>.from(line['duplicateTitles'] ?? const [])),
    );
    representative['duplicateVisibleStates'] = <String, bool>{
      for (final line in component)
        ...Map<String, bool>.from(line['duplicateVisibleStates'] ?? const <String, bool>{}),
    };
    representative['componentLineIds'] = _stableStringList(
      component.expand((line) => [..._lineOwnRenderIds(line), ..._lineLinkRenderIds(line)]),
    );
    representative['isDeduped'] = component.length > 1;
    _applyLineRenderKey(representative);
    return representative;
  }).map(_cleanRenderMetadata).toList();

  _logKakaoDedupe('lines', rawLines.length, result.length);
  return result;
}

List<Map<String, dynamic>> _buildMarkerJsonList({bool dedupe = true}) {
  final markers = <Map<String, dynamic>>[];

  for (var entry in _markerDataMap.entries) {
    final id = entry.key;
    final site = entry.value;
    final group = _userGroups.firstWhere(
      (g) => g.name == site.group.name,
      orElse: () => site.group,
    );

    if (group.isVisible) {
      final scope = site.canonicalMarkerId != null || site.originalMarkerId != null || site.sourceMarkerId != null || site.parentMarkerId != null ? 'received' : 'own';
      if (_verboseMapDebug) debugPrint('MARKER_RENDER markerId=$id groupName=${group.name} groupKey=${group.name} scope=$scope originalMarkerId=${site.originalMarkerId} sourceMarkerId=${site.sourceMarkerId} updateTarget=${widget.teamName}|${group.name}|${site.id}');
      markers.add(_siteToMarkerJson(id, site, group, scope: scope, teamName: widget.teamName));
    }
  }

  if (isAdmin) {
    for (var teamEntry in _allTeamsMap.entries) {
      final teamDocId = teamEntry.key;
      final team = teamEntry.value;
      if (!team.isVisible) continue;

      for (var entry in team.markers.entries) {
        final id = entry.key;
        final site = entry.value;
        final group = team.groups.firstWhere(
          (g) => g.name == site.group.name,
          orElse: () => site.group,
        );

        if (group.isVisible) {
          final scope = site.canonicalMarkerId != null || site.originalMarkerId != null || site.sourceMarkerId != null || site.parentMarkerId != null || group.name.contains('/') ? 'shared' : 'own';
          if (_verboseMapDebug) debugPrint('MARKER_RENDER markerId=${teamDocId}_$id groupName=${group.name} groupKey=${group.name} scope=$scope originalMarkerId=${site.originalMarkerId} sourceMarkerId=${site.sourceMarkerId} updateTarget=$teamDocId|${group.name}|${site.id}');
          markers.add(_siteToMarkerJson('${teamDocId}_$id', site, group, scope: scope, teamName: teamDocId));
        }
      }
    }
  }

  final result = dedupe ? _dedupeMarkerJsonList(markers) : markers.map(_cleanRenderMetadata).toList();
  if (_verboseMapDebug) {
    debugPrint('[KAKAO_DEDUPE] markers raw=${markers.length} rendered=${result.length} removed=${markers.length - result.length}');
  }
  return result;
}

bool _isValidNativeMarkerCoordinate(double lat, double lng) {
  return lat.isFinite && lng.isFinite && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

String _nativeMarkerDisplayKey(Map<String, dynamic> marker) {
  final canonicalValue = [
    marker['canonicalMarkerId'],
    marker['originalMarkerId'],
    marker['sourceMarkerId'],
    marker['parentMarkerId'],
  ].map((value) => value?.toString().trim() ?? '').firstWhere(
        (value) => value.isNotEmpty,
        orElse: () => '',
      );
  if (canonicalValue.isNotEmpty) return 'canonical:$canonicalValue';

  final teamName = marker['teamName']?.toString().trim().isNotEmpty == true
      ? marker['teamName'].toString().trim()
      : widget.teamName;
  final id = [
    marker['markerId'],
    marker['id'],
  ].map((value) => value?.toString().trim() ?? '').firstWhere(
        (value) => value.isNotEmpty,
        orElse: () => 'unknown',
      );
  return 'marker:$teamName:$id';
}

Map<String, dynamic>? _nativeMarkerDtoFromRenderMarker(Map<String, dynamic> marker) {
  final lat = (marker['lat'] as num?)?.toDouble();
  final lng = (marker['lng'] as num?)?.toDouble();
  if (lat == null || lng == null || !_isValidNativeMarkerCoordinate(lat, lng)) {
    return null;
  }

  final displayKey = _nativeMarkerDisplayKey(marker);
  final title = (marker['title'] ?? '').toString();
  final renderKey = [
    displayKey,
    lat.toStringAsFixed(6),
    lng.toStringAsFixed(6),
    title,
    marker['groupName'] ?? '',
    marker['colorValue'] ?? '',
    marker['isChecked'] ?? false,
    marker['renderKey'] ?? '',
  ].join('|');

  final renderId = (marker['id'] ?? marker['markerId'] ?? '').toString();
  final markerId = (marker['markerId'] ?? marker['id'] ?? '').toString();
  final teamName = marker['teamName']?.toString();

  return <String, dynamic>{
    'displayKey': displayKey,
    'renderKey': renderKey,
    'id': renderId,
    'markerId': markerId,
    if (teamName != null && teamName.trim().isNotEmpty) 'teamName': teamName,
    'lat': lat,
    'lng': lng,
    'title': title,
    'groupName': (marker['groupName'] ?? '').toString(),
    'colorValue': (marker['colorValue'] as num?)?.toInt() ?? Colors.blue.value,
    'isChecked': marker['isChecked'] == true,
    if (marker['canonicalMarkerId'] != null) 'canonicalMarkerId': marker['canonicalMarkerId'].toString(),
    if (marker['originalMarkerId'] != null) 'originalMarkerId': marker['originalMarkerId'].toString(),
    if (marker['sourceMarkerId'] != null) 'sourceMarkerId': marker['sourceMarkerId'].toString(),
    if (marker['parentMarkerId'] != null) 'parentMarkerId': marker['parentMarkerId'].toString(),
  };
}

List<Map<String, dynamic>> _buildNativeMarkerJsonList() {
  if (_enableNativeMarkerPerformanceTest) {
    return _buildNativeMarkerPerformanceTestJsonList(_nativeMarkerPerformanceTestCount);
  }

  final markers = <Map<String, dynamic>>[];
  for (final marker in _buildMarkerJsonList()) {
    final dto = _nativeMarkerDtoFromRenderMarker(marker);
    if (dto != null) markers.add(dto);
  }
  markers.sort((a, b) => (a['displayKey'] ?? '').toString().compareTo((b['displayKey'] ?? '').toString()));
  return markers;
}

List<Map<String, dynamic>> _buildNativeMarkerPerformanceTestJsonList(int count) {
  final safeCount = count.clamp(1, 2000);
  final markers = <Map<String, dynamic>>[];
  const centerLat = 35.1795;
  const centerLng = 129.0756;
  const columns = 40;

  for (var i = 0; i < safeCount; i++) {
    final row = i ~/ columns;
    final col = i % columns;
    final lat = centerLat + ((row - 10) * 0.0007);
    final lng = centerLng + ((col - 20) * 0.0007);
    final color = [
      Colors.red.value,
      Colors.blue.value,
      Colors.green.value,
      Colors.orange.value,
      Colors.purple.value,
    ][i % 5];
    final displayKey = 'marker:${widget.teamName}:perf_$i';
    markers.add({
      'displayKey': displayKey,
      'renderKey': '$displayKey|${lat.toStringAsFixed(6)}|${lng.toStringAsFixed(6)}|$color',
      'id': 'perf_$i',
      'lat': lat,
      'lng': lng,
      'title': 'P${i + 1}',
      'groupName': 'native-performance-test',
      'colorValue': color,
      'isChecked': false,
    });
  }
  return markers;
}

String _nativeLineDisplayKey(LineData line, String fallbackId, {required String teamName}) {
  final canonicalValue = [
    line.canonicalLineId,
    line.originalLineId,
    line.sourceLineId,
    line.parentLineId,
  ].map((value) => value?.trim() ?? '').firstWhere(
        (value) => value.isNotEmpty,
        orElse: () => '',
      );
  if (canonicalValue.isNotEmpty) return 'canonical:$canonicalValue';

  final id = line.id.trim().isNotEmpty ? line.id.trim() : fallbackId;
  return 'line:$teamName:$id';
}

bool _isNativeLineVisible(String displayKey, LineData line) {
  return _nativeLineVisibilityOverrides[displayKey] ?? line.isVisible;
}

Map<String, dynamic>? _nativeLineDtoFromLine(String id, LineData line, {required String teamName}) {
  final displayKey = _nativeLineDisplayKey(line, id, teamName: teamName);
  final isVisible = _isNativeLineVisible(displayKey, line);
  final points = <Map<String, double>>[];
  for (final point in line.points) {
    final lat = point.latitude;
    final lng = point.longitude;
    if (_isValidNativeMarkerCoordinate(lat, lng)) {
      points.add({'lat': lat, 'lng': lng});
    }
  }

  final markerIdsKey = line.markerIds
      .map((markerId) => markerId.trim())
      .where((markerId) => markerId.isNotEmpty)
      .toList()
    ..sort();
  final cached = _lastValidNativeLineJsonByDisplayKey[displayKey];
  final pointsForRender = points.length >= 2
      ? points
      : List<Map<String, double>>.from(
          (cached?['points'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((point) => {
                    'lat': (point['lat'] as num).toDouble(),
                    'lng': (point['lng'] as num).toDouble(),
                  }),
        );

  if (pointsForRender.length < 2) {
    if (_verboseMapDebug) {
      debugPrint('[LINE_RENDER] skip invalid native line without cache displayKey=$displayKey points=${points.length}');
    }
    return null;
  }

  if (points.length < 2 && cached != null && _verboseMapDebug) {
    debugPrint('[LINE_RENDER] keep cached line points displayKey=$displayKey currentPoints=${points.length}');
  }

  final pathHash = pointsForRender.map((p) => '${p['lat']!.toStringAsFixed(7)},${p['lng']!.toStringAsFixed(7)}').join('>');
  final markerIdsHash = markerIdsKey
      .join('>');
  final renderKey = [
    displayKey,
    line.title.trim(),
    line.description.trim(),
    line.colorValue,
    isVisible,
    pathHash,
    markerIdsHash,
  ].join('|');

  final dto = <String, dynamic>{
    'displayKey': displayKey,
    'renderKey': renderKey,
    'id': line.id.trim().isNotEmpty ? line.id : id,
    'title': line.title,
    'description': line.description,
    'points': pointsForRender,
    'markerIds': line.markerIds,
    'colorValue': line.colorValue,
    'isVisible': isVisible,
    if (line.canonicalLineId != null) 'canonicalLineId': line.canonicalLineId,
    if (line.originalLineId != null) 'originalLineId': line.originalLineId,
    if (line.sourceLineId != null) 'sourceLineId': line.sourceLineId,
    if (line.parentLineId != null) 'parentLineId': line.parentLineId,
  };

  _lastValidNativeLineJsonByDisplayKey[displayKey] = Map<String, dynamic>.from(dto);
  if (_verboseMapDebug) {
    debugPrint('[LINE_RENDER] line displayKey=$displayKey renderKey=$renderKey color=${line.colorValue} points=${pointsForRender.length}');
  }
  return dto;
}

List<Map<String, dynamic>> _buildNativeLineJsonList() {
  final lines = <Map<String, dynamic>>[];
  final expectedDisplayKeys = <String>{};

  void addLineDto(
    String fallbackId,
    LineData line, {
    required String teamName,
  }) {
    final displayKey = _nativeLineDisplayKey(line, fallbackId, teamName: teamName);
    expectedDisplayKeys.add(displayKey);
    final dto = _nativeLineDtoFromLine(
      fallbackId,
      line,
      teamName: teamName,
    );

    if (dto != null) {
      lines.add(dto);
    }
  }

  for (final entry in _lineDataMap.entries) {
    addLineDto(
      entry.key,
      entry.value,
      teamName: widget.teamName,
    );
  }

  if (isAdmin) {
    for (final team in _allTeamsMap.values) {
      if (!team.isVisible) continue;

      for (final entry in team.lines.entries) {
        addLineDto(
          '${team.teamName}_${entry.key}',
          entry.value,
          teamName: team.teamName,
        );
      }
    }
  }

  _lastValidNativeLineJsonByDisplayKey.removeWhere((displayKey, _) => !expectedDisplayKeys.contains(displayKey));

  final dedupedByDisplayKey = <String, Map<String, dynamic>>{};

  for (final line in lines) {
    final displayKey = (line['displayKey'] ?? '').toString().trim();
    if (displayKey.isEmpty) continue;

    dedupedByDisplayKey.putIfAbsent(
      displayKey,
      () => line,
    );
  }

  final result = dedupedByDisplayKey.values.toList()
    ..sort(
      (a, b) => (a['displayKey'] ?? '')
          .toString()
          .compareTo((b['displayKey'] ?? '').toString()),
    );

  return result;
}

List<Map<String, dynamic>> _buildLineJsonList({bool dedupe = true}) {
  final lines = <Map<String, dynamic>>[];

  for (var entry in _lineDataMap.entries) {
    final line = entry.value;
    if (line.isVisible) {
      lines.add(_lineToJson(entry.key, line, ownerTeam: widget.teamName));
    }
  }

  if (isAdmin) {
    for (var team in _allTeamsMap.values) {
      if (!team.isVisible) continue;

      for (var entry in team.lines.entries) {
        final line = entry.value;
        if (line.isVisible) {
          lines.add(_lineToJson('${team.teamName}_${line.id}', line, ownerTeam: team.teamName));
        }
      }
    }
  }

  final pointsToDraw = _isModalOpen ? _frozenFreeLinePoints : _tempFreeLinePoints;
  if (pointsToDraw.isNotEmpty) {
    final points = pointsToDraw.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    final pathHash = points.map((p) {
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      return '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    }).join('>');
    lines.add({
      'id': 'temp_free_line',
      'displayKey': 'temp:${widget.teamName}:temp_free_line',
      'pathHash': pathHash,
      'renderKey': [
        'temp_free_line',
        'temp:${widget.teamName}:temp_free_line',
        '',
        _colorToHex(Colors.redAccent),
        pathHash,
        1,
      ].join('|'),
      'duplicateCount': 1,
      'duplicateTeams': <String>[widget.teamName],
      'duplicateTitles': <String>[''],
      'duplicateVisibleStates': <String, bool>{widget.teamName: true},
      'isDeduped': false,
      'title': '',
      'description': '',
      'color': _colorToHex(Colors.redAccent),
      'isVisible': true,
      'markerIds': const <String>[],
      'points': points,
    });
  }

  final result = dedupe ? _dedupeLineJsonList(lines) : lines.map(_cleanRenderMetadata).toList();
  if (_verboseMapDebug) {
    debugPrint('[KAKAO_DEDUPE] lines raw=${lines.length} rendered=${result.length} removed=${lines.length - result.length}');
  }
  return result;
}

Future<void> _renderMarkersOnKakaoMap() async {
  final controller = _webViewController;
  if (!mounted || controller == null) return;

  try {
    final markerList = _buildMarkerJsonList()
      ..sort((a, b) => (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString()));
    final hash = markerList.map((m) => (m['renderKey'] ?? '').toString()).join('||');
    if (hash == _lastSentMarkersHash) {
      if (_verboseMapDebug) debugPrint('[KAKAO_RENDER] skipped markers hash unchanged');
      await _setMarkerMoveModeOnKakaoMap(_isMoveMode);
      return;
    }

    await controller.runJavaScript('renderMarkers(${jsonEncode(markerList)});');
    _lastSentMarkersHash = hash;
    await _setMarkerMoveModeOnKakaoMap(_isMoveMode);
  } catch (e) {
    debugPrint('renderMarkers failed: $e');
  }
}

Future<void> _renderMarkersOnNativeKakaoMap() async {
  if (!mounted || !_shouldUseNativeKakaoMap) return;

  try {
    final markerList = _buildNativeMarkerJsonList();
    final hash = markerList.map((m) => (m['renderKey'] ?? '').toString()).join('||');
    if (hash == _lastSentMarkersHash) {
      if (_verboseMapDebug) debugPrint('[NATIVE_KAKAO_RENDER] skipped markers hash unchanged');
      await _setMarkerMoveModeOnKakaoMap(_isMoveMode);
      return;
    }

    await _nativeKakaoMapCommands.invokeMethod('renderMarkers', markerList);
    _lastSentMarkersHash = hash;
    await _setMarkerMoveModeOnKakaoMap(_isMoveMode);
  } catch (e) {
    debugPrint('native renderMarkers failed: $e');
  }
}

Future<void> _renderLinesOnNativeKakaoMap() async {
  return _renderLinesOnNativeKakaoMapInternal();
}

int _nativeLineResultInt(dynamic result, String key) {
  if (result is Map) {
    final value = result[key];
    if (value is num) return value.toInt();
  }
  return 0;
}

Future<void> _renderLinesOnNativeKakaoMapInternal({bool force = false, String reason = 'line-change'}) async {
  if (!mounted || !_shouldUseNativeKakaoMap) return;

  try {
    final lineList = _buildNativeLineJsonList();
    final hasSourceLines = _lineDataMap.isNotEmpty || (isAdmin && _allTeamsMap.values.any((team) => team.isVisible && team.lines.isNotEmpty));
    if (lineList.isEmpty && hasSourceLines) {
      if (_verboseMapDebug) debugPrint('[LINE_RENDER] skip sending empty native lineList because source lines exist');
      return;
    }
    final hash = lineList.map((line) => (line['renderKey'] ?? '').toString()).join('||');
    if (!force && hash == _lastSentNativeLinesHash) {
      if (_verboseMapDebug) debugPrint('[NATIVE_KAKAO_RENDER] skipped lines hash unchanged');
      await _setShowAllLineLabelsOnKakaoMap(_showAllLineLabels);
      return;
    }

    final result = await _nativeKakaoMapCommands.invokeMethod('renderLines', lineList);
    final failed = _nativeLineResultInt(result, 'failed');
    final pending = _nativeLineResultInt(result, 'pending');
    if (failed <= 0 && pending <= 0) {
      _lastSentNativeLinesHash = hash;
      _pendingNativeLineRetryHash = null;
      _nativeLineRetryTimer?.cancel();
    } else {
      debugPrint('[LINE_RENDER] native failed=$failed pending=$pending; keep previous hash for retry result=$result');
      if (!force) {
        _scheduleNativeLineRenderRetry(hash);
      }
    }
    if (_verboseMapDebug) {
      debugPrint('[LINE_RENDER] source=${_lineDataMap.length} native=${lineList.length} hash=$hash force=$force reason=$reason result=$result');
    }
    await _setShowAllLineLabelsOnKakaoMap(_showAllLineLabels);
  } catch (e) {
    debugPrint('native renderLines failed: $e');
  }
}

void _scheduleNativeLineRenderRetry(String hash) {
  if (hash.isEmpty || _pendingNativeLineRetryHash == hash) return;
  _pendingNativeLineRetryHash = hash;
  _nativeLineRetryTimer?.cancel();
  _nativeLineRetryTimer = Timer(const Duration(milliseconds: 300), () {
    if (!mounted || _pendingNativeLineRetryHash != hash) return;
    _pendingNativeLineRetryHash = null;
    _renderLinesOnNativeKakaoMapInternal(force: true, reason: 'line-style-change-retry');
  });
}

Future<void> _renderLinesOnKakaoMap() async {
  final controller = _webViewController;
  if (!mounted || controller == null) return;

  try {
    final lineList = _buildLineJsonList()
      ..sort((a, b) => (a['displayKey'] ?? '').toString().compareTo((b['displayKey'] ?? '').toString()));
    final hash = lineList.map((l) => (l['renderKey'] ?? '').toString()).join('||');
    if (hash == _lastSentLinesHash) {
      if (_verboseMapDebug) debugPrint('[KAKAO_RENDER] skipped lines hash unchanged');
      await _setShowAllLineLabelsOnKakaoMap(_showAllLineLabels);
      return;
    }

    await controller.runJavaScript('renderLines(${jsonEncode(lineList)});');
    _lastSentLinesHash = hash;
    await _setShowAllLineLabelsOnKakaoMap(_showAllLineLabels);
  } catch (e) {
    debugPrint('renderLines failed: $e');
  }
}
  Future<void> _saveData() async {
    // 1. [로컬 저장] 기존처럼 내 폰에도 백업 (비상용)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_sKey}_g', jsonEncode(_userGroups.map((g) => g.toJson()).toList()));
    await prefs.setString('${_sKey}_m', jsonEncode(_markerDataMap.values.map((m) => m.toJson()).toList()));
    await prefs.setString('${_sKey}_l', jsonEncode(_lineDataMap.values.map((l) => l.toJson()).toList()));

    // 2. [서버 저장] 구글 Firestore에 우리 팀 데이터를 통째로 업로드
    try {
      await FirebaseFirestore.instance.collection('teams').doc(widget.teamName).set({
        'teamName': widget.teamName,
        'teamPw': widget.teamPw,
        'lastUpdated': FieldValue.serverTimestamp(), // 저장 시간 기록
        'groups': _userGroups.map((g) => g.toJson()).toList(),
        'markers': _markerDataMap.values.map((m) => m.toJson()).toList(),
        'lines': _lineDataMap.values.map((l) => l.toJson()).toList(),
      }, SetOptions(merge: true)); // 기존 데이터와 합치기(덮어쓰기 방지)
      
      debugPrint("구글 서버 동기화 완료!");
    } catch (e) {
      debugPrint("서버 저장 실패: $e");
    }
  }


Future<void> _loadData() async {
    // 1. [로컬 저장] 안전하게 불러오기
    final prefs = await SharedPreferences.getInstance();
    String? gJ = prefs.getString('${_sKey}_g');
    String? mJ = prefs.getString('${_sKey}_m');
    String? lJ = prefs.getString('${_sKey}_l');

    if (mounted) {
      setState(() {
        if (gJ != null) _userGroups.addAll((jsonDecode(gJ) as List).map((g) => MapGroup.fromJson(g)));
        if (mJ != null) { for (var item in jsonDecode(mJ)) { SiteData d = SiteData.fromJson(item); _markerDataMap[d.id] = d; } }
        if (lJ != null) { for (var item in jsonDecode(lJ)) { LineData d = LineData.fromJson(item); _lineDataMap[d.id] = d; } }
      });
    }

    // 2. [서버 동기화] 내 팀 데이터 불러오기
    _myTeamSub = FirebaseFirestore.instance
        .collection('teams')
        .doc(widget.teamName)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null && mounted) {
        // 📍 1. 데이터가 존재할 때 (수정되거나 일부 삭제되었을 때 포함)
        var data = doc.data()!;

        if (!isAdmin) {
          final storedPw = data['teamPw']?.toString() ?? '';
          if (storedPw != widget.teamPw) {
            _invalidateCurrentSession();
            return;
          }
        }

        setState(() {
          _userGroups.clear();
          if (data['groups'] != null) {
            for (var g in (data['groups'] as List)) _userGroups.add(MapGroup.fromJson(g));
          }

          _markerDataMap.clear();
          if (data['markers'] != null) {
            for (var m in (data['markers'] as List)) {
              SiteData d = SiteData.fromJson(m);
              _markerDataMap[d.id] = d;
            }
          }

          _lineDataMap.clear();
          if (data['lines'] != null) {
            for (var l in (data['lines'] as List)) {
              LineData d = LineData.fromJson(l);
              _lineDataMap[d.id] = d;
            }
          }
        });

        // 실제 마커/선 표시값이 달라진 경우에만 내부 hash 비교를 통과해 WebView로 전송됨
        _scheduleMarkerUpdate(ms: 120);
      } else if (!doc.exists && mounted) {
        if (!isAdmin) {
          _invalidateCurrentSession();
          return;
        }

        // 📍 2. 관리자가 파이어베이스에서 팀 폴더(문서)를 아예 삭제했을 때
        setState(() {
          _userGroups.clear();    // 그룹 목록 비우기
          _markerDataMap.clear(); // 마커 데이터 비우기
          _lineDataMap.clear();   // 선 데이터 비우기
        });

        // 데이터가 실제로 비워졌으므로 계산되는 hash가 달라져 지도에서도 제거됨
        _scheduleMarkerUpdate(ms: 120);

        // (선택 사항) 사용자에게 알려주기
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("관리자가 데이터를 삭제했습니다."))
        );
      }
    });

    // 3. [관리자 모드] 안전하게 불러오기 (마커 깜빡임 및 초기화 방지 적용 완료)
    if (isAdmin) {
      _allTeamsSub = FirebaseFirestore.instance.collection('teams').snapshots().listen((snapshot) {
        if (!mounted) return;

        setState(() {
          // 1. 기존 데이터를 '백업'해둡니다. (이전에 꺼뒀던 isVisible 상태를 기억하기 위함)
          Map<String, TeamData> oldMap = Map.from(_allTeamsMap);

          // 2. 맵을 비웁니다.
          _allTeamsMap.clear();

          for (var doc in snapshot.docs) {
            if (doc.id == widget.teamName) continue; // 내 팀은 제외

            var data = doc.data();

            // ⭐ [핵심 수정] 이 팀이 아까 꺼져 있었나요? (기억해둔 상태 불러오기)
            bool previousState = true;
            if (oldMap.containsKey(doc.id)) {
              previousState = oldMap[doc.id]!.isVisible;
            }

            // 3. 데이터를 다시 만듭니다 (isVisible에는 기억해둔 값 적용)
            _allTeamsMap[doc.id] = TeamData(
              teamName: data['teamName'] ?? doc.id,
              teamPw: data['teamPw'] ?? "",
              isVisible: previousState, // 👈 여기가 핵심입니다! (강제 true가 아님)
              groups: data['groups'] != null
                  ? (data['groups'] as List).map((g) => MapGroup.fromJson(g)).toList()
                  : [],
              markers: data['markers'] != null
                  ? { for (var m in (data['markers'] as List)) m['id'].toString(): SiteData.fromJson(m) }
                  : {},
              lines: data['lines'] != null
                  ? { for (var l in (data['lines'] as List)) l['id'].toString(): LineData.fromJson(l) }
                  : {},
            );
          }
        });
        _invalidateMarkerRenderHash();
        _scheduleMarkerUpdate(ms: 120);
      });
    }
  }
// ✅ [수정] 새 그룹 추가 (문구 변경: 일자 지역 + 색상 팔레트)
  void _addNewGroupDialog(VoidCallback onComplete) {
    String n = "";
    Color selectedColor = Colors.blue; // 기본값

    final List<Color> palette = [
      Colors.red, Colors.pinkAccent, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
    ];

    showDialog(
      context: context, 
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text("새 그룹 추가"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                TextField(
                  onChanged: (v) => n = v, 
                  // 요청하신 문구로 변경
                  decoration: const InputDecoration(
                    labelText: "일자 지역", 
                    hintText: "예: 2.4 부산 다대포"
                  )
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("그룹 색상 선택", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))
                ),
                const SizedBox(height: 10),
                
                // 🎨 원형 색상 팔레트
                Wrap(
                  spacing: 12, runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: palette.map((color) {
                    bool isSelected = selectedColor.value == color.value;
                    return GestureDetector(
                      onTap: () => setD(() => selectedColor = color),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.white, width: 3) : Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
                          boxShadow: isSelected ? [BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1)] : [],
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 24) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), 
            ElevatedButton(
              onPressed: () { 
                if (n.isNotEmpty) { 
                  setState(() => _userGroups.add(MapGroup(name: n, colorValue: selectedColor.value)));
                  _saveData(); 
                  Navigator.pop(c); 
                  // 자동 선택을 위한 콜백
                  Future.microtask(() => onComplete()); 
                } 
              }, 
              child: const Text("추가")
            )
          ]
        )
      )
    );
  }

// ✅ [수정] 그룹 수정 다이얼로그 (색상 팔레트 적용)
  void _showEditGroupDialog(MapGroup group) {
    String n = group.name;
    // 기존 그룹 색상 가져오기
    Color selectedColor = Color(group.colorValue); 

    // 🎨 색상 팔레트
    final List<Color> palette = [
      Colors.red, Colors.pinkAccent, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
    ];

    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("그룹 수정"), 
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                TextField(
                  controller: TextEditingController(text: n), 
                  onChanged: (v) => n = v, 
                  decoration: const InputDecoration(labelText: "그룹 이름 수정")
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("그룹 색상 변경", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))
                ),
                const SizedBox(height: 10),
                
                // 🎨 원형 색상 팔레트
                Wrap(
                  spacing: 12, runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: palette.map((color) {
                    bool isSelected = selectedColor.value == color.value;
                    return GestureDetector(
                      onTap: () => setD(() => selectedColor = color),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.white, width: 3) : Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
                          boxShadow: isSelected ? [BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1)] : [],
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 24) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), 
            ElevatedButton(
              onPressed: () async {
                final editedName = n.trim();
                if (editedName.isEmpty) return;
                final oldGroupName = group.name;
                final newColorValue = selectedColor.value;
                final sourceMarkersBeforeEdit = _markerDataMap.values
                    .where((marker) => marker.group.name == oldGroupName)
                    .toList();

                // 이름과 색상 변경 반영
                setState(() { 
                  group.name = editedName;
                  group.colorValue = newColorValue;
                  
                  // 해당 그룹에 속한 마커들도 정보 업데이트
                  _markerDataMap.forEach((k,v) { 
                    if(v.group.name == oldGroupName) {
                      v.group.name = editedName;
                      v.group.colorValue = group.colorValue;
                    }
                  }); 
                }); 

                try {
                  await _saveData();
                  if (isAdmin) {
                    await _syncEditedAdminGroupToDistributedCopies(
                      oldGroupName: oldGroupName,
                      editedGroup: group,
                      sourceMarkersBeforeEdit: sourceMarkersBeforeEdit,
                    );
                  }

                  if (!mounted) return;
                  setState(() {
                    _applyEditedAdminGroupLocally(
                      oldGroupName: oldGroupName,
                      newGroupName: editedName,
                      newColorValue: newColorValue,
                      sourceMarkersBeforeEdit: sourceMarkersBeforeEdit,
                    );
                  });

                  _invalidateMarkerRenderHash();
                  _scheduleMarkerUpdate(ms: 0);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("그룹 수정이 완료되었습니다."), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  debugPrint("관리자 그룹 동기화 실패: $e");
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("그룹 동기화 실패: $e"), backgroundColor: Colors.red),
                  );
                }
              }, 
              child: const Text("수정 완료")
            )
          ]
        )
      )
    );
  }
  
// --- [여기에 _uploadPhotos 함수를 넣으세요] ---
  Future<List<PhotoItem>> _uploadPhotos(List<PhotoItem> localPhotos, String teamName) async {
    List<PhotoItem> existing = localPhotos.where((p) => p.filePath.startsWith('http') && !p.filePath.contains("blob:")).toList();
    List<PhotoItem> newPhotos = localPhotos.where((p) => !p.filePath.startsWith('http') || p.filePath.contains("blob:")).toList();

    List<PhotoItem> uploaded = await Future.wait(
      newPhotos.asMap().entries.map((entry) async {
        int index = entry.key;
        PhotoItem photo = entry.value;

        try {
          String fileName = "${DateTime.now().millisecondsSinceEpoch}_$index.jpg";
          var ref = FirebaseStorage.instance.ref().child("teams/$teamName/$fileName");
          
          // ✅ [핵심 수정] 웹 vs 앱 업로드 방식 분기
          if (kIsWeb) {
            // 1. 웹: blob URL에서 데이터를 읽어와서 바이트(Byte)로 업로드
            var response = await http.get(Uri.parse(photo.filePath));
            var data = response.bodyBytes;
            await ref.putData(data, SettableMetadata(contentType: 'image/jpeg'));
          } else {
            // 2. 앱: 파일 경로로 업로드
            File file = File(photo.filePath);
            if (!await file.exists()) return photo;
            await ref.putFile(file);
          }
          
          String downloadUrl = await ref.getDownloadURL();
          return PhotoItem(filePath: downloadUrl, comment: photo.comment);
        } catch (e) {
          debugPrint("업로드 실패 ($index번): $e");
          return photo; 
        }
      })
    );
    return [...existing, ...uploaded];
  }

  String _formatFieldPhotoDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  String _fieldPhotoBatchId(DateTime createdAt) {
    String two(int value) => value.toString().padLeft(2, '0');
    final date = '${createdAt.year}${two(createdAt.month)}${two(createdAt.day)}';
    final time = '${two(createdAt.hour)}${two(createdAt.minute)}${two(createdAt.second)}';
    final suffix = createdAt.microsecondsSinceEpoch.toRadixString(36);
    return '${date}_${time}_$suffix';
  }

  String _fieldPhotoOriginalName(XFile source) {
    final name = source.name.trim();
    if (name.isNotEmpty) return name;
    final normalized = source.path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  String _fieldPhotoFileName(int sortIndex) {
    final setIndex = (sortIndex ~/ 3) + 1;
    final orderInSet = (sortIndex % 3) + 1;
    return '${setIndex.toString().padLeft(3, '0')}_$orderInSet.jpg';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)}MB';
  }

  String _formatDurationMs(int elapsedMs) {
    final totalSeconds = (elapsedMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes <= 0) return '$seconds초';
    return '$minutes분 ${seconds.toString().padLeft(2, '0')}초';
  }

  Future<int> _safeXFileLength(XFile file) async {
    try {
      return await file.length();
    } catch (_) {
      if (!kIsWeb && file.path.isNotEmpty) {
        final localFile = File(file.path);
        if (await localFile.exists()) return localFile.length();
      }
      return 0;
    }
  }

  Future<List<XFile>> _prepareFieldPhotos(List<XFile> images) async {
    final unique = <String, XFile>{};
    for (final image in images) {
      final size = await _safeXFileLength(image);
      final path = image.path.trim();
      final name = _fieldPhotoOriginalName(image);
      final key = path.isNotEmpty ? 'path:$path' : 'name:$name:$size';
      unique.putIfAbsent(key, () => image);
    }

    final result = unique.values.toList();
    result.sort((a, b) {
      final byName = _fieldPhotoOriginalName(a)
          .toLowerCase()
          .compareTo(_fieldPhotoOriginalName(b).toLowerCase());
      if (byName != 0) return byName;
      return a.path.compareTo(b.path);
    });
    return result;
  }

  Future<_CompressedFieldPhoto> _compressFieldPhoto(
    XFile source, {
    required String batchId,
    required String fileName,
    required int sortIndex,
    required int originalSizeBytes,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('웹에서는 임시 파일 압축을 지원하지 않습니다.');
    }

    final lowerName = _fieldPhotoOriginalName(source).toLowerCase();
    final canSkipCompress = lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg');
    if (canSkipCompress && originalSizeBytes > 0 && originalSizeBytes <= fieldPhotoSkipCompressBytes) {
      final originalFile = File(source.path);
      if (await originalFile.exists()) {
        return _CompressedFieldPhoto(
          source: source,
          file: originalFile,
          sortIndex: sortIndex,
          originalSizeBytes: originalSizeBytes,
          compressedSizeBytes: originalSizeBytes,
          isTemporary: false,
        );
      }
    }

    final tempRoot = await getTemporaryDirectory();
    final uploadDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}field_photo_zip_uploads'
      '${Platform.pathSeparator}$batchId',
    );
    await uploadDir.create(recursive: true);

    final targetPath = '${uploadDir.path}${Platform.pathSeparator}$fileName';
    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      targetPath,
      minWidth: fieldPhotoMaxDimension,
      minHeight: fieldPhotoMaxDimension,
      quality: fieldPhotoJpegQuality,
      format: CompressFormat.jpeg,
    );

    if (compressed == null) {
      throw Exception('사진 압축 결과가 없습니다.');
    }
    final compressedFile = File(compressed.path);
    return _CompressedFieldPhoto(
      source: source,
      file: compressedFile,
      sortIndex: sortIndex,
      originalSizeBytes: originalSizeBytes,
      compressedSizeBytes: await compressedFile.length(),
      isTemporary: true,
    );
  }

  Future<void> _cleanupFieldPhotoZipTempFiles(String batchId) async {
    try {
      final tempRoot = await getTemporaryDirectory();
      final tempDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}field_photo_zip_uploads'
        '${Platform.pathSeparator}$batchId',
      );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      debugPrint('[FIELD_PHOTO_TEMP_CLEANUP_DONE] batchId=$batchId');
    } catch (e) {
      debugPrint('[FIELD_PHOTO_TEMP_CLEANUP_FAILED] $e');
    }
  }

  Future<List<_PendingFieldPhotoUpload>> _loadPendingFieldPhotoUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fieldPhotoPendingUploadPrefsKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => _PendingFieldPhotoUpload.fromJson(Map<String, dynamic>.from(item)))
          .where((item) =>
              item.batchId.isNotEmpty &&
              item.zipPath.isNotEmpty &&
              item.zipStoragePath.isNotEmpty &&
              item.teamName == widget.teamName)
          .toList();
    } catch (e) {
      debugPrint('[FIELD_PHOTO_PENDING_LOAD_FAILED] $e');
      return [];
    }
  }

  Future<_PendingFieldPhotoUpload?> _latestPendingFieldPhotoUpload({
    bool includeIgnored = true,
  }) async {
    final pendingUploads = (await _loadPendingFieldPhotoUploads())
        .where((item) => includeIgnored || item.restorePromptIgnoredAtMillis <= 0)
        .toList();
    if (pendingUploads.isEmpty) return null;
    pendingUploads.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return pendingUploads.first;
  }

  Future<void> _savePendingFieldPhotoUpload(_PendingFieldPhotoUpload pending) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingUploads = await _loadPendingFieldPhotoUploads();
    pendingUploads.removeWhere((item) => item.batchId == pending.batchId);
    pendingUploads.add(pending);
    await prefs.setString(
      _fieldPhotoPendingUploadPrefsKey,
      jsonEncode(pendingUploads.map((item) => item.toJson()).toList()),
    );
    debugPrint('[FIELD_PHOTO_PENDING_SAVE] batchId=${pending.batchId} zipPath=${pending.zipPath}');
  }

  Future<void> _clearPendingFieldPhotoUpload(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingUploads = await _loadPendingFieldPhotoUploads();
    pendingUploads.removeWhere((item) => item.batchId == batchId);
    if (pendingUploads.isEmpty) {
      await prefs.remove(_fieldPhotoPendingUploadPrefsKey);
    } else {
      await prefs.setString(
        _fieldPhotoPendingUploadPrefsKey,
        jsonEncode(pendingUploads.map((item) => item.toJson()).toList()),
      );
    }
    debugPrint('[FIELD_PHOTO_PENDING_CLEAR] batchId=$batchId');
  }

  Future<void> _deletePendingFieldPhotoUpload(_PendingFieldPhotoUpload pending) async {
    await _clearPendingFieldPhotoUpload(pending.batchId);
    await _cleanupFieldPhotoZipTempFiles(pending.batchId);
  }

  bool _shouldRetryFieldZipUploadError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('network-request-failed') ||
        message.contains('unknown') ||
        message.contains('socket') ||
        message.contains('connection reset');
  }

  Future<void> _setFieldPhotoUploadWakelock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('[FIELD_PHOTO_WAKELOCK_FAILED] enabled=$enabled error=$e');
    }
  }

  int _pendingFieldPhotoSelectedCount(_PendingFieldPhotoUpload pending) {
    if (pending.selectedCount > 0) return pending.selectedCount;
    if (pending.photoCount > 0) return pending.photoCount;
    return pending.uploadedCount + pending.failedCount;
  }

  int _pendingFieldPhotoZipEntryCount(_PendingFieldPhotoUpload pending) {
    if (pending.zipEntryCount > 0) return pending.zipEntryCount;
    if (pending.uploadedCount > 0) return pending.uploadedCount;
    return pending.photoCount;
  }

  Future<int> _countFieldPhotoZipEntries(File zipFile) async {
    if (!await zipFile.exists()) {
      throw Exception('ZIP 파일 생성 실패');
    }
    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input, verify: true);
      return archive.files.where((file) => file.isFile).length;
    } finally {
      input.closeSync();
    }
  }

  Future<int> _validatedFieldPhotoZipSize(File zipFile) async {
    if (!await zipFile.exists()) {
      throw Exception('ZIP 파일 생성 실패');
    }
    final zipSizeBytes = await zipFile.length();
    if (zipSizeBytes <= 0) {
      throw Exception('ZIP 파일 크기가 0입니다.');
    }
    return zipSizeBytes;
  }

  SettableMetadata _fieldPhotoZipMetadata(_PendingFieldPhotoUpload pending) {
    final selectedCount = _pendingFieldPhotoSelectedCount(pending);
    final zipEntryCount = _pendingFieldPhotoZipEntryCount(pending);
    return SettableMetadata(
      contentType: 'application/zip',
      customMetadata: {
        'teamName': pending.teamName,
        'date': pending.date,
        'batchId': pending.batchId,
        'selectedCount': selectedCount.toString(),
        'compressedCount': pending.uploadedCount.toString(),
        'zipEntryCount': zipEntryCount.toString(),
        'zipSizeBytes': pending.zipSizeBytes.toString(),
      },
    );
  }

  Future<String> _verifyUploadedFieldPhotoZip({
    required Reference storageRef,
    required int localZipSizeBytes,
  }) async {
    final uploadedMetadata = await storageRef.getMetadata();
    final uploadedSize = uploadedMetadata.size;

    if (uploadedSize != null) {
      if (uploadedSize <= 0) {
        throw Exception('Storage 업로드 검증 실패: 업로드 크기가 0입니다.');
      }
      if (localZipSizeBytes > 0 && uploadedSize != localZipSizeBytes) {
        throw Exception('Storage 업로드 크기 불일치: 로컬 $localZipSizeBytes / 서버 $uploadedSize');
      }
    }

    final downloadUrl = await storageRef.getDownloadURL();
    if (downloadUrl.trim().isEmpty) {
      throw Exception('Storage 업로드 검증 실패: 다운로드 URL이 없습니다.');
    }
    return downloadUrl;
  }

  Map<String, dynamic> _fieldPhotoBatchPayload({
    required _PendingFieldPhotoUpload pending,
    required String downloadUrl,
    required DateTime createdAt,
    required List<_FieldPhotoFailure> failures,
  }) {
    final selectedCount = _pendingFieldPhotoSelectedCount(pending);
    final zipEntryCount = _pendingFieldPhotoZipEntryCount(pending);
    return {
      'batchId': pending.batchId,
      'teamName': pending.teamName,
      'date': pending.date,
      'uploaderTeamName': pending.teamName,
      'selectedCount': selectedCount,
      'compressedCount': pending.uploadedCount,
      'zipEntryCount': zipEntryCount,
      'photoCount': selectedCount,
      'setCount': selectedCount ~/ 3,
      'remainderCount': selectedCount % 3,
      'uploadedCount': selectedCount,
      'failedCount': 0,
      'zipStoragePath': pending.zipStoragePath,
      'storagePath': pending.zipStoragePath,
      'zipFileName': pending.zipFileName,
      'zipSizeBytes': pending.zipSizeBytes,
      'downloadUrl': downloadUrl,
      'compressedTotalBytes': pending.compressedTotalBytes,
      'originalTotalBytes': pending.originalTotalBytes,
      'storageUploaded': true,
      'firestoreSaved': true,
      'recoverable': false,
      'errorMessage': '',
      'status': 'uploaded',
      'failedFiles': failures
          .map((failure) => {
                'originalName': _fieldPhotoOriginalName(failure.source),
                'sortIndex': failure.sortIndex,
                'message': failure.message,
              })
          .toList(),
      'uploadMode': 'zip_archive',
      'maxDimension': fieldPhotoMaxDimension,
      'jpegQuality': fieldPhotoJpegQuality,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
      'deleteSuggestedAt': Timestamp.fromDate(createdAt.add(const Duration(days: 3))),
      'expiresAt': Timestamp.fromDate(createdAt.add(const Duration(days: 30))),
      'downloadedAt': null,
      'downloadedBy': null,
      'deletedAt': null,
    };
  }

  Future<void> _saveFieldPhotoBatchRecord({
    required _PendingFieldPhotoUpload pending,
    required String downloadUrl,
    required DateTime createdAt,
    required List<_FieldPhotoFailure> failures,
  }) async {
    final batchRef = FirebaseFirestore.instance.collection('photoBatches').doc(pending.batchId);
    await batchRef.set(
      _fieldPhotoBatchPayload(
        pending: pending,
        downloadUrl: downloadUrl,
        createdAt: createdAt,
        failures: failures,
      ),
      SetOptions(merge: true),
    );
    final savedBatch = await batchRef.get();
    final savedData = savedBatch.data();
    if (!savedBatch.exists || savedData == null || savedData['status'] != 'uploaded') {
      throw Exception('Firestore 저장 검증 실패');
    }
  }

  Future<bool> _tryRecoverUploadedFieldPhotoArchive(
    _PendingFieldPhotoUpload pending,
    _FieldPhotoProgress onProgress, {
    List<_FieldPhotoFailure> failures = const [],
  }) async {
    if (!(pending.storageUploaded && !pending.firestoreSaved && pending.recoverable)) {
      return false;
    }

    final storageRef = FirebaseStorage.instance.ref().child(pending.zipStoragePath);
    final selectedCount = _pendingFieldPhotoSelectedCount(pending);
    final zipEntryCount = _pendingFieldPhotoZipEntryCount(pending);
    if (selectedCount <= 0 || pending.uploadedCount != selectedCount || zipEntryCount != selectedCount) {
      return false;
    }

    try {
      onProgress(
        _FieldPhotoUploadStatus.uploading,
        selectedCount,
        selectedCount,
        0,
        '업로드 검증 중',
      );
      final downloadUrl = await _verifyUploadedFieldPhotoZip(
        storageRef: storageRef,
        localZipSizeBytes: pending.zipSizeBytes,
      );
      onProgress(
        _FieldPhotoUploadStatus.uploading,
        selectedCount,
        selectedCount,
        0,
        '사진보관함 기록 저장 중',
      );
      await _saveFieldPhotoBatchRecord(
        pending: pending.copyWith(
          zipEntryCount: zipEntryCount,
          storageUploaded: true,
          firestoreSaved: true,
          recoverable: false,
          errorMessage: '',
        ),
        downloadUrl: downloadUrl,
        createdAt: DateTime.fromMillisecondsSinceEpoch(pending.createdAtMillis),
        failures: failures,
      );
      return true;
    } catch (e) {
      debugPrint('[FIELD_PHOTO_RECOVER_FIRESTORE_FAILED] batchId=${pending.batchId} error=$e');
      await _savePendingFieldPhotoUpload(
        pending.copyWith(
          storageUploaded: true,
          firestoreSaved: false,
          recoverable: true,
          errorMessage: 'Firestore 상태 저장 실패: $e',
        ),
      );
      return false;
    }
  }

  Future<int> _putFieldPhotoZipWithRetry({
    required File zipFile,
    required Reference storageRef,
    required SettableMetadata metadata,
    required _PendingFieldPhotoUpload pending,
    required _FieldPhotoProgress onProgress,
  }) async {
    final retryDelays = [
      const Duration(seconds: 5),
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ];
    final uploadWatch = Stopwatch()..start();

    for (var attempt = 0;; attempt += 1) {
      try {
        final uploadTask = storageRef.putFile(zipFile, metadata);
        await for (final snapshot in uploadTask.snapshotEvents) {
          final totalBytes = snapshot.totalBytes;
          if (totalBytes > 0) {
            final percent = ((snapshot.bytesTransferred / totalBytes) * 100).clamp(0, 100).round();
            onProgress(
              _FieldPhotoUploadStatus.uploading,
              pending.uploadedCount + pending.failedCount,
              pending.uploadedCount,
              pending.failedCount,
              'ZIP 업로드 중: $percent%',
            );
          }
        }
        await uploadTask;
        uploadWatch.stop();
        return uploadWatch.elapsedMilliseconds;
      } catch (e) {
        if (attempt >= retryDelays.length || !_shouldRetryFieldZipUploadError(e)) {
          uploadWatch.stop();
          rethrow;
        }
        final retryAttempt = attempt + 1;
        debugPrint('[FIELD_UPLOAD_RETRY] attempt=$retryAttempt error=$e');
        onProgress(
          _FieldPhotoUploadStatus.retrying,
          pending.uploadedCount + pending.failedCount,
          pending.uploadedCount,
          pending.failedCount,
          '자동 재시도 중 ($retryAttempt/3)',
        );
        await Future.delayed(retryDelays[attempt]);
      }
    }
  }

  Future<_FieldPhotoUploadResult> _uploadPendingFieldPhotoBatch(
    _PendingFieldPhotoUpload pending,
    _FieldPhotoProgress onProgress, {
    bool manageWakelock = true,
    List<_FieldPhotoFailure> failures = const [],
  }) async {
    final totalStopwatch = Stopwatch()..start();
    var uploadElapsedMs = 0;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(pending.createdAtMillis);
    final storageRef = FirebaseStorage.instance.ref().child(pending.zipStoragePath);
    final zipFile = File(pending.zipPath);
    final selectedCount = _pendingFieldPhotoSelectedCount(pending);

    if (manageWakelock) await _setFieldPhotoUploadWakelock(true);
    try {
      if (await _tryRecoverUploadedFieldPhotoArchive(pending, onProgress, failures: failures)) {
        await _clearPendingFieldPhotoUpload(pending.batchId);
        await _cleanupFieldPhotoZipTempFiles(pending.batchId);
        totalStopwatch.stop();
        onProgress(
          _FieldPhotoUploadStatus.uploaded,
          selectedCount,
          selectedCount,
          0,
          '사진 $selectedCount장 업로드 완료',
        );
        return _FieldPhotoUploadResult(
          batchId: pending.batchId,
          selectedCount: selectedCount,
          compressedCount: pending.uploadedCount,
          zipEntryCount: _pendingFieldPhotoZipEntryCount(pending),
          uploadedCount: selectedCount,
          failedCount: 0,
          originalTotalBytes: pending.originalTotalBytes,
          compressedTotalBytes: pending.compressedTotalBytes,
          oversizedCompressedCount: pending.oversizedCompressedCount,
          elapsedMs: totalStopwatch.elapsedMilliseconds,
          compressElapsedMs: pending.compressElapsedMs,
          uploadElapsedMs: 0,
          zipSizeBytes: pending.zipSizeBytes,
          storageVerified: true,
          firestoreVerified: true,
          recoverable: false,
          errorMessage: null,
          failures: failures,
        );
      }

      if (!await zipFile.exists()) {
        throw Exception('재업로드할 ZIP 파일이 없습니다.');
      }

      final actualZipSizeBytes = await _validatedFieldPhotoZipSize(zipFile);
      final actualZipEntryCount = await _countFieldPhotoZipEntries(zipFile);
      if (selectedCount <= 0) {
        throw Exception('선택 사진 수를 확인할 수 없습니다.');
      }
      if (pending.uploadedCount != selectedCount) {
        final message = '사진 압축 수 불일치: 선택 $selectedCount장 / 압축 성공 ${pending.uploadedCount}장';
        await _savePendingFieldPhotoUpload(
          pending.copyWith(
            selectedCount: selectedCount,
            zipEntryCount: actualZipEntryCount,
            storageUploaded: false,
            firestoreSaved: false,
            recoverable: false,
            errorMessage: message,
          ),
        );
        throw Exception(message);
      }
      if (actualZipEntryCount != selectedCount) {
        final message = 'ZIP 사진 수 불일치: 선택 $selectedCount장 / ZIP $actualZipEntryCount장';
        await _savePendingFieldPhotoUpload(
          pending.copyWith(
            selectedCount: selectedCount,
            zipEntryCount: actualZipEntryCount,
            storageUploaded: false,
            firestoreSaved: false,
            recoverable: false,
            errorMessage: message,
          ),
        );
        throw Exception(message);
      }

      pending = pending.copyWith(
        selectedCount: selectedCount,
        zipEntryCount: actualZipEntryCount,
        storageUploaded: false,
        firestoreSaved: false,
        recoverable: false,
        errorMessage: '',
      );
      await _savePendingFieldPhotoUpload(pending);

      debugPrint('[FIELD_ZIP_UPLOAD_START] batchId=${pending.batchId} zipPath=${pending.zipPath}');
      onProgress(
        _FieldPhotoUploadStatus.uploading,
        selectedCount,
        pending.uploadedCount,
        0,
        'ZIP 업로드 중',
      );

      uploadElapsedMs = await _putFieldPhotoZipWithRetry(
        zipFile: zipFile,
        storageRef: storageRef,
        metadata: _fieldPhotoZipMetadata(pending),
        pending: pending,
        onProgress: onProgress,
      );

      onProgress(
        _FieldPhotoUploadStatus.uploading,
        selectedCount,
        selectedCount,
        0,
        '업로드 검증 중',
      );
      final downloadUrl = await _verifyUploadedFieldPhotoZip(
        storageRef: storageRef,
        localZipSizeBytes: actualZipSizeBytes,
      );
      pending = pending.copyWith(
        storageUploaded: true,
        firestoreSaved: false,
        recoverable: true,
        errorMessage: '',
      );
      await _savePendingFieldPhotoUpload(pending);

      debugPrint('[FIELD_ZIP_UPLOAD_DONE] batchId=${pending.batchId} uploadElapsedMs=$uploadElapsedMs');
      onProgress(
        _FieldPhotoUploadStatus.uploading,
        selectedCount,
        selectedCount,
        0,
        '사진보관함 기록 저장 중',
      );

      try {
        await _saveFieldPhotoBatchRecord(
          pending: pending.copyWith(
            storageUploaded: true,
            firestoreSaved: true,
            recoverable: false,
            errorMessage: '',
          ),
          downloadUrl: downloadUrl,
          createdAt: createdAt,
          failures: failures,
        );
        debugPrint('[FIELD_FIRESTORE_BATCH_SAVE] batchId=${pending.batchId}');
      } catch (e) {
        final message = 'Firestore 상태 저장 실패: $e';
        await _savePendingFieldPhotoUpload(
          pending.copyWith(
            storageUploaded: true,
            firestoreSaved: false,
            recoverable: true,
            errorMessage: message,
          ),
        );
        throw Exception('$message. 재시도하면 복구를 시도합니다.');
      }

      await _clearPendingFieldPhotoUpload(pending.batchId);
      await _cleanupFieldPhotoZipTempFiles(pending.batchId);
      totalStopwatch.stop();

      final averageBytes = selectedCount > 0 ? pending.compressedTotalBytes ~/ selectedCount : 0;
      debugPrint(
        '[FIELD_UPLOAD_COMPLETE] '
        'batchId=${pending.batchId} '
        'count=$selectedCount '
        'failed=0 '
        'zipBytes=${pending.zipSizeBytes} '
        'compressedBytes=${pending.compressedTotalBytes} '
        'elapsedMs=${totalStopwatch.elapsedMilliseconds} '
        'averageBytes=$averageBytes '
        'compressElapsedMs=${pending.compressElapsedMs} '
        'uploadElapsedMs=$uploadElapsedMs',
      );
      onProgress(
        _FieldPhotoUploadStatus.uploaded,
        selectedCount,
        selectedCount,
        0,
        '사진 $selectedCount장 업로드 완료',
      );

      return _FieldPhotoUploadResult(
        batchId: pending.batchId,
        selectedCount: selectedCount,
        compressedCount: pending.uploadedCount,
        zipEntryCount: actualZipEntryCount,
        uploadedCount: selectedCount,
        failedCount: 0,
        originalTotalBytes: pending.originalTotalBytes,
        compressedTotalBytes: pending.compressedTotalBytes,
        oversizedCompressedCount: pending.oversizedCompressedCount,
        elapsedMs: totalStopwatch.elapsedMilliseconds,
        compressElapsedMs: pending.compressElapsedMs,
        uploadElapsedMs: uploadElapsedMs,
        zipSizeBytes: pending.zipSizeBytes,
        storageVerified: true,
        firestoreVerified: true,
        recoverable: false,
        errorMessage: null,
        failures: failures,
      );
    } catch (e) {
      totalStopwatch.stop();
      debugPrint('[FIELD_UPLOAD_FAILED] batchId=${pending.batchId} error=$e');
      onProgress(
        _FieldPhotoUploadStatus.failed,
        selectedCount,
        pending.uploadedCount,
        pending.failedCount > 0
            ? pending.failedCount
            : (selectedCount - pending.uploadedCount).clamp(0, selectedCount).toInt(),
        e.toString(),
      );
      rethrow;
    } finally {
      if (manageWakelock) await _setFieldPhotoUploadWakelock(false);
    }
  }

  Future<_FieldPhotoUploadResult> _uploadFieldPhotoBatch(
    List<XFile> sourceImages,
    DateTime selectedDate,
    _FieldPhotoProgress onProgress,
  ) async {
    final teamName = widget.teamName;
    final createdAt = DateTime.now();
    final batchId = _fieldPhotoBatchId(createdAt);
    final dateText = _formatFieldPhotoDate(selectedDate);
    final batchRef = FirebaseFirestore.instance.collection('photoBatches').doc(batchId);
    final selectedCount = sourceImages.length;

    final tempRoot = await getTemporaryDirectory();
    final tempDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}field_photo_zip_uploads'
      '${Platform.pathSeparator}$batchId',
    );
    final failures = <_FieldPhotoFailure>[];
    var originalTotalBytes = 0;
    var compressedTotalBytes = 0;
    var oversizedCompressedCount = 0;
    var compressedCount = 0;
    var zipAddedCount = 0;
    var zipEntryCount = 0;
    var failedCount = 0;
    var compressElapsedMs = 0;
    var zipSizeBytes = 0;
    final zipFolderName = '${teamName}_$dateText';
    final zipFileName = '${teamName}_${dateText}_$batchId.zip';
    final zipFile = File('${tempDir.path}${Platform.pathSeparator}$zipFileName');
    final zipStoragePath = 'field_photo_archives/$teamName/$dateText/$zipFileName';

    void emitProgress(String phase) {
      final averageBytes = zipAddedCount > 0 ? compressedTotalBytes ~/ zipAddedCount : 0;
      final avgText = averageBytes > 0 ? ' / 평균 ${_formatBytes(averageBytes)}' : '';
      onProgress(_FieldPhotoUploadStatus.compressing, compressedCount, zipAddedCount, failedCount, '$phase$avgText');
    }

    await _setFieldPhotoUploadWakelock(true);
    try {
      await tempDir.create(recursive: true);
      final zipEncoder = ZipFileEncoder();
      zipEncoder.create(zipFile.path, level: ZipFileEncoder.STORE);
      try {
        for (var i = 0; i < sourceImages.length; i += 1) {
          final source = sourceImages[i];
          final fileName = _fieldPhotoFileName(i);
          try {
            final originalBytes = await _safeXFileLength(source);
            originalTotalBytes += originalBytes;

            final compressWatch = Stopwatch()..start();
            final compressedPhoto = await _compressFieldPhoto(
              source,
              batchId: batchId,
              fileName: fileName,
              sortIndex: i,
              originalSizeBytes: originalBytes,
            );
            compressWatch.stop();
            compressElapsedMs += compressWatch.elapsedMilliseconds;

            compressedTotalBytes += compressedPhoto.compressedSizeBytes;
            if (compressedPhoto.compressedSizeBytes > 2 * 1024 * 1024) {
              oversizedCompressedCount += 1;
            }

            compressedCount += 1;
            emitProgress('사진 압축 중 $compressedCount/$selectedCount');

            await zipEncoder.addFile(compressedPhoto.file, '$zipFolderName/$fileName', ZipFileEncoder.STORE);
            zipAddedCount += 1;
            emitProgress('ZIP 생성 중');

            if (compressedPhoto.isTemporary && await compressedPhoto.file.exists()) {
              await compressedPhoto.file.delete();
            }
          } catch (e) {
            failedCount += 1;
            failures.add(_FieldPhotoFailure(source: source, sortIndex: i, message: 'ZIP 준비 실패: $e'));
            emitProgress('ZIP 준비 실패: $failedCount');
          }
        }
      } finally {
        await zipEncoder.close();
      }

      zipSizeBytes = await _validatedFieldPhotoZipSize(zipFile);
      zipEntryCount = await _countFieldPhotoZipEntries(zipFile);
      final pendingUpload = _PendingFieldPhotoUpload(
        batchId: batchId,
        zipPath: zipFile.path,
        zipStoragePath: zipStoragePath,
        zipFileName: zipFileName,
        teamName: teamName,
        date: dateText,
        createdAtMillis: createdAt.millisecondsSinceEpoch,
        photoCount: selectedCount,
        uploadedCount: zipAddedCount,
        failedCount: failedCount,
        originalTotalBytes: originalTotalBytes,
        compressedTotalBytes: compressedTotalBytes,
        oversizedCompressedCount: oversizedCompressedCount,
        compressElapsedMs: compressElapsedMs,
        zipSizeBytes: zipSizeBytes,
        selectedCount: selectedCount,
        zipEntryCount: zipEntryCount,
      );
      await _savePendingFieldPhotoUpload(pendingUpload);

      if (compressedCount != selectedCount) {
        final message = '사진 압축 수 불일치: 선택 $selectedCount장 / 압축 성공 $compressedCount장';
        await _savePendingFieldPhotoUpload(
          pendingUpload.copyWith(
            storageUploaded: false,
            firestoreSaved: false,
            recoverable: false,
            errorMessage: message,
          ),
        );
        throw Exception(message);
      }

      if (zipEntryCount != selectedCount) {
        final message = 'ZIP 사진 수 불일치: 선택 $selectedCount장 / ZIP $zipEntryCount장';
        await _savePendingFieldPhotoUpload(
          pendingUpload.copyWith(
            storageUploaded: false,
            firestoreSaved: false,
            recoverable: false,
            errorMessage: message,
          ),
        );
        throw Exception(message);
      }

      return await _uploadPendingFieldPhotoBatch(
        pendingUpload,
        onProgress,
        manageWakelock: false,
        failures: failures,
      );
    } catch (e) {
      try {
        final pendingUploads = await _loadPendingFieldPhotoUploads();
        _PendingFieldPhotoUpload? pending;
        for (final item in pendingUploads) {
          if (item.batchId == batchId) {
            pending = item;
            break;
          }
        }
        if (!(pending?.storageUploaded == true && pending?.recoverable == true)) {
          await batchRef.set({
            'batchId': batchId,
            'teamName': teamName,
            'date': dateText,
            'uploaderTeamName': teamName,
            'selectedCount': selectedCount,
            'compressedCount': compressedCount,
            'zipEntryCount': zipEntryCount,
            'photoCount': selectedCount,
            'uploadedCount': 0,
            'failedCount': selectedCount - compressedCount,
            'setCount': selectedCount ~/ 3,
            'remainderCount': selectedCount % 3,
            'zipStoragePath': zipStoragePath,
            'zipFileName': zipFileName,
            'zipSizeBytes': zipSizeBytes,
            'compressedTotalBytes': compressedTotalBytes,
            'originalTotalBytes': originalTotalBytes,
            'storageUploaded': false,
            'firestoreSaved': false,
            'recoverable': false,
            'status': 'failed',
            'errorMessage': e.toString(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'deleteSuggestedAt': Timestamp.fromDate(createdAt.add(const Duration(days: 3))),
            'expiresAt': Timestamp.fromDate(createdAt.add(const Duration(days: 30))),
            'downloadedAt': null,
            'downloadedBy': null,
            'deletedAt': null,
          }, SetOptions(merge: true));
        }
      } catch (_) {}
      debugPrint('[FIELD_PHOTO_UPLOAD_FAILED] failed=${failedCount + 1} error=$e');
      rethrow;
    } finally {
      await _setFieldPhotoUploadWakelock(false);
    }
  }

  Future<void> _restorePendingFieldPhotoUploadIfNeeded() async {
    if (!canManageTeamData || !mounted) return;
    final pending = await _latestPendingFieldPhotoUpload(includeIgnored: false);
    if (pending == null || !mounted) return;
    if (pending.restorePromptIgnoredAtMillis > 0) {
      return;
    }
    final localZipExists = await File(pending.zipPath).exists();
    if (!localZipExists && !(pending.storageUploaded && pending.recoverable)) {
      await _clearPendingFieldPhotoUpload(pending.batchId);
      return;
    }

    final shouldRetry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('미완료 업로드 발견'),
        content: Text(
          '미완료 업로드 1건 발견\n'
          '${pending.date} / ZIP ${_formatBytes(pending.zipSizeBytes)}\n\n'
          '재업로드하시겠습니까?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('무시')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('재업로드')),
        ],
      ),
    );

    if (shouldRetry == false) {
      final ignored = pending.copyWith(
        restorePromptIgnoredAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _savePendingFieldPhotoUpload(ignored);
      return;
    }

    if (shouldRetry == true && mounted) {
      final retryPending = pending.copyWith(restorePromptIgnoredAtMillis: 0);
      await _savePendingFieldPhotoUpload(retryPending);
      _showFieldPhotoUploadSheet(initialPendingUpload: retryPending, autoRetry: true);
    }
  }

  Future<bool> _confirmCancelFieldPhotoUpload() async {
    final cancel = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('사진 업로드를 취소할까요?'),
          content: const Text(
            '선택한 사진은 아직 서버에 업로드되지 않았습니다.\n'
            '취소하면 다시 사진을 선택해야 할 수 있습니다.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 업로드')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('업로드 취소')),
          ],
        ),
      ),
    );
    return cancel == true;
  }

  Widget _buildFieldPhotoUploadCountLine(String label, int value, String unit) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: '$value',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          TextSpan(text: unit),
        ],
      ),
    );
  }

  Future<void> _showFieldPhotoUploadingCannotCloseDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('업로드 중입니다'),
        content: const Text(
          '현재 사진 업로드가 진행 중입니다.\n'
          '완료될 때까지 기다려 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFieldPhotoUploadCompletedDialog({
    required int photoCount,
  }) async {
    if (!mounted) return;

    final manholeCount = photoCount ~/ 3;
    final remainCount = photoCount % 3;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('업로드가 완료되었습니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldPhotoUploadCountLine('사진장수', photoCount, '장'),
            const SizedBox(height: 6),
            _buildFieldPhotoUploadCountLine('맨홀개수', manholeCount, '개'),
            if (remainCount > 0) ...[
              const SizedBox(height: 6),
              _buildFieldPhotoUploadCountLine('남는사진', remainCount, '장'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmFieldPhotoUploadIfNeeded(int count, int estimatedBytes) async {
    final warnings = <String>[];
    if (count % 3 != 0) {
      warnings.add('사진 수가 3의 배수가 아닙니다.');
    }
    if (count >= 300) {
      warnings.add('사진이 많습니다. 업로드 중 앱을 종료하지 마세요.');
    }
    if (estimatedBytes > 500 * 1024 * 1024) {
      warnings.add('선택한 원본 사진 총 용량이 500MB를 초과합니다.');
    }
    warnings.add('사진이 많을 경우 업로드 중 임시 저장공간이 필요합니다.');
    warnings.add('업로드 성공 검증 후 ZIP 파일과 임시 사진은 앱이 자동 삭제합니다.');
    if (warnings.isEmpty) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('현장 사진 업로드 확인'),
          content: Text('${warnings.join('\n')}\n\n그래도 업로드할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('업로드')),
          ],
        ),
      ),
    );
    return confirmed == true;
  }

  String _fieldPhotoUploadStatusText(_FieldPhotoUploadStatus status) {
    switch (status) {
      case _FieldPhotoUploadStatus.compressing:
        return '사진 압축 / ZIP 생성 중...';
      case _FieldPhotoUploadStatus.uploading:
        return 'ZIP 업로드 / 검증 중...';
      case _FieldPhotoUploadStatus.retrying:
        return '자동 재시도 중...';
      case _FieldPhotoUploadStatus.uploaded:
        return '업로드 완료';
      case _FieldPhotoUploadStatus.failed:
        return '업로드 실패';
      case _FieldPhotoUploadStatus.idle:
        return '대기 중';
    }
  }

  void _showFieldPhotoUploadSheet({
    _PendingFieldPhotoUpload? initialPendingUpload,
    bool autoRetry = false,
  }) {
    if (!canManageTeamData) return;

    DateTime selectedDate = DateTime.now();
    List<XFile> selectedImages = [];
    List<_FieldPhotoFailure> failures = [];
    _PendingFieldPhotoUpload? pendingUpload = initialPendingUpload;
    var estimatedBytes = 0;
    var compressedCount = pendingUpload?.uploadedCount ?? 0;
    var uploadedCount = pendingUpload?.uploadedCount ?? 0;
    var failedCount = pendingUpload?.failedCount ?? 0;
    var uploading = false;
    var completed = false;
    var photoDetailsLoading = false;
    var photoSelectionSequence = 0;
    var uploadStatus = pendingUpload == null ? _FieldPhotoUploadStatus.idle : _FieldPhotoUploadStatus.failed;
    var autoRetryStarted = false;
    var pendingLoadStarted = false;
    var message = pendingUpload == null
        ? '갤러리에서 현장 사진을 선택하세요.'
        : '업로드 실패\n재업로드 또는 삭제를 선택하세요.';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void applyUploadResult(_FieldPhotoUploadResult result) {
            uploading = false;
            completed = true;
            uploadStatus = _FieldPhotoUploadStatus.uploaded;
            pendingUpload = null;
            failures = result.failures;
            compressedCount = result.uploadedCount + result.failedCount;
            uploadedCount = result.uploadedCount;
            failedCount = result.failedCount;
            final warnings = <String>[];
            if (result.oversizedCompressedCount > 0) {
              warnings.add('2MB 초과 ${result.oversizedCompressedCount}장');
            }
            if (result.compressedTotalBytes > 500 * 1024 * 1024) {
              warnings.add('압축 후 총 500MB 초과');
            }
            final warningText = warnings.isEmpty ? '' : ' (${warnings.join(', ')})';
            final avgBytes = result.uploadedCount > 0 ? result.compressedTotalBytes ~/ result.uploadedCount : 0;
            final setCount = result.selectedCount ~/ 3;
            final remainderCount = result.selectedCount % 3;
            final setText = remainderCount == 0 ? '$setCount개' : '$setCount개 + 남는 사진 $remainderCount장';
            message = '사진 ${result.selectedCount}장 업로드 완료 / 세트 $setText / ZIP ${_formatBytes(result.zipSizeBytes)} / 평균 ${_formatBytes(avgBytes)} / ${_formatDurationMs(result.elapsedMs)} / 임시 파일 자동 삭제 완료$warningText';
            if (result.failedCount == 0) selectedImages = [];
          }

          Future<void> finishUploadSuccess(_FieldPhotoUploadResult result) async {
            setSheet(() => applyUploadResult(result));
            if (ctx.mounted) Navigator.pop(ctx);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _showFieldPhotoUploadCompletedDialog(photoCount: result.selectedCount);
            });
          }

          Future<void> retryPendingUpload() async {
            var retryTarget = pendingUpload;
            if (retryTarget == null || uploading) return;
            if (retryTarget.restorePromptIgnoredAtMillis > 0) {
              retryTarget = retryTarget.copyWith(restorePromptIgnoredAtMillis: 0);
              await _savePendingFieldPhotoUpload(retryTarget);
              pendingUpload = retryTarget;
            }
            final retryPending = retryTarget;
            setSheet(() {
              uploading = true;
              completed = false;
              uploadStatus = _FieldPhotoUploadStatus.uploading;
              compressedCount = retryPending.uploadedCount + retryPending.failedCount;
              uploadedCount = retryPending.uploadedCount;
              failedCount = retryPending.failedCount;
              message = 'ZIP 업로드 중';
            });

            try {
              final result = await _uploadPendingFieldPhotoBatch(
                retryPending,
                (nextStatus, nextCompressedCount, nextUploadedCount, nextFailedCount, nextMessage) {
                  if (!mounted) return;
                  setSheet(() {
                    uploadStatus = nextStatus;
                    compressedCount = nextCompressedCount;
                    uploadedCount = nextUploadedCount;
                    failedCount = nextFailedCount;
                    message = nextMessage;
                  });
                },
              );
              await finishUploadSuccess(result);
            } catch (e) {
              setSheet(() {
                uploading = false;
                completed = false;
                uploadStatus = _FieldPhotoUploadStatus.failed;
                pendingUpload = retryPending;
                failedCount = retryPending.failedCount > 0 ? retryPending.failedCount : retryPending.photoCount;
                message = '업로드 실패\n재업로드 또는 삭제를 선택하세요. ($e)';
              });
            }
          }

          Future<void> deletePendingUpload() async {
            final deleteTarget = pendingUpload;
            if (deleteTarget == null || uploading) return;
            await _deletePendingFieldPhotoUpload(deleteTarget);
            setSheet(() {
              pendingUpload = null;
              completed = false;
              uploadStatus = _FieldPhotoUploadStatus.idle;
              compressedCount = 0;
              uploadedCount = 0;
              failedCount = 0;
              message = '보류 중인 ZIP 파일을 삭제했습니다.';
              photoDetailsLoading = false;
            });
          }

          Future<void> runUpload(List<XFile> uploadTargets) async {
            if (uploadTargets.isEmpty || uploading) return;
            final confirmed = await _confirmFieldPhotoUploadIfNeeded(uploadTargets.length, estimatedBytes);
            if (!confirmed) {
              _showSnack('사진 업로드가 취소되었습니다.');
              return;
            }

            setSheet(() {
              uploading = true;
              completed = false;
              compressedCount = 0;
              uploadedCount = 0;
              failedCount = 0;
              failures = [];
              pendingUpload = null;
              photoDetailsLoading = false;
              uploadStatus = _FieldPhotoUploadStatus.compressing;
              message = '업로드 준비 중...';
            });

            try {
              final result = await _uploadFieldPhotoBatch(
                uploadTargets,
                selectedDate,
                (nextStatus, nextCompressedCount, nextUploadedCount, nextFailedCount, nextMessage) {
                  if (!mounted) return;
                  setSheet(() {
                    uploadStatus = nextStatus;
                    compressedCount = nextCompressedCount;
                    uploadedCount = nextUploadedCount;
                    failedCount = nextFailedCount;
                    message = nextMessage;
                  });
                },
              );
              await finishUploadSuccess(result);
            } catch (e) {
              final latestPending = await _latestPendingFieldPhotoUpload();
              setSheet(() {
                uploading = false;
                completed = false;
                uploadStatus = _FieldPhotoUploadStatus.failed;
                pendingUpload = latestPending;
                failedCount = latestPending?.failedCount ?? uploadTargets.length;
                message = '업로드 실패\n재업로드 또는 삭제를 선택하세요. ($e)';
              });
            }
          }

          if (autoRetry && pendingUpload != null && !autoRetryStarted) {
            autoRetryStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) retryPendingUpload();
            });
          }

          if (!autoRetry && initialPendingUpload == null && pendingUpload == null && !pendingLoadStarted) {
            pendingLoadStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final latestPending = await _latestPendingFieldPhotoUpload();
              if (!mounted || !ctx.mounted || latestPending == null) return;
              if (!await File(latestPending.zipPath).exists() &&
                  !(latestPending.storageUploaded && latestPending.recoverable)) {
                await _clearPendingFieldPhotoUpload(latestPending.batchId);
                return;
              }
              if (!mounted || !ctx.mounted) return;
              setSheet(() {
                pendingUpload = latestPending;
                compressedCount = latestPending.uploadedCount + latestPending.failedCount;
                uploadedCount = latestPending.uploadedCount;
                failedCount = latestPending.failedCount;
                uploadStatus = _FieldPhotoUploadStatus.failed;
                message = '업로드 실패\n재업로드 또는 삭제를 선택하세요.';
              });
            });
          }

          final photoCount = selectedImages.length;
          final displayPhotoCount = pendingUpload?.photoCount ?? photoCount;
          final setCount = displayPhotoCount ~/ 3;
          final remainderCount = displayPhotoCount % 3;
          final dateText = _formatFieldPhotoDate(selectedDate);
          final expectedZipName = pendingUpload?.zipFileName ?? '${widget.teamName}_${dateText}_업로드시각.zip';

          Future<void> requestCloseSheet() async {
            if (uploading) {
              await _showFieldPhotoUploadingCannotCloseDialog();
              return;
            }
            if (completed) {
              if (ctx.mounted) Navigator.pop(ctx);
              return;
            }
            final cancel = await _confirmCancelFieldPhotoUpload();
            if (!cancel) return;
            if (ctx.mounted) Navigator.pop(ctx);
            _showSnack('사진 업로드가 취소되었습니다.');
          }

          return WillPopScope(
            onWillPop: () async {
              if (uploading) {
                await _showFieldPhotoUploadingCannotCloseDialog();
              }
              return false;
            },
            child: PointerInterceptor(
              child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.86),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('사진 ZIP 업로드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      '선택한 사진을 팀명_날짜 폴더가 들어있는 ZIP 파일 1개로 묶어 업로드합니다.\n'
                      '웹관리자에서 ZIP 파일을 다운로드해 압축을 풀면 사진을 바로 확인할 수 있습니다.\n'
                      '업로드 성공 후 ZIP 파일은 자동 삭제하고, 실패 시 재업로드를 위해 보존합니다.',
                      style: TextStyle(color: Colors.black87, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text('날짜: ${_formatFieldPhotoDate(selectedDate)}'),
                      trailing: TextButton(
                        onPressed: (uploading || pendingUpload != null)
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setSheet(() => selectedDate = picked);
                                }
                              },
                        child: const Text('변경'),
                      ),
                    ),
                    Text('팀명: ${widget.teamName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      '빠른 업로드 모드: 긴 변 ${fieldPhotoMaxDimension}px / 품질 $fieldPhotoJpegQuality',
                      style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                        onPressed: (uploading || pendingUpload != null)
                            ? null
                            : () async {
                              final picked = await _picker.pickMultiImage(imageQuality: 100);
                              if (picked.isEmpty) {
                                _showSnack('선택된 사진이 없습니다.');
                                return;
                              }
                              final selectionSequence = ++photoSelectionSequence;
                              final immediateSelection = picked.length > 300
                                  ? picked.take(300).toList()
                                  : List<XFile>.from(picked);
                              setSheet(() {
                                selectedImages = immediateSelection;
                                failures = [];
                                estimatedBytes = 0;
                                compressedCount = 0;
                                uploadedCount = 0;
                                failedCount = 0;
                                pendingUpload = null;
                                photoDetailsLoading = true;
                                uploadStatus = _FieldPhotoUploadStatus.idle;
                                message = '사진 정보를 확인 중입니다...';
                              });

                              try {
                                final prepared = await _prepareFieldPhotos(picked);
                                var limited = prepared;
                                var nextMessage = '사진 선택 완료';
                                if (prepared.length > 300) {
                                  limited = prepared.take(300).toList();
                                  nextMessage = '최대 300장까지만 선택됩니다.';
                                }

                                var totalBytes = 0;
                                for (final image in limited) {
                                  totalBytes += await _safeXFileLength(image);
                                }

                                if (!mounted || !ctx.mounted || selectionSequence != photoSelectionSequence) return;
                                setSheet(() {
                                  selectedImages = limited;
                                  estimatedBytes = totalBytes;
                                  photoDetailsLoading = false;
                                  message = nextMessage;
                                });
                              } catch (e) {
                                if (!mounted || !ctx.mounted || selectionSequence != photoSelectionSequence) return;
                                setSheet(() {
                                  photoDetailsLoading = false;
                                  message = '사진 정보 확인 중 오류가 발생했습니다. 다시 선택해 주세요. ($e)';
                                });
                              }
                            },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('갤러리에서 사진 선택'),
                    ),
                    const SizedBox(height: 14),
                    _buildFieldPhotoUploadCountLine('선택사진', displayPhotoCount, '장'),
                    _buildFieldPhotoUploadCountLine('작업세트', setCount, '개'),
                    _buildFieldPhotoUploadCountLine('남는사진', remainderCount, '장'),
                    if (photoDetailsLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('사진 정보를 확인 중입니다...', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                      ),
                    Text('예상 ZIP 이름: $expectedZipName'),
                    Text('선택 원본 용량: ${_formatBytes(pendingUpload?.originalTotalBytes ?? estimatedBytes)}'),
                    Text('예상 임시 필요공간: 최종 ZIP 용량의 약 2배', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                    const Text('임시 파일 자동 삭제: 업로드 성공 검증 후 정리 / 실패 시 ZIP 보존', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                    if (remainderCount != 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('사진 수가 3의 배수가 아닙니다. 업로드 전 확인이 필요합니다.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                      ),
                    if (displayPhotoCount >= 90)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('하루 한 팀 권장량 90장 이상입니다. 업로드 중 앱을 종료하지 마세요.', style: TextStyle(color: Colors.deepOrange)),
                      ),
                    const SizedBox(height: 12),
                    if (uploading || compressedCount > 0 || uploadedCount > 0 || failedCount > 0) ...[
                      Text('상태: ${_fieldPhotoUploadStatusText(uploadStatus)}'),
                      Text('압축 중: $compressedCount / $displayPhotoCount'),
                      Text('업로드 중: $uploadedCount / $displayPhotoCount'),
                      Text('실패: $failedCount'),
                      const SizedBox(height: 8),
                    ],
                    Text(message, style: TextStyle(color: uploadStatus == _FieldPhotoUploadStatus.failed ? Colors.red : Colors.grey.shade700)),
                    if (failures.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('실패 사진', style: TextStyle(fontWeight: FontWeight.bold)),
                      ...failures.take(5).map((failure) => Text(
                            '${_fieldPhotoOriginalName(failure.source)} - ${failure.message}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          )),
                      if (failures.length > 5) Text('외 ${failures.length - 5}장'),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: requestCloseSheet,
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (pendingUpload != null) ...[
                          Expanded(
                            child: ElevatedButton(
                              onPressed: uploading ? null : retryPendingUpload,
                              child: const Text('재업로드'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: uploading ? null : deletePendingUpload,
                              child: const Text('삭제'),
                            ),
                          ),
                        ] else if (failures.isNotEmpty)
                          Expanded(
                            child: ElevatedButton(
                              onPressed: uploading ? null : () => runUpload(failures.map((failure) => failure.source).toList()),
                              child: const Text('실패 재시도'),
                            ),
                          )
                        else
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (!uploading && !photoDetailsLoading && selectedImages.isNotEmpty) ? () => runUpload(selectedImages) : null,
                              child: const Text('업로드'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  // ✅ [추가] 관리자용 팀명(폴더명) 수정 함수
  void _editTeamNameDialog(String oldTeamName) {
    if (!canUseAdminTools) return;

    TextEditingController nameCtrl = TextEditingController(text: oldTeamName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("팀명(폴더명) 수정"),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "새 팀 이름")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              String newName = nameCtrl.text.trim();
              if (newName.isEmpty || newName == oldTeamName) return;

              // Firestore는 문서 ID를 바꿀 수 없으므로 [복사 후 삭제] 방식 사용
              var doc = await FirebaseFirestore.instance.collection('teams').doc(oldTeamName).get();
              if (doc.exists) {
                var data = doc.data()!;
                data['teamName'] = newName;
                await FirebaseFirestore.instance.collection('teams').doc(newName).set(data);
                await FirebaseFirestore.instance.collection('teams').doc(oldTeamName).delete();
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("수정 완료"),
          )
        ],
      ),
    );
  }

  // ✅ [수정] 관리자용 팀 폴더 전체 삭제 함수 (즉시 반영)
  void _deleteTeamDialog(String teamName) {
    if (!canUseAdminTools) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("팀 삭제 확인"),
        content: Text("'$teamName' 팀의 모든 데이터가 삭제됩니다. 정말 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx); // 팝업 닫기

              // 1. ✅ [핵심] 화면에서 먼저 즉시 지웁니다 (눈속임이지만 사용자 경험엔 필수)
              setState(() {
                _allTeamsMap.remove(teamName);
              });
              _scheduleMarkerUpdate(); // 지도에서도 마커 제거

              // 2. 그 다음 실제 서버 삭제 수행
              try {
                await FirebaseFirestore.instance.collection('teams').doc(teamName).delete();
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("'$teamName' 팀이 삭제되었습니다."))
                   );
                }
              } catch (e) {
                // 만약 에러나면 다시 불러오게 할 수도 있지만, 보통은 그냥 둡니다.
                debugPrint("팀 삭제 실패: $e");
              }
            },
            child: const Text("폴더 삭제", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  int _markerTitleNumber(String? title) {
    final match = RegExp(r'\d+').firstMatch(title ?? '');
    return match == null ? 1 << 30 : int.parse(match.group(0)!);
  }

  String _nextMarkerTitleForGroup(String groupName, {String? excludeMarkerId}) {
    int maxNumber = 0;
    final groupMarkers = _markerDataMap.values.where((m) => m.group.name == groupName && m.id != excludeMarkerId);

    for (var m in groupMarkers) {
      final match = RegExp(r'\d+').firstMatch(m.title);
      if (match != null) {
        final number = int.parse(match.group(0)!);
        if (number > maxNumber) maxNumber = number;
      }
    }

    return (maxNumber + 1).toString();
  }

  String? _defaultMarkerGroupName() {
    if (isAdmin && _quickGroupMode > 0 && _quickSelectedGroupName != null && _userGroups.any((g) => g.name == _quickSelectedGroupName)) {
      return _quickSelectedGroupName;
    }
    if (_lastSelectedGroupName != null && _userGroups.any((g) => g.name == _lastSelectedGroupName)) {
      return _lastSelectedGroupName;
    }
    return _userGroups.isNotEmpty ? _userGroups.first.name : null;
  }

  void _setQuickSelectedGroupName(String groupName) {
    _quickSelectedGroupName = groupName;
    _quickGroupMode = 1;
    _lastSelectedGroupName = groupName;
  }

  void _cycleQuickGroupMode(String groupName) {
    if (_quickSelectedGroupName != groupName || _quickGroupMode == 0) {
      _quickSelectedGroupName = groupName;
      _quickGroupMode = 1;
      _lastSelectedGroupName = groupName;
      return;
    }

    if (_quickGroupMode == 1) {
      _quickGroupMode = 2;
      _lastSelectedGroupName = groupName;
      return;
    }

    _quickSelectedGroupName = null;
    _quickGroupMode = 0;
  }

    bool get _canQuickSlotCreateMarker {
    return isAdmin &&
        _isAdminQuickSlotsVisible &&
        _quickGroupMode == 2 &&
        _quickSelectedGroupName != null &&
        _userGroups.any((g) => g.name == _quickSelectedGroupName) &&
        !_isLineMode &&
        !_isFreeLineMode &&
        !_isLineDeleteMode;
  }

  Future<void> _quickCreateMarkerAt(LatLng point) async {
    final groupName = _quickSelectedGroupName;
    if (groupName == null) return;

    final group = _userGroups.firstWhere((g) => g.name == groupName);
    final address = await _getKoreanAddressOrNull(point.latitude, point.longitude);
    if (!_isValidMarkerAddress(address)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주소를 찾지 못해 마커를 생성하지 않았습니다. 다시 시도해 주세요.')),
        );
      }
      return;
    }

    final marker = SiteData(
      id: DateTime.now().toString(),
      lat: point.latitude,
      lng: point.longitude,
      title: _nextMarkerTitleForGroup(groupName),
      description: "",
      address: address!,
      group: group,
      photos: const [],
    );

    setState(() {
      _lastSelectedGroupName = groupName;
      _markerDataMap[marker.id] = marker;
    });

    await _saveData();
    _scheduleMarkerUpdate(ms: 0);

    if (_isOriginalMarkerForSharedSync(marker)) {
      await _appendNewMarkerToSharedGroups(
        sourceTeamName: widget.teamName,
        marker: marker,
      );
    }

    if (_spreadsheetEnabled) {
      await _uploadToSpreadsheet(marker);
    }
  }

  Set<String> _renumberGroupNames(Iterable<String?> groupNames) {
    return groupNames
        .where((name) => name != null && name.isNotEmpty)
        .map((name) => name!)
        .toSet();
  }

  void _renumberOwnMarkersForGroups(Iterable<String?> groupNames) {
    for (final groupName in _renumberGroupNames(groupNames)) {
      final entries = _markerDataMap.entries.where((entry) => entry.value.group.name == groupName).toList();
      entries.sort((a, b) {
        final numberCompare = _markerTitleNumber(a.value.title).compareTo(_markerTitleNumber(b.value.title));
        if (numberCompare != 0) return numberCompare;
        return a.key.compareTo(b.key);
      });

      for (var i = 0; i < entries.length; i++) {
        entries[i].value.title = '${i + 1}';
      }
    }
  }

  void _renumberMarkerJsonListForGroups(List<dynamic> markers, Iterable<String?> groupNames) {
    for (final groupName in _renumberGroupNames(groupNames)) {
      final entries = <MapEntry<int, Map<String, dynamic>>>[];

      for (var i = 0; i < markers.length; i++) {
        final item = markers[i];
        if (item is! Map) continue;
        final marker = Map<String, dynamic>.from(item);
        if (marker['group'] is Map && marker['group']['name'] == groupName) {
          entries.add(MapEntry(i, marker));
        }
      }

      entries.sort((a, b) {
        final numberCompare = _markerTitleNumber(a.value['title']?.toString()).compareTo(_markerTitleNumber(b.value['title']?.toString()));
        if (numberCompare != 0) return numberCompare;
        return a.key.compareTo(b.key);
      });

      for (var i = 0; i < entries.length; i++) {
        final marker = entries[i].value;
        marker['title'] = '${i + 1}';
        markers[entries[i].key] = marker;
      }
    }
  }

Future<void> _showInputSheet({LatLng? newPoint, SiteData? existingData, String? targetTeamName}) async {
    setState(() {
      _clearTemporaryMapModes();
      _isModalOpen = true;
      _isMapControlActive = false;
    });
    _setMarkerMoveModeOnKakaoMap(false);
    
    // 1. 위치 및 주소 설정
    LatLng pos = newPoint ?? (existingData?.position ?? const LatLng(37.56, 126.97));
    String fetchedAddress = existingData?.address ?? "주소를 불러오는 중...";
    if (newPoint != null) {
      fetchedAddress = await _getKoreanAddressOrNull(pos.latitude, pos.longitude) ?? "";
      if (!_isValidMarkerAddress(fetchedAddress) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주소를 찾지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.')),
        );
      }
    }

    String? selectedGroupName;
    if (existingData != null) {
      selectedGroupName = existingData.group.name;
    } else {
      selectedGroupName = _defaultMarkerGroupName();
    }

    // ✅ 2. 맨홀 번호 스마트 자동 채번 (Max + 1)
    String defaultTitle = "";
    if (existingData != null) {
      defaultTitle = existingData.title; // 기존 데이터 수정 시 그대로 유지
    } else {
      String targetGroup = selectedGroupName ?? "";
      defaultTitle = _nextMarkerTitleForGroup(targetGroup); // 가장 큰 수 + 1
    }

    // 3. 텍스트 컨트롤러 초기화 (자동 채번된 번호를 입력창에 꽂아줌)
    TextEditingController tCtrl = TextEditingController(text: defaultTitle);
    TextEditingController dCtrl = TextEditingController(text: existingData?.description ?? "");
    TextEditingController aCtrl = TextEditingController(text: fetchedAddress);

    List<PhotoItem> photos = existingData != null ? List.from(existingData.photos) : [];
    // ----------------------------------------------------------------------

    if (!mounted) return;
    // ⭐ 반드시 await를 추가하여 창이 완전히 닫힐 때까지 다음 코드로 넘어가지 않게 막아야 합니다.
    await showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMS) {
          // 현재 선택된 그룹 객체 찾기 (UI 표시용)
          MapGroup? selG;
          
          if (targetTeamName != null && existingData != null) {
            // 관리자 모드일 때
            selG = existingData.group;
          } else {
            // 일반 모드일 때 (위에서 정한 selectedGroupName 기반으로 객체 찾기)
            selG = selectedGroupName != null 
              ? _userGroups.firstWhere((g) => g.name == selectedGroupName, orElse: () => _userGroups.first)
              : (_userGroups.isNotEmpty ? _userGroups.first : null);
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 60, left: 20, right: 20, top: 20), 
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  TextField(controller: tCtrl, decoration: const InputDecoration(labelText: "맨홀 번호")),
                  TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "상세 설명")),
                  TextField(controller: aCtrl, decoration: const InputDecoration(labelText: "현장 주소", icon: Icon(Icons.location_on, color: Colors.red))),
                  const SizedBox(height: 20),
                  
                  // [그룹 선택 UI]
                  if (targetTeamName != null)
                     ListTile(
                       title: Text("그룹: ${selG?.name ?? '없음'} (타 팀 데이터)"), 
                       leading: Icon(Icons.layers, color: selG?.color),
                       subtitle: const Text("관리자 모드에서는 그룹 이동이 제한됩니다.", style: TextStyle(fontSize: 10, color: Colors.grey)),
                     )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<MapGroup>(
                            isExpanded: true, 
                            hint: const Text("그룹 선택"), 
                            value: selG, 
                            items: _userGroups.map((g) => DropdownMenuItem(value: g, child: Text(g.name, style: TextStyle(color: g.color)))).toList(), 
                            onChanged: (v) => setMS(() {
                              selectedGroupName = v?.name;
                              if (v != null) {
                                if (existingData != null && v.name == existingData.group.name) {
                                  tCtrl.text = existingData.title;
                                } else {
                                  tCtrl.text = _nextMarkerTitleForGroup(v.name, excludeMarkerId: existingData?.id);
                                }
                              }
                              // 수동으로 바꿔도 기억하기
                              if (v != null) _setQuickSelectedGroupName(v.name);
                            })
                          ),
                        ),
                        // 그룹 추가 버튼
                        IconButton(
                          icon: const Icon(Icons.add_box, color: Colors.blue, size: 30),
                          tooltip: "새 그룹 추가",
                          onPressed: () {
                            _addNewGroupDialog(() {
                              setMS(() {
                                if (_userGroups.isNotEmpty) {
                                  // ✅ 여기서도 즉시 반영 및 기억
                                  selectedGroupName = _userGroups.last.name;
                                  _setQuickSelectedGroupName(_userGroups.last.name);
                                  tCtrl.text = _nextMarkerTitleForGroup(_userGroups.last.name, excludeMarkerId: existingData?.id);
                                }
                              });
                            });
                          },
                        )
                      ],
                    ),
                  
                  const SizedBox(height: 10),

                  // 사진 등록 (전경, 시공전, 시공후)
                  const SizedBox(height: 10),
                  const Align(alignment: Alignment.centerLeft, child: Text("현장 사진 등록", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey))),
                  const SizedBox(height: 10),
                  
                  ...["전경", "시공전", "시공후", "기타"].map((category) {
                    List<PhotoItem> categoryPhotos;
                    if (category == "기타") {
                      categoryPhotos = photos.where((p) => !["전경", "시공전", "시공후"].contains(p.comment)).toList();
                      if (categoryPhotos.isEmpty) return const SizedBox.shrink(); // 기타 사진 없으면 숨김
                    } else {
                      categoryPhotos = photos.where((p) => p.comment == category).toList();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(category, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            if (category != "기타")
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (bottomCtx) => SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: const Icon(Icons.camera_alt, color: Colors.green),
                                            title: const Text("카메라로 촬영"),
                                            onTap: () async {
                                              Navigator.pop(bottomCtx);
                                              final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1024);
                                              if (x != null) setMS(() => photos.add(PhotoItem(filePath: x.path, comment: category)));
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(Icons.photo_library, color: Colors.blue),
                                            title: const Text("갤러리에서 선택"),
                                            onTap: () async {
                                              Navigator.pop(bottomCtx);
                                              final images = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1024);
                                              if (images.isNotEmpty) setMS(() { for (var img in images) photos.add(PhotoItem(filePath: img.path, comment: category)); });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )
                          ],
                        ),
                        if (categoryPhotos.isNotEmpty)
                          SizedBox(
                            height: 90,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: categoryPhotos.length,
                              itemBuilder: (ctx, i) {
                                var p = categoryPhotos[i];
                                return Stack(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _showEnlargedPhoto(p.filePath, p.comment),
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 10, top: 10),
                                        width: 80, height: 80,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: (kIsWeb || p.filePath.startsWith('http'))
                                              ? Image.network(p.filePath, fit: BoxFit.cover, errorBuilder: (c,e,s)=>const Icon(Icons.error))
                                              : Image.file(File(p.filePath), fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0, top: 0,
                                      child: GestureDetector(
                                        onTap: () => setMS(() => photos.remove(p)),
                                        child: Container(
                                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                          child: const Icon(Icons.cancel, color: Colors.red, size: 24),
                                        ),
                                      ),
                                    )
                                  ],
                                );
                              },
                            ),
                          )
                        else if (category != "기타")
                          const Padding(
                            padding: EdgeInsets.only(bottom: 5),
                            child: Text("등록된 사진이 없습니다.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ),
                        const Divider(),
                      ],
                    );
                  }).toList(),
                  
                  const SizedBox(height: 15),

                  // 저장 버튼
                  ElevatedButton(
  style: ElevatedButton.styleFrom(
    minimumSize: const Size(double.infinity, 50), 
    backgroundColor: Colors.green
  ),
  onPressed: () async {
 
    // ✅ [추가] 그룹이 없거나 선택되지 않았을 때 알림창 띄우기
    if (selG == null) {
      showDialog(
        context: context,
        builder: (alertCtx) => AlertDialog(
          title: const Text("알림"),
          content: const Text("그룹을 생성하거나 선택해 주세요."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(alertCtx), // 확인 누르면 알림창만 닫힘
              child: const Text("확인", style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      );
      return; // 여기서 실행을 멈추어 저장이 안 되게 막음
    }

    final addressForSave = aCtrl.text.trim();
    if (!_isValidMarkerAddress(addressForSave)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주소를 찾지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.')),
      );
      return;
    }

    Navigator.pop(ctx);
    
    // 로딩 화면 켜기
    setState(() { _isGlobalProcessing = true; _processingText = "저장 중..."; });
    
    try {
      // 🔥 [핵심 추가] 전체 저장 로직을 20초 타임아웃으로 묶습니다.
      await Future(() async {
        String uploadTeamName = targetTeamName ?? widget.teamName;
        List<PhotoItem> serverPhotos = await _uploadPhotos(photos, uploadTeamName);

        final isNewMarker = existingData == null;
        final id = existingData?.id ?? DateTime.now().toString();
        final previousGroupName = existingData?.group.name;
        final selectedGroupForSave = selG!;
        final shouldRenumberMarkerGroups =
            existingData != null && targetTeamName == null && previousGroupName != selectedGroupForSave.name;
        final renumberGroupNames = [previousGroupName, selectedGroupForSave.name];
        SiteData newData = SiteData(
          id: id, lat: pos.latitude, lng: pos.longitude,
          title: tCtrl.text, description: dCtrl.text, address: addressForSave,
          group: selectedGroupForSave, photos: serverPhotos,
          canonicalMarkerId: existingData?.canonicalMarkerId,
          originalMarkerId: existingData?.originalMarkerId,
          sourceMarkerId: existingData?.sourceMarkerId,
          parentMarkerId: existingData?.parentMarkerId,
          isChecked: existingData?.isChecked == true,
        );

        if (!isNewMarker) {
          final mutationTeamName = targetTeamName ?? widget.teamName;
          final fields = _canonicalFieldsFromSite(newData, {
            'title': newData.title,
            'description': newData.description,
            'address': newData.address,
            'lat': newData.lat,
            'lng': newData.lng,
            'isChecked': existingData?.isChecked == true,
          });
          _applyCanonicalMarkerMutationLocally(
            initiatingMarker: newData,
            canonicalFields: fields,
            updateConnectedLines: true,
            initiatingTeamName: mutationTeamName,
          );
          final saved = await _commitCanonicalMarkerMutation(
            initiatingMarker: newData,
            canonicalFields: fields,
            updateConnectedLines: true,
            mutationType: 'details',
            initiatingTeamName: mutationTeamName,
          );
          if (!saved) throw Exception('marker canonical mutation target not found');

          final shouldUpload = isAdmin ? _spreadsheetEnabled : true;
          if (shouldUpload) {
            if (targetTeamName != null) {
              await _uploadToSpreadsheet(newData, targetTeamName: targetTeamName);
            } else {
              await _uploadToSpreadsheet(newData);
            }
          }
          return;
        }

        if (isAdmin && targetTeamName != null) {
           // 관리자 모드 저장 로직
           var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeamName);
           var snapshot = await docRef.get();
           if (snapshot.exists) {
             var data = snapshot.data()!;
             List<dynamic> markers = List.from(data['markers'] ?? []);
             int idx = markers.indexWhere((m) => m['id'] == id);
             if (idx != -1) markers[idx] = newData.toJson();
             else markers.add(newData.toJson());
             await docRef.update({'markers': markers});
             final shouldUpload = isAdmin ? _spreadsheetEnabled : true;
             if (shouldUpload) {
               await _uploadToSpreadsheet(newData, targetTeamName: targetTeamName);
             }
           }
        } else {
          // ✅ 내 데이터 저장 로직 (트랜잭션 적용: 동시 접속 덮어쓰기 완벽 방지)
          var docRef = FirebaseFirestore.instance.collection('teams').doc(widget.teamName);
          
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            var snapshot = await transaction.get(docRef);
            
            if (!snapshot.exists) {
              // 문서가 아예 없으면 초기 생성
              transaction.set(docRef, {
                'teamName': widget.teamName,
                'teamPw': widget.teamPw,
                'groups': _userGroups.map((g) => g.toJson()).toList(),
                'markers': [newData.toJson()],
                'lines': _lineDataMap.values.map((l) => l.toJson()).toList(),
              });
            } else {
              var data = snapshot.data()!;
              
              // 1. 기존 데이터가 있으면 충돌 없이 markers 배열만 안전하게 업데이트
              List<dynamic> markers = List.from(data['markers'] ?? []);
              int idx = markers.indexWhere((m) => m['id'] == id);
              if (idx != -1) {
                markers[idx] = newData.toJson(); // 기존 마커 수정
              } else {
                markers.add(newData.toJson()); // 새 마커 추가
              }
              if (shouldRenumberMarkerGroups) {
                _renumberMarkerJsonListForGroups(markers, renumberGroupNames);
              }

              // 2. 만약 그룹이 새로 만들어진 거라면 그룹 리스트도 덮어쓰지 않고 추가
              List<dynamic> groups = List.from(data['groups'] ?? []);
              if (!groups.any((g) => g['name'] == selectedGroupForSave.name)) {
                groups.add(selectedGroupForSave.toJson());
              }

              transaction.update(docRef, {'markers': markers, 'groups': groups});
            }
          });

          // 로컬 화면(UI) 즉시 반영
          setState(() {
            _setQuickSelectedGroupName(selectedGroupForSave.name);
            _markerDataMap[id] = newData;
            if (shouldRenumberMarkerGroups) {
              _renumberOwnMarkersForGroups(renumberGroupNames);
            }
          });
          if (shouldRenumberMarkerGroups) {
            await _saveData();
            _scheduleMarkerUpdate(ms: 0);
          } else {
            _scheduleMarkerUpdate(ms: 0);

            // 기존 _saveData()는 전체를 덮어씌우므로 제외하고, 비상용 로컬 폰 저장만 수행
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('${widget.teamName}_${widget.teamPw}_m', jsonEncode(_markerDataMap.values.map((m) => m.toJson()).toList()));
            await prefs.setString('${widget.teamName}_${widget.teamPw}_g', jsonEncode(_userGroups.map((g) => g.toJson()).toList()));
          }

          if (isNewMarker && targetTeamName == null && _isOriginalMarkerForSharedSync(newData)) {
            await _appendNewMarkerToSharedGroups(
              sourceTeamName: widget.teamName,
              marker: newData,
            );
          }

          final shouldUpload = isAdmin ? _spreadsheetEnabled : true;
          if (shouldUpload) {
            await _uploadToSpreadsheet(newData, targetTeamName: targetTeamName);
          }
        }
      }).timeout(const Duration(seconds: 20)); // ⏱️ 20초 후 강제 중단

    } on TimeoutException {
      // 🔥 20초 초과 시 실행됨
      debugPrint("🔴 저장 시간 초과");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⏳ 저장 시간 초과! 다시 시도해 주세요."), backgroundColor: Colors.orange)
        );
      }
    } catch (e) {
      // 기타 다른 에러 발생 시
      debugPrint("🔴 저장 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("에러: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      // ⭐ [가장 중요] 성공하든, 에러가 나든, 시간이 초과되든 무조건 로딩 바를 없앱니다.
      if (mounted) setState(() => _isGlobalProcessing = false);
    }
  }, 
  child: const Text("저장 완료", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
),
                ],
              ),
            ),
          );
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _isModalOpen = false;
        _isMapControlActive = true;
      });
    }
  }

// ✅ [최종 수정] 보관함 모드 스위치 제거 (항상 실시간 지도 모드) + 모든 기능 유지
  Widget _buildDrawer() {
    return Drawer(
      width: 360,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isMapControlActive = false),
        onExit: (_) => setState(() => _isMapControlActive = true),
        child: ListView(
          children: [
            // ❌ [삭제됨] 보관함 모드 스위치가 있던 자리 (이제 헤더가 가장 위입니다)

            // 1. 헤더 (시스템 로고)
            DrawerHeader(
              decoration: BoxDecoration(
                color: isAdmin ? Colors.blueAccent : Colors.green
              ),
              child: Center(
                child: Text(
                  isAdmin ? "통합 관제 시스템" : "현장 관리 시스템",
                  style: const TextStyle(color: Colors.white, fontSize: 22),
                ),
              ),
            ),

            if (isAdmin)
              SwitchListTile(
                secondary: const Icon(Icons.table_chart, color: Colors.green),
                title: const Text("Spreadsheet upload"),
                subtitle: const Text("Off by default on every app start"),
                value: _spreadsheetEnabled,
                onChanged: (value) {
                  setState(() => _spreadsheetEnabled = value);
                },
              ),

            // 2. [관리자 전용] 협력사(다른 팀) 목록 표시
            if (isAdmin) ...[
              // 통합 관리 버튼 (저장/복구 기능 유지)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 5, 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("협력사/팀 목록", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    IconButton(
                      icon: const Icon(Icons.save, size: 26, color: Colors.amber),
                      tooltip: "전체 데이터 아카이브 (통합 관리)",
                      onPressed: _showGlobalArchiveDialog, 
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),

              // 팀 목록 반복
              ..._allTeamsMap.entries.map((entry) {
                String teamName = entry.key;
                TeamData team = entry.value;
                
                return ExpansionTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(teamName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_note, size: 22, color: Colors.blueGrey),
                        onPressed: () => _editTeamNameDialog(teamName),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, size: 22, color: Colors.redAccent),
                        onPressed: () => _deleteTeamDialog(teamName),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ],
                  ),
                  trailing: Switch(
                    value: team.isVisible,
                    activeColor: Colors.blue,
                    onChanged: (v) {
                      setState(() {
                        team.isVisible = v;
                      });
                      _scheduleMarkerUpdate();
                    },
                  ),

                  // 팀 내부 그룹 목록
                  children: team.groups.map((g) {
                    List<SiteData> groupMarkers = team.markers.values
                        .where((m) => m.group.name == g.name)
                        .toList()
                      ..sort(_compareSiteDataByMarkerNumber);
                    
                    return ExpansionTile(
                      leading: Icon(Icons.layers, color: g.color, size: 20),
                      title: Text(g.name, style: TextStyle(color: g.color, fontSize: 13, fontWeight: FontWeight.bold)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1) 앱(App)에서는 PDF 리포트 버튼
                          if (!kIsWeb) 
                            IconButton(
                              icon: const Icon(Icons.picture_as_pdf, size: 20, color: Colors.blueAccent),
                              tooltip: "PDF 리포트",
                              onPressed: () => _exportGroupPdfForAdmin(teamName, g),
                            ),
                          
                          // 2) 웹(Web)에서는 사진 모음 다운로드 버튼
                          if (kIsWeb)
                            IconButton(
                              icon: const Icon(Icons.photo_library, size: 20, color: Colors.green),
                              tooltip: "사진 모음 다운로드 (ZIP)",
                              onPressed: () => _downloadGroupPhotosWeb(teamName, g),
                            ),

                          // 3) 삭제 버튼
                          IconButton(
                            icon: const Icon(Icons.delete_forever, size: 20, color: Colors.red),
                            onPressed: () => _deleteOtherTeamGroupDialog(teamName, g),
                          ),
                          // 4) 보이기 스위치
                          Switch(
                            value: g.isVisible,
                            activeColor: g.color,
                            onChanged: (v) {
                              setState(() {
                                g.isVisible = v;
                              });
                              _scheduleMarkerUpdate();
                            },
                          ),
                        ],
                      ),
                      
                      // 상세설명(subtitle) 포함된 마커 리스트
                      children: groupMarkers.isEmpty 
                          ? [ const ListTile(dense: true, title: Text("마커 없음", style: TextStyle(fontSize: 12, color: Colors.grey))) ]
                          : groupMarkers.map((marker) => ListTile(
                              dense: true,
                              // 아이콘도 파란색으로 맞추고 싶다면 아래 color 부분 참고 (현재는 유지)
                              leading: Icon(Icons.location_on, size: 18, color: marker.isChecked ? Colors.blue : Colors.grey), 
                              // ✅ title 텍스트 색상 동적 변경 (const 제거)
                              title: Text(marker.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: marker.isChecked ? Colors.blue : null)),
                              // ✅ subtitle 텍스트 색상 동적 변경 (const 제거)
                              subtitle: Text(marker.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: marker.isChecked ? Colors.blue : null)), 
                              onTap: () { 
                                Navigator.pop(context); 
                                _moveTo(marker.lat, marker.lng, _shouldUseNativeKakaoMap ? _nativeFocusedZoomLevel : 1);
                              },
                            )).toList(),
                    );
                  }).toList(),
                );
              }).toList(),
              const Divider(),
            ],

            // 3. [개인/팀장 전용] 나의 데이터 목록
            const Padding(
              padding: EdgeInsets.all(10), 
              child: Text("나의 데이터", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))
            ),
            
            ..._userGroups.map((g) {
              final groupMarkers = _markerDataMap.values
                  .where((m) => m.group.name == g.name)
                  .toList()
                ..sort(_compareSiteDataByMarkerNumber);

              return ExpansionTile(
                title: Text(
                  g.name,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(color: g.color, fontWeight: FontWeight.bold),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     IconButton(
                      icon: const Icon(Icons.cloud_upload, color: Colors.blueAccent),
                      tooltip: "데이터 전송",
                      onPressed: () => _showSendGroupSheet(g),
                      constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                      padding: EdgeInsets.zero,
                    ),

                    // 2. 삭제 버튼 (복구 유지)
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      onPressed: () => _deleteGroupDialog(g),
                      constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                      padding: EdgeInsets.zero,
                    ),

                    // 3. 설정(수정) 버튼
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.grey),
                      onPressed: () => _showEditGroupDialog(g),
                      constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                      padding: EdgeInsets.zero,
                    ),

                    // 4. 보이기 스위치
                    Switch(
                      value: g.isVisible,
                      activeColor: g.color,
                      onChanged: (val) {
                        setState(() {
                          g.isVisible = val;
                        });
                        _scheduleMarkerUpdate();
                      },
                    ),
                  ],
                ),
                children: groupMarkers.map((s) => ListTile(
                  // ✅ 아이콘 추가 및 색상 적용 (보기 좋게 통일)
                  leading: Icon(Icons.location_on, size: 18, color: s.isChecked ? Colors.blue : Colors.grey),
                  // ✅ 텍스트에 조건부 TextStyle 추가
                  title: Text(s.title, softWrap: true, overflow: TextOverflow.visible, style: TextStyle(color: s.isChecked ? Colors.blue : null, fontWeight: FontWeight.bold)),
                  subtitle: Text(s.description, softWrap: true, overflow: TextOverflow.visible, style: TextStyle(color: s.isChecked ? Colors.blue : Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _moveTo(s.lat, s.lng, _shouldUseNativeKakaoMap ? _nativeFocusedZoomLevel : 1);
                  },
                )).toList(),
              );
            }),

            ListTile(
              leading: const Icon(Icons.add_box, color: Colors.blue),
              title: const Text("새 그룹 추가"),
              onTap: () {
                _addNewGroupDialog(() {
                  setState(() {
                    // 슬라이드바에서 그룹을 만들어도, 마커 생성 시 이 그룹이 기본값이 됨
                    if (_userGroups.isNotEmpty) {
                      _setQuickSelectedGroupName(_userGroups.last.name);
                    }
                  });
                });
              },
            ),
            const Divider(), // 구분선

            ExpansionTile(
              leading: const Icon(Icons.timeline, color: Colors.purple),
              title: Row(
                children: [
                  const Expanded(child: Text("선 목록 (Lines)", style: TextStyle(fontWeight: FontWeight.bold))),
                  if (_isLineDeleteMode)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _selectedLineIds.isEmpty ? null : _deleteSelectedLines,
                      child: const Text("선택 삭제"),
                    ),
                  if (_isLineDeleteMode)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _lineDataMap.isEmpty ? null : _deleteAllLines,
                      child: const Text("전체 삭제"),
                    ),
                  IconButton(
                    icon: Icon(_isLineDeleteMode ? Icons.close : Icons.checklist),
                    constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                    padding: EdgeInsets.zero,
                    tooltip: _isLineDeleteMode ? "삭제 모드 종료" : "삭제 모드",
                    onPressed: () {
                      setState(() {
                        _isLineDeleteMode = !_isLineDeleteMode;
                        if (!_isLineDeleteMode) _clearSelectedLines();
                      });
                    },
                  ),
                ],
              ),
              children: [
                // 1. 선이 아예 없을 때
                if (_lineDataMap.isEmpty && (!isAdmin || _allTeamsMap.values.every((t) => t.lines.isEmpty)))
                  const ListTile(title: Text("생성된 선이 없습니다.", style: TextStyle(fontSize: 12, color: Colors.grey)))
                else ...[
                  // 2. [내 선] 목록 그리기 (함수 호출)
                  ..._lineDataMap.values.map((line) => _buildLineListTile(line, isMyLine: true)),

                  // 3. [관리자용] 다른 팀 선 목록 그리기 (함수 호출)
                  if (isAdmin)
                    ..._allTeamsMap.entries.expand((entry) {
                      String teamName = entry.key;
                      TeamData teamData = entry.value;
                      return teamData.lines.values.map((line) => _buildLineListTile(line, isMyLine: false, teamName: teamName));
                    }),
                ]
              ],
            ),
            
            // 로그아웃 버튼
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("로그아웃"),
              onTap: widget.onLogout,
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildAdminGroupQuickSlots() {
    if (
      !isAdmin ||
      !_isAdminQuickSlotsVisible ||
      _userGroups.isEmpty ||
      _isModalOpen ||
      !_isMapControlActive ||
      _isLineMode ||
      _isFreeLineMode
    ) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: SafeArea(
        bottom: false,
        child: _uiBlocker(
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _userGroups.map((group) {
                  final quickMode = group.name == _quickSelectedGroupName ? _quickGroupMode : 0;
                  final selected = quickMode > 0;
                  final quickCreate = quickMode == 2;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        setState(() {
                          _cycleQuickGroupMode(group.name);
                        });
                      },
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 110),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: quickCreate ? Colors.black87 : (selected ? group.color : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? group.color : group.color.withOpacity(0.7),
                            width: quickCreate ? 2.5 : 1,
                          ),
                        ),
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.white : group.color,
                            fontSize: 12,
                            fontWeight: quickCreate ? FontWeight.w900 : (selected ? FontWeight.bold : FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  
  @override
  Widget build(BuildContext context) {
    // 2. 화면 구성 시작
    return Scaffold(
      resizeToAvoidBottomInset: false,
        appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text('${widget.teamName} ($_roleLabel)-지도')),
            const Text(
              "제작자 : 박건희",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        backgroundColor: isAdmin ? Colors.blueAccent : Colors.green,
      ),
      drawer: _buildDrawer(),
      floatingActionButton: _uiBlocker(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isAdmin) ...[
              FloatingActionButton(
                heroTag: "quickSlots",
                tooltip: _isAdminQuickSlotsVisible
                    ? "퀵상태바 끄기"
                    : "퀵상태바 켜기",
                backgroundColor: _isAdminQuickSlotsVisible
                    ? Colors.blueAccent
                    : Colors.white,
                onPressed: () {
                  setState(() {
                    _isAdminQuickSlotsVisible =
                        !_isAdminQuickSlotsVisible;

                    if (!_isAdminQuickSlotsVisible) {
                      _quickSelectedGroupName = null;
                      _quickGroupMode = 0;
                    }
                  });
                },
                child: Icon(
                  _isAdminQuickSlotsVisible
                      ? Icons.visibility_off
                      : Icons.view_stream,
                  color: _isAdminQuickSlotsVisible
                      ? Colors.white
                      : Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 10),
            ],

            FloatingActionButton(
              heroTag: "markerNumberSearchFab",
              tooltip: "마커번호 검색",
              backgroundColor: Colors.white,
              onPressed: _showMarkerNumberSearchDialog,
              child: const Icon(Icons.search, color: Colors.black),
            ),

            const SizedBox(height: 10),

            FloatingActionButton(
              heroTag: "lineLabels",
              tooltip: _showAllLineLabels
                  ? "선 라벨 끄기"
                  : "선 라벨 켜기",
              backgroundColor: _showAllLineLabels
                  ? Colors.blueAccent
                  : Colors.white,
              onPressed: () async {
                setState(() {
                  _showAllLineLabels = !_showAllLineLabels;
                });

                await _setShowAllLineLabelsOnKakaoMap(_showAllLineLabels);
              },
              child: Icon(
                _showAllLineLabels
                    ? Icons.label
                    : Icons.label_off,
                color: _showAllLineLabels
                    ? Colors.white
                    : Colors.black,
              ),
            ),

            const SizedBox(height: 10),

            FloatingActionButton(
              heroTag: "move",
              tooltip: _isMoveMode ? "마커 이동 OFF" : "마커 이동 ON",
              backgroundColor: _isMoveMode ? Colors.orange : Colors.white,
              onPressed: () {
                final next = !_isMoveMode;
                setState(() {
                  _clearTemporaryMapModes();
                  if (next) {
                    _isMoveMode = true;
                  }
                });
                _setMarkerMoveModeOnKakaoMap(_isMoveMode);
                _scheduleMarkerUpdate();
              },
              child: Icon(
                Icons.open_with,
                color: _isMoveMode ? Colors.white : Colors.black,
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.only(bottom: 100),
              child: FloatingActionButton(
                heroTag: "gps",
                onPressed: () async {
                  try {
                    final serviceEnabled =
                        await Geolocator.isLocationServiceEnabled();

                    if (!serviceEnabled) {
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("휴대폰 위치 서비스를 켜주세요."),
                        ),
                      );
                      return;
                    }

                    var permission = await Geolocator.checkPermission();

                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                    }

                    if (
                      permission == LocationPermission.denied ||
                      permission == LocationPermission.deniedForever
                    ) {
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("현재 위치를 보려면 위치 권한이 필요합니다."),
                        ),
                      );
                      return;
                    }

                    final position = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.high,
                    );

                    await _showCurrentLocationOnMap(
                      position.latitude,
                      position.longitude,
                    );

                    await _moveTo(
                      position.latitude,
                      position.longitude,
                      _shouldUseNativeKakaoMap ? _nativeFocusedZoomLevel : 3,
                    );
                  } catch (e) {
                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("현재 위치를 불러오지 못했습니다."),
                      ),
                    );
                  }
                },
                child: const Icon(Icons.my_location),
              )
            ),
          ]
        ),
      ),

body: Stack(
      children: [
        // 1. [가장 뒤] 지도 레이어
        IgnorePointer(
          ignoring: !_isMapControlActive || _isModalOpen, 
          child: _shouldUseNativeKakaoMap
              ? const AndroidView(viewType: _nativeKakaoMapViewType)
              : _webViewController == null
                  ? const SizedBox.shrink()
                  : WebViewWidget(controller: _webViewController!),
        ),

    if (_isModalOpen || !_isMapControlActive)
      Positioned.fill(
        child: PointerInterceptor(
          intercepting: true, 
          child: Container(
            // ⭐ [핵심 1] 투명(transparent) 대신 1% 불투명도를 주어 물리적 벽을 생성!
            color: Colors.black.withOpacity(0.01), 
          ),
        ),
      ),

          _buildAdminGroupQuickSlots(),

          if (_isTappingMode || _isMoveMode)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: _uiBlocker(
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_isMoveMode ? Colors.orange : Colors.green).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isMoveMode
                              ? "마커 이동 ON"
                              : "지도에서 마커를 추가할 위치를 선택하세요.",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(_clearTemporaryMapModes);
                          _setMarkerMoveModeOnKakaoMap(false);
                        },
                        child: const Text("취소", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            
if (_isFreeLineMode) 
            Positioned(
              top: 10, left: 10, right: 10, 
              // ✅ [수정] 강력 방어막 적용
              child: _uiBlocker(
                Container(
                  padding: const EdgeInsets.all(10), 
                  decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), borderRadius: BorderRadius.circular(10)), 
                  child: Column(
                    children: [
                      const Text("지도 빈 곳을 터치하여 선을 만드세요", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                        children: [
                          TextButton(
                            onPressed: () => setState(() { _isFreeLineMode = false; _tempFreeLinePoints.clear(); }), 
                            child: const Text("취소", style: TextStyle(color: Colors.white))
                          ), 
                          IconButton(
                            icon: const Icon(Icons.undo, color: Colors.white),
                            onPressed: () {
                              if (_tempFreeLinePoints.isNotEmpty) {
                                setState(() => _tempFreeLinePoints.removeLast());
                              }
                            },
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.redAccent),
                            onPressed: () {
                                if (_tempFreeLinePoints.length < 2) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("최소 2개 지점이 필요합니다.")));
                            return;
                             }
    // ✅ [핵심 수정] 설정창을 띄우기 직전에 그리기 모드를 '완전히' 종료하여 터치 관통을 원천 차단
    setState(() {
      _isFreeLineMode = false;
      _isMapControlActive = false;
      _isModalOpen = true; // 팝업이 뜨기 전부터 미리 모달 상태를 true로 잠금
    });
    
    _showLineInputSheet(isFreeDraw: true);
  }, 
  child: const Text("완료")
),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 2. [중간] 선 그리기 안내창 레이어
if (_isLineMode) 
            Positioned(
              top: 10, left: 10, right: 10, 
              // ✅ [수정] 방어막 적용
              child: _uiBlocker(
                Container(
                  padding: const EdgeInsets.all(10), 
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.9), borderRadius: BorderRadius.circular(10)), 
                  child: Column(
                    children: [
                      const Text("선 그리기 (마커를 순서대로 클릭)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                        children: [
                          TextButton(onPressed: () => setState(() { _isLineMode = false; _tempLineMarkerIds.clear(); }), child: const Text("취소", style: TextStyle(color: Colors.white))), 
                          ElevatedButton(onPressed: () => _showLineInputSheet(), child: const Text("완료")),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 3. [중간] 하단 새 마커 생성 버튼 레이어
          Align(
            alignment: Alignment.bottomCenter, 
            child: Padding(
              padding: const EdgeInsets.only(bottom: 80), 
              // ✅ [수정] 방어막 적용
              child: _uiBlocker(
                ElevatedButton(onPressed: () => _showCreateMenu(), child: const Text("새 마커/선 생성"))
              ),
            ),
          ),

          // ⭐ 4. [가장 앞] 상단 로딩/알림 바 (가장 마지막에 배치하여 모든 UI를 덮음)
          if (_isGlobalProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black26, // 화면 전체를 어둡게 하여 로딩 중 터치 차단 및 강조
                child: Column(
                  children: [
                    SafeArea(
                      child: Container(
                        width: double.infinity,
                        color: Colors.black, // 알림 바 배경
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            ),
                            const SizedBox(width: 20),
                            Text(
                              _processingText,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ], // Stack 끝
      ),
    );
  }
  // --- [상세 보기: 관리자용 다운로드 버튼 추가 버전] ---
void _showMarkerDetails(String mid, {TeamData? fromOtherTeam}) {
    final d = fromOtherTeam != null ? fromOtherTeam.markers[mid]! : _markerDataMap[mid]!;
    String? targetTeamName = fromOtherTeam?.teamName; 

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent, // ✅ 배경을 투명하게 해야 변경된 창 색상이 보입니다.
      builder: (ctx) => StatefulBuilder( // ✅ 화면을 바로 갱신하기 위한 감싸기
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.all(20), 
          decoration: BoxDecoration(
            color: d.isChecked ? Colors.yellow.shade50 : Colors.white, // ✅ 온(On) 일때 연한 노란색, 오프일때 흰색
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              // 1. 상단 헤더 (스위치 + 그룹명)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children: [
                  // ✅ [추가] 좌상단 온오프 토글 및 그룹명
                  Expanded(
                    child: Row(
                      children: [
                        Switch(
                          value: d.isChecked,
                          activeColor: Colors.orangeAccent,
                          onChanged: (val) async {
                  setModalState(() => d.isChecked = val);
                  _applyCanonicalMarkerMutationLocally(
                    initiatingMarker: d,
                    canonicalFields: _canonicalFieldsFromSite(d, {'isChecked': val}),
                    updateConnectedLines: false,
                    initiatingTeamName: targetTeamName ?? widget.teamName,
                  );
                   
                  // 1. 서버/로컬 데이터 저장
                  if (isAdmin && targetTeamName != null) {
                    await _commitCanonicalMarkerMutation(
                      initiatingMarker: d,
                      canonicalFields: _canonicalFieldsFromSite(d, {'isChecked': val}),
                      updateConnectedLines: false,
                      mutationType: 'check',
                      initiatingTeamName: targetTeamName,
                    );
                    // ✅ [추가] 관리자 모드 시트 동기화
                    await _syncToGoogleSheetAdmin(d, targetTeamName); 
                  } else {
                    await _commitCanonicalMarkerMutation(
                      initiatingMarker: d,
                      canonicalFields: _canonicalFieldsFromSite(d, {'isChecked': val}),
                      updateConnectedLines: false,
                      mutationType: 'check',
                      initiatingTeamName: widget.teamName,
                    );
                    // ✅ [추가] 내 팀 시트 동기화
                    await _syncToGoogleSheet(d); 
                  }
                  
                  // 2. 지도 마커와 슬라이드바 텍스트 색상 즉시 갱신을 위해 호출
                  _scheduleMarkerUpdate();
                },
                        ),
                        Expanded(
                          child: Text(
                            "${targetTeamName != null ? '[$targetTeamName] ' : ''}${d.group.name}", 
                            style: TextStyle(color: d.group.color, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 우측 아이콘 버튼들 (기존 코드 유지)
                  Row(
                    children: [
                      
                IconButton(
  icon: const Icon(Icons.map, color: Color(0xFF2DB400), size: 28),
  tooltip: "네이버 지도에서 보기",
  onPressed: () async {
    // 1. [웹(Web) 환경일 때] -> 네이버 지도 '사이트'로 이동
    if (kIsWeb) {
      // 🚨 [핵심 수정] 좌표 단순 검색이 아닌, '목적지 핀(작은 창)'을 띄우는 이전 형식으로 변경!
      // (띄어쓰기나 특수문자가 들어간 맨홀 이름도 안 깨지도록 Uri.encodeComponent 추가)
      final webUrl = Uri.parse("https://map.naver.com/?lng=${d.lng}&lat=${d.lat}&title=현장위치");
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("지도를 열 수 없습니다.")));
      }
    }
    // 2. [앱(App) 환경일 때] -> 네이버 지도 '어플' 실행
    else {
      // 앱 환경에서도 핀 이름이 정확히 뜨도록 URL 안전 인코딩 장착
      final appUrl = Uri.parse("nmap://place?lat=${d.lat}&lng=${d.lng}&name=${Uri.encodeComponent(d.title)}&appname=com.fieldmanager.app");
      final marketUrl = Uri.parse("market://details?id=com.nhn.android.nmap");

      try {
        if (await canLaunchUrl(appUrl)) {
          await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(marketUrl, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("지도를 실행할 수 없습니다.")));
        }
      }
    }
  },
),

if (isAdmin)
    IconButton(
      icon: const Icon(Icons.gps_fixed, color: Colors.blueAccent, size: 28),
      tooltip: "이 위치로 GPS 변경",
      onPressed: () {
        showDialog(
          context: context,
          builder: (confirmCtx) => AlertDialog(
            title: const Text("GPS 위치 변경"),
            content: const Text("내 기기의 현재 위치를 이 마커의 위치로 변경하시겠습니까?\n\n※ 앱을 백그라운드로 내리거나 완전히 종료하면 원래 위치로 복구됩니다."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(confirmCtx),
                child: const Text("아니오", style: TextStyle(color: Colors.grey))
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () async {
                  Navigator.pop(confirmCtx);
                  try {
                    await MockLocationPlugin.startMockLocation(d.lat, d.lng, 5.0);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("현재 위치가 마커 좌표로 변경되었습니다!"), backgroundColor: Colors.green)
                      );
                    }
                  } catch (e) {
    debugPrint("GPS 조작 에러: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        // 에러 내용을 화면에 5초 동안 길게 띄워줍니다.
        SnackBar(content: Text("에러 원인: $e"), backgroundColor: Colors.red, duration: const Duration(seconds: 5))
      );
    }
  }
                },
                child: const Text("예", style: TextStyle(color: Colors.white))
              )
            ],
          )
        );
      },
    ),
                      // 기존 다운로드 버튼
                      IconButton(
                        icon: const Icon(Icons.cloud_download, color: Colors.green),
                        onPressed: () => _downloadMarkerPhotos(d),
                        tooltip: "현장 사진 다운로드",
                      ),

                      // 수정/삭제 버튼 (권한 있을 때만)
                      if (fromOtherTeam == null || isAdmin) ...[
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue), 
                          onPressed: () { 
                            Navigator.pop(ctx);
                            _showInputSheet(existingData: d, targetTeamName: targetTeamName); 
                          }
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            _confirmAndDeleteMarker(
                              d,
                              initiatingTeamName: targetTeamName ?? widget.teamName,
                              detailContext: ctx,
                            );
                          },
                        ),
                      ]
                  ],
                )
              ]
            ),
            
            // ... (나머지 상세 정보 표시 - 기존과 동일) ...
            Text(d.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text("📍 ${d.address}", style: const TextStyle(fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.w500)), 
            const SizedBox(height: 8),
            Text(d.description),
            const SizedBox(height: 10),
            
            // ✅ [수정됨] 사진 리스트 부분 (클릭 시 확대 기능 추가)
            if (d.photos.isNotEmpty) 
              SizedBox(
                height: 160, 
                child: ListView.builder(
                  scrollDirection: Axis.horizontal, 
                  itemCount: d.photos.length, 
                  itemBuilder: (ctx, i) {
                    // 1. 현재 사진 데이터 가져오기
                    final photo = d.photos[i];

                    // 2. 터치 감지(GestureDetector)로 감싸서 리턴
                    return GestureDetector(
                      onTap: () => _showEnlargedPhoto(photo.filePath, photo.comment), // 확대 함수 호출
                      child: Container(
                        width: 120, 
                        margin: const EdgeInsets.only(right: 10), 
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8), 
                              child: (kIsWeb || photo.filePath.startsWith('http'))
                                  ? Image.network(photo.filePath, width: 120, height: 100, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.error))
                                  : Image.file(File(photo.filePath), width: 120, height: 100, fit: BoxFit.cover)
                            ), 
                            const SizedBox(height: 5), // 사진과 설명 사이 간격 살짝 추가
                            Text(photo.comment, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center, maxLines: 2)
                          ]
                        )
                      ),
                    );
                  }
                )
              )
          ] // children 닫기
        ) // Column 닫기
      ) // Container 닫기
      )
    ); // showModalBottomSheet 닫기
} // _showMarkerDetails 함수 닫기
  
  Widget _colorSlider(String l, double v, Function(double) o, Color c) => Row(children: [Text(l), Expanded(child: Slider(value: v, min: 0, max: 255, activeColor: c, onChanged: o))]);
  // --- [마커/선 생성 메뉴 팝업] ---
void _showCreateMenu() {
    if (!canManageTeamData) return;

    showModalBottomSheet(
      context: context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_upload, color: Colors.green),
            title: const Text("사진 업로드"),
            subtitle: const Text("날짜별 현장 사진을 Firebase에 보관합니다."),
            onTap: () {
              Navigator.pop(c);
              _showFieldPhotoUploadSheet();
            },
          ),

          // 1. 현재 위치 마커
          ListTile(
            leading: const Icon(Icons.gps_fixed, color: Colors.blue),
            title: const Text("현재 위치에 마커 생성"),
            onTap: () async {
              // 🛡️ 1. 지도 터치 잠금 (클릭 뚫림 방지)
              setState(() {
                _clearTemporaryMapModes();
                _isMapControlActive = false;
              });
              _setMarkerMoveModeOnKakaoMap(false);
              
              Navigator.pop(c);
              
              try {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("현재 위치를 찾는 중..."), duration: Duration(milliseconds: 800)));
                Position p = await Geolocator.getCurrentPosition();
                
                // 🛡️ 2. 잠금 해제 (창 띄우기 직전)
                if (mounted) setState(() => _isMapControlActive = true);
                
                _showInputSheet(newPoint: LatLng(p.latitude, p.longitude));
              } catch (e) {
                if (mounted) setState(() => _isMapControlActive = true); // 에러 나도 잠금 해제
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("위치 찾기 실패: $e")));
              }
            },
          ),
          
          // 2. 지도 터치 마커
          ListTile(
            leading: const Icon(Icons.touch_app, color: Colors.orange),
            title: const Text("지도 터치해서 마커 생성"),
            onTap: () async {
              // 🛡️ 1. 지도 터치 잠금
              setState(() => _isMapControlActive = false);
              
              Navigator.pop(c);
              
              // 🛡️ 2. 메뉴가 사라질 때까지 충분히 대기 (0.5초)
              await Future.delayed(const Duration(milliseconds: 500));
              
              // 🛡️ 3. 모드 켜면서 지도 잠금 해제
              if (mounted) {
                _enterMarkerCreateMode();
              }
            },
          ),
          
          // 3. 선 그리기 (선택 팝업)
          ListTile(
            leading: const Icon(Icons.timeline, color: Colors.green),
            title: const Text("선 그리기 (라인 작업)"),
            onTap: () {
              Navigator.pop(c); // 바텀시트 닫고
              
              // 선택 다이얼로그 호출
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("선 그리기 방식 선택"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 3-A. 마커끼리 연결
                      ListTile(
                        leading: const Icon(Icons.hub, color: Colors.purple),
                        title: const Text("마커끼리 연결"),
                        subtitle: const Text("기존 마커들을 순서대로 터치"),
                        onTap: () async {
                          // 🛡️ 1. 지도 잠금
                          setState(() => _isMapControlActive = false);
                          
                          Navigator.pop(ctx);
                          
                          // 🛡️ 2. 대기
                          await Future.delayed(const Duration(milliseconds: 500));
                          
                          // 🛡️ 3. 잠금 해제 및 모드 활성화
                          if (mounted) {
                            setState(() { 
                              _clearTemporaryMapModes();
                              _isLineMode = true; 
                              _isMapControlActive = true;
                            });
                            _setMarkerMoveModeOnKakaoMap(false);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("연결할 마커들을 순서대로 터치하세요.")));
                          }
                        },
                      ),
                      
                      // 3-B. 지도에 직접 긋기 (여기가 문제였음!)
                      ListTile(
                        leading: const Icon(Icons.draw, color: Colors.redAccent),
                        title: const Text("지도에 직접 긋기"),
                        subtitle: const Text("지도 빈 곳을 자유롭게 터치"),
                        onTap: () async {
                          // 🛡️ 1. 지도 잠금 (이게 핵심!)
                          setState(() => _isMapControlActive = false);
                          
                          Navigator.pop(ctx); // 팝업 닫기
                          
                          // 🛡️ 2. 팝업이 사라지고 클릭 효과가 끝날 때까지 0.5초 대기
                          await Future.delayed(const Duration(milliseconds: 500));
                          
                          // 🛡️ 3. 이제 안전하니까 지도 잠금 해제 & 그리기 모드 ON
                          if (mounted) {
                            setState(() { 
                              _clearTemporaryMapModes();
                              _isFreeLineMode = true; 
                              _isMapControlActive = true; // 지도 다시 켜기
                            });
                            _setMarkerMoveModeOnKakaoMap(false);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("지도를 터치하여 점을 찍으세요.")));
                          }
                        },
                      ),
                    ],
                  ),
                )
              );
            },
          ),
        if (canUseAdminTools)
        ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.deepPurple),
            title: const Text("AI 탐지 마커 불러오기"),
            subtitle: const Text("웹에서 분석한 데이터를 가져와 팀에 배포합니다."),
            onTap: () {
              Navigator.pop(c); // 바텀시트 닫기
              _showAiImportListDialog(); 
            },
          ),
        ],
      ),
    );
  }

  void _showLineInputSheet({LineData? existingLine, bool isFreeDraw = false, String? targetTeamName}) async {
    final List<LatLng> capturedFreePoints = List.from(_tempFreeLinePoints);
    final List<String> capturedMarkerIds = List.from(_tempLineMarkerIds);

    setState(() {
      _frozenFreeLinePoints = List.from(_tempFreeLinePoints);
      _tempFreeLinePoints.clear();
      _isModalOpen = true; 
      _isMapControlActive = false;
      _isFreeLineMode = false;  
      _isLineMode = false;
    });

    TextEditingController tCtrl = TextEditingController(text: existingLine?.title ?? "");
    TextEditingController dCtrl = TextEditingController(text: existingLine?.description ?? "");
    Color selectedColor = existingLine != null ? Color(existingLine.colorValue) : Colors.blue;
    
    List<String> selectedTargetTeams = [widget.teamName];
    final List<Color> palette = [
      Colors.red, Colors.orange, Colors.amber, Colors.green, Colors.teal, 
      Colors.blue, Colors.indigo, Colors.purple, Colors.brown, Colors.black
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 🛑 [핵심 2] 바깥 배경을 아예 반투명하게 만들어 시스템 단에서 터치 흡수
      barrierColor: Colors.black.withOpacity(0.5), 
      backgroundColor: Colors.transparent, 
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom, 
          ),
          child: PointerInterceptor(
            // 🛑 [핵심 3] 설정창 본체만 감싸서 깔끔하게 차단
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(existingLine == null ? "새 선 생성" : "선 정보 수정", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  
                  if (isAdmin && existingLine == null) ...[
                    const SizedBox(height: 15),
                    const Align(
                      alignment: Alignment.centerLeft, 
                      child: Text("전송할 팀 선택 (다중 선택 가능)", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))
                    ),
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: [widget.teamName, ..._allTeamsMap.keys].map((teamName) {
                          bool isSelected = selectedTargetTeams.contains(teamName);
                          return FilterChip(
                            label: Text(teamName == widget.teamName ? "내 팀" : teamName),
                            selected: isSelected,
                            selectedColor: Colors.blueAccent.withOpacity(0.3),
                            checkmarkColor: Colors.blueAccent,
                            onSelected: (bool selected) {
                              // ❌ 지도를 뒤흔들던 메인 setState 제거하고 모달 내부 상태만 변경!
                              setSheet(() {
                                if (selected) {
                                  selectedTargetTeams.add(teamName);
                                } else {
                                  if (selectedTargetTeams.length > 1) { 
                                    selectedTargetTeams.remove(teamName);
                                  }
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  TextField(controller: tCtrl, decoration: const InputDecoration(labelText: "선 이름")),
                  TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "설명")),
                  const SizedBox(height: 15),
                  
                  const Align(alignment: Alignment.centerLeft, child: Text("선 색상", style: TextStyle(color: Colors.grey, fontSize: 12))),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    // ❌ 지도를 뒤흔들던 _uiBlocker 완벽 제거!
                    children: palette.map((c) => GestureDetector(
                      onTap: () => setSheet(() => selectedColor = c),
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: c, 
                          shape: BoxShape.circle,
                          border: selectedColor.value == c.value ? Border.all(color: Colors.black, width: 2) : null
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: () async {
                      final id = existingLine?.id ?? DateTime.now().toString();
                      List<LatLng> pts;
                      if (existingLine != null) {
                        pts = existingLine.points;
                      } else if (isFreeDraw) {
                        pts = capturedFreePoints;
                      } else {
                        pts = capturedMarkerIds.map((mid) => _markerDataMap[mid]!.position).toList();
                      }

                      LineData newLine = LineData(
                        id: id, title: tCtrl.text, description: dCtrl.text,
                        points: pts,
                        markerIds: existingLine?.markerIds ?? (isFreeDraw ? [] : List.from(_tempLineMarkerIds)),
                        colorValue: selectedColor.value,
                        isVisible: existingLine?.isVisible ?? true,
                        canonicalLineId: existingLine?.canonicalLineId ?? existingLine?.originalLineId ?? existingLine?.sourceLineId ?? existingLine?.parentLineId ?? id,
                        originalLineId: existingLine?.originalLineId ?? existingLine?.canonicalLineId ?? existingLine?.sourceLineId ?? existingLine?.parentLineId ?? id,
                        sourceLineId: existingLine?.sourceLineId ?? existingLine?.canonicalLineId ?? existingLine?.originalLineId ?? existingLine?.parentLineId ?? id,
                        parentLineId: existingLine?.parentLineId ?? existingLine?.canonicalLineId ?? existingLine?.originalLineId ?? existingLine?.sourceLineId ?? id,
                      );
                      Navigator.pop(ctx); 

                      if (isAdmin && existingLine == null) {
                        for (String targetTeam in selectedTargetTeams) {
                          if (targetTeam == widget.teamName) {
                            setState(() { _lineDataMap[id] = newLine; });
                            _invalidateLineRenderHash();
                            _scheduleMarkerUpdate(ms: 0);
                            _saveData();
                          } else {
                            try {
                              var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeam);
                              var snap = await docRef.get();
                              if (snap.exists) {
                                await _upsertLineInTeamDoc(targetTeam, newLine, addIfMissing: true);
                              }
                            } catch (e) {
                              debugPrint("타 팀 저장 실패 ($targetTeam): $e");
                            }
                          }
                        }
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("총 ${selectedTargetTeams.length}개 팀에 선을 전송했습니다.")));
                        setState(() {
                          _isLineMode = false;
                          _isFreeLineMode = false;
                          _tempLineMarkerIds.clear();
                          _tempFreeLinePoints.clear();
                        });
                      } else if (existingLine != null && targetTeamName != null) {
                        await _upsertLineInTeamDoc(targetTeamName, newLine, addIfMissing: false);
                        setState(() {
                          _allTeamsMap[targetTeamName]?.lines[id] = newLine;
                          _isLineMode = false;
                          _isFreeLineMode = false;
                          _tempLineMarkerIds.clear();
                          _tempFreeLinePoints.clear();
                        });
                        _scheduleMarkerUpdate(ms: 0);
                      } else {
                        setState(() {
                          _lineDataMap[id] = newLine;
                          _isLineMode = false;
                          _isFreeLineMode = false;
                          _tempLineMarkerIds.clear();
                          _tempFreeLinePoints.clear();
                        });
                        _invalidateLineRenderHash();
                        _scheduleMarkerUpdate(ms: 0);
                        await _saveData();
                        if (isAdmin && existingLine != null) {
                          await _updateDistributedLine(newLine);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Colors.green),
                    child: const Text("저장 완료", style: TextStyle(color: Colors.white)),
                  )
                ],
              ), 
            ), 
          ), 
        ), 
      ), 
    );

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _isModalOpen = false;
        _isMapControlActive = true;
        _frozenFreeLinePoints.clear();
      });
    }
  }
  
  
    // --- [선 상세 정보 보기] ---
  void _showLineDetails(String lid) {
    final d = _lineDataMap[lid]!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(d.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
const SizedBox(height: 5),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() => _lineDataMap.remove(lid));
                    _invalidateLineRenderHash();
                    _scheduleMarkerUpdate(ms: 0);
                    _saveData();
                    Navigator.pop(context);
                  },
                )
              ],
            ),
            const Divider(),
            Text(d.description),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

// --- [사진 개별 다운로드 함수: 갤러리(DCIM) 저장 버전] ---
Future<void> _downloadMarkerPhotos(SiteData d) async {
  if (d.photos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("다운로드할 사진이 없습니다.")));
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사진 다운로드를 시작합니다...")));
  int successCount = 0;

  // 안드로이드 기본 카메라 폴더 경로
  String cameraFolderPath = '/storage/emulated/0/DCIM/Camera';
  
  if (!kIsWeb && Platform.isAndroid) {
    final directory = Directory(cameraFolderPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  for (var photo in d.photos) {
    try {
      final response = await http.get(Uri.parse(photo.filePath));
      if (response.statusCode != 200) continue;
      final Uint8List bytes = response.bodyBytes;
      
      String fileName = "${d.title}_${DateTime.now().millisecondsSinceEpoch}.jpg";

      if (kIsWeb) {
        web_saver.saveFileWeb(bytes, fileName);
        successCount++;
      } else if (Platform.isAndroid) {
        // 1. 파일 저장
        File file = File("$cameraFolderPath/$fileName");
        await file.writeAsBytes(bytes);
        
        // ✅ 2. [핵심] 갤러리 새로고침(미디어 스캔) 요청
        // 파일이 생성되었으면 시스템에 "이 파일 좀 갤러리에 띄워줘"라고 신호를 보냅니다.
        if (await file.exists()) {
          try {
            await MediaScanner.loadMedia(path: file.path); // 👈 이 코드가 갤러리에 즉시 띄워줍니다.
            successCount++;
          } catch (e) {
            debugPrint("스캔 실패: $e");
            // 스캔이 실패해도 파일은 저장되었으므로 successCount는 올립니다.
            successCount++; 
          }
        }
      }
    } catch (e) {
      debugPrint("다운로드 에러: $e");
    }
  }
  
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$successCount장의 사진이 ${kIsWeb ? '다운로드' : '카메라 앨범에 저장'}되었습니다.")));
  }
}

// ✅ [수정됨] 관리자용: 타 팀의 그룹 삭제 시 마커 + 연결된 선(Line)까지 완벽 제거
  void _deleteOtherTeamGroupDialog(String targetTeamName, MapGroup group) {
    if (!canUseAdminTools) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("협력사 그룹 삭제"),
        content: Text("['$targetTeamName'] 팀의\n'${group.name}' 그룹과\n포함된 모든 마커 및 연결된 선이 삭제됩니다.\n\n정말 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx); // 팝업 닫기
              
              try {
                // 1. 서버에서 해당 팀의 최신 데이터를 가져옴
                var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeamName);
                var snapshot = await docRef.get();

                if (snapshot.exists && snapshot.data() != null) {
                  var data = snapshot.data()!;
                  
                  // 2. 데이터 가져오기 (그룹, 마커, 선)
                  List<dynamic> groups = List.from(data['groups'] ?? []);
                  List<dynamic> markers = List.from(data['markers'] ?? []);
                  List<dynamic> lines = List.from(data['lines'] ?? []);

                  // 3. 삭제 대상 마커 ID 수집 (선 삭제를 위해 미리 ID를 파악)
                  Set<String> deletedMarkerIds = {};
                  
                  // 조건에 맞는 마커를 찾아서 ID를 저장하고, 리스트에서 제거
                  markers.removeWhere((m) {
                    // 데이터 안전성 체크 (group['name']이 없을 경우 대비)
                    String? mGroupName = m['group']?['name'];
                    bool isTarget = mGroupName == group.name;
                    
                    if (isTarget) {
                      deletedMarkerIds.add(m['id']); // 삭제될 마커의 ID 기록
                    }
                    return isTarget;
                  });

                  // 4. 그룹 리스트에서 해당 그룹 제거
                  groups.removeWhere((g) => g['name'] == group.name);

                  // 5. 선(Line) 데이터 정리
                  // 삭제된 마커 ID를 포함하고 있는 선들을 찾아 점을 제거하거나 선 자체를 삭제
                  if (deletedMarkerIds.isNotEmpty) {
                    for (int i = lines.length - 1; i >= 0; i--) {
                      var line = lines[i];
                      List<dynamic> mIds = List.from(line['markerIds'] ?? []);
                      List<dynamic> pts = List.from(line['points'] ?? []);
                      
                      bool lineChanged = false;

                      // 선을 구성하는 점들을 뒤에서부터 확인하며 삭제된 마커와 연결된 점 제거
                      for (int j = mIds.length - 1; j >= 0; j--) {
                        if (deletedMarkerIds.contains(mIds[j])) {
                          mIds.removeAt(j);
                          if (j < pts.length) pts.removeAt(j); // 점 좌표도 함께 제거
                          lineChanged = true;
                        }
                      }
                      
                      // 점이 2개 미만 남으면 선 자체를 삭제 (선으로서 의미 없음)
                      if (mIds.length < 2) {
                        lines.removeAt(i);
                      } else if (lineChanged) {
                        // 점이 삭제되었지만 선이 남아있다면 업데이트
                        line['markerIds'] = mIds;
                        line['points'] = pts;
                        lines[i] = line;
                      }
                    }
                  }

                  // 6. 서버에 수정된 데이터 덮어쓰기 (그룹, 마커, 선 모두 업데이트)
                  await docRef.update({
                    'groups': groups,
                    'markers': markers,
                    'lines': lines,
                  });
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("그룹과 관련 데이터가 모두 삭제되었습니다."))
                    );
                  }
                }
              } catch (e) {
                debugPrint("타 팀 그룹 삭제 중 오류: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("삭제 실패: $e"))
                  );
                }
              }
            },
            child: const Text("삭제", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  // ✅ [2] 내 그룹 삭제 함수 (별도로 존재해야 함)
  Future<Map<String, int>> _commitAppGroupDeletion({
    required MapGroup group,
    required List<SiteData> sourceMarkers,
  }) async {
    final sourceDocId = widget.teamName;
    final sourceIds = _sourceIdsFromMarkers(sourceMarkers);
    final snapshot = await FirebaseFirestore.instance.collection('teams').get();
    final batch = FirebaseFirestore.instance.batch();
    var writes = 0;
    var removedGroups = 0;
    var removedMarkers = 0;
    var changedLines = 0;

    for (final doc in snapshot.docs) {
      final isSourceDoc = doc.id == sourceDocId;
      final data = doc.data();
      final groups = List<dynamic>.from(data['groups'] ?? const []);
      final markers = List<dynamic>.from(data['markers'] ?? const []);
      final lines = List<dynamic>.from(data['lines'] ?? const []);
      final nextMarkers = <dynamic>[];
      final deletedIds = <String>{};
      var markersChanged = false;

      for (final rawMarker in markers) {
        if (rawMarker is! Map) {
          nextMarkers.add(rawMarker);
          continue;
        }

        final marker = Map<String, dynamic>.from(rawMarker);
        final shouldDelete = isSourceDoc
            ? _rawMarkerInGroup(marker, group)
            : sourceIds.isNotEmpty && _markerHasSourceId(marker, sourceIds);

        if (!shouldDelete) {
          nextMarkers.add(rawMarker);
          continue;
        }

        deletedIds.addAll(_deletedMarkerIdsFromRaw(marker));
        removedMarkers++;
        markersChanged = true;
      }

      if (deletedIds.isNotEmpty || sourceIds.isNotEmpty) {
        for (final rawLine in lines) {
          if (rawLine is! Map) continue;
          final markerIds = List<dynamic>.from(rawLine['markerIds'] ?? const []);
          for (final markerId in markerIds) {
            final cleaned = _cleanMarkerId(markerId);
            if (cleaned.isEmpty) continue;
            if (deletedIds.contains(cleaned) || sourceIds.contains(cleaned)) {
              deletedIds.add(cleaned);
            }
          }
        }
      }

      final lineResult = _removeDeletedMarkerPointsFromLinesJson(lines, deletedIds);
      final linesChanged = lineResult['changed'] == true;
      if (linesChanged) {
        changedLines += lineResult['changedLineCount'] as int? ?? 0;
      }

      final nextGroups = <dynamic>[];
      var groupsChanged = false;
      for (final rawGroup in groups) {
        final isTargetGroup = _groupMatchesTarget(rawGroup, group);
        final shouldRemoveGroup = isTargetGroup &&
            (isSourceDoc ||
                (markersChanged && !_rawGroupHasRemainingMarkers(nextMarkers, group)));

        if (shouldRemoveGroup) {
          removedGroups++;
          groupsChanged = true;
          continue;
        }

        nextGroups.add(rawGroup);
      }

      if (!groupsChanged && !markersChanged && !linesChanged) continue;
      if (writes >= 450) {
        throw StateError('APP_GROUP_DELETE_TOO_MANY_DOCS');
      }

      batch.update(doc.reference, {
        'groups': nextGroups,
        if (markersChanged) 'markers': nextMarkers,
        if (linesChanged) 'lines': lineResult['lines'],
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      writes++;
    }

    if (writes > 0) {
      await batch.commit();
    }

    return {
      'writes': writes,
      'removedGroups': removedGroups,
      'removedMarkers': removedMarkers,
      'changedLines': changedLines,
    };
  }

  void _applyAppGroupDeletionLocally({
    required MapGroup group,
    required List<SiteData> sourceMarkers,
  }) {
    final sourceIds = _sourceIdsFromMarkers(sourceMarkers);

    setState(() {
      final ownDeletedIds = <String>{};

      for (final entry in _markerDataMap.entries.toList()) {
        if (!_groupMatchesTarget(entry.value, group)) continue;
        ownDeletedIds.addAll(_deletedMarkerIdsFromSite(entry.value));
        _markerDataMap.remove(entry.key);
      }

      _userGroups.removeWhere((candidate) => _groupMatchesTarget(candidate, group));
      _removeDeletedMarkerPointsFromLineMap(_lineDataMap, ownDeletedIds);

      if (_quickSelectedGroupName == group.name) {
        _quickSelectedGroupName = null;
        _quickGroupMode = 0;
      }
      if (_lastSelectedGroupName == group.name) {
        _lastSelectedGroupName = null;
      }

      for (final teamEntry in _allTeamsMap.entries) {
        final team = teamEntry.value;
        final teamDeletedIds = <String>{};

        for (final markerEntry in team.markers.entries.toList()) {
          final marker = markerEntry.value;
          if (sourceIds.isEmpty || !_markerHasSourceId(marker, sourceIds)) continue;
          teamDeletedIds.addAll(_deletedMarkerIdsFromSite(marker));
          team.markers.remove(markerEntry.key);
        }

        if (teamDeletedIds.isNotEmpty) {
          team.groups.removeWhere(
            (candidate) =>
                _groupMatchesTarget(candidate, group) &&
                !team.markers.values.any((marker) => _groupMatchesTarget(marker, group)),
          );
          _removeDeletedMarkerPointsFromLineMap(team.lines, teamDeletedIds);
        }
      }

      _selectedLineIds.removeWhere((id) => !_lineDataMap.containsKey(id));
    });

    _invalidateMarkerRenderHash();
    _invalidateLineRenderHash();
    _scheduleMarkerUpdate(ms: 0);
  }

  Future<void> _persistLocalTeamCacheOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_sKey}_g', jsonEncode(_userGroups.map((g) => g.toJson()).toList()));
    await prefs.setString('${_sKey}_m', jsonEncode(_markerDataMap.values.map((m) => m.toJson()).toList()));
    await prefs.setString('${_sKey}_l', jsonEncode(_lineDataMap.values.map((l) => l.toJson()).toList()));
  }

  Future<void> _deleteGroupDialog(MapGroup group) async {
    final sourceMarkers =
        _markerDataMap.values.where((marker) => _groupMatchesTarget(marker, group)).toList();
    final markerCount = sourceMarkers.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("그룹 삭제 확인"),
        content: Text(
          "이 그룹을 삭제할까요?\n"
          "그룹 안의 마커 $markerCount개도 함께 삭제됩니다.\n"
          "삭제 후 복구할 수 없습니다.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("삭제", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final teamName = widget.teamName;
    debugPrint('[APP_GROUP_DELETE_START] team=$teamName group=${group.name} markerCount=$markerCount');

    setState(() {
      _isGlobalProcessing = true;
      _processingText = "그룹 삭제 중...";
    });

    try {
      final result = await _commitAppGroupDeletion(
        group: group,
        sourceMarkers: sourceMarkers,
      );

      if (result['writes'] == 0) {
        throw StateError('삭제할 그룹을 찾을 수 없습니다.');
      }

      if (!mounted) return;
      _applyAppGroupDeletionLocally(
        group: group,
        sourceMarkers: sourceMarkers,
      );
      await _persistLocalTeamCacheOnly();

      debugPrint(
        '[APP_GROUP_DELETE_DONE] team=$teamName group=${group.name} '
        'removedMarkers=${result['removedMarkers']} docs=${result['writes']} '
        'changedLines=${result['changedLines']}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("'${group.name}' 그룹과 마커 ${result['removedMarkers']}개를 삭제했습니다."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('[APP_GROUP_DELETE_FAILED] team=$teamName group=${group.name} error=$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("그룹 삭제 실패: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGlobalProcessing = false;
          _processingText = "";
        });
      }
    }
  }



// ✅ [최종 수정] 번호 자동 숨김 (한 장일 땐 숫자 X) + 파일명 규칙 완벽 적용
  Future<void> _downloadGroupPhotosWeb(String teamName, MapGroup group) async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("이 기능은 웹에서만 사용 가능합니다."))
      );
      return;
    }

    TeamData? targetTeam = _allTeamsMap[teamName];
    if (targetTeam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("팀 데이터를 찾을 수 없습니다."))
      );
      return;
    }

    List<SiteData> markers = targetTeam.markers.values
        .where((m) => m.group.name == group.name)
        .toList();

    if (markers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("다운로드할 사진이 없습니다."))
      );
      return;
    }

    // 1. 다운로드 방식 선택 팝업
    String? mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("다운로드 방식 선택"),
        content: const Text("사진을 어떻게 저장하시겠습니까?"),
        actions: [
          // 1) 분할
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 'split'),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("분할 다운로드", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("(맨홀별 폴더 생성)", style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
          // 2) 일괄 (마커번호) 주소)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 'bulk'),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("일괄 다운로드", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("(마커번호) 주소)", style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
          // 3) 측정 (마커번호) 주소 - 내용)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 'measure'),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("측정 다운로드", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("(번호) 주소 - 내용)", style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );

    if (mode == null) return; 

    setState(() {
      _isGlobalProcessing = true;
      _processingText = "사진 다운로드 준비 중... (${markers.length}개 포인트)";
    });

    try {
      final archive = Archive();
      int photoCount = 0;
      int processedMarkers = 0;
      int chunkSize = 5; 
      
      for (int i = 0; i < markers.length; i += chunkSize) {
        int end = (i + chunkSize < markers.length) ? i + chunkSize : markers.length;
        List<SiteData> batch = markers.sublist(i, end);

        if (mounted) {
            setState(() => _processingText = "다운로드 중... ($processedMarkers / ${markers.length} 지점 완료)");
        }

        await Future.wait(batch.map((marker) async {
            if (marker.photos.isEmpty) return;

            final regExp = RegExp(r'[<>:"/\\|?*]');
            String safeAddress = marker.address.replaceAll(regExp, '_');
            String safeTitle = marker.title.replaceAll(regExp, '_');
            
            // ✅ [핵심] 사진이 2장 이상일 때만 번호를 붙이기 위한 조건 확인
            bool hasMultiplePhotos = marker.photos.length > 1;

            for (int j = 0; j < marker.photos.length; j++) {
                var photo = marker.photos[j];
                try {
                    final response = await http.get(Uri.parse(photo.filePath));
                    if (response.statusCode == 200) {
                        final Uint8List photoBytes = response.bodyBytes;
                        
                        String fileName;
                        String zipPath;
                        String safeComment = photo.comment.replaceAll(regExp, '_');
                        if (safeComment.isEmpty) safeComment = "사진";

                        // ✅ [스마트 접미사] 여러 장이면 _1, _2 붙이고, 한 장이면 안 붙임
                        String suffix = hasMultiplePhotos ? "_${j+1}" : "";

                        if (mode == 'bulk') {
                          // [일괄] 마커번호) 주소.jpg (한 장일 때 깔끔!)
                          fileName = "$safeTitle) $safeAddress$suffix.jpg";
                          zipPath = "${teamName}_${group.name}_일괄/$fileName";

                        } else if (mode == 'measure') {
                          // [측정] 마커번호) 주소 - 내용.jpg
                          fileName = "$safeTitle) $safeAddress - $safeComment$suffix.jpg";
                          zipPath = "${teamName}_${group.name}_측정/$fileName";

                        } else {
                          // [분할] 기존 방식
                          String folderName = "${safeTitle}_${safeAddress}";
                          fileName = "${safeComment}_${j+1}.jpg";
                          zipPath = "${teamName}_${group.name}/$folderName/$fileName";
                        }
                        
                        archive.addFile(ArchiveFile(zipPath, photoBytes.length, photoBytes));
                        photoCount++;
                    }
                } catch (e) {
                    debugPrint("사진 다운로드 실패: ${photo.filePath}");
                }
            }
        }));
        processedMarkers += batch.length;
      }

      if (photoCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("다운로드 가능한 사진이 없습니다."))
          );
        }
        return;
      }

      if (mounted) setState(() => _processingText = "ZIP 파일 압축 중...");
      
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) throw Exception("ZIP 생성 실패");

      String zipName;
      if (mode == 'bulk') zipName = '${teamName}_${group.name}_일괄모음.zip';
      else if (mode == 'measure') zipName = '${teamName}_${group.name}_측정모음.zip';
      else zipName = '${teamName}_${group.name}_분할모음.zip';

      web_saver.saveFileWeb(
        Uint8List.fromList(zipBytes), 
        zipName
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("총 $photoCount장의 사진 다운로드 완료!"))
        );
      }

    } catch (e) {
      debugPrint("다운로드 실패: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류: $e")));
      }
    } finally {
      if (mounted) setState(() => _isGlobalProcessing = false);
    }
  }  
  Future<void> _exportDetailedPdf(MapGroup group) async {
    debugPrint('PDF export is temporarily disabled during Kakao map migration.');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF 기능은 지도 전환 작업 중 임시 비활성화되었습니다.')),
      );
    }
  }

Future<void> _uploadToSpreadsheet(SiteData siteData, {String? targetTeamName}) async {
    if (isAdmin && targetTeamName != null) {
      await _syncToGoogleSheetAdmin(siteData, targetTeamName);
      return;
    }

    await _syncToGoogleSheet(siteData);
  }

Future<void> _syncToGoogleSheet(SiteData site) async {
    String webAppUrl = "https://script.google.com/macros/s/AKfycbw3f4BlSBAplVWVR2rbWKwNf7cEzRBdDRdmnK9D1dr9mg8vGSDeyvcBvvPEb4qv8r6hDg/exec";
    
    debugPrint("🔵 [구글시트] 전송 시작...");

    try {
      final response = await http.post(
        Uri.parse(webAppUrl),
        // ✅ [수정] 웹 전송 성공률을 높이기 위해 헤더를 최소화합니다.
        headers: {
          "Content-Type": "text/plain", 
          // "Accept": "application/json"  <-- 이 줄을 지웠습니다 (보안 차단 방지)
        },
        body: jsonEncode({
            "teamName": widget.teamName, 
            "id": site.id,
            "groupName": site.group.name,
            "title": site.title,
            "description": site.description,
            "address": site.address,
            "lat": site.lat,
            "lng": site.lng,
            "isChecked": site.isChecked, // ✅ 현재 온오프 상태 추가
            "photos": site.photos.map((p) => {
              "url": p.filePath,
              "comment": p.comment
            }).toList(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 400) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ 구글 시트 저장 완료"), backgroundColor: Colors.green)
          );
        }
        debugPrint("✅ [구글시트] 성공!");
      } else {
        debugPrint("❌ [구글시트] 실패: ${response.statusCode} / ${response.body}");
      }
    } catch (e) {
      debugPrint("🔴 [구글시트] 전송 실패: $e");
    }
  }
Future<void> _syncToGoogleSheetAdmin(SiteData site, String targetTeamName) async {
    String webAppUrl = "https://script.google.com/macros/s/AKfycbw3f4BlSBAplVWVR2rbWKwNf7cEzRBdDRdmnK9D1dr9mg8vGSDeyvcBvvPEb4qv8r6hDg/exec";
    debugPrint("🔵 [관리자] $targetTeamName 팀 시트로 전송 시도...");

    try {
      final response = await http.post(
        Uri.parse(webAppUrl),
        headers: {
            "Content-Type": "text/plain", 
        },
        body: jsonEncode({
            "teamName": targetTeamName,
            "id": site.id, 
            "groupName": site.group.name,
            "title": site.title, 
            "description": site.description,
            "address": site.address,
            "lat": site.lat,
            "lng": site.lng,
            "isChecked": site.isChecked, // ✅ 현재 온오프 상태 추가
            "photos": site.photos.map((p) => {
              "url": p.filePath,
              "comment": p.comment
            }).toList(),
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 400) {
        debugPrint("✅ [관리자] 전송 성공");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("✅ [$targetTeamName] 시트 업데이트 완료"), backgroundColor: Colors.green)
           );
        }
      } else {
        debugPrint("❌ [관리자] 실패: ${response.statusCode} / ${response.body}");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("⚠️ 저장 실패 (${response.statusCode})"), backgroundColor: Colors.red)
           );
        }
      }
    } catch (e) {
      debugPrint("🔴 [관리자] 오류: $e");
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("전송 오류: $e"), backgroundColor: Colors.red)
         );
      }
    }
  } 

// ✅ [앱/관리자용] 팀명/주소 상단 표시 + 사진 높이 최적화
  Future<void> _exportGroupPdfForAdmin(String teamName, MapGroup group) async {
    debugPrint('Admin PDF export is temporarily disabled during Kakao map migration.');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF 기능은 지도 전환 작업 중 임시 비활성화되었습니다.')),
      );
    }
  }
 void _showEnlargedPhoto(String imagePath, String comment) {
    showDialog(
      context: context, 
      barrierDismissible: true, // 배경 누르면 닫힘fl
      builder: (ctx) => Stack(
        alignment: Alignment.center,
        children: [
          // 1. 검은 배경 (누르면 닫힘)
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              color: Colors.black.withOpacity(0.9),
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          // 2. 사진 및 닫기 버튼
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: kIsWeb || imagePath.startsWith('http')
                      ? Image.network(imagePath, fit: BoxFit.contain)
                      : Image.file(File(imagePath), fit: BoxFit.contain),
                ),
              ),
              if (comment.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 20),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    child: Text(comment, textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
// ===============================================================
  // ⚡ [신규 기능] 아카이브 (타임머신 저장/불러오기) 시스템
  // ===============================================================

  // 1. 아카이브 관리 팝업창
  void _showArchiveManagerDialog(String teamName, List<MapGroup> groups) {
    if (!canUseAdminTools) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.save, color: Colors.amber),
          const SizedBox(width: 10),
          Text("[$teamName] 데이터 보관소"),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("그룹별로 데이터를 '저장'하거나 '불러오기' 할 수 있습니다.\n불러오기를 하면 현재 화면이 저장된 시점으로 즉시 교체됩니다.", 
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 20),
                ...groups.map((g) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    leading: Icon(Icons.layers, color: g.color),
                    title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("서버 아카이브 관리"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 저장 버튼
                        ElevatedButton.icon(
                          icon: const Icon(Icons.cloud_upload, size: 16),
                          label: const Text("저장"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                          onPressed: () => _archiveGroupData(teamName, g),
                        ),
                        const SizedBox(width: 8),
                        // 불러오기 버튼
                        ElevatedButton.icon(
                          icon: const Icon(Icons.cloud_download, size: 16),
                          label: const Text("불러오기"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                          onPressed: () => _loadArchiveData(teamName, g, ctx),
                        ),
                      ],
                    ),
                  ),
                )).toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기")),
        ],
      ),
    );
  }

// ✅ [최종 수정] 아카이브 삭제 기능(영구 삭제 확인 포함) 추가된 통합 관리 창
  void _showGlobalArchiveDialog() {
    if (!canUseAdminTools) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.save, color: Colors.amber),
          SizedBox(width: 10),
          Text("데이터 보관소 (아카이브)"),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text("원하는 그룹을 저장/복구하거나, 불필요한 데이터는 영구 삭제하세요.\n'불러오기' 시 현재 화면은 해당 시점으로 덮어씌워집니다.", 
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _allTeamsMap.isEmpty 
                    ? [const Padding(padding: EdgeInsets.all(20), child: Text("협력사 데이터가 없습니다."))]
                    : _allTeamsMap.entries.map((entry) {
                        String teamName = entry.key;
                        TeamData team = entry.value;
                      
                        return ExpansionTile(
                          initiallyExpanded: false,
                          leading: const Icon(Icons.folder_shared, color: Colors.blueGrey),
                          title: Text(teamName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          
                          children: [
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('teams').doc(teamName)
                                  .collection('archives').snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const LinearProgressIndicator();

                                // 1. 현재 살아있는 그룹 목록 (Live)
                                Map<String, MapGroup> liveGroups = { for(var g in team.groups) g.name : g };
                                
                                // 2. 아카이브에 저장된 그룹 목록 (Saved)
                                var archiveDocs = snapshot.data!.docs;
                                Set<String> allGroupNames = liveGroups.keys.toSet();
                                allGroupNames.addAll(archiveDocs.map((d) => d.id)); 

                                return Column(
                                  children: allGroupNames.map((gName) {
                                    MapGroup? liveGroup = liveGroups[gName];
                                    
                                    var archiveDoc = archiveDocs
                                        .where((d) => d.id == gName)
                                        .firstOrNull;
                                    
                                    bool isLive = (liveGroup != null);
                                    bool hasArchive = (archiveDoc != null);
                                    
                                    int colorVal = Colors.grey.value;
                                    if (isLive) {
                                      colorVal = liveGroup.colorValue;
                                    } else if (hasArchive && archiveDoc.data() is Map) {
                                      var d = archiveDoc.data() as Map;
                                      if (d.containsKey('colorValue')) colorVal = d['colorValue'];
                                    }
                                    
                                    MapGroup targetGroup = liveGroup ?? MapGroup(name: gName, colorValue: colorVal);

                                    return Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      color: isLive ? Colors.white : Colors.red[50],
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
                                        leading: Icon(Icons.layers, color: Color(colorVal)),
                                        title: Text(
                                          gName + (!isLive ? " (삭제됨)" : ""),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 14,
                                            color: !isLive ? Colors.red : Colors.black
                                          )
                                        ),
                                        subtitle: hasArchive 
                                            ? Text("저장됨: ${_formatDate(archiveDoc?['savedAt'])}") 
                                            : const Text("저장본 없음"),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // [저장 버튼]
                                            if (isLive)
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                                                onPressed: () => _archiveGroupData(teamName, targetGroup),
                                                child: const Text("저장"),
                                              ),
                                            
                                            const SizedBox(width: 8),
                                            
                                            // [불러오기 버튼]
                                            if (hasArchive)
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10)),
                                                onPressed: () => _loadArchiveData(teamName, targetGroup, ctx), 
                                                child: const Text("복구"),
                                              ),

                                            // ✅ [추가됨] 영구 삭제 버튼 (휴지통 아이콘)
                                            if (hasArchive)
                                              IconButton(
                                                icon: const Icon(Icons.delete_forever, color: Colors.red),
                                                tooltip: "아카이브 영구 삭제",
                                                onPressed: () {
                                                  // 삭제 확인 팝업 호출
                                                  showDialog(
                                                    context: context,
                                                    builder: (delCtx) => AlertDialog(
                                                      title: const Text("영구 삭제 확인"),
                                                      content: Text("['$teamName'] 팀의 보관된 데이터 ['$gName']을(를) 삭제하시겠습니까?\n\n⚠️ 이 작업은 되돌릴 수 없습니다."),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(delCtx),
                                                          child: const Text("취소"),
                                                        ),
                                                        ElevatedButton(
                                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                          onPressed: () async {
                                                            Navigator.pop(delCtx); // 팝업 닫기
                                                            
                                                            // 실제 삭제 수행
                                                            await FirebaseFirestore.instance
                                                                .collection('teams').doc(teamName)
                                                                .collection('archives').doc(gName)
                                                                .delete();
                                                            
                                                            if (mounted) {
                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                const SnackBar(content: Text("보관된 데이터가 영구 삭제되었습니다."))
                                                              );
                                                            }
                                                          },
                                                          child: const Text("삭제", style: TextStyle(color: Colors.white)),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              }
                            )
                          ], 
                        );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기")),
        ],
      ),
    );
  }
  // 2. 그룹 데이터 저장 (타입 캐스팅 오류 해결)
  Future<void> _archiveGroupData(String teamName, MapGroup group) async {
    if (!canUseAdminTools) return;

    // 1) 팀 데이터 확인
    if (!_allTeamsMap.containsKey(teamName)) return;
    var teamData = _allTeamsMap[teamName];
    if (teamData == null) return;

    // 2) 저장할 마커 필터링
    var markersToSave = teamData.markers.values.where((m) => m.group.name == group.name).toList();
    
    // 3) 확인 팝업
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("현재 상태 저장"),
        content: Text("팀: $teamName\n그룹: ${group.name}\n마커: ${markersToSave.length}개\n\n현재 데이터를 아카이브에 저장하시겠습니까?\n(이전 저장 내역은 덮어씌워집니다.)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("취소")),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text("저장하기")),
        ],
      )
    );

    if (confirm != true) return;

    try {
      var archiveRef = FirebaseFirestore.instance
          .collection('teams').doc(teamName)
          .collection('archives').doc(group.name);

      await archiveRef.set({
        'groupName': group.name,
        'colorValue': group.colorValue,
        'savedAt': FieldValue.serverTimestamp(),
        'markerCount': markersToSave.length,
        'markers': markersToSave.map((m) => m.toJson()).toList(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ [${group.name}] 데이터 저장 완료")));
      }
    } catch (e) {
      debugPrint("저장 실패: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("저장 실패: $e")));
    }
  }

 // 3. 그룹 데이터 불러오기 (복구 기능 - 그룹 삭제 시 재생성 로직 포함)
  Future<void> _loadArchiveData(String teamName, MapGroup group, BuildContext dialogCtx) async {
    if (!canUseAdminTools) return;

    // 1) 경고 팝업
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("데이터 불러오기 (복구)"),
        content: Text("⚠️ 주의: [${group.name}] 그룹의 현재 화면 데이터가 모두 지워지고, 마지막 저장 시점으로 복구됩니다.\n\n연결된 모든 팀장의 앱 화면도 즉시 변경됩니다.\n계속하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text("복구 실행")
          ),
        ],
      )
    );
    if (confirm != true) return;
    
    try {
      Navigator.pop(dialogCtx); // 아카이브 목록 팝업 닫기
    } catch (e) {}

    setState(() { _isGlobalProcessing = true; _processingText = "데이터 복구 및 동기화 중..."; });
    
    try {
      // 2) 아카이브(저장소) 데이터 가져오기
      var archiveSnap = await FirebaseFirestore.instance
          .collection('teams').doc(teamName)
          .collection('archives').doc(group.name)
          .get();

      if (!archiveSnap.exists || archiveSnap.data() == null) {
        throw Exception("저장된 데이터가 없습니다.");
      }

      Map<String, dynamic> archiveData = Map<String, dynamic>.from(archiveSnap.data() as Map);
      List<dynamic> savedMarkersJson = archiveData['markers'] ?? [];
      
      // 3) 라이브 서버 데이터 교체 (트랜잭션 시작)
      var liveRef = FirebaseFirestore.instance.collection('teams').doc(teamName);
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        var liveSnap = await transaction.get(liveRef);
        if (!liveSnap.exists) throw Exception("팀 데이터 없음");
        
        Map<String, dynamic> liveData = Map<String, dynamic>.from(liveSnap.data() as Map);
        
        // ✅ [수정] 여기서 currentGroups를 확실하게 선언합니다.
        List<dynamic> currentMarkers = List.from(liveData['markers'] ?? []);
        List<dynamic> currentGroups = List.from(liveData['groups'] ?? []); 

        // (A) 현재 라이브 데이터에서 해당 그룹의 마커들을 싹 지움 (중복 방지)
        currentMarkers.removeWhere((m) {
             if (m is Map && m['group'] is Map) {
               return m['group']['name'].toString() == group.name;
            }
            return false;
        });
        
        // (B) 아카이브에 있던 마커들을 다시 추가
        currentMarkers.addAll(savedMarkersJson);
        
        // (C) ⭐ 만약 그룹(폴더) 자체가 삭제되어 리스트에 없다면, 다시 생성해서 넣어줌
        bool groupExists = currentGroups.any((g) => g['name'] == group.name);
        
        if (!groupExists) {
           // 저장된 색상 정보가 있으면 쓰고, 없으면 현재 객체 색상 사용
           int savedColor = group.colorValue; 
           if (archiveData.containsKey('colorValue')) {
             savedColor = archiveData['colorValue'];
           }

           currentGroups.add({
             'name': group.name,
             'colorValue': savedColor,
             'isVisible': true
           });
        }
        
        // (D) 최종 업데이트 (마커와 그룹 정보 모두 저장)
        transaction.update(liveRef, {
          'markers': currentMarkers,
          'groups': currentGroups, 
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ [${group.name}] 복구 완료!"))
        );
      }

    } catch (e) {
      debugPrint("불러오기 실패: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("복구 실패: $e")));
    } finally {
      if (mounted) setState(() => _isGlobalProcessing = false);
    }
  }
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "날짜 없음";
    try {
      // 파이어베이스 Timestamp를 DateTime으로 변환
      DateTime date = (timestamp as Timestamp).toDate();
      // "2025-02-03 14:30" 형식으로 반환
      return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} "
             "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "-";
    }
  }
// 1. 선 수정 다이얼로그 함수
  void _editLineDialog(LineData line) {
    _showLineInputSheet(existingLine: line);
  } // 👈 여기서 닫는 괄호가 꼭 있어야 합니다! (함수 끝)

  // 2. 선 목록 아이템 생성 함수 (이제 밖으로 나왔으니 잘 보입니다)
  Widget _buildLineListTile(LineData line, {required bool isMyLine, String? teamName}) {
    final isSelectedLine = _selectedLineIds.contains(line.id);
    final nativeDisplayKey = _nativeLineDisplayKey(line, line.id, teamName: teamName ?? widget.teamName);
    final visibleForThisScreen = _shouldUseNativeKakaoMap
        ? _isNativeLineVisible(nativeDisplayKey, line)
        : line.isVisible;

    return ListTile(
      dense: _isLineDeleteMode,
      contentPadding: EdgeInsets.symmetric(horizontal: _isLineDeleteMode ? 8 : 16),
      leading: _isLineDeleteMode
          ? Checkbox(
              value: isSelectedLine,
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedLineIds.add(line.id);
                  } else {
                    _selectedLineIds.remove(line.id);
                  }
                });
              },
            )
          : Icon(Icons.horizontal_rule, color: Color(line.colorValue)),
      title: Text(
        "${isMyLine ? '' : '[$teamName] '}${line.title}",
        maxLines: _isLineDeleteMode ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        style: TextStyle(color: visibleForThisScreen ? Colors.black : Colors.grey, fontSize: 13),
      ),
      subtitle: Text(line.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      
      trailing: _isLineDeleteMode ? null : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // On/Off 스위치
          Switch(
            value: visibleForThisScreen,
            activeColor: Color(line.colorValue),
            onChanged: (val) async {
              if (_shouldUseNativeKakaoMap) {
                setState(() {
                  _nativeLineVisibilityOverrides[nativeDisplayKey] = val;
                });
                _invalidateLineRenderHash();
                _scheduleMarkerUpdate();
                return;
              }

              setState(() { line.isVisible = val; });
              _invalidateLineRenderHash();
              _scheduleMarkerUpdate();
              
              if (isMyLine) {
                _saveData(); 
              } else if (teamName != null) {
                try {
                  var docRef = FirebaseFirestore.instance.collection('teams').doc(teamName);
                  var snap = await docRef.get();
                  if (snap.exists) {
                    var data = snap.data()!;
                    List<dynamic> lines = List.from(data['lines'] ?? []);
                    int idx = lines.indexWhere((l) => l['id'] == line.id);
                    if (idx != -1) {
                      lines[idx]['isVisible'] = val;
                      await docRef.update({'lines': lines});
                    }
                  }
                } catch (e) { debugPrint("타 팀 선 스위치 에러: $e"); }
              }
            },
          ),

          // 설정 버튼
          IconButton(
            icon: const Icon(Icons.settings, size: 20, color: Colors.grey),
            onPressed: () {
              Navigator.pop(context); 
              _showLineInputSheet(existingLine: line, targetTeamName: isMyLine ? null : teamName); 
            },
          ),

          // 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            onPressed: () {
              showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text("선 삭제"),
                  content: Text(isMyLine 
                    ? "'${line.title}' 선을 삭제하시겠습니까?" 
                    : "['$teamName'] 팀의 '${line.title}' 선을 영구 삭제하시겠습니까?"),
                  actions: [
                    TextButton(onPressed: ()=>Navigator.pop(c), child: const Text("취소")),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        Navigator.pop(c); 
                        
                        if (isMyLine) {
                          setState(() => _lineDataMap.remove(line.id));
                          _invalidateLineRenderHash();
                          _scheduleMarkerUpdate();
                          _saveData();
                        } else if (teamName != null) {
                          try {
                            var docRef = FirebaseFirestore.instance.collection('teams').doc(teamName);
                            var snap = await docRef.get();
                            if (snap.exists) {
                              var data = snap.data()!;
                              List<dynamic> lines = List.from(data['lines'] ?? []);
                              lines.removeWhere((l) => l['id'] == line.id);
                              await docRef.update({'lines': lines});
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("삭제 완료")));
                            }
                          } catch (e) { debugPrint("타 팀 선 삭제 실패: $e"); }
                        }
                        if (mounted) Navigator.pop(context); 
                      }, 
                      child: const Text("삭제", style: TextStyle(color: Colors.white))
                    )
                  ],
                )
              );
            },
          ),
        ],
      ),
      onTap: () async {
        if (_isLineDeleteMode) {
          setState(() {
            if (isSelectedLine) {
              _selectedLineIds.remove(line.id);
            } else {
              _selectedLineIds.add(line.id);
            }
          });
          return;
        }

        if (!visibleForThisScreen) return;
        Navigator.pop(context);
        await _focusLineFromList(line, teamName: teamName ?? widget.teamName);
      },
    );
  }
  // ✅ [신규 추가] 지도 클릭 방지용 강력 방어막 (마우스+터치 모두 방어)
    Widget _uiBlocker(Widget child) {
    return GestureDetector(
      // behavior: HitTestBehavior.opaque가 핵심입니다. 빈 공간의 터치도 모두 흡수합니다.
      behavior: HitTestBehavior.opaque,
      onTap: () {},        // 탭(클릭) 이벤트 흡수
      onPanDown: (_) {},   // 드래그 이벤트 흡수
      child: child,
    );
  }
// ✅ 1. 파이어베이스에 올라간 '하나의 파일'들 목록 보기 (에러 디버깅 강화 버전)
  Future<void> _showAiImportListDialog() async {
    if (!canUseAdminTools) return;

    setState(() { _isGlobalProcessing = true; _processingText = "서버 데이터 조회 중..."; });

    try {
      // 파이어베이스에서 'ai_detected' 컬렉션의 데이터 가져오기
      var snapshot = await FirebaseFirestore.instance.collection('ai_detected').orderBy('createdAt', descending: true).get();
      setState(() => _isGlobalProcessing = false);

      if (snapshot.docs.isEmpty) {
        // 데이터가 없으면 확실하게 팝업으로 알려줌
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("알림"),
              content: const Text("파이어베이스 'ai_detected' 폴더에 업로드된 데이터가 없습니다.\n\n맨홀 탐지 웹에서 [☁️ 전송] 버튼을 눌러 데이터를 먼저 업로드해 주세요."),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))],
            )
          );
        }
        return;
      }

      if (!mounted) return;
      
      // 정상적으로 데이터를 찾았을 때 띄우는 창
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("AI 탐지 그룹 불러오기"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: snapshot.docs.map((doc) {
                var data = doc.data();
                List<dynamic> manholes = data['manholes'] ?? [];
                String gName = data['groupName'] ?? "이름 없음";
                
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.memory, color: Colors.deepPurple),
                    title: Text(gName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("맨홀: ${manholes.length}개"),
                    trailing: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAiTeamSelectionSheet(doc.id, gName, manholes); // 👉 배포할 팀 선택 시트 호출
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                      child: const Text("가져오기"),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기"))],
        ),
      );
    } catch (e) {
      // 🚨 오류 발생 시 팝업으로 상세 원인을 보여줌!
      setState(() => _isGlobalProcessing = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("데이터 조회 에러"),
            content: Text("서버 통신 중 오류가 발생했습니다.\n\n$e"),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))],
          )
        );
      }
    }
  }
  // ✅ 2. 선 그리기 때와 완벽히 동일한 UI! (FilterChip 팀 선택)
  void _showAiTeamSelectionSheet(String aiDocumentId, String aiGroupName, List<dynamic> aiManholes) {
    if (!canUseAdminTools) return;

    List<String> selectedTargetTeams = [widget.teamName]; // 기본값: 내 팀

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.5),
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("데이터 배포: $aiGroupName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("전송할 팀 선택 (다중 선택 가능)", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))
                ),
                const SizedBox(height: 5),
                
                // ⭐ 선 그리기(Line) 때 사용한 바로 그 칩(Chip) UI
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: [widget.teamName, ..._allTeamsMap.keys].map((teamName) {
                      bool isSelected = selectedTargetTeams.contains(teamName);
                      return FilterChip(
                        label: Text(teamName == widget.teamName ? "내 팀" : teamName),
                        selected: isSelected,
                        selectedColor: Colors.deepPurple.withOpacity(0.3),
                        checkmarkColor: Colors.deepPurple,
                        onSelected: (bool selected) {
                          setSheet(() {
                            if (selected) {
                              selectedTargetTeams.add(teamName);
                            } else {
                              if (selectedTargetTeams.length > 1) selectedTargetTeams.remove(teamName);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _distributeAiDataToTeams(selectedTargetTeams, aiDocumentId, aiGroupName, aiManholes);
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Colors.green),
                  child: const Text("배포 완료", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ 3. 선택된 여러 팀에 트랜잭션으로 안전하게 한 번에 꽂아줌
String _safeAiToken(String value) => value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

String _aiCanonicalMarkerId(String aiDocumentId, int index) {
  return 'AI_${_safeAiToken(aiDocumentId)}_${index + 1}';
}

Future<void> _distributeAiDataToTeams(List<String> targetTeams, String aiDocumentId, String aiGroupName, List<dynamic> aiManholes) async {
    if (!canUseAdminTools) return;

    setState(() { _isGlobalProcessing = true; _processingText = "선택한 팀으로 데이터 배포 중..."; });

    try {
      String newGroupName = "AI탐지_$aiGroupName";

      for (String targetTeam in targetTeams) {
        var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeam);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          var snapshot = await transaction.get(docRef);
          if (!snapshot.exists) return; // 팀이 없으면 패스

          var data = snapshot.data()!;
          List<dynamic> markers = List.from(data['markers'] ?? []);
          List<dynamic> groups = List.from(data['groups'] ?? []);

          // 🚨 그룹 추가 (없을 때만) - 색상을 빨간색(Colors.red)으로 지정!
          if (!groups.any((g) => g['name'] == newGroupName)) {
            groups.add({'name': newGroupName, 'colorValue': Colors.red.value, 'isVisible': true});
          }

          // 🚨 마커 데이터 일괄 추가 - 소속 그룹 색상도 빨간색으로 맞춤!
          for (int i = 0; i < aiManholes.length; i++) {
            var m = aiManholes[i];
            final canonicalId = _aiCanonicalMarkerId(aiDocumentId, i);
            final id = 'Sent_AI_${_safeAiToken(targetTeam)}_${_safeAiToken(canonicalId)}';
            final markerPayload = {
              'id': id,
              'lat': m['lat'],
              'lng': m['lng'],
              'title': "AI탐지 ${i + 1}",
              'description': "AI 시스템에서 일괄 로드된 위치",
              'address': "주소 확인 필요 (AI)", 
              'group': {'name': newGroupName, 'colorValue': Colors.red.value, 'isVisible': true},
              'photos': [],
              'isChecked': false,
              'canonicalMarkerId': canonicalId,
              'originalMarkerId': canonicalId,
              'sourceMarkerId': canonicalId,
            };
            final existingIndex = markers.indexWhere((item) =>
                item is Map &&
                (item['id'] == id ||
                    item['canonicalMarkerId'] == canonicalId ||
                    item['originalMarkerId'] == canonicalId ||
                    item['sourceMarkerId'] == canonicalId ||
                    item['parentMarkerId'] == canonicalId));

            if (existingIndex != -1) {
              final existing = markers[existingIndex];
              if (existing is Map && (existing['id']?.toString() ?? '').isNotEmpty) {
                markerPayload['id'] = existing['id'];
              }
              markers[existingIndex] = {...Map<String, dynamic>.from(existing as Map), ...markerPayload};
            } else {
              markers.add(markerPayload);
            }
          }

          transaction.update(docRef, {'groups': groups, 'markers': markers});
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ 총 ${targetTeams.length}개 팀에 배포가 완료되었습니다!"), backgroundColor: Colors.green)
        );
      }

    } catch (e) {

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("에러: $e")));
    } finally {
      setState(() => _isGlobalProcessing = false);
    }
  }
  void _showLeaderSendToAdminSheet(MapGroup group) {
    final targetGroupName = '${widget.teamName}/${group.name}';
    final markerCount = _markerDataMap.values.where((m) => m.group.name == group.name).length;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Send data to admin", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text("Target group: $targetGroupName"),
            Text("Markers: $markerCount"),
            const SizedBox(height: 6),
            const Text("Line data is not included.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 18),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Colors.green),
              onPressed: () async {
                Navigator.pop(ctx);
                await _sendGroupDataToTeams([_adminTeamName], group);
              },
              child: const Text("Send", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSendGroupSheet(MapGroup group) {
    if (isLeader) {
      _showLeaderSendToAdminSheet(group);
      return;
    }

    List<String> selectedTargetTeams = []; // 기본적으로 선택된 팀 없음

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.5),
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("데이터 전송: ${group.name}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("전송받을 팀 선택 (다중 선택 가능)", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))
                ),
                const SizedBox(height: 5),
                
                // 협력사(타 팀) 목록을 칩(Chip) 형태로 나열
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: _allTeamsMap.keys.map((teamName) {
                      bool isSelected = selectedTargetTeams.contains(teamName);
                      return FilterChip(
                        label: Text(teamName),
                        selected: isSelected,
                        selectedColor: Colors.blueAccent.withOpacity(0.3),
                        checkmarkColor: Colors.blueAccent,
                        onSelected: (bool selected) {
                          setSheet(() {
                            if (selected) {
                              selectedTargetTeams.add(teamName);
                            } else {
                              selectedTargetTeams.remove(teamName);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedTargetTeams.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("전송할 팀을 하나 이상 선택해주세요.")));
                      return;
                    }
                    Navigator.pop(ctx);
                    await _sendGroupDataToTeams(selectedTargetTeams, group); // 전송 실행
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Colors.green),
                  child: const Text("전송 완료", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // ✅ [3단계 추가] 2. 선택된 팀들의 DB에 그룹과 마커를 복사하여 꽂아주는 함수
  // =====================================================================
  Future<void> _sendLeaderGroupToAdmin(MapGroup group) async {
    final targetGroupName = '${widget.teamName}/${group.name}';
    final targetGroup = MapGroup(
      name: targetGroupName,
      colorValue: group.colorValue,
      isVisible: group.isVisible,
    );
    final markersToSend = _markerDataMap.values
        .where((m) => m.group.name == group.name)
        .map((m) {
          final canonicalId = (m.canonicalMarkerId ?? m.originalMarkerId ?? m.sourceMarkerId ?? m.parentMarkerId ?? m.id).trim();
          final markerJson = m.toJson();
          markerJson['id'] = m.id;
          markerJson['canonicalMarkerId'] = canonicalId;
          markerJson['originalMarkerId'] = canonicalId;
          markerJson['sourceMarkerId'] = canonicalId;
          markerJson['group'] = targetGroup.toJson();
          return markerJson;
        })
        .toList();

    setState(() { _isGlobalProcessing = true; _processingText = "관리자에게 데이터 전송 중..."; });

    try {
      final docRef = FirebaseFirestore.instance.collection('teams').doc(_adminTeamName);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          transaction.set(docRef, {
            'teamName': _adminTeamName,
            'teamPw': '1234',
            'groups': [targetGroup.toJson()],
            'markers': markersToSend,
            'lines': [],
          }, SetOptions(merge: true));
          return;
        }

        final data = snapshot.data()!;
        final groups = List<dynamic>.from(data['groups'] ?? []);
        final markers = List<dynamic>.from(data['markers'] ?? []);

        groups.removeWhere((g) => g is Map && g['name'] == targetGroupName);
        groups.add(targetGroup.toJson());

        markers.removeWhere((m) =>
            m is Map &&
            m['group'] is Map &&
            m['group']['name'] == targetGroupName);
        markers.addAll(markersToSend);

        transaction.update(docRef, {
          'groups': groups,
          'markers': markers,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("관리자에게 '$targetGroupName' 데이터가 전송되었습니다."), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      debugPrint("팀장 데이터 전송 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("전송 에러: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isGlobalProcessing = false);
    }
  }

  Future<void> _sendGroupDataToTeams(List<String> targetTeams, MapGroup group) async {
    if (isLeader) {
      await _sendLeaderGroupToAdmin(group);
      return;
    }

    setState(() { _isGlobalProcessing = true; _processingText = "선택한 팀으로 데이터 전송 중..."; });

    try {
      // 내 데이터 중에서 보낼 그룹에 속한 마커들만 싹 추려냅니다.
      List<SiteData> markersToSend = _markerDataMap.values.where((m) => m.group.name == group.name).toList();

      for (String targetTeam in targetTeams) {
        var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeam);

        // 안전하게 트랜잭션으로 처리 (팀장이 동시에 앱을 조작하고 있어도 꼬이지 않게)
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          var snapshot = await transaction.get(docRef);
          if (!snapshot.exists) return; // 해당 팀 문서가 아예 없으면 패스

          var data = snapshot.data()!;
          List<dynamic> markers = List.from(data['markers'] ?? []);
          List<dynamic> groups = List.from(data['groups'] ?? []);

          // 1. 받는 팀의 기존 ON/OFF 상태는 유지하면서 그룹 색상을 갱신합니다.
          final existingGroupIndex = groups.indexWhere(
            (g) => g is Map && g['name'] == group.name,
          );
          dynamic targetGroupIsVisible = true;

          if (existingGroupIndex == -1) {
            groups.add({
              'name': group.name, 
              'colorValue': group.colorValue, 
              'isVisible': true
            });
          } else {
            final existingGroup =
                Map<String, dynamic>.from(groups[existingGroupIndex] as Map);
            targetGroupIsVisible = existingGroup['isVisible'] ?? true;
            groups[existingGroupIndex] = {
              ...existingGroup,
              'name': group.name,
              'colorValue': group.colorValue,
              'isVisible': targetGroupIsVisible,
            };
          }

          // 2. 마커 복사해서 밀어 넣기
          for (int i = 0; i < markersToSend.length; i++) {
            var m = markersToSend[i];
            final canonicalId = (m.canonicalMarkerId ?? m.originalMarkerId ?? m.sourceMarkerId ?? m.parentMarkerId ?? m.id).trim();
            var markerJson = m.toJson();
            markerJson['id'] = m.id;
            markerJson['canonicalMarkerId'] = canonicalId;
            markerJson['originalMarkerId'] = canonicalId;
            markerJson['sourceMarkerId'] = canonicalId;
            markerJson['group'] = {
              ...Map<String, dynamic>.from(markerJson['group'] as Map),
              'name': group.name,
              'colorValue': group.colorValue,
              'isVisible': targetGroupIsVisible,
            };

            int idx = markers.indexWhere((item) =>
                item is Map &&
                item['group'] is Map &&
                item['group']['name'] == group.name &&
                (item['id'] == m.id ||
                    item['canonicalMarkerId'] == canonicalId ||
                    item['originalMarkerId'] == canonicalId ||
                    item['sourceMarkerId'] == canonicalId ||
                    item['parentMarkerId'] == canonicalId ||
                    item['originalMarkerId'] == m.id ||
                    item['sourceMarkerId'] == m.id ||
                    item['parentMarkerId'] == m.id));

            if (idx != -1) {
              final existingMarker = markers[idx];
              if (existingMarker is Map && existingMarker['group'] is Map) {
                final existingMarkerGroup = existingMarker['group'] as Map;
                markerJson['group'] = {
                  ...Map<String, dynamic>.from(markerJson['group'] as Map),
                  'isVisible': existingMarkerGroup['isVisible'] ?? targetGroupIsVisible,
                };
              }
              markers[idx] = markerJson;
            } else {
              markers.add(markerJson);
            }
          }

          // 3. 서버에 최종 덮어쓰기
          transaction.update(docRef, {'groups': groups, 'markers': markers});
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ 총 ${targetTeams.length}개 팀에 데이터 전송이 완료되었습니다!"), backgroundColor: Colors.green)
        );
      }

    } catch (e) {
      debugPrint("데이터 전송 에러: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("전송 에러: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isGlobalProcessing = false); // 로딩바 끄기
    }
  }

  
  } // ✅ 여기가 진짜 MapSampleState 클래스 끝나는 곳! (괄호 딱 하나!)


class MockLocationPlugin {
  static const MethodChannel _channel = MethodChannel('app.mock.location');

  static Future<void> startMockLocation(double lat, double lng, double accuracy) async {
    await _channel.invokeMethod('startMockLocation', {'lat': lat, 'lng': lng});
  }

  static Future<void> stopMockLocation() async {
    await _channel.invokeMethod('stopMockLocation');
  }
}
