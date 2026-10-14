import 'dart:math';

import 'package:flutter/material.dart';

import 'edit.dart';
import 'view.dart';

class _Category {
  const _Category(this.title, this.groups, {this.max = 1});

  final String title;

  /// 组名为空串时不显示分组标题
  final Map<String, List<String>> groups;

  /// 1 为单选；>1 为多选上限
  final int max;

  Iterable<String> get options => groups.values.expand((e) => e);
}

const List<_Category> _categories = [
  _Category('气质风格', {
    '': [
      '清纯', '甜美可爱', '元气活泼', '温柔贤淑', '知性优雅', '文艺清新', //
      '清冷禁欲', '高冷御姐', '妩媚风情', '性感火辣', '慵懒随性', '飒爽帅气',
      '神秘魅惑', '纯欲', '辣妹', '大小姐', '邻家女孩', '成熟韵味',
      '勾人妖艳', '欲女气质', '反差萌', '病娇诱惑', '冷艳尤物',
    ],
  }),
  _Category('性感程度', {
    '': [
      '含蓄保守', '若隐若现', '自然大方', '撩人', '热辣奔放', //
      '刻意诱惑', '毫不掩饰', '极度色情',
    ],
  }),
  _Category('身高', {
    '': ['娇小 150 左右', '小巧 155-160', '中等 160-165', '高挑 165-170', '模特 170+'],
  }),
  _Category('体型', {
    '': [
      '纤细骨感', '匀称苗条', '娇小玲珑', '微肉丰腴', '沙漏曲线', '运动健美', //
      '肉感丰满', '梨形身材', '长腿细腰', '紧致马甲线',
      '极致沙漏', '丰乳肥臀', '软肉感', '健身翘臀体',
    ],
  }),
  _Category('上围', {
    '': [
      '平坦', '小巧', '适中', '丰满', '傲人', //
      '巨乳', '软弹饱满', '挺拔上翘', '乳沟明显', '敏感易红',
    ],
  }),
  _Category('臀部', {
    '': [
      '扁平', '圆润适中', '蜜桃臀', '丰满翘臀', '肥美肉感', //
      '紧致上翘', '软弹可捏', '宽胯翘臀',
    ],
  }),
  _Category('腰肢', {
    '': [
      '纤细', '软腰', '马甲线明显', '小蛮腰', '肉感腰肢', //
      '极细腰', '可握住',
    ],
  }),
  _Category('腿部', {
    '': [
      '纤细笔直', '修长匀称', '丰腴肉感', '肌肉线条', '小腿纤细', //
      '大腿肉感', '绝对领域', '美腿杀',
    ],
  }),
  _Category('脸型', {
    '': ['鹅蛋脸', '瓜子脸', '圆脸', '心形脸', '小V脸', '方圆脸', '娃娃脸'],
  }),
  _Category('眼型', {
    '': ['杏眼', '桃花眼', '丹凤眼', '狐狸眼', '下垂眼', '圆眼', '细长眼', '眯眯眼'],
  }),
  _Category('瞳色', {
    '': ['黑色', '深棕', '琥珀', '灰蓝', '碧绿', '紫色', '异色瞳'],
  }),
  _Category('唇形', {
    '': [
      '薄唇', '微笑唇', '嘟嘟唇', '饱满丰唇', 'M 字唇', //
      '水润厚唇', '诱人红唇',
    ],
  }),
  _Category('肤色', {
    '': ['冷白皮', '白皙', '自然肤色', '蜜桃粉', '小麦色', '健康古铜', '蜜色'],
  }),
  _Category('发型', {
    '': [
      '黑长直', '大波浪', '羊毛卷', '短发波波头', '齐耳短发', '锁骨发', //
      '高马尾', '低马尾', '双马尾', '丸子头', '公主切', '狼尾', '编发', '侧分长发',
      '空气刘海', '盘发',
    ],
  }),
  _Category('发色', {
    '': ['黑色', '深棕', '栗色', '金色', '银白', '粉色', '酒红', '雾蓝', '紫色', '挑染', '渐变'],
  }),
  _Category(
      '细节特征',
      {
        '': [
          '泪痣', '酒窝', '虎牙', '雀斑', '纹身', '耳钉', '舌钉', '眼镜', //
          '美甲', '锁骨明显', '腰窝', '马甲线', '美人尖', '卧蚕', '香水味',
          '乳钉', '脐钉', '锁骨链', '大腿环', '脚链', '红痣', '唇钉',
        ],
      },
      max: 5),
  _Category(
      '私密特征',
      {
        '': [
          '光滑无毛', '修剪整齐', '自然体毛', '敏感体质', //
          '粉嫩', '颜色较深', '紧致', '湿润易兴奋',
          '有胎记', '对称好看',
        ],
      },
      max: 3),
  _Category(
      '穿搭风格',
      {
        '日常': ['韩系简约', '法式优雅', '日系森女', '街头潮牌', '运动风', '辣妹风', '居家睡衣'],
        '制服': ['职业套装', 'OL 白衬衫', 'JK 制服', '护士服', '空乘制服', '女仆装', '警服'],
        '特色': ['旗袍', '汉服', '洛丽塔', '哥特', '晚礼服', '泳装', '机能风', '皮衣朋克'],
        '性感': [
          '紧身包臀裙', '低胸装', '超短裙', '透视装', '露脐装', //
          '吊带睡裙', '黑丝吊带', '渔网袜', '情趣内衣',
        ],
      },
      max: 3),
  _Category(
      '情趣穿搭',
      {
        '': [
          '蕾丝情趣内衣', '开裆丝袜', '丁字裤', '三点式', //
          '兔女郎', '猫耳女仆', '透明睡衣', '束缚带',
          '项圈牵引绳', '乳贴', '可撕丝袜',
        ],
      },
      max: 2),
  _Category('职业身份', {
    '学生': ['大学生', '研究生', '艺术生', '舞蹈生', '留学生', '学生会长'],
    '职场': [
      '秘书',
      '白领',
      'HR',
      '律师',
      '医生',
      '护士',
      '教师',
      '空姐',
      '记者',
      '女总裁',
      '设计师',
      '程序员'
    ],
    '娱乐': ['偶像', '主播', '模特', '演员', 'Coser', '舞者', '歌手', '电竞选手', '网红博主'],
    '服务': ['咖啡店员', '调酒师', '花店老板', '健身教练', '瑜伽老师', '甜品师', '酒店前台', '美容师'],
    '特殊': ['警察', '军人', '特工', '杀手', '黑客', '侦探', '赏金猎人', '黑帮千金'],
    '奇幻': ['女骑士', '魔法师', '精灵', '魅魔', '吸血鬼', '修女', '公主', '女仆', '狐妖', '女剑仙'],
  }),
    _Category(
      '性格',
      {
        '': [
          '傲娇', '温柔', '腹黑', '高冷', '天然呆', '元气', '毒舌', '害羞', //
          '强势', '黏人', '嘴硬心软', '病娇', '慵懒', '理性', '叛逆', '小恶魔',
          '成熟稳重', '爱撒娇', '好胜', '占有欲强',
          '主动色气', '被动顺从', '闷骚', '放荡不羁', '专情痴女',
        ],
      },
      max: 3),
  _Category(
      '体位偏好',
      {
        '': [
          '传教士', '女上位', '后入式', '侧卧位', '站立抱操', //
          '骑乘位', '蹲坐式', '俯卧位', '仰卧抬腿', '椅上式',
          '壁咚站立', '跪趴式', '侧入式', '观音坐莲', '火车便当',
          '69式', '颜面骑乘', '背后抱紧', '抬腿深入', '压腿式',
          '喜欢被从后面进入', '喜欢主导骑乘', '喜欢被压着做', '喜欢边走边做',
          '喜欢对镜', '喜欢被抱起来做', '喜欢跪着口交后插入',
        ],
      },
      max: 4),
  _Category('与你的关系', {
    '': [
      '同学', '同事', '上司', '下属', '邻居', '青梅竹马', '初恋', '前任', //
      '室友', '网友', '陌生人', '房东', '学姐', '学妹', '契约关系', '死对头',
      '炮友', '情人', '主奴关系', '契约伴侣',
    ],
  }),
  _Category('世界观', {
    '': ['现代都市', '校园', '职场', '古风', '仙侠', '民国', '豪门', '赛博朋克', '西幻', '末世'],
  }),
];
/// 用选项拼出生成描述，交给 [CharacterEditPage] 生成
class CharacterGeneratePage extends StatefulWidget {
  const CharacterGeneratePage({super.key});

