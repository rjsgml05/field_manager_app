import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http; // 이 줄을 꼭 추가하세요!
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 자동으로 생성된 파일입니다.
import 'package:firebase_storage/firebase_storage.dart'; // 이 줄을 추가하세요!
import 'package:cloud_firestore/cloud_firestore.dart'; // 나중에 DB 저장할 때 필요하니 미리 추가해두세요.
import 'package:permission_handler/permission_handler.dart'; // ◀ 맨 위에 추가
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart' as web_saver;
import 'package:geocoding/geocoding.dart';




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
  String address; // ◀ 추가됨
  MapGroup group;
  List<PhotoItem> photos;

  SiteData({required this.id, required this.lat, required this.lng, required this.title, required this.description, required this.address, required this.group, required this.photos});
  
  LatLng get position => LatLng(lat, lng);
  set position(LatLng pos) { lat = pos.latitude; lng = pos.longitude; }

  Map<String, dynamic> toJson() => {
    'id': id, 'lat': lat, 'lng': lng, 'title': title, 'description': description, 
    'address': address, // ◀ 추가됨
    'group': group.toJson(), 'photos': photos.map((p) => p.toJson()).toList()
  };

  factory SiteData.fromJson(Map<String, dynamic> json) => SiteData(
    id: json['id'], lat: json['lat'], lng: json['lng'], 
    title: json['title'], description: json['description'], 
    address: json['address'] ?? "주소 정보 없음", // ◀ 추가됨
    group: MapGroup.fromJson(json['group']), 
    photos: (json['photos'] as List).map((p) => PhotoItem.fromJson(p)).toList()
  );
}

class LineData {
  String id, title, description;
  List<String> markerIds;
  List<LatLng> points;
  int colorValue;

  LineData({
    required this.id, 
    required this.title, 
    required this.description, 
    required this.points, 
    required this.markerIds, 
    required this.colorValue
  });

  // ✅ 'markerIds'에 따옴표를 추가하여 수정했습니다.
  Map<String, dynamic> toJson() => {
    'id': id, 
    'title': title, 
    'description': description, 
    'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(), 
    'markerIds': markerIds, // 이 부분에 따옴표 추가
    'colorValue': colorValue
  };

