import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
        useMaterial3: true,
      ),
      home: const CityLingHomePage(),
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
  final ValueNotifier<int> _captureVersion = ValueNotifier<int>(0);
  int _tabIndex = 0;
  bool _apiReady = false;

  @override
  void initState() {
    super.initState();
    _initApi();
  }

  Future<void> _initApi() async {
    await _api.init();
    if (!mounted) {
      return;
    }
    setState(() => _apiReady = true);
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

  @override
  Widget build(BuildContext context) {
    if (!_apiReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = [
      ExplorePage(
        api: _api,
        onCaptured: () => _captureVersion.value += 1,
        onOpenApiSettings: _openBackendSettings,
      ),
      PokedexPage(
        api: _api,
        refreshSignal: _captureVersion,
      ),
      DailyReportPage(
        api: _api,
        refreshSignal: _captureVersion,
      ),
    ];

    return Scaffold(
      appBar: _tabIndex == 0
          ? null
          : AppBar(
              title: const Text('城市灵'),
              actions: [
                IconButton(
                  onPressed: _openBackendSettings,
                  icon: const Icon(Icons.settings_ethernet),
                  tooltip: '后端地址',
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
    super.key,
  });

  final ApiClient api;
  final VoidCallback onCaptured;
  final Future<void> Function() onOpenApiSettings;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _childIdCtrl = TextEditingController(text: 'kid_1');
  final _ageCtrl = TextEditingController(text: '8');
  final _answerCtrl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _profileReady = false;
  String _childId = 'kid_1';
  int _childAge = 8;

  CameraController? _cameraController;

  String _detectedLabel = '';
  String _detectedRawLabel = '';
  String _detectedReason = '';

  bool _cameraInitializing = false;
  bool _cameraReady = false;
  bool _detecting = false;
  bool _busy = false;

  String _cameraError = '';
  ScanResult? _scanResult;

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
    _initCamera();
  }

  @override
  void dispose() {
    _childIdCtrl.dispose();
    _ageCtrl.dispose();
    _answerCtrl.dispose();

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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF4F3), Color(0xFFF7FBFA)],
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
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('先输入孩子信息，然后进入全屏识别模式。'),
                      const SizedBox(height: 16),
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
                        child: Text(
                          '孩子：$_childId · 年龄：$_childAge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
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
            child: _buildSpiritCard(_scanResult!),
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
            Text(
              '${scan.spirit.name}（${_labelToChinese(scan.objectType)}）',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('性格：${scan.spirit.personality}'),
            const SizedBox(height: 6),
            Text(scan.spirit.intro),
            const SizedBox(height: 8),
            if (scan.dialogues.isNotEmpty) ...[
              const Text('对话：', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ...scan.dialogues.map((line) => Text('• $line')),
              const SizedBox(height: 8),
            ],
            Text('知识点：${scan.fact}'),
            const SizedBox(height: 8),
            Text('问题：${scan.quiz}'),
            const SizedBox(height: 12),
            TextField(
              controller: _answerCtrl,
              decoration: const InputDecoration(
                labelText: '你的答案',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () async {
                      await _submitAnswer();
                    },
              icon: const Icon(Icons.catching_pokemon),
              label: Text(_busy ? '提交中...' : '提交并收集'),
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

    setState(() => _detecting = true);
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
      setState(() => _detecting = true);
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
              child: const Text('确认并生成'),
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
        _answerCtrl.clear();
      });
    } catch (e) {
      _showSnack('扫描失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submitAnswer() async {
    final scan = _scanResult;
    if (scan == null) {
      _showSnack('请先完成扫描。');
      return;
    }

    setState(() => _busy = true);
    try {
      final response = await widget.api.submitAnswer(
        sessionId: scan.sessionId,
        childId: _childId,
        answer: _answerCtrl.text.trim(),
      );
      if (!response.correct) {
        await _showWrongAnswerDialog(response.message);
        if (!mounted) {
          return;
        }
        setState(() {
          _scanResult = null;
          _answerCtrl.clear();
        });
        return;
      }

      _showSnack(response.message);
      if (response.captured && mounted) {
        widget.onCaptured();
      }
    } catch (e) {
      _showSnack('提交失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
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

  Future<void> _showWrongAnswerDialog(String message) async {
    final text = message.trim().isEmpty ? '回答错误，请重新识别后再试。' : message.trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('回答错误'),
          content: Text(text),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回识别'),
            ),
          ],
        );
      },
    );
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
      _detectedLabel = '';
      _detectedRawLabel = '';
      _detectedReason = '';
      _answerCtrl.clear();
    });
  }

  Future<void> _captureAndGenerate() async {
    await _detectFromFrame();
    if (!mounted || _detectedLabel.isEmpty) {
      return;
    }
    await _confirmDetectedObjectAndScan();
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
    super.key,
  });

  final ApiClient api;
  final ValueNotifier<int> refreshSignal;

  @override
  State<PokedexPage> createState() => _PokedexPageState();
}

class _PokedexPageState extends State<PokedexPage> {
  final _childIdCtrl = TextEditingController(text: 'kid_1');
  bool _loading = false;
  String _error = '';
  List<PokedexEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
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
    super.key,
  });

  final ApiClient api;
  final ValueNotifier<int> refreshSignal;

  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  final _childIdCtrl = TextEditingController(text: 'kid_1');
  DateTime _date = DateTime.now();
  bool _loading = false;
  String _error = '';
  DailyReport? _report;

  @override
  void initState() {
    super.initState();
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
