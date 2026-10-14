import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pilipala/models/tavern/character.dart';
import 'package:pilipala/services/tavern_service.dart';

import 'view.dart';

/// 新建 / 编辑角色。传 [generateFrom] 时先用 AI 按描述生成，结果只填入表单，保存需手动确认
class CharacterEditPage extends StatefulWidget {
  const CharacterEditPage({super.key, this.character, this.generateFrom});

  final TavernCharacter? character;
  final String? generateFrom;

  @override
  State<CharacterEditPage> createState() => _CharacterEditPageState();
}

class _CharacterEditPageState extends State<CharacterEditPage> {
  final TavernService service = TavernService.to;
  late TavernCharacter draft;
  late final Map<String, TextEditingController> fields;
  CancelToken? _generateToken;

  bool get generating => _generateToken != null;

  static const List<(String, String, int)> _fieldSpecs = [
    ('name', '名字', 1),
    ('description', '描述（外貌、身份、背景）', 6),
    ('personality', '性格', 3),
    ('scenario', '场景', 3),
    ('firstMes', '开场白', 5),
    ('mesExample', '示例对话（<START> 分隔）', 6),
  ];

  @override
  void initState() {
    super.initState();
    final TavernCharacter? c = widget.character;
    // 编辑时操作副本，未保存的修改不影响列表
    draft = c == null
        ? TavernCharacter(name: '')
        : TavernCharacter.fromJson(c.toJson());
    fields = {
      for (final (String key, _, _) in _fieldSpecs)
        key: TextEditingController(text: draft.toJson()[key] ?? ''),
    };
    if (widget.generateFrom != null) _generate();
  }

  @override
  void dispose() {
    _generateToken?.cancel();
    for (final TextEditingController c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    final CancelToken token = CancelToken();
    setState(() => _generateToken = token);
    try {
      final TavernCharacter result = await service
          .generateCharacter(widget.generateFrom!, cancelToken: token);
      final Map<String, dynamic> json = result.toJson();
      for (final MapEntry<String, TextEditingController> e in fields.entries) {
        e.value.text = json[e.key] ?? '';
      }
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) SmartDialog.showToast('生成失败：$e');
    } catch (e) {
      SmartDialog.showToast('生成失败：$e');
    } finally {
      if (mounted) setState(() => _generateToken = null);
    }
  }

  Future<void> _pickAvatar() async {
    final PlatformFile? file = await TavernPicker.pick(FileType.image);
    if (file?.path == null) return;
    final Directory dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/tavern/avatars');
    await dir.create(recursive: true);
    final String ext = file!.extension ?? 'png';
    // 文件名带时间戳，避免同名覆盖后 FileImage 仍显示缓存的旧图
    final String target =
        '${dir.path}/${draft.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(file.path!).copy(target);
    setState(() => draft.avatarPath = target);
  }

  Future<void> _save() async {
    final String name = fields['name']!.text.trim();
    if (name.isEmpty) {
      SmartDialog.showToast('名字不能为空');
      return;
    }
    draft
      ..name = name
      ..description = fields['description']!.text
      ..personality = fields['personality']!.text
      ..scenario = fields['scenario']!.text
      ..firstMes = fields['firstMes']!.text
      ..mesExample = fields['mesExample']!.text;
    await service.saveCharacter(draft);
    Get.back();
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${draft.name}」？'),
        content: const Text('角色和聊天记录都会删除，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await service.deleteCharacter(widget.character!);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.character == null ? '新建角色' : '编辑角色'),
        actions: [
          if (widget.generateFrom != null)
            IconButton(
              tooltip: '重新生成',
              onPressed: generating ? null : _generate,
              icon: const Icon(Icons.refresh),
            ),
          if (widget.character != null)
            IconButton(
              tooltip: '删除',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
              onPressed: generating ? null : _save, child: const Text('保存')),
        ],
      ),
      body: generating
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('正在生成角色…'),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _generateToken?.cancel(),
                    icon: const Icon(Icons.close),
                    label: const Text('取消'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        TavernAvatar(character: draft, size: 88),
                        const Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                              radius: 14,
                              child: Icon(Icons.photo_camera, size: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final (String key, String label, int lines)
                    in _fieldSpecs) ...[
                  TextField(
                    controller: fields[key],
                    minLines: lines,
                    maxLines: lines == 1 ? 1 : null,
                    decoration: InputDecoration(
                      labelText: label,
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('可用 {{char}} 代指角色名、{{user}} 代指你的名字',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline)),
              ],
            ),
    );
  }
}
