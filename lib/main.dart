
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show randomBytes;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _ink = Color(0xFF26383A);
const _muted = Color(0xFF687779);
const _paper = Color(0xFFF5F5F1);
const _green = Color(0xFF54796E);
const _greenPale = Color(0xFFE8F0EC);
const _sand = Color(0xFFF1E9DC);
const _line = Color(0xFFE3E8E4);

const _backupHeader = 'MOODPRESS_BACKUP_V1\n';
const _backupKdfIterations = 150000;
const _maxBackupFileBytes = 30 * 1024 * 1024;
const _maxBackupPhotoBytes = 12 * 1024 * 1024;

Future<Uint8List> encryptMoodPressBackup(
  Map<String, dynamic> document,
  String password,
) async {
  if (password.trim().length < 8) {
    throw ArgumentError('Gebruik een wachtwoord van minimaal 8 tekens.');
  }

  final headerBytes = utf8.encode(_backupHeader);
  final salt = randomBytes(16);
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _backupKdfIterations,
    bits: 256,
  );
  final key = await kdf.deriveKeyFromPassword(
    password: password,
    nonce: salt,
  );
  final cipher = AesGcm.with256bits();
  final clearText = utf8.encode(jsonEncode(document));
  if (clearText.length > _maxBackupFileBytes) {
    throw FormatException(
      'De back-up is te groot. Verwijder eventueel een paar grote foto’s en probeer opnieuw.',
    );
  }

  final secretBox = await cipher.encrypt(
    clearText,
    secretKey: key,
    nonce: cipher.newNonce(),
    aad: headerBytes,
  );
  final envelope = <String, dynamic>{
    'format': 'MoodPressEncryptedBackup',
    'version': 1,
    'cipher': 'AES-256-GCM',
    'kdf': 'PBKDF2-HMAC-SHA256',
    'iterations': _backupKdfIterations,
    'salt': base64Encode(salt),
    'nonce': base64Encode(secretBox.nonce),
    'cipherText': base64Encode(secretBox.cipherText),
    'mac': base64Encode(secretBox.mac.bytes),
  };
  final fileBytes = <int>[
    ...headerBytes,
    ...utf8.encode(jsonEncode(envelope)),
  ];
  if (fileBytes.length > _maxBackupFileBytes) {
    throw FormatException('De back-up is groter dan MoodPress veilig kan verwerken.');
  }
  return Uint8List.fromList(fileBytes);
}

Future<Map<String, dynamic>> decryptMoodPressBackup(
  Uint8List fileBytes,
  String password,
) async {
  if (fileBytes.length > _maxBackupFileBytes ||
      fileBytes.length <= utf8.encode(_backupHeader).length) {
    throw FormatException('Dit is geen geldig MoodPress-back-upbestand.');
  }
  if (password.trim().length < 8) {
    throw ArgumentError('Vul het wachtwoord van je back-up in.');
  }

  final headerBytes = utf8.encode(_backupHeader);
  for (var index = 0; index < headerBytes.length; index++) {
    if (fileBytes[index] != headerBytes[index]) {
      throw FormatException('Dit is geen geldig MoodPress-back-upbestand.');
    }
  }

  final decoded = jsonDecode(
    utf8.decode(fileBytes.sublist(headerBytes.length)),
  );
  if (decoded is! Map<String, dynamic> ||
      decoded['format'] != 'MoodPressEncryptedBackup' ||
      decoded['version'] != 1 ||
      decoded['cipher'] != 'AES-256-GCM' ||
      decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
      decoded['iterations'] != _backupKdfIterations) {
    throw FormatException('Dit back-upbestand wordt niet ondersteund.');
  }

  try {
    final salt = base64Decode(decoded['salt'] as String);
    final nonce = base64Decode(decoded['nonce'] as String);
    final cipherText = base64Decode(decoded['cipherText'] as String);
    final macBytes = base64Decode(decoded['mac'] as String);
    if (salt.length != 16 || nonce.length != 12 || macBytes.length != 16) {
      throw FormatException('Het back-upbestand is beschadigd.');
    }

    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _backupKdfIterations,
      bits: 256,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final clearText = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: key,
      aad: headerBytes,
    );
    final data = jsonDecode(utf8.decode(clearText));
    if (data is! Map<String, dynamic> ||
        data['app'] != 'MoodPress' ||
        data['dataVersion'] != 1) {
      throw FormatException('De inhoud van deze back-up wordt niet ondersteund.');
    }
    return data;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw FormatException(
      'Het wachtwoord klopt niet of het back-upbestand is beschadigd.',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = MoodPressController();
  await controller.load();
  runApp(MoodPressApp(controller: controller));
}

class DayActivity {
  DayActivity({
    required this.id,
    required this.title,
    required this.time,
    this.who = '',
    this.what = '',
    this.where = '',
    this.how = '',
    this.note = '',
    this.symbol = '📌',
    this.photoPath = '',
    this.done = false,
  });

  final String id;
  String title;
  String time;
  String who;
  String what;
  String where;
  String how;
  String note;
  String symbol;
  String photoPath;
  bool done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'time': time,
        'who': who,
        'what': what,
        'where': where,
        'how': how,
        'note': note,
        'symbol': symbol,
        'photoPath': photoPath,
        'done': done,
      };

  factory DayActivity.fromJson(Map<String, dynamic> json) => DayActivity(
        id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? 'Nieuwe activiteit',
        time: json['time'] as String? ?? '09:00',
        who: json['who'] as String? ?? '',
        what: json['what'] as String? ?? '',
        where: json['where'] as String? ?? '',
        how: json['how'] as String? ?? '',
        note: json['note'] as String? ?? '',
        symbol: json['symbol'] as String? ?? '📌',
        photoPath: json['photoPath'] as String? ?? '',
        done: json['done'] as bool? ?? false,
      );

  DayActivity copyWith({String? id, bool? done}) => DayActivity(
        id: id ?? this.id,
        title: title,
        time: time,
        who: who,
        what: what,
        where: where,
        how: how,
        note: note,
        symbol: symbol,
        photoPath: photoPath,
        done: done ?? this.done,
      );
}

class DayTemplate {
  DayTemplate({required this.id, required this.name, required this.activities});

  final String id;
  final String name;
  final List<DayActivity> activities;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'activities': activities.map((item) => item.toJson()).toList(),
      };

  factory DayTemplate.fromJson(Map<String, dynamic> json) {
    final rawActivities = json['activities'];
    return DayTemplate(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Dagindeling',
      activities: rawActivities is List
          ? rawActivities.whereType<Map<String, dynamic>>().map(DayActivity.fromJson).toList()
          : <DayActivity>[],
    );
  }

  List<DayActivity> createActivities() {
    final prefix = DateTime.now().microsecondsSinceEpoch.toString();
    return List<DayActivity>.generate(
      activities.length,
      (index) => activities[index].copyWith(
        id: prefix + '-' + index.toString(),
        done: false,
      ),
    );
  }
}

String _dateKey(DateTime date) =>
    date.year.toString().padLeft(4, '0') + '-' +
    date.month.toString().padLeft(2, '0') + '-' +
    date.day.toString().padLeft(2, '0');

const _dutchWeekdays = [
  'maandag', 'dinsdag', 'woensdag', 'donderdag',
  'vrijdag', 'zaterdag', 'zondag',
];

const _dutchMonths = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];

String _formatDutchDate(DateTime date) =>
    date.day.toString() + ' ' + _dutchMonths[date.month - 1];

String _formatDutchWeekday(DateTime date) => _dutchWeekdays[date.weekday - 1];

bool isActivityDueAt(DayActivity activity, DateTime now) {
  if (activity.done) return false;
  final parts = activity.time.split(':');
  if (parts.length != 2) return false;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  return hour != null && minute != null && hour == now.hour && minute == now.minute;
}

void reorderDayActivities(List<DayActivity> activities, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= activities.length ||
      newIndex < 0 || newIndex > activities.length) return;
  if (newIndex > oldIndex) newIndex -= 1;
  final activity = activities.removeAt(oldIndex);
  activities.insert(newIndex, activity);
}

class WeeklyRoutine {
  const WeeklyRoutine({this.days = const <int, DayTemplate>{}});

  final Map<int, DayTemplate> days;

  DayTemplate? forWeekday(int weekday) => days[weekday];

  WeeklyRoutine withDay(int weekday, DayTemplate template) =>
      WeeklyRoutine(days: {...days, weekday: template});

  WeeklyRoutine withoutDay(int weekday) {
    final updated = Map<int, DayTemplate>.from(days)..remove(weekday);
    return WeeklyRoutine(days: updated);
  }

  Map<String, dynamic> toJson() => {
        for (final entry in days.entries)
          entry.key.toString(): entry.value.toJson(),
      };

  List<DateTime> datesToFill(
    DateTime monday, {
    required Set<String> existingDateKeys,
  }) {
    final dates = <DateTime>[];
    for (var offset = 0; offset < 7; offset++) {
      final date = monday.add(Duration(days: offset));
      if (forWeekday(date.weekday) != null &&
          !existingDateKeys.contains(_dateKey(date))) {
        dates.add(date);
      }
    }
    return dates;
  }

  factory WeeklyRoutine.fromJson(Map<String, dynamic> json) {
    final result = <int, DayTemplate>{};
    for (final entry in json.entries) {
      final weekday = int.tryParse(entry.key);
      final value = entry.value;
      if (weekday != null && weekday >= 1 && weekday <= 7 &&
          value is Map<String, dynamic>) {
        result[weekday] = DayTemplate.fromJson(value);
      }
    }
    return WeeklyRoutine(days: result);
  }
}

class MoodPressPreferences {
  const MoodPressPreferences({
    this.textScale = 1.0,
    this.speechRate = 0.42,
    this.reduceMotion = false,
    this.inAppRemindersEnabled = false,
  });

  final double textScale;
  final double speechRate;
  final bool reduceMotion;
  final bool inAppRemindersEnabled;

  Map<String, dynamic> toJson() => {
        'textScale': textScale,
        'speechRate': speechRate,
        'reduceMotion': reduceMotion,
        'inAppRemindersEnabled': inAppRemindersEnabled,
      };

  factory MoodPressPreferences.fromJson(Map<String, dynamic> json) {
    final rawTextScale = json['textScale'];
    final rawSpeechRate = json['speechRate'];
    return MoodPressPreferences(
      textScale: rawTextScale is num
          ? rawTextScale.toDouble().clamp(1.0, 1.4).toDouble()
          : 1.0,
      speechRate: rawSpeechRate is num
          ? rawSpeechRate.toDouble().clamp(0.3, 0.6).toDouble()
          : 0.42,
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      inAppRemindersEnabled: json['inAppRemindersEnabled'] as bool? ?? false,
    );
  }
}

class MoodPressController extends ChangeNotifier {
  static const _dayPlansKey = 'moodpress.dayplans.v1';
  static const _legacyDayKey = 'moodpress.day.v1';
  static const _supportKey = 'moodpress.support.v1';
  static const _preferencesKey = 'moodpress.preferences.v1';
  static const _templatesKey = 'moodpress.templates.v1';
  static const _weeklyRoutineKey = 'moodpress.weeklyroutine.v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Map<String, List<DayActivity>> _plansByDate = {};
  DateTime selectedDate = DateTime.now();

  List<DayTemplate> templates = [];
  WeeklyRoutine weeklyRoutine = const WeeklyRoutine();
  Map<String, String> support = {
    'help': 'Ik wil even rust en één ding tegelijk doen.',
    'place': 'Een rustige plek waar ik mij prettig voel.',
    'person': '',
  };
  MoodPressPreferences preferences = const MoodPressPreferences();
  String? feeling;
  String? storageNotice;
  bool ready = false;

  List<DayActivity> get activities => activitiesFor(selectedDate);
  int get completed => completedOn(selectedDate);
  double get progress => progressOn(selectedDate);

  List<DayActivity> activitiesFor(DateTime date) =>
      _plansByDate[_dateKey(date)] ?? const <DayActivity>[];

  int completedOn(DateTime date) =>
      activitiesFor(date).where((item) => item.done).length;

  double progressOn(DateTime date) {
    final items = activitiesFor(date);
    return items.isEmpty ? 0 : items.where((item) => item.done).length / items.length;
  }

  List<DayActivity> _mutableActivitiesFor(DateTime date) =>
      _plansByDate.putIfAbsent(_dateKey(date), () => <DayActivity>[]);

  List<DayActivity> _starterPlan() => [
        DayActivity(id: '1', title: 'Rustig opstarten', time: '08:00', what: 'Opstaan en aankleden', where: 'Thuis', how: 'Stap voor stap', note: 'Neem de tijd om wakker te worden.'),
        DayActivity(id: '2', title: 'Ontbijten', time: '08:30', what: 'Ontbijt eten en iets drinken', where: 'Keuken', how: 'Pak wat je nodig hebt'),
        DayActivity(id: '3', title: 'Mijn activiteit', time: '10:00', what: 'Mijn gekozen activiteit', where: 'Op de afgesproken plek', how: 'Begin met de eerste stap'),
        DayActivity(id: '4', title: 'Rustmoment', time: '12:00', what: 'Even pauze nemen', where: 'Een fijne plek', how: 'Kies wat jou helpt'),
        DayActivity(id: '5', title: 'Middagactiviteit', time: '14:00', what: 'Een kleine activiteit doen', where: 'Thuis of buiten', how: 'Eén ding tegelijk'),
        DayActivity(id: '6', title: 'Avond rustig afronden', time: '19:30', what: 'Ontspannen en voorbereiden op de nacht', where: 'Thuis', how: 'Kies een vertrouwde activiteit'),
      ];

  Future<void> load() async {
    final todayKey = _dateKey(selectedDate);
    try {
      final savedPlans = await _storage.read(key: _dayPlansKey);
      if (savedPlans != null) {
        final decoded = jsonDecode(savedPlans) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final rawItems = entry.value;
          if (rawItems is List) {
            _plansByDate[entry.key] = rawItems
                .whereType<Map<String, dynamic>>()
                .map(DayActivity.fromJson)
                .toList();
          }
        }
      } else {
        // Migrate an existing single-day plan without losing the user's data.
        final legacyPlan = await _storage.read(key: _legacyDayKey);
        if (legacyPlan != null) {
          final decoded = jsonDecode(legacyPlan) as List<dynamic>;
          _plansByDate[todayKey] = decoded
              .whereType<Map<String, dynamic>>()
              .map(DayActivity.fromJson)
              .toList();
        } else {
          _plansByDate[todayKey] = _starterPlan();
        }
        await _saveDayPlans();
      }
    } catch (_) {
      _plansByDate.putIfAbsent(todayKey, _starterPlan);
      storageNotice = 'Een planning kon niet worden gelezen of opgeslagen. Gebruik nog geen echte cliëntgegevens.';
    }

