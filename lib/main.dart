import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http; // 이 줄을 꼭 추가하세요!
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 자동으로 생성된 파일입니다.
import 'package:firebase_storage/firebase_storage.dart'; // 이 줄을 추가하세요!
import 'package:cloud_firestore/cloud_firestore.dart'; // 나중에 DB 저장할 때 필요하니 미리 추가해두세요.
import 'package:permission_handler/permission_handler.dart'; // ◀ 맨 위에 추가
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart' as web_saver;
import 'package:geocoding/geocoding.dart';
import 'package:archive/archive.dart';
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

class SiteData {
  String id;
  double lat, lng;
  String title, description;
  String address; 
  MapGroup group;
  List<PhotoItem> photos;
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
    'isChecked': isChecked // ✅ JSON 저장 시 포함
  };

  factory SiteData.fromJson(Map<String, dynamic> json) => SiteData(
    id: json['id'], lat: json['lat'], lng: json['lng'], 
    title: json['title'], description: json['description'], 
    address: json['address'] ?? "주소 정보 없음", 
    group: MapGroup.fromJson(json['group']), 
    photos: (json['photos'] as List).map((p) => PhotoItem.fromJson(p)).toList(),
    isChecked: json['isChecked'] ?? false // ✅ JSON 불러올 때 포함
  );
}

class LineData {
  String id, title, description;
  List<String> markerIds;
  List<LatLng> points;
  int colorValue;
  bool isVisible; // ✅ [추가]

  LineData({
    required this.id, 
    required this.title, 
    required this.description, 
    required this.points, 
    required this.markerIds, 
    required this.colorValue,
    this.isVisible = true, // ✅ [수정] 여기에 ' = true'가 꼭 있어야 합니다!
  });

  Map<String, dynamic> toJson() => {
    'id': id, 
    'title': title, 
    'description': description, 
    'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(), 
    'markerIds': markerIds, 
    'colorValue': colorValue,
    'isVisible': isVisible, // ✅ 저장 포함
  };

  factory LineData.fromJson(Map<String, dynamic> json) => LineData(
    id: json['id'], 
    title: json['title'], 
    description: json['description'], 
    points: (json['points'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList(), 
    markerIds: List<String>.from(json['markerIds'] ?? []), 
    colorValue: json['colorValue'],
    isVisible: json['isVisible'] ?? true, // ✅ 불러오기 포함
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
    setState(() {
      _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      _isAdmin = prefs.getBool('isAdmin') ?? false;
      _teamName = prefs.getString('teamName') ?? "";
      _teamPw = prefs.getString('teamPw') ?? "";
    });
  }

  void _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    setState(() { _isLoggedIn = false; });
  }

  @override
  Widget build(BuildContext context) {
    return _isLoggedIn 
      ? MapSample(isAdmin: _isAdmin, teamName: _teamName, teamPw: _teamPw, onLogout: _performLogout)
      : LoginScreen(onLoginSuccess: (admin, name, pw) => setState(() { _isAdmin = admin; _teamName = name; _teamPw = pw; _isLoggedIn = true; }));
  }
}
// ◀ 여기서 끊고 바로 아래에 LoginScreen 클래스가 오면 됩니다.

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
                        if (tCtrl.text.isEmpty || pCtrl.text.isEmpty) return;

                        // ✅ 2. 로딩바 시작
                        setState(() { _isLoggingIn = true; });

