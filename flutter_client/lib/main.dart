import 'dart:async';
import 'dart:convert';
import 'dart:ui';

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

const Color kFairyRose = Color(0xFFE86AA6);
const Color kFairyRoseDeep = Color(0xFFB84D86);
const Color kFairySky = Color(0xFFDCEBFF);
const Color kFairyMint = Color(0xFF6ED3B5);
const Color kFairyButter = Color(0xFFF4B860);
const Color kFairyInk = Color(0xFF2D2A38);
const Color kFairyInkSubtle = Color(0xFF6B667A);
const Color kFairyInkHint = Color(0xFFB3AFC1);
const Color kFairyBgBase = Color(0xFFF5F2FA);
const Duration kMicroAnim = Duration(milliseconds: 150);
const List<double> _kGrayScaleMatrix = <double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
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
          seedColor: kFairyRose,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: kFairyBgBase,
        textTheme: ThemeData.light().textTheme.copyWith(
              headlineLarge: const TextStyle(
                color: kFairyInk,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.64,
                height: 1.22,
              ),
              titleLarge: const TextStyle(
                color: kFairyInk,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
              bodyMedium: const TextStyle(
                color: kFairyInkSubtle,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFF8F6FC),
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          labelStyle: TextStyle(
            color: kFairyInkSubtle,
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: TextStyle(
            color: kFairyRoseDeep,
            fontWeight: FontWeight.w700,
          ),
          hintStyle: TextStyle(
            color: kFairyInkHint,
            fontWeight: FontWeight.w500,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Colors.transparent),
          ),
        ),
        cardTheme: const CardThemeData(
          surfaceTintColor: Colors.transparent,
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          iconTheme: WidgetStatePropertyAll(
            IconThemeData(color: kFairyInkSubtle, size: 22),
          ),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kFairyRose,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            shadowColor: const Color(0x66E86AA6),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kFairyInkSubtle,
            side: const BorderSide(color: Color(0x88FFFFFF)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            backgroundColor: Colors.white54,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF5A506B),
          contentTextStyle: TextStyle(fontWeight: FontWeight.w600),
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
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _loadAccounts();
      _loadSession();
    } catch (_) {
      // 降级为仅内存会话，避免初始化失败导致页面卡在 loading。
      _prefs = null;
      _accounts.clear();
      _session = null;
    }
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

class _AtmosphericBackground extends StatelessWidget {
  const _AtmosphericBackground({
    required this.child,
    this.showStars = true,
  });

  final Widget child;
  final bool showStars;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kFairyBgBase,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7DCF1), Color(0xFFE0ECFF), Color(0xFFF5F2FA)],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -130,
            left: -96,
            child: _glow(const Color(0xAAFFD4EC), 360),
          ),
          Positioned(
            top: 60,
            right: -90,
            child: _glow(const Color(0x88DCEBFF), 320),
          ),
          Positioned(
            bottom: -120,
            left: -44,
            child: _glow(const Color(0x80FFE8D4), 300),
          ),
          if (showStars) ...[
            const Positioned(
              top: 120,
              right: 46,
              child:
                  Icon(Icons.auto_awesome, color: Color(0xFFFFD26D), size: 20),
            ),
            const Positioned(
              bottom: 150,
              left: 26,
              child:
                  Icon(Icons.auto_awesome, color: Color(0xFFC5D8FF), size: 16),
            ),
          ],
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  static Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = 30,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.42),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x142D2A38),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
              BoxShadow(
                color: Color(0x22FFFFFF),
                blurRadius: 1,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _CandyPrimaryButton extends StatefulWidget {
  const _CandyPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.breathe = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool enabled;
  final bool breathe;

  @override
  State<_CandyPrimaryButton> createState() => _CandyPrimaryButtonState();
}

class _CandyPrimaryButtonState extends State<_CandyPrimaryButton>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _breathingController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    if (widget.breathe) {
      _breathingController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _CandyPrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.breathe && !_breathingController.isAnimating) {
      _breathingController.repeat(reverse: true);
    }
    if (!widget.breathe && _breathingController.isAnimating) {
      _breathingController.stop();
      _breathingController.value = 0;
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, _) {
        final breatheScale =
            widget.breathe ? (1 + _breathingController.value * 0.02) : 1.0;
        final hoverScale = _hovering && enabled ? 1.03 : 1.0;
        return AnimatedScale(
          scale: breatheScale * hoverScale,
          duration: kMicroAnim,
          curve: Curves.easeOutCubic,
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: SizedBox(
              height: 54,
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() => _hovering = false),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kFairyRose, kFairyRoseDeep],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.32)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x66E86AA6).withValues(
                          alpha: _hovering ? 0.35 : 0.25,
                        ),
                        blurRadius: _hovering ? 24 : 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: enabled ? widget.onPressed : null,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.24),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              widget.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: 0.2,
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
        );
      },
    );
  }
}

class AuthEntryPage extends StatefulWidget {
  const AuthEntryPage({
    required this.authStore,
    required this.onAuthed,
    this.bootstrapHint = '',
    super.key,
  });