    try {
      final savedSupport = await _storage.read(key: _supportKey);
      if (savedSupport != null) {
        final values = jsonDecode(savedSupport) as Map<String, dynamic>;
        support = values.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (_) {
      storageNotice ??= 'Je steunplan kon niet worden gelezen.';
    }

    try {
      final savedPreferences = await _storage.read(key: _preferencesKey);
      if (savedPreferences != null) {
        preferences = MoodPressPreferences.fromJson(
          jsonDecode(savedPreferences) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      preferences = const MoodPressPreferences();
    }

    try {
      final savedTemplates = await _storage.read(key: _templatesKey);
      if (savedTemplates != null) {
        final values = jsonDecode(savedTemplates) as List<dynamic>;
        templates = values
            .whereType<Map<String, dynamic>>()
            .map(DayTemplate.fromJson)
            .toList();
      }
    } catch (_) {
      templates = [];
      storageNotice ??= 'Je dagindelingen konden niet worden gelezen.';
    }

    try {
      final savedRoutine = await _storage.read(key: _weeklyRoutineKey);
      if (savedRoutine != null) {
        weeklyRoutine = WeeklyRoutine.fromJson(
          jsonDecode(savedRoutine) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      weeklyRoutine = const WeeklyRoutine();
      storageNotice ??= 'Je vaste weekritme kon niet worden gelezen.';
    }

    ready = true;
    notifyListeners();
  }

  Future<void> _saveDayPlans() async {
    try {
      final values = _plansByDate.map(
        (key, items) => MapEntry(
          key,
          items.map((item) => item.toJson()).toList(),
        ),
      );
      await _storage.write(key: _dayPlansKey, value: jsonEncode(values));
    } catch (_) {
      storageNotice = 'Je weekplanning kon niet veilig worden opgeslagen.';
    }
  }

  Future<void> _saveTemplates() async {
    try {
      await _storage.write(
        key: _templatesKey,
        value: jsonEncode(templates.map((item) => item.toJson()).toList()),
      );
    } catch (_) {
      storageNotice = 'Je dagindelingen konden niet veilig worden opgeslagen.';
    }
  }

  Future<void> _saveWeeklyRoutine() async {
    try {
      await _storage.write(
        key: _weeklyRoutineKey,
        value: jsonEncode(weeklyRoutine.toJson()),
      );
    } catch (_) {
      storageNotice = 'Je vaste weekritme kon niet veilig worden opgeslagen.';
    }
  }

  bool hasPlanFor(DateTime date) => _plansByDate.containsKey(_dateKey(date));

  int routinesInWeek(DateTime monday) =>
      weeklyRoutine
          .datesToFill(monday, existingDateKeys: _plansByDate.keys.toSet())
          .length;

  Future<void> saveWeeklyRoutineFromDate(DateTime date) async {
    final source = activitiesFor(date);
    if (source.isEmpty) return;

    final weekday = date.weekday;
    final template = DayTemplate(
      id: 'weekly-' + weekday.toString() + '-' +
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _dutchWeekdays[weekday - 1][0].toUpperCase() +
          _dutchWeekdays[weekday - 1].substring(1),
      activities: source.map((item) => item.copyWith(done: false)).toList(),
    );
    weeklyRoutine = weeklyRoutine.withDay(weekday, template);
    await _saveWeeklyRoutine();
    notifyListeners();
  }

  Future<void> removeWeeklyRoutine(int weekday) async {
    weeklyRoutine = weeklyRoutine.withoutDay(weekday);
    await _saveWeeklyRoutine();
    notifyListeners();
  }

  Future<int> applyWeeklyRoutineToWeek(DateTime monday) async {
    final dates = weeklyRoutine.datesToFill(
      monday,
      existingDateKeys: _plansByDate.keys.toSet(),
    );
    for (final date in dates) {
      final routine = weeklyRoutine.forWeekday(date.weekday)!;
      _plansByDate[_dateKey(date)] = routine.createActivities();
    }
    if (dates.isNotEmpty) {
      await _saveDayPlans();
      notifyListeners();
    }
    return dates.length;
  }

  void selectDate(DateTime date) {
    selectedDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  Future<void> saveActivity(DayActivity activity) async {
    final dayActivities = _mutableActivitiesFor(selectedDate);
    final index = dayActivities.indexWhere((item) => item.id == activity.id);
    if (index == -1) {
      dayActivities.add(activity);
    } else {
      dayActivities[index] = activity;
    }
    dayActivities.sort((a, b) => a.time.compareTo(b.time));
    await _saveDayPlans();
    notifyListeners();
  }

  Future<void> reorderActivities(int oldIndex, int newIndex) async {
    reorderDayActivities(_mutableActivitiesFor(selectedDate), oldIndex, newIndex);
    await _saveDayPlans();
    notifyListeners();
  }

  Future<void> toggleActivity(String id) async {
    final item = _mutableActivitiesFor(selectedDate)
        .firstWhere((activity) => activity.id == id);
    item.done = !item.done;
    await _saveDayPlans();
    notifyListeners();
  }

  Future<void> deleteActivity(String id) async {
    _mutableActivitiesFor(selectedDate)
        .removeWhere((activity) => activity.id == id);
    await _saveDayPlans();
    notifyListeners();
  }

  Future<void> saveTemplateFromDate(String name, DateTime date) async {
    final source = activitiesFor(date);
    if (source.isEmpty || name.trim().isEmpty) return;

    templates.add(DayTemplate(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      activities: source.map((item) => item.copyWith(done: false)).toList(),
    ));
    await _saveTemplates();
    notifyListeners();
  }

  Future<bool> applyTemplateToDate(String templateId, DateTime date) async {
    DayTemplate? selected;
    for (final template in templates) {
      if (template.id == templateId) {
        selected = template;
        break;
      }
    }
    if (selected == null) return false;

    _plansByDate[_dateKey(date)] = selected.createActivities();
    await _saveDayPlans();
    notifyListeners();
    return true;
  }

  Future<void> deleteTemplate(String templateId) async {
    templates.removeWhere((item) => item.id == templateId);
    await _saveTemplates();
    notifyListeners();
  }

  Future<void> saveSupport(String key, String value) async {
    support[key] = value;
    try {
      await _storage.write(key: _supportKey, value: jsonEncode(support));
    } catch (_) {
      storageNotice = 'Je steunplan kon niet veilig worden opgeslagen.';
    }
    notifyListeners();
  }


  Future<Uint8List> createBackupBytes(String password) async {
    final allActivities = <DayActivity>[
      for (final items in _plansByDate.values) ...items,
      for (final template in templates) ...template.activities,
      for (final template in weeklyRoutine.days.values) ...template.activities,
    ];
    final photoIds = <String, String>{};
    final photos = <String, dynamic>{};
    var totalPhotoBytes = 0;

    for (final path in allActivities
        .map((item) => item.photoPath)
        .where((path) => path.isNotEmpty)
        .toSet()) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      totalPhotoBytes += bytes.length;
      if (totalPhotoBytes > _maxBackupPhotoBytes) {
        throw FormatException(
          'De foto’s zijn samen te groot voor één back-up. Verwijder eerst een paar grote foto’s.',
        );
      }
      final id = 'photo_' + (photoIds.length + 1).toString();
      photoIds[path] = id;
      final match = RegExp(r'\.([a-zA-Z0-9]{1,5})
    preferences = MoodPressPreferences(
      textScale: value.clamp(1.0, 1.4).toDouble(),
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setSpeechRate(double value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: value.clamp(0.3, 0.6).toDouble(),
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: value,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setInAppRemindersEnabled(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: value,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> resetPreferences() async {
    preferences = const MoodPressPreferences();
    await _savePreferences();
    notifyListeners();
  }

  Future<void> _savePreferences() async {
    try {
      await _storage.write(
        key: _preferencesKey,
        value: jsonEncode(preferences.toJson()),
      );
    } catch (_) {
      storageNotice = 'Je instellingen konden niet veilig worden opgeslagen.';
    }
  }

  void setFeeling(String value) {
    // This voluntary check-in is temporary and is never stored as a health record.
    feeling = value;
    notifyListeners();
  }
}

class MoodPressApp extends StatelessWidget {
  const MoodPressApp({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.light)
        .copyWith(primary: _green, onPrimary: Colors.white, onSurface: _ink);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        title: 'MoodPress',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(systemScale * controller.preferences.textScale),
              disableAnimations: controller.preferences.reduceMotion,
            ),
            child: child!,
          );
        },
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: _paper,
          fontFamily: 'Arial',
          textTheme: const TextTheme(
            headlineLarge: TextStyle(color: _ink, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.6),
            headlineMedium: TextStyle(color: _ink, fontSize: 25, fontWeight: FontWeight.w700),
            titleLarge: TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w700),
            bodyLarge: TextStyle(color: _ink, fontSize: 16, height: 1.45),
            bodyMedium: TextStyle(color: _muted, fontSize: 14, height: 1.45),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFFAFAF7),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          ),
        ),
        home: controller.ready ? MoodPressShell(controller: controller) : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}

class MoodPressShell extends StatefulWidget {
  const MoodPressShell({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<MoodPressShell> createState() => _MoodPressShellState();
}

class _MoodPressShellState extends State<MoodPressShell> {
  int selected = 0;
  Timer? _reminderTimer;
  final Set<String> _shownReminders = <String>{};

  @override
  void initState() {
    super.initState();
    _reminderTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkInAppReminders(),
    );
  }

  void _checkInAppReminders() {
    if (!mounted || !widget.controller.preferences.inAppRemindersEnabled) return;
    final now = DateTime.now();
    final dateKey = _dateKey(now);
    for (final activity in widget.controller.activitiesFor(now)) {
      if (!isActivityDueAt(activity, now)) continue;
      final reminderKey = '$dateKey-${activity.id}';
      if (!_shownReminders.add(reminderKey)) continue;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Rustige herinnering: ${activity.title}. Als het nu niet uitkomt, mag je het overslaan.'),
          duration: const Duration(seconds: 8),
        ));
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }
  static const labels = ['Vandaag', 'Planning', 'Even rust', 'Mijn steun', 'Instellingen'];
  static const icons = [Icons.wb_sunny_outlined, Icons.calendar_month_outlined, Icons.spa_outlined, Icons.favorite_border, Icons.tune_rounded];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        final pages = [
          TodayPage(controller: widget.controller, openPlan: () => setState(() => selected = 1)),
          PlanningPage(controller: widget.controller),
          const CalmPage(),
          SupportPage(controller: widget.controller),
          SettingsPage(controller: widget.controller),
        ];
        return Scaffold(
          body: Row(children: [
            if (desktop)
              NavigationRail(
                backgroundColor: const Color(0xFFFBFBF8),
                selectedIndex: selected,
                onDestinationSelected: (value) => setState(() => selected = value),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(padding: EdgeInsets.fromLTRB(4, 22, 4, 28), child: BrandMark()),
                destinations: List.generate(labels.length, (index) => NavigationRailDestination(icon: Icon(icons[index]), label: Text(labels[index]))),
              ),
            Expanded(child: IndexedStack(index: selected, children: pages)),
          ]),
          bottomNavigationBar: desktop ? null : NavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (value) => setState(() => selected = value),
            destinations: List.generate(labels.length, (index) => NavigationDestination(icon: Icon(icons[index]), label: labels[index])),
          ),
        );
      });
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.waves_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 10),
        const Text('moodpress', style: TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
      ]);
}

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child, this.title, this.subtitle, this.action});
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 38),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) ...[
                LayoutBuilder(builder: (context, constraints) {
                  final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title!, style: Theme.of(context).textTheme.headlineMedium),
                    if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle!)),
                  ]);
                  if (action == null) return heading;
                  if (constraints.maxWidth < 580) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const SizedBox(height: 13), action!]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: heading), action!]);
                }),
                const SizedBox(height: 24),
              ],
              child,
            ]),
          ),
        ),
      );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.controller, required this.openPlan});
  final MoodPressController controller;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Goedemorgen' : now.hour < 18 ? 'Goedemiddag' : 'Goedenavond';
    final todayActivities = controller.activitiesFor(now);
    final upcoming = todayActivities.where((item) => !item.done).toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    final completedToday = todayActivities.where((item) => item.done).length;
    final progressToday = todayActivities.isEmpty ? 0.0 : completedToday / todayActivities.length;

    return PageFrame(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const BrandMark(),
      const SizedBox(height: 28),
      Text(greeting + '.', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text('We doen het rustig aan. Eén ding tegelijk.', style: TextStyle(color: _muted, fontSize: 16)),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, constraints) {
        final nextCard = NextStepCard(activity: next, openPlan: openPlan);
        final progressCard = ProgressCard(done: completedToday, total: todayActivities.length, progress: progressToday, openPlan: openPlan);
        if (constraints.maxWidth > 650) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: nextCard), const SizedBox(width: 14), Expanded(flex: 4, child: progressCard)]);
        return Column(children: [nextCard, const SizedBox(height: 14), progressCard]);
      }),
      const SizedBox(height: 28),
      Text('Hoe is het nu met je?', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Kies wat bij dit moment past. Je hoeft niets uit te leggen.', style: TextStyle(color: _muted)),
      const SizedBox(height: 14),
      Wrap(spacing: 9, runSpacing: 9, children: [
        FeelingChoice(label: 'Rustig', emoji: '🙂', selected: controller.feeling == 'Rustig', onTap: () => controller.setFeeling('Rustig')),
        FeelingChoice(label: 'Wat onrustig', emoji: '😐', selected: controller.feeling == 'Wat onrustig', onTap: () => controller.setFeeling('Wat onrustig')),
        FeelingChoice(label: 'Een vol hoofd', emoji: '😣', selected: controller.feeling == 'Een vol hoofd', onTap: () => controller.setFeeling('Een vol hoofd')),
      ]),
      if (controller.feeling != null) const Padding(padding: EdgeInsets.only(top: 13), child: Text('Dank je. Je hoeft hier verder niets mee te doen.', style: TextStyle(color: _muted, fontSize: 13))),
      if (controller.storageNotice != null) Padding(padding: const EdgeInsets.only(top: 16), child: StorageNotice(message: controller.storageNotice!)),
      const SizedBox(height: 22),
      const SmallDisclaimer(),
    ]));
  }
}

class NextStepCard extends StatelessWidget {
  const NextStepCard({super.key, required this.activity, required this.openPlan});
  final DayActivity? activity;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(23),
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(23)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('DIT IS JE VOLGENDE STAP', style: TextStyle(color: Color(0xFFE1ECE6), fontSize: 10, letterSpacing: 1.35, fontWeight: FontWeight.w800)),
          const SizedBox(height: 17),
          Text(activity?.title ?? 'Je dag is klaar', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(activity == null ? 'Goed gedaan. Neem de tijd voor jezelf.' : activity!.time + ' uur · ' + (activity!.note.isEmpty ? 'Je kunt dit stap voor stap doen.' : activity!.note), style: const TextStyle(color: Color(0xFFE9F0EB), height: 1.45)),
          const SizedBox(height: 21),
          FilledButton.icon(onPressed: openPlan, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _green), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Bekijk mijn planning')),
        ]),
      );
}

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.done, required this.total, required this.progress, required this.openPlan});
  final int done;
  final int total;
  final double progress;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(21),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('JOUW DAG', style: TextStyle(fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: _muted)),
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(width: 70, height: 70, child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: progress, strokeWidth: 7, backgroundColor: _greenPale, color: _green)),
                Text((progress * 100).round().toString() + '%', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
              ])),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(done.toString() + ' van ' + total.toString() + ' gedaan', style: const TextStyle(fontSize: 15, color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Elke stap telt. Ook een kleine stap.', style: TextStyle(color: _muted, fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 12),
            TextButton.icon(onPressed: openPlan, icon: const Icon(Icons.list_alt_outlined), label: const Text('Mijn weekplanning')),
          ]),
        ),
      );
}

