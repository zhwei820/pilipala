import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/models/tavern/character.dart';
import 'package:pilipala/pages/main/controller.dart';
import 'package:pilipala/services/tavern_service.dart';

import 'chat.dart';
import 'edit.dart';
import 'settings.dart';

class TavernPage extends StatefulWidget {
  const TavernPage({super.key});

  @override
  State<TavernPage> createState() => _TavernPageState();
}

class _TavernPageState extends State<TavernPage>
    with AutomaticKeepAliveClientMixin {
  final TavernService service = TavernService.to;
  late final AppLifecycleListener _lifecycle;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: () {
      // 选文件 / 选图片会让 App 短暂进入后台，此时不上锁
      if (!TavernPicker.picking) lockTavern();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() => service.unlocked.value
        ? const _CharacterListView()
        : _LockView(service: service));
  }
}

const String _tavernRoutePrefix = '/tavern/';

/// 打开酒馆子页面；统一路由前缀，上锁时据此关闭，避免后台回来后绕过密码直接看到聊天
Future<T?>? openTavernPage<T>(Widget page) =>
    Get.to<T>(() => page, routeName: '$_tavernRoutePrefix${page.runtimeType}');

void lockTavern() {
  TavernService.to.unlocked.value = false;
  if (Get.currentRoute.startsWith(_tavernRoutePrefix)) {
    Get.until(
        (route) => !(route.settings.name ?? '').startsWith(_tavernRoutePrefix));
  }
}

/// 选文件期间 App 会进入后台，标记出来避免误上锁
class TavernPicker {
  static bool picking = false;

  static Future<PlatformFile?> pick(FileType type,
      {List<String>? extensions}) async {
    picking = true;
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: extensions,
        withData: true,
      );
      return result?.files.single;
    } finally {
      picking = false;
    }
  }
}

class _LockView extends StatefulWidget {
  const _LockView({required this.service});

  final TavernService service;

  @override
  State<_LockView> createState() => _LockViewState();
}

