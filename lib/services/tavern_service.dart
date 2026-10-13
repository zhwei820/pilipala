import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:hive/hive.dart';
import 'package:pilipala/models/tavern/character.dart';
import 'package:pilipala/utils/storage.dart';

class TavernSettings {
  TavernSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.temperature,
    required this.maxTokens,
    required this.userName,
    required this.systemPrompt,
  });

  String baseUrl;
  String apiKey;
  String model;
  double temperature;
  int maxTokens;
  // {{user}} 宏替换成的名字
  String userName;
  String systemPrompt;

  static const String defaultSystemPrompt =
      '这是一场虚构的角色扮演。你扮演 {{char}}，与 {{user}} 对话。'
      '始终保持角色，用第三人称以*斜体*描写动作和神态，不要替 {{user}} 说话或行动。';

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'userName': userName,
        'systemPrompt': systemPrompt,
      };

  factory TavernSettings.fromJson(Map json) => TavernSettings(
        baseUrl: json['baseUrl'] ?? 'https://api.deepseek.com',
        apiKey: json['apiKey'] ?? '',
        model: json['model'] ?? 'deepseek-flash',
        temperature: (json['temperature'] ?? 1.0).toDouble(),
        maxTokens: json['maxTokens'] ?? 1024,
        userName: json['userName'] ?? '我',
        systemPrompt: json['systemPrompt'] ?? defaultSystemPrompt,
      );
}

class TavernService extends GetxService {
  static TavernService get to => Get.isRegistered<TavernService>()
      ? Get.find<TavernService>()
      : Get.put(TavernService(), permanent: true);