class FeelingChoice extends StatelessWidget {
  const FeelingChoice({super.key, required this.label, required this.emoji, required this.selected, required this.onTap});
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? _greenPale : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? _green : _line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(emoji, style: const TextStyle(fontSize: 18)), const SizedBox(width: 8), Text(label, style: TextStyle(color: _ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))]),
          ),
        ),
      );
}

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  bool _showWeek = true;
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayFor(DateTime.now());
  }

  DateTime _mondayFor(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);

  String _rangeLabel() {
    final lastDay = _weekStart.add(const Duration(days: 6));
    return _formatDutchDate(_weekStart) + ' - ' +
        _formatDutchDate(lastDay) + ' ' + lastDay.year.toString();
  }

  void _openDay(DateTime date) {
    widget.controller.selectDate(date);
    setState(() => _showWeek = false);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Mijn planning',
        subtitle: _showWeek
            ? 'Een rustig overzicht van maandag tot en met zondag.'
            : 'Bekijk één dag tegelijk. Je kunt alles aanpassen.',
        action: _showWeek
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showWeeklyRoutineManager(context),
                    icon: const Icon(Icons.repeat_rounded),
                    label: const Text('Vast weekritme'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showTemplateManager(context),
                    icon: const Icon(Icons.library_books_outlined),
                    label: const Text('Dagindelingen'),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: () => editActivity(context, widget.controller),
                icon: const Icon(Icons.add),
                label: const Text('Activiteit toevoegen'),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Weekoverzicht')),
                ButtonSegment(value: false, label: Text('Dagplan')),
              ],
              selected: {_showWeek},
              onSelectionChanged: (values) =>
                  setState(() => _showWeek = values.first),
            ),
            const SizedBox(height: 18),
            if (_showWeek) _buildWeek(context) else _buildDay(context),
          ],
        ),
      );

  Widget _buildWeek(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Vorige week',
              onPressed: () => setState(
                () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _rangeLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Volgende week',
              onPressed: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var offset = 0; offset < 7; offset++)
          _buildWeekDayCard(
            context,
            _weekStart.add(Duration(days: offset)),
          ),
        if (widget.controller.weeklyRoutine.days.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 8),
            child: Card(
              color: _greenPale,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vaste dagen invullen',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.controller.routinesInWeek(_weekStart).toString() +
                          ' lege dagen kunnen worden gevuld. Bestaande plannen blijven staan.',
                      style: const TextStyle(color: _muted, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: widget.controller.routinesInWeek(_weekStart) == 0
                          ? null
                          : () => _applyWeeklyRoutine(context),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Vul lege dagen met weekritme'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.controller.templates.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: _green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Je hebt nog geen vaste dagindeling. Open een dagplan en kies ‘Bewaar als dagindeling’ om een sjabloon te maken.',
                      style: TextStyle(color: _ink, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              widget.controller.templates.length.toString() +
                  (widget.controller.templates.length == 1
                      ? ' dagindeling beschikbaar'
                      : ' dagindelingen beschikbaar'),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => setState(() => _weekStart = _mondayFor(DateTime.now())),
          icon: const Icon(Icons.today_outlined),
          label: const Text('Ga naar deze week'),
        ),
      ],
    );
  }

  Widget _buildWeekDayCard(BuildContext context, DateTime date) {
    final items = widget.controller.activitiesFor(date);
    final completed = items.where((item) => item.done).length;
    final summary = items.isEmpty
        ? 'Nog geen dagplan'
        : items.length.toString() +
            (items.length == 1 ? ' activiteit · ' : ' activiteiten · ') +
            completed.toString() + ' afgerond';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _greenPale,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  date.day.toString(),
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDutchWeekday(date),
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (widget.controller.weeklyRoutine.forWeekday(date.weekday) != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Text(
                          'Vaste indeling beschikbaar',
                          style: TextStyle(
                            color: _green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      summary,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openDay(date),
                child: const Text('Open dag'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Dagindeling toepassen',
                enabled: widget.controller.templates.isNotEmpty,
                icon: const Icon(Icons.copy_all_outlined, color: _green),
                onSelected: (templateId) =>
                    _applyTemplateToDate(context, date, templateId),
                itemBuilder: (context) => widget.controller.templates
                    .map(
                      (template) => PopupMenuItem<String>(
                        value: template.id,
                        child: Text(template.name),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDay(BuildContext context) {
    final date = widget.controller.selectedDate;
    final items = widget.controller.activities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Vorige dag',
                  onPressed: () =>
                      widget.controller.selectDate(date.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatDutchWeekday(date),
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _formatDutchDate(date) + ' ' + date.year.toString(),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Volgende dag',
                  onPressed: () =>
                      widget.controller.selectDate(date.add(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 13),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: _sand,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Text(
            'Kijk alleen naar de eerstvolgende activiteit. De rest komt later.',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 15),
        if (items.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: items.length,
            onReorder: widget.controller.reorderActivities,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: 11),
                child: ActivityCard(
                  activity: item,
                  speechRate: widget.controller.preferences.speechRate,
                  toggle: () => widget.controller.toggleActivity(item.id),
                  edit: () => editActivity(context, widget.controller, existing: item),
                  delete: () => confirmDelete(context, widget.controller, item),
                  reorderHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 12),
                      child: Icon(Icons.drag_handle_rounded, color: _muted),
                    ),
                  ),
                ),
              );
            },
          ),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'Voor deze dag staat nog niets gepland. Voeg een activiteit toe of gebruik een dagindeling.',
                style: TextStyle(color: _muted, height: 1.45),
              ),
            ),
          ),
        Wrap(
          spacing: 9,
          runSpacing: 7,
          children: [
            OutlinedButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => _saveTemplateFromDay(context, date),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Bewaar als dagindeling'),
            ),
            OutlinedButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => _saveWeeklyRoutineFromDay(context, date),
              icon: const Icon(Icons.repeat_rounded),
              label: const Text('Bewaar als vast weekritme'),
            ),
            TextButton.icon(
              onPressed: () => widget.controller.selectDate(DateTime.now()),
              icon: const Icon(Icons.today_outlined),
              label: const Text('Vandaag'),
            ),
          ],
        ),
        if (widget.controller.storageNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: StorageNotice(message: widget.controller.storageNotice!),
          ),
      ],
    );
  }

  Future<void> _saveTemplateFromDay(BuildContext context, DateTime date) async {
    final field = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dagindeling bewaren'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: field,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Naam van de dagindeling',
              hintText: 'Bijvoorbeeld: Werkdag',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, field.text.trim()),
            child: const Text('Bewaren'),
          ),
        ],
      ),
    );
    field.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await widget.controller.saveTemplateFromDate(name, date);
    }
  }

  Future<void> _applyTemplateToDate(
    BuildContext context,
    DateTime date,
    String templateId,
  ) async {
    if (widget.controller.activitiesFor(date).isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Dagindeling vervangen?'),
          content: const Text(
            'De activiteiten die nu op deze dag staan, worden vervangen door de gekozen dagindeling.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vervangen'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.controller.applyTemplateToDate(templateId, date);
  }

  Future<void> _saveWeeklyRoutineFromDay(
    BuildContext context,
    DateTime date,
  ) async {
    final existing = widget.controller.weeklyRoutine.forWeekday(date.weekday);
    if (existing != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Vaste dagindeling aanpassen?'),
          content: Text(
            'Er is al een vaste indeling voor ' +
                _formatDutchWeekday(date) +
                '. Wil je deze vervangen door het huidige dagplan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vervangen'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await widget.controller.saveWeeklyRoutineFromDate(date);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Vaste indeling voor ' + _formatDutchWeekday(date) + ' bewaard.',
        ),
      ),
    );
  }

  Future<void> _applyWeeklyRoutine(BuildContext context) async {
    final count = widget.controller.routinesInWeek(_weekStart);
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Weekritme toepassen?'),
        content: Text(
          'MoodPress vult ' + count.toString() +
              (count == 1 ? ' lege dag' : ' lege dagen') +
              ' met de vaste indeling. Bestaande dagplannen blijven ongewijzigd.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lege dagen invullen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final added = await widget.controller.applyWeeklyRoutineToWeek(_weekStart);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added.toString() +
              (added == 1 ? ' dag ingevuld.' : ' dagen ingevuld.'),
        ),
      ),
    );
  }

  Future<void> _showWeeklyRoutineManager(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final routines = widget.controller.weeklyRoutine.days.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          return AlertDialog(
            title: const Text('Mijn vaste weekritme'),
            content: SizedBox(
              width: 460,
              height: 320,
              child: routines.isEmpty
                  ? const Center(
                      child: Text(
                        'Er zijn nog geen vaste dagen. Open een dagplan en bewaar het als weekritme.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: routines.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = routines[index];
                        final weekday = entry.key;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _dutchWeekdays[weekday - 1][0].toUpperCase() +
                                _dutchWeekdays[weekday - 1].substring(1),
                          ),
                          subtitle: Text(
                            entry.value.activities.length.toString() +
                                (entry.value.activities.length == 1
                                    ? ' vaste activiteit'
                                    : ' vaste activiteiten'),
                          ),
                          trailing: IconButton(
                            tooltip: 'Vaste dag verwijderen',
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text('Vaste dag verwijderen?'),
                                  content: Text(
                                    'Wil je het vaste weekritme voor ' +
                                        _dutchWeekdays[weekday - 1] +
                                        ' verwijderen?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, false),
                                      child: const Text('Annuleren'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, true),
                                      child: const Text('Verwijderen'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await widget.controller.removeWeeklyRoutine(weekday);
                                setDialogState(() {});
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Sluiten'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTemplateManager(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mijn dagindelingen'),
          content: SizedBox(
            width: 460,
            height: 300,
            child: widget.controller.templates.isEmpty
                ? const Center(
                    child: Text(
                      'Je hebt nog geen dagindelingen bewaard.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: widget.controller.templates.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final template = widget.controller.templates[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(template.name),
                        subtitle: Text(
                          template.activities.length.toString() +
                              (template.activities.length == 1
                                  ? ' activiteit'
                                  : ' activiteiten'),
                        ),
                        trailing: IconButton(
                          tooltip: 'Dagindeling verwijderen',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (confirmContext) => AlertDialog(
                                title: const Text('Dagindeling verwijderen?'),
                                content: Text(
                                  'Wil je ‘' + template.name + '’ verwijderen?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, false),
                                    child: const Text('Annuleren'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, true),
                                    child: const Text('Verwijderen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await widget.controller.deleteTemplate(template.id);
                              setDialogState(() {});
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      ),
    );
  }
}
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.speechRate, required this.toggle, required this.edit, required this.delete, required this.reorderHandle});
  final DayActivity activity;
  final double speechRate;
  final VoidCallback toggle;
  final VoidCallback edit;
  final VoidCallback delete;
  final Widget reorderHandle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 55, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(12)), child: Text(activity.time, textAlign: TextAlign.center, style: const TextStyle(color: _green, fontWeight: FontWeight.w800, fontSize: 12))),
            const SizedBox(width: 13),
            Expanded(child: InkWell(
              onTap: edit,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text(activity.symbol, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 9),
                  Expanded(child: Text(activity.title, style: TextStyle(color: activity.done ? _muted : _ink, fontSize: 16, fontWeight: FontWeight.w700, decoration: activity.done ? TextDecoration.lineThrough : null))),
                ]),
                if (activity.photoPath.isNotEmpty && File(activity.photoPath).existsSync()) ...[
                  const SizedBox(height: 9),
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(activity.photoPath), height: 110, width: 150, fit: BoxFit.cover)),
                ],
                if (activity.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(activity.note, style: const TextStyle(color: _muted, fontSize: 13))),
                const SizedBox(height: 7),
                const Text('Tik om de vijf vragen te bekijken', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            )),
            reorderHandle,
            SpeakButton(text: activity.title + '. ' + activity.time + '. Wie: ' + activity.who + '. Wat: ' + activity.what + '. Waar: ' + activity.where + '. Hoe: ' + activity.how + '.', speechRate: speechRate),
            IconButton(tooltip: activity.done ? 'Niet afgerond' : 'Markeer als afgerond', onPressed: toggle, icon: Icon(activity.done ? Icons.check_circle : Icons.circle_outlined, color: activity.done ? _green : _muted)),
            PopupMenuButton<String>(
              tooltip: 'Meer opties',
              onSelected: (choice) { if (choice == 'edit') edit(); if (choice == 'delete') delete(); },
              itemBuilder: (context) => const [PopupMenuItem(value: 'edit', child: Text('Bewerken')), PopupMenuItem(value: 'delete', child: Text('Verwijderen'))],
            ),
          ]),
        ),
      );
}

Future<void> editActivity(BuildContext context, MoodPressController controller, {DayActivity? existing}) async {
  final result = await showDialog<DayActivity>(context: context, builder: (context) => ActivityEditor(existing: existing));
  if (result != null) await controller.saveActivity(result);
}

Future<void> confirmDelete(BuildContext context, MoodPressController controller, DayActivity activity) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Activiteit verwijderen?'),
      content: Text('Wil je "' + activity.title + '" uit jouw dagplan halen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuleren')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verwijderen')),
      ],
    ),
  );
  if (result == true) await controller.deleteActivity(activity.id);
}

class ActivityEditor extends StatefulWidget {
  const ActivityEditor({super.key, this.existing});
  final DayActivity? existing;

  @override
  State<ActivityEditor> createState() => _ActivityEditorState();
}

class _ActivityEditorState extends State<ActivityEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController time;
  late final TextEditingController who;
  late final TextEditingController what;
  late final TextEditingController where;
  late final TextEditingController how;
  late final TextEditingController note;
  String symbol = '📌';
  String photoPath = '';

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    title = TextEditingController(text: item?.title ?? '');
    time = TextEditingController(text: item?.time ?? '09:00');
    who = TextEditingController(text: item?.who ?? 'Ik');
    what = TextEditingController(text: item?.what ?? '');
    where = TextEditingController(text: item?.where ?? '');
    how = TextEditingController(text: item?.how ?? '');
    note = TextEditingController(text: item?.note ?? '');
    symbol = item?.symbol ?? '📌';
    photoPath = item?.photoPath ?? '';
  }

  @override
  void dispose() {
    title.dispose(); time.dispose(); who.dispose(); what.dispose(); where.dispose(); how.dispose(); note.dispose();
    super.dispose();
  }

  Widget field(TextEditingController controller, String label, String hint, {bool required = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          controller: controller,
          maxLines: lines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: required ? (value) => value == null || value.trim().isEmpty ? 'Vul een naam in.' : null : null,
        ),
      );

  Future<void> choosePhoto() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return;
      final file = picked.first;
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) return;
      final directory = await getApplicationSupportDirectory();
      final imageDirectory = Directory('${directory.path}${Platform.pathSeparator}activity_images');
      await imageDirectory.create(recursive: true);
      final extension = (file.extension ?? 'jpg').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final safeName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
      final saved = await File(sourcePath).copy(
        '${imageDirectory.path}${Platform.pathSeparator}$safeName',
      );
      if (!mounted) return;
      setState(() => photoPath = saved.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('De foto kon niet worden toegevoegd. Probeer een andere afbeelding.')));
    }
  }

  void save() {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.existing;
    Navigator.pop(context, DayActivity(
      id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.text.trim(),
      time: time.text.trim().isEmpty ? '09:00' : time.text.trim(),
      who: who.text.trim(),
      what: what.text.trim(),
      where: where.text.trim(),
      how: how.text.trim(),
      note: note.text.trim(),
      symbol: symbol,
      photoPath: photoPath,
      done: old?.done ?? false,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Nieuwe activiteit' : 'Activiteit aanpassen'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Maak de uitleg kort en duidelijk. Je kunt dit samen invullen.', style: TextStyle(color: _muted)),
                const SizedBox(height: 12),
                const SizedBox(height: 8),
                const Text('Pictogram', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: symbol,
                  decoration: const InputDecoration(labelText: 'Kies een herkenbaar plaatje'),
                  items: const [
                    DropdownMenuItem(value: '📌', child: Text('📌  Algemeen')),
                    DropdownMenuItem(value: '🍽️', child: Text('🍽️  Eten')),
                    DropdownMenuItem(value: '🚿', child: Text('🚿  Douchen')),
                    DropdownMenuItem(value: '👕', child: Text('👕  Aankleden')),
                    DropdownMenuItem(value: '🏠', child: Text('🏠  Thuis')),
                    DropdownMenuItem(value: '🚶', child: Text('🚶  Wandelen')),
                    DropdownMenuItem(value: '🚌', child: Text('🚌  Reizen')),
                    DropdownMenuItem(value: '💊', child: Text('💊  Medicatie')),
                    DropdownMenuItem(value: '🧹', child: Text('🧹  Opruimen')),
                    DropdownMenuItem(value: '🎮', child: Text('🎮  Vrije tijd')),
                    DropdownMenuItem(value: '🛒', child: Text('🛒  Boodschappen')),
                    DropdownMenuItem(value: '😴', child: Text('😴  Rust')),
                  ],
                  onChanged: (value) { if (value != null) setState(() => symbol = value); },
                ),
                const SizedBox(height: 12),
                const Text('Eigen foto (optioneel)', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                const Text('Kies een foto die jou helpt de activiteit te herkennen. De foto blijft op dit apparaat.', style: TextStyle(color: _muted, fontSize: 13)),
                if (photoPath.isNotEmpty && File(photoPath).existsSync()) ...[
                  const SizedBox(height: 9),
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(photoPath), height: 130, width: double.infinity, fit: BoxFit.cover)),
                ],
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: choosePhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Foto kiezen')),
                  if (photoPath.isNotEmpty) TextButton.icon(onPressed: () => setState(() => photoPath = ''), icon: const Icon(Icons.close), label: const Text('Foto weghalen')),
                ]),
                field(title, 'Naam van de activiteit', 'Bijvoorbeeld: naar de winkel', required: true),
                field(time, 'Wanneer?', 'Bijvoorbeeld: 10:30'),
                field(who, 'Wie?', 'Wie is erbij?'),
                field(what, 'Wat?', 'Wat ga je doen?'),
                field(where, 'Waar?', 'Waar gebeurt het?'),
                field(how, 'Hoe?', 'Welke kleine stappen helpen?'),
                field(note, 'Extra uitleg (optioneel)', 'Wat is fijn om vooraf te weten?', lines: 2),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(onPressed: save, child: const Text('Opslaan')),
        ],
      );
}

class CalmPage extends StatefulWidget {
  const CalmPage({super.key});
  @override
  State<CalmPage> createState() => _CalmPageState();
}

class CalmStep {
  const CalmStep({required this.title, required this.description, required this.icon});
  final String title;
  final String description;
  final IconData icon;
}

class _CalmPageState extends State<CalmPage> {
  int step = 0;
  static const steps = [
    CalmStep(title: 'Voel de grond', description: 'Zet je voeten neer. Voel waar je voeten de grond raken.', icon: Icons.place_outlined),
    CalmStep(title: 'Kijk rustig om je heen', description: 'Noem voor jezelf drie dingen die je ziet. Je hoeft niets hardop te zeggen.', icon: Icons.remove_red_eye_outlined),
    CalmStep(title: 'Kies één kleine stap', description: 'Wat heb je nu nodig? Rust, hulp of verdergaan?', icon: Icons.spa_outlined),
  ];

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Even rust',
        subtitle: 'Een rustig moment. Je hoeft niets goed te doen.',
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(23)),
              child: Column(children: [
                CircleAvatar(radius: 33, backgroundColor: Colors.white, child: Icon(steps[step].icon, color: _green, size: 29)),
                const SizedBox(height: 18),
                Text('STAP ' + (step + 1).toString() + ' VAN 3', style: const TextStyle(color: _green, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                const SizedBox(height: 11),
                Text(steps[step].title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(steps[step].description, textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 16, height: 1.5)),
                const SizedBox(height: 23),
                Row(children: List.generate(3, (index) => Expanded(child: Container(height: 5, margin: EdgeInsets.only(right: index == 2 ? 0 : 7), decoration: BoxDecoration(color: index <= step ? _green : _line, borderRadius: BorderRadius.circular(5)))))),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: step == 0 ? null : () => setState(() => step--), child: const Text('Vorige'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(onPressed: () => setState(() => step = step == 2 ? 0 : step + 1), child: Text(step == 2 ? 'Opnieuw' : 'Volgende'))),
                ]),
                TextButton(onPressed: () => setState(() => step = 0), child: const Text('Stop met deze oefening')),
              ]),
            ),
            const SizedBox(height: 14),
            const Card(child: Padding(padding: EdgeInsets.all(17), child: Text('Je mag een stap overslaan of stoppen. Als dit niet prettig voelt, kies dan iets anders dat voor jou veilig en vertrouwd is.', style: TextStyle(color: _muted, height: 1.45)))),
          ]),
        )),
      );
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Mijn steun',
        subtitle: 'Zet hier wat jou helpt als een dag moeilijk voelt.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: _sand, borderRadius: BorderRadius.circular(18)), child: const Text('Je hoeft het niet alleen te doen. Je mag om hulp vragen en je eigen tempo volgen.', style: TextStyle(color: _ink, fontWeight: FontWeight.w600))),
          const SizedBox(height: 18),
          SupportCard(title: 'Als ik vastloop', value: controller.support['help'] ?? '', icon: Icons.pan_tool_outlined, edit: () => editSupport(context, controller, 'help', 'Als ik vastloop')),
          const SizedBox(height: 10),
          SupportCard(title: 'Een plek waar ik rust vind', value: controller.support['place'] ?? '', icon: Icons.home_outlined, edit: () => editSupport(context, controller, 'place', 'Een plek waar ik rust vind')),
          const SizedBox(height: 10),
          SupportCard(title: 'Iemand die mij kan helpen', value: (controller.support['person'] ?? '').isEmpty ? 'Nog niet ingevuld' : controller.support['person']!, icon: Icons.people_outline, edit: () => editSupport(context, controller, 'person', 'Iemand die mij kan helpen')),
          const SizedBox(height: 22),
          const Text('Wat kun je doen als het te veel wordt?', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const SimpleStep(number: '1', text: 'Ga naar een plek die voor jou rustig en veilig voelt.'),
          const SimpleStep(number: '2', text: 'Kies één ding. De rest kan wachten.'),
          const SimpleStep(number: '3', text: 'Vraag iemand die je vertrouwt om hulp.'),
          const SizedBox(height: 13),
          const Text('Bij direct gevaar: bel 112 of vraag iemand in de buurt om direct hulp te halen.', style: TextStyle(color: _muted, fontSize: 12, height: 1.45)),
          if (controller.storageNotice != null) Padding(padding: const EdgeInsets.only(top: 12), child: StorageNotice(message: controller.storageNotice!)),
          const SizedBox(height: 18),
          const SmallDisclaimer(),
        ]),
      );
}


Future<String?> _askBackupPassword(
  BuildContext context, {
  required bool confirm,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _BackupPasswordDialog(confirm: confirm),
    );

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.trim().length < 8) {
      setState(() => _error = 'Kies een wachtwoord van minimaal 8 tekens.');
      return;
    }
    if (widget.confirm && _password.text != _confirmation.text) {
      setState(() => _error = 'De wachtwoorden zijn niet hetzelfde.');
      return;
    }
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.confirm ? 'Beveilig je back-up' : 'Open je back-up'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.confirm
                    ? 'Kies een wachtwoord dat je kunt onthouden. Je hebt dit nodig om de back-up later te openen. MoodPress kan het niet voor je terughalen.'
                    : 'Vul het wachtwoord in dat je hebt gebruikt toen je deze back-up maakte.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscure,
                autofocus: true,
                textInputAction: widget.confirm ? TextInputAction.next : TextInputAction.done,
                onSubmitted: (_) {
                  if (!widget.confirm) _submit();
                },
                decoration: InputDecoration(
                  labelText: 'Wachtwoord',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Wachtwoord tonen' : 'Wachtwoord verbergen',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              if (widget.confirm) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmation,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Herhaal wachtwoord'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.confirm ? 'Maak back-up' : 'Verder'),
          ),
        ],
      );