  factory LineData.fromJson(Map<String, dynamic> json) => LineData(
    id: json['id'], 
    title: json['title'], 
    description: json['description'], 
    points: (json['points'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList(), 
    markerIds: List<String>.from(json['markerIds'] ?? []), 
    colorValue: json['colorValue']
  );
}

// --- [관리자용 팀 데이터 클래스] ---
class TeamData {
  String teamName;
  String teamPw;
  bool isVisible;
  List<MapGroup> groups;
  Map<MarkerId, SiteData> markers;
  Map<PolylineId, LineData> lines;
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

  // ✅ 권한 요청 함수
  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.camera,
    ].request();

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


class MapSampleState extends State<MapSample> {
  bool _isGlobalProcessing = false; // 현재 작업 중인지 확인
  String _processingText = "";    // 상단에 띄울 문구
  Set<Marker> _cachedMarkers = {};
  // 여기에 이 변수가 있어야 아래 PDF 함수에서 오류가 나지 않습니다.
  final String googleApiKey = "AIzaSyDe_DmJBD4aFBOrUlLrJBB5Snoc1yPBljE"; 

  final Map<MarkerId, SiteData> _markerDataMap = {};
  // ... 나머지 기존 코드들 ...
  final Map<PolylineId, LineData> _lineDataMap = {};
  final List<MapGroup> _userGroups = [];
  
  // ✅ 관리자 전용: 전체 팀 데이터를 저장할 Map
  final Map<String, TeamData> _allTeamsMap = {};

  final ImagePicker _picker = ImagePicker();
  final List<String> _tempLineMarkerIds = [];
  GoogleMapController? _mapController;
  bool _isTappingMode = false, _isMoveMode = false, _isLineMode = false;

Future<String> _getKoreanAddress(double lat, double lng) async {
    if (kIsWeb) { // 웹용 구글 API 호출
      try {
        final url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleApiKey&language=ko";
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'OK') return data['results'][0]['formatted_address'];
        }
      } catch (e) { return "웹 주소 변환 실패"; }
    }
    // 모바일용 기존 로직
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark p = placemarks[0];
        return "${p.administrativeArea} ${p.locality} ${p.subLocality} ${p.thoroughfare} ${p.name}".trim();
      }
    } catch (e) { debugPrint(e.toString()); }
    return "주소 정보를 불러올 수 없음";
  }

  String get _sKey => "${widget.teamName}_${widget.teamPw}";

  @override
  void initState() { super.initState(); _loadData(); }

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
    // 1. 먼저 내 폰에 저장된 데이터를 불러와서 빠르게 보여줍니다. (오프라인 대비)
    final prefs = await SharedPreferences.getInstance();
    String? gJ = prefs.getString('${_sKey}_g'), mJ = prefs.getString('${_sKey}_m'), lJ = prefs.getString('${_sKey}_l');
    setState(() {
      if (gJ != null) _userGroups.addAll((jsonDecode(gJ) as List).map((g) => MapGroup.fromJson(g)));
      if (mJ != null) { for (var item in jsonDecode(mJ)) { SiteData d = SiteData.fromJson(item); _markerDataMap[MarkerId(d.id)] = d; } }
      if (lJ != null) { for (var item in jsonDecode(lJ)) { LineData d = LineData.fromJson(item); _lineDataMap[PolylineId(d.id)] = d; } }
    });
    _updateMarkerSet();

    // 2. [실시간 동기화] 구글 서버의 데이터가 바뀌면 즉시 화면을 업데이트합니다.
    FirebaseFirestore.instance.collection('teams').doc(widget.teamName).snapshots().listen((doc) {
      if (doc.exists && doc.data() != null) {
        var data = doc.data()!;
        setState(() {
          // 서버 데이터로 그룹 정보 갱신
          _userGroups.clear();
          for (var g in (data['groups'] as List)) _userGroups.add(MapGroup.fromJson(g));
          
          // 서버 데이터로 마커 정보 갱신
          _markerDataMap.clear();
          for (var m in (data['markers'] as List)) {
            SiteData d = SiteData.fromJson(m);
            _markerDataMap[MarkerId(d.id)] = d;
          }
          
          // 서버 데이터로 선(Line) 정보 갱신
          _lineDataMap.clear();
          for (var l in (data['lines'] as List)) {
            LineData d = LineData.fromJson(l);
            _lineDataMap[PolylineId(d.id)] = d;
          }
        });
      }
    });

    // 3. 관리자라면 모든 팀의 리스트를 감시합니다.
    if (widget.isAdmin) {
      FirebaseFirestore.instance.collection('teams').snapshots().listen((snapshot) {
        setState(() {
          _allTeamsMap.clear();
          for (var doc in snapshot.docs) {
            if (doc.id == widget.teamName) continue; // 내 데이터는 제외
            var data = doc.data();
            // 타 팀 데이터를 TeamData 형식으로 변환하여 저장
            // _loadData 함수 내부의 관리자 리스트 감시 부분 수정 제안
_allTeamsMap[doc.id] = TeamData(
  teamName: data['teamName'] ?? doc.id,
  teamPw: data['teamPw'] ?? "",
  groups: data['groups'] != null 
      ? (data['groups'] as List).map((g) => MapGroup.fromJson(g)).toList() 
      : [], // 데이터가 없으면 빈 리스트로 처리
  markers: data['markers'] != null 
      ? { for (var m in (data['markers'] as List)) MarkerId(m['id']): SiteData.fromJson(m) }
      : {},
  lines: data['lines'] != null 
      ? { for (var l in (data['lines'] as List)) PolylineId(l['id']): LineData.fromJson(l) }
      : {},
);
          }
        });
      });
    }
  }

  // --- [UI 헬퍼 함수들 (기존과 동일)] ---
  void _addNewGroupDialog(VoidCallback onComplete) {
    String n = ""; double r=255, g=0, b=0;
    showDialog(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: const Text("새 그룹 추가"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(onChanged: (v) => n = v, decoration: const InputDecoration(labelText: "그룹명")),
        const SizedBox(height: 15),
        Container(width: double.infinity, height: 40, decoration: BoxDecoration(color: Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()), borderRadius: BorderRadius.circular(8)), child: Center(child: Text("색상 미리보기", style: TextStyle(color: (r+g+b) > 400 ? Colors.black : Colors.white, fontWeight: FontWeight.bold)))),
        _colorSlider("R", r, (v) => setD(() => r = v), Colors.red),
        _colorSlider("G", g, (v) => setD(() => g = v), Colors.green),
        _colorSlider("B", b, (v) => setD(() => b = v), Colors.blue),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), ElevatedButton(onPressed: () { if (n.isNotEmpty) { setState(() => _userGroups.add(MapGroup(name: n, colorValue: Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()).toARGB32()))); _saveData(); Navigator.pop(c); onComplete(); } }, child: const Text("추가"))],
    )));
  }

  void _showEditGroupDialog(MapGroup group) {
    String n = group.name; double r = group.color.red.toDouble(), g = group.color.green.toDouble(), b = group.color.blue.toDouble();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: const Text("그룹 수정"), 
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: TextEditingController(text: n), onChanged: (v) => n = v, decoration: const InputDecoration(labelText: "그룹명")),
        const SizedBox(height: 15),
        Container(width: double.infinity, height: 40, decoration: BoxDecoration(color: Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()), borderRadius: BorderRadius.circular(8)), child: Center(child: Text("색상 미리보기", style: TextStyle(color: (r+g+b) > 400 ? Colors.black : Colors.white, fontWeight: FontWeight.bold)))),
        _colorSlider("R", r, (v) => setD(() => r = v), Colors.red), _colorSlider("G", g, (v) => setD(() => g = v), Colors.green), _colorSlider("B", b, (v) => setD(() => b = v), Colors.blue),
      ]), 
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), ElevatedButton(onPressed: () { setState(() { group.name = n; group.colorValue = Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()).toARGB32(); _markerDataMap.forEach((k,v) { if(v.group.name == group.name) v.group.colorValue = group.colorValue; }); }); _saveData(); Navigator.pop(ctx); }, child: const Text("완료"))]
    )));
  }
