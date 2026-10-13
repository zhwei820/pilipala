class TavernCharacter {
  TavernCharacter({
    String? id,
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMes = '',
    this.mesExample = '',
    this.avatarPath,
    int? createdAt,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String name;
  String description;
  String personality;
  String scenario;
  // 开场白，新会话的第一条角色消息
  String firstMes;
  // 示例对话，SillyTavern 约定以 <START> 分隔多段
  String mesExample;
  String? avatarPath;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'personality': personality,
        'scenario': scenario,
        'firstMes': firstMes,
        'mesExample': mesExample,
        'avatarPath': avatarPath,
        'createdAt': createdAt,
      };

  factory TavernCharacter.fromJson(Map json) => TavernCharacter(
        id: json['id'],
        name: json['name'] ?? '',
        description: json['description'] ?? '',
        personality: json['personality'] ?? '',
        scenario: json['scenario'] ?? '',
        firstMes: json['firstMes'] ?? '',
        mesExample: json['mesExample'] ?? '',
        avatarPath: json['avatarPath'],
        createdAt: json['createdAt'],
      );

  /// 解析 SillyTavern 角色卡 JSON（V1 字段在顶层，V2/V3 在 `data` 下），
  /// 导入文件与 AI 生成共用。缺少名字时返回 null。
  static TavernCharacter? fromCardJson(Map json) {
    final Map data = json['data'] is Map ? json['data'] : json;
    String field(String key) =>
        (data[key] ?? json[key] ?? '').toString().trim();
    final String name =
        field('name').isNotEmpty ? field('name') : field('char_name');
    if (name.isEmpty) return null;
    return TavernCharacter(
      name: name,
      description: field('description').isNotEmpty
          ? field('description')
          : field('char_persona'),
      personality: field('personality'),
      scenario: field('scenario').isNotEmpty
          ? field('scenario')
          : field('world_scenario'),
      firstMes: field('first_mes').isNotEmpty
          ? field('first_mes')
          : field('char_greeting'),
      mesExample: field('mes_example').isNotEmpty
          ? field('mes_example')
          : field('example_dialogue'),
    );
  }
}

class TavernMessage {
  TavernMessage({required this.role, required this.content, int? time})
      : time = time ?? DateTime.now().millisecondsSinceEpoch;

  // user / assistant，与 OpenAI 兼容接口的 role 一致
  final String role;
  String content;
  final int time;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() =>
      {'role': role, 'content': content, 'time': time};

  factory TavernMessage.fromJson(Map json) => TavernMessage(
        role: json['role'],
        content: json['content'] ?? '',
        time: json['time'],
      );
}