  @override
  State<CharacterGeneratePage> createState() => _CharacterGeneratePageState();
}

class _CharacterGeneratePageState extends State<CharacterGeneratePage> {
  static const int _minAge = 18;
  static const int _maxAge = 30;

  final Map<String, List<String>> _selected = {
    for (final _Category c in _categories) c.title: [],
  };
  final TextEditingController _extra = TextEditingController();
  double _age = 22;

  @override
  void initState() {
    super.initState();
    _roll();
  }

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  void _toggle(_Category c, String option) {
    final List<String> list = _selected[c.title]!;
    setState(() {
      if (list.remove(option)) return;
      if (c.max == 1) list.clear();
      if (list.length < c.max) list.add(option);
    });
  }

  void _roll() {
    final Random rnd = Random();
    _age = (_minAge + rnd.nextInt(_maxAge - _minAge + 1)).toDouble();
    for (final _Category c in _categories) {
      final List<String> pool = c.options.toList()..shuffle(rnd);
      _selected[c.title] =
          pool.take(c.max == 1 ? 1 : 1 + rnd.nextInt(c.max)).toList();
    }
  }

  void _randomize() => setState(_roll);

  void _clear() => setState(() {
        for (final List<String> list in _selected.values) {
          list.clear();
        }
      });

  String _buildIdea() {
    final StringBuffer sb = StringBuffer()
      ..writeln('创作一个女性角色，${_age.round()} 岁（成年人）。')
      ..writeln('设定如下：');
    for (final _Category c in _categories) {
      final List<String> list = _selected[c.title]!;
      if (list.isNotEmpty) sb.writeln('- ${c.title}：${list.join('、')}');
    }
    final String extra = _extra.text.trim();
    if (extra.isNotEmpty) sb.writeln('- 补充：$extra');
    sb.writeln('未指定的项由你自由发挥并保持整体协调；'
        'description 中要细致描写外貌、身材、穿着与职业背景，所有内容都符合她的成年年龄。');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 生成角色'),
        actions: [
          IconButton(
            tooltip: '随机',
            onPressed: _randomize,
            icon: const Icon(Icons.casino_outlined),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: _clear,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text('性别：女　·　已随机选好，点选项可修改，取消选中则由 AI 自由发挥',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
          const SizedBox(height: 12),
          Text('年龄：${_age.round()} 岁', style: theme.textTheme.titleSmall),
          Slider(
            value: _age,
            min: _minAge.toDouble(),
            max: _maxAge.toDouble(),
            divisions: _maxAge - _minAge,
            label: '${_age.round()}',
            onChanged: (v) => setState(() => _age = v),
          ),
          for (final _Category c in _categories) _buildCategory(theme, c),
          const SizedBox(height: 8),
          TextField(
            controller: _extra,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '补充描述（可选）',
              hintText: '如：嘴硬心软，喜欢在深夜给你发语音',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            openTavernPage(CharacterEditPage(generateFrom: _buildIdea())),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('生成'),
      ),
    );
  }

  Widget _buildCategory(ThemeData theme, _Category c) {
    final List<String> selected = _selected[c.title]!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: c.title, style: theme.textTheme.titleSmall),
            if (c.max > 1)
              TextSpan(
                text: '  最多 ${c.max} 项',
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline),
              ),
          ])),
          const SizedBox(height: 6),
          for (final MapEntry<String, List<String>> g in c.groups.entries) ...[
            if (g.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(g.key,
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.outline)),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final String o in g.value)
                  FilterChip(
                    label: Text(o),
                    selected: selected.contains(o),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _toggle(c, o),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
