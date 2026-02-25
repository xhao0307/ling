import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_player.dart';

const List<(String, String)> kObjectOptions = [
  ('mailbox', '邮箱'),
  ('tree', '树'),
  ('manhole', '井盖'),
  ('road_sign', '路牌'),
  ('traffic_light', '红绿灯'),
];

void main() {
  runApp(const CityLingApp());
}

class CityLingApp extends StatelessWidget {
  const CityLingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '城市灵',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0C7E78),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F6F4),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFFCEE3E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFF0C7E78), width: 1.4),
          ),
        ),
        cardTheme: const CardThemeData(
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          indicatorColor: Color(0xFFD9EEE9),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
        useMaterial3: true,
      ),
      home: const CityLingHomePage(),
    );
  }
}

enum _AuthMode { login, register }

class AuthSession {
  const AuthSession({
    required this.accountId,
    required this.displayName,
    required this.isDebug,
  });

  final String accountId;
  final String displayName;
  final bool isDebug;

  String get preferredChildId => isDebug ? 'kid_1' : accountId;

  Map<String, dynamic> toJson() {
    return {
      'account_id': accountId,
      'display_name': displayName,
      'is_debug': isDebug,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accountId: json['account_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      isDebug: json['is_debug'] as bool? ?? false,
    );
  }
}

class AuthStore {
  static const String _accountsKey = 'cityling_accounts_v1';
  static const String _sessionKey = 'cityling_auth_session_v1';

  final Map<String, String> _accounts = <String, String>{};
  SharedPreferences? _prefs;
  AuthSession? _session;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _loadAccounts();
    _loadSession();
  }

  Future<AuthSession?> restoreSession() async {
    return _session;
  }

  Future<AuthSession> register({
    required String account,
    required String password,
    required String confirmPassword,
  }) async {
    final normalizedAccount = _normalizeAccount(account);
    if (normalizedAccount.length < 3) {
      throw Exception('账号至少 3 位，只能包含字母、数字、下划线');
    }
    if (password.length < 6) {
      throw Exception('密码至少 6 位');
    }
    if (password != confirmPassword) {
      throw Exception('两次输入的密码不一致');
    }
    if (_accounts.containsKey(normalizedAccount)) {
      throw Exception('账号已存在，请直接登录');
    }

    _accounts[normalizedAccount] = _encodePassword(password);
    await _saveAccounts();

    final session = AuthSession(
      accountId: normalizedAccount,
      displayName: normalizedAccount,
      isDebug: false,
    );
    await _saveSession(session);
    return session;
  }

  Future<AuthSession> login({
    required String account,
    required String password,
  }) async {
    final normalizedAccount = _normalizeAccount(account);
    final stored = _accounts[normalizedAccount];
    if (stored == null) {
      throw Exception('账号不存在，请先注册');
    }
    if (stored != _encodePassword(password)) {
      throw Exception('密码错误，请重试');
    }

    final session = AuthSession(
      accountId: normalizedAccount,
      displayName: normalizedAccount,
      isDebug: false,
    );
    await _saveSession(session);
    return session;
  }

  Future<AuthSession> enterDebugMode() async {
    final session = const AuthSession(
      accountId: 'debug',
      displayName: '调试测试账号',
      isDebug: true,
    );
    await _saveSession(session);
    return session;
  }

  Future<void> logout() async {
    _session = null;
    await _prefs?.remove(_sessionKey);
  }

  String _normalizeAccount(String value) {
    final trimmed = value.trim().toLowerCase();
    final safe = trimmed.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return safe;
  }

  String _encodePassword(String password) {
    return base64Encode(utf8.encode('city-ling:$password'));
  }

  void _loadAccounts() {
    final raw = _prefs?.getString(_accountsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _accounts
          ..clear()
          ..addAll(decoded.map((key, value) => MapEntry(key, '$value')));
      }
    } catch (_) {
      _accounts.clear();
    }
  }

  void _loadSession() {
    final raw = _prefs?.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      _session = null;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _session = AuthSession.fromJson(decoded);
      }
    } catch (_) {
      _session = null;
    }
  }

  Future<void> _saveAccounts() async {
    await _prefs?.setString(_accountsKey, jsonEncode(_accounts));
  }

  Future<void> _saveSession(AuthSession session) async {
    _session = session;
    await _prefs?.setString(_sessionKey, jsonEncode(session.toJson()));
  }
}

class AuthEntryPage extends StatefulWidget {
  const AuthEntryPage({
    required this.authStore,
    required this.onAuthed,
    super.key,
  });

  final AuthStore authStore;
  final ValueChanged<AuthSession> onAuthed;

  @override
  State<AuthEntryPage> createState() => _AuthEntryPageState();
}

class _AuthEntryPageState extends State<AuthEntryPage> {
  final TextEditingController _accountCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _submitting = false;
  String _error = '';

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      final account = _accountCtrl.text.trim();
      final password = _passwordCtrl.text;