String _backupErrorMessage(Object error, {required bool importing}) {
  if (error is FormatException) return error.message.toString();
  if (error is ArgumentError) return error.message.toString();
  return importing
      ? 'De back-up kon niet worden teruggezet. Je bestaande gegevens zijn niet bewust gewist.'
      : 'De back-up kon niet worden gemaakt of bewaard.';
}

Future<void> _exportMoodPressBackup(
  BuildContext context,
  MoodPressController controller,
) async {
  final password = await _askBackupPassword(context, confirm: true);
  if (password == null || !context.mounted) return;

  try {
    final bytes = await controller.createBackupBytes(password);
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Bewaar je MoodPress-back-up',
      fileName: 'moodpress-back-up.mpb',
      mimeType: 'application/octet-stream',
      type: FileType.custom,
      allowedExtensions: ['mpb'],
      bytes: bytes,
    );
    if (!context.mounted || saved == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Je beveiligde back-up is bewaard.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_backupErrorMessage(error, importing: false))),
    );
  }
}

Future<void> _importMoodPressBackup(
  BuildContext context,
  MoodPressController controller,
) async {
  try {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mpb'],
    );
    if (picked == null || !context.mounted) return;
    final length = await picked.length();
    if (length != null && length > _maxBackupFileBytes) {
      throw FormatException('Dit back-upbestand is te groot om veilig te openen.');
    }

    final password = await _askBackupPassword(context, confirm: false);
    if (password == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Back-up terugzetten?'),
        content: const Text(
          'De huidige dagplannen, dagindelingen, het weekritme, je steunplan en instellingen worden vervangen door de gegevens uit deze back-up. Dit kun je niet automatisch ongedaan maken.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Terugzetten'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    await controller.restoreBackupBytes(bytes, password);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Je MoodPress-back-up is teruggezet.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_backupErrorMessage(error, importing: true))),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Instellingen',
        subtitle: 'Pas MoodPress aan op wat prettig werkt voor jou.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.text_fields_rounded, color: _green),
                  SizedBox(width: 10),
                  Text('Tekstgrootte', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Kies tekst die prettig leesbaar is.', style: TextStyle(color: _muted)),
                const SizedBox(height: 15),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1.0, label: Text('Normaal')),
                    ButtonSegment(value: 1.15, label: Text('Groter')),
                    ButtonSegment(value: 1.3, label: Text('Extra groot')),
                  ],
                  selected: {controller.preferences.textScale},
                  onSelectionChanged: (values) => controller.setTextScale(values.first),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.motion_photos_off_outlined, color: _green),
                  SizedBox(width: 10),
                  Expanded(child: Text('Minder beweging', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 5),
                const Text('Schakel bewegende overgangen en animaties zoveel mogelijk uit als dat rustiger voelt.', style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rustige weergave'),
                  subtitle: const Text('Minder animaties in de app'),
                  value: controller.preferences.reduceMotion,
                  onChanged: controller.setReduceMotion,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.notifications_none_rounded, color: _green),
                  SizedBox(width: 10),
                  Text('Herinneringen', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Krijg op het geplande tijdstip een rustige melding zolang MoodPress open is. Je kunt dit altijd uitzetten.', style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Herinneringen in de app'),
                  subtitle: const Text('Staat standaard uit'),
                  value: controller.preferences.inAppRemindersEnabled,
                  onChanged: controller.setInAppRemindersEnabled,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.backup_outlined, color: _green),
                  SizedBox(width: 10),
                  Text('Back-up en terugzetten', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text(
                  'Bewaar je planning, dagindelingen, weekritme, steunplan, instellingen en activiteitfoto’s op een plek die jij kiest. De back-up wordt met een wachtwoord versleuteld.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () => _exportMoodPressBackup(context, controller),
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Maak back-up'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _importMoodPressBackup(context, controller),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Zet back-up terug'),
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Je wachtwoord is niet te herstellen. Bewaar het goed. Een back-up kan persoonlijke informatie bevatten.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.volume_up_outlined, color: _green),
                  SizedBox(width: 10),
                  Text('Voorleessnelheid', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Maak het voorlezen langzamer of sneller.', style: TextStyle(color: _muted)),
                Slider(
                  value: controller.preferences.speechRate,
                  min: 0.3,
                  max: 0.6,
                  divisions: 6,
                  label: controller.preferences.speechRate.toStringAsFixed(2),
                  onChanged: controller.setSpeechRate,
                ),
                const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Langzaam', style: TextStyle(color: _muted, fontSize: 12)),
                  Text('Sneller', style: TextStyle(color: _muted, fontSize: 12)),
                ]),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => SpeakButtonPreview.play(context, controller.preferences.speechRate),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Luister naar een voorbeeld'),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Jouw instellingen', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                const Text('Je voorkeuren worden op dit apparaat bewaard. Ze worden niet naar een account of cloud verstuurd.', style: TextStyle(color: _muted, height: 1.45)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.resetPreferences,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Herstel standaardinstellingen'),
                ),
              ]),
            ),
          ),
          if (controller.storageNotice != null) ...[
            const SizedBox(height: 12),
            StorageNotice(message: controller.storageNotice!),
          ],
          const SizedBox(height: 18),
          const SmallDisclaimer(),
        ]),
      );
}

class SpeakButtonPreview {
  static Future<void> play(BuildContext context, double rate) async {
    final messenger = ScaffoldMessenger.of(context);
    final tts = FlutterTts();
    try {
      await tts.setLanguage('nl-NL');
      await tts.setSpeechRate(rate);
      await tts.setPitch(1.0);
      await tts.awaitSpeakCompletion(true);
      await tts.speak('Dit is een voorbeeld. Je kunt de voorleessnelheid aanpassen aan wat prettig is.');
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Voorlezen is op dit apparaat niet beschikbaar.')));
    } finally {
      await tts.stop();
    }
  }
}

class SupportCard extends StatelessWidget {
  const SupportCard({super.key, required this.title, required this.value, required this.icon, required this.edit});
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback edit;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _green)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value.isEmpty ? 'Nog niet ingevuld' : value, style: const TextStyle(color: _muted, fontSize: 13, height: 1.35)),
          ])),
          IconButton(tooltip: 'Aanpassen', onPressed: edit, icon: const Icon(Icons.edit_outlined, color: _green)),
        ]),
      ));
}

Future<void> editSupport(BuildContext context, MoodPressController controller, String key, String title) async {
  final field = TextEditingController(text: controller.support[key] ?? '');
  final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 450, child: TextField(controller: field, autofocus: true, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Schrijf op wat jou helpt.'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Opslaan')),
        ],
      ));
  field.dispose();
  if (value != null) await controller.saveSupport(key, value);
}

class SimpleStep extends StatelessWidget {
  const SimpleStep({super.key, required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 13, backgroundColor: _greenPale, child: Text(number, style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w800))),
        const SizedBox(width: 11),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(text, style: const TextStyle(color: _ink)))),
      ]));
}

class StorageNotice extends StatelessWidget {
  const StorageNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFFFF2E6), borderRadius: BorderRadius.circular(13)), child: Text(message, style: const TextStyle(color: _ink, fontSize: 12, height: 1.4)));
}

class SmallDisclaimer extends StatelessWidget {
  const SmallDisclaimer({super.key});

  @override
  Widget build(BuildContext context) => const Text(
        'MoodPress helpt bij dagstructuur en overzicht. De app stelt geen diagnose en vervangt geen professionele zorg.',
        style: TextStyle(color: _muted, fontSize: 11, height: 1.45),
      );
}

class SpeakButton extends StatefulWidget {
  const SpeakButton({super.key, required this.text, this.speechRate = 0.42});
  final String text;
  final double speechRate;

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  final FlutterTts _tts = FlutterTts();
  bool speaking = false;

  Future<void> _toggle() async {
    try {
      if (speaking) {
        await _tts.stop();
        if (mounted) setState(() => speaking = false);
        return;
      }
      await _tts.setLanguage('nl-NL');
      await _tts.setSpeechRate(widget.speechRate);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      if (mounted) setState(() => speaking = true);
      await _tts.speak(widget.text);
      if (mounted) setState(() => speaking = false);
    } catch (_) {
      if (mounted) setState(() => speaking = false);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: speaking ? 'Stop voorlezen' : 'Lees voor',
        onPressed: _toggle,
        icon: Icon(speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined, color: _green),
      );
}
).firstMatch(path);
      final candidate = match?.group(1)?.toLowerCase() ?? 'jpg';
      final extension = const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'}
              .contains(candidate)
          ? candidate
          : 'jpg';
      photos[id] = {
        'extension': extension,
        'data': base64Encode(bytes),
      };
    }

    Map<String, dynamic> activityJson(DayActivity activity) {
      final values = Map<String, dynamic>.from(activity.toJson())
        ..remove('photoPath');
      final photoId = photoIds[activity.photoPath];
      if (photoId != null) values['photoId'] = photoId;
      return values;
    }

    Map<String, dynamic> templateJson(DayTemplate template) => {
          'id': template.id,
          'name': template.name,
          'activities': template.activities.map(activityJson).toList(),
        };

    final document = <String, dynamic>{
      'app': 'MoodPress',
      'dataVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'dayPlans': {
        for (final entry in _plansByDate.entries)
          entry.key: entry.value.map(activityJson).toList(),
      },
      'support': Map<String, String>.from(support),
      'preferences': preferences.toJson(),
      'templates': templates.map(templateJson).toList(),
      'weeklyRoutine': {
        for (final entry in weeklyRoutine.days.entries)
          entry.key.toString(): templateJson(entry.value),
      },
      'photos': photos,
    };

    return encryptMoodPressBackup(document, password);
  }

  Future<void> restoreBackupBytes(
    Uint8List fileBytes,
    String password,
  ) async {
    final document = await decryptMoodPressBackup(fileBytes, password);
    final savedPhotoFiles = <File>[];

    try {
      final rawPhotos = document['photos'];
      if (rawPhotos is! Map<String, dynamic>) {
        throw FormatException('De foto’s in deze back-up zijn niet geldig.');
      }

      final photoPaths = <String, String>{};
      var totalPhotoBytes = 0;
      var photoIndex = 0;
      if (rawPhotos.isNotEmpty) {
        final directory = await getApplicationSupportDirectory();
        final imageDirectory = Directory(
          directory.path + Platform.pathSeparator + 'activity_images',
        );
        await imageDirectory.create(recursive: true);

        for (final entry in rawPhotos.entries) {
          if (!RegExp(r'^photo_[0-9]+
    preferences = MoodPressPreferences(
      textScale: value.clamp(1.0, 1.4).toDouble(),
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setSpeechRate(double value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: value.clamp(0.3, 0.6).toDouble(),
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: value,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setInAppRemindersEnabled(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: value,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> resetPreferences() async {
    preferences = const MoodPressPreferences();
    await _savePreferences();
    notifyListeners();
  }

  Future<void> _savePreferences() async {
    try {
      await _storage.write(
        key: _preferencesKey,
        value: jsonEncode(preferences.toJson()),
      );
    } catch (_) {
      storageNotice = 'Je instellingen konden niet veilig worden opgeslagen.';
    }
  }

  void setFeeling(String value) {
    // This voluntary check-in is temporary and is never stored as a health record.
    feeling = value;
    notifyListeners();
  }
}

class MoodPressApp extends StatelessWidget {
  const MoodPressApp({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.light)
        .copyWith(primary: _green, onPrimary: Colors.white, onSurface: _ink);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        title: 'MoodPress',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(systemScale * controller.preferences.textScale),
              disableAnimations: controller.preferences.reduceMotion,
            ),
            child: child!,
          );
        },
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: _paper,
          fontFamily: 'Arial',
          textTheme: const TextTheme(
            headlineLarge: TextStyle(color: _ink, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.6),
            headlineMedium: TextStyle(color: _ink, fontSize: 25, fontWeight: FontWeight.w700),
            titleLarge: TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w700),
            bodyLarge: TextStyle(color: _ink, fontSize: 16, height: 1.45),
            bodyMedium: TextStyle(color: _muted, fontSize: 14, height: 1.45),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFFAFAF7),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          ),
        ),
        home: controller.ready ? MoodPressShell(controller: controller) : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}

class MoodPressShell extends StatefulWidget {
  const MoodPressShell({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<MoodPressShell> createState() => _MoodPressShellState();
}

class _MoodPressShellState extends State<MoodPressShell> {
  int selected = 0;
  Timer? _reminderTimer;
  final Set<String> _shownReminders = <String>{};

  @override
  void initState() {
    super.initState();
    _reminderTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkInAppReminders(),
    );
  }

  void _checkInAppReminders() {
    if (!mounted || !widget.controller.preferences.inAppRemindersEnabled) return;
    final now = DateTime.now();
    final dateKey = _dateKey(now);
    for (final activity in widget.controller.activitiesFor(now)) {
      if (!isActivityDueAt(activity, now)) continue;
      final reminderKey = '$dateKey-${activity.id}';
      if (!_shownReminders.add(reminderKey)) continue;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Rustige herinnering: ${activity.title}. Als het nu niet uitkomt, mag je het overslaan.'),
          duration: const Duration(seconds: 8),
        ));
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }
  static const labels = ['Vandaag', 'Planning', 'Even rust', 'Mijn steun', 'Instellingen'];
  static const icons = [Icons.wb_sunny_outlined, Icons.calendar_month_outlined, Icons.spa_outlined, Icons.favorite_border, Icons.tune_rounded];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        final pages = [
          TodayPage(controller: widget.controller, openPlan: () => setState(() => selected = 1)),
          PlanningPage(controller: widget.controller),
          const CalmPage(),
          SupportPage(controller: widget.controller),
          SettingsPage(controller: widget.controller),
        ];
        return Scaffold(
          body: Row(children: [
            if (desktop)
              NavigationRail(
                backgroundColor: const Color(0xFFFBFBF8),
                selectedIndex: selected,
                onDestinationSelected: (value) => setState(() => selected = value),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(padding: EdgeInsets.fromLTRB(4, 22, 4, 28), child: BrandMark()),
                destinations: List.generate(labels.length, (index) => NavigationRailDestination(icon: Icon(icons[index]), label: Text(labels[index]))),
              ),
            Expanded(child: IndexedStack(index: selected, children: pages)),
          ]),
          bottomNavigationBar: desktop ? null : NavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (value) => setState(() => selected = value),
            destinations: List.generate(labels.length, (index) => NavigationDestination(icon: Icon(icons[index]), label: labels[index])),
          ),
        );
      });
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.waves_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 10),
        const Text('moodpress', style: TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
      ]);
}

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child, this.title, this.subtitle, this.action});
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 38),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) ...[
                LayoutBuilder(builder: (context, constraints) {
                  final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title!, style: Theme.of(context).textTheme.headlineMedium),
                    if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle!)),
                  ]);
                  if (action == null) return heading;
                  if (constraints.maxWidth < 580) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const SizedBox(height: 13), action!]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: heading), action!]);
                }),
                const SizedBox(height: 24),
              ],
              child,
            ]),
          ),
        ),
      );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.controller, required this.openPlan});
  final MoodPressController controller;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Goedemorgen' : now.hour < 18 ? 'Goedemiddag' : 'Goedenavond';
    final todayActivities = controller.activitiesFor(now);
    final upcoming = todayActivities.where((item) => !item.done).toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    final completedToday = todayActivities.where((item) => item.done).length;
    final progressToday = todayActivities.isEmpty ? 0.0 : completedToday / todayActivities.length;

    return PageFrame(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const BrandMark(),
      const SizedBox(height: 28),
      Text(greeting + '.', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text('We doen het rustig aan. Eén ding tegelijk.', style: TextStyle(color: _muted, fontSize: 16)),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, constraints) {
        final nextCard = NextStepCard(activity: next, openPlan: openPlan);
        final progressCard = ProgressCard(done: completedToday, total: todayActivities.length, progress: progressToday, openPlan: openPlan);
        if (constraints.maxWidth > 650) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: nextCard), const SizedBox(width: 14), Expanded(flex: 4, child: progressCard)]);
        return Column(children: [nextCard, const SizedBox(height: 14), progressCard]);
      }),
      const SizedBox(height: 28),
      Text('Hoe is het nu met je?', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Kies wat bij dit moment past. Je hoeft niets uit te leggen.', style: TextStyle(color: _muted)),
      const SizedBox(height: 14),
      Wrap(spacing: 9, runSpacing: 9, children: [
        FeelingChoice(label: 'Rustig', emoji: '🙂', selected: controller.feeling == 'Rustig', onTap: () => controller.setFeeling('Rustig')),
        FeelingChoice(label: 'Wat onrustig', emoji: '😐', selected: controller.feeling == 'Wat onrustig', onTap: () => controller.setFeeling('Wat onrustig')),
        FeelingChoice(label: 'Een vol hoofd', emoji: '😣', selected: controller.feeling == 'Een vol hoofd', onTap: () => controller.setFeeling('Een vol hoofd')),
      ]),
      if (controller.feeling != null) const Padding(padding: EdgeInsets.only(top: 13), child: Text('Dank je. Je hoeft hier verder niets mee te doen.', style: TextStyle(color: _muted, fontSize: 13))),
      if (controller.storageNotice != null) Padding(padding: const EdgeInsets.only(top: 16), child: StorageNotice(message: controller.storageNotice!)),
      const SizedBox(height: 22),
      const SmallDisclaimer(),
    ]));
  }
}