// --- [여기에 _uploadPhotos 함수를 넣으세요] ---
  Future<List<PhotoItem>> _uploadPhotos(List<PhotoItem> localPhotos, String teamName) async {
    List<PhotoItem> uploadedPhotos = [];
    for (var photo in localPhotos) {
      // 이미 http로 시작하면 서버 주소이므로 다시 업로드하지 않음
      if (photo.filePath.startsWith('http')) {
        uploadedPhotos.add(photo);
        continue;
      }
      
      try {
        File file = File(photo.filePath);
        if (!await file.exists()) continue;

        // 서버 저장 경로 설정
        String fileName = "${DateTime.now().millisecondsSinceEpoch}_${uploadedPhotos.length}.jpg";
        var ref = FirebaseStorage.instance.ref().child("teams/$teamName/$fileName");
        
        // 파일 업로드 실행
        await ref.putFile(file); 
        // 업로드된 파일의 인터넷 주소(URL) 가져오기
        String downloadUrl = await ref.getDownloadURL(); 
        
        uploadedPhotos.add(PhotoItem(filePath: downloadUrl, comment: photo.comment));
      } catch (e) {
        debugPrint("사진 업로드 실패: $e");
      }
    }
    return uploadedPhotos;
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

  // ✅ [추가] 관리자용 팀 폴더 전체 삭제 함수
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
              await FirebaseFirestore.instance.collection('teams').doc(teamName).delete();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("폴더 삭제", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

void _showInputSheet({LatLng? newPoint, SiteData? existingData}) async {
    setState(() => _isTappingMode = false);
    LatLng pos = newPoint ?? (existingData?.position ?? const LatLng(37.56, 126.97));
    
    String currentAddr = existingData?.address ?? "주소를 확인 중입니다...";
    if (existingData == null && newPoint != null) {
      currentAddr = await _getKoreanAddress(newPoint.latitude, newPoint.longitude);
    }

    TextEditingController tCtrl = TextEditingController(text: existingData?.title ?? "");
    TextEditingController dCtrl = TextEditingController(text: existingData?.description ?? "");
    List<PhotoItem> photos = existingData != null ? List.from(existingData.photos) : [];
    
    // ⭐ [수정] 외부 변수로 관리하여 상태가 변해도 유지되도록 함
    MapGroup? selG;
    if (existingData != null) {
      selG = _userGroups.any((g) => g.name == existingData.group.name)
          ? _userGroups.firstWhere((g) => g.name == existingData.group.name)
          : (_userGroups.isNotEmpty ? _userGroups.first : null);
    } else {
      selG = _userGroups.isNotEmpty ? _userGroups.first : null;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 60, left: 20, right: 20, top: 20), 
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: Text("📍 $currentAddr", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                TextField(controller: tCtrl, decoration: const InputDecoration(labelText: "제목")),
                TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "상세 설명")),
                const SizedBox(height: 15),
                
                // ⭐ [수정] 드롭다운: 현재 리스트 내에 있는 객체인지 더 정확히 비교
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<MapGroup>(
                        isExpanded: true,
                        // 현재 selG와 이름이 같은 객체를 리스트에서 찾아 선택값으로 고정
                        value: _userGroups.any((g) => g.name == selG?.name) 
                               ? _userGroups.firstWhere((g) => g.name == selG?.name) 
                               : null,
                        hint: const Text("그룹 선택"),
                        items: _userGroups.map((g) => DropdownMenuItem(
                          value: g, 
                          child: Text(g.name, style: TextStyle(color: g.color))
                        )).toList(),
                        onChanged: (v) {
                          setMS(() => selG = v); // 내부 UI 갱신
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green), 
                      onPressed: () => _addNewGroupDialog(() {
                        setMS(() => selG = _userGroups.last);
                      })
                    ),
                  ],
                ),
                
                ...photos.map((p) => ListTile(
                  leading: p.filePath.startsWith('http') 
                           ? Image.network(p.filePath, width: 40, height: 40, fit: BoxFit.cover) 
                           : Image.file(File(p.filePath), width: 40, height: 40, fit: BoxFit.cover),
                  title: TextField(
                    controller: TextEditingController(text: p.comment), 
                    decoration: const InputDecoration(hintText: "사진 설명"), 
                    onChanged: (v) => p.comment = v
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    onPressed: () => setMS(() => photos.remove(p)),
                  ),
                )),
                
                ElevatedButton.icon(
                  onPressed: () async {
                    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1024);
                    if (x != null) {
                      // ⭐ 사진 촬영 후 상태를 업데이트할 때 selG 값이 유지되도록 보장
                      setMS(() {
                        photos.add(PhotoItem(filePath: x.path));
                      });
                    }
                  }, 
                  icon: const Icon(Icons.camera_alt), 
                  label: const Text("사진 촬영 추가")
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (selG == null) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    setState(() { _isGlobalProcessing = true; _processingText = "저장 중..."; });
                    try {
                      List<PhotoItem> serverPhotos = await _uploadPhotos(photos, widget.teamName);
                      if (!mounted) return;
                      setState(() {
                        final id = existingData?.id ?? DateTime.now().toString();
                        _markerDataMap[MarkerId(id)] = SiteData(
                          id: id, lat: pos.latitude, lng: pos.longitude,
                          title: tCtrl.text, description: dCtrl.text,
                          address: currentAddr, group: selG!, photos: serverPhotos,
                        );
                      });
                      await _saveData();
                    } finally {
                      if (mounted) setState(() => _isGlobalProcessing = false);
                    }
                  }, 
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45), 
                    backgroundColor: Colors.green
                  ), 
                  child: const Text("저장 완료", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }  // --- [Drawer 구성: 관리자일 때 팀 폴더 기능 추가] ---