                        try {
                          final prefs = await SharedPreferences.getInstance();
                          bool admin = (tCtrl.text == "admin" && pCtrl.text == "1234");

                          if (!admin) {
                            List<String> registered = prefs.getStringList('registered_teams') ?? [];
                            String entry = "${tCtrl.text}|${pCtrl.text}";
                            if (!registered.contains(entry)) {
                              registered.add(entry);
                              await prefs.setStringList('registered_teams', registered);
                            }
                          }

                          await prefs.setBool('isLoggedIn', true);
                          await prefs.setBool('isAdmin', admin);
                          await prefs.setString('teamName', tCtrl.text);
                          await prefs.setString('teamPw', pCtrl.text);

                          // 약간의 지연 시간을 주어 로딩바가 보이게 함 (선택 사항)
                          await Future.delayed(const Duration(milliseconds: 500));

                          widget.onLoginSuccess(admin, tCtrl.text, pCtrl.text);
                        } catch (e) {
                          setState(() { _isLoggingIn = false; });
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

  final ImagePicker _picker = ImagePicker();
  final List<String> _tempLineMarkerIds = [];
  WebViewController? _webViewController;
  bool _isTappingMode = false, _isMoveMode = false, _isLineMode = false;
  bool _isMapControlActive = true;
  bool _isFreeLineMode = false;
  bool _isModalOpen = false;
  bool _isHoveringUI = false;
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
  String? _lastSelectedGroupName; // ✅ 마지막으로 선택한 그룹 이름 저장

Future<String> _getKoreanAddress(double lat, double lng) async {
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
              return parts.take(parts.length - 2).join(',').trim();
            }
            return data['display_name']; 
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
            if (doc['road_address'] != null) return doc['road_address']['address_name'];
            if (doc['address'] != null) return doc['address']['address_name'];
          }
        }
      }
    } catch (e) {
      debugPrint("주소 변환 에러: $e");
    }
    return "위치: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}";
  }

  String get _sKey => "${widget.teamName}_${widget.teamPw}";

  void _initializeKakaoWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MarkerChannel',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint("MarkerChannel: ${message.message}");
          _handleKakaoMarkerTap(message.message);
        },
      )
      ..addJavaScriptChannel(
        'MapTapChannel',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint("MapTapChannel: ${message.message}");
          _handleKakaoMapTap(message.message);
        },
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint("FlutterChannel: ${message.message}");
          if (message.message.contains('mapReady')) {
            _updateMarkers();
          }
        },
      )
      ..loadFlutterAsset('assets/kakao_map.html');
  }

  Future<void> _moveTo(double lat, double lng, int level) async {
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

  Future<void> _showCurrentLocationOnMap(double lat, double lng) async {
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

  void _setStateAndRefreshMap(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateMarkers();
    });
  }

  void _handleKakaoMarkerTap(String markerId) {
    if (_isModalOpen || _isHoveringUI || !_isMapControlActive) return;
    if (markerId.trim().isEmpty) return;

    String targetMarkerId = markerId;
    TeamData? targetTeam;
    SiteData? site = _markerDataMap[targetMarkerId];

    if (site == null && widget.isAdmin) {
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
    } else {
      _showMarkerDetails(targetMarkerId, fromOtherTeam: targetTeam);
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

  void _handleKakaoMapTap(String message) {
    if (_isModalOpen || !_isMapControlActive) return;

    final point = _parseKakaoMapTapPoint(message);
    if (point == null) {
      debugPrint('MapTapChannel parse failed: $message');
      return;
    }

    if (_isTappingMode) {
      _showInputSheet(newPoint: point);
    } else if (_isFreeLineMode) {
      _setStateAndRefreshMap(() => _tempFreeLinePoints.add(point));
    }
  }

  @override
  void initState() { 
    super.initState(); 
    WidgetsBinding.instance.addObserver(this); // ◀ 이 줄 추가
    _initializeKakaoWebView();
    _loadData().then((_) => _updateMarkers());
  }

  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  MockLocationPlugin.stopMockLocation();
  _myTeamSub?.cancel();    // ← 추가
  _allTeamsSub?.cancel();  // ← 추가
  super.dispose();
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    await _moveTo(position.latitude, position.longitude, 3);
  } catch (e) {
    debugPrint("위치 이동 에러: $e");
  }
}


Future<void> _updateMarkers() async {
  await _renderMarkersOnKakaoMap();
  await _renderLinesOnKakaoMap();
}