class NextStepCard extends StatelessWidget {
  const NextStepCard({super.key, required this.activity, required this.openPlan});
  final DayActivity? activity;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(23),
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(23)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('DIT IS JE VOLGENDE STAP', style: TextStyle(color: Color(0xFFE1ECE6), fontSize: 10, letterSpacing: 1.35, fontWeight: FontWeight.w800)),
          const SizedBox(height: 17),
          Text(activity?.title ?? 'Je dag is klaar', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(activity == null ? 'Goed gedaan. Neem de tijd voor jezelf.' : activity!.time + ' uur · ' + (activity!.note.isEmpty ? 'Je kunt dit stap voor stap doen.' : activity!.note), style: const TextStyle(color: Color(0xFFE9F0EB), height: 1.45)),
          const SizedBox(height: 21),
          FilledButton.icon(onPressed: openPlan, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _green), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Bekijk mijn planning')),
        ]),
      );
}

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.done, required this.total, required this.progress, required this.openPlan});
  final int done;
  final int total;
  final double progress;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(21),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('JOUW DAG', style: TextStyle(fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: _muted)),
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(width: 70, height: 70, child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: progress, strokeWidth: 7, backgroundColor: _greenPale, color: _green)),
                Text((progress * 100).round().toString() + '%', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
              ])),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(done.toString() + ' van ' + total.toString() + ' gedaan', style: const TextStyle(fontSize: 15, color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Elke stap telt. Ook een kleine stap.', style: TextStyle(color: _muted, fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 12),
            TextButton.icon(onPressed: openPlan, icon: const Icon(Icons.list_alt_outlined), label: const Text('Mijn weekplanning')),
          ]),
        ),
      );
}

class FeelingChoice extends StatelessWidget {
  const FeelingChoice({super.key, required this.label, required this.emoji, required this.selected, required this.onTap});
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? _greenPale : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? _green : _line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(emoji, style: const TextStyle(fontSize: 18)), const SizedBox(width: 8), Text(label, style: TextStyle(color: _ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))]),
          ),
        ),
      );
}

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  bool _showWeek = true;
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayFor(DateTime.now());
  }

  DateTime _mondayFor(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);

  String _rangeLabel() {
    final lastDay = _weekStart.add(const Duration(days: 6));
    return _formatDutchDate(_weekStart) + ' - ' +
        _formatDutchDate(lastDay) + ' ' + lastDay.year.toString();
  }

  void _openDay(DateTime date) {
    widget.controller.selectDate(date);
    setState(() => _showWeek = false);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Mijn planning',
        subtitle: _showWeek
            ? 'Een rustig overzicht van maandag tot en met zondag.'
            : 'Bekijk één dag tegelijk. Je kunt alles aanpassen.',
        action: _showWeek
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showWeeklyRoutineManager(context),
                    icon: const Icon(Icons.repeat_rounded),
                    label: const Text('Vast weekritme'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showTemplateManager(context),
                    icon: const Icon(Icons.library_books_outlined),
                    label: const Text('Dagindelingen'),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: () => editActivity(context, widget.controller),
                icon: const Icon(Icons.add),
                label: const Text('Activiteit toevoegen'),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Weekoverzicht')),
                ButtonSegment(value: false, label: Text('Dagplan')),
              ],
              selected: {_showWeek},
              onSelectionChanged: (values) =>
                  setState(() => _showWeek = values.first),
            ),
            const SizedBox(height: 18),
            if (_showWeek) _buildWeek(context) else _buildDay(context),
          ],
        ),
      );

  Widget _buildWeek(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Vorige week',
              onPressed: () => setState(
                () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _rangeLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Volgende week',
              onPressed: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var offset = 0; offset < 7; offset++)
          _buildWeekDayCard(
            context,
            _weekStart.add(Duration(days: offset)),
          ),
        if (widget.controller.weeklyRoutine.days.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 8),
            child: Card(
              color: _greenPale,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vaste dagen invullen',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.controller.routinesInWeek(_weekStart).toString() +
                          ' lege dagen kunnen worden gevuld. Bestaande plannen blijven staan.',
                      style: const TextStyle(color: _muted, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: widget.controller.routinesInWeek(_weekStart) == 0
                          ? null
                          : () => _applyWeeklyRoutine(context),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Vul lege dagen met weekritme'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.controller.templates.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: _green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Je hebt nog geen vaste dagindeling. Open een dagplan en kies ‘Bewaar als dagindeling’ om een sjabloon te maken.',
                      style: TextStyle(color: _ink, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              widget.controller.templates.length.toString() +
                  (widget.controller.templates.length == 1
                      ? ' dagindeling beschikbaar'
                      : ' dagindelingen beschikbaar'),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => setState(() => _weekStart = _mondayFor(DateTime.now())),
          icon: const Icon(Icons.today_outlined),
          label: const Text('Ga naar deze week'),
        ),
      ],
    );
  }

  Widget _buildWeekDayCard(BuildContext context, DateTime date) {
    final items = widget.controller.activitiesFor(date);
    final completed = items.where((item) => item.done).length;
    final summary = items.isEmpty
        ? 'Nog geen dagplan'
        : items.length.toString() +
            (items.length == 1 ? ' activiteit · ' : ' activiteiten · ') +
            completed.toString() + ' afgerond';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _greenPale,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  date.day.toString(),
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDutchWeekday(date),
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (widget.controller.weeklyRoutine.forWeekday(date.weekday) != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Text(
                          'Vaste indeling beschikbaar',
                          style: TextStyle(
                            color: _green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      summary,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openDay(date),
                child: const Text('Open dag'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Dagindeling toepassen',
                enabled: widget.controller.templates.isNotEmpty,
                icon: const Icon(Icons.copy_all_outlined, color: _green),
                onSelected: (templateId) =>
                    _applyTemplateToDate(context, date, templateId),
                itemBuilder: (context) => widget.controller.templates
                    .map(
                      (template) => PopupMenuItem<String>(
                        value: template.id,
                        child: Text(template.name),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDay(BuildContext context) {
    final date = widget.controller.selectedDate;
    final items = widget.controller.activities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Vorige dag',
                  onPressed: () =>
                      widget.controller.selectDate(date.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatDutchWeekday(date),
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _formatDutchDate(date) + ' ' + date.year.toString(),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Volgende dag',
                  onPressed: () =>
                      widget.controller.selectDate(date.add(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 13),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: _sand,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Text(
            'Kijk alleen naar de eerstvolgende activiteit. De rest komt later.',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 15),
        if (items.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: items.length,
            onReorder: widget.controller.reorderActivities,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: 11),
                child: ActivityCard(
                  activity: item,
                  speechRate: widget.controller.preferences.speechRate,
                  toggle: () => widget.controller.toggleActivity(item.id),
                  edit: () => editActivity(context, widget.controller, existing: item),
                  delete: () => confirmDelete(context, widget.controller, item),
                  reorderHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 12),
                      child: Icon(Icons.drag_handle_rounded, color: _muted),
                    ),
                  ),
                ),
              );
            },
          ),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'Voor deze dag staat nog niets gepland. Voeg een activiteit toe of gebruik een dagindeling.',
                style: TextStyle(color: _muted, height: 1.45),
              ),
            ),
          ),
        Wrap(
          spacing: 9,
          runSpacing: 7,
          children: [
            OutlinedButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => _saveTemplateFromDay(context, date),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Bewaar als dagindeling'),
            ),
            OutlinedButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => _saveWeeklyRoutineFromDay(context, date),
              icon: const Icon(Icons.repeat_rounded),
              label: const Text('Bewaar als vast weekritme'),
            ),
            TextButton.icon(
              onPressed: () => widget.controller.selectDate(DateTime.now()),
              icon: const Icon(Icons.today_outlined),
              label: const Text('Vandaag'),
            ),
          ],
        ),
        if (widget.controller.storageNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: StorageNotice(message: widget.controller.storageNotice!),
          ),
      ],
    );
  }

  Future<void> _saveTemplateFromDay(BuildContext context, DateTime date) async {
    final field = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dagindeling bewaren'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: field,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Naam van de dagindeling',
              hintText: 'Bijvoorbeeld: Werkdag',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, field.text.trim()),
            child: const Text('Bewaren'),
          ),
        ],
      ),
    );
    field.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await widget.controller.saveTemplateFromDate(name, date);
    }
  }

  Future<void> _applyTemplateToDate(
    BuildContext context,
    DateTime date,
    String templateId,
  ) async {
    if (widget.controller.activitiesFor(date).isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Dagindeling vervangen?'),
          content: const Text(
            'De activiteiten die nu op deze dag staan, worden vervangen door de gekozen dagindeling.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vervangen'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.controller.applyTemplateToDate(templateId, date);
  }

  Future<void> _saveWeeklyRoutineFromDay(
    BuildContext context,
    DateTime date,
  ) async {
    final existing = widget.controller.weeklyRoutine.forWeekday(date.weekday);
    if (existing != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Vaste dagindeling aanpassen?'),
          content: Text(
            'Er is al een vaste indeling voor ' +
                _formatDutchWeekday(date) +
                '. Wil je deze vervangen door het huidige dagplan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vervangen'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await widget.controller.saveWeeklyRoutineFromDate(date);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Vaste indeling voor ' + _formatDutchWeekday(date) + ' bewaard.',
        ),
      ),
    );
  }

  Future<void> _applyWeeklyRoutine(BuildContext context) async {
    final count = widget.controller.routinesInWeek(_weekStart);
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Weekritme toepassen?'),
        content: Text(
          'MoodPress vult ' + count.toString() +
              (count == 1 ? ' lege dag' : ' lege dagen') +
              ' met de vaste indeling. Bestaande dagplannen blijven ongewijzigd.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lege dagen invullen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final added = await widget.controller.applyWeeklyRoutineToWeek(_weekStart);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added.toString() +
              (added == 1 ? ' dag ingevuld.' : ' dagen ingevuld.'),
        ),
      ),
    );
  }

  Future<void> _showWeeklyRoutineManager(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final routines = widget.controller.weeklyRoutine.days.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          return AlertDialog(
            title: const Text('Mijn vaste weekritme'),
            content: SizedBox(
              width: 460,
              height: 320,
              child: routines.isEmpty
                  ? const Center(
                      child: Text(
                        'Er zijn nog geen vaste dagen. Open een dagplan en bewaar het als weekritme.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: routines.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = routines[index];
                        final weekday = entry.key;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _dutchWeekdays[weekday - 1][0].toUpperCase() +
                                _dutchWeekdays[weekday - 1].substring(1),
                          ),
                          subtitle: Text(
                            entry.value.activities.length.toString() +
                                (entry.value.activities.length == 1
                                    ? ' vaste activiteit'
                                    : ' vaste activiteiten'),
                          ),
                          trailing: IconButton(
                            tooltip: 'Vaste dag verwijderen',
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text('Vaste dag verwijderen?'),
                                  content: Text(
                                    'Wil je het vaste weekritme voor ' +
                                        _dutchWeekdays[weekday - 1] +
                                        ' verwijderen?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, false),
                                      child: const Text('Annuleren'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, true),
                                      child: const Text('Verwijderen'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await widget.controller.removeWeeklyRoutine(weekday);
                                setDialogState(() {});
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Sluiten'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTemplateManager(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mijn dagindelingen'),
          content: SizedBox(
            width: 460,
            height: 300,
            child: widget.controller.templates.isEmpty
                ? const Center(
                    child: Text(
                      'Je hebt nog geen dagindelingen bewaard.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: widget.controller.templates.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final template = widget.controller.templates[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(template.name),
                        subtitle: Text(
                          template.activities.length.toString() +
                              (template.activities.length == 1
                                  ? ' activiteit'
                                  : ' activiteiten'),
                        ),
                        trailing: IconButton(
                          tooltip: 'Dagindeling verwijderen',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (confirmContext) => AlertDialog(
                                title: const Text('Dagindeling verwijderen?'),
                                content: Text(
                                  'Wil je ‘' + template.name + '’ verwijderen?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, false),
                                    child: const Text('Annuleren'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, true),
                                    child: const Text('Verwijderen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await widget.controller.deleteTemplate(template.id);
                              setDialogState(() {});
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      ),
    );
  }
}
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.speechRate, required this.toggle, required this.edit, required this.delete, required this.reorderHandle});
  final DayActivity activity;
  final double speechRate;
  final VoidCallback toggle;
  final VoidCallback edit;
  final VoidCallback delete;
  final Widget reorderHandle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 55, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(12)), child: Text(activity.time, textAlign: TextAlign.center, style: const TextStyle(color: _green, fontWeight: FontWeight.w800, fontSize: 12))),
            const SizedBox(width: 13),
            Expanded(child: InkWell(
              onTap: edit,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text(activity.symbol, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 9),
                  Expanded(child: Text(activity.title, style: TextStyle(color: activity.done ? _muted : _ink, fontSize: 16, fontWeight: FontWeight.w700, decoration: activity.done ? TextDecoration.lineThrough : null))),
                ]),
                if (activity.photoPath.isNotEmpty && File(activity.photoPath).existsSync()) ...[
                  const SizedBox(height: 9),
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(activity.photoPath), height: 110, width: 150, fit: BoxFit.cover)),
                ],
                if (activity.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(activity.note, style: const TextStyle(color: _muted, fontSize: 13))),
                const SizedBox(height: 7),
                const Text('Tik om de vijf vragen te bekijken', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            )),
            reorderHandle,
            SpeakButton(text: activity.title + '. ' + activity.time + '. Wie: ' + activity.who + '. Wat: ' + activity.what + '. Waar: ' + activity.where + '. Hoe: ' + activity.how + '.', speechRate: speechRate),
            IconButton(tooltip: activity.done ? 'Niet afgerond' : 'Markeer als afgerond', onPressed: toggle, icon: Icon(activity.done ? Icons.check_circle : Icons.circle_outlined, color: activity.done ? _green : _muted)),
            PopupMenuButton<String>(
              tooltip: 'Meer opties',
              onSelected: (choice) { if (choice == 'edit') edit(); if (choice == 'delete') delete(); },
              itemBuilder: (context) => const [PopupMenuItem(value: 'edit', child: Text('Bewerken')), PopupMenuItem(value: 'delete', child: Text('Verwijderen'))],
            ),
          ]),
        ),
      );
}

Future<void> editActivity(BuildContext context, MoodPressController controller, {DayActivity? existing}) async {
  final result = await showDialog<DayActivity>(context: context, builder: (context) => ActivityEditor(existing: existing));
  if (result != null) await controller.saveActivity(result);
}

Future<void> confirmDelete(BuildContext context, MoodPressController controller, DayActivity activity) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Activiteit verwijderen?'),
      content: Text('Wil je "' + activity.title + '" uit jouw dagplan halen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuleren')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verwijderen')),
      ],
    ),
  );
  if (result == true) await controller.deleteActivity(activity.id);
}

class ActivityEditor extends StatefulWidget {
  const ActivityEditor({super.key, this.existing});
  final DayActivity? existing;

  @override
  State<ActivityEditor> createState() => _ActivityEditorState();
}

class _ActivityEditorState extends State<ActivityEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController time;
  late final TextEditingController who;
  late final TextEditingController what;
  late final TextEditingController where;
  late final TextEditingController how;
  late final TextEditingController note;
  String symbol = '📌';
  String photoPath = '';

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    title = TextEditingController(text: item?.title ?? '');
    time = TextEditingController(text: item?.time ?? '09:00');
    who = TextEditingController(text: item?.who ?? 'Ik');
    what = TextEditingController(text: item?.what ?? '');
    where = TextEditingController(text: item?.where ?? '');
    how = TextEditingController(text: item?.how ?? '');
    note = TextEditingController(text: item?.note ?? '');
    symbol = item?.symbol ?? '📌';
    photoPath = item?.photoPath ?? '';
  }

  @override
  void dispose() {
    title.dispose(); time.dispose(); who.dispose(); what.dispose(); where.dispose(); how.dispose(); note.dispose();
    super.dispose();
  }

  Widget field(TextEditingController controller, String label, String hint, {bool required = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          controller: controller,
          maxLines: lines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: required ? (value) => value == null || value.trim().isEmpty ? 'Vul een naam in.' : null : null,
        ),
      );

  Future<void> choosePhoto() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return;
      final file = picked.first;
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) return;
      final directory = await getApplicationSupportDirectory();
      final imageDirectory = Directory('${directory.path}${Platform.pathSeparator}activity_images');
      await imageDirectory.create(recursive: true);
      final extension = (file.extension ?? 'jpg').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final safeName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
      final saved = await File(sourcePath).copy(
        '${imageDirectory.path}${Platform.pathSeparator}$safeName',
      );
      if (!mounted) return;
      setState(() => photoPath = saved.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('De foto kon niet worden toegevoegd. Probeer een andere afbeelding.')));
    }
  }

  void save() {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.existing;
    Navigator.pop(context, DayActivity(
      id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.text.trim(),
      time: time.text.trim().isEmpty ? '09:00' : time.text.trim(),
      who: who.text.trim(),
      what: what.text.trim(),
      where: where.text.trim(),
      how: how.text.trim(),
      note: note.text.trim(),
      symbol: symbol,
      photoPath: photoPath,
      done: old?.done ?? false,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Nieuwe activiteit' : 'Activiteit aanpassen'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Maak de uitleg kort en duidelijk. Je kunt dit samen invullen.', style: TextStyle(color: _muted)),
                const SizedBox(height: 12),
                const SizedBox(height: 8),
                const Text('Pictogram', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: symbol,
                  decoration: const InputDecoration(labelText: 'Kies een herkenbaar plaatje'),
                  items: const [
                    DropdownMenuItem(value: '📌', child: Text('📌  Algemeen')),
                    DropdownMenuItem(value: '🍽️', child: Text('🍽️  Eten')),
                    DropdownMenuItem(value: '🚿', child: Text('🚿  Douchen')),
                    DropdownMenuItem(value: '👕', child: Text('👕  Aankleden')),
                    DropdownMenuItem(value: '🏠', child: Text('🏠  Thuis')),
                    DropdownMenuItem(value: '🚶', child: Text('🚶  Wandelen')),
                    DropdownMenuItem(value: '🚌', child: Text('🚌  Reizen')),
                    DropdownMenuItem(value: '💊', child: Text('💊  Medicatie')),
                    DropdownMenuItem(value: '🧹', child: Text('🧹  Opruimen')),
                    DropdownMenuItem(value: '🎮', child: Text('🎮  Vrije tijd')),
                    DropdownMenuItem(value: '🛒', child: Text('🛒  Boodschappen')),
                    DropdownMenuItem(value: '😴', child: Text('😴  Rust')),
                  ],
                  onChanged: (value) { if (value != null) setState(() => symbol = value); },
                ),
                const SizedBox(height: 12),
                const Text('Eigen foto (optioneel)', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                const Text('Kies een foto die jou helpt de activiteit te herkennen. De foto blijft op dit apparaat.', style: TextStyle(color: _muted, fontSize: 13)),
                if (photoPath.isNotEmpty && File(photoPath).existsSync()) ...[
                  const SizedBox(height: 9),
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(photoPath), height: 130, width: double.infinity, fit: BoxFit.cover)),
                ],
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: choosePhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Foto kiezen')),
                  if (photoPath.isNotEmpty) TextButton.icon(onPressed: () => setState(() => photoPath = ''), icon: const Icon(Icons.close), label: const Text('Foto weghalen')),
                ]),
                field(title, 'Naam van de activiteit', 'Bijvoorbeeld: naar de winkel', required: true),
                field(time, 'Wanneer?', 'Bijvoorbeeld: 10:30'),
                field(who, 'Wie?', 'Wie is erbij?'),
                field(what, 'Wat?', 'Wat ga je doen?'),
                field(where, 'Waar?', 'Waar gebeurt het?'),
                field(how, 'Hoe?', 'Welke kleine stappen helpen?'),
                field(note, 'Extra uitleg (optioneel)', 'Wat is fijn om vooraf te weten?', lines: 2),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(onPressed: save, child: const Text('Opslaan')),
        ],
      );
}

