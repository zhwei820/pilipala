import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/services/tavern_service.dart';

class TavernSettingsPage extends StatefulWidget {
  const TavernSettingsPage({super.key});

  @override
  State<TavernSettingsPage> createState() => _TavernSettingsPageState();
}

class _TavernSettingsPageState extends State<TavernSettingsPage> {
  final TavernService service = TavernService.to;
  late final TavernSettings s = service.settings;
  late final TextEditingController baseUrl =
      TextEditingController(text: s.baseUrl);
  late final TextEditingController apiKey =
      TextEditingController(text: s.apiKey);
  late final TextEditingController model = TextEditingController(text: s.model);
  late final TextEditingController maxTokens =
      TextEditingController(text: s.maxTokens.toString());
  late final TextEditingController userName =
      TextEditingController(text: s.userName);
  late final TextEditingController systemPrompt =
      TextEditingController(text: s.systemPrompt);
  late double temperature = s.temperature;
  bool showKey = false;
  late bool biometric = service.biometricEnabled;

  @override
  void dispose() {
    for (final TextEditingController c in [
      baseUrl,
      apiKey,
      model,
      maxTokens,
      userName,
      systemPrompt
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final int? tokens = int.tryParse(maxTokens.text.trim());
    if (tokens == null || tokens <= 0) {
      SmartDialog.showToast('最大输出长度需为正整数');
      return;
    }
    s
      ..baseUrl = baseUrl.text.trim()
      ..apiKey = apiKey.text.trim()
      ..model = model.text.trim()
      ..maxTokens = tokens
      ..temperature = temperature
      ..userName = userName.text.trim().isEmpty ? '我' : userName.text.trim()
      ..systemPrompt = systemPrompt.text;
    await service.saveSettings();
    SmartDialog.showToast('已保存');
    Get.back();
  }

  Future<void> _changePassword() async {
    final TextEditingController oldPwd = TextEditingController();
    final TextEditingController newPwd = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: oldPwd,
                obscureText: true,
                decoration: const InputDecoration(labelText: '原密码')),
            TextField(
                controller: newPwd,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密码（至少 4 位）')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    if (!service.verifyPassword(oldPwd.text)) {
      SmartDialog.showToast('原密码错误');
    } else if (newPwd.text.length < 4) {
      SmartDialog.showToast('新密码至少 4 位');
    } else {
      await service.setPassword(newPwd.text);
      SmartDialog.showToast('密码已修改');
    }
  }

  Widget _field(TextEditingController c, String label,
      {int lines = 1, bool obscure = false, Widget? suffix, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        minLines: lines,
        maxLines: lines == 1 ? 1 : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('酒馆设置'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(baseUrl, 'Base URL', hint: 'OpenAI 兼容接口地址'),
          _field(apiKey, 'API Key',
              obscure: !showKey,
              suffix: IconButton(
                icon: Icon(showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => showKey = !showKey),
              )),
          _field(model, '模型', hint: 'deepseek-flash'),
          _field(maxTokens, '最大输出长度（tokens）'),
          Text('温度 ${temperature.toStringAsFixed(1)}'),
          Slider(
            value: temperature,
            max: 2,
            divisions: 20,
            onChanged: (v) => setState(() => temperature = v),
          ),
          _field(userName, '你的名字（{{user}}）'),
          _field(systemPrompt, '系统提示', lines: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(
                  () => systemPrompt.text = TavernSettings.defaultSystemPrompt),
              child: const Text('恢复默认系统提示'),
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password),
            title: const Text('修改酒馆密码'),
            onTap: _changePassword,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.fingerprint),
            title: const Text('指纹解锁'),
            subtitle: const Text('进入酒馆时可用指纹代替密码'),
            value: biometric,
            onChanged: (v) async {
              await service.setBiometricEnabled(v);
              setState(() => biometric = v);
            },
          ),
        ],
      ),
    );
  }
}