String _colorToHex(Color color) {
  return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

Map<String, dynamic> _siteToMarkerJson(String id, SiteData site, MapGroup group) {
  return {
    'id': id,
    'lat': site.lat,
    'lng': site.lng,
    'title': site.title,
    'color': _colorToHex(site.isChecked ? Colors.blue : group.color),
    'groupName': group.name,
  };
}

Map<String, dynamic> _lineToJson(String id, LineData line) {
  return {
    'id': id,
    'title': line.title,
    'color': _colorToHex(Color(line.colorValue)),
    'points': line.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
  };
}

List<Map<String, dynamic>> _buildMarkerJsonList() {
  final markers = <Map<String, dynamic>>[];

  for (var entry in _markerDataMap.entries) {
    final id = entry.key;
    final site = entry.value;
    final group = _userGroups.firstWhere(
      (g) => g.name == site.group.name,
      orElse: () => site.group,
    );

    if (group.isVisible) {
      markers.add(_siteToMarkerJson(id, site, group));
    }
  }

  if (widget.isAdmin) {
    for (var team in _allTeamsMap.values) {
      if (!team.isVisible) continue;

      for (var entry in team.markers.entries) {
        final id = entry.key;
        final site = entry.value;
        final group = team.groups.firstWhere(
          (g) => g.name == site.group.name,
          orElse: () => site.group,
        );

        if (group.isVisible) {
          markers.add(_siteToMarkerJson('${team.teamName}_$id', site, group));
        }
      }
    }
  }

  return markers;
}

List<Map<String, dynamic>> _buildLineJsonList() {
  final lines = <Map<String, dynamic>>[];

  for (var entry in _lineDataMap.entries) {
    final line = entry.value;
    if (line.isVisible) {
      lines.add(_lineToJson(entry.key, line));
    }
  }

  if (widget.isAdmin) {
    for (var team in _allTeamsMap.values) {
      if (!team.isVisible) continue;

      for (var entry in team.lines.entries) {
        final line = entry.value;
        if (line.isVisible) {
          lines.add(_lineToJson('${team.teamName}_${line.id}', line));
        }
      }
    }
  }

  final pointsToDraw = _isModalOpen ? _frozenFreeLinePoints : _tempFreeLinePoints;
  if (pointsToDraw.isNotEmpty) {
    lines.add({
      'id': 'temp_free_line',
      'title': '',
      'color': _colorToHex(Colors.redAccent),
      'points': pointsToDraw.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    });
  }

  return lines;
}

Future<void> _renderMarkersOnKakaoMap() async {
  final controller = _webViewController;
  if (controller == null) return;

  try {
    await controller.runJavaScript('renderMarkers(${jsonEncode(_buildMarkerJsonList())});');
  } catch (e) {
    debugPrint('renderMarkers failed: $e');
  }
}

Future<void> _renderLinesOnKakaoMap() async {
  final controller = _webViewController;
  if (controller == null) return;

  try {
    await controller.runJavaScript('renderLines(${jsonEncode(_buildLineJsonList())});');
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
    _myTeamSub = FirebaseFirestore.instance.collection('teams').doc(widget.teamName).snapshots().listen((doc) {
      if (doc.exists && doc.data() != null && mounted) {
        // 📍 1. 데이터가 존재할 때 (수정되거나 일부 삭제되었을 때 포함)
        var data = doc.data()!;
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

        // 화면에 마커 아이콘 다시 그리기
        _updateMarkers();
      } else if (!doc.exists && mounted) {
        // 📍 2. 관리자가 파이어베이스에서 팀 폴더(문서)를 아예 삭제했을 때
        setState(() {
          _userGroups.clear();    // 그룹 목록 비우기
          _markerDataMap.clear(); // 마커 데이터 비우기
          _lineDataMap.clear();   // 선 데이터 비우기
        });
        // 화면에서 마커/선 싹 지우기
        _updateMarkers();

        // (선택 사항) 사용자에게 알려주기
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("관리자가 데이터를 삭제했습니다."))
        );
      }
    });

    // 3. [관리자 모드] 안전하게 불러오기 (마커 깜빡임 및 초기화 방지 적용 완료)
    if (widget.isAdmin) {
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
          _updateMarkers(); // 화면 갱신
        });
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
              onPressed: () { 
                // 이름과 색상 변경 반영
                setState(() { 
                  String oldName = group.name;
                  group.name = n;
                  group.colorValue = selectedColor.value; 
                  
                  // 해당 그룹에 속한 마커들도 정보 업데이트
                  _markerDataMap.forEach((k,v) { 
                    if(v.group.name == oldName) {
                      v.group.name = n;
                      v.group.colorValue = group.colorValue;
                    }
                  }); 
                }); 
                _saveData(); 
                Navigator.pop(ctx);
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

  // ✅ [추가] 관리자용 팀명(폴더명) 수정 함수
  void _editTeamNameDialog(String oldTeamName) {
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
                _updateMarkers(); // 지도에서도 마커 제거
              });

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