class CalmPage extends StatefulWidget {
  const CalmPage({super.key});
  @override
  State<CalmPage> createState() => _CalmPageState();
}

class CalmStep {
  const CalmStep({required this.title, required this.description, required this.icon});
  final String title;
  final String description;
  final IconData icon;
}

class _CalmPageState extends State<CalmPage> {
  int step = 0;
  static const steps = [
    CalmStep(title: 'Voel de grond', description: 'Zet je voeten neer. Voel waar je voeten de grond raken.', icon: Icons.place_outlined),
    CalmStep(title: 'Kijk rustig om je heen', description: 'Noem voor jezelf drie dingen die je ziet. Je hoeft niets hardop te zeggen.', icon: Icons.remove_red_eye_outlined),
    CalmStep(title: 'Kies één kleine stap', description: 'Wat heb je nu nodig? Rust, hulp of verdergaan?', icon: Icons.spa_outlined),
  ];

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Even rust',
        subtitle: 'Een rustig moment. Je hoeft niets goed te doen.',
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(23)),
              child: Column(children: [
                CircleAvatar(radius: 33, backgroundColor: Colors.white, child: Icon(steps[step].icon, color: _green, size: 29)),
                const SizedBox(height: 18),
                Text('STAP ' + (step + 1).toString() + ' VAN 3', style: const TextStyle(color: _green, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                const SizedBox(height: 11),
                Text(steps[step].title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(steps[step].description, textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 16, height: 1.5)),
                const SizedBox(height: 23),
                Row(children: List.generate(3, (index) => Expanded(child: Container(height: 5, margin: EdgeInsets.only(right: index == 2 ? 0 : 7), decoration: BoxDecoration(color: index <= step ? _green : _line, borderRadius: BorderRadius.circular(5)))))),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: step == 0 ? null : () => setState(() => step--), child: const Text('Vorige'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(onPressed: () => setState(() => step = step == 2 ? 0 : step + 1), child: Text(step == 2 ? 'Opnieuw' : 'Volgende'))),
                ]),
                TextButton(onPressed: () => setState(() => step = 0), child: const Text('Stop met deze oefening')),
              ]),
            ),
            const SizedBox(height: 14),
            const Card(child: Padding(padding: EdgeInsets.all(17), child: Text('Je mag een stap overslaan of stoppen. Als dit niet prettig voelt, kies dan iets anders dat voor jou veilig en vertrouwd is.', style: TextStyle(color: _muted, height: 1.45)))),
          ]),
        )),
      );
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Mijn steun',
        subtitle: 'Zet hier wat jou helpt als een dag moeilijk voelt.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: _sand, borderRadius: BorderRadius.circular(18)), child: const Text('Je hoeft het niet alleen te doen. Je mag om hulp vragen en je eigen tempo volgen.', style: TextStyle(color: _ink, fontWeight: FontWeight.w600))),
          const SizedBox(height: 18),
          SupportCard(title: 'Als ik vastloop', value: controller.support['help'] ?? '', icon: Icons.pan_tool_outlined, edit: () => editSupport(context, controller, 'help', 'Als ik vastloop')),
          const SizedBox(height: 10),
          SupportCard(title: 'Een plek waar ik rust vind', value: controller.support['place'] ?? '', icon: Icons.home_outlined, edit: () => editSupport(context, controller, 'place', 'Een plek waar ik rust vind')),
          const SizedBox(height: 10),
          SupportCard(title: 'Iemand die mij kan helpen', value: (controller.support['person'] ?? '').isEmpty ? 'Nog niet ingevuld' : controller.support['person']!, icon: Icons.people_outline, edit: () => editSupport(context, controller, 'person', 'Iemand die mij kan helpen')),
          const SizedBox(height: 22),
          const Text('Wat kun je doen als het te veel wordt?', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const SimpleStep(number: '1', text: 'Ga naar een plek die voor jou rustig en veilig voelt.'),
          const SimpleStep(number: '2', text: 'Kies één ding. De rest kan wachten.'),
          const SimpleStep(number: '3', text: 'Vraag iemand die je vertrouwt om hulp.'),
          const SizedBox(height: 13),
          const Text('Bij direct gevaar: bel 112 of vraag iemand in de buurt om direct hulp te halen.', style: TextStyle(color: _muted, fontSize: 12, height: 1.45)),
          if (controller.storageNotice != null) Padding(padding: const EdgeInsets.only(top: 12), child: StorageNotice(message: controller.storageNotice!)),
          const SizedBox(height: 18),
          const SmallDisclaimer(),
        ]),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Instellingen',
        subtitle: 'Pas MoodPress aan op wat prettig werkt voor jou.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.text_fields_rounded, color: _green),
                  SizedBox(width: 10),
                  Text('Tekstgrootte', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Kies tekst die prettig leesbaar is.', style: TextStyle(color: _muted)),
                const SizedBox(height: 15),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1.0, label: Text('Normaal')),
                    ButtonSegment(value: 1.15, label: Text('Groter')),
                    ButtonSegment(value: 1.3, label: Text('Extra groot')),
                  ],
                  selected: {controller.preferences.textScale},
                  onSelectionChanged: (values) => controller.setTextScale(values.first),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.motion_photos_off_outlined, color: _green),
                  SizedBox(width: 10),
                  Expanded(child: Text('Minder beweging', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 5),
                const Text('Schakel bewegende overgangen en animaties zoveel mogelijk uit als dat rustiger voelt.', style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rustige weergave'),
                  subtitle: const Text('Minder animaties in de app'),
                  value: controller.preferences.reduceMotion,
                  onChanged: controller.setReduceMotion,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.notifications_none_rounded, color: _green),
                  SizedBox(width: 10),
                  Text('Herinneringen', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Krijg op het geplande tijdstip een rustige melding zolang MoodPress open is. Je kunt dit altijd uitzetten.', style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Herinneringen in de app'),
                  subtitle: const Text('Staat standaard uit'),
                  value: controller.preferences.inAppRemindersEnabled,
                  onChanged: controller.setInAppRemindersEnabled,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.volume_up_outlined, color: _green),
                  SizedBox(width: 10),
                  Text('Voorleessnelheid', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Maak het voorlezen langzamer of sneller.', style: TextStyle(color: _muted)),
                Slider(
                  value: controller.preferences.speechRate,
                  min: 0.3,
                  max: 0.6,
                  divisions: 6,
                  label: controller.preferences.speechRate.toStringAsFixed(2),
                  onChanged: controller.setSpeechRate,
                ),
                const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Langzaam', style: TextStyle(color: _muted, fontSize: 12)),
                  Text('Sneller', style: TextStyle(color: _muted, fontSize: 12)),
                ]),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => SpeakButtonPreview.play(context, controller.preferences.speechRate),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Luister naar een voorbeeld'),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Jouw instellingen', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                const Text('Je voorkeuren worden op dit apparaat bewaard. Ze worden niet naar een account of cloud verstuurd.', style: TextStyle(color: _muted, height: 1.45)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.resetPreferences,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Herstel standaardinstellingen'),
                ),
              ]),
            ),
          ),
          if (controller.storageNotice != null) ...[
            const SizedBox(height: 12),
            StorageNotice(message: controller.storageNotice!),
          ],
          const SizedBox(height: 18),
          const SmallDisclaimer(),
        ]),
      );
}

class SpeakButtonPreview {
  static Future<void> play(BuildContext context, double rate) async {
    final messenger = ScaffoldMessenger.of(context);
    final tts = FlutterTts();
    try {
      await tts.setLanguage('nl-NL');
      await tts.setSpeechRate(rate);
      await tts.setPitch(1.0);
      await tts.awaitSpeakCompletion(true);
      await tts.speak('Dit is een voorbeeld. Je kunt de voorleessnelheid aanpassen aan wat prettig is.');
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Voorlezen is op dit apparaat niet beschikbaar.')));
    } finally {
      await tts.stop();
    }
  }
}

class SupportCard extends StatelessWidget {
  const SupportCard({super.key, required this.title, required this.value, required this.icon, required this.edit});
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback edit;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _green)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value.isEmpty ? 'Nog niet ingevuld' : value, style: const TextStyle(color: _muted, fontSize: 13, height: 1.35)),
          ])),
          IconButton(tooltip: 'Aanpassen', onPressed: edit, icon: const Icon(Icons.edit_outlined, color: _green)),
        ]),
      ));
}

Future<void> editSupport(BuildContext context, MoodPressController controller, String key, String title) async {
  final field = TextEditingController(text: controller.support[key] ?? '');
  final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 450, child: TextField(controller: field, autofocus: true, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Schrijf op wat jou helpt.'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Opslaan')),
        ],
      ));
  field.dispose();
  if (value != null) await controller.saveSupport(key, value);
}

class SimpleStep extends StatelessWidget {
  const SimpleStep({super.key, required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 13, backgroundColor: _greenPale, child: Text(number, style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w800))),
        const SizedBox(width: 11),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(text, style: const TextStyle(color: _ink)))),
      ]));
}

class StorageNotice extends StatelessWidget {
  const StorageNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFFFF2E6), borderRadius: BorderRadius.circular(13)), child: Text(message, style: const TextStyle(color: _ink, fontSize: 12, height: 1.4)));
}

class SmallDisclaimer extends StatelessWidget {
  const SmallDisclaimer({super.key});

  @override
  Widget build(BuildContext context) => const Text(
        'MoodPress helpt bij dagstructuur en overzicht. De app stelt geen diagnose en vervangt geen professionele zorg.',
        style: TextStyle(color: _muted, fontSize: 11, height: 1.45),
      );
}

class SpeakButton extends StatefulWidget {
  const SpeakButton({super.key, required this.text, this.speechRate = 0.42});
  final String text;
  final double speechRate;

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  final FlutterTts _tts = FlutterTts();
  bool speaking = false;

  Future<void> _toggle() async {
    try {
      if (speaking) {
        await _tts.stop();
        if (mounted) setState(() => speaking = false);
        return;
      }
      await _tts.setLanguage('nl-NL');
      await _tts.setSpeechRate(widget.speechRate);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      if (mounted) setState(() => speaking = true);
      await _tts.speak(widget.text);
      if (mounted) setState(() => speaking = false);
    } catch (_) {
      if (mounted) setState(() => speaking = false);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: speaking ? 'Stop voorlezen' : 'Lees voor',
        onPressed: _toggle,
        icon: Icon(speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined, color: _green),
      );
}
).hasMatch(entry.key) ||
              entry.value is! Map<String, dynamic>) {
            throw FormatException('Een foto in deze back-up is niet geldig.');
          }
          final photo = entry.value as Map<String, dynamic>;
          final extension = photo['extension'];
          if (extension is! String ||
              !const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'}
                  .contains(extension)) {
            throw FormatException('Een fotoformaat in deze back-up wordt niet ondersteund.');
          }
          final encoded = photo['data'];
          if (encoded is! String) {
            throw FormatException('Een foto in deze back-up is niet compleet.');
          }
          final imageBytes = base64Decode(encoded);
          totalPhotoBytes += imageBytes.length;
          if (totalPhotoBytes > _maxBackupPhotoBytes) {
            throw FormatException('De foto’s in deze back-up zijn te groot.');
          }

          photoIndex += 1;
          final file = File(
            imageDirectory.path + Platform.pathSeparator +
            'restored_' + DateTime.now().microsecondsSinceEpoch.toString() +
            '_' + photoIndex.toString() + '.' + extension,
          );
          await file.writeAsBytes(imageBytes, flush: true);
          savedPhotoFiles.add(file);
          photoPaths[entry.key] = file.path;
        }
      }

      List<DayActivity> restoreActivities(dynamic rawActivities) {
        if (rawActivities is! List) {
          throw FormatException('Een activiteitenlijst in de back-up is niet geldig.');
        }
        return rawActivities.map((raw) {
          if (raw is! Map<String, dynamic>) {
            throw FormatException('Een activiteit in de back-up is niet geldig.');
          }
          final values = Map<String, dynamic>.from(raw);
          final photoId = values.remove('photoId');
          values['photoPath'] = photoId is String
              ? (photoPaths[photoId] ?? '')
              : '';
          return DayActivity.fromJson(values);
        }).toList();
      }

      DayTemplate restoreTemplate(dynamic raw) {
        if (raw is! Map<String, dynamic>) {
          throw FormatException('Een dagindeling in de back-up is niet geldig.');
        }
        return DayTemplate(
          id: raw['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
          name: raw['name'] as String? ?? 'Dagindeling',
          activities: restoreActivities(raw['activities']),
        );
      }

      final rawPlans = document['dayPlans'];
      if (rawPlans is! Map<String, dynamic>) {
        throw FormatException('De dagplanning in deze back-up is niet geldig.');
      }
      final restoredPlans = <String, List<DayActivity>>{};
      for (final entry in rawPlans.entries) {
        final date = DateTime.tryParse(entry.key);
        if (date == null || _dateKey(date) != entry.key) {
          throw FormatException('Een datum in de dagplanning is niet geldig.');
        }
        restoredPlans[entry.key] = restoreActivities(entry.value);
      }

      final rawTemplates = document['templates'];
      if (rawTemplates is! List) {
        throw FormatException('De dagindelingen in deze back-up zijn niet geldig.');
      }
      final restoredTemplates = rawTemplates.map(restoreTemplate).toList();

      final rawRoutine = document['weeklyRoutine'];
      if (rawRoutine is! Map<String, dynamic>) {
        throw FormatException('Het vaste weekritme in deze back-up is niet geldig.');
      }
      final routineDays = <int, DayTemplate>{};
      for (final entry in rawRoutine.entries) {
        final weekday = int.tryParse(entry.key);
        if (weekday == null || weekday < 1 || weekday > 7) {
          throw FormatException('Een weekdag in de back-up is niet geldig.');
        }
        routineDays[weekday] = restoreTemplate(entry.value);
      }
      final restoredRoutine = WeeklyRoutine(days: routineDays);

      final rawSupport = document['support'];
      if (rawSupport is! Map<String, dynamic>) {
        throw FormatException('Het steunplan in deze back-up is niet geldig.');
      }
      final restoredSupport = <String, String>{
        'help': rawSupport['help']?.toString() ?? '',
        'place': rawSupport['place']?.toString() ?? '',
        'person': rawSupport['person']?.toString() ?? '',
      };

      final rawPreferences = document['preferences'];
      if (rawPreferences is! Map<String, dynamic>) {
        throw FormatException('De instellingen in deze back-up zijn niet geldig.');
      }
      final restoredPreferences = MoodPressPreferences.fromJson(rawPreferences);

      final nextStorage = <String, String>{
        _dayPlansKey: jsonEncode({
          for (final entry in restoredPlans.entries)
            entry.key: entry.value.map((item) => item.toJson()).toList(),
        }),
        _supportKey: jsonEncode(restoredSupport),
        _preferencesKey: jsonEncode(restoredPreferences.toJson()),
        _templatesKey: jsonEncode(
          restoredTemplates.map((item) => item.toJson()).toList(),
        ),
        _weeklyRoutineKey: jsonEncode(restoredRoutine.toJson()),
      };
      final previousStorage = <String, String?>{};
      for (final key in nextStorage.keys) {
        previousStorage[key] = await _storage.read(key: key);
      }

      try {
        for (final entry in nextStorage.entries) {
          await _storage.write(key: entry.key, value: entry.value);
        }
      } catch (_) {
        for (final entry in previousStorage.entries) {
          try {
            if (entry.value == null) {
              await _storage.delete(key: entry.key);
            } else {
              await _storage.write(key: entry.key, value: entry.value!);
            }
          } catch (_) {
            // Best-effort rollback; the original storage error is reported below.
          }
        }
        rethrow;
      }

      _plansByDate
        ..clear()
        ..addAll(restoredPlans);
      support = restoredSupport;
      preferences = restoredPreferences;
      templates = restoredTemplates;
      weeklyRoutine = restoredRoutine;
      storageNotice = null;
      notifyListeners();
    } catch (_) {
      for (final file in savedPhotoFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Ignore cleanup failures and keep the original import error.
        }
      }
      rethrow;
    }
  }

  Future<void> setTextScale(double value) async {
    preferences = MoodPressPreferences(
      textScale: value.clamp(1.0, 1.4).toDouble(),
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setSpeechRate(double value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: value.clamp(0.3, 0.6).toDouble(),
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: value,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setInAppRemindersEnabled(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: value,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> resetPreferences() async {
    preferences = const MoodPressPreferences();
    await _savePreferences();
    notifyListeners();
  }

  Future<void> _savePreferences() async {
    try {
      await _storage.write(
        key: _preferencesKey,
        value: jsonEncode(preferences.toJson()),
      );
    } catch (_) {
      storageNotice = 'Je instellingen konden niet veilig worden opgeslagen.';
    }
  }

  void setFeeling(String value) {
    // This voluntary check-in is temporary and is never stored as a health record.
    feeling = value;
    notifyListeners();
  }
}

class MoodPressApp extends StatelessWidget {
  const MoodPressApp({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.light)
        .copyWith(primary: _green, onPrimary: Colors.white, onSurface: _ink);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        title: 'MoodPress',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(systemScale * controller.preferences.textScale),
              disableAnimations: controller.preferences.reduceMotion,
            ),
            child: child!,
          );
        },
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: _paper,
          fontFamily: 'Arial',
          textTheme: const TextTheme(
            headlineLarge: TextStyle(color: _ink, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.6),
            headlineMedium: TextStyle(color: _ink, fontSize: 25, fontWeight: FontWeight.w700),
            titleLarge: TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w700),
            bodyLarge: TextStyle(color: _ink, fontSize: 16, height: 1.45),
            bodyMedium: TextStyle(color: _muted, fontSize: 14, height: 1.45),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFFAFAF7),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          ),
        ),
        home: controller.ready ? MoodPressShell(controller: controller) : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}