  final Box _box = GStrorage.tavern;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 3),
  ));

  final RxList<TavernCharacter> characters = <TavernCharacter>[].obs;
  // 进程内解锁状态；App 退到后台由页面置回 false
  final RxBool unlocked = false.obs;
  late TavernSettings settings;

  // 历史消息按字符数截断，粗略对应 token 预算，避免长对话超出上下文
  static const int _historyCharBudget = 60000;

  @override
  void onInit() {
    super.onInit();
    settings = TavernSettings.fromJson(Map.from(_box.get('settings') ?? {}));
    final Map stored = Map.from(_box.get('characters') ?? {});
    characters.assignAll(
        stored.values.map((e) => TavernCharacter.fromJson(Map.from(e))).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  // ---------- 密码 ----------

  bool get hasPassword => _box.get('passwordHash') != null;

  String _hash(String password) =>
      sha256.convert(utf8.encode('pilipala-tavern:$password')).toString();

  bool verifyPassword(String password) =>
      _box.get('passwordHash') == _hash(password);

  Future<void> setPassword(String password) =>
      _box.put('passwordHash', _hash(password));

  // ---------- 设置 / 角色 / 会话 ----------

  Future<void> saveSettings() => _box.put('settings', settings.toJson());

  Future<void> _persistCharacters() =>
      _box.put('characters', {for (final c in characters) c.id: c.toJson()});

  Future<void> saveCharacter(TavernCharacter c) async {
    final int index = characters.indexWhere((e) => e.id == c.id);
    if (index == -1) {
      characters.insert(0, c);
    } else {
      characters[index] = c;
    }
    await _persistCharacters();
  }

  Future<void> deleteCharacter(TavernCharacter c) async {
    characters.removeWhere((e) => e.id == c.id);
    await _persistCharacters();
    await _box.delete('chat_${c.id}');
  }

  /// 读取会话；没有记录时以开场白开启新会话
  List<TavernMessage> loadChat(TavernCharacter c) {
    final List? stored = _box.get('chat_${c.id}');
    if (stored != null) {
      return stored.map((e) => TavernMessage.fromJson(Map.from(e))).toList();
    }
    return [
      if (c.firstMes.isNotEmpty)
        TavernMessage(role: 'assistant', content: c.firstMes),
    ];
  }

  Future<void> saveChat(TavernCharacter c, List<TavernMessage> messages) =>
      _box.put('chat_${c.id}', messages.map((e) => e.toJson()).toList());

  Future<void> clearChat(TavernCharacter c) => _box.delete('chat_${c.id}');

  // ---------- Prompt ----------

  String _applyMacros(String text, TavernCharacter c) => text
      .replaceAll(RegExp(r'\{\{char\}\}|<BOT>', caseSensitive: false), c.name)
      .replaceAll(RegExp(r'\{\{user\}\}|<USER>', caseSensitive: false),
          settings.userName);

  /// 按 SillyTavern 的顺序拼系统提示：破限/设定 → 描述 → 性格 → 场景 → 示例对话；
  /// 历史从最新往前取，超出预算的早期消息丢弃。
  List<Map<String, String>> buildMessages(
      TavernCharacter c, List<TavernMessage> history) {
    final List<String> sections = [
      settings.systemPrompt,
      if (c.description.isNotEmpty) '[{{char}} 的设定]\n${c.description}',
      if (c.personality.isNotEmpty) '[{{char}} 的性格]\n${c.personality}',
      if (c.scenario.isNotEmpty) '[场景]\n${c.scenario}',
      if (c.mesExample.isNotEmpty)
        '[对话示例，仅供参考语气]\n${c.mesExample.replaceAll('<START>', '').trim()}',
    ];
    final List<Map<String, String>> picked = [];
    int used = 0;
    for (final TavernMessage m in history.reversed) {
      used += m.content.length;
      if (used > _historyCharBudget && picked.isNotEmpty) break;
      picked.insert(0, {'role': m.role, 'content': _applyMacros(m.content, c)});
    }
    return [
      {'role': 'system', 'content': _applyMacros(sections.join('\n\n'), c)},
      ...picked,
    ];
  }

  // ---------- 模型调用 ----------

  Options get _authOptions =>
      Options(headers: {'Authorization': 'Bearer ${settings.apiKey}'});

  String get _completionsUrl =>
      '${settings.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';

  /// 流式对话，逐段产出增量文本。取消时流正常结束。
  Stream<String> streamChat(
      List<Map<String, String>> messages, CancelToken cancelToken) async* {
    if (settings.apiKey.isEmpty) throw '请先在酒馆设置里填写 API Key';
    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        _completionsUrl,
        data: {
          'model': settings.model,
          'messages': messages,
          'temperature': settings.temperature,
          'max_tokens': settings.maxTokens,
          'stream': true,
        },
        options: _authOptions.copyWith(responseType: ResponseType.stream),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      throw await _describeError(e);
    }
    try {
      final Stream<String> lines = res.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final String line in lines) {
        if (!line.startsWith('data:')) continue;
        final String payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        final Map chunk = jsonDecode(payload);
        final String? delta = chunk['choices']?[0]?['delta']?['content'];
        if (delta != null && delta.isNotEmpty) yield delta;
      }
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) rethrow;
    }
  }

  /// 按描述生成角色卡（JSON 模式），解析失败抛出可读的错误信息
  Future<TavernCharacter> generateCharacter(String idea) async {
    if (settings.apiKey.isEmpty) throw '请先在酒馆设置里填写 API Key';
    const String instruction = '你是 SillyTavern 角色卡作者。根据用户的描述创作一个角色，'
        '只输出一个 json 对象，字段：name（角色名）、description（外貌、身份、背景）、'
        'personality（性格关键词与说话方式）、scenario（与 {{user}} 相遇的情境）、'
        'first_mes（角色的开场白，含*动作描写*）、'
        'mes_example（两段示例对话，每段以 <START> 开头，用 {{user}}: 与 {{char}}: 标注说话人）。'
        '使用与用户描述相同的语言。';
    try {
      final Response res = await _dio.post(
        _completionsUrl,
        data: {
          'model': settings.model,
          'messages': [
            {'role': 'system', 'content': instruction},
            {'role': 'user', 'content': idea},
          ],
          'temperature': 1.0,
          'response_format': {'type': 'json_object'},
        },
        options: _authOptions,
      );
      final String content = res.data['choices'][0]['message']['content'];
      final TavernCharacter? character =
          TavernCharacter.fromCardJson(jsonDecode(content));
      if (character == null) throw '生成结果缺少角色名，请重试';
      return character;
    } on DioException catch (e) {
      throw await _describeError(e);
    } on FormatException {
      throw '模型返回的不是合法 JSON，请重试';
    }
  }

  Future<String> _describeError(DioException e) async {
    final dynamic data = e.response?.data;
    String body = '';
    try {
      if (data is ResponseBody) {
        body = await utf8.decodeStream(data.stream.cast<List<int>>());
      } else if (data != null) {
        body = data is String ? data : jsonEncode(data);
      }
      final dynamic msg = jsonDecode(body)['error']?['message'];
      if (msg != null) return '${e.response?.statusCode}：$msg';
    } catch (_) {}
    if (e.response != null) return '${e.response!.statusCode}：$body';
    return e.message ?? e.type.name;
  }
}