Future<void> _showInputSheet({LatLng? newPoint, SiteData? existingData, String? targetTeamName}) async {
    setState(() {
      _isTappingMode = false;
      _isModalOpen = true;
      _isMapControlActive = false;
    });
    
    // 1. 위치 및 주소 설정
    LatLng pos = newPoint ?? (existingData?.position ?? const LatLng(37.56, 126.97));
    String fetchedAddress = existingData?.address ?? "주소를 불러오는 중...";
    if (newPoint != null) {
      fetchedAddress = await _getKoreanAddress(pos.latitude, pos.longitude);
    }

    String? selectedGroupName;
    if (existingData != null) {
      selectedGroupName = existingData.group.name;
    } else {
      if (_lastSelectedGroupName != null && _userGroups.any((g) => g.name == _lastSelectedGroupName)) {
        selectedGroupName = _lastSelectedGroupName;
      } else {
        selectedGroupName = _userGroups.isNotEmpty ? _userGroups.first.name : null;
      }
    }

    // ✅ 2. 맨홀 번호 스마트 자동 채번 (Max + 1)
    String defaultTitle = "";
    if (existingData != null) {
      defaultTitle = existingData.title; // 기존 데이터 수정 시 그대로 유지
    } else {
      String targetGroup = selectedGroupName ?? "";
      int maxNumber = 0;
      
      // 내 마커들 중에서 현재 선택된 그룹의 마커만 필터링
      List<SiteData> groupMarkers = _markerDataMap.values.where((m) => m.group.name == targetGroup).toList();
      
      for (var m in groupMarkers) {
        final match = RegExp(r'\d+').firstMatch(m.title); // "맨홀 3", "3" 등에서 숫자만 추출
        if (match != null) {
          int num = int.parse(match.group(0)!);
          if (num > maxNumber) maxNumber = num;
        }
      }
      defaultTitle = (maxNumber + 1).toString(); // 가장 큰 수 + 1
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
                              // 수동으로 바꿔도 기억하기
                              if (v != null) _lastSelectedGroupName = v.name; 
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
                                  _lastSelectedGroupName = _userGroups.last.name;
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
                                    Container(
                                      margin: const EdgeInsets.only(right: 10, top: 10),
                                      width: 80, height: 80,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: (kIsWeb || p.filePath.startsWith('http')) 
                                            ? Image.network(p.filePath, fit: BoxFit.cover, errorBuilder: (c,e,s)=>const Icon(Icons.error)) 
                                            : Image.file(File(p.filePath), fit: BoxFit.cover),
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

    Navigator.pop(ctx);
    
    // 로딩 화면 켜기
    setState(() { _isGlobalProcessing = true; _processingText = "저장 중..."; });
    
    try {
      // 🔥 [핵심 추가] 전체 저장 로직을 20초 타임아웃으로 묶습니다.
      await Future(() async {
        String uploadTeamName = targetTeamName ?? widget.teamName;
        List<PhotoItem> serverPhotos = await _uploadPhotos(photos, uploadTeamName);

        final id = existingData?.id ?? DateTime.now().toString();
        SiteData newData = SiteData(
          id: id, lat: pos.latitude, lng: pos.longitude,
          title: tCtrl.text, description: dCtrl.text, address: aCtrl.text,
          group: selG!, photos: serverPhotos,
        );

        if (widget.isAdmin && targetTeamName != null) {
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
             await _syncToGoogleSheetAdmin(newData, targetTeamName);
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

              // 2. 만약 그룹이 새로 만들어진 거라면 그룹 리스트도 덮어쓰지 않고 추가
              List<dynamic> groups = List.from(data['groups'] ?? []);
              if (!groups.any((g) => g['name'] == selG!.name)) {
                groups.add(selG!.toJson());
              }

              transaction.update(docRef, {'markers': markers, 'groups': groups});
            }
          });

          // 로컬 화면(UI) 즉시 반영
          setState(() {
            _lastSelectedGroupName = selG!.name;
            _markerDataMap[id] = newData;
          });
          
          // 기존 _saveData()는 전체를 덮어씌우므로 제외하고, 비상용 로컬 폰 저장만 수행
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('${widget.teamName}_${widget.teamPw}_m', jsonEncode(_markerDataMap.values.map((m) => m.toJson()).toList()));
          await prefs.setString('${widget.teamName}_${widget.teamPw}_g', jsonEncode(_userGroups.map((g) => g.toJson()).toList()));
          
          await _syncToGoogleSheet(newData);
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _isMapControlActive = false),
        onExit: (_) => setState(() => _isMapControlActive = true),
        child: ListView(
          children: [
            // ❌ [삭제됨] 보관함 모드 스위치가 있던 자리 (이제 헤더가 가장 위입니다)

            // 1. 헤더 (시스템 로고)
            DrawerHeader(
              decoration: BoxDecoration(
                color: widget.isAdmin ? Colors.blueAccent : Colors.green
              ),
              child: Center(
                child: Text(
                  widget.isAdmin ? "통합 관제 시스템" : "현장 관리 시스템",
                  style: const TextStyle(color: Colors.white, fontSize: 22),
                ),
              ),
            ),

            // 2. [관리자 전용] 협력사(다른 팀) 목록 표시
            if (widget.isAdmin) ...[
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
                        _updateMarkers(); 
                      });
                    },
                  ),

                  // 팀 내부 그룹 목록
                  children: team.groups.map((g) {
                    List<SiteData> groupMarkers = team.markers.values
                        .where((m) => m.group.name == g.name)
                        .toList();
                    
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
                                _updateMarkers(); 
                              });
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
                                _moveTo(marker.lat, marker.lng, 1); 
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
            
            ..._userGroups.map((g) => ExpansionTile(
              title: Text(g.name, style: TextStyle(color: g.color, fontWeight: FontWeight.bold)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   // ⭐ [수정됨] 기존 PDF(전송) 버튼 자리를 '카카오맵 뷰어' 버튼으로 교체
                   IconButton(
                    icon: const Icon(Icons.map, color: Colors.green), // 아이콘과 색상 변경
                    tooltip: "카카오맵 뷰어에서 보기",
                    onPressed: () {
                      Navigator.pop(context); // 사이드바 닫기
                      _openKakaoMapViewer(g); // 🚀 뷰어 실행 함수 호출!
                    },
                  ),
                  
                  // 2. 삭제 버튼 (복구 유지)
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    onPressed: () => _deleteGroupDialog(g),
                  ),

                  // 3. 설정(수정) 버튼
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.grey),
                    onPressed: () => _showEditGroupDialog(g),
                  ),
                  
                  // 4. 보이기 스위치
                  Switch(
                    value: g.isVisible,
                    activeColor: g.color,
                    onChanged: (val) {
                      setState(() {
                        g.isVisible = val;
                        _updateMarkers();
                      });
                    },
                  ),
                ],
              ),
              children: _markerDataMap.values.where((m) => m.group.name == g.name).map((s) => ListTile(
                // ✅ 아이콘 추가 및 색상 적용 (보기 좋게 통일)
                leading: Icon(Icons.location_on, size: 18, color: s.isChecked ? Colors.blue : Colors.grey),
                // ✅ 텍스트에 조건부 TextStyle 추가
                title: Text(s.title, style: TextStyle(color: s.isChecked ? Colors.blue : null, fontWeight: FontWeight.bold)),
                subtitle: Text(s.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.isChecked ? Colors.blue : Colors.grey)),
                onTap: () {
                  Navigator.pop(context);
                  _moveTo(s.lat, s.lng, 1);
                },
              )).toList(),
            )),

            ListTile(
              leading: const Icon(Icons.add_box, color: Colors.blue),
              title: const Text("새 그룹 추가"),
              onTap: () {
                _addNewGroupDialog(() {
                  setState(() {
                    // 슬라이드바에서 그룹을 만들어도, 마커 생성 시 이 그룹이 기본값이 됨
                    if (_userGroups.isNotEmpty) {
                      _lastSelectedGroupName = _userGroups.last.name;
                    }
                  });
                });
              },
            ),
            const Divider(), // 구분선

            ExpansionTile(
              leading: const Icon(Icons.timeline, color: Colors.purple),
              title: const Text("선 목록 (Lines)", style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                // 1. 선이 아예 없을 때
                if (_lineDataMap.isEmpty && (!widget.isAdmin || _allTeamsMap.values.every((t) => t.lines.isEmpty)))
                  const ListTile(title: Text("생성된 선이 없습니다.", style: TextStyle(fontSize: 12, color: Colors.grey)))
                else ...[
                  // 2. [내 선] 목록 그리기 (함수 호출)
                  ..._lineDataMap.values.map((line) => _buildLineListTile(line, isMyLine: true)),

                  // 3. [관리자용] 다른 팀 선 목록 그리기 (함수 호출)
                  if (widget.isAdmin)
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
  
  
  @override
  Widget build(BuildContext context) {
    // 2. 화면 구성 시작
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text('${widget.teamName}${widget.isAdmin ? " (관리자)" : ""}-지도')),
            const Text("제작자 : 박건희", style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70)),
          ],
        ),
        backgroundColor: widget.isAdmin ? Colors.blueAccent : Colors.green,
      ),
      drawer: _buildDrawer(),
      floatingActionButton: _uiBlocker(
        Column(
          mainAxisAlignment: MainAxisAlignment.end, 
          children: [
            FloatingActionButton(
              heroTag: "move", 
              backgroundColor: _isMoveMode ? Colors.orange : Colors.white, 
              onPressed: () {
                setState(() { _isMoveMode = !_isMoveMode; });
                _updateMarkers(); 
              }, 
              child: Icon(Icons.open_with, color: _isMoveMode ? Colors.white : Colors.black)
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 100), 
              child: FloatingActionButton(
                heroTag: "gps", 
                onPressed: () async { 
                  Position p = await Geolocator.getCurrentPosition(); 
                  await _showCurrentLocationOnMap(p.latitude, p.longitude);
                  _moveTo(p.latitude, p.longitude, 3); 
                }, 
                child: const Icon(Icons.my_location)
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
          child: _webViewController == null
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
                  
                  // 1. 서버/로컬 데이터 저장
                  if (widget.isAdmin && targetTeamName != null) {
                    var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeamName);
                    var snap = await docRef.get();
                    if (snap.exists) {
                      var data = snap.data()!;
                      List<dynamic> markers = List.from(data['markers'] ?? []);
                      int idx = markers.indexWhere((m) => m['id'] == d.id);
                      if (idx != -1) {
                        markers[idx]['isChecked'] = val;
                        await docRef.update({'markers': markers});
                      }
                    }
                    // ✅ [추가] 관리자 모드 시트 동기화
                    await _syncToGoogleSheetAdmin(d, targetTeamName); 
                  } else {
                    await _saveData();
                    // ✅ [추가] 내 팀 시트 동기화
                    await _syncToGoogleSheet(d); 
                  }
                  
                  // 2. 지도 마커와 슬라이드바 텍스트 색상 즉시 갱신을 위해 호출
                  _updateMarkers(); 
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

if (widget.isAdmin)
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
                      if (fromOtherTeam == null || widget.isAdmin) ...[
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
                            showDialog(
                              context: context,
                              builder: (confirmCtx) => AlertDialog(
                                title: const Text("마커 삭제"),
                                content: const Text("정말 삭제하시겠습니까?\n(팀장 앱과 구글 시트에서도 삭제됩니다)"),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text("취소")),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () async {
                                      if (!mounted) return;
                                      Navigator.pop(confirmCtx);
                                      Navigator.pop(context);

                                      // 삭제 로직
if (widget.isAdmin && targetTeamName != null) {
  // 1. [관리자 모드] 서버에서 직접 삭제 및 그룹 정리
  try {
    var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeamName);
    
    // 트랜잭션으로 안전하게 처리 (동시 수정 방지)
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      var snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      var data = snapshot.data()!;
      List<dynamic> markers = List.from(data['markers'] ?? []);
      List<dynamic> groups = List.from(data['groups'] ?? []); // 그룹 목록도 가져옴

      // (1) 마커 삭제
      markers.removeWhere((m) => m['id'] == d.id);

      // (2) 해당 그룹에 남은 마커가 있는지 검사
      // 주의: d.group.name은 삭제하려는 마커의 그룹명
      bool hasRemainingMarkers = markers.any((m) => 
          (m['group'] is Map) && m['group']['name'] == d.group.name
      );

      // (3) 남은 마커가 없다면 그룹도 삭제
      if (!hasRemainingMarkers) {
        groups.removeWhere((g) => g['name'] == d.group.name);
      }

      // (4) DB 업데이트 (마커와 그룹 모두)
      transaction.update(docRef, {
        'markers': markers,
        'groups': groups
      });
    });

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("삭제 완료 (빈 그룹 정리됨)")));
    
  } catch (e) { debugPrint("삭제 오류: $e"); }

} else {
  // 2. [일반 모드] 내 폰 데이터 삭제 및 그룹 정리
  setState(() {
    if (_markerDataMap.containsKey(mid)) {
      // 삭제할 마커의 그룹 이름 기억
      String targetGroupName = _markerDataMap[mid]!.group.name;

      // (1) 마커 삭제
      _markerDataMap.remove(mid);

      // (2) 해당 그룹에 남은 마커가 있는지 확인
      bool hasRemaining = _markerDataMap.values.any((m) => m.group.name == targetGroupName);

      // (3) 남은 마커가 없으면 그룹 리스트에서 삭제
      if (!hasRemaining) {
        _userGroups.removeWhere((g) => g.name == targetGroupName);
        
        // (선택사항) 사용자에게 알림
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("'$targetGroupName' 그룹이 비어 있어 삭제되었습니다."))
        );
      }
    }
  });
  await _saveData();
}
                                    },
                                    child: const Text("삭제", style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
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
    showModalBottomSheet(
      context: context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 현재 위치 마커
          ListTile(
            leading: const Icon(Icons.gps_fixed, color: Colors.blue),
            title: const Text("현재 위치에 마커 생성"),
            onTap: () async {
              // 🛡️ 1. 지도 터치 잠금 (클릭 뚫림 방지)
              setState(() => _isMapControlActive = false);
              
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
                setState(() {
                  _isTappingMode = true;
                  _isMapControlActive = true; 
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("지도의 원하는 지점을 터치하세요."), duration: Duration(seconds: 2)));
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
                              _isLineMode = true; 
                              _isFreeLineMode = false;
                              _tempLineMarkerIds.clear();
                              _isMapControlActive = true;
                            });
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
                              _isFreeLineMode = true; 
                              _isLineMode = false;
                              _tempFreeLinePoints.clear();
                              _isMapControlActive = true; // 지도 다시 켜기
                            });
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

  void _showLineInputSheet({LineData? existingLine, bool isFreeDraw = false}) async {
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
                  
                  if (widget.isAdmin && existingLine == null) ...[
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
                        isVisible: true,
                      );
                      Navigator.pop(ctx); 

                      if (widget.isAdmin && existingLine == null) {
                        for (String targetTeam in selectedTargetTeams) {
                          if (targetTeam == widget.teamName) {
                            setState(() { _lineDataMap[id] = newLine; });
                            _saveData();
                          } else {
                            try {
                              var docRef = FirebaseFirestore.instance.collection('teams').doc(targetTeam);
                              var snap = await docRef.get();
                              if (snap.exists) {
                                var data = snap.data()!;
                                List<dynamic> lines = List.from(data['lines'] ?? []);
                                lines.add(newLine.toJson()); 
                                await docRef.update({'lines': lines});
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
                      } else {
                        setState(() {
                          _lineDataMap[id] = newLine;
                          _isLineMode = false;
                          _isFreeLineMode = false;
                          _tempLineMarkerIds.clear();
                          _tempFreeLinePoints.clear();
                        });
                        _saveData();
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
void _deleteGroupDialog(MapGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("그룹 삭제 확인"),
        content: Text("'${group.name}' 그룹과 포함된 모든 마커가 삭제됩니다.\n정말 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              setState(() {
                _markerDataMap.removeWhere((key, marker) => marker.group.name == group.name);
                _userGroups.remove(group);
                _lineDataMap.forEach((polyId, lineData) {
                   // 필요시 로직 추가
                });
              });
              await _saveData();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("삭제", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
    return ListTile(
      leading: Icon(Icons.horizontal_rule, color: Color(line.colorValue)),
      title: Text(
        "${isMyLine ? '' : '[$teamName] '}${line.title}",
        style: TextStyle(color: line.isVisible ? Colors.black : Colors.grey, fontSize: 13),
      ),
      subtitle: Text(line.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // On/Off 스위치
          Switch(
            value: line.isVisible,
            activeColor: Color(line.colorValue),
            onChanged: (val) async {
              setState(() { line.isVisible = val; });
              
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
              _showLineInputSheet(existingLine: line); 
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
      onTap: () {
        if (!line.isVisible) return;
        Navigator.pop(context);
        if (line.points.isNotEmpty) {
          final firstPoint = line.points.first;
          _moveTo(firstPoint.latitude, firstPoint.longitude, 3);
        }
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

  Timer? _markerUpdateTimer;

  // ✅ [추가] _updateMarkers 중복 호출 방지 함수
  void _scheduleMarkerUpdate() {
    _markerUpdateTimer?.cancel();
    _markerUpdateTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _updateMarkers();
    });
  }

// ✅ 1. 파이어베이스에 올라간 '하나의 파일'들 목록 보기 (에러 디버깅 강화 버전)
  Future<void> _showAiImportListDialog() async {
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
                        _showAiTeamSelectionSheet(gName, manholes); // 👉 배포할 팀 선택 시트 호출
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
  void _showAiTeamSelectionSheet(String aiGroupName, List<dynamic> aiManholes) {
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
                    await _distributeAiDataToTeams(selectedTargetTeams, aiGroupName, aiManholes);
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
Future<void> _distributeAiDataToTeams(List<String> targetTeams, String aiGroupName, List<dynamic> aiManholes) async {
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
            String id = "AI_${targetTeam}_${DateTime.now().millisecondsSinceEpoch}_$i";
            
            markers.add({
              'id': id,
              'lat': m['lat'],
              'lng': m['lng'],
              'title': "AI탐지 ${i + 1}",
              'description': "AI 시스템에서 일괄 로드된 위치",
              'address': "주소 확인 필요 (AI)", 
              'group': {'name': newGroupName, 'colorValue': Colors.red.value, 'isVisible': true},
              'photos': [],
              'isChecked': false
            });
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
  void _showSendGroupSheet(MapGroup group) {
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
  Future<void> _sendGroupDataToTeams(List<String> targetTeams, MapGroup group) async {
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

          // 1. 받는 팀에 해당 그룹명(폴더)이 없다면 생성해줍니다.
          if (!groups.any((g) => g['name'] == group.name)) {
            groups.add({
              'name': group.name, 
              'colorValue': group.colorValue, 
              'isVisible': true
            });
          }

          // 2. 마커 복사해서 밀어 넣기
          for (int i = 0; i < markersToSend.length; i++) {
            var m = markersToSend[i];
            
            // 💡 [중요] 받는 쪽에서 마커 ID가 겹치지 않게 새로운 고유 ID를 발급해줍니다.
            String newId = "Sent_${widget.teamName}_${DateTime.now().millisecondsSinceEpoch}_$i";
            
            var markerJson = m.toJson();
            markerJson['id'] = newId; // 발급한 새 ID 교체
            markerJson['isChecked'] = false; // 보낼 때는 기본 상태(False)로 초기화해서 보냄

            markers.add(markerJson);
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

  // ⭐ [새로 추가] 해당 그룹 마커를 JSON으로 업로드하고 카카오맵 뷰어 띄우기
Future<void> _openKakaoMapViewer(MapGroup group) async {
    setState(() {
      _isGlobalProcessing = true;
      _processingText = "지도 뷰어 준비 중...";
    });

    try {
      List<SiteData> groupMarkers = _markerDataMap.values
          .where((m) => m.group.name == group.name)
          .toList();

      if (groupMarkers.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("해당 그룹에 마커가 없습니다.")));
        return;
      }

      List<Map<String, dynamic>> markersJson = groupMarkers.map((m) => {
        'title': m.title,
        'lat': m.lat,
        'lng': m.lng,
        'description': m.description,
      }).toList();

      String newJsonString = jsonEncode(markersJson);

      // ⭐ 파일명을 그룹명 기반 고정 이름으로 (매번 새로 만들지 않음)
      String fileName = "viewer_${widget.teamName}_${group.name}.json";
      var ref = FirebaseStorage.instance.ref().child("viewer/$fileName");

      // ⭐ 기존 파일 내용과 비교해서 다를 때만 업로드
      bool needUpload = true;
      try {
        final existing = await http.get(Uri.parse(await ref.getDownloadURL()));
        if (existing.statusCode == 200 && existing.body == newJsonString) {
          needUpload = false; // 내용 같으면 업로드 스킵
        }
      } catch (_) {
        needUpload = true; // 파일 없으면 새로 업로드
      }

      String jsonDownloadUrl;
      if (needUpload) {
        await ref.putData(
          Uint8List.fromList(utf8.encode(newJsonString)),
          SettableMetadata(contentType: 'application/json')
        );
      }
      jsonDownloadUrl = await ref.getDownloadURL();

      String viewerHtmlUrl = "https://fieldmanager-c94c2.web.app/viewer.html";
      final Uri url = Uri.parse("$viewerHtmlUrl?data=${Uri.encodeComponent(jsonDownloadUrl)}");

      if (mounted) setState(() => _isGlobalProcessing = false);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("지도 준비 완료", style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text("데이터 업로드가 완료되었습니다.\n아래 버튼을 눌러 카카오맵을 확인하세요."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("취소", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  launchUrl(url, webOnlyWindowName: '_blank');
                  Navigator.pop(ctx);
                },
                child: const Text("지도 열기",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          )
        );
      }

    } catch (e) {
      debugPrint("뷰어 실행 에러: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("오류 발생: $e")));
    } finally {
      if (mounted) setState(() => _isGlobalProcessing = false);
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