class MoodPressShell extends StatefulWidget {
  const MoodPressShell({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<MoodPressShell> createState() => _MoodPressShellState();
}

class _MoodPressShellState extends State<MoodPressShell> {
  int selected = 0;
  Timer? _reminderTimer;
  final Set<String> _shownReminders = <String>{};

  @override
  void initState() {
    super.initState();
    _reminderTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkInAppReminders(),
    );
  }

  void _checkInAppReminders() {
    if (!mounted || !widget.controller.preferences.inAppRemindersEnabled) return;
    final now = DateTime.now();
    final dateKey = _dateKey(now);
    for (final activity in widget.controller.activitiesFor(now)) {
      if (!isActivityDueAt(activity, now)) continue;
      final reminderKey = '$dateKey-${activity.id}';
      if (!_shownReminders.add(reminderKey)) continue;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Rustige herinnering: ${activity.title}. Als het nu niet uitkomt, mag je het overslaan.'),
          duration: const Duration(seconds: 8),
        ));
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }
  static const labels = ['Vandaag', 'Planning', 'Even rust', 'Mijn steun', 'Instellingen'];
  static const icons = [Icons.wb_sunny_outlined, Icons.calendar_month_outlined, Icons.spa_outlined, Icons.favorite_border, Icons.tune_rounded];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        final pages = [
          TodayPage(controller: widget.controller, openPlan: () => setState(() => selected = 1)),
          PlanningPage(controller: widget.controller),
          const CalmPage(),
          SupportPage(controller: widget.controller),
          SettingsPage(controller: widget.controller),
        ];
        return Scaffold(
          body: Row(children: [
            if (desktop)
              NavigationRail(
                backgroundColor: const Color(0xFFFBFBF8),
                selectedIndex: selected,
                onDestinationSelected: (value) => setState(() => selected = value),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(padding: EdgeInsets.fromLTRB(4, 22, 4, 28), child: BrandMark()),
                destinations: List.generate(labels.length, (index) => NavigationRailDestination(icon: Icon(icons[index]), label: Text(labels[index]))),
              ),
            Expanded(child: IndexedStack(index: selected, children: pages)),
          ]),
          bottomNavigationBar: desktop ? null : NavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (value) => setState(() => selected = value),
            destinations: List.generate(labels.length, (index) => NavigationDestination(icon: Icon(icons[index]), label: labels[index])),
          ),
        );
      });
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.waves_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 10),
        const Text('moodpress', style: TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
      ]);
}

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child, this.title, this.subtitle, this.action});
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 38),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) ...[
                LayoutBuilder(builder: (context, constraints) {
                  final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title!, style: Theme.of(context).textTheme.headlineMedium),
                    if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle!)),
                  ]);
                  if (action == null) return heading;
                  if (constraints.maxWidth < 580) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const SizedBox(height: 13), action!]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: heading), action!]);
                }),
                const SizedBox(height: 24),
              ],
              child,
            ]),
          ),
        ),
      );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.controller, required this.openPlan});
  final MoodPressController controller;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Goedemorgen' : now.hour < 18 ? 'Goedemiddag' : 'Goedenavond';
    final todayActivities = controller.activitiesFor(now);
    final upcoming = todayActivities.where((item) => !item.done).toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    final completedToday = todayActivities.where((item) => item.done).length;
    final progressToday = todayActivities.isEmpty ? 0.0 : completedToday / todayActivities.length;

    return PageFrame(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const BrandMark(),
      const SizedBox(height: 28),
      Text(greeting + '.', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text('We doen het rustig aan. Eén ding tegelijk.', style: TextStyle(color: _muted, fontSize: 16)),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, constraints) {
        final nextCard = NextStepCard(activity: next, openPlan: openPlan);
        final progressCard = ProgressCard(done: completedToday, total: todayActivities.length, progress: progressToday, openPlan: openPlan);
        if (constraints.maxWidth > 650) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: nextCard), const SizedBox(width: 14), Expanded(flex: 4, child: progressCard)]);
        return Column(children: [nextCard, const SizedBox(height: 14), progressCard]);
      }),
      const SizedBox(height: 28),
      Text('Hoe is het nu met je?', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Kies wat bij dit moment past. Je hoeft niets uit te leggen.', style: TextStyle(color: _muted)),
      const SizedBox(height: 14),
      Wrap(spacing: 9, runSpacing: 9, children: [
        FeelingChoice(label: 'Rustig', emoji: '🙂', selected: controller.feeling == 'Rustig', onTap: () => controller.setFeeling('Rustig')),
        FeelingChoice(label: 'Wat onrustig', emoji: '😐', selected: controller.feeling == 'Wat onrustig', onTap: () => controller.setFeeling('Wat onrustig')),
        FeelingChoice(label: 'Een vol hoofd', emoji: '😣', selected: controller.feeling == 'Een vol hoofd', onTap: () => controller.setFeeling('Een vol hoofd')),
      ]),
      if (controller.feeling != null) const Padding(padding: EdgeInsets.only(top: 13), child: Text('Dank je. Je hoeft hier verder niets mee te doen.', style: TextStyle(color: _muted, fontSize: 13))),
      if (controller.storageNotice != null) Padding(padding: const EdgeInsets.only(top: 16), child: StorageNotice(message: controller.storageNotice!)),
      const SizedBox(height: 22),
      const SmallDisclaimer(),
    ]));
  }
}

class NextStepCard extends StatelessWidget {
  const NextStepCard({super.key, required this.activity, required this.openPlan});
  final DayActivity? activity;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(23),
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(23)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('DIT IS JE VOLGENDE STAP', style: TextStyle(color: Color(0xFFE1ECE6), fontSize: 10, letterSpacing: 1.35, fontWeight: FontWeight.w800)),
          const SizedBox(height: 17),
          Text(activity?.title ?? 'Je dag is klaar', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(activity == null ? 'Goed gedaan. Neem de tijd voor jezelf.' : activity!.time + ' uur · ' + (activity!.note.isEmpty ? 'Je kunt dit stap voor stap doen.' : activity!.note), style: const TextStyle(color: Color(0xFFE9F0EB), height: 1.45)),
          const SizedBox(height: 21),
          FilledButton.icon(onPressed: openPlan, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _green), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Bekijk mijn planning')),
        ]),
      );
}

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.done, required this.total, required this.progress, required this.openPlan});
  final int done;
  final int total;
  final double progress;
  final VoidCallback openPlan;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(21),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('JOUW DAG', style: TextStyle(fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: _muted)),
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(width: 70, height: 70, child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: progress, strokeWidth: 7, backgroundColor: _greenPale, color: _green)),
                Text((progress * 100).round().toString() + '%', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
              ])),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(done.toString() + ' van ' + total.toString() + ' gedaan', style: const TextStyle(fontSize: 15, color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Elke stap telt. Ook een kleine stap.', style: TextStyle(color: _muted, fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 12),
            TextButton.icon(onPressed: openPlan, icon: const Icon(Icons.list_alt_outlined), label: const Text('Mijn weekplanning')),
          ]),
        ),
      );
}

class FeelingChoice extends StatelessWidget {
  const FeelingChoice({super.key, required this.label, required this.emoji, required this.selected, required this.onTap});
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? _greenPale : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? _green : _line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(emoji, style: const TextStyle(fontSize: 18)), const SizedBox(width: 8), Text(label, style: TextStyle(color: _ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))]),
          ),
        ),
      );
}

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  bool _showWeek = true;
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayFor(DateTime.now());
  }

  DateTime _mondayFor(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);

  String _rangeLabel() {
    final lastDay = _weekStart.add(const Duration(days: 6));
    return _formatDutchDate(_weekStart) + ' - ' +
        _formatDutchDate(lastDay) + ' ' + lastDay.year.toString();
  }

  void _openDay(DateTime date) {
    widget.controller.selectDate(date);
    setState(() => _showWeek = false);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Mijn planning',
        subtitle: _showWeek
            ? 'Een rustig overzicht van maandag tot en met zondag.'
            : 'Bekijk één dag tegelijk. Je kunt alles aanpassen.',
        action: _showWeek
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showWeeklyRoutineManager(context),
                    icon: const Icon(Icons.repeat_rounded),
                    label: const Text('Vast weekritme'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showTemplateManager(context),
                    icon: const Icon(Icons.library_books_outlined),
                    label: const Text('Dagindelingen'),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: () => editActivity(context, widget.controller),
                icon: const Icon(Icons.add),
                label: const Text('Activiteit toevoegen'),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Weekoverzicht')),
                ButtonSegment(value: false, label: Text('Dagplan')),
              ],
              selected: {_showWeek},
              onSelectionChanged: (values) =>
                  setState(() => _showWeek = values.first),
            ),
            const SizedBox(height: 18),
            if (_showWeek) _buildWeek(context) else _buildDay(context),
          ],
        ),
      );

  Widget _buildWeek(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Vorige week',
              onPressed: () => setState(
                () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _rangeLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Volgende week',
              onPressed: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var offset = 0; offset < 7; offset++)
          _buildWeekDayCard(
            context,
            _weekStart.add(Duration(days: offset)),
          ),
        if (widget.controller.weeklyRoutine.days.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 8),
            child: Card(
              color: _greenPale,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vaste dagen invullen',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.controller.routinesInWeek(_weekStart).toString() +
                          ' lege dagen kunnen worden gevuld. Bestaande plannen blijven staan.',
                      style: const TextStyle(color: _muted, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: widget.controller.routinesInWeek(_weekStart) == 0
                          ? null
                          : () => _applyWeeklyRoutine(context),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Vul lege dagen met weekritme'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.controller.templates.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: _green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Je hebt nog geen vaste dagindeling. Open een dagplan en kies ‘Bewaar als dagindeling’ om een sjabloon te maken.',
                      style: TextStyle(color: _ink, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              widget.controller.templates.length.toString() +
                  (widget.controller.templates.length == 1
                      ? ' dagindeling beschikbaar'
                      : ' dagindelingen beschikbaar'),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => setState(() => _weekStart = _mondayFor(DateTime.now())),
          icon: const Icon(Icons.today_outlined),
          label: const Text('Ga naar deze week'),
        ),
      ],
    );
  }

  Widget _buildWeekDayCard(BuildContext context, DateTime date) {
    final items = widget.controller.activitiesFor(date);
    final completed = items.where((item) => item.done).length;
    final summary = items.isEmpty
        ? 'Nog geen dagplan'
        : items.length.toString() +
            (items.length == 1 ? ' activiteit · ' : ' activiteiten · ') +
            completed.toString() + ' afgerond';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _greenPale,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  date.day.toString(),
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDutchWeekday(date),
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (widget.controller.weeklyRoutine.forWeekday(date.weekday) != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Text(
                          'Vaste indeling beschikbaar',
                          style: TextStyle(
                            color: _green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      summary,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openDay(date),
                child: const Text('Open dag'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Dagindeling toepassen',
                enabled: widget.controller.templates.isNotEmpty,
                icon: const Icon(Icons.copy_all_outlined, color: _green),
                onSelected: (templateId) =>
                    _applyTemplateToDate(context, date, templateId),
                itemBuilder: (context) => widget.controller.templates
                    .map(
                      (template) => PopupMenuItem<String>(
                        value: template.id,
                        child: Text(template.name),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDay(BuildContext context) {
    final date = widget.controller.selectedDate;
    final items = widget.controller.activities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Vorige dag',
                  onPressed: () =>
                      widget.controller.selectDate(date.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatDutchWeekday(date),
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _formatDutchDate(date) + ' ' + date.year.toString(),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Volgende dag',
                  onPressed: () =>
                      widget.controller.selectDate(date.add(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 13),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: _sand,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Text(
            'Kijk alleen naar de eerstvolgende activiteit. De rest komt later.',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 15),
        if (items.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: items.length,
            onReorder: widget.controller.reorderActivities,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: 11),
                child: ActivityCard(
                  activity: item,
                  speechRate: widget.controller.preferences.speechRate,
                  toggle: () => widget.controller.toggleActivity(item.id),
                  edit: () => editActivity(context, widget.controller, existing: item),
                  delete: () => confirmDelete(context, widget.controller, item),
                  reorderHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 12),
                      child: Icon(Icons.drag_handle_rounded, color: _muted),
                    ),
                  ),
                ),
              );
            },
          ),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'Voor deze dag staat nog niets gepland. Voeg een activiteit toe of gebruik een dagindeling.',
                style: TextStyle(color: _muted, height: 1.45),
              ),
            ),
          ),
        Wrap(
          spacing: 9,
          runSpacing: 7,
          children: [
            OutlinedButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => _saveTemplateFromDay(context, date),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Bewaar als dagindeling'),
            ),
            OutlinedButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => _saveWeeklyRoutineFromDay(context, date),
              icon: const Icon(Icons.repeat_rounded),
              label: const Text('Bewaar als vast weekritme'),
            ),
            TextButton.icon(
              onPressed: () => widget.controller.selectDate(DateTime.now()),
              icon: const Icon(Icons.today_outlined),
              label: const Text('Vandaag'),
            ),
          ],
        ),
        if (widget.controller.storageNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: StorageNotice(message: widget.controller.storageNotice!),
          ),
      ],
    );
  }

  Future<void> _saveTemplateFromDay(BuildContext context, DateTime date) async {
    final field = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dagindeling bewaren'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: field,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Naam van de dagindeling',
              hintText: 'Bijvoorbeeld: Werkdag',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, field.text.trim()),
            child: const Text('Bewaren'),
          ),
        ],
      ),
    );
    field.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await widget.controller.saveTemplateFromDate(name, date);
    }
  }

  Future<void> _applyTemplateToDate(
    BuildContext context,
    DateTime date,
    String templateId,
  ) async {
    if (widget.controller.activitiesFor(date).isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Dagindeling vervangen?'),
          content: const Text(
            'De activiteiten die nu op deze dag staan, worden vervangen door de gekozen dagindeling.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vervangen'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.controller.applyTemplateToDate(templateId, date);
  }

  Future<void> _saveWeeklyRoutineFromDay(
    BuildContext context,
    DateTime date,
  ) async {
    final existing = widget.controller.weeklyRoutine.forWeekday(date.weekday);
    if (existing != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Vaste dagindeling aanpassen?'),
          content: Text(
            'Er is al een vaste indeling voor ' +
                _formatDutchWeekday(date) +
                '. Wil je deze vervangen door het huidige dagplan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vervangen'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await widget.controller.saveWeeklyRoutineFromDate(date);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Vaste indeling voor ' + _formatDutchWeekday(date) + ' bewaard.',
        ),
      ),
    );
  }

  Future<void> _applyWeeklyRoutine(BuildContext context) async {
    final count = widget.controller.routinesInWeek(_weekStart);
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Weekritme toepassen?'),
        content: Text(
          'MoodPress vult ' + count.toString() +
              (count == 1 ? ' lege dag' : ' lege dagen') +
              ' met de vaste indeling. Bestaande dagplannen blijven ongewijzigd.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lege dagen invullen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final added = await widget.controller.applyWeeklyRoutineToWeek(_weekStart);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added.toString() +
              (added == 1 ? ' dag ingevuld.' : ' dagen ingevuld.'),
        ),
      ),
    );
  }

  Future<void> _showWeeklyRoutineManager(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final routines = widget.controller.weeklyRoutine.days.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          return AlertDialog(
            title: const Text('Mijn vaste weekritme'),
            content: SizedBox(
              width: 460,
              height: 320,
              child: routines.isEmpty
                  ? const Center(
                      child: Text(
                        'Er zijn nog geen vaste dagen. Open een dagplan en bewaar het als weekritme.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: routines.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = routines[index];
                        final weekday = entry.key;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _dutchWeekdays[weekday - 1][0].toUpperCase() +
                                _dutchWeekdays[weekday - 1].substring(1),
                          ),
                          subtitle: Text(
                            entry.value.activities.length.toString() +
                                (entry.value.activities.length == 1
                                    ? ' vaste activiteit'
                                    : ' vaste activiteiten'),
                          ),
                          trailing: IconButton(
                            tooltip: 'Vaste dag verwijderen',
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text('Vaste dag verwijderen?'),
                                  content: Text(
                                    'Wil je het vaste weekritme voor ' +
                                        _dutchWeekdays[weekday - 1] +
                                        ' verwijderen?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, false),
                                      child: const Text('Annuleren'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, true),
                                      child: const Text('Verwijderen'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await widget.controller.removeWeeklyRoutine(weekday);
                                setDialogState(() {});
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Sluiten'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTemplateManager(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mijn dagindelingen'),
          content: SizedBox(
            width: 460,
            height: 300,
            child: widget.controller.templates.isEmpty
                ? const Center(
                    child: Text(
                      'Je hebt nog geen dagindelingen bewaard.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: widget.controller.templates.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final template = widget.controller.templates[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(template.name),
                        subtitle: Text(
                          template.activities.length.toString() +
                              (template.activities.length == 1
                                  ? ' activiteit'
                                  : ' activiteiten'),
                        ),
                        trailing: IconButton(
                          tooltip: 'Dagindeling verwijderen',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (confirmContext) => AlertDialog(
                                title: const Text('Dagindeling verwijderen?'),
                                content: Text(
                                  'Wil je ‘' + template.name + '’ verwijderen?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, false),
                                    child: const Text('Annuleren'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, true),
                                    child: const Text('Verwijderen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await widget.controller.deleteTemplate(template.id);
                              setDialogState(() {});
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      ),
    );
  }
}
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.speechRate, required this.toggle, required this.edit, required this.delete, required this.reorderHandle});
  final DayActivity activity;
  final double speechRate;
  final VoidCallback toggle;
  final VoidCallback edit;
  final VoidCallback delete;
  final Widget reorderHandle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 55, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(12)), child: Text(activity.time, textAlign: TextAlign.center, style: const TextStyle(color: _green, fontWeight: FontWeight.w800, fontSize: 12))),
            const SizedBox(width: 13),
            Expanded(child: InkWell(
              onTap: edit,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text(activity.symbol, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 9),
                  Expanded(child: Text(activity.title, style: TextStyle(color: activity.done ? _muted : _ink, fontSize: 16, fontWeight: FontWeight.w700, decoration: activity.done ? TextDecoration.lineThrough : null))),
                ]),
                if (activity.photoPath.isNotEmpty && File(activity.photoPath).existsSync()) ...[
                  const SizedBox(height: 9),
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(activity.photoPath), height: 110, width: 150, fit: BoxFit.cover)),
                ],
                if (activity.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(activity.note, style: const TextStyle(color: _muted, fontSize: 13))),
                const SizedBox(height: 7),
                const Text('Tik om de vijf vragen te bekijken', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            )),
            reorderHandle,
            SpeakButton(text: activity.title + '. ' + activity.time + '. Wie: ' + activity.who + '. Wat: ' + activity.what + '. Waar: ' + activity.where + '. Hoe: ' + activity.how + '.', speechRate: speechRate),
            IconButton(tooltip: activity.done ? 'Niet afgerond' : 'Markeer als afgerond', onPressed: toggle, icon: Icon(activity.done ? Icons.check_circle : Icons.circle_outlined, color: activity.done ? _green : _muted)),
            PopupMenuButton<String>(
              tooltip: 'Meer opties',
              onSelected: (choice) { if (choice == 'edit') edit(); if (choice == 'delete') delete(); },
              itemBuilder: (context) => const [PopupMenuItem(value: 'edit', child: Text('Bewerken')), PopupMenuItem(value: 'delete', child: Text('Verwijderen'))],
            ),
          ]),
        ),
      );
}

