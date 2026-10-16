// ============================================================================
//  错题本 APP  ·  全文件版本（无任何文件夹，所有代码集中在一个文件）
//
//  功能清单：
//   1. 4 个独立账户，APP 内一键切换
//   2. 英语/数学/语文内置学科 + 可无限添加自定义学科
//   3. 拍照收集 + 选框精准取题；也支持手动录入
//   4. ✨ AI 自动识题：拍完照自动提取文字、生成答案与解析、分析错因与知识点
//   5. 导出 .docx（WPS 可编辑）/ 分享 / 系统打印
//   6. 每个学科可新建无限个文件，可持续追加题目
//
//  作者注：AI 功能需在「设置」中填入腾讯混元 API Key 后使用
// ============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:docx_template/docx_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// ============================================================================
//  第 1 部分：数据模型
// ============================================================================

/// 账户（最多 4 个）
class Account {
  final int? id;
  final String name;
  final String avatarEmoji;
  final int colorValue;
  final DateTime createdAt;

  Account({
    this.id,
    required this.name,
    this.avatarEmoji = '👤',
    this.colorValue = 0xFF4A90D9,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'avatar_emoji': avatarEmoji,
        'color_value': colorValue,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        avatarEmoji: m['avatar_emoji'] as String? ?? '👤',
        colorValue: m['color_value'] as int? ?? 0xFF4A90D9,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

/// 学科
class Subject {
  final int? id;
  final int accountId;
  final String name;
  final String icon;
  final bool isBuiltIn;
  final int sortOrder;

  Subject({
    this.id,
    required this.accountId,
    required this.name,
    this.icon = '📘',
    this.isBuiltIn = false,
    this.sortOrder = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'name': name,
        'icon': icon,
        'is_built_in': isBuiltIn ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory Subject.fromMap(Map<String, Object?> m) => Subject(
        id: m['id'] as int?,
        accountId: m['account_id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as String? ?? '📘',
        isBuiltIn: (m['is_built_in'] as int? ?? 0) == 1,
        sortOrder: m['sort_order'] as int? ?? 0,
      );
}

/// 错题文件
class MistakeFile {
  final int? id;
  final int accountId;
  final int subjectId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  MistakeFile({
    this.id,
    required this.accountId,
    required this.subjectId,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'subject_id': subjectId,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory MistakeFile.fromMap(Map<String, Object?> m) => MistakeFile(
        id: m['id'] as int?,
        accountId: m['account_id'] as int,
        subjectId: m['subject_id'] as int,
        title: m['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}

/// 题目
class MistakeItem {
  final int? id;
  final int fileId;
  final int subjectId;
  final String? imagePath;
  final String? questionText;
  final String? answerText;
  final String? note;
  final int sortOrder;
  final DateTime createdAt;

  MistakeItem({
    this.id,
    required this.fileId,
    required this.subjectId,
    this.imagePath,
    this.questionText,
    this.answerText,
    this.note,
    this.sortOrder = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  MistakeItem withFileId(int newFileId) => MistakeItem(
        id: id,
        fileId: newFileId,
        subjectId: subjectId,
        imagePath: imagePath,
        questionText: questionText,
        answerText: answerText,
        note: note,
        sortOrder: sortOrder,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'file_id': fileId,
        'subject_id': subjectId,
        'image_path': imagePath,
        'question_text': questionText,
        'answer_text': answerText,
        'note': note,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory MistakeItem.fromMap(Map<String, Object?> m) => MistakeItem(
        id: m['id'] as int?,
        fileId: m['file_id'] as int,
        subjectId: m['subject_id'] as int,
        imagePath: m['image_path'] as String?,
        questionText: m['question_text'] as String?,
        answerText: m['answer_text'] as String?,
        note: m['note'] as String?,
        sortOrder: m['sort_order'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

/// AI 识题结果
class AiResult {
  final String question;
  final String answer;
  final String note;
  AiResult({required this.question, required this.answer, required this.note});

  static AiResult fromJson(String raw) {
    var s = raw.trim();
    // 去掉可能的 markdown 代码块包裹
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      s = s.replaceFirst(RegExp(r'\s*```$'), '');
    }
    // 截取最外层 JSON
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) s = s.substring(start, end + 1);

    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return AiResult(
        question: (m['question'] ?? '').toString().trim(),
        answer: (m['answer'] ?? '').toString().trim(),
        note: (m['note'] ?? '').toString().trim(),
      );
    } catch (_) {
      // 解析失败时，把原文当作题目内容，避免丢失信息
      return AiResult(question: raw.trim(), answer: '', note: '');
    }
  }
}

// ============================================================================
//  第 2 部分：AI 服务（腾讯混元 / 元宝大模型，OpenAI 兼容接口）
// ============================================================================

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  static const String kBaseUrl =
      'https://api.hunyuan.cloud.tencent.com/v1/chat/completions';

  String? _apiKey;
  String _model = 'hunyuan-vision';

  String? get apiKey => _apiKey;
  String get model => _model;
  bool get ready => _apiKey != null && _apiKey!.isNotEmpty;

  /// 从本地读取已保存的 Key
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _apiKey = sp.getString('ai_api_key');
    _model = sp.getString('ai_model') ?? 'hunyuan-vision';
  }

  Future<void> saveConfig(String key, String model) async {
    _apiKey = key.trim();
    _model = model.trim().isEmpty ? 'hunyuan-vision' : model.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString('ai_api_key', _apiKey!);
    await sp.setString('ai_model', _model);
  }

  /// 系统提示词：约束模型输出严格 JSON，并输出错因与知识点
  static const String _systemPrompt = '''
你是一位经验丰富的中小学老师，擅长从题目图片中识别内容并给出精准讲解。
用户会给你一张题目照片，请完成：
1. 识别图片中的题目文字（数学公式用通俗写法，如 × ÷ √ 分数用 a/b 表示）
2. 给出正确答案
3. 给出解题思路与解析
4. 备注栏写明：错因分析 + 涉及的知识点

严格要求：
- 只输出一个 JSON 对象，不要任何多余文字、不要 markdown 代码块
- 格式如下：
{"question":"完整题干","answer":"正确答案","note":"错因分析。涉及知识点：xxx"}
- 若图片中没有清晰题目，question 填你看到的内容，answer 留空
- 语言用简体中文
''';

  /// 识别图片中的题目
  /// [imageBytes] 图片二进制数据
  /// [subjectName] 学科名，帮助模型判断语境
  Future<AiResult> recognize({
    required Uint8List imageBytes,
    required String subjectName,
  }) async {
    if (!ready) {
      throw Exception('尚未配置 AI Key，请到「设置 → AI 识题」中填写');
    }

    final b64 = base64Encode(imageBytes);
    final body = jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': '这是一道【$subjectName】题目，请识别并给出答案、解析、错因和知识点。'
            },
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$b64'}
            },
          ]
        }
      ],
      'temperature': 0.2,
      'max_tokens': 2048,
    });

    final resp = await http
        .post(
          Uri.parse(kBaseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          body: utf8.encode(body),
        )
        .timeout(const Duration(seconds: 90));

    if (resp.statusCode != 200) {
      final msg = utf8.decode(resp.bodyBytes);
      throw Exception('AI 请求失败(${resp.statusCode})：${_brief(msg)}');
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('AI 返回内容为空');
    }
    final content =
        (choices[0]['message']?['content'] ?? '').toString();
    if (content.trim().isEmpty) throw Exception('AI 返回内容为空');

    return AiResult.fromJson(content);
  }

  /// 连通性测试
  Future<String> testConnection() async {
    if (!ready) throw Exception('请先填写 API Key');
    final body = jsonEncode({
      'model': 'hunyuan-lite',
      'messages': [
        {'role': 'user', 'content': '回复"连接成功"四个字'}
      ],
      'max_tokens': 20,
    });
    final resp = await http
        .post(
          Uri.parse(kBaseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          body: utf8.encode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('连接失败(${resp.statusCode})：${_brief(utf8.decode(resp.bodyBytes))}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (data['choices']?[0]?['message']?['content'] ?? '已连通').toString();
  }

  String _brief(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

// ============================================================================
//  第 3 部分：数据库服务
// ============================================================================

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  static const List<List<String>> builtInSubjects = [
    ['英语', '🔤'],
    ['数学', '📐'],
    ['语文', '📖'],
  ];

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'mistake_book.db'),
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            avatar_emoji TEXT NOT NULL DEFAULT '👤',
            color_value INTEGER NOT NULL DEFAULT 4283465945,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE subjects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT '📘',
            is_built_in INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL,
            subject_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE,
            FOREIGN KEY (subject_id) REFERENCES subjects (id) ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL,
            subject_id INTEGER NOT NULL,
            image_path TEXT,
            question_text TEXT,
            answer_text TEXT,
            note TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (file_id) REFERENCES files (id) ON DELETE CASCADE
          )''');
        await db.execute('CREATE INDEX idx_sub ON subjects(account_id)');
        await db.execute('CREATE INDEX idx_file ON files(subject_id)');
        await db.execute('CREATE INDEX idx_item ON items(file_id)');
      },
    );
  }

  // --- 账户 ---
  Future<List<Account>> getAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'created_at ASC');
    return rows.map(Account.fromMap).toList();
  }

  Future<int> createAccount(Account a) async {
    final db = await database;
    final id = await db.insert('accounts', a.toMap()..remove('id'));
    for (var i = 0; i < builtInSubjects.length; i++) {
      await db.insert('subjects', {
        'account_id': id,
        'name': builtInSubjects[i][0],
        'icon': builtInSubjects[i][1],
        'is_built_in': 1,
        'sort_order': i,
      });
    }
    return id;
  }

  Future<void> deleteAccount(int id) async {
    final db = await database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  // --- 学科 ---
  Future<List<Subject>> getSubjects(int accountId) async {
    final db = await database;
    final rows = await db.query('subjects',
        where: 'account_id = ?',
        whereArgs: [accountId],
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(Subject.fromMap).toList();
  }

  Future<int> createSubject(Subject s) async {
    final db = await database;
    return db.insert('subjects', s.toMap()..remove('id'));
  }

  Future<void> deleteSubject(int id) async {
    final db = await database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  // --- 文件 ---
  Future<List<MistakeFile>> getFiles(int subjectId) async {
    final db = await database;
    final rows = await db.query('files',
        where: 'subject_id = ?',
        whereArgs: [subjectId],
        orderBy: 'updated_at DESC');
    return rows.map(MistakeFile.fromMap).toList();
  }

  Future<int> createFile(MistakeFile f) async {
    final db = await database;
    return db.insert('files', f.toMap()..remove('id'));
  }

  Future<void> renameFile(int id, String title) async {
    final db = await database;
    await db.update('files',
        {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFile(int id) async {
    final db = await database;
    await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> touchFile(int id) async {
    final db = await database;
    await db.update('files',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  // --- 题目 ---
  Future<List<MistakeItem>> getItems(int fileId) async {
    final db = await database;
    final rows = await db.query('items',
        where: 'file_id = ?',
        whereArgs: [fileId],
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(MistakeItem.fromMap).toList();
  }

  Future<int> addItem(MistakeItem item) async {
    final db = await database;
    final id = await db.insert('items', item.toMap()..remove('id'));
    await touchFile(item.fileId);
    return id;
  }

  Future<void> updateItem(MistakeItem item) async {
    final db = await database;
    await db.update('items', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<void> deleteItem(int id) async {
    final db = await database;
    await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }
}

// ============================================================================
//  第 4 部分：导出服务
// ============================================================================

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  Future<Directory> _dir(String acc, String sub) async {
    Directory base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/错题本');
      try {
        if (!await base.exists()) await base.create(recursive: true);
      } catch (_) {
        base = await getApplicationDocumentsDirectory();
      }
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final d = Directory(p.join(base.path, _safe(acc), _safe(sub)));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  Future<Uint8List> buildDocx({
    required String title,
    required String subjectName,
    required List<MistakeItem> items,
  }) async {
    final tpl = await rootBundle.load('mistake_template.docx');
    final docx = await DocxTemplate.fromBytes(tpl.buffer.asUint8List());
    final d = DateTime.now();

    final content = Content()
      ..add(TextContent('TITLE', title))
      ..add(TextContent('SUBJECT', subjectName))
      ..add(TextContent(
          'DATE', '${d.year}年${d.month}月${d.day}日'))
      ..add(TextContent('COUNT', '${items.length}'));

    final sb = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      sb.writeln('第 ${i + 1} 题');
      if (it.questionText?.isNotEmpty == true) sb.writeln(it.questionText);
      if (it.imagePath?.isNotEmpty == true) {
        sb.writeln('【题目图片：${p.basename(it.imagePath!)}】');
      }
      if (it.answerText?.isNotEmpty == true) sb.writeln('答案：${it.answerText}');
      if (it.note?.isNotEmpty == true) sb.writeln('备注：${it.note}');
      sb.writeln('');
    }
    content.add(TextContent('ITEMS', sb.toString()));

    final out = await docx.generate(content);
    if (out == null) throw Exception('模板渲染失败');
    return Uint8List.fromList(out);
  }

  Future<String> exportDocx({
    required Account account,
    required Subject subject,
    required MistakeFile file,
    required List<MistakeItem> items,
  }) async {
    final bytes = await buildDocx(
      title: file.title,
      subjectName: subject.name,
      items: items,
    );
    final dir = await _dir(account.name, subject.name);
    final path = p.join(dir.path, '${_safe(file.title)}.docx');
    await File(path).writeAsBytes(bytes);
    return path;
  }
}

// ============================================================================
//  第 5 部分：全局状态
// ============================================================================

class AppState extends ChangeNotifier {
  final _db = DatabaseService.instance;
  final _export = ExportService.instance;

  List<Account> accounts = [];
  Account? currentAccount;
  List<Subject> subjects = [];
  Subject? currentSubject;
  List<MistakeFile> files = [];
  MistakeFile? currentFile;
  List<MistakeItem> items = [];
  bool loading = true;
  bool aiReady = false;

  Future<void> init() async {
    loading = true;
    notifyListeners();

    await AiService.instance.load();
    aiReady = AiService.instance.ready;

    accounts = await _db.getAccounts();
    if (accounts.isEmpty) {
      await _db.createAccount(Account(name: '我的账户'));
      accounts = await _db.getAccounts();
    }
    currentAccount = accounts.first;
    subjects = await _db.getSubjects(currentAccount!.id!);

    loading = false;
    notifyListeners();
  }

  Future<void> refreshAi() async {
    await AiService.instance.load();
    aiReady = AiService.instance.ready;
    notifyListeners();
  }

  // --- 账户 ---
  Future<void> switchAccount(Account a) async {
    currentAccount = a;
    currentSubject = null;
    currentFile = null;
    files = [];
    items = [];
    subjects = await _db.getSubjects(a.id!);
    notifyListeners();
  }

  Future<void> createAccount(String name, String emoji) async {
    if (accounts.length >= 4) return;
    const colors = [0xFF4A90D9, 0xFFE86A6A, 0xFF5DB075, 0xFFB07CD9];
    await _db.createAccount(Account(
      name: name,
      avatarEmoji: emoji,
      colorValue: colors[accounts.length % colors.length],
    ));
    accounts = await _db.getAccounts();
    await switchAccount(accounts.last);
  }

  Future<void> deleteAccount(Account a) async {
    await _db.deleteAccount(a.id!);
    accounts = await _db.getAccounts();
    await switchAccount(accounts.first);
  }

  // --- 学科 ---
  Future<void> openSubject(Subject s) async {
    currentSubject = s;
    currentFile = null;
    items = [];
    files = await _db.getFiles(s.id!);
    notifyListeners();
  }

  Future<void> addSubject(String name, String icon) async {
    await _db.createSubject(Subject(
      accountId: currentAccount!.id!,
      name: name,
      icon: icon,
      sortOrder: subjects.length,
    ));
    subjects = await _db.getSubjects(currentAccount!.id!);
    notifyListeners();
  }

  Future<void> deleteSubject(Subject s) async {
    await _db.deleteSubject(s.id!);
    subjects = await _db.getSubjects(currentAccount!.id!);
    notifyListeners();
  }

  // --- 文件 ---
  Future<void> createFile(int subjectId, String title) async {
    await _db.createFile(MistakeFile(
      accountId: currentAccount!.id!,
      subjectId: subjectId,
      title: title,
    ));
    files = await _db.getFiles(subjectId);
    notifyListeners();
  }

  Future<void> openFile(MistakeFile f) async {
    currentFile = f;
    items = await _db.getItems(f.id!);
    notifyListeners();
  }

  Future<void> renameFile(int id, String title) async {
    await _db.renameFile(id, title);
    if (currentSubject != null) files = await _db.getFiles(currentSubject!.id!);
    notifyListeners();
  }

  Future<void> deleteFile(int id) async {
    await _db.deleteFile(id);
    if (currentSubject != null) files = await _db.getFiles(currentSubject!.id!);
    notifyListeners();
  }

  // --- 题目 ---
  Future<void> addItem(MistakeItem item) async {
    await _db.addItem(item);
    items = await _db.getItems(item.fileId);
    if (currentSubject != null) files = await _db.getFiles(currentSubject!.id!);
    notifyListeners();
  }

  Future<void> updateItem(MistakeItem item) async {
    await _db.updateItem(item);
    items = await _db.getItems(item.fileId);
    notifyListeners();
  }

  Future<void> deleteItem(int id) async {
    await _db.deleteItem(id);
    if (currentFile != null) items = await _db.getItems(currentFile!.id!);
    if (currentSubject != null) files = await _db.getFiles(currentSubject!.id!);
    notifyListeners();
  }

  // --- 导出 / 打印 / 分享 ---
  Future<String> exportDocx() async {
    _check();
    return _export.exportDocx(
      account: currentAccount!,
      subject: currentSubject!,
      file: currentFile!,
      items: items,
    );
  }

  Future<void> printFile(String title) async {
    _check();
    final doc = pw.Document();
    // 使用 PDF 内置字体，不依赖网络下载（避免 CI 环境字体下载失败）
    final base = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      build: (ctx) {
        final ws = <pw.Widget>[
          pw.Header(
            level: 0,
            child: pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold, font: bold)),
          ),
          pw.Text('学科：${currentSubject!.name}　共 ${items.length} 道题'),
          pw.SizedBox(height: 12),
        ];
        for (var i = 0; i < items.length; i++) {
          final it = items[i];
          ws.add(pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('第 ${i + 1} 题',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, font: bold)),
                if (it.questionText?.isNotEmpty == true)
                  pw.Text(it.questionText!),
                if (it.imagePath != null && File(it.imagePath!).existsSync())
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    child: pw.Image(
                      pw.MemoryImage(File(it.imagePath!).readAsBytesSync()),
                      height: 200,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                if (it.answerText?.isNotEmpty == true)
                  pw.Text('答案：${it.answerText}'),
                if (it.note?.isNotEmpty == true)
                  pw.Text('备注：${it.note}',
                      style: const pw.TextStyle(color: PdfColors.grey700)),
                pw.Divider(),
              ],
            ),
          ));
        }
        return ws;
      },
    ));

    await Printing.layoutPdf(onLayout: (f) => doc.save(), name: title);
  }

  Future<void> shareFile() async {
    _check();
    final path = await exportDocx();
    await Share.shareXFiles([XFile(path)],
        subject: currentFile!.title, text: '错题本导出');
  }

  Future<void> openWithWps(String path) => OpenFilex.open(path);

  void _check() {
    if (currentAccount == null ||
        currentSubject == null ||
        currentFile == null) {
      throw StateError('导出参数不完整');
    }
  }
}

// ============================================================================
//  第 6 部分：界面 —— 首页
// ============================================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final acc = st.currentAccount;
    if (acc == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _switchSheet(context),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(acc.avatarEmoji),
            const SizedBox(width: 8),
            Text(acc.name),
            const Icon(Icons.arrow_drop_down, size: 20),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.15,
        ),
        itemCount: st.subjects.length + 1,
        itemBuilder: (c, i) {
          if (i == st.subjects.length) {
            return _AddTile(onTap: () => _addSubject(context));
          }
          final s = st.subjects[i];
          return _SubjectTile(
            subject: s,
            onTap: () async {
              await context.read<AppState>().openSubject(s);
              if (context.mounted) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SubjectScreen(subject: s)));
              }
            },
            onLongPress: () => _subjectMenu(context, s),
          );
        },
      ),
    );
  }

  void _switchSheet(BuildContext context) {
    final st = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('切换账户',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...st.accounts.map((a) => ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Color(a.colorValue),
                      child: Text(a.avatarEmoji)),
                  title: Text(a.name),
                  trailing: st.currentAccount?.id == a.id
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await context.read<AppState>().switchAccount(a);
                  },
                )),
            if (st.accounts.length < 4)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add)),
                title: const Text('新建账户'),
                onTap: () {
                  Navigator.pop(ctx);
                  _newAccount(context);
                },
              ),
            if (st.accounts.length > 1)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除当前账户'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _confirm(context, '删除账户？',
                      '「${st.currentAccount!.name}」下的所有学科、文件、错题都会被删除，无法恢复。');
                  if (ok) {
                    await context
                        .read<AppState>()
                        .deleteAccount(st.currentAccount!);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _newAccount(BuildContext context) async {
    final st = context.read<AppState>();
    if (st.accounts.length >= 4) {
      _toast(context, '最多支持 4 个账户');
      return;
    }
    final ctrl = TextEditingController();
    const emojis = ['👤', '🧒', '👧', '👦', '🐱', '🐶', '⭐', '🎓'];
    String emoji = emojis[st.accounts.length % emojis.length];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('新建账户'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '账户名')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: emojis
                  .map((e) => ChoiceChip(
                        label: Text(e, style: const TextStyle(fontSize: 18)),
                        selected: emoji == e,
                        onSelected: (_) => setSt(() => emoji = e),
                      ))
                  .toList(),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty && context.mounted) {
      await context
          .read<AppState>()
          .createAccount(ctrl.text.trim(), emoji);
    }
  }

  void _addSubject(BuildContext context) async {
    final ctrl = TextEditingController();
    const icons = ['📘', '📗', '📙', '📕', '🔬', '🌏', '🎨', '💻', '🏛️', '🎵'];
    String icon = icons[0];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('添加自定义学科'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: '学科名称', hintText: '例如：物理、化学、历史')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: icons
                  .map((e) => ChoiceChip(
                        label: Text(e, style: const TextStyle(fontSize: 18)),
                        selected: icon == e,
                        onSelected: (_) => setSt(() => icon = e),
                      ))
                  .toList(),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('添加')),
          ],
        ),
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty && context.mounted) {
      await context.read<AppState>().addSubject(ctrl.text.trim(), icon);
    }
  }

  void _subjectMenu(BuildContext context, Subject s) {
    if (s.isBuiltIn) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('删除该学科'),
          subtitle: const Text('该学科下所有文件与错题将一并删除'),
          onTap: () async {
            Navigator.pop(ctx);
            final ok = await _confirm(
                context, '删除学科「${s.name}」？', '此操作不可恢复。');
            if (ok && context.mounted) {
              await context.read<AppState>().deleteSubject(s);
            }
          },
        ),
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  final Subject subject;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _SubjectTile(
      {required this.subject, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(subject.icon, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text(subject.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600)),
            if (!subject.isBuiltIn)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('自定义', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline,
                  size: 36, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              const Text('添加学科'),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  第 7 部分：学科页
// ============================================================================

class SubjectScreen extends StatelessWidget {
  final Subject subject;
  const SubjectScreen({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    final files = context.watch<AppState>().files;

    return Scaffold(
      appBar: AppBar(title: Text('${subject.icon} ${subject.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newFile(context),
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('新建文件'),
      ),
      body: files.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.folder_open_outlined,
                  size: 64, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              const Text('还没有错题文件'),
              const SizedBox(height: 4),
              const Text('点击右下角「新建文件」开始',
                  style: TextStyle(fontSize: 12)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemCount: files.length,
              itemBuilder: (c, i) {
                final f = files[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.description_outlined, size: 20)),
                    title: Text(f.title),
                    subtitle: Text(_fmt(f.updatedAt),
                        style: const TextStyle(fontSize: 12)),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'rename') _rename(context, f);
                        if (v == 'delete') _delete(context, f);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                    onTap: () async {
                      await context.read<AppState>().openFile(f);
                      if (context.mounted) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => FileDetailScreen(file: f)));
                      }
                    },
                  ),
                );
              },
            ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _newFile(BuildContext context) async {
    final d = DateTime.now();
    final ctrl = TextEditingController(
        text: '${subject.name}错题 ${d.month}月${d.day}日');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建错题文件'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: '文件名', hintText: '例如：数学错题本 第3单元')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    if (title != null && title.isNotEmpty && context.mounted) {
      await context.read<AppState>().createFile(subject.id!, title);
    }
  }

  Future<void> _rename(BuildContext context, MistakeFile f) async {
    final ctrl = TextEditingController(text: f.title);
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (t != null && t.isNotEmpty && context.mounted) {
      await context.read<AppState>().renameFile(f.id!, t);
    }
  }

  Future<void> _delete(BuildContext context, MistakeFile f) async {
    final ok = await _confirm(
        context, '删除《${f.title}》？', '文件内所有错题将一并删除。');
    if (ok && context.mounted) {
      await context.read<AppState>().deleteFile(f.id!);
    }
  }
}

// ============================================================================
//  第 8 部分：文件详情页
// ============================================================================

class FileDetailScreen extends StatelessWidget {
  final MistakeFile file;
  const FileDetailScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppState>().items;

    return Scaffold(
      appBar: AppBar(
        title: Text(file.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: items.isEmpty ? null : () => _exportSheet(context),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'manual',
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.edit_note),
            label: const Text('手动录入'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'camera',
            onPressed: () => _capture(context),
            icon: const Icon(Icons.camera_alt),
            label: const Text('拍照收集'),
          ),
        ],
      ),
      body: items.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (c, i) => _ItemCard(
                index: i,
                item: items[i],
                onTap: () => _openEditor(context, existing: items[i]),
                onDelete: () => _del(context, items[i]),
              ),
            ),
    );
  }

  /// 拍照 → 直接进入 AI 识题流程
  Future<void> _capture(BuildContext context) async {
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (bytes == null || !context.mounted) return;

    // 存图
    final dir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(dir.path, 'mistake_images'));
    if (!await imgDir.exists()) await imgDir.create(recursive: true);
    final path =
        p.join(imgDir.path, 'q_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(path).writeAsBytes(bytes);

    if (!context.mounted) return;

    // 如果配置了 AI，先自动识题
    final st = context.read<AppState>();
    AiResult? ai;
    if (st.aiReady) {
      ai = await showDialog<AiResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AiDialog(
          bytes: bytes,
          subjectName: st.currentSubject?.name ?? '通用',
        ),
      );
    }

    if (!context.mounted) return;
    // 带着 AI 结果进入编辑页，用户可修改
    final item = await Navigator.push<MistakeItem>(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemScreen(
          fileId: file.id!,
          subjectId: file.subjectId,
          initialImagePath: path,
          presetQuestion: ai?.question,
          presetAnswer: ai?.answer,
          presetNote: ai?.note,
        ),
      ),
    );
    if (item != null && context.mounted) {
      await context.read<AppState>().addItem(item);
      if (context.mounted) _toast(context, '已添加到《${file.title}》');
    }
  }

  Future<void> _openEditor(BuildContext context, {MistakeItem? existing}) async {
    final item = await Navigator.push<MistakeItem>(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemScreen(
          fileId: file.id!,
          subjectId: file.subjectId,
          existing: existing,
        ),
      ),
    );
    if (item == null || !context.mounted) return;
    if (existing == null) {
      await context.read<AppState>().addItem(item);
    } else {
      await context.read<AppState>().updateItem(item);
    }
  }

  Future<void> _del(BuildContext context, MistakeItem it) async {
    final ok = await _confirm(context, '删除这道错题？', '删除后无法恢复。');
    if (ok && context.mounted) {
      await context.read<AppState>().deleteItem(it.id!);
    }
  }

  void _exportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('导出与打印',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('导出 Word 文档（WPS 可编辑）'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                final path = await context.read<AppState>().exportDocx();
                if (context.mounted) _openDialog(context, path);
              } catch (e) {
                if (context.mounted) _toast(context, '导出失败：$e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('导出 PDF 并打印'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await context
                    .read<AppState>()
                    .printFile(file.title);
              } catch (e) {
                if (context.mounted) _toast(context, '打印失败：$e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('分享当前文档'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await context.read<AppState>().shareFile();
              } catch (e) {
                if (context.mounted) _toast(context, '分享失败：$e');
              }
            },
          ),
        ]),
      ),
    );
  }

  void _openDialog(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出成功'),
        content: SelectableText(path),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('好')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppState>().openWithWps(path);
            },
            child: const Text('用 WPS 打开'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox_outlined,
            size: 64, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        const Text('还没有错题，点击下方按钮开始收集'),
      ]),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final int index;
  final MistakeItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ItemCard(
      {required this.index,
      required this.item,
      required this.onTap,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                  radius: 14,
                  child: Text('${index + 1}',
                      style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 12),
              if (item.imagePath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(item.imagePath!),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 72)),
                ),
              if (item.imagePath != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.questionText?.isNotEmpty == true
                          ? item.questionText!
                          : '（图片题目）',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.answerText?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text('答案：${item.answerText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 13)),
                    ],
                  ],
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  第 9 部分：拍照 + 选框裁剪页（返回裁剪后的图片字节）
// ============================================================================

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _picker = ImagePicker();
  final _cropCtrl = CropController();
  Uint8List? _image;
  bool _busy = false;

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await _picker.pickImage(
          source: src, imageQuality: 95, maxWidth: 3000);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _image = bytes);
    } catch (e) {
      if (mounted) _toast(context, '获取图片失败：$e');
    }
  }

  void _onCropped(Uint8List r) {
    setState(() => _busy = false);
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照收集'),
        actions: [
          if (_image != null)
            IconButton(
                tooltip: '重选',
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() => _image = null)),
        ],
      ),
      body: _image == null ? _pickerUi() : _cropperUi(),
    );
  }

  Widget _pickerUi() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.photo_camera_outlined,
            size: 72, color: Theme.of(context).disabledColor),
        const SizedBox(height: 16),
        const Text('拍摄题目，或从相册选择'),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text('拍完可拖动四角精准框选错题区域，AI 会自动识题',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _pick(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('拍照'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('从相册选择'),
        ),
      ]),
    );
  }

  Widget _cropperUi() {
    return Column(children: [
      Expanded(
        child: Crop(
          image: _image!,
          controller: _cropCtrl,
          onCropped: _onCropped,
          interactive: true,
          withCircleUi: false,
          baseColor: Colors.black,
          maskColor: Colors.black54,
          cornerDotBuilder: (s, e) => const DotControl(color: Colors.white),
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _busy = true);
                        _cropCtrl.crop();
                      },
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('框选完成'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ============================================================================
//  第 10 部分：AI 识题进度对话框
// ============================================================================

class _AiDialog extends StatefulWidget {
  final Uint8List bytes;
  final String subjectName;
  const _AiDialog({required this.bytes, required this.subjectName});

  @override
  State<_AiDialog> createState() => _AiDialogState();
}

class _AiDialogState extends State<_AiDialog> {
  String _status = '正在识别题目…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final r = await AiService.instance.recognize(
        imageBytes: widget.bytes,
        subjectName: widget.subjectName,
      );
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _status = '识别失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_error == null ? 'AI 正在识题' : '识别失败'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(),
            ),
          Text(_status, textAlign: TextAlign.center),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                textAlign: TextAlign.center),
          ],
        ],
      ),
      actions: _error == null
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('手动录入'),
              ),
            ],
    );
  }
}

// ============================================================================
//  第 11 部分：题目编辑页（支持 AI 结果预填）
// ============================================================================

class AddItemScreen extends StatefulWidget {
  final int fileId;
  final int subjectId;
  final MistakeItem? existing;
  final String? initialImagePath;
  final String? presetQuestion;
  final String? presetAnswer;
  final String? presetNote;

  const AddItemScreen({
    super.key,
    required this.fileId,
    required this.subjectId,
    this.existing,
    this.initialImagePath,
    this.presetQuestion,
    this.presetAnswer,
    this.presetNote,
  });

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _q = TextEditingController();
  final _a = TextEditingController();
  final _n = TextEditingController();
  final _picker = ImagePicker();

  String? _imagePath;
  bool _aiBusy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _q.text = e?.questionText ?? widget.presetQuestion ?? '';
    _a.text = e?.answerText ?? widget.presetAnswer ?? '';
    _n.text = e?.note ?? widget.presetNote ?? '';
    _imagePath = e?.imagePath ?? widget.initialImagePath;
  }

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    _n.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 95, maxWidth: 3000);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => _CropOnlyScreen(bytes: bytes)),
    );
    if (cropped == null) return;
    final saved = await _saveBytes(cropped);
    setState(() => _imagePath = saved);
    await _runAi();
  }

  Future<String> _saveBytes(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'mistake_images'));
    if (!await d.exists()) await d.create(recursive: true);
    final path =
        p.join(d.path, 'q_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// 用当前图片调 AI 识题，结果填入输入框
  Future<void> _runAi() async {
    if (_imagePath == null) {
      _toast(context, '请先添加题目图片');
      return;
    }
    if (!AiService.instance.ready) {
      _toast(context, '请先到「设置 → AI 识题」配置 API Key');
      return;
    }
    setState(() => _aiBusy = true);
    try {
      final bytes = await File(_imagePath!).readAsBytes();
      final r = await AiService.instance.recognize(
        imageBytes: bytes,
        subjectName: context.read<AppState>().currentSubject?.name ?? '通用',
      );
      if (!mounted) return;
      setState(() {
        if (r.question.isNotEmpty) _q.text = r.question;
        if (r.answer.isNotEmpty) _a.text = r.answer;
        if (r.note.isNotEmpty) _n.text = r.note;
        _aiBusy = false;
      });
      _toast(context, 'AI 识别完成，请核对后保存');
    } catch (e) {
      if (mounted) {
        setState(() => _aiBusy = false);
        _toast(context, 'AI 识别失败：$e');
      }
    }
  }

  void _save() {
    if (_q.text.trim().isEmpty && _imagePath == null) {
      _toast(context, '请填写题目文字或拍照添加图片');
      return;
    }
    final e = widget.existing;
    Navigator.pop(
      context,
      MistakeItem(
        id: e?.id,
        fileId: widget.fileId,
        subjectId: widget.subjectId,
        imagePath: _imagePath,
        questionText: _q.text.trim().isEmpty ? null : _q.text.trim(),
        answerText: _a.text.trim().isEmpty ? null : _a.text.trim(),
        note: _n.text.trim().isEmpty ? null : _n.text.trim(),
        sortOrder: e?.sortOrder ?? 0,
        createdAt: e?.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑题目' : '录入题目'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_imagePath != null)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_imagePath!),
                    height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _imagePath = null),
                ),
              ),
            ])
          else
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('拍照添加题目图片'),
            ),

          const SizedBox(height: 12),

          // AI 识题按钮
          FilledButton.tonalIcon(
            onPressed: _aiBusy || _imagePath == null ? null : _runAi,
            icon: _aiBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_aiBusy ? 'AI 识别中…' : 'AI 自动识题（提取文字+答案+错因）'),
          ),

          const SizedBox(height: 16),
          _field('题目内容', _q, 4, '可输入题干，或配合上方图片'),
          const SizedBox(height: 12),
          _field('答案 / 解析', _a, 3, 'AI 会自动填写，可修改'),
          const SizedBox(height: 12),
          _field('备注（错因 / 知识点）', _n, 3, 'AI 会自动填写，可修改'),
          const SizedBox(height: 24),
          FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存题目')),
        ],
      ),
    );
  }

  Widget _field(
      String label, TextEditingController c, int lines, String hint) {
    return TextField(
      controller: c,
      maxLines: lines,
      minLines: lines > 2 ? 2 : 1,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    );
  }
}

// ============================================================================
//  第 12 部分：独立裁剪页（返回字节）
// ============================================================================

class _CropOnlyScreen extends StatefulWidget {
  final Uint8List bytes;
  const _CropOnlyScreen({required this.bytes});

  @override
  State<_CropOnlyScreen> createState() => _CropOnlyScreenState();
}

class _CropOnlyScreenState extends State<_CropOnlyScreen> {
  final _ctrl = CropController();

  void _onCropped(Uint8List r) {
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('框选题目区域')),
      body: Column(children: [
        Expanded(
          child: Crop(
            image: widget.bytes,
            controller: _ctrl,
            onCropped: _onCropped,
            withCircleUi: false,
            baseColor: Colors.black,
            maskColor: Colors.black54,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: () => _ctrl.crop(),
                  child: const Text('框选完成')),
            ),
          ),
        ),
      ]),
    );
  }
}

// ============================================================================
//  第 13 部分：设置页（AI 配置）
// ============================================================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _key.text = AiService.instance.apiKey ?? '';
    _model.text = AiService.instance.model;
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_key.text.trim().isEmpty) {
      _toast(context, '请填写 API Key');
      return;
    }
    await AiService.instance.saveConfig(_key.text.trim(), _model.text.trim());
    if (mounted) await context.read<AppState>().refreshAi();
    if (mounted) _toast(context, '已保存');
  }

  Future<void> _test() async {
    if (_key.text.trim().isEmpty) {
      _toast(context, '请先填写 API Key');
      return;
    }
    setState(() => _testing = true);
    await AiService.instance.saveConfig(_key.text.trim(), _model.text.trim());
    try {
      final r = await AiService.instance.testConnection();
      if (mounted) _toast(context, '连接成功：$r');
    } catch (e) {
      if (mounted) _toast(context, '连接失败：$e');
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 8),
                    Text('AI 自动识题',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 10),
                  const Text(
                    '配置后，拍照收集时会自动提取题目文字、生成答案与解析、'
                    '并给出错因分析和知识点。使用腾讯混元（元宝同款底座）大模型。',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _key,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: '在腾讯云混元控制台创建',
                      border: OutlineInputBorder(),
                      helperText: '仅保存在本机，不会上传',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: '模型名',
                      hintText: 'hunyuan-vision',
                      border: OutlineInputBorder(),
                      helperText: '识图必须用 hunyuan-vision 或 hunyuan-t1-vision',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering),
                        label: const Text('测试连接'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: const Text('保存'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('如何获取 API Key',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text(
                    '1. 访问腾讯云混元大模型控制台\n'
                    '   cloud.tencent.com/product/hunyuan\n'
                    '2. 完成实名认证并开通服务\n'
                    '3. 在「API Key 管理」中创建密钥\n'
                    '4. 把密钥粘贴到上方输入框\n\n'
                    '接口地址：api.hunyuan.cloud.tencent.com/v1\n'
                    '新用户通常有免费额度，够日常使用。',
                    style: TextStyle(fontSize: 13, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              subtitle: const Text('错题本 v1.0 · 多账户 · 拍照收集 · AI 识题 · 文档导出'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  第 14 部分：公共工具 + 应用入口
// ============================================================================

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> _confirm(
    BuildContext context, String title, String text) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定')),
      ],
    ),
  );
  return r == true;
}

void main() => runApp(const MistakeBookApp());

class MistakeBookApp extends StatelessWidget {
  const MistakeBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: '错题本',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A90D9)),
          appBarTheme: const AppBarTheme(centerTitle: true),
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const HomeScreen();
  }
}