      final session = _mode == _AuthMode.login
          ? await widget.authStore.login(account: account, password: password)
          : await widget.authStore.register(
              account: account,
              password: password,
              confirmPassword: _confirmCtrl.text,
            );
      if (!mounted) {
        return;
      }
      widget.onAuthed(session);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _enterDebugMode() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      final session = await widget.authStore.enterDebugMode();
      if (!mounted) {
        return;
      }
      widget.onAuthed(session);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '进入调试模式失败：$e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE3F5F2), Color(0xFFF4F8FF), Color(0xFFFFF5E8)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -40,
              child: _buildGlowCircle(
                color: const Color(0xFF9CDDD4).withValues(alpha: 0.8),
                size: 220,
              ),
            ),
            Positioned(
              bottom: -90,
              left: -20,
              child: _buildGlowCircle(
                color: const Color(0xFFFFCF9E).withValues(alpha: 0.75),
                size: 210,
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '城市灵探索台',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0A5F5A),
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '先登录，再开始移动端识别与剧情探索。',
                              style: TextStyle(
                                color: Color(0xFF4C6360),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SegmentedButton<_AuthMode>(
                              segments: const [
                                ButtonSegment<_AuthMode>(
                                  value: _AuthMode.login,
                                  icon: Icon(Icons.login),
                                  label: Text('登录'),
                                ),
                                ButtonSegment<_AuthMode>(
                                  value: _AuthMode.register,
                                  icon: Icon(Icons.app_registration),
                                  label: Text('注册'),
                                ),
                              ],
                              selected: {_mode},
                              onSelectionChanged: (selected) {
                                setState(() {
                                  _mode = selected.first;
                                  _error = '';
                                });
                              },
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _accountCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '账号',
                                hintText: '示例：kid_parent_01',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: true,
                              textInputAction: _mode == _AuthMode.login
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              onSubmitted: (_) {
                                if (_mode == _AuthMode.login) {
                                  unawaited(_submit());
                                }
                              },
                              decoration: const InputDecoration(
                                labelText: '密码',
                                hintText: '不少于 6 位',
                                prefixIcon: Icon(Icons.lock_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (_mode == _AuthMode.register) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmCtrl,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => unawaited(_submit()),
                                decoration: const InputDecoration(
                                  labelText: '确认密码',
                                  prefixIcon:
                                      Icon(Icons.verified_user_outlined),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _submitting ? null : _submit,
                              icon: Icon(_mode == _AuthMode.login
                                  ? Icons.login
                                  : Icons.check_circle),
                              label: Text(
                                _mode == _AuthMode.login ? '登录进入' : '注册并进入',
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _submitting ? null : _enterDebugMode,
                              icon: const Icon(Icons.bug_report_outlined),
                              label: const Text('调试测试入口（免登录）'),
                            ),
                            if (_error.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFE9EA)
                                      .withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    _error,
                                    style: const TextStyle(
                                      color: Color(0xFFB22A30),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowCircle({
    required Color color,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class CityLingHomePage extends StatefulWidget {
  const CityLingHomePage({super.key});

  @override
  State<CityLingHomePage> createState() => _CityLingHomePageState();
}

class _CityLingHomePageState extends State<CityLingHomePage> {
  final ApiClient _api = ApiClient();
  final AuthStore _authStore = AuthStore();
  final ValueNotifier<int> _captureVersion = ValueNotifier<int>(0);
  int _tabIndex = 0;
  bool _bootReady = false;
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _api.init();
    await _authStore.init();
    final restored = await _authStore.restoreSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = restored;
      _bootReady = true;
    });
  }

  Future<void> _openBackendSettings() async {
    final controller = TextEditingController(text: _api.baseUrl);
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('后端地址设置'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'CITYLING_BASE_URL',
            border: OutlineInputBorder(),
            hintText: '例如：http://121.43.118.53:3026',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (input == null) {
      return;
    }

    try {
      await _api.setBaseUrl(input);
      if (!mounted) {
        return;
      }
      final text = input.isEmpty
          ? '已恢复默认后端地址：${_api.baseUrl}'
          : '后端地址已更新：${_api.baseUrl}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('地址无效：$e')));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _authStore.logout();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
      _tabIndex = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = _session;
    if (session == null) {
      return AuthEntryPage(
        authStore: _authStore,
        onAuthed: (nextSession) {
          if (!mounted) {
            return;
          }
          setState(() {
            _session = nextSession;
            _tabIndex = 0;
          });
        },
      );
    }

    final tabs = [
      ExplorePage(
        api: _api,
        onCaptured: () => _captureVersion.value += 1,
        onOpenApiSettings: _openBackendSettings,
        session: session,
        onLogout: _logout,
      ),
      PokedexPage(
        api: _api,
        refreshSignal: _captureVersion,
        defaultChildId: session.preferredChildId,
      ),
      DailyReportPage(
        api: _api,
        refreshSignal: _captureVersion,
        defaultChildId: session.preferredChildId,
      ),
    ];

    return Scaffold(
      appBar: _tabIndex == 0
          ? null
          : AppBar(
              title: Text(
                session.isDebug ? '城市灵（调试模式）' : '城市灵 · ${session.displayName}',
              ),
              actions: [
                IconButton(
                  onPressed: _openBackendSettings,
                  icon: const Icon(Icons.settings_ethernet),
                  tooltip: '后端地址',
                ),
                IconButton(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  tooltip: '退出登录',
                ),
              ],
            ),
      body: tabs[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.travel_explore),
            label: '探索',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome),
            label: '图鉴',
          ),
          NavigationDestination(
            icon: Icon(Icons.summarize),
            label: '报告',
          ),
        ],
      ),
    );
  }
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    required this.api,
    required this.onCaptured,
    required this.onOpenApiSettings,
    required this.session,
    required this.onLogout,
    super.key,
  });

  final ApiClient api;
  final VoidCallback onCaptured;
  final Future<void> Function() onOpenApiSettings;
  final AuthSession session;
  final Future<void> Function() onLogout;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _childIdCtrl = TextEditingController();
  final _ageCtrl = TextEditingController(text: '8');
  final _companionReplyCtrl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final VoicePlayer _voicePlayer = createVoicePlayer();

  bool _profileReady = false;
  String _childId = '';
  int _childAge = 8;

  CameraController? _cameraController;

  String _detectedLabel = '';
  String _detectedRawLabel = '';
  String _detectedReason = '';
  String _lastDetectedImageBase64 = '';

  bool _cameraInitializing = false;
  bool _cameraReady = false;
  bool _detecting = false;
  bool _busy = false;

  String _cameraError = '';
  ScanResult? _scanResult;
  bool _scanCardCollapsed = false;
  CompanionSceneResult? _companionScene;
  final List<_CompanionChatMessage> _companionMessages =
      <_CompanionChatMessage>[];
  final List<_StoryLine> _storyLines = <_StoryLine>[];
  final Set<int> _recordedStoryIndexes = <int>{};
  int _currentStoryIndex = -1;
  bool _waitingForAnswerInput = false;
  bool _quizSolved = false;
  final String _lastSceneWeather = '晴天';
  final String _lastSceneEnvironment = '小区道路';
  final String _lastSceneTraits = '';

  bool get _supportsCameraPreview {
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    _childId = widget.session.preferredChildId;
    _childIdCtrl.text = _childId;
    _initCamera();
  }

  @override
  void dispose() {
    _childIdCtrl.dispose();
    _ageCtrl.dispose();
    _companionReplyCtrl.dispose();
    _voicePlayer.dispose();

    final controller = _cameraController;
    if (controller != null) {
      unawaited(controller.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_profileReady) {
      return _buildEntryScreen();
    }
    return _buildExploreScreen();
  }

  Widget _buildEntryScreen() {
    final isDebug = widget.session.isDebug;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFE6F6F2),
            const Color(0xFFF3FAF8),
            const Color(0xFFFFF8EE).withValues(alpha: 0.95),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 0,
                color: Colors.white.withValues(alpha: 0.92),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '开始探索',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0A5F5A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isDebug ? '当前为调试测试模式，可快速验证流程。' : '先输入孩子信息，然后进入全屏识别模式。',
                        style: const TextStyle(
                          color: Color(0xFF4E6360),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            avatar: Icon(
                              isDebug ? Icons.bug_report : Icons.verified_user,
                              size: 16,
                            ),
                            label: Text(
                              isDebug
                                  ? widget.session.displayName
                                  : '账号：${widget.session.displayName}',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => unawaited(widget.onLogout()),
                            icon: const Icon(Icons.logout, size: 16),
                            label: const Text('切换账号'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _childIdCtrl,
                        decoration: const InputDecoration(
                          labelText: '孩子 ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '孩子年龄（3-15）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _enterExploreMode,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('进入识别'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExploreScreen() {
    final theme = Theme.of(context);
    final safeTop = MediaQuery.paddingOf(context).top;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildCameraBackground()),
        if (_canTapScreenToAdvance)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                unawaited(_advanceStoryLine());
              },
              child: Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 290),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '点击屏幕继续对话',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: safeTop + 10,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.session.isDebug
                                  ? '调试模式 · ${widget.session.displayName}'
                                  : '账号：${widget.session.displayName}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '孩子：$_childId · 年龄：$_childAge',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed:
                            _busy || _detecting ? null : _pickPhotoAndGenerate,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.file_upload, size: 18),
                        label: const Text(
                          '上传',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _busy || _detecting
                            ? null
                            : () => unawaited(widget.onOpenApiSettings()),
                        icon: const Icon(Icons.settings_ethernet),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                        ),
                        tooltip: '后端地址',
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _busy || _detecting
                            ? null
                            : () => unawaited(widget.onLogout()),
                        icon: const Icon(Icons.logout),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                        ),
                        tooltip: '退出登录',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildDetectionBadge(),
              if (_scanResult != null) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '已生成：${_scanResult!.spirit.name}（${_labelToChinese(_scanResult!.objectType)}）',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_scanResult != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 120,
            child: _scanCardCollapsed
                ? Align(
                    alignment: Alignment.center,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _scanCardCollapsed = false;
                            });
                          },
                          icon: const Icon(Icons.unfold_more, size: 18),
                          label: const Text('展开剧情'),
                        ),
                        TextButton.icon(
                          onPressed: _dismissScanCard,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('关闭剧情'),
                        ),
                      ],
                    ),
                  )
                : _buildSpiritCard(_scanResult!),
          ),
        Positioned(
          bottom: 28,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _busy || _detecting ? null : _captureAndGenerate,
                  borderRadius: BorderRadius.circular(40),
                  child: Ink(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _busy || _detecting
                          ? Colors.white.withValues(alpha: 0.45)
                          : Colors.white,
                      border: Border.all(
                        color: const Color(0xFF0C7E78),
                        width: 5,
                      ),
                    ),
                    child: Icon(
                      _detecting ? Icons.hourglass_top : Icons.camera_alt,
                      color: const Color(0xFF0C7E78),
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      _detecting ? '识别中...' : '拍照识别',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraBackground() {
    if (!_supportsCameraPreview) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Colors.black87),
        child: Center(
          child: Text(
            '当前平台不支持相机取景，请使用手机设备进行识别。',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (_cameraInitializing) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Colors.black87),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_cameraError.isNotEmpty) {
      return ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '相机初始化失败',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _cameraError,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _cameraInitializing ? null : _initCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _cameraController;
    if (!_cameraReady ||
        controller == null ||
        !controller.value.isInitialized) {
      return ColoredBox(
        color: Colors.black87,
        child: Center(
          child: FilledButton.icon(
            onPressed: _initCamera,
            icon: const Icon(Icons.videocam),
            label: const Text('初始化相机'),
          ),
        ),
      );
    }

    final previewSize = controller.value.previewSize;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (previewSize != null)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(controller),
            ),
          )
        else
          CameraPreview(controller),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.30),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.36),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
        if (_scanResult != null)
          _SpiritOverlay(
            spirit: _scanResult!.spirit,
            objectType: _scanResult!.objectType,
          ),
      ],
    );
  }

  Widget _buildDetectionBadge() {
    final text = _detectedLabel.isEmpty
        ? '视觉识别：未命中'
        : '视觉识别：${_detectedLabelDisplayZh()}';
    final reason = _detectedReasonDisplayZh();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (reason.isNotEmpty)
              Text(
                reason,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpiritCard(ScanResult scan) {
    final companionName = _companionScene?.characterName ?? scan.spirit.name;
    final silhouetteImageUrl = _companionScene?.characterImageUrl ?? '';
    final currentLine = _currentStoryLine;
    final hasStoryLine = currentLine != null;
    final displaySpeaker = hasStoryLine ? currentLine.speaker : companionName;
    final displayText = hasStoryLine
        ? currentLine.text
        : (_companionScene == null ? '剧情生成中，请稍候...' : '剧情准备中...');
    final storyProgress = hasStoryLine
        ? '${_currentStoryIndex + 1}/${_storyLines.length}'
        : '--/${_storyLines.length}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${scan.spirit.name}（${_labelToChinese(scan.objectType)}）',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '收起',
                  onPressed: () {
                    setState(() {
                      _scanCardCollapsed = true;
                    });
                  },
                  icon: const Icon(Icons.expand_more),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _companionScene == null ? '剧情生成中...' : '剧情互动进行中',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_quizSolved)
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 16),
                    label: const Text('已完成收集'),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  const Text(
                    '请在对话中回答问题',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_companionScene == null) ...[
              const LinearProgressIndicator(minHeight: 3),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: _companionScene == null
                    ? ColoredBox(
                        color: Colors.black12,
                        child: Center(
                          child: Icon(
                            Icons.auto_awesome,
                            size: 46,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      )
                    : _buildCompanionImage(_companionScene!),
              ),
            ),
            const SizedBox(height: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xEE24345A),
                        Color(0xEE18233C),
                        Color(0xEE101828),
                      ],
                      stops: [0, 0.62, 1],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            storyProgress,
                            style: const TextStyle(
                              color: Color(0xFFE7EBFF),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          displayText,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.4,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await _playCurrentStoryVoice();
                                    },
                              icon: const Icon(Icons.volume_up, size: 18),
                              label: const Text('重播本句'),
                            ),
                            if (_canAdvanceStory)
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        await _advanceStoryLine();
                                      },
                                icon: const Icon(Icons.skip_next, size: 18),
                                label: const Text('下一句'),
                              ),
                            if (_busy)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_waitingForAnswerInput && !_quizSolved)
                          TextField(
                            controller: _companionReplyCtrl,
                            minLines: 1,
                            maxLines: 3,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) async {
                              await _sendCompanionMessage(scan);
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              labelText: '输入你的回答',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        await _sendCompanionMessage(scan);
                                      },
                                icon: const Icon(Icons.send),
                                tooltip: '发送',
                              ),
                            ),
                          )
                        else
                          Text(
                            _quizSolved
                                ? '你已经完成本轮问答，可以继续拍照探索新目标。'
                                : (_canTapScreenToAdvance
                                    ? '点击屏幕任意位置继续剧情。'
                                    : '等待剧情加载或角色回应。'),
                            style: const TextStyle(
                              color: Color(0xFFD9DFF7),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: -74,
                  child: _AnimatedNameSilhouette(
                    imageBytes: _companionScene?.characterImageBytes,
                    imageUrl: silhouetteImageUrl,
                    fallbackIcon: _iconForObjectType(scan.objectType),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: -14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFBE8B0), Color(0xFFE7C36A)],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: Text(
                        displaySpeaker,
                        style: const TextStyle(
                          color: Color(0xFF332200),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _scanCardCollapsed = true;
                          });
                        },
                  icon: const Icon(Icons.expand_less, size: 18),
                  label: const Text('收起剧情'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _dismissScanCard,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('关闭剧情'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initCamera() async {
    if (!_supportsCameraPreview) {
      return;
    }

    setState(() {
      _cameraInitializing = true;
      _cameraError = '';
    });

    try {
      final cameras = await availableCameras();
      if (!mounted) {
        return;
      }
      if (cameras.isEmpty) {
        setState(() {
          _cameraError = '当前设备没有可用摄像头。';
          _cameraInitializing = false;
        });
        return;
      }

      CameraDescription selected = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selected = camera;
          break;
        }
      }

      final oldController = _cameraController;
      if (oldController != null) {
        await oldController.dispose();
      }

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _cameraInitializing = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraReady = false;
        _cameraInitializing = false;
        _cameraError = '相机初始化失败：$e';
      });
    }
  }

  Future<void> _detectFromFrame() async {
    if (_detecting) {
      return;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || !mounted) {
      _showSnack('识别器未就绪，请稍后重试。');
      return;
    }

    setState(() {
      _detecting = true;
      _lastDetectedImageBase64 = '';
    });
    try {
      if (controller.value.isTakingPicture) {
        return;
      }

      final frame = await controller.takePicture();
      final imageBytes = await frame.readAsBytes();
      await _detectFromImageBytes(imageBytes);
    } catch (e) {
      _showSnack('视觉识别失败：$e');
    } finally {
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  Future<void> _pickPhotoAndGenerate() async {
    if (_busy || _detecting) {
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      final imageBytes = await picked.readAsBytes();
      setState(() {
        _detecting = true;
        _lastDetectedImageBase64 = '';
      });
      await _detectFromImageBytes(imageBytes);
      if (!mounted || _detectedLabel.isEmpty) {
        return;
      }
      await _confirmDetectedObjectAndScan();
    } catch (e) {
      _showSnack('上传图片识别失败：$e');
    } finally {
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  Future<void> _detectFromImageBytes(Uint8List imageBytes) async {
    final imageBase64 = base64Encode(imageBytes);
    final match = await widget.api.scanImage(
      childId: _childId,
      childAge: _childAge,
      imageBase64: imageBase64,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _detectedLabel = _normalizeObjectLabel(match.detectedLabel);
      _detectedRawLabel = match.rawLabel;
      _detectedReason = match.reason;
      _lastDetectedImageBase64 = imageBase64;
    });

    _showSnack('识别到 ${_labelToChinese(match.detectedLabel)}，请确认主体。');
  }

  Future<void> _confirmDetectedObjectAndScan() async {
    if (_detectedLabel.isEmpty) {
      _showSnack('请先完成一次识别。');
      return;
    }

    final recognized = _detectedLabelDisplayZh();
    final reason = _detectedReasonDisplayZh();
    final scrollController = ScrollController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认识别结果'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('模型识别为：$recognized'),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('识别依据：$reason'),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认并进入剧情'),
            ),
          ],
        );
      },
    );
    scrollController.dispose();

    if (confirmed != true) {
      return;
    }
    await _scan(detectedLabel: _detectedLabel);
  }

  Future<void> _scan({required String detectedLabel}) async {
    setState(() => _busy = true);
    try {
      final result = await widget.api.scan(
        childId: _childId,
        childAge: _childAge,
        detectedLabel: detectedLabel,
      );
      setState(() {
        _scanResult = result;
        _scanCardCollapsed = false;
        _clearCompanionFlow();
      });
      unawaited(_voicePlayer.stop());
      await _startCompanionStory(result);
    } catch (e) {
      _showSnack('扫描失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _startCompanionStory(ScanResult scan) async {
    try {
      final result = await widget.api.generateCompanionScene(
        childId: _childId,
        childAge: _childAge,
        objectType: scan.objectType,
        weather: _lastSceneWeather,
        environment: _lastSceneEnvironment,
        objectTraits: _lastSceneTraits,
        sourceImageBase64: _lastDetectedImageBase64,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _companionScene = result;
        _quizSolved = false;
        _resetStoryLines(<_StoryLine>[
          _StoryLine(
            speaker: result.characterName,
            text: result.dialogText,
            voiceAudioBase64: result.voiceAudioBase64,
            voiceMimeType: result.voiceMimeType,
          ),
          _StoryLine(
            speaker: result.characterName,
            text: '小知识：${scan.fact}',
          ),
          _StoryLine(
            speaker: result.characterName,
            text: '挑战问题：${scan.quiz}',
            requiresAnswerAfter: true,
          ),
        ]);
      });

      await _playCurrentStoryVoice();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _companionScene = null;
        _quizSolved = false;
        _resetStoryLines(<_StoryLine>[
          _StoryLine(
            speaker: scan.spirit.name,
            text: '我们来认识一下${_labelToChinese(scan.objectType)}吧。',
          ),
          _StoryLine(
            speaker: scan.spirit.name,
            text: '小知识：${scan.fact}',
          ),
          _StoryLine(
            speaker: scan.spirit.name,
            text: '挑战问题：${scan.quiz}',
            requiresAnswerAfter: true,
          ),
        ]);
      });
      _showSnack('剧情自动生成失败，已切换基础对话模式。');
    }
  }

  Future<void> _playCurrentStoryVoice() async {
    final line = _currentStoryLine;
    if (line == null) {
      _showSnack('剧情还在准备中，请稍候。');
      return;
    }
    final audio = line.voiceAudioBase64.trim();
    if (audio.isEmpty) {
      _showSnack('当前句暂无语音。');
      return;
    }
    await _playCompanionVoiceData(
      audioBase64: audio,
      mimeType: line.voiceMimeType,
    );
  }

  Future<void> _playCompanionVoiceData({
    required String audioBase64,
    required String mimeType,
    bool showSnackWhenDone = false,
  }) async {
    final audio = audioBase64.trim();
    if (audio.isEmpty) {
      _showSnack('语音数据为空，请重新生成。');
      return;
    }
    try {
      await _voicePlayer.playBase64(
        audioBase64: audio,
        mimeType: mimeType.isEmpty ? 'audio/mpeg' : mimeType,
      );
      if (showSnackWhenDone) {
        _showSnack('已播放角色语音。');
      }
    } catch (e) {
      _showSnack('语音播放失败：$e');
    }
  }

  Future<void> _sendCompanionMessage(ScanResult scan) async {
    final scene = _companionScene;
    if (_storyLines.isEmpty) {
      _showSnack('剧情还在准备中，请稍候。');
      return;
    }
    if (!_waitingForAnswerInput) {
      _showSnack(_quizSolved ? '本轮问答已完成。' : '请先点击“下一句”推进到提问。');
      return;
    }

    final childMessage = _companionReplyCtrl.text.trim();
    if (childMessage.isEmpty) {
      _showSnack('请输入一句话再发送。');
      return;
    }

    final optimistic = _CompanionChatMessage(
      role: _CompanionRole.child,
      text: childMessage,
    );

    setState(() {
      _companionMessages.add(optimistic);
      _companionReplyCtrl.clear();
      _waitingForAnswerInput = false;
      _busy = true;
    });

    try {
      var answerCorrectNow = false;
      if (!_quizSolved) {
        final answer = await widget.api.submitAnswer(
          sessionId: scan.sessionId,
          childId: _childId,
          answer: childMessage,
        );
        if (answer.correct) {
          answerCorrectNow = true;
          if (mounted) {
            setState(() {
              _quizSolved = true;
            });
          }
          if (answer.captured && mounted) {
            widget.onCaptured();
          }
        }
      }

      final hints = <String>[];
      if (answerCorrectNow) {
        hints.add('系统：孩子刚刚回答正确并已完成收集，请先祝贺，再收尾。');
      } else if (!_quizSolved) {
        hints.add('系统：孩子回答暂未命中标准答案，请鼓励并给提示，不要直接公布完整答案。');
      }

      final result = await widget.api.chatCompanion(
        childId: _childId,
        childAge: _childAge,
        objectType: scan.objectType,
        characterName: scene?.characterName ?? scan.spirit.name,
        characterPersonality:
            scene?.characterPersonality ?? scan.spirit.personality,
        weather: _lastSceneWeather,
        environment: _lastSceneEnvironment,
        objectTraits: _lastSceneTraits,
        history: _buildCompanionHistory(extraSystemHints: hints),
        childMessage: childMessage,
      );

      if (!mounted) {
        return;
      }
      final roleName = scene?.characterName ?? scan.spirit.name;
      final replySegments = _splitStoryText(result.replyText);
      final lines = replySegments.isNotEmpty
          ? replySegments
          : <String>[
              result.replyText.trim().isEmpty
                  ? '我听到啦，我们继续。'
                  : result.replyText.trim(),
            ];

      setState(() {
        final firstNewIndex = _storyLines.length;
        for (var i = 0; i < lines.length; i++) {
          final isFirst = i == 0;
          final isLast = i == lines.length - 1;
          _storyLines.add(
            _StoryLine(
              speaker: roleName,
              text: lines[i],
              voiceAudioBase64: isFirst ? result.voiceAudioBase64 : '',
              voiceMimeType: isFirst ? result.voiceMimeType : 'audio/mpeg',
              requiresAnswerAfter: !_quizSolved && !answerCorrectNow && isLast,
            ),
          );
        }
        _currentStoryIndex = firstNewIndex;
        _syncCurrentStoryToHistory();
      });
      if (answerCorrectNow) {
        _showSnack('回答正确，已成功收集精灵。');
      }
      await _playCurrentStoryVoice();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (_companionMessages.isNotEmpty &&
            identical(_companionMessages.last, optimistic)) {
          _companionMessages.removeLast();
        }
      });
      _showSnack('角色回复失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _advanceStoryLine() async {
    if (_waitingForAnswerInput && !_quizSolved) {
      _showSnack('先输入你的回答，再继续剧情。');
      return;
    }
    if (!_canAdvanceStory) {
      _showSnack('已经是当前剧情最后一句。');
      return;
    }
    setState(() {
      _currentStoryIndex += 1;
      _syncCurrentStoryToHistory();
    });
    await _playCurrentStoryVoice();
  }

  List<String> _buildCompanionHistory({
    List<String> extraSystemHints = const [],
  }) {
    final lines = <String>[...extraSystemHints];
    for (final msg in _companionMessages) {
      lines.add(msg.role == _CompanionRole.child
          ? '孩子：${msg.text}'
          : '角色：${msg.text}');
    }
    return lines;
  }

  _StoryLine? get _currentStoryLine {
    if (_currentStoryIndex < 0 || _currentStoryIndex >= _storyLines.length) {
      return null;
    }
    return _storyLines[_currentStoryIndex];
  }

  bool get _canAdvanceStory {
    return !_waitingForAnswerInput &&
        _currentStoryIndex >= 0 &&
        _currentStoryIndex < _storyLines.length - 1;
  }

  bool get _canTapScreenToAdvance {
    return _scanResult != null &&
        !_scanCardCollapsed &&
        !_busy &&
        _canAdvanceStory;
  }

  void _resetStoryLines(List<_StoryLine> lines) {
    _companionMessages.clear();
    _storyLines
      ..clear()
      ..addAll(
        lines.where((line) => line.text.trim().isNotEmpty),
      );
    _recordedStoryIndexes.clear();
    _currentStoryIndex = _storyLines.isEmpty ? -1 : 0;
    _waitingForAnswerInput = false;
    _companionReplyCtrl.clear();
    _syncCurrentStoryToHistory();
  }

  void _syncCurrentStoryToHistory() {
    final line = _currentStoryLine;
    if (line == null) {
      _waitingForAnswerInput = false;
      return;
    }
    if (_recordedStoryIndexes.add(_currentStoryIndex)) {
      _companionMessages.add(
        _CompanionChatMessage(
          role: _CompanionRole.companion,
          text: line.text,
        ),
      );
    }
    _waitingForAnswerInput = !_quizSolved && line.requiresAnswerAfter;
  }

  List<String> _splitStoryText(String text) {
    final normalized = text.replaceAll('\n', ' ').trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final marked = normalized.replaceAllMapped(
      RegExp(r'[。！？!?]'),
      (match) => '${match.group(0)}|',
    );
    return marked
        .split('|')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _clearCompanionFlow() {
    _companionScene = null;
    _quizSolved = false;
    _companionMessages.clear();
    _storyLines.clear();
    _recordedStoryIndexes.clear();
    _currentStoryIndex = -1;
    _waitingForAnswerInput = false;
    _companionReplyCtrl.clear();
  }

  String _normalizeObjectLabel(String label) {
    return label.toLowerCase().trim().replaceAll(' ', '_');
  }

  String _detectedLabelDisplayZh() {
    final normalized = _normalizeObjectLabel(_detectedLabel);
    final detectedZh = _labelToChinese(normalized);
    final raw = _detectedRawLabel.trim();
    if (raw.isEmpty) {
      return detectedZh;
    }

    final rawZh = _labelToChinese(_normalizeObjectLabel(raw));
    if (rawZh == detectedZh) {
      return detectedZh;
    }
    return '$detectedZh（原始标签：$rawZh）';
  }

  String _detectedReasonDisplayZh() {
    final trimmed = _detectedReason.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final lines = <String>[];
        decoded.forEach((key, value) {
          lines.add(
              '${_reasonKeyToChinese(key)}：${_reasonValueToChinese(value)}');
        });
        return lines.join('\n');
      }
    } catch (_) {
      // 原因不是 JSON 时直接显示原文。
    }
    return trimmed;
  }

  String _reasonKeyToChinese(String key) {
    switch (key) {
      case 'object_type':
        return '识别类别';
      case 'raw_label':
        return '原始标签';
      case 'matched_label':
        return '命中标签';
      case 'source':
        return '来源';
      case 'confidence':
        return '置信度';
      default:
        return key;
    }
  }

  String _reasonValueToChinese(dynamic value) {
    if (value is String) {
      final raw = value.trim();
      final normalized = _normalizeObjectLabel(value);
      final zh = _labelToChinese(normalized);
      if (zh == normalized) {
        return raw;
      }
      return zh;
    }
    return value?.toString() ?? '';
  }

  void _showSnack(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _dismissScanCard() {
    if (!mounted) {
      return;
    }
    setState(() {
      _scanResult = null;
      _scanCardCollapsed = false;
      _clearCompanionFlow();
      _lastDetectedImageBase64 = '';
    });
    unawaited(_voicePlayer.stop());
  }

  void _enterExploreMode() {
    final childID = _childIdCtrl.text.trim();
    final age = int.tryParse(_ageCtrl.text.trim());
    if (childID.isEmpty) {
      _showSnack('请先输入孩子 ID。');
      return;
    }
    if (age == null || age < 3 || age > 15) {
      _showSnack('年龄必须在 3 到 15 岁之间。');
      return;
    }

    setState(() {
      _profileReady = true;
      _childId = childID;
      _childAge = age;
      _scanResult = null;
      _scanCardCollapsed = false;
      _clearCompanionFlow();
      _detectedLabel = '';
      _detectedRawLabel = '';
      _detectedReason = '';
      _lastDetectedImageBase64 = '';
    });
    unawaited(_voicePlayer.stop());
  }

  Future<void> _captureAndGenerate() async {
    await _detectFromFrame();
    if (!mounted || _detectedLabel.isEmpty) {
      return;
    }
    await _confirmDetectedObjectAndScan();
  }

  Widget _buildCompanionImage(CompanionSceneResult scene) {
    final bytes = scene.characterImageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) {
          return _buildCompanionImageNetworkFallback(scene.characterImageUrl);
        },
      );
    }
    return _buildCompanionImageNetworkFallback(scene.characterImageUrl);
  }

  Widget _buildCompanionImageNetworkFallback(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.image_not_supported)),
      );
    }
    return Image.network(
      trimmed,
      fit: BoxFit.cover,
      errorBuilder: (context, _, __) {
        return ColoredBox(
          color: Colors.black12,
          child: Center(
            child: Text(
              '角色图加载失败\n$trimmed',
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}

enum _CompanionRole {
  child,
  companion,
}

class _CompanionChatMessage {
  const _CompanionChatMessage({
    required this.role,
    required this.text,
  });

  final _CompanionRole role;
  final String text;
}

class _StoryLine {
  const _StoryLine({
    required this.speaker,
    required this.text,
    this.voiceAudioBase64 = '',
    this.voiceMimeType = 'audio/mpeg',
    this.requiresAnswerAfter = false,
  });

  final String speaker;
  final String text;
  final String voiceAudioBase64;
  final String voiceMimeType;
  final bool requiresAnswerAfter;
}

class _AnimatedNameSilhouette extends StatefulWidget {
  const _AnimatedNameSilhouette({
    this.imageBytes,
    required this.imageUrl,
    required this.fallbackIcon,
  });

  final Uint8List? imageBytes;
  final String imageUrl;
  final IconData fallbackIcon;

  @override
  State<_AnimatedNameSilhouette> createState() =>
      _AnimatedNameSilhouetteState();
}

class _AnimatedNameSilhouetteState extends State<_AnimatedNameSilhouette>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portrait = ClipOval(
      child: SizedBox(
        width: 56,
        height: 56,
        child: _buildSilhouettePortrait(),
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      child: portrait,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final scale = 0.96 + 0.07 * t;
        final lift = -2 + 4 * t;
        final glow = 10 + 7 * t;
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.scale(
            scale: scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xAA84C8FF)
                        .withValues(alpha: 0.18 + 0.2 * t),
                    blurRadius: glow,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSilhouettePortrait() {
    if (widget.imageBytes != null && widget.imageBytes!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.33,
              0.33,
              0.33,
              0,
              0,
              0.33,
              0.33,
              0.33,
              0,
              0,
              0.33,
              0.33,
              0.33,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: Image.memory(
              widget.imageBytes!,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => _fallbackSilhouetteIcon(),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.60),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1.2,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final imageUrl = widget.imageUrl.trim();
    if (imageUrl.isEmpty) {
      return _fallbackSilhouetteIcon();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.33,
            0.33,
            0.33,
            0,
            0,
            0.33,
            0.33,
            0.33,
            0,
            0,
            0.33,
            0.33,
            0.33,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              // 图片加载失败时，返回 fallback 图标
              return _fallbackSilhouetteIcon();
            },
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.60),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackSilhouetteIcon() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2E3A55), Color(0xFF111A2E)],
        ),
      ),
      child:
          Icon(widget.fallbackIcon, color: const Color(0xFFDCE8FF), size: 30),
    );
  }
}