Future<void> editActivity(BuildContext context, MoodPressController controller, {DayActivity? existing}) async {
  final result = await showDialog<DayActivity>(context: context, builder: (context) => ActivityEditor(existing: existing));
  if (result != null) await controller.saveActivity(result);
}

Future<void> confirmDelete(BuildContext context, MoodPressController controller, DayActivity activity) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Activiteit verwijderen?'),
      content: Text('Wil je "' + activity.title + '" uit jouw dagplan halen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuleren')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verwijderen')),
      ],
    ),
  );
  if (result == true) await controller.deleteActivity(activity.id);
}

class ActivityEditor extends StatefulWidget {
  const ActivityEditor({super.key, this.existing});
  final DayActivity? existing;

  @override
  State<ActivityEditor> createState() => _ActivityEditorState();
}

class _ActivityEditorState extends State<ActivityEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController time;
  late final TextEditingController who;
  late final TextEditingController what;
  late final TextEditingController where;
  late final TextEditingController how;
  late final TextEditingController note;
  String symbol = '📌';
  String photoPath = '';

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    title = TextEditingController(text: item?.title ?? '');
    time = TextEditingController(text: item?.time ?? '09:00');
    who = TextEditingController(text: item?.who ?? 'Ik');
    what = TextEditingController(text: item?.what ?? '');
    where = TextEditingController(text: item?.where ?? '');
    how = TextEditingController(text: item?.how ?? '');
    note = TextEditingController(text: item?.note ?? '');
    symbol = item?.symbol ?? '📌';
    photoPath = item?.photoPath ?? '';
  }

  @override
  void dispose() {
    title.dispose(); time.dispose(); who.dispose(); what.dispose(); where.dispose(); how.dispose(); note.dispose();
    super.dispose();
  }

  Widget field(TextEditingController controller, String label, String hint, {bool required = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          controller: controller,
          maxLines: lines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: required ? (value) => value == null || value.trim().isEmpty ? 'Vul een naam in.' : null : null,
        ),
      );

  Future<void> choosePhoto() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return;
      final file = picked.first;
      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) return;
      final directory = await getApplicationSupportDirectory();
      final imageDirectory = Directory('${directory.path}${Platform.pathSeparator}activity_images');
      await imageDirectory.create(recursive: true);
      final extension = (file.extension ?? 'jpg').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final safeName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
      final saved = await File(sourcePath).copy(
        '${imageDirectory.path}${Platform.pathSeparator}$safeName',
      );
      if (!mounted) return;
      setState(() => photoPath = saved.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('De foto kon niet worden toegevoegd. Probeer een andere afbeelding.')));
    }
  }

  void save() {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.existing;
    Navigator.pop(context, DayActivity(
      id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.text.trim(),
      time: time.text.trim().isEmpty ? '09:00' : time.text.trim(),
      who: who.text.trim(),
      what: what.text.trim(),
      where: where.text.trim(),
      how: how.text.trim(),
      note: note.text.trim(),
      symbol: symbol,
      photoPath: photoPath,
      done: old?.done ?? false,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Nieuwe activiteit' : 'Activiteit aanpassen'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Maak de uitleg kort en duidelijk. Je kunt dit samen invullen.', style: TextStyle(color: _muted)),
                const SizedBox(height: 12),
                const SizedBox(height: 8),
                const Text('Pictogram', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: symbol,
                  decoration: const InputDecoration(labelText: 'Kies een herkenbaar plaatje'),
                  items: const [
                    DropdownMenuItem(value: '📌', child: Text('📌  Algemeen')),
                    DropdownMenuItem(value: '🍽️', child: Text('🍽️  Eten')),
                    DropdownMenuItem(value: '🚿', child: Text('🚿  Douchen')),
                    DropdownMenuItem(value: '👕', child: Text('👕  Aankleden')),
                    DropdownMenuItem(value: '🏠', child: Text('🏠  Thuis')),
                    DropdownMenuItem(value: '🚶', child: Text('🚶  Wandelen')),
                    DropdownMenuItem(value: '🚌', child: Text('🚌  Reizen')),
                    DropdownMenuItem(value: '💊', child: Text('💊  Medicatie')),
                    DropdownMenuItem(value: '🧹', child: Text('🧹  Opruimen')),
                    DropdownMenuItem(value: '🎮', child: Text('🎮  Vrije tijd')),
                    DropdownMenuItem(value: '🛒', child: Text('🛒  Boodschappen')),
                    DropdownMenuItem(value: '😴', child: Text('😴  Rust')),
                  ],
                  onChanged: (value) { if (value != null) setState(() => symbol = value); },
                ),
                const SizedBox(height: 12),
                const Text('Eigen foto (optioneel)', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                const Text('Kies een foto die jou helpt de activiteit te herkennen. De foto blijft op dit apparaat.', style: TextStyle(color: _muted, fontSize: 13)),
                if (photoPath.isNotEmpty && File(photoPath).existsSync()) ...[
                  const SizedBox(height: 9),
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(photoPath), height: 130, width: double.infinity, fit: BoxFit.cover)),
                ],
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: choosePhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Foto kiezen')),
                  if (photoPath.isNotEmpty) TextButton.icon(onPressed: () => setState(() => photoPath = ''), icon: const Icon(Icons.close), label: const Text('Foto weghalen')),
                ]),
                field(title, 'Naam van de activiteit', 'Bijvoorbeeld: naar de winkel', required: true),
                field(time, 'Wanneer?', 'Bijvoorbeeld: 10:30'),
                field(who, 'Wie?', 'Wie is erbij?'),
                field(what, 'Wat?', 'Wat ga je doen?'),
                field(where, 'Waar?', 'Waar gebeurt het?'),
                field(how, 'Hoe?', 'Welke kleine stappen helpen?'),
                field(note, 'Extra uitleg (optioneel)', 'Wat is fijn om vooraf te weten?', lines: 2),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(onPressed: save, child: const Text('Opslaan')),
        ],
      );
}

class CalmPage extends StatefulWidget {
  const CalmPage({super.key});
  @override
  State<CalmPage> createState() => _CalmPageState();
}

class CalmStep {
  const CalmStep({required this.title, required this.description, required this.icon});
  final String title;
  final String description;
  final IconData icon;
}

class _CalmPageState extends State<CalmPage> {
  int step = 0;
  static const steps = [
    CalmStep(title: 'Voel de grond', description: 'Zet je voeten neer. Voel waar je voeten de grond raken.', icon: Icons.place_outlined),
    CalmStep(title: 'Kijk rustig om je heen', description: 'Noem voor jezelf drie dingen die je ziet. Je hoeft niets hardop te zeggen.', icon: Icons.remove_red_eye_outlined),
    CalmStep(title: 'Kies één kleine stap', description: 'Wat heb je nu nodig? Rust, hulp of verdergaan?', icon: Icons.spa_outlined),
  ];

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Even rust',
        subtitle: 'Een rustig moment. Je hoeft niets goed te doen.',
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(23)),
              child: Column(children: [
                CircleAvatar(radius: 33, backgroundColor: Colors.white, child: Icon(steps[step].icon, color: _green, size: 29)),
                const SizedBox(height: 18),
                Text('STAP ' + (step + 1).toString() + ' VAN 3', style: const TextStyle(color: _green, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                const SizedBox(height: 11),
                Text(steps[step].title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(steps[step].description, textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 16, height: 1.5)),
                const SizedBox(height: 23),
                Row(children: List.generate(3, (index) => Expanded(child: Container(height: 5, margin: EdgeInsets.only(right: index == 2 ? 0 : 7), decoration: BoxDecoration(color: index <= step ? _green : _line, borderRadius: BorderRadius.circular(5)))))),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: step == 0 ? null : () => setState(() => step--), child: const Text('Vorige'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(onPressed: () => setState(() => step = step == 2 ? 0 : step + 1), child: Text(step == 2 ? 'Opnieuw' : 'Volgende'))),
                ]),
                TextButton(onPressed: () => setState(() => step = 0), child: const Text('Stop met deze oefening')),
              ]),
            ),
            const SizedBox(height: 14),
            const Card(child: Padding(padding: EdgeInsets.all(17), child: Text('Je mag een stap overslaan of stoppen. Als dit niet prettig voelt, kies dan iets anders dat voor jou veilig en vertrouwd is.', style: TextStyle(color: _muted, height: 1.45)))),
          ]),
        )),
      );
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Mijn steun',
        subtitle: 'Zet hier wat jou helpt als een dag moeilijk voelt.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: _sand, borderRadius: BorderRadius.circular(18)), child: const Text('Je hoeft het niet alleen te doen. Je mag om hulp vragen en je eigen tempo volgen.', style: TextStyle(color: _ink, fontWeight: FontWeight.w600))),
          const SizedBox(height: 18),
          SupportCard(title: 'Als ik vastloop', value: controller.support['help'] ?? '', icon: Icons.pan_tool_outlined, edit: () => editSupport(context, controller, 'help', 'Als ik vastloop')),
          const SizedBox(height: 10),
          SupportCard(title: 'Een plek waar ik rust vind', value: controller.support['place'] ?? '', icon: Icons.home_outlined, edit: () => editSupport(context, controller, 'place', 'Een plek waar ik rust vind')),
          const SizedBox(height: 10),
          SupportCard(title: 'Iemand die mij kan helpen', value: (controller.support['person'] ?? '').isEmpty ? 'Nog niet ingevuld' : controller.support['person']!, icon: Icons.people_outline, edit: () => editSupport(context, controller, 'person', 'Iemand die mij kan helpen')),
          const SizedBox(height: 22),
          const Text('Wat kun je doen als het te veel wordt?', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const SimpleStep(number: '1', text: 'Ga naar een plek die voor jou rustig en veilig voelt.'),
          const SimpleStep(number: '2', text: 'Kies één ding. De rest kan wachten.'),
          const SimpleStep(number: '3', text: 'Vraag iemand die je vertrouwt om hulp.'),
          const SizedBox(height: 13),
          const Text('Bij direct gevaar: bel 112 of vraag iemand in de buurt om direct hulp te halen.', style: TextStyle(color: _muted, fontSize: 12, height: 1.45)),
          if (controller.storageNotice != null) Padding(padding: const EdgeInsets.only(top: 12), child: StorageNotice(message: controller.storageNotice!)),
          const SizedBox(height: 18),
          const SmallDisclaimer(),
        ]),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Instellingen',
        subtitle: 'Pas MoodPress aan op wat prettig werkt voor jou.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.text_fields_rounded, color: _green),
                  SizedBox(width: 10),
                  Text('Tekstgrootte', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Kies tekst die prettig leesbaar is.', style: TextStyle(color: _muted)),
                const SizedBox(height: 15),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1.0, label: Text('Normaal')),
                    ButtonSegment(value: 1.15, label: Text('Groter')),
                    ButtonSegment(value: 1.3, label: Text('Extra groot')),
                  ],
                  selected: {controller.preferences.textScale},
                  onSelectionChanged: (values) => controller.setTextScale(values.first),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.motion_photos_off_outlined, color: _green),
                  SizedBox(width: 10),
                  Expanded(child: Text('Minder beweging', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 5),
                const Text('Schakel bewegende overgangen en animaties zoveel mogelijk uit als dat rustiger voelt.', style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rustige weergave'),
                  subtitle: const Text('Minder animaties in de app'),
                  value: controller.preferences.reduceMotion,
                  onChanged: controller.setReduceMotion,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.notifications_none_rounded, color: _green),
                  SizedBox(width: 10),
                  Text('Herinneringen', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Krijg op het geplande tijdstip een rustige melding zolang MoodPress open is. Je kunt dit altijd uitzetten.', style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Herinneringen in de app'),
                  subtitle: const Text('Staat standaard uit'),
                  value: controller.preferences.inAppRemindersEnabled,
                  onChanged: controller.setInAppRemindersEnabled,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.volume_up_outlined, color: _green),
                  SizedBox(width: 10),
                  Text('Voorleessnelheid', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                const Text('Maak het voorlezen langzamer of sneller.', style: TextStyle(color: _muted)),
                Slider(
                  value: controller.preferences.speechRate,
                  min: 0.3,
                  max: 0.6,
                  divisions: 6,
                  label: controller.preferences.speechRate.toStringAsFixed(2),
                  onChanged: controller.setSpeechRate,
                ),
                const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Langzaam', style: TextStyle(color: _muted, fontSize: 12)),
                  Text('Sneller', style: TextStyle(color: _muted, fontSize: 12)),
                ]),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => SpeakButtonPreview.play(context, controller.preferences.speechRate),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Luister naar een voorbeeld'),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Jouw instellingen', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                const Text('Je voorkeuren worden op dit apparaat bewaard. Ze worden niet naar een account of cloud verstuurd.', style: TextStyle(color: _muted, height: 1.45)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.resetPreferences,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Herstel standaardinstellingen'),
                ),
              ]),
            ),
          ),
          if (controller.storageNotice != null) ...[
            const SizedBox(height: 12),
            StorageNotice(message: controller.storageNotice!),
          ],
          const SizedBox(height: 18),
          const SmallDisclaimer(),
        ]),
      );
}

class SpeakButtonPreview {
  static Future<void> play(BuildContext context, double rate) async {
    final messenger = ScaffoldMessenger.of(context);
    final tts = FlutterTts();
    try {
      await tts.setLanguage('nl-NL');
      await tts.setSpeechRate(rate);
      await tts.setPitch(1.0);
      await tts.awaitSpeakCompletion(true);
      await tts.speak('Dit is een voorbeeld. Je kunt de voorleessnelheid aanpassen aan wat prettig is.');
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Voorlezen is op dit apparaat niet beschikbaar.')));
    } finally {
      await tts.stop();
    }
  }
}

class SupportCard extends StatelessWidget {
  const SupportCard({super.key, required this.title, required this.value, required this.icon, required this.edit});
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback edit;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _green)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value.isEmpty ? 'Nog niet ingevuld' : value, style: const TextStyle(color: _muted, fontSize: 13, height: 1.35)),
          ])),
          IconButton(tooltip: 'Aanpassen', onPressed: edit, icon: const Icon(Icons.edit_outlined, color: _green)),
        ]),
      ));
}

Future<void> editSupport(BuildContext context, MoodPressController controller, String key, String title) async {
  final field = TextEditingController(text: controller.support[key] ?? '');
  final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 450, child: TextField(controller: field, autofocus: true, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Schrijf op wat jou helpt.'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Opslaan')),
        ],
      ));
  field.dispose();
  if (value != null) await controller.saveSupport(key, value);
}

class SimpleStep extends StatelessWidget {
  const SimpleStep({super.key, required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 13, backgroundColor: _greenPale, child: Text(number, style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w800))),
        const SizedBox(width: 11),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(text, style: const TextStyle(color: _ink)))),
      ]));
}

class StorageNotice extends StatelessWidget {
  const StorageNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFFFF2E6), borderRadius: BorderRadius.circular(13)), child: Text(message, style: const TextStyle(color: _ink, fontSize: 12, height: 1.4)));
}

class SmallDisclaimer extends StatelessWidget {
  const SmallDisclaimer({super.key});

  @override
  Widget build(BuildContext context) => const Text(
        'MoodPress helpt bij dagstructuur en overzicht. De app stelt geen diagnose en vervangt geen professionele zorg.',
        style: TextStyle(color: _muted, fontSize: 11, height: 1.45),
      );
}

class SpeakButton extends StatefulWidget {
  const SpeakButton({super.key, required this.text, this.speechRate = 0.42});
  final String text;
  final double speechRate;

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  final FlutterTts _tts = FlutterTts();
  bool speaking = false;

  Future<void> _toggle() async {
    try {
      if (speaking) {
        await _tts.stop();
        if (mounted) setState(() => speaking = false);
        return;
      }
      await _tts.setLanguage('nl-NL');
      await _tts.setSpeechRate(widget.speechRate);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      if (mounted) setState(() => speaking = true);
      await _tts.speak(widget.text);
      if (mounted) setState(() => speaking = false);
    } catch (_) {
      if (mounted) setState(() => speaking = false);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: speaking ? 'Stop voorlezen' : 'Lees voor',
        onPressed: _toggle,
        icon: Icon(speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined, color: _green),
      );
}