Widget _buildDrawer() {
    return Drawer(child: ListView(children: [
      // 상단 헤더: 관리자/일반 사용자 색상 구분
      DrawerHeader(
        decoration: BoxDecoration(color: widget.isAdmin ? Colors.blueAccent : Colors.green), 
        child: Center(child: Text(widget.isAdmin ? "통합 관제 시스템" : "현장 관리 시스템", style: const TextStyle(color: Colors.white, fontSize: 22)))
      ),
      
      // 1. 관리자인 경우 다른 팀들(협력사) 폴더 표시
      if (widget.isAdmin) ...[
        const Padding(padding: EdgeInsets.all(10), child: Text("협력사/팀 목록", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
        ..._allTeamsMap.values.map((team) => ExpansionTile(
          leading: Icon(Icons.folder, color: team.isVisible ? Colors.amber : Colors.grey),
          // 👇 이 title 부분이 수정되었습니다 (글자 + 편집버튼 + 삭제버튼)
          title: Row(
            children: [
              Expanded(
                child: Text(team.teamName, 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // [편집 버튼]
              IconButton(
                icon: const Icon(Icons.edit_note, size: 22, color: Colors.blueGrey),
                onPressed: () => _editTeamNameDialog(team.teamName), // 이름 수정 팝업 실행
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              // [삭제 버튼]
              IconButton(
                icon: const Icon(Icons.delete_forever, size: 22, color: Colors.redAccent),
                onPressed: () => _deleteTeamDialog(team.teamName), // 폴더 삭제 팝업 실행
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ],
          ),
          trailing: Switch(
            value: team.isVisible, 
            activeColor: Colors.blue, 
            onChanged: (v) => setState(() => team.isVisible = v)
          ),
          children: team.groups.map((g) => ExpansionTile(
            title: Text(g.name, style: TextStyle(color: g.color, fontSize: 13)),
            trailing: Switch(value: g.isVisible, activeColor: g.color, onChanged: (v) => setState(() => g.isVisible = v)),
            children: team.markers.values.where((m) => m.group.name == g.name).map((s) => ListTile(
              dense: true, 
              title: Text(s.title, style: const TextStyle(fontSize: 12)), 
              onTap: () { Navigator.pop(context); _mapController?.animateCamera(CameraUpdate.newLatLngZoom(s.position, 18)); }
            )).toList(),
          )).toList(),
        )).toList(),
        const Divider(),
      ],

      // 2. 나의 데이터 (로그인한 본인의 데이터)
      const Padding(padding: EdgeInsets.all(10), child: Text("나의 데이터", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
      ..._userGroups.map((g) => ExpansionTile(
        title: Row(
          children: [
            Text(g.name, style: TextStyle(color: g.color, fontWeight: FontWeight.bold)), 
            const SizedBox(width: 10),
            // 그룹명 수정 버튼
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: Colors.grey), 
              onPressed: () => _showEditGroupDialog(g),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ), 
            const SizedBox(width: 12),
            // PDF 리포트 버튼
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, size: 18, color: Colors.redAccent), 
              onPressed: () => _exportDetailedPdf(g),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            )
          ],
        ),
        trailing: Switch(
          value: g.isVisible, 
          activeColor: g.color, 
          onChanged: (val) { 
            setState(() { 
              g.isVisible = val; 
              _markerDataMap.forEach((id, s) { if (s.group.name == g.name) s.group.isVisible = val; }); 
            }); 
            _saveData(); 
          }
        ),
        children: _markerDataMap.values.where((m) => m.group.name == g.name).map((s) => ListTile(
          dense: true, title: Text(s.title), 
          onTap: () { Navigator.pop(context); _mapController?.animateCamera(CameraUpdate.newLatLngZoom(s.position, 18)); }
        )).toList(),
      )).toList(),
      
      // 3. 하단 메뉴 버튼들
      ListTile(
        leading: const Icon(Icons.add_box, color: Colors.blue), 
        title: const Text("새 그룹 추가"), 
        onTap: () => _addNewGroupDialog(() {})
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout, color: Colors.red), 
        title: const Text("로그아웃"), 
        onTap: widget.onLogout
      ),
    ]));
  }

  void _updateMarkerSet() {
    Set<Marker> newMarkers = {};
    
    // 1. 내 팀 마커 계산
    _markerDataMap.forEach((id, site) {
      final g = _userGroups.firstWhere((group) => group.name == site.group.name, orElse: () => site.group);
      if (g.isVisible) {
        newMarkers.add(Marker(
          markerId: id, position: site.position, draggable: _isMoveMode,
          icon: BitmapDescriptor.defaultMarkerWithHue(HSVColor.fromColor(g.color).hue),
          onTap: () => _isLineMode ? setState(() => _tempLineMarkerIds.add(id.value)) : _showMarkerDetails(id),
          onDragEnd: (newPos) async {
            String newAddr = await _getKoreanAddress(newPos.latitude, newPos.longitude);
            setState(() { site.lat = newPos.latitude; site.lng = newPos.longitude; site.address = newAddr; });
            _saveData(); _updateMarkerSet();
          },
        ));
      }
    });

    // 2. 관리자용 타 팀 마커 계산 (있을 경우만)
    if (widget.isAdmin) {
      for (var team in _allTeamsMap.values) {
        if (!team.isVisible) continue;
        team.markers.forEach((id, site) {
          final groupInfo = team.groups.firstWhere((g) => g.name == site.group.name, orElse: () => site.group);
          if (groupInfo.isVisible) {
            newMarkers.add(Marker(
              markerId: MarkerId("${team.teamName}_${id.value}"), position: site.position,
              icon: BitmapDescriptor.defaultMarkerWithHue(HSVColor.fromColor(groupInfo.color).hue),
              alpha: 0.8,
              infoWindow: InfoWindow(title: "[${team.teamName}] ${site.title}", snippet: "그룹: ${groupInfo.name}"),
              onTap: () => _showMarkerDetails(id, fromOtherTeam: team),
            ));
          }
        });
      }
    }

    // 3. 화면 갱신
    setState(() { _cachedMarkers = newMarkers; });
  }

@override
  Widget build(BuildContext context) {
    // 1. 마커 및 선 데이터 취합 (기존 로직 유지)
    Set<Marker> allMarkers = {};
    
    // 내 마커 추가
    _markerDataMap.forEach((id, site) {
      final g = _userGroups.firstWhere((group) => group.name == site.group.name, orElse: () => site.group);
      if (g.isVisible) {
        allMarkers.add(Marker(
          markerId: id, 
          position: site.position, 
          draggable: _isMoveMode,
          icon: BitmapDescriptor.defaultMarkerWithHue(HSVColor.fromColor(g.color).hue),
          onTap: () { 
            if (_isLineMode) setState(() => _tempLineMarkerIds.add(id.value)); 
            else _showMarkerDetails(id); 
          },
// 마커 드래그 끝날 때 실행
          onDragEnd: (newPos) async {
            // ◀ [추가] 새 위치의 주소를 가져옴
            String newAddr = await _getKoreanAddress(newPos.latitude, newPos.longitude);
            setState(() {
              site.lat = newPos.latitude;
              site.lng = newPos.longitude;
              site.address = newAddr; // ◀ [갱신] 주소 업데이트
 
              _lineDataMap.forEach((polyId, lineData) {
                int idx = lineData.markerIds.indexOf(id.value);
                if (idx != -1) lineData.points[idx] = newPos;
              });
            });
            _saveData();
          },
        ));
      }
    });

    // 관리자용 타 팀 마커 추가
    if (widget.isAdmin) {
      for (var team in _allTeamsMap.values) {
        if (!team.isVisible) continue;
        team.markers.forEach((id, site) {
          final groupInfo = team.groups.firstWhere((g) => g.name == site.group.name, orElse: () => site.group);
          if (groupInfo.isVisible) {
            allMarkers.add(Marker(
              markerId: MarkerId("${team.teamName}_${id.value}"), 
              position: site.position,
              draggable: _isMoveMode, 
              icon: BitmapDescriptor.defaultMarkerWithHue(HSVColor.fromColor(groupInfo.color).hue),
              alpha: 0.8,
              infoWindow: InfoWindow(title: "[${team.teamName}] ${site.title}", snippet: "그룹: ${groupInfo.name}"),
              onTap: () => _showMarkerDetails(id, fromOtherTeam: team),
            ));
          }
        });
      }
    }

    final vPolylines = _lineDataMap.entries.map((e) => Polyline(
      polylineId: e.key, 
      points: e.value.points, 
      color: Color(e.value.colorValue).withOpacity(0.9), 
      width: 8, 
      onTap: () => _showLineDetails(e.key), 
      consumeTapEvents: true
    )).toSet();

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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end, 
        children: [
          FloatingActionButton(
            heroTag: "move", 
            backgroundColor: _isMoveMode ? Colors.orange : Colors.white, 
            onPressed: () => setState(() => _isMoveMode = !_isMoveMode), 
            child: Icon(Icons.open_with, color: _isMoveMode ? Colors.white : Colors.black)
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 100), 
            child: FloatingActionButton(
              heroTag: "gps", 
              onPressed: () async { 
                Position p = await Geolocator.getCurrentPosition(); 
                _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 17)); 
              }, 
              child: const Icon(Icons.my_location)
            )
          ),
        ]
      ),