  final AuthStore authStore;
  final ValueChanged<AuthSession> onAuthed;
  final String bootstrapHint;

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
  void initState() {
    super.initState();
    _error = widget.bootstrapHint;
  }

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
      body: _AtmosphericBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 260),
                tween: Tween<double>(begin: 20, end: 0),
                curve: Curves.easeOutCubic,
                builder: (context, dy, child) {
                  final opacity = (1 - dy / 20).clamp(0.0, 1.0);
                  return Transform.translate(
                    offset: Offset(0, dy),
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: _GlassPanel(
                    radius: 32,
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, color: kFairyRose),
                            SizedBox(width: 8),
                            Text(
                              '城市灵童话站',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.64,
                                color: kFairyInk,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '欢迎回来，今天也一起去发现生活里的小魔法。',
                          style: TextStyle(
                            color: kFairyInkSubtle,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<_AuthMode>(
                          style: const ButtonStyle(
                            textStyle: WidgetStatePropertyAll(
                              TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
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
                              prefixIcon: Icon(Icons.verified_user_outlined),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _CandyPrimaryButton(
                          onPressed: _submitting ? () {} : _submit,
                          enabled: !_submitting,
                          breathe: true,
                          icon: _mode == _AuthMode.login
                              ? Icons.login
                              : Icons.check_circle,
                          label: _mode == _AuthMode.login ? '登录进入' : '注册并进入',
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
                              color: const Color(0xFFFDEDEE)
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
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
  String _bootError = '';
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _api.init();
      await _authStore.init().timeout(const Duration(seconds: 8));
      final restored = await _authStore.restoreSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = restored;
        _bootReady = true;
        _bootError = '';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _bootReady = true;
        _bootError = '初始化异常，已进入离线登录模式：$e';
      });
    }
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
        bootstrapHint: _bootError,
        onAuthed: (nextSession) {
          if (!mounted) {
            return;
          }
          setState(() {
            _session = nextSession;
            _tabIndex = 0;
            _bootError = '';
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
      ProfilePage(
        api: _api,
        refreshSignal: _captureVersion,
        session: session,
        onOpenApiSettings: _openBackendSettings,
        onLogout: _logout,
      ),
    ];

    return Scaffold(
      appBar: _tabIndex == 0
          ? null
          : AppBar(
              title: Text(_titleForTab(session)),
              actions: [
                if (_tabIndex != 3) ...[
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
              ],
            ),
      body: tabs[_tabIndex],
      bottomNavigationBar: _buildFrostedBottomNav(),
    );
  }

  String _titleForTab(AuthSession session) {
    switch (_tabIndex) {
      case 1:
        return '图鉴';
      case 2:
        return '报告';
      case 3:
        return session.isDebug ? '我的（调试）' : '我的';
      default:
        return session.isDebug ? '城市灵（调试模式）' : '城市灵';
    }
  }

  Widget _buildFrostedBottomNav() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + bottomInset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x122D2A38),
                  blurRadius: 18,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: NavigationBar(
              height: 72,
              backgroundColor: Colors.transparent,
              selectedIndex: _tabIndex,
              onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
              destinations: [
                NavigationDestination(
                  icon: _buildUnselectedNavIcon(Icons.travel_explore_outlined),
                  selectedIcon: _buildSelectedNavIcon(Icons.travel_explore),
                  label: '探索',
                ),
                NavigationDestination(
                  icon: _buildUnselectedNavIcon(Icons.auto_awesome_outlined),
                  selectedIcon: _buildSelectedNavIcon(Icons.auto_awesome),
                  label: '图鉴',
                ),
                NavigationDestination(
                  icon: _buildUnselectedNavIcon(Icons.summarize_outlined),
                  selectedIcon: _buildSelectedNavIcon(Icons.summarize),
                  label: '报告',
                ),
                NavigationDestination(
                  icon: _buildUnselectedNavIcon(Icons.person_outline),
                  selectedIcon: _buildSelectedNavIcon(Icons.person),
                  label: '我的',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnselectedNavIcon(IconData icon) {
    return Opacity(
      opacity: 0.6,
      child: Icon(icon, color: kFairyInkSubtle),
    );
  }

  Widget _buildSelectedNavIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF2EAF8).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
      ),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kFairyRose, kFairyRoseDeep],
          ).createShader(bounds);
        },
        child: Icon(icon, color: Colors.white, size: 22),
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
  String _lastDetectedImageUrl = '';

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
  final Set<int> _storyVoiceGeneratingIndexes = <int>{};
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
    return _AtmosphericBackground(
      showStars: false,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 250),
              tween: Tween<double>(begin: 22, end: 0),
              curve: Curves.easeOutCubic,
              builder: (context, dy, child) {
                return Transform.translate(offset: Offset(0, dy), child: child);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _GlassPanel(
                  radius: 30,
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '梦幻探索',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.64,
                          color: kFairyInk,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isDebug
                            ? '当前是调试测试模式，你可以快速验证完整流程。'
                            : '先输入孩子信息，再开始今天的童话识别旅程。',
                        style: const TextStyle(
                          color: kFairyInkSubtle,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
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
                            style: TextButton.styleFrom(
                              foregroundColor: kFairyRoseDeep,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _childIdCtrl,
                        decoration: const InputDecoration(
                          labelText: '孩子 ID',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '孩子年龄（3-15）',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _CandyPrimaryButton(
                        onPressed: _enterExploreMode,
                        icon: Icons.play_arrow_rounded,
                        label: '进入识别',
                        breathe: true,
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
    final safeTop = MediaQuery.paddingOf(context).top;
    final storyModeActive = _scanResult != null && !_scanCardCollapsed;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildCameraBackground()),
        if (!storyModeActive)
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
                          onPressed: _busy || _detecting
                              ? null
                              : _pickPhotoAndGenerate,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.white,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
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
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
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
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
                          ),
                          tooltip: '退出登录',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildDetectionBadge(),
              ],
            ),
          ),
        if (_scanResult != null && !storyModeActive)
          Positioned(
            left: 12,
            right: 12,
            bottom: 120,
            child: Align(
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
            ),
          ),
        if (storyModeActive && _scanResult != null)
          Positioned.fill(
            child: _buildStoryFullscreen(_scanResult!),
          ),
        if (!storyModeActive)
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
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

  Widget _buildStoryFullscreen(ScanResult scan) {
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final companionName = _companionScene?.characterName ?? scan.spirit.name;
    final currentLine = _currentStoryLine;
    final hasStoryLine = currentLine != null;
    final displaySpeaker = hasStoryLine ? currentLine.speaker : companionName;
    final displayText = hasStoryLine
        ? currentLine.text
        : (_companionScene == null ? '剧情生成中，请稍候...' : '剧情准备中...');
    final scene = _companionScene;
    final canTapDialogToAdvance = _canTapDialogToAdvance;
    final canRetreatStory = _canRetreatStory;
    final hasSceneImage = scene != null &&
        ((scene.characterImageBytes != null &&
                scene.characterImageBytes!.isNotEmpty) ||
            scene.characterImageUrl.trim().isNotEmpty);

    if (!hasSceneImage) {
      return DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 12),
              const Text(
                '剧情图片生成中...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '图片加载完成后自动进入剧情',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _dismissScanCard,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('退出剧情'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCompanionImage(scene),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.30),
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.56),
                ],
                stops: const [0, 0.46, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 14,
          right: 14,
          child: Row(
            children: [
              Expanded(child: _buildDetectionBadge()),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _dismissScanCard,
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withValues(alpha: 0.38),
                ),
                tooltip: '关闭剧情',
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: viewInsetsBottom + safeBottom + 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.46),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.26),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canTapDialogToAdvance
                        ? () {
                            unawaited(_advanceStoryLine());
                          }
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFBE8B0), Color(0xFFE7C36A)],
                            ),
                            borderRadius: BorderRadius.circular(999),
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
                        const SizedBox(height: 10),
                        Text(
                          displayText,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.45,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                              fillColor: Colors.white.withValues(alpha: 0.95),
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
                                ? '你已经完成本轮问答，可以退出剧情继续探索。'
                                : (canTapDialogToAdvance
                                    ? '点击聊天框或右箭头继续剧情，可用左箭头回看。'
                                    : (canRetreatStory
                                        ? '已到当前末句，可用左箭头回看。'
                                        : '等待剧情加载或角色回应。')),
                            style: const TextStyle(
                              color: Color(0xFFE3E7FB),
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: canRetreatStory
                            ? () async {
                                await _retreatStoryLine();
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.10),
                        ),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('上一句'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () async {
                                await _playCurrentStoryVoice();
                              },
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.10),
                        ),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('播放'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: canTapDialogToAdvance
                            ? () async {
                                await _advanceStoryLine();
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.10),
                        ),
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('下一句'),
                      ),
                      if (_busy) ...[
                        const SizedBox(width: 10),
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
      _lastDetectedImageUrl = '';
    });
    try {
      if (controller.value.isTakingPicture) {
        return;
      }

      final frame = await controller.takePicture();
      final imageBytes = await frame.readAsBytes();
      await _detectFromImageBytes(imageBytes, fileName: 'camera_capture.jpg');
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
        _lastDetectedImageUrl = '';
      });
      await _detectFromImageBytes(
        imageBytes,
        fileName: picked.name.isEmpty ? 'gallery_upload.jpg' : picked.name,
      );
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

  Future<void> _detectFromImageBytes(
    Uint8List imageBytes, {
    required String fileName,
  }) async {
    final imageUrl = await widget.api.uploadImage(
      bytes: imageBytes,
      fileName: fileName,
    );
    final match = await widget.api.scanImage(
      childId: _childId,
      childAge: _childAge,
      imageUrl: imageUrl,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _detectedLabel = _normalizeObjectLabel(match.detectedLabel);
      _detectedRawLabel = match.rawLabel;
      _detectedReason = match.reason;
      _lastDetectedImageUrl = imageUrl;
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
        sourceImageUrl: _lastDetectedImageUrl,
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

      unawaited(_prefetchStoryVoices(scan, startIndex: 1));
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
      unawaited(_prefetchStoryVoices(scan, startIndex: 0));
      _showSnack('剧情自动生成失败，已切换基础对话模式。');
    }
  }

  Future<void> _playCurrentStoryVoice() async {
    var line = _currentStoryLine;
    if (line == null) {
      _showSnack('剧情还在准备中，请稍候。');
      return;
    }
    var audio = line.voiceAudioBase64.trim();
    if (audio.isEmpty) {
      final scan = _scanResult;
      final currentIndex = _currentStoryIndex;
      if (scan != null && currentIndex >= 0) {
        await _ensureStoryLineVoice(scan, currentIndex, silent: true);
        line = _currentStoryLine;
        if (line != null) {
          audio = line.voiceAudioBase64.trim();
        }
      }
      if (audio.isEmpty) {
        _showSnack('当前句暂无语音。');
        return;
      }
    }
    if (line == null) {
      _showSnack('剧情还在准备中，请稍候。');
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
      _showSnack(_quizSolved ? '本轮问答已完成。' : '请先点击画面推进到提问。');
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
      var answerCapturedNow = false;
      if (!_quizSolved) {
        final answer = await widget.api.submitAnswer(
          sessionId: scan.sessionId,
          childId: _childId,
          answer: childMessage,
        );
        if (answer.correct) {
          answerCorrectNow = true;
          answerCapturedNow = answer.captured;
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
      if (answerCorrectNow && answerCapturedNow) {
        hints.add('系统：孩子刚刚回答正确并已完成收集，请先祝贺，再收尾。');
      } else if (answerCorrectNow && !answerCapturedNow) {
        hints.add('系统：孩子刚刚回答正确，已记录识别但未计入勋章收集，请先鼓励观察，再收尾。');
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
      unawaited(_prefetchStoryVoices(scan, startIndex: _currentStoryIndex));
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

  Future<void> _retreatStoryLine() async {
    if (!_canRetreatStory) {
      _showSnack('已经是当前剧情第一句。');
      return;
    }
    setState(() {
      _currentStoryIndex -= 1;
      _syncCurrentStoryToHistory();
    });
    await _playCurrentStoryVoice();
  }

  Future<void> _prefetchStoryVoices(
    ScanResult scan, {
    int startIndex = 0,
  }) async {
    final normalizedStart = startIndex < 0 ? 0 : startIndex;
    final futures = <Future<void>>[];
    for (var i = normalizedStart; i < _storyLines.length; i++) {
      if (_storyLines[i].voiceAudioBase64.trim().isNotEmpty) {
        continue;
      }
      futures.add(_ensureStoryLineVoice(scan, i, silent: true));
    }
    if (futures.isEmpty) {
      return;
    }
    await Future.wait(futures);
  }

  Future<void> _ensureStoryLineVoice(
    ScanResult scan,
    int index, {
    bool silent = false,
  }) async {
    if (!mounted || index < 0 || index >= _storyLines.length) {
      return;
    }
    final line = _storyLines[index];
    if (line.voiceAudioBase64.trim().isNotEmpty) {
      return;
    }
    if (_storyVoiceGeneratingIndexes.contains(index)) {
      return;
    }
    _storyVoiceGeneratingIndexes.add(index);
    try {
      final voice = await widget.api.synthesizeCompanionVoice(
        childId: _childId,
        childAge: _childAge,
        objectType: scan.objectType,
        text: line.text,
      );
      if (!mounted || index < 0 || index >= _storyLines.length) {
        return;
      }
      final current = _storyLines[index];
      if (current.voiceAudioBase64.trim().isNotEmpty) {
        return;
      }
      if (current.text != line.text || current.speaker != line.speaker) {
        return;
      }
      setState(() {
        _storyLines[index] = current.copyWith(
          voiceAudioBase64: voice.voiceAudioBase64,
          voiceMimeType: voice.voiceMimeType,
        );
      });
    } catch (e) {
      if (!silent) {
        _showSnack('语音生成失败：$e');
      }
    } finally {
      _storyVoiceGeneratingIndexes.remove(index);
    }
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

  bool get _canTapDialogToAdvance {
    return _scanResult != null &&
        !_scanCardCollapsed &&
        !_busy &&
        _canAdvanceStory;
  }

  bool get _canRetreatStory {
    return _scanResult != null &&
        !_scanCardCollapsed &&
        !_busy &&
        _currentStoryIndex > 0 &&
        _currentStoryIndex < _storyLines.length;
  }

  void _resetStoryLines(List<_StoryLine> lines) {
    _companionMessages.clear();
    _storyVoiceGeneratingIndexes.clear();
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
    _storyVoiceGeneratingIndexes.clear();
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
      _lastDetectedImageUrl = '';
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
      _lastDetectedImageUrl = '';
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

  _StoryLine copyWith({
    String? speaker,
    String? text,
    String? voiceAudioBase64,
    String? voiceMimeType,
    bool? requiresAnswerAfter,
  }) {
    return _StoryLine(
      speaker: speaker ?? this.speaker,
      text: text ?? this.text,
      voiceAudioBase64: voiceAudioBase64 ?? this.voiceAudioBase64,
      voiceMimeType: voiceMimeType ?? this.voiceMimeType,
      requiresAnswerAfter: requiresAnswerAfter ?? this.requiresAnswerAfter,
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

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    required this.api,
    required this.refreshSignal,
    required this.session,
    required this.onOpenApiSettings,
    required this.onLogout,
    super.key,
  });

  final ApiClient api;
  final ValueNotifier<int> refreshSignal;
  final AuthSession session;
  final Future<void> Function() onOpenApiSettings;
  final Future<void> Function() onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = false;
  String _error = '';
  int _totalSpirits = 0;
  int _totalCaptures = 0;
  int _todayCaptures = 0;
  int _todayKnowledgePoints = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_refreshSummary);
    _refreshSummary();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_refreshSummary);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final avatarText = session.displayName.isEmpty
        ? '?'
        : session.displayName.substring(0, 1).toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF0F9), Color(0xFFF2F6FF), Color(0xFFFFFCE8)],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _refreshSummary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF39AC2),
                    Color(0xFFB3DAFF),
                    Color(0xFFAEE8D7),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withValues(alpha: 0.92),
                      foregroundColor: const Color(0xFF8D5FAF),
                      child: Text(
                        avatarText,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _buildTag(
                                session.isDebug ? '调试模式' : '正式账号',
                                session.isDebug
                                    ? const Color(0xFFFFE3A8)
                                    : const Color(0xFFFFD6EA),
                                const Color(0xFF6A4E86),
                              ),
                              _buildTag(
                                '孩子ID: ${session.preferredChildId}',
                                Colors.white.withValues(alpha: 0.24),
                                Colors.white,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '账号：${session.accountId}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Row(
                  children: [
                    _buildStatItem('图鉴精灵', _totalSpirits.toString()),
                    _buildStatItem('累计收集', _totalCaptures.toString()),
                    _buildStatItem('今日收集', _todayCaptures.toString()),
                    _buildStatItem('今日知识点', _todayKnowledgePoints.toString()),
                  ],
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 14),
            const Text(
              '常用功能',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildQuickAction(
                  icon: Icons.favorite_outline,
                  label: '我的收藏',
                  onTap: () => _openPage(const FavoritesPage()),
                ),
                _buildQuickAction(
                  icon: Icons.chat_bubble_outline,
                  label: '消息中心',
                  onTap: () => _openPage(const MessageCenterPage()),
                ),
                _buildQuickAction(
                  icon: Icons.auto_stories_outlined,
                  label: '学习记录',
                  onTap: () => _openPage(
                    LearningRecordPage(
                      totalCaptures: _totalCaptures,
                      todayCaptures: _todayCaptures,
                      todayKnowledgePoints: _todayKnowledgePoints,
                    ),
                  ),
                ),
                _buildQuickAction(
                  icon: Icons.card_giftcard,
                  label: '成长勋章',
                  onTap: () => _openPage(
                    AchievementBadgesPage(
                      api: widget.api,
                      childId: widget.session.preferredChildId,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  _buildMenuTile(
                    icon: Icons.person_outline,
                    title: '个人资料',
                    subtitle: '管理头像、昵称与展示信息',
                    onTap: () => _openPage(
                      ProfileDetailPage(session: widget.session),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.notifications_none,
                    title: '消息通知',
                    subtitle: '配置提醒与通知偏好',
                    onTap: () => _openPage(const MessageCenterPage()),
                  ),
                  _buildMenuTile(
                    icon: Icons.verified_user_outlined,
                    title: '隐私与安全',
                    subtitle: '账号安全、权限与隐私设置',
                    onTap: () => _openPage(const PrivacySecurityPage()),
                  ),
                  _buildMenuTile(
                    icon: Icons.settings_ethernet,
                    title: '后端地址',
                    subtitle: '联调环境切换入口',
                    onTap: widget.onOpenApiSettings,
                  ),
                  _buildMenuTile(
                    icon: Icons.help_outline,
                    title: '帮助与反馈',
                    subtitle: '常见问题与问题反馈',
                    onTap: () => _openPage(const HelpFeedbackPage()),
                    showDivider: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: widget.onLogout,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC7637F),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8D5FAF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF5A6D6A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8EAFE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(icon, color: const Color(0xFF8D5FAF)),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B5A7F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required FutureOr<void> Function() onTap,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: const Color(0xFF8D5FAF)),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(Future<void>.value(onTap())),
        ),
        if (showDivider) const Divider(height: 1, indent: 56, endIndent: 14),
      ],
    );
  }

  Future<void> _refreshSummary() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final childId = widget.session.preferredChildId;
      final pokedexFuture = widget.api.fetchPokedex(childId);
      final reportFuture = widget.api.fetchDailyReport(
        childId: childId,
        date: DateTime.now(),
      );
      final results = await Future.wait<dynamic>([pokedexFuture, reportFuture]);
      final entries = results[0] as List<PokedexEntry>;
      final report = results[1] as DailyReport;
      if (!mounted) {
        return;
      }
      setState(() {
        _totalSpirits = entries.length;
        _totalCaptures = entries.fold<int>(
          0,
          (sum, item) => sum + item.captures,
        );
        _todayCaptures = report.totalCaptured;
        _todayKnowledgePoints = report.knowledgePoints.length;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '加载统计失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class ProfileDetailPage extends StatefulWidget {
  const ProfileDetailPage({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  State<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<ProfileDetailPage> {
  static const String _nickKeyPrefix = 'cityling_profile_nick_';
  static const String _guardianKeyPrefix = 'cityling_profile_guardian_';

  late final TextEditingController _nickCtrl;
  late final TextEditingController _guardianCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nickCtrl = TextEditingController(text: widget.session.displayName);
    _guardianCtrl = TextEditingController();
    _loadLocalProfile();
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _guardianCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '基础信息',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nickCtrl,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      hintText: '如：小小探险家',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _guardianCtrl,
                    decoration: const InputDecoration(
                      labelText: '家长称呼',
                      hintText: '如：妈妈/爸爸',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('账号ID：${widget.session.accountId}'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? '保存中...' : '保存资料'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLocalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final account = widget.session.accountId;
    _nickCtrl.text = prefs.getString('$_nickKeyPrefix$account') ??
        widget.session.displayName;
    _guardianCtrl.text = prefs.getString('$_guardianKeyPrefix$account') ?? '';
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    final account = widget.session.accountId;
    await prefs.setString('$_nickKeyPrefix$account', _nickCtrl.text.trim());
    await prefs.setString(
      '$_guardianKeyPrefix$account',
      _guardianCtrl.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存个人资料')),
    );
  }
}

class MessageCenterPage extends StatelessWidget {
  const MessageCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final messages = <(String, String, bool)>[
      ('今日识别任务已更新', '去探索页完成 1 次识别可点亮新星星。', true),
      ('本周成长报告可查看', '你家小朋友本周已经收集 3 个新知识点。', false),
      ('新勋章解锁提醒', '连续 3 天学习可解锁“晨光探索者”。', false),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('消息中心')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, i) {
          final item = messages[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    item.$3 ? const Color(0xFFFFDDEB) : const Color(0xFFE8F1FF),
                child: Icon(
                  item.$3 ? Icons.mark_chat_unread : Icons.mark_chat_read,
                  color: const Color(0xFF7B5DA0),
                ),
              ),
              title: Text(item.$1),
              subtitle: Text(item.$2),
              trailing: item.$3
                  ? const Chip(
                      label: Text('未读'),
                      backgroundColor: Color(0xFFFFEAF3),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: messages.length,
      ),
    );
  }
}

class LearningRecordPage extends StatelessWidget {
  const LearningRecordPage({
    required this.totalCaptures,
    required this.todayCaptures,
    required this.todayKnowledgePoints,
    super.key,
  });

  final int totalCaptures;
  final int todayCaptures;
  final int todayKnowledgePoints;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习记录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _metric('累计收集', '$totalCaptures'),
                  _metric('今日收集', '$todayCaptures'),
                  _metric('今日知识点', '$todayKnowledgePoints'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '近期学习轨迹',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.auto_stories),
              title: Text('认识了路边“井盖”'),
              subtitle: Text('获得新知识：井盖图案代表地下管网信息。'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.emoji_nature),
              title: Text('识别了小区里的树'),
              subtitle: Text('获得新知识：树叶形状可帮助辨别树种。'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF7B5DA0),
            ),
          ),
          const SizedBox(height: 6),
          Text(label),
        ],
      ),
    );
  }
}

class AchievementBadgesPage extends StatefulWidget {
  const AchievementBadgesPage({
    required this.api,
    required this.childId,
    super.key,
  });

  final ApiClient api;
  final String childId;

  @override
  State<AchievementBadgesPage> createState() => _AchievementBadgesPageState();
}

class _AchievementBadgesPageState extends State<AchievementBadgesPage> {
  bool _loading = false;
  String _error = '';
  List<PokedexBadge> _badges = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('成长勋章墙')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF4D7), Color(0xFFEDE6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                '把勋章挂在展示墙上吧。灰色代表未获得，彩色代表已点亮，点击任意勋章查看要收集的物品与进度。',
                style: TextStyle(
                  color: Color(0xFF5F5673),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 10),
            if (_badges.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('暂无勋章数据')),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.95,
                ),
                itemCount: _badges.length,
                itemBuilder: (context, i) {
                  final badge = _badges[i];
                  return Card(
                    color: badge.unlocked
                        ? const Color(0xFFFFF2C7)
                        : const Color(0xFFF3F1F7),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showBadgeDetailSheet(context, badge),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _buildBadgeImage(badge),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${badge.categoryId}. ${badge.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: badge.unlocked
                                    ? const Color(0xFF6F4D0B)
                                    : const Color(0xFF7A6D88),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '进度 ${badge.progress}/${badge.target}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6E6581),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeImage(PokedexBadge badge) {
    if (badge.imageUrl.trim().isEmpty) {
      return _buildBadgeFallbackIcon(badge);
    }
    final image = Image.network(
      badge.imageUrl.trim(),
      fit: BoxFit.cover,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (context, error, stackTrace) =>
          _buildBadgeFallbackIcon(badge),
    );
    if (badge.unlocked) {
      return image;
    }
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_kGrayScaleMatrix),
      child: Opacity(opacity: 0.72, child: image),
    );
  }

  Widget _buildBadgeFallbackIcon(PokedexBadge badge) {
    final bool unlocked = badge.unlocked;
    final Color frame =
        unlocked ? const Color(0xFFE6C26A) : const Color(0xFFC6C2CE);
    final List<Color> gradient = unlocked
        ? const [Color(0xFFFFF4CF), Color(0xFFFFE39A)]
        : const [Color(0xFFEAE7EF), Color(0xFFD7D3DD)];
    final List<Color> emblemGradient = unlocked
        ? const [Color(0xFFFFF0AE), Color(0xFFE3B347)]
        : const [Color(0xFFE2DFE8), Color(0xFFBEB8C8)];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: frame, width: 1.2),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -16,
            top: -14,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (unlocked
                        ? const Color(0xFFFFF7DA)
                        : const Color(0xFFF0EDF4))
                    .withValues(alpha: 0.65),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: emblemGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: frame, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 32,
                    color: unlocked
                        ? const Color(0xFFAF7A00)
                        : const Color(0xFF958EA2),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 14,
                  decoration: BoxDecoration(
                    color: unlocked
                        ? const Color(0xFFF2C76A)
                        : const Color(0xFFC0BBC8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
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
      final badges = await widget.api.fetchPokedexBadges(widget.childId);
      if (!mounted) {
        return;
      }
      setState(() => _badges = badges);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '加载勋章失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    const favorites = ['会发光的路牌', '会唱歌的邮箱', '跳舞的小树', '微笑井盖'];
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: favorites.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => Card(
          child: ListTile(
            leading: const Icon(Icons.favorite, color: Color(0xFFE46FA3)),
            title: Text(favorites[i]),
            subtitle: const Text('点击后可跳转对应故事页（下一版接入）'),
          ),
        ),
      ),
    );
  }
}

