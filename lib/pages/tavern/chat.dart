import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pilipala/models/tavern/character.dart';
import 'package:pilipala/services/tavern_service.dart';

import 'view.dart';

class TavernChatPage extends StatefulWidget {
  const TavernChatPage({super.key, required this.character});

  final TavernCharacter character;

  @override
  State<TavernChatPage> createState() => _TavernChatPageState();
}

class _TavernChatPageState extends State<TavernChatPage> {
  final TavernService service = TavernService.to;
  final TextEditingController _input = TextEditingController();
  late List<TavernMessage> messages = service.loadChat(widget.character);
  CancelToken? _cancelToken;

  bool get _streaming => _cancelToken != null;

  @override
  void dispose() {
    _cancelToken?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _persist() => service.saveChat(widget.character, messages);

  void _send() {
    final String text = _input.text.trim();
    if (text.isEmpty || _streaming) return;
    _input.clear();
    setState(() => messages.add(TavernMessage(role: 'user', content: text)));
    _persist();
    _reply();
  }

  /// 请求一条角色回复，流式追加到列表末尾；出错时移除空回复并提示
  Future<void> _reply() async {
    final List<Map<String, String>> prompt =
        service.buildMessages(widget.character, messages);
    final TavernMessage reply = TavernMessage(role: 'assistant', content: '');
    final CancelToken token = CancelToken();
    setState(() {
      messages.add(reply);
      _cancelToken = token;
    });
    try {
      await for (final String delta in service.streamChat(prompt, token)) {
        if (!mounted) return;
        setState(() => reply.content += delta);
      }
    } catch (e) {
      SmartDialog.showToast('请求失败：$e', displayTime: const Duration(seconds: 4));
    }
    if (!mounted) return;
    setState(() {
      if (reply.content.isEmpty) messages.remove(reply);
      _cancelToken = null;
    });
    _persist();
  }

  void _stop() => _cancelToken?.cancel();

  void _regenerate() {
    if (_streaming || messages.isEmpty || messages.last.isUser) return;
    setState(() => messages.removeLast());
    _reply();
  }

  Future<void> _edit(TavernMessage m) async {
    final TextEditingController c = TextEditingController(text: m.content);
    final String? text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(controller: c, minLines: 3, maxLines: 12),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (text == null) return;
    setState(() => m.content = text);
    _persist();
  }

  void _showMenu(TavernMessage m) {
    if (_streaming) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制'),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: m.content));
              SmartDialog.showToast('已复制');
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑'),
            onTap: () {
              Navigator.pop(context);
              _edit(m);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除'),
            onTap: () {
              Navigator.pop(context);
              setState(() => messages.remove(m));
              _persist();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _clear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开始新对话？'),
        content: const Text('当前聊天记录会被清空。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await service.clearChat(widget.character);
    setState(() => messages = service.loadChat(widget.character));
  }

  @override
  Widget build(BuildContext context) {
    final bool canRegenerate =
        !_streaming && messages.isNotEmpty && !messages.last.isUser;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          TavernAvatar(character: widget.character, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.character.name, overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: '重新生成',
            onPressed: canRegenerate ? _regenerate : null,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '新对话',
            onPressed: _streaming ? null : _clear,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final TavernMessage m = messages[messages.length - 1 - index];
                return _Bubble(
                  message: m,
                  character: widget.character,
                  pending: _streaming && identical(m, messages.last),
                  onLongPress: () => _showMenu(m),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: '说点什么…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _streaming
                      ? IconButton.filledTonal(
                          tooltip: '停止',
                          onPressed: _stop,
                          icon: const Icon(Icons.stop))
                      : IconButton.filled(
                          tooltip: '发送',
                          onPressed: _send,
                          icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.character,
    required this.pending,
    required this.onLongPress,
  });

  final TavernMessage message;
  final TavernCharacter character;
  // 正在流式输出、尚无内容时显示省略号
  final bool pending;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isUser = message.isUser;
    final Widget bubble = Flexible(
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                isUser ? colors.primaryContainer : colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: pending && message.content.isEmpty
              ? const Text('…')
              : MarkdownBody(
                  data: message.content,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    em: TextStyle(
                        fontStyle: FontStyle.italic, color: colors.outline),
                  ),
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isUser
            ? [const SizedBox(width: 48), bubble]
            : [
                TavernAvatar(character: character, size: 32),
                const SizedBox(width: 8),
                bubble,
                const SizedBox(width: 24),
              ],
      ),
    );
  }
}