body: Stack(
        children: [
          // 1. [가장 뒤] 지도 레이어
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(37.56, 126.97), zoom: 14), 
            markers: _cachedMarkers, 
            polylines: vPolylines, 
            onMapCreated: (c) => _mapController = c, 
            myLocationEnabled: true, 
            onTap: (p) { if (_isTappingMode) _showInputSheet(newPoint: p); },
          ),

          // 2. [중간] 선 그리기 안내창 레이어
          if (_isLineMode) 
            Positioned(
              top: 10, left: 10, right: 10, 
              child: Container(
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

          // 3. [중간] 하단 새 마커 생성 버튼 레이어
          Align(
            alignment: Alignment.bottomCenter, 
            child: Padding(
              padding: const EdgeInsets.only(bottom: 80), 
              child: ElevatedButton(onPressed: () => _showCreateMenu(), child: const Text("새 마커/선 생성")),
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
  void _showMarkerDetails(MarkerId mid, {TeamData? fromOtherTeam}) {
    final d = fromOtherTeam != null ? fromOtherTeam.markers[mid]! : _markerDataMap[mid]!;
    
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20), 
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [
                Text(
                  "${fromOtherTeam != null ? '[${fromOtherTeam.teamName}] ' : ''}${d.group.name}", 
                  style: TextStyle(color: d.group.color, fontWeight: FontWeight.bold)
                ),
                Row(
                  children: [
                      IconButton(
                        icon: const Icon(Icons.cloud_download, color: Colors.green),
                        onPressed: () => _downloadMarkerPhotos(d),
                        tooltip: "현장 사진 다운로드",
                      ),

                    // 본인 마커인 경우에만 수정/삭제 버튼 노출
                    if (fromOtherTeam == null) ...[
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue), 
                        onPressed: () { Navigator.pop(ctx); _showInputSheet(existingData: d); }
                      ),
IconButton(
  icon: const Icon(Icons.delete, color: Colors.red),
  onPressed: () {
    // 1. 삭제 전, 해당 데이터가 아직 존재하는지 최종 확인 (방어 코드)
    if (!_markerDataMap.containsKey(mid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("이미 삭제되었거나 존재하지 않는 데이터입니다."))
      );
      Navigator.pop(context); // 상세창 닫기
      return;
    }

    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        title: const Text("마커 삭제"),
        content: const Text("이 마커와 관련된 데이터를 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // 2. 창을 닫기 전 mounted(위젯 유효성) 체크
              if (!mounted) return;

              try {
                // 3. 팝업과 상세창을 먼저 안전하게 닫음
                Navigator.pop(confirmCtx); 
                Navigator.pop(context); 

                // 화면 전환 애니메이션을 위해 아주 짧게 대기
                await Future.delayed(const Duration(milliseconds: 100));

                setState(() {
                  // 4. 삭제 실행 전 다시 한번 존재 확인 (관리자 삭제 대응)
                  if (_markerDataMap.containsKey(mid)) {
                    final String targetId = mid.value;
                    final String targetGroupName = _markerDataMap[mid]!.group.name;

                    // (1) 선(Line) 정리
                    _lineDataMap.removeWhere((polyId, lineData) {
                      int idx = lineData.markerIds.indexOf(targetId);
                      if (idx != -1) {
                        lineData.markerIds.removeAt(idx);
                        lineData.points.removeAt(idx);
                      }
                      return lineData.points.length < 2;
                    });

                    // (2) 마커 삭제
                    _markerDataMap.remove(mid);

                    // (3) 빈 그룹 정리
                    bool hasRemaining = _markerDataMap.values.any((m) => m.group.name == targetGroupName);
                    if (!hasRemaining) {
                      _userGroups.removeWhere((g) => g.name == targetGroupName);
                    }
                  }
                });

                // 5. 서버 저장 시도 (관리자가 팀을 이미 지웠다면 에러가 날 수 있으므로 try-catch)
                await _saveData();

              } catch (e) {
                debugPrint("삭제 처리 중 오류: $e");
              }
            },
            child: const Text("삭제", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  },
),                    ]
                  ],
                )
              ]
            ),
            Text(d.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
Text("📍 ${d.address}", style: const TextStyle(fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.w500)), 
const SizedBox(height: 8),
            Text(d.description),
            const SizedBox(height: 10),
            if (d.photos.isNotEmpty) 
              SizedBox(
                height: 160, 
                child: ListView.builder(
                  scrollDirection: Axis.horizontal, 
                  itemCount: d.photos.length, 
                  itemBuilder: (ctx, i) => Container(
                    width: 120, 
                    margin: const EdgeInsets.only(right: 10), 
                    child: Column(
                      children: [
                        ClipRRect(
  borderRadius: BorderRadius.circular(8), 
  child: d.photos[i].filePath.startsWith('http')
      ? Image.network(
          d.photos[i].filePath, 
          width: 120, 
          height: 100, 
          fit: BoxFit.cover,
          // 로딩 중 표시 추가
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 120, height: 100, 
              color: Colors.grey[200], 
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2))
            );
          },
        )
      : Image.file(File(d.photos[i].filePath), width: 120, height: 100, fit: BoxFit.cover),
), 
                        Text(d.photos[i].comment, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center, maxLines: 2)
                      ]
                    )
                  )
                )
              )
          ]
        )
      )
    );
  }


  Widget _colorSlider(String l, double v, Function(double) o, Color c) => Row(children: [Text(l), Expanded(child: Slider(value: v, min: 0, max: 255, activeColor: c, onChanged: o))]);
  // --- [마커/선 생성 메뉴 팝업] ---
  void _showCreateMenu() {
    showModalBottomSheet(
      context: context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.gps_fixed, color: Colors.blue),
            title: const Text("현재 위치에 마커 생성"),
            onTap: () async {
              Navigator.pop(c);
              // 현재 위치 가져오기
              Position p = await Geolocator.getCurrentPosition();
              _showInputSheet(newPoint: LatLng(p.latitude, p.longitude));
            },
          ),
          ListTile(
            leading: const Icon(Icons.touch_app, color: Colors.orange),
            title: const Text("지도 터치해서 마커 생성"),
            onTap: () {
              Navigator.pop(c);
              setState(() => _isTappingMode = true); // 터치 모드 활성화
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("지도의 원하는 지점을 터치하세요."))
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.timeline, color: Colors.green),
            title: const Text("마커 연결해서 선 그리기"),
            onTap: () {
              Navigator.pop(c);
              setState(() {
                _isLineMode = true; // 선 그리기 모드 활성화
                _tempLineMarkerIds.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  // --- [선 생성 입력창] ---
  void _showLineInputSheet({LineData? existingLine}) {
    TextEditingController tCtrl = TextEditingController(text: existingLine?.title ?? "");
    TextEditingController dCtrl = TextEditingController(text: existingLine?.description ?? "");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("선 정보 입력", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextField(controller: tCtrl, decoration: const InputDecoration(labelText: "선 이름")),
            TextField(controller: dCtrl, decoration: const InputDecoration(labelText: "설명")),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  final id = existingLine?.id ?? DateTime.now().toString();
                  // 선택된 마커들의 좌표로 선 포인트 생성
                  List<LatLng> pts = existingLine?.points ?? 
                      _tempLineMarkerIds.map((mid) => _markerDataMap[MarkerId(mid)]!.position).toList();
                  
                  _lineDataMap[PolylineId(id)] = LineData(
                    id: id,
                    title: tCtrl.text,
                    description: dCtrl.text,
                    points: pts,
                    markerIds: List.from(_tempLineMarkerIds),
                    colorValue: Colors.blue.toARGB32(),
                  );
                  _isLineMode = false; // 모드 종료
                  _tempLineMarkerIds.clear();
                });
                _saveData();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45)),
              child: const Text("저장 완료"),
            )
          ],
        ),
      ),
    );
  }

  // --- [선 상세 정보 보기] ---
  void _showLineDetails(PolylineId lid) {
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
// --- [개선된 PDF 내보내기: 한글 지원 + 지도 + 현장사진] ---
// --- [사진 개별 다운로드 함수] ---
// --- [사진 개별 다운로드 함수] ---
  Future<void> _downloadMarkerPhotos(SiteData d) async {
    if (d.photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("다운로드할 사진이 없습니다.")));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사진 다운로드를 시작합니다...")));
    int successCount = 0;

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
          final directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) await directory.create(recursive: true);
          final file = File("${directory.path}/$fileName");
          await file.writeAsBytes(bytes);
          successCount++;
        }
      } catch (e) {
        debugPrint("다운로드 에러: $e");
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$successCount장의 사진이 저장되었습니다.")));
    }
  }