class PrivacySecurityPage extends StatefulWidget {
  const PrivacySecurityPage({super.key});

  @override
  State<PrivacySecurityPage> createState() => _PrivacySecurityPageState();
}

class _PrivacySecurityPageState extends State<PrivacySecurityPage> {
  bool _allowVoice = true;
  bool _allowAnalytics = false;
  bool _privateMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私与安全')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _allowVoice,
                  title: const Text('允许语音播放'),
                  subtitle: const Text('用于角色对话语音功能'),
                  onChanged: (v) => setState(() => _allowVoice = v),
                ),
                SwitchListTile(
                  value: _allowAnalytics,
                  title: const Text('匿名体验统计'),
                  subtitle: const Text('帮助我们优化儿童学习体验'),
                  onChanged: (v) => setState(() => _allowAnalytics = v),
                ),
                SwitchListTile(
                  value: _privateMode,
                  title: const Text('儿童隐私模式'),
                  subtitle: const Text('隐藏部分互动信息与历史记录'),
                  onChanged: (v) => setState(() => _privateMode = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HelpFeedbackPage extends StatefulWidget {
  const HelpFeedbackPage({super.key});

  @override
  State<HelpFeedbackPage> createState() => _HelpFeedbackPageState();
}

class _HelpFeedbackPageState extends State<HelpFeedbackPage> {
  final TextEditingController _feedbackCtrl = TextEditingController();

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('帮助与反馈')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.help_outline),
              title: Text('为什么有时候识别会失败？'),
              subtitle: Text('可尝试在光线更稳定的环境下重新拍摄。'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.help_outline),
              title: Text('如何切换孩子账号？'),
              subtitle: Text('在“我的”页点击退出登录后重新登录即可。'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '问题反馈',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _feedbackCtrl,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '请输入你遇到的问题或建议...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('反馈已记录，感谢你的建议')),
                      );
                      _feedbackCtrl.clear();
                    },
                    child: const Text('提交反馈'),
                  ),
                ],
              ),
            ),
          ),
        ],
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
  bool _badgeExpanded = false;
  String _error = '';
  List<PokedexEntry> _entries = const [];
  List<PokedexBadge> _badges = const [];

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
          if (_badges.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              color: const Color(0xFFF8F4FB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _badgeExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _badgeExpanded = expanded);
                  },
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  title: const Text(
                    '勋章 Tab',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _badgeExpanded ? '点击收起勋章墙' : '点击展开查看勋章墙',
                    style: const TextStyle(
                      color: Color(0xFF6E6581),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '规则：每个勋章需完成该类全部示例收集后才会点亮。',
                            style: TextStyle(
                              color: Color(0xFF6E6581),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.95,
                            ),
                            itemCount: _badges.length,
                            itemBuilder: (context, i) {
                              final badge = _badges[i];
                              final image = badge.imageUrl.trim();
                              return Card(
                                color: badge.unlocked
                                    ? const Color(0xFFFFF2C7)
                                    : const Color(0xFFF3F1F7),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      _showBadgeDetailSheet(context, badge),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Center(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: image.isNotEmpty
                                                  ? _buildBadgeImage(badge)
                                                  : _buildBadgeFallbackIcon(
                                                      badge),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${badge.categoryId}. ${badge.name}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: badge.unlocked
                                                ? const Color(0xFF6F4D0B)
                                                : const Color(0xFF7A6D88),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '进度 ${badge.progress}/${badge.target}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6E6581),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
      final childId = _childIdCtrl.text.trim();
      final results = await Future.wait<dynamic>([
        widget.api.fetchPokedex(childId),
        widget.api.fetchPokedexBadges(childId),
      ]);
      setState(() {
        _entries = results[0] as List<PokedexEntry>;
        _badges = results[1] as List<PokedexBadge>;
      });
    } catch (e) {
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildBadgeFallbackIcon(PokedexBadge badge) {
    final bool unlocked = badge.unlocked;
    final Color frame =
        unlocked ? const Color(0xFFE6C26A) : const Color(0xFFC6C2CE);
    final List<Color> gradient = unlocked
        ? const [Color(0xFFFFF4CF), Color(0xFFFFE39A)]
        : const [Color(0xFFEAE7EF), Color(0xFFD7D3DD)];
    final List<Color> emblemGradient = unlocked
        ? const [Color(0xFFFFF0AE), Color(0xFFE3B347)]
        : const [Color(0xFFE2DFE8), Color(0xFFBEB8C8)];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: frame, width: 1.2),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -16,
            top: -14,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (unlocked
                        ? const Color(0xFFFFF7DA)
                        : const Color(0xFFF0EDF4))
                    .withValues(alpha: 0.65),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: emblemGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: frame, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 32,
                    color: unlocked
                        ? const Color(0xFFAF7A00)
                        : const Color(0xFF958EA2),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 14,
                  decoration: BoxDecoration(
                    color: unlocked
                        ? const Color(0xFFF2C76A)
                        : const Color(0xFFC0BBC8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeImage(PokedexBadge badge) {
    final image = Image.network(
      badge.imageUrl.trim(),
      fit: BoxFit.cover,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (context, error, stackTrace) =>
          _buildBadgeFallbackIcon(badge),
    );
    if (badge.unlocked) {
      return image;
    }
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_kGrayScaleMatrix),
      child: Opacity(opacity: 0.72, child: image),
    );
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

  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final base = baseUrl;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/api/v1/media/upload'),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName.trim().isEmpty ? 'upload.jpg' : fileName.trim(),
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final body = _decode(response);
    return (body['image_url'] as String? ?? '').trim();
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

  Future<List<PokedexBadge>> fetchPokedexBadges(String childId) async {
    final base = baseUrl;
    final response = await http.get(
      Uri.parse(
        '$base/api/v1/pokedex/badges?child_id=${Uri.encodeQueryComponent(childId)}',
      ),
    );
    final body = _decode(response);
    final badges = (body['badges'] as List<dynamic>? ?? const []);
    return badges
        .map((raw) => PokedexBadge.fromJson(raw as Map<String, dynamic>))
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
    String sourceImageUrl = '',
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
        'source_image_url': sourceImageUrl,
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

  Future<CompanionVoiceResult> synthesizeCompanionVoice({
    required String childId,
    required int childAge,
    required String objectType,
    required String text,
  }) async {
    final base = baseUrl;
    final response = await http.post(
      Uri.parse('$base/api/v1/companion/voice'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'child_id': childId,
        'child_age': childAge,
        'object_type': objectType,
        'text': text,
      }),
    );
    final body = _decode(response);
    return CompanionVoiceResult.fromJson(body);
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

class PokedexBadge {
  PokedexBadge({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.code,
    required this.description,
    required this.recordScope,
    required this.rule,
    required this.imageUrl,
    required this.unlocked,
    required this.progress,
    required this.target,
    required this.examples,
    required this.collectedExamples,
  });

  final String id;
  final String categoryId;
  final String name;
  final String code;
  final String description;
  final String recordScope;
  final String rule;
  final String imageUrl;
  final bool unlocked;
  final int progress;
  final int target;
  final List<String> examples;
  final List<String> collectedExamples;

  factory PokedexBadge.fromJson(Map<String, dynamic> json) {
    final examples = (json['examples'] as List<dynamic>? ?? const []);
    final collected =
        (json['collected_examples'] as List<dynamic>? ?? const []);
    return PokedexBadge(
      id: json['id'] as String? ?? '',
      categoryId: json['category_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      description: json['description'] as String? ?? '',
      recordScope: json['record_scope'] as String? ?? '',
      rule: json['rule'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      unlocked: json['unlocked'] as bool? ?? false,
      progress: json['progress'] as int? ?? 0,
      target: json['target'] as int? ?? 1,
      examples: examples.map((item) => item.toString()).toList(),
      collectedExamples: collected.map((item) => item.toString()).toList(),
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

class CompanionVoiceResult {
  CompanionVoiceResult({
    required this.voiceAudioBase64,
    required this.voiceMimeType,
  });

  final String voiceAudioBase64;
  final String voiceMimeType;

  factory CompanionVoiceResult.fromJson(Map<String, dynamic> json) {
    return CompanionVoiceResult(
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

void _showBadgeDetailSheet(BuildContext context, PokedexBadge badge) {
  final collectedSet = badge.collectedExamples.toSet();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final progress = badge.target <= 0
          ? 0.0
          : (badge.progress / badge.target).clamp(0, 1).toDouble();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${badge.categoryId}. ${badge.name}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                badge.unlocked ? '已点亮' : '未点亮',
                style: TextStyle(
                  color: badge.unlocked
                      ? const Color(0xFFAF7A00)
                      : const Color(0xFF6E6581),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                badge.description,
                style: const TextStyle(color: Color(0xFF5F5673)),
              ),
              const SizedBox(height: 10),
              Text('进度 ${badge.progress}/${badge.target}'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: const Color(0xFFE6E1EC),
                color: badge.unlocked
                    ? const Color(0xFFE4AE2F)
                    : const Color(0xFF9D94AA),
              ),
              const SizedBox(height: 10),
              Text(
                '收集规则：${badge.rule}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6E6581)),
              ),
              const SizedBox(height: 12),
              const Text(
                '要收集的物品',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (badge.examples.isEmpty)
                const Text('暂无示例物品。')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: badge.examples.map((item) {
                    final matched = collectedSet.contains(item);
                    return Chip(
                      avatar: Icon(
                        matched
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: matched
                            ? const Color(0xFF4E9A52)
                            : const Color(0xFF8C829B),
                      ),
                      backgroundColor: matched
                          ? const Color(0xFFE7F7DF)
                          : const Color(0xFFF2EEF6),
                      label: Text(item),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      );
    },
  );
}