class _LockViewState extends State<_LockView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  late final bool _creating = !widget.service.hasPassword;
  String? _error;
  bool _biometric = false;
  bool _authing = false;
  // 只在「变为可见」时自动弹一次指纹，用户取消后不反复弹
  bool _wasVisible = false;
  late final AppLifecycleListener _lifecycle;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _wasVisible = false,
      onResume: _onVisibilityChanged,
    );
    if (!_creating && widget.service.biometricEnabled) _initBiometric();
  }

  Future<void> _initBiometric() async {
    if (!await widget.service.canUseBiometric() || !mounted) return;
    setState(() => _biometric = true);
    if (Get.isRegistered<MainController>()) {
      _pageController = Get.find<MainController>().pageController
        ..addListener(_onVisibilityChanged);
    }
    _onVisibilityChanged();
  }

  /// 酒馆 tab 在前台、且没有其他页面盖在主页上
  bool get _visible {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    if (!Get.isRegistered<MainController>()) return true;
    final MainController main = Get.find<MainController>();
    final int index = main.pagesIds.indexOf(4);
    final PageController? pc = _pageController;
    final int current = pc != null && pc.hasClients && pc.page != null
        ? pc.page!.round()
        : main.selectedIndex;
    return index == current;
  }

  void _onVisibilityChanged() {
    if (!_biometric || !mounted) return;
    final bool visible = _visible;
    if (visible && !_wasVisible) _authBiometric();
    _wasVisible = visible;
  }

  Future<void> _authBiometric() async {
    if (_authing) return;
    _authing = true;
    try {
      if (await widget.service.authenticateBiometric()) {
        widget.service.unlocked.value = true;
      }
    } finally {
      _authing = false;
    }
  }

  @override
  void dispose() {
    _pageController?.removeListener(_onVisibilityChanged);
    _lifecycle.dispose();
    _input.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String password = _input.text;
    if (_creating) {
      if (password.length < 4) {
        setState(() => _error = '密码至少 4 位');
        return;
      }
      if (password != _confirm.text) {
        setState(() => _error = '两次输入不一致');
        return;
      }
      await widget.service.setPassword(password);
    } else if (!widget.service.verifyPassword(password)) {
      _input.clear();
      setState(() => _error = '密码错误');
      return;
    }
    widget.service.unlocked.value = true;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_bar, size: 56, color: colors.primary),
              const SizedBox(height: 12),
              Text(_creating ? '首次进入，请设置酒馆密码' : '输入密码进入酒馆',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              TextField(
                controller: _input,
                obscureText: true,
                // 指纹弹窗时不抢先弹出键盘
                autofocus: _creating || !widget.service.biometricEnabled,
                decoration: const InputDecoration(
                    labelText: '密码', border: OutlineInputBorder()),
                onSubmitted: _creating ? null : (_) => _submit(),
              ),
              if (_creating) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '再次输入', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(_creating ? '设置并进入' : '进入'),
                ),
              ),
              if (_biometric) ...[
                const SizedBox(height: 16),
                IconButton(
                  tooltip: '指纹解锁',
                  iconSize: 48,
                  color: colors.primary,
                  onPressed: _authBiometric,
                  icon: const Icon(Icons.fingerprint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterListView extends StatelessWidget {
  const _CharacterListView();

  TavernService get service => TavernService.to;

  Future<void> _importJson() async {
    final PlatformFile? file =
        await TavernPicker.pick(FileType.custom, extensions: ['json']);
    if (file == null) return;
    try {
      final String text = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();
      final TavernCharacter? character =
          TavernCharacter.fromCardJson(jsonDecode(text));
      if (character == null) {
        SmartDialog.showToast('不是有效的角色卡：缺少 name');
        return;
      }
      await service.saveCharacter(character);
      SmartDialog.showToast('已导入「${character.name}」');
    } on FormatException {
      SmartDialog.showToast('文件不是合法的 JSON');
    }
  }

  Future<void> _generate(BuildContext context) async {
    final TextEditingController idea = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 生成角色'),
        content: TextField(
          controller: idea,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '描述你想要的角色，如：冷淡的赛博朋克女黑客，嘴硬心软',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, idea.text.trim()),
              child: const Text('生成')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    openTavernPage(CharacterEditPage(generateFrom: text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('酒馆'),
        actions: [
          IconButton(
            tooltip: 'AI 生成角色',
            onPressed: () => _generate(context),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: '导入 JSON 角色卡',
            onPressed: _importJson,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => openTavernPage(const TavernSettingsPage()),
            icon: const Icon(Icons.settings_outlined),
          ),
          const IconButton(
            tooltip: '上锁',
            onPressed: lockTavern,
            icon: Icon(Icons.lock_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openTavernPage(const CharacterEditPage()),
        child: const Icon(Icons.add),
      ),
      body: Obx(() {
        if (service.characters.isEmpty) {
          return Center(
            child: Text('还没有角色\n点右下角新建，或用右上角 AI 生成 / 导入',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: service.characters.length,
          itemBuilder: (context, index) {
            final TavernCharacter c = service.characters[index];
            return ListTile(
              leading: TavernAvatar(character: c, size: 44),
              title: Text(c.name),
              subtitle: Text(
                c.description.isNotEmpty ? c.description : c.personality,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => openTavernPage(TavernChatPage(character: c)),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () =>
                    openTavernPage(CharacterEditPage(character: c)),
              ),
            );
          },
        );
      }),
    );
  }
}

class TavernAvatar extends StatelessWidget {
  const TavernAvatar({super.key, required this.character, this.size = 40});

  final TavernCharacter character;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? path = character.avatarPath;
    final bool hasImage = path != null && File(path).existsSync();
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: hasImage ? FileImage(File(path)) : null,
      child: hasImage
          ? null
          : Text(
              character.name.isEmpty ? '?' : character.name.characters.first),
    );
  }
}