class _SpiritOverlay extends StatelessWidget {
  const _SpiritOverlay({
    required this.spirit,
    required this.objectType,
  });

  final Spirit spirit;
  final String objectType;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.94, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 142,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFF0C7E78).withValues(alpha: 0.84),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForObjectType(objectType),
                color: Colors.white,
                size: 44,
              ),
              const SizedBox(height: 6),
              Text(
                spirit.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _labelToChinese(objectType),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PokedexPage extends StatefulWidget {
  const PokedexPage({
    required this.api,
    required this.refreshSignal,
    required this.defaultChildId,
    super.key,
  });

  final ApiClient api;
  final ValueNotifier<int> refreshSignal;
  final String defaultChildId;

  @override
  State<PokedexPage> createState() => _PokedexPageState();
}

class _PokedexPageState extends State<PokedexPage> {
  late final TextEditingController _childIdCtrl;
  bool _loading = false;
  String _error = '';
  List<PokedexEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _childIdCtrl = TextEditingController(text: widget.defaultChildId);
    widget.refreshSignal.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_refresh);
    _childIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '图鉴',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _childIdCtrl,
            decoration: const InputDecoration(
              labelText: '孩子 ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          if (_entries.isEmpty && !_loading) const Text('还没有收集到精灵。'),
          ..._entries.map(
            (entry) => Card(
              child: ListTile(
                title: Text(entry.spiritName),
                subtitle: Text(
                  '${_labelToChinese(entry.objectType)} · 收集 ${entry.captures} 次',
                ),
                trailing: Text(_fmtDate(entry.lastSeenAt)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final entries = await widget.api.fetchPokedex(_childIdCtrl.text.trim());
      setState(() => _entries = entries);
    } catch (e) {
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class DailyReportPage extends StatefulWidget {
  const DailyReportPage({
    required this.api,
    required this.refreshSignal,
    required this.defaultChildId,
    super.key,
  });

  final ApiClient api;
  final ValueNotifier<int> refreshSignal;
  final String defaultChildId;

  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  late final TextEditingController _childIdCtrl;
  DateTime _date = DateTime.now();
  bool _loading = false;
  String _error = '';
  DailyReport? _report;

  @override
  void initState() {
    super.initState();
    _childIdCtrl = TextEditingController(text: widget.defaultChildId);
    widget.refreshSignal.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_refresh);
    _childIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '每日报告',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _childIdCtrl,
          decoration: const InputDecoration(
            labelText: '孩子 ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('日期：${_fmtDay(_date)}')),
            OutlinedButton(
              onPressed: _loading ? null : _pickDate,
              child: const Text('选择日期'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('刷新报告'),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 12),
        if (_report != null) _buildReport(_report!),
      ],
    );
  }

  Widget _buildReport(DailyReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report.generatedText,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('总收集数：${report.totalCaptured}'),
            const SizedBox(height: 8),
            const Text('知识点：'),
            const SizedBox(height: 6),
            if (report.knowledgePoints.isEmpty) const Text('今天还没有知识点。'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: report.knowledgePoints
                  .map((point) => Chip(label: Text(point)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final report = await widget.api.fetchDailyReport(
        childId: _childIdCtrl.text.trim(),
        date: _date,
      );
      setState(() => _report = report);
    } catch (e) {
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class ApiClient {
  static const String _defaultBaseUrl = String.fromEnvironment(
    'CITYLING_BASE_URL',
    defaultValue: 'http://121.43.118.53:3026',
  );
  String? _baseUrlOverride;

  String get baseUrl => _baseUrlOverride ?? _defaultBaseUrl;

  Future<void> init() async {
    return;
  }

  Future<void> setBaseUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _baseUrlOverride = null;
      return;
    }

    final normalized = _normalizeBaseUrl(trimmed);
    _baseUrlOverride = normalized;
  }

  Future<ScanResult> scan({
    required String childId,
    required int childAge,
    required String detectedLabel,
  }) async {
    final base = baseUrl;
    final response = await http.post(
      Uri.parse('$base/api/v1/scan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'child_id': childId,
        'child_age': childAge,
        'detected_label': detectedLabel,
      }),
    );
    final body = _decode(response);
    return ScanResult.fromJson(body);
  }

  Future<ScanImageResult> scanImage({
    required String childId,
    required int childAge,
    String imageBase64 = '',
    String imageUrl = '',
  }) async {
    if (imageBase64.isEmpty && imageUrl.isEmpty) {
      throw Exception('需要提供 imageBase64 或 imageUrl');
    }
    final base = baseUrl;
    final response = await http.post(
      Uri.parse('$base/api/v1/scan/image'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'child_id': childId,
        'child_age': childAge,
        'image_base64': imageBase64,
        'image_url': imageUrl,
      }),
    );
    final body = _decode(response);
    return ScanImageResult.fromJson(body);
  }

  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String childId,
    required String answer,
  }) async {
    final base = baseUrl;
    final response = await http.post(
      Uri.parse('$base/api/v1/answer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId,
        'child_id': childId,
        'answer': answer,
      }),
    );
    final body = _decode(response);
    return AnswerResult.fromJson(body);
  }

  Future<List<PokedexEntry>> fetchPokedex(String childId) async {
    final base = baseUrl;
    final response = await http.get(
      Uri.parse(
        '$base/api/v1/pokedex?child_id=${Uri.encodeQueryComponent(childId)}',
      ),
    );
    final body = _decode(response);
    final entries = (body['entries'] as List<dynamic>? ?? const []);
    return entries
        .map((raw) => PokedexEntry.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<DailyReport> fetchDailyReport({
    required String childId,
    required DateTime date,
  }) async {
    final base = baseUrl;
    final formattedDate = _fmtDay(date);
    final response = await http.get(
      Uri.parse(
        '$base/api/v1/report/daily?child_id=${Uri.encodeQueryComponent(childId)}&date=$formattedDate',
      ),
    );
    final body = _decode(response);
    return DailyReport.fromJson(body);
  }

  Future<CompanionSceneResult> generateCompanionScene({
    required String childId,
    required int childAge,
    required String objectType,
    required String weather,
    required String environment,
    String objectTraits = '',
    String sourceImageBase64 = '',
  }) async {
    final base = baseUrl;
    final response = await http.post(
      Uri.parse('$base/api/v1/companion/scene'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'child_id': childId,
        'child_age': childAge,
        'object_type': objectType,
        'weather': weather,
        'environment': environment,
        'object_traits': objectTraits,
        'source_image_base64': sourceImageBase64,
      }),
    );
    final body = _decode(response);
    return CompanionSceneResult.fromJson(body);
  }

  Future<CompanionChatResult> chatCompanion({
    required String childId,
    required int childAge,
    required String objectType,
    required String characterName,
    required String characterPersonality,
    required String weather,
    required String environment,
    required String objectTraits,
    required List<String> history,
    required String childMessage,
  }) async {
    final base = baseUrl;
    final response = await http.post(
      Uri.parse('$base/api/v1/companion/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'child_id': childId,
        'child_age': childAge,
        'object_type': objectType,
        'character_name': characterName,
        'character_personality': characterPersonality,
        'weather': weather,
        'environment': environment,
        'object_traits': objectTraits,
        'history': history,
        'child_message': childMessage,
      }),
    );
    final body = _decode(response);
    return CompanionChatResult.fromJson(body);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(payload['error'] ?? '请求失败：HTTP ${response.statusCode}');
    }
    return payload;
  }

  static String _normalizeBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw Exception('请输入有效地址（http/https）');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}

class ScanImageResult {
  ScanImageResult({
    required this.detectedLabel,
    required this.detectedLabelZh,
    required this.rawLabel,
    required this.reason,
  });

  final String detectedLabel;
  final String detectedLabelZh;
  final String rawLabel;
  final String reason;

  factory ScanImageResult.fromJson(Map<String, dynamic> json) {
    final detectedLabelEn = (json['detected_label_en'] as String? ?? '').trim();
    final detectedLabelZh = (json['detected_label'] as String? ?? '').trim();
    return ScanImageResult(
      detectedLabel:
          detectedLabelEn.isNotEmpty ? detectedLabelEn : detectedLabelZh,
      detectedLabelZh: detectedLabelZh,
      rawLabel: json['raw_label'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }
}

class ScanResult {
  ScanResult({
    required this.sessionId,
    required this.objectType,
    required this.spirit,
    required this.fact,
    required this.quiz,
    required this.dialogues,
  });

  final String sessionId;
  final String objectType;
  final Spirit spirit;
  final String fact;
  final String quiz;
  final List<String> dialogues;

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    final rawDialogues = (json['dialogues'] as List<dynamic>? ?? const []);
    return ScanResult(
      sessionId: json['session_id'] as String? ?? '',
      objectType: json['object_type'] as String? ?? '',
      spirit:
          Spirit.fromJson(json['spirit'] as Map<String, dynamic>? ?? const {}),
      fact: json['fact'] as String? ?? '',
      quiz: json['quiz'] as String? ?? '',
      dialogues: rawDialogues.map((item) => item.toString()).toList(),
    );
  }
}

class Spirit {
  Spirit({
    required this.id,
    required this.name,
    required this.intro,
    required this.personality,
  });

  final String id;
  final String name;
  final String intro;
  final String personality;

  factory Spirit.fromJson(Map<String, dynamic> json) {
    return Spirit(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      intro: json['intro'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
    );
  }
}

class AnswerResult {
  AnswerResult({
    required this.correct,
    required this.captured,
    required this.message,
  });

  final bool correct;
  final bool captured;
  final String message;

  factory AnswerResult.fromJson(Map<String, dynamic> json) {
    return AnswerResult(
      correct: json['correct'] as bool? ?? false,
      captured: json['captured'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

class PokedexEntry {
  PokedexEntry({
    required this.spiritName,
    required this.objectType,
    required this.captures,
    required this.lastSeenAt,
  });

  final String spiritName;
  final String objectType;
  final int captures;
  final DateTime lastSeenAt;

  factory PokedexEntry.fromJson(Map<String, dynamic> json) {
    return PokedexEntry(
      spiritName: json['spirit_name'] as String? ?? '',
      objectType: json['object_type'] as String? ?? '',
      captures: json['captures'] as int? ?? 0,
      lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DailyReport {
  DailyReport({
    required this.totalCaptured,
    required this.generatedText,
    required this.knowledgePoints,
  });

  final int totalCaptured;
  final String generatedText;
  final List<String> knowledgePoints;

  factory DailyReport.fromJson(Map<String, dynamic> json) {
    final points = (json['knowledge_points'] as List<dynamic>? ?? const []);
    return DailyReport(
      totalCaptured: json['total_captured'] as int? ?? 0,
      generatedText: json['generated_text'] as String? ?? '',
      knowledgePoints: points.map((item) => item.toString()).toList(),
    );
  }
}

class CompanionSceneResult {
  CompanionSceneResult({
    required this.characterName,
    required this.characterPersonality,
    required this.dialogText,
    required this.imagePrompt,
    required this.characterImageUrl,
    required this.characterImageBase64,
    required this.characterImageMimeType,
    required this.characterImageBytes,
    required this.voiceAudioBase64,
    required this.voiceMimeType,
  });

  final String characterName;
  final String characterPersonality;
  final String dialogText;
  final String imagePrompt;
  final String characterImageUrl;
  final String characterImageBase64;
  final String characterImageMimeType;
  final Uint8List? characterImageBytes;
  final String voiceAudioBase64;
  final String voiceMimeType;

  factory CompanionSceneResult.fromJson(Map<String, dynamic> json) {
    final imageBase64 =
        (json['character_image_base64'] as String? ?? '').trim();
    Uint8List? imageBytes;
    if (imageBase64.isNotEmpty) {
      try {
        imageBytes = base64Decode(imageBase64);
      } catch (_) {
        imageBytes = null;
      }
    }
    return CompanionSceneResult(
      characterName: json['character_name'] as String? ?? '',
      characterPersonality: json['character_personality'] as String? ?? '',
      dialogText: json['dialog_text'] as String? ?? '',
      imagePrompt: json['image_prompt'] as String? ?? '',
      characterImageUrl: json['character_image_url'] as String? ?? '',
      characterImageBase64: imageBase64,
      characterImageMimeType:
          json['character_image_mime_type'] as String? ?? 'image/png',
      characterImageBytes: imageBytes,
      voiceAudioBase64: json['voice_audio_base64'] as String? ?? '',
      voiceMimeType: json['voice_mime_type'] as String? ?? 'audio/mpeg',
    );
  }
}

class CompanionChatResult {
  CompanionChatResult({
    required this.replyText,
    required this.voiceAudioBase64,
    required this.voiceMimeType,
  });

  final String replyText;
  final String voiceAudioBase64;
  final String voiceMimeType;

  factory CompanionChatResult.fromJson(Map<String, dynamic> json) {
    return CompanionChatResult(
      replyText: json['reply_text'] as String? ?? '',
      voiceAudioBase64: json['voice_audio_base64'] as String? ?? '',
      voiceMimeType: json['voice_mime_type'] as String? ?? 'audio/mpeg',
    );
  }
}

String _labelToChinese(String rawLabel) {
  for (final option in kObjectOptions) {
    if (option.$1 == rawLabel) {
      return option.$2;
    }
  }
  return rawLabel;
}

IconData _iconForObjectType(String rawLabel) {
  switch (rawLabel) {
    case 'mailbox':
      return Icons.markunread_mailbox;
    case 'tree':
      return Icons.park;
    case 'manhole':
      return Icons.blur_circular;
    case 'road_sign':
      return Icons.signpost;
    case 'traffic_light':
      return Icons.traffic;
    default:
      return Icons.auto_awesome;
  }
}

String _fmtDay(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _fmtDate(DateTime dateTime) {
  final date = _fmtDay(dateTime);
  final h = dateTime.hour.toString().padLeft(2, '0');
  final m = dateTime.minute.toString().padLeft(2, '0');
  return '$date $h:$m';
}