// --- [최종 수정된 PDF 내보내기 함수: 괄호 및 안전 코드 교정] ---
  Future<void> _exportDetailedPdf(MapGroup group) async {
    final markers = _markerDataMap.values.where((m) => m.group.name == group.name).toList();
    
    if (markers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("해당 그룹에 저장된 마커가 없습니다.")));
      return;
    }

    // 1. 폰트 및 제목 설정
    TextEditingController titleController = TextEditingController(text: "${group.name}_상세리포트");
    String? action;

    // 제목 입력 다이얼로그
    await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("PDF 내보내기"), 
        content: TextField(controller: titleController, decoration: const InputDecoration(labelText: "리포트 제목")), 
        actions: [
          ElevatedButton(onPressed: () { action = 'save'; Navigator.pop(ctx); }, child: const Text("저장")),
          ElevatedButton(onPressed: () { action = 'share'; Navigator.pop(ctx); }, child: const Text("공유")),
        ]
      )
    );

    if (action == null || !mounted) return;

    // 2. 상단 알림 바 활성화
    setState(() {
      _isGlobalProcessing = true;
      _processingText = "PDF 생성 중 (사진 및 지도 로드)...";
    });

    final pdf = pw.Document();

    try {
      // 폰트 파일 로드
      final fontData = await rootBundle.load("assets/fonts/NanumGothic.ttf");
      final ttf = pw.Font.ttf(fontData);

      // 마커별 반복 작업 시작
      for (var m in markers) {
        // (1) 구글 정적 지도 이미지 가져오기
        final staticMapUrl = "https://maps.googleapis.com/maps/api/staticmap?"
            "center=${m.lat},${m.lng}&zoom=16&size=600x300&markers=color:red%7C${m.lat},${m.lng}&key=$googleApiKey";
        
        Uint8List? mapImg;
        try {
          final res = await http.get(Uri.parse(staticMapUrl)).timeout(const Duration(seconds: 10));
          if (res.statusCode == 200) mapImg = res.bodyBytes;
        } catch (e) {
          debugPrint("지도 로드 실패: $e");
        }

        // (2) 현장 사진들 가져오기
        List<pw.Widget> photoWidgets = [];
        for (var p in m.photos) {
          Uint8List? imgB;
          try {
            if (p.filePath.startsWith('http')) {
              final res = await http.get(Uri.parse(p.filePath)).timeout(const Duration(seconds: 15));
              if (res.statusCode == 200) imgB = res.bodyBytes;
            } else {
              final file = File(p.filePath);
              if (await file.exists()) imgB = await file.readAsBytes();
            }

            if (imgB != null) {
              photoWidgets.add(
                pw.Container(
                  width: 230,
                  margin: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    children: [
                      pw.Image(pw.MemoryImage(imgB), height: 160, fit: pw.BoxFit.cover),
                      pw.SizedBox(height: 5),
                      pw.Text(p.comment, style: pw.TextStyle(font: ttf, fontSize: 10)),
                    ],
                  ),
                ),
              );
            }
          } catch (e) {
            debugPrint("사진 처리 실패: $e");
          }
        } // 사진 for문 끝

        // (3) PDF 페이지에 데이터 추가
        pdf.addPage(
          pw.MultiPage(
            theme: pw.ThemeData.withFont(base: ttf),
            build: (pw.Context context) => [
              pw.Header(level: 0, child: pw.Text(m.title, style: pw.TextStyle(font: ttf, fontSize: 22, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 10),
              pw.Text("상세 설명: ${m.description}", style: pw.TextStyle(font: ttf, fontSize: 14)),
              pw.Text("좌표: ${m.lat}, ${m.lng}", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
              pw.SizedBox(height: 20),
              pw.Text("📍 주변 지도 정보 (${m.address})", 
    style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold)),
pw.SizedBox(height: 10),
              mapImg != null 
                  ? pw.Center(child: pw.Image(pw.MemoryImage(mapImg)))
                  : pw.Text("지도를 불러올 수 없습니다."),
              pw.SizedBox(height: 30),
              if (photoWidgets.isNotEmpty) ...[
                pw.Text("📸 현장 사진 및 설명", style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Wrap(spacing: 10, runSpacing: 10, children: photoWidgets),
              ],
            ],
          ),
        );
      } // 마커 for문 끝

      // 3. 파일 저장 및 내보내기 로직
      final bytes = await pdf.save(); 
      final fName = "${titleController.text}.pdf";

      if (!mounted) return;

      if (action == 'share') {
        final dir = await getTemporaryDirectory();
        final file = File("${dir.path}/$fName");
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)], subject: titleController.text);
      } else {
        Directory dDir = Platform.isAndroid 
            ? Directory('/storage/emulated/0/Download') 
            : await getApplicationDocumentsDirectory();
        if (!await dDir.exists()) await dDir.create(recursive: true);
        final file = File("${dDir.path}/$fName");
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("다운로드 폴더에 저장: $fName")));
        }
      }
    } catch (e) {
      debugPrint("PDF 생성 실패: $e");
    } finally {
      // 4. 작업 종료 후 상단 바 해제
      if (mounted) {
        setState(() {
          _isGlobalProcessing = false;
        });
      }
    }
  }
}