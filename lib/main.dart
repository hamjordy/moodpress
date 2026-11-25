
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  runApp(MoodPressApp(controller: controller));
  unawaited(controller.load());
}

List<bool> _normalizeStepProgress(List<String> steps, List<bool> progress) =>
    List<bool>.generate(
      steps.length,
      (index) => index < progress.length ? progress[index] : false,
    );

List<String> parseActivitySteps(String value) => value
    .split('\n')
    .map((step) => step.trim())
    .where((step) => step.isNotEmpty)
    .take(12)
    .toList();

int safeFocusedActivityIndex(int requestedIndex, int activityCount) {
  if (activityCount <= 0) return 0;
  return requestedIndex.clamp(0, activityCount - 1).toInt();
}

bool toggleDayActivityStep(DayActivity activity, int index) {
  if (index < 0 || index >= activity.steps.length) return false;
  activity.stepDone = _normalizeStepProgress(
    activity.steps,
    activity.stepDone,
  );
  activity.stepDone[index] = !activity.stepDone[index];
  return true;
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
    this.steps = const <String>[],
    this.stepDone = const <bool>[],
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
  List<String> steps;
  List<bool> stepDone;

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
        'steps': steps,
        'stepDone': _normalizeStepProgress(steps, stepDone),
      };

  factory DayActivity.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    final rawProgress = json['stepDone'];
    final steps = <String>[];
    final progress = <bool>[];
    if (rawSteps is List) {
      for (var index = 0; index < rawSteps.length && steps.length < 12; index++) {
        final step = rawSteps[index];
        if (step is! String) continue;
        steps.add(step);
        final savedProgress = rawProgress is List && index < rawProgress.length
            ? rawProgress[index]
            : null;
        progress.add(savedProgress is bool ? savedProgress : false);
      }
    }
    return DayActivity(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title'] is String ? json['title'] as String : 'Nieuwe activiteit',
      time: json['time'] is String ? json['time'] as String : '09:00',
      who: json['who'] is String ? json['who'] as String : '',
      what: json['what'] is String ? json['what'] as String : '',
      where: json['where'] is String ? json['where'] as String : '',
      how: json['how'] is String ? json['how'] as String : '',
      note: json['note'] is String ? json['note'] as String : '',
      symbol: json['symbol'] is String ? json['symbol'] as String : '📌',
      photoPath: json['photoPath'] is String ? json['photoPath'] as String : '',
      done: json['done'] is bool ? json['done'] as bool : false,
      steps: steps,
      stepDone: _normalizeStepProgress(steps, progress),
    );
  }

  DayActivity copyWith({
    String? id,
    bool? done,
    bool resetSteps = false,
  }) =>
      DayActivity(
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
        steps: List<String>.from(steps),
        stepDone: resetSteps
            ? List<bool>.filled(steps.length, false)
            : List<bool>.from(_normalizeStepProgress(steps, stepDone)),
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
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] is String ? json['name'] as String : 'Dagindeling',
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
        resetSteps: true,
      ),
    );
  }
}

DayTemplate buildRestoredDayTemplate(
  dynamic raw,
  List<DayActivity> activities,
) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException('Een dagindeling in deze back-up is niet geldig.');
  }
  final rawId = raw['id'];
  final rawName = raw['name'];
  return DayTemplate(
    id: rawId is String && rawId.isNotEmpty
        ? rawId
        : DateTime.now().microsecondsSinceEpoch.toString(),
    name: rawName is String ? rawName : 'Dagindeling',
    activities: activities,
  );
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



class PrikkelMeting {
  const PrikkelMeting({
    required this.id,
    required this.level,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final int level;
  final DateTime createdAt;
  final String note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level,
    'createdAt': createdAt.toIso8601String(),
    'note': note,
  };

  factory PrikkelMeting.fromJson(Map<String, dynamic> json) {
    final level = json['level'];
    final date = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    return PrikkelMeting(
      id: json['id'] is String ? json['id'] as String : '',
      level: level is int ? level.clamp(1, 5) : 1,
      createdAt: date ?? DateTime.now(),
      note: json['note'] is String ? json['note'] as String : '',
    );
  }
}

class PrikkelInzichten {
  const PrikkelInzichten({
    required this.totalMeasurements,
    required this.averageLevel,
    required this.mostCommonLevel,
    required this.highestAverageWeekday,
    required this.highestAverageWeekdayLevel,
    required this.highestAverageWeekdayCount,
    required this.recentAverage,
    required this.previousAverage,
  });

  final int totalMeasurements;
  final double? averageLevel;
  final int? mostCommonLevel;
  final int? highestAverageWeekday;
  final double? highestAverageWeekdayLevel;
  final int highestAverageWeekdayCount;
  final double? recentAverage;
  final double? previousAverage;
}

PrikkelInzichten berekenPrikkelInzichten(
  List<PrikkelMeting> metingen, {
  DateTime? vandaag,
}) {
  final total = metingen.length;
  final average = total == 0
      ? null
      : metingen.fold<int>(0, (sum, item) => sum + item.level) / total;
  final levelCounts = List<int>.filled(5, 0);
  for (final meting in metingen) {
    if (meting.level >= 1 && meting.level <= 5) {
      levelCounts[meting.level - 1]++;
    }
  }
  int? commonLevel;
  for (var index = 0; index < levelCounts.length; index++) {
    if (levelCounts[index] > 0 &&
        (commonLevel == null ||
            levelCounts[index] > levelCounts[commonLevel - 1])) {
      commonLevel = index + 1;
    }
  }
  final weekdayTotals = List<int>.filled(7, 0);
  final weekdayCounts = List<int>.filled(7, 0);
  for (final meting in metingen) {
    final index = meting.createdAt.weekday - 1;
    weekdayTotals[index] += meting.level;
    weekdayCounts[index]++;
  }
  int? busiestWeekday;
  double? busiestAverage;
  for (var index = 0; index < 7; index++) {
    if (weekdayCounts[index] == 0) continue;
    final dayAverage = weekdayTotals[index] / weekdayCounts[index];
    if (busiestAverage == null || dayAverage > busiestAverage) {
      busiestWeekday = index + 1;
      busiestAverage = dayAverage;
    }
  }
  final comparison = vergelijkPrikkelPeriodes(
    metingen,
    periode: 0,
    vandaag: vandaag,
  );
  return PrikkelInzichten(
    totalMeasurements: total,
    averageLevel: average,
    mostCommonLevel: commonLevel,
    highestAverageWeekday: busiestWeekday,
    highestAverageWeekdayLevel: busiestAverage,
    highestAverageWeekdayCount: busiestWeekday == null
        ? 0
        : weekdayCounts[busiestWeekday - 1],
    recentAverage: comparison.huidigGemiddelde,
    previousAverage: comparison.vorigGemiddelde,
  );
}

class PrikkelWeekTrendPunt {
  const PrikkelWeekTrendPunt({
    required this.weekStart,
    required this.averageLevel,
    required this.count,
  });

  final DateTime weekStart;
  final double? averageLevel;
  final int count;
}

List<PrikkelWeekTrendPunt> maakPrikkelWeekTrend(
  List<PrikkelMeting> metingen, {
  DateTime? vandaag,
  int aantalWeken = 8,
}) {
  final reference = vandaag ?? DateTime.now();
  final startDezeWeek = DateTime(
    reference.year,
    reference.month,
    reference.day,
  ).subtract(Duration(days: reference.weekday - 1));
  return List<PrikkelWeekTrendPunt>.generate(aantalWeken, (index) {
    final weekStart = startDezeWeek.subtract(
      Duration(days: (aantalWeken - index - 1) * 7),
    );
    final weekEinde = weekStart.add(const Duration(days: 7));
    final weekMetingen = metingen.where((meting) {
      final datum = meting.createdAt;
      return !datum.isBefore(weekStart) && datum.isBefore(weekEinde);
    }).toList();
    final count = weekMetingen.length;
    final average = count == 0
        ? null
        : weekMetingen.fold<int>(0, (sum, item) => sum + item.level) / count;
    return PrikkelWeekTrendPunt(
      weekStart: weekStart,
      averageLevel: average,
      count: count,
    );
  });
}

class PrikkelDagSamenvatting {
  const PrikkelDagSamenvatting({
    required this.date,
    required this.averageLevel,
    required this.count,
  });

  final DateTime date;
  final double? averageLevel;
  final int count;
}

class PrikkelGrafiekPunt {
  const PrikkelGrafiekPunt({
    required this.date,
    required this.label,
    required this.averageLevel,
    required this.count,
  });

  final DateTime date;
  final String label;
  final double? averageLevel;
  final int count;
}

List<PrikkelDagSamenvatting> maakPrikkelWeekOverzicht(
  List<PrikkelMeting> metingen, {
  DateTime? vandaag,
}) {
  final now = vandaag ?? DateTime.now();
  final start = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 6));
  return List.generate(7, (index) {
    final date = start.add(Duration(days: index));
    final dayMeasurements = metingen.where((item) =>
        item.createdAt.year == date.year &&
        item.createdAt.month == date.month &&
        item.createdAt.day == date.day);
    final count = dayMeasurements.length;
    final average = count == 0
        ? null
        : dayMeasurements.fold<int>(0, (sum, item) => sum + item.level) /
            count;
    return PrikkelDagSamenvatting(
      date: date,
      averageLevel: average,
      count: count,
    );
  });
}

List<PrikkelGrafiekPunt> maakPrikkelGrafiekPunten(
  List<PrikkelMeting> metingen, {
  required int periode,
  DateTime? vandaag,
}) {
  final now = vandaag ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  const weekdays = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  const months = [
    'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
    'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
  ];
  final monthly = periode == 2;
  final count = periode == 0 ? 7 : (periode == 1 ? 30 : 12);
  final firstDate = monthly
      ? DateTime(today.year, today.month - count + 1, 1)
      : today.subtract(Duration(days: count - 1));

  return List.generate(count, (index) {
    final date = monthly
        ? DateTime(firstDate.year, firstDate.month + index, 1)
        : firstDate.add(Duration(days: index));
    final nextDate = monthly
        ? DateTime(date.year, date.month + 1, 1)
        : date.add(const Duration(days: 1));
    final bucket = metingen.where((item) =>
        !item.createdAt.isBefore(date) && item.createdAt.isBefore(nextDate));
    final total = bucket.fold<int>(0, (sum, item) => sum + item.level);
    final amount = bucket.length;
    final label = monthly
        ? months[date.month - 1]
        : (periode == 0
            ? weekdays[date.weekday - 1]
            : (index % 5 == 0 || index == count - 1
                ? date.day.toString()
                : ''));
    return PrikkelGrafiekPunt(
      date: date,
      label: label,
      averageLevel: amount == 0 ? null : total / amount,
      count: amount,
    );
  });
}

List<PrikkelMeting> prikkelMetingenVoorGrafiekPunt(
  List<PrikkelMeting> metingen,
  PrikkelGrafiekPunt point, {
  required bool perMaand,
}) {
  final start = perMaand
      ? DateTime(point.date.year, point.date.month, 1)
      : DateTime(point.date.year, point.date.month, point.date.day);
  final end = perMaand
      ? DateTime(point.date.year, point.date.month + 1, 1)
      : start.add(const Duration(days: 1));
  final matches = metingen
      .where((item) =>
          !item.createdAt.isBefore(start) && item.createdAt.isBefore(end))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return matches;
}

PrikkelGrafiekPunt? hoogstePrikkelGrafiekPunt(
  List<PrikkelGrafiekPunt> punten,
) {
  final metingen = punten.where((punt) => punt.averageLevel != null);
  if (metingen.isEmpty) return null;
  return metingen.reduce((hoogste, huidig) =>
      huidig.averageLevel! > hoogste.averageLevel! ? huidig : hoogste);
}

class PrikkelPeriodeVergelijking {
  const PrikkelPeriodeVergelijking({
    required this.huidigGemiddelde,
    required this.vorigGemiddelde,
    required this.huidigAantal,
    required this.vorigAantal,
  });

  final double? huidigGemiddelde;
  final double? vorigGemiddelde;
  final int huidigAantal;
  final int vorigAantal;
}

PrikkelPeriodeVergelijking vergelijkPrikkelPeriodes(
  List<PrikkelMeting> metingen, {
  required int periode,
  DateTime? vandaag,
}) {
  final now = vandaag ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dagen = periode == 0 ? 7 : 30;
  final huidigBegin = periode == 2
      ? DateTime(today.year, today.month - 11, 1)
      : today.subtract(Duration(days: dagen - 1));
  final huidigEinde = periode == 2
      ? DateTime(today.year, today.month + 1, 1)
      : today.add(const Duration(days: 1));
  final vorigBegin = periode == 2
      ? DateTime(huidigBegin.year, huidigBegin.month - 12, 1)
      : huidigBegin.subtract(Duration(days: dagen));
  final vorigEinde = huidigBegin;

  double? gemiddelde(DateTime begin, DateTime einde) {
    final geselecteerd = metingen.where((meting) =>
        !meting.createdAt.isBefore(begin) &&
        meting.createdAt.isBefore(einde)).toList();
    if (geselecteerd.isEmpty) return null;
    final totaal = geselecteerd.fold<int>(
      0,
      (som, meting) => som + meting.level,
    );
    return totaal / geselecteerd.length;
  }

  final huidig = metingen.where((meting) =>
      !meting.createdAt.isBefore(huidigBegin) &&
      meting.createdAt.isBefore(huidigEinde)).length;
  final vorig = metingen.where((meting) =>
      !meting.createdAt.isBefore(vorigBegin) &&
      meting.createdAt.isBefore(vorigEinde)).length;
  return PrikkelPeriodeVergelijking(
    huidigGemiddelde: gemiddelde(huidigBegin, huidigEinde),
    vorigGemiddelde: gemiddelde(vorigBegin, vorigEinde),
    huidigAantal: huidig,
    vorigAantal: vorig,
  );
}

const prikkelNiveaus = <String>[
  'Helemaal rustig',
  'Een beetje prikkels',
  'Best veel prikkels',
  'Erg veel prikkels',
  'Overprikkeld',
];

List<PrikkelMeting> filterPrikkelMetingen(
  List<PrikkelMeting> metingen, {
  String query = '',
  int niveau = 0,
}) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  final results = metingen.where((meting) {
    if (niveau != 0 && meting.level != niveau) return false;
    final date = meting.createdAt;
    final dateText = [
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}',
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      date.toIso8601String(),
      'niveau ${meting.level}',
      meting.level.toString(),
      prikkelNiveaus[meting.level - 1],
      meting.note,
    ].join(' ').toLowerCase();
    return terms.every(dateText.contains);
  }).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return results;
}

class PlanningSearchResult {
  const PlanningSearchResult({
    required this.date,
    required this.activity,
  });

  final DateTime date;
  final DayActivity activity;
}

List<PlanningSearchResult> searchPlanningActivities(
  Map<String, List<DayActivity>> plans,
  String query,
) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  if (terms.isEmpty) return const <PlanningSearchResult>[];

  final results = <PlanningSearchResult>[];
  final dateKeys = plans.keys.toList()..sort();

  for (final dateKey in dateKeys) {
    final date = DateTime.tryParse(dateKey);
    if (date == null) continue;
    final dateText = [
      _formatDutchWeekday(date),
      _formatDutchDate(date),
      date.year.toString(),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
      dateKey,
    ].join(' ');

    for (final activity in plans[dateKey] ?? const <DayActivity>[]) {
      final searchableText = [
        activity.title,
        activity.time,
        activity.who,
        activity.what,
        activity.where,
        activity.how,
        activity.note,
        ...activity.steps,
        activity.done ? 'afgerond klaar voltooid' : 'openstaand niet afgerond',
        dateText,
      ].join(' ').toLowerCase();

      if (terms.every(searchableText.contains)) {
        results.add(PlanningSearchResult(date: date, activity: activity));
      }
    }
  }

  return results;
}

bool isActivityDueAt(DayActivity activity, DateTime now) {
  if (activity.done) return false;
  final parts = activity.time.split(':');
  if (parts.length != 2) return false;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  return hour != null && minute != null &&
      hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 &&
      hour == now.hour && minute == now.minute;
}


List<DayActivity> copyDayActivities(
  List<DayActivity> source, {
  required String idPrefix,
}) =>
    List<DayActivity>.generate(
      source.length,
      (index) => source[index].copyWith(
        id: idPrefix + '-' + index.toString(),
        done: false,
        resetSteps: true,
      ),
    );

DayActivity copyDayActivity(
  DayActivity source, {
  required String newId,
}) =>
    source.copyWith(id: newId, done: false, resetSteps: true);

bool moveDayActivityBetweenLists(
  List<DayActivity> source,
  List<DayActivity> destination, {
  required String activityId,
}) {
  if (identical(source, destination)) return false;
  final index = source.indexWhere((activity) => activity.id == activityId);
  if (index == -1) return false;
  destination.add(source.removeAt(index));
  return true;
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
    this.speechEnabled = true,
    this.hasSeenWelcome = false,
  });

  final double textScale;
  final double speechRate;
  final bool reduceMotion;
  final bool inAppRemindersEnabled;
  final bool speechEnabled;
  final bool hasSeenWelcome;

  Map<String, dynamic> toJson() => {
        'textScale': textScale,
        'speechRate': speechRate,
        'reduceMotion': reduceMotion,
        'inAppRemindersEnabled': inAppRemindersEnabled,
        'speechEnabled': speechEnabled,
        'hasSeenWelcome': hasSeenWelcome,
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
      reduceMotion: json['reduceMotion'] is bool ? json['reduceMotion'] as bool : false,
      inAppRemindersEnabled: json['inAppRemindersEnabled'] is bool
          ? json['inAppRemindersEnabled'] as bool
          : false,
      // Existing preference files did not contain this field; keep speech on.
      speechEnabled: json['speechEnabled'] is bool ? json['speechEnabled'] as bool : true,
      // Older installations already know the app; do not show onboarding after an update.
      hasSeenWelcome: json['hasSeenWelcome'] is bool
          ? json['hasSeenWelcome'] as bool
          : true,
    );
  }
}

class MoodPressController extends ChangeNotifier {
  MoodPressController({
    Map<DateTime, List<DayActivity>> initialPlans =
        const <DateTime, List<DayActivity>>{},
  }) {
    for (final entry in initialPlans.entries) {
      _plansByDate[_dateKey(entry.key)] =
          List<DayActivity>.from(entry.value);
    }
  }

  static const _dayPlansKey = 'moodpress.dayplans.v1';
  static const _legacyDayKey = 'moodpress.day.v1';
  static const _supportKey = 'moodpress.support.v1';
  static const _preferencesKey = 'moodpress.preferences.v1';
  static const _templatesKey = 'moodpress.templates.v1';
  static const _weeklyRoutineKey = 'moodpress.weeklyroutine.v1';
  static const _prikkelMetingenKey = 'moodpress.prikkelmetingen.v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Map<String, List<DayActivity>> _plansByDate = {};
  DateTime selectedDate = DateTime.now();

  List<DayTemplate> templates = [];
  WeeklyRoutine weeklyRoutine = const WeeklyRoutine();
  List<PrikkelMeting> prikkelMetingen = [];
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

  List<PlanningSearchResult> searchActivities(String query) =>
      searchPlanningActivities(_plansByDate, query);

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
    var hasExistingLocalData = false;
    try {
      final savedPlans = await _storage.read(key: _dayPlansKey);
      if (savedPlans != null) {
        hasExistingLocalData = true;
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
          hasExistingLocalData = true;
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
        hasExistingLocalData = true;
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
      } else {
        preferences = MoodPressPreferences(
          hasSeenWelcome: hasExistingLocalData,
        );
      }
    } catch (_) {
      preferences = MoodPressPreferences(
        hasSeenWelcome: hasExistingLocalData,
      );
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

    try {
      final savedMetingen = await _storage.read(key: _prikkelMetingenKey);
      if (savedMetingen != null) {
        final values = jsonDecode(savedMetingen) as List<dynamic>;
        prikkelMetingen = values
            .whereType<Map<String, dynamic>>()
            .map(PrikkelMeting.fromJson)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    } catch (_) {
      prikkelMetingen = [];
      storageNotice ??= 'Je prikkelmetergegevens konden niet worden gelezen.';
    }

    ready = true;
    notifyListeners();
  }

  Future<void> savePrikkelMeting(int level, String note) async {
    if (level < 1 || level > 5) return;
    prikkelMetingen.insert(0, PrikkelMeting(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      level: level,
      createdAt: DateTime.now(),
      note: note.trim(),
    ));
    if (prikkelMetingen.length > 200) {
      prikkelMetingen = prikkelMetingen.take(200).toList();
    }
    await _savePrikkelMetingen();
  }

  Future<bool> updatePrikkelMeting(
    String id, {
    required int level,
    required String note,
  }) async {
    if (level < 1 || level > 5) return false;
    final index = prikkelMetingen.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final current = prikkelMetingen[index];
    prikkelMetingen[index] = PrikkelMeting(
      id: current.id,
      level: level,
      createdAt: current.createdAt,
      note: note.trim(),
    );
    await _savePrikkelMetingen();
    return true;
  }

  Future<bool> deletePrikkelMeting(String id) async {
    final index = prikkelMetingen.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    prikkelMetingen.removeAt(index);
    await _savePrikkelMetingen();
    return true;
  }

  Future<void> _savePrikkelMetingen() async {
    try {
      await _storage.write(
        key: _prikkelMetingenKey,
        value: jsonEncode(prikkelMetingen.map((item) => item.toJson()).toList()),
      );
    } catch (_) {
      storageNotice = 'Je prikkelmetergegevens konden niet veilig worden opgeslagen.';
    }
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
      activities: source.map((item) => item.copyWith(done: false, resetSteps: true)).toList(),
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


  Future<int> copyDayPlan(
    DateTime sourceDate,
    DateTime targetDate, {
    bool replaceExisting = false,
  }) async {
    final sourceKey = _dateKey(sourceDate);
    final targetKey = _dateKey(targetDate);
    if (sourceKey == targetKey) return 0;

    final source = activitiesFor(sourceDate);
    if (source.isEmpty) return 0;
    if (_plansByDate.containsKey(targetKey) && !replaceExisting) return 0;

    final prefix = 'copy-' + DateTime.now().microsecondsSinceEpoch.toString();
    _plansByDate[targetKey] = copyDayActivities(
      source,
      idPrefix: prefix,
    );
    await _saveDayPlans();
    notifyListeners();
    return source.length;
  }

  Future<bool> copyActivityToDate(
    DateTime sourceDate,
    String activityId,
    DateTime targetDate,
  ) async {
    final sourceKey = _dateKey(sourceDate);
    final targetKey = _dateKey(targetDate);
    if (sourceKey == targetKey) return false;

    final source = _plansByDate[sourceKey];
    if (source == null) return false;
    final index = source.indexWhere((activity) => activity.id == activityId);
    if (index == -1) return false;

    final prefix = 'copy-activity-' +
        DateTime.now().microsecondsSinceEpoch.toString();
    final destination = _plansByDate.putIfAbsent(
      targetKey,
      () => <DayActivity>[],
    );
    destination.add(
      copyDayActivity(source[index], newId: prefix),
    );
    await _saveDayPlans();
    notifyListeners();
    return true;
  }

  Future<bool> moveActivityToDate(
    DateTime sourceDate,
    String activityId,
    DateTime targetDate,
  ) async {
    final sourceKey = _dateKey(sourceDate);
    final targetKey = _dateKey(targetDate);
    if (sourceKey == targetKey) return false;

    final source = _plansByDate[sourceKey];
    if (source == null) return false;

    final destinationExisted = _plansByDate.containsKey(targetKey);
    final destination = _plansByDate.putIfAbsent(
      targetKey,
      () => <DayActivity>[],
    );
    final moved = moveDayActivityBetweenLists(
      source,
      destination,
      activityId: activityId,
    );
    if (!moved) {
      if (!destinationExisted) _plansByDate.remove(targetKey);
      return false;
    }

    await _saveDayPlans();
    notifyListeners();
    return true;
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

  Future<void> toggleActivityStep(String id, int stepIndex) async {
    final dayActivities = _mutableActivitiesFor(selectedDate);
    final activityIndex = dayActivities.indexWhere(
      (activity) => activity.id == id,
    );
    if (activityIndex == -1) return;

    final activity = dayActivities[activityIndex];
    if (!toggleDayActivityStep(activity, stepIndex)) return;

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
      activities: source.map((item) => item.copyWith(done: false, resetSteps: true)).toList(),
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
      final parts = path.split('.');
      final candidate = parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
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
      'prikkelMetingen': prikkelMetingen.map((item) => item.toJson()).toList(),
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
          if (!RegExp(r'^photo_[0-9]+$').hasMatch(entry.key) ||
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
          throw FormatException('Een dagindeling in deze back-up is niet geldig.');
        }
        return buildRestoredDayTemplate(
          raw,
          restoreActivities(raw['activities']),
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

      final rawPrikkelMetingen = document['prikkelMetingen'];
      final restoredPrikkelMetingen = rawPrikkelMetingen is List
          ? rawPrikkelMetingen
              .whereType<Map<String, dynamic>>()
              .map(PrikkelMeting.fromJson)
              .toList()
          : <PrikkelMeting>[];

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
        _prikkelMetingenKey: jsonEncode(
          restoredPrikkelMetingen.map((item) => item.toJson()).toList(),
        ),
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
      prikkelMetingen = restoredPrikkelMetingen;
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
      speechEnabled: preferences.speechEnabled,
      hasSeenWelcome: preferences.hasSeenWelcome,
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
      speechEnabled: preferences.speechEnabled,
      hasSeenWelcome: preferences.hasSeenWelcome,
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
      speechEnabled: preferences.speechEnabled,
      hasSeenWelcome: preferences.hasSeenWelcome,
    );
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setSpeechEnabled(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
      speechEnabled: value,
      hasSeenWelcome: preferences.hasSeenWelcome,
    );
    notifyListeners();
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setInAppRemindersEnabled(bool value) async {
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: value,
      speechEnabled: preferences.speechEnabled,
      hasSeenWelcome: preferences.hasSeenWelcome,
    );
    // Update the visible switch immediately; disk persistence follows.
    notifyListeners();
    await _savePreferences();
    // Refresh again so a storage warning is also visible if saving failed.
    notifyListeners();
  }

  Future<void> deleteAllLocalData() async {
    // Delete only MoodPress-owned secure-storage keys.
    for (final key in [
      _dayPlansKey,
      _legacyDayKey,
      _supportKey,
      _preferencesKey,
      _templatesKey,
      _weeklyRoutineKey,
      _prikkelMetingenKey,
    ]) {
      await _storage.delete(key: key);
    }

    final appDirectory = await getApplicationSupportDirectory();
    final photoDirectory = Directory(
      appDirectory.path + Platform.pathSeparator + 'activity_images',
    );
    if (await photoDirectory.exists()) {
      await photoDirectory.delete(recursive: true);
    }

    _plansByDate.clear();
    templates = [];
    weeklyRoutine = const WeeklyRoutine();
    prikkelMetingen = [];
    support = {
      'help': 'Ik wil even rust en één ding tegelijk doen.',
      'place': 'Een rustige plek waar ik mij prettig voel.',
      'person': '',
    };
    preferences = const MoodPressPreferences();
    feeling = null;
    storageNotice = null;
    notifyListeners();
  }

  Future<void> completeWelcome() async {
    if (preferences.hasSeenWelcome) return;
    preferences = MoodPressPreferences(
      textScale: preferences.textScale,
      speechRate: preferences.speechRate,
      reduceMotion: preferences.reduceMotion,
      inAppRemindersEnabled: preferences.inAppRemindersEnabled,
      speechEnabled: preferences.speechEnabled,
      hasSeenWelcome: true,
    );
    // Switch to the app immediately; saving locally may take a moment.
    notifyListeners();
    await _savePreferences();
  }

  Future<void> resetPreferences() async {
    preferences = const MoodPressPreferences(hasSeenWelcome: true);
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
        home: !controller.ready
            ? const MoodPressSplashScreen()
            : controller.preferences.hasSeenWelcome
                ? MoodPressShell(controller: controller)
                : MoodPressWelcomeScreen(controller: controller),
      ),
    );
  }
}

class MoodPressSplashScreen extends StatelessWidget {
  const MoodPressSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _paper,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: _greenPale,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.spa_rounded,
                      size: 48,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'MoodPress',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Rust en overzicht in je dag.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Container(
                    width: 54,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Je omgeving wordt klaargemaakt…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class MoodPressWelcomeScreen extends StatelessWidget {
  const MoodPressWelcomeScreen({super.key, required this.controller});

  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _paper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: _greenPale,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(Icons.spa_rounded, color: _green, size: 40),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Welkom bij MoodPress',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _ink,
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Een rustige plek om overzicht te maken, op een manier die bij jou past.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    const _WelcomeFeature(
                      icon: Icons.calendar_month_rounded,
                      title: 'Maak je dag overzichtelijk',
                      description: 'Zet activiteiten op een rij en kijk wat voor jou werkt.',
                    ),
                    const SizedBox(height: 12),
                    const _WelcomeFeature(
                      icon: Icons.format_list_numbered_rounded,
                      title: 'Kleine stappen zijn genoeg',
                      description: 'Deel een activiteit op in stappen. Je mag het rustig aan doen.',
                    ),
                    const SizedBox(height: 12),
                    const _WelcomeFeature(
                      icon: Icons.spa_rounded,
                      title: 'Ruimte voor rust',
                      description: 'Neem een pauze wanneer je die nodig hebt. Je hoeft niets af te maken.',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Je gegevens blijven op dit apparaat. MoodPress gebruikt geen account of cloud.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => controller.completeWelcome(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 13),
                        child: Text('Aan de slag'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => controller.completeWelcome(),
                      child: const Text('Overslaan'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _WelcomeFeature extends StatelessWidget {
  const _WelcomeFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _green, size: 25),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: _muted, height: 1.4, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class MoodPressShell extends StatefulWidget {
  const MoodPressShell({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<MoodPressShell> createState() => _MoodPressShellState();
}

class _NavigateToPageIntent extends Intent {
  const _NavigateToPageIntent(this.index);

  final int index;
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
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.digit1, control: true):
              _NavigateToPageIntent(0),
          SingleActivator(LogicalKeyboardKey.digit2, control: true):
              _NavigateToPageIntent(1),
          SingleActivator(LogicalKeyboardKey.digit3, control: true):
              _NavigateToPageIntent(2),
          SingleActivator(LogicalKeyboardKey.digit4, control: true):
              _NavigateToPageIntent(3),
          SingleActivator(LogicalKeyboardKey.digit5, control: true):
              _NavigateToPageIntent(4),
          SingleActivator(LogicalKeyboardKey.numpad1, control: true):
              _NavigateToPageIntent(0),
          SingleActivator(LogicalKeyboardKey.numpad2, control: true):
              _NavigateToPageIntent(1),
          SingleActivator(LogicalKeyboardKey.numpad3, control: true):
              _NavigateToPageIntent(2),
          SingleActivator(LogicalKeyboardKey.numpad4, control: true):
              _NavigateToPageIntent(3),
          SingleActivator(LogicalKeyboardKey.numpad5, control: true):
              _NavigateToPageIntent(4),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _NavigateToPageIntent: CallbackAction<_NavigateToPageIntent>(
              onInvoke: (intent) {
                if (intent.index < 0 || intent.index >= labels.length) {
                  return null;
                }
                setState(() => selected = intent.index);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        final pages = [
          TodayPage(controller: widget.controller, openPlan: () => setState(() => selected = 1)),
          PlanningPage(controller: widget.controller),
          CalmPage(controller: widget.controller),
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
              }),
            ),
          ),
        ),
      );}

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
                    Semantics(
                      header: true,
                      child: Text(title!, style: Theme.of(context).textTheme.headlineMedium),
                    ),
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

class FocusedActivityAnnouncement extends StatelessWidget {
  const FocusedActivityAnnouncement({
    super.key,
    required this.index,
    required this.total,
    required this.activityTitle,
  });

  final int index;
  final int total;
  final String activityTitle;

  String get announcement =>
      'Activiteit ${index + 1} van $total: $activityTitle';

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        liveRegion: true,
        label: announcement,
        child: ExcludeSemantics(
          child: Text(
            'Activiteit ${index + 1} van $total',
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
    final greeting = now.hour < 12
        ? 'Goedemorgen'
        : now.hour < 18
            ? 'Goedemiddag'
            : 'Goedenavond';
    final weekday = _formatDutchWeekday(now);
    final todayLabel =
        weekday[0].toUpperCase() + weekday.substring(1) +
        ' ' + _formatDutchDate(now) + ' ' + now.year.toString();
    final todayActivities = controller.activitiesFor(now);
    final upcoming = todayActivities.where((item) => !item.done).toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    final completedToday = todayActivities.where((item) => item.done).length;
    final progressToday = todayActivities.isEmpty
        ? 0.0
        : completedToday / todayActivities.length;

    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(),
          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: _green),
                const SizedBox(width: 9),
                Semantics(
                  label: 'Vandaag, $todayLabel',
                  child: Text(
                    todayLabel,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 19),
          Semantics(
            header: true,
            child: Text(
              greeting + '.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'We doen het rustig aan. Eén ding tegelijk.',
            style: TextStyle(color: _muted, fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 25),
          LayoutBuilder(
            builder: (context, constraints) {
              final nextCard = NextStepCard(
                activity: next,
                openPlan: openPlan,
              );
              final progressCard = ProgressCard(
                done: completedToday,
                total: todayActivities.length,
                progress: progressToday,
                openPlan: openPlan,
              );
              if (constraints.maxWidth > 650) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: nextCard),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: progressCard),
                  ],
                );
              }
              return Column(
                children: [
                  nextCard,
                  const SizedBox(height: 14),
                  progressCard,
                ],
              );
            },
          ),
          const SizedBox(height: 29),
          Text(
            'Hoe is het nu met je?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Kies wat bij dit moment past. Je hoeft niets uit te leggen.',
            style: TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              FeelingChoice(
                label: 'Rustig',
                emoji: '🙂',
                selected: controller.feeling == 'Rustig',
                onTap: () => controller.setFeeling('Rustig'),
              ),
              FeelingChoice(
                label: 'Wat onrustig',
                emoji: '😐',
                selected: controller.feeling == 'Wat onrustig',
                onTap: () => controller.setFeeling('Wat onrustig'),
              ),
              FeelingChoice(
                label: 'Een vol hoofd',
                emoji: '😣',
                selected: controller.feeling == 'Een vol hoofd',
                onTap: () => controller.setFeeling('Een vol hoofd'),
              ),
            ],
          ),
          if (controller.feeling != null)
            const Padding(
              padding: EdgeInsets.only(top: 13),
              child: Text(
                'Dank je. Je hoeft hier verder niets mee te doen.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          if (controller.storageNotice != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: StorageNotice(message: controller.storageNotice!),
            ),
          const SizedBox(height: 22),
          const SmallDisclaimer(),
        ],
      ),
    );
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
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        selected: selected,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
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
  bool _singleActivityMode = false;
  int _focusedActivityIndex = 0;
  late DateTime _weekStart;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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


  Future<void> _copyDayToDate(
    BuildContext context,
    DateTime sourceDate,
  ) async {
    final targetDate = await showDatePicker(
      context: context,
      initialDate: sourceDate.add(const Duration(days: 1)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Kies de nieuwe datum',
      cancelText: 'Annuleren',
      confirmText: 'Kies datum',
    );
    if (targetDate == null || !context.mounted) return;

    if (_dateKey(targetDate) == _dateKey(sourceDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een andere datum dan de brondag.')),
      );
      return;
    }

    var replaceExisting = false;
    if (widget.controller.hasPlanFor(targetDate)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Er staat al een dagplan'),
          content: const Text(
            'Wil je het bestaande dagplan op deze datum vervangen? De activiteiten uit de gekozen dag worden opnieuw klaargezet.',
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
      if (confirmed != true || !context.mounted) return;
      replaceExisting = true;
    }

    final copied = await widget.controller.copyDayPlan(
      sourceDate,
      targetDate,
      replaceExisting: replaceExisting,
    );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied == 0
              ? 'Er zijn geen activiteiten om te kopiëren.'
              : copied.toString() + ' activiteiten gekopieerd naar ' +
                  _formatDutchWeekday(targetDate) + ' ' +
                  _formatDutchDate(targetDate) + '.',
        ),
      ),
    );
  }

  Future<void> _copyActivityToDate(
    BuildContext context,
    DateTime sourceDate,
    DayActivity activity,
  ) async {
    final targetDate = await showDatePicker(
      context: context,
      initialDate: sourceDate.add(const Duration(days: 1)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Kies de datum voor de kopie',
      cancelText: 'Annuleren',
      confirmText: 'Kopiëren',
    );
    if (targetDate == null || !context.mounted) return;

    if (_dateKey(targetDate) == _dateKey(sourceDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een andere datum dan de huidige dag.')),
      );
      return;
    }

    final copied = await widget.controller.copyActivityToDate(
      sourceDate,
      activity.id,
      targetDate,
    );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? 'Activiteit gekopieerd naar ' +
                  _formatDutchWeekday(targetDate) + ' ' +
                  _formatDutchDate(targetDate) + '.'
              : 'De activiteit kon niet worden gekopieerd.',
        ),
      ),
    );
  }

  Future<void> _moveActivityToDate(
    BuildContext context,
    DateTime sourceDate,
    DayActivity activity,
  ) async {
    final targetDate = await showDatePicker(
      context: context,
      initialDate: sourceDate.add(const Duration(days: 1)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Kies de nieuwe datum',
      cancelText: 'Annuleren',
      confirmText: 'Verplaatsen',
    );
    if (targetDate == null || !context.mounted) return;

    if (_dateKey(targetDate) == _dateKey(sourceDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een andere datum dan de huidige dag.')),
      );
      return;
    }

    final moved = await widget.controller.moveActivityToDate(
      sourceDate,
      activity.id,
      targetDate,
    );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          moved
              ? 'Activiteit verplaatst naar ' +
                  _formatDutchWeekday(targetDate) + ' ' +
                  _formatDutchDate(targetDate) + '.'
              : 'De activiteit kon niet worden verplaatst.',
        ),
      ),
    );
  }

  void _selectDay(DateTime date) {
    setState(() => _focusedActivityIndex = 0);
    widget.controller.selectDate(date);
  }

  void _openDay(DateTime date) {
    _selectDay(date);
    setState(() => _showWeek = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Zoek in je hele planning',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Zoekopdracht wissen',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _line),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_searchQuery.trim().isNotEmpty)
              _buildSearchResults()
            else ...[
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
          ],
        ),
      );

  Widget _buildSearchResults() {
    final results = widget.controller.searchActivities(_searchQuery);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            results.length.toString() +
                (results.length == 1
                    ? ' resultaat gevonden'
                    : ' resultaten gevonden'),
            style: const TextStyle(
              color: _muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (results.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.search_off_rounded, color: _muted),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Geen activiteiten gevonden. Probeer een andere naam, datum, tijd of een woord uit de uitleg.',
                      style: TextStyle(color: _ink, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final result in results) _buildSearchResultCard(result),
      ],
    );
  }

  Widget _buildSearchResultCard(PlanningSearchResult result) {
    final activity = result.activity;
    var detail = activity.what.trim();
    if (detail.isEmpty) detail = activity.note.trim();
    if (detail.isEmpty) detail = activity.where.trim();
    if (detail.isEmpty) detail = activity.how.trim();
    if (detail.isEmpty && activity.steps.isNotEmpty) {
      detail = activity.steps.first;
    }
    if (detail.isEmpty) {
      detail = activity.done ? 'Afgerond' : 'Nog te doen';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _greenPale,
            child: Text(
              activity.symbol,
              style: const TextStyle(fontSize: 20),
            ),
          ),
          title: Text(
            activity.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            _formatDutchWeekday(result.date) + ' ' +
                _formatDutchDate(result.date) + ' ' +
                result.date.year.toString() + ' · ' + activity.time +
                '\n' + detail,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: _green),
          onTap: () => _openSearchResult(result),
        ),
      ),
    );
  }

  void _openSearchResult(PlanningSearchResult result) {
    final items = widget.controller.activitiesFor(result.date);
    final index = items.indexWhere(
      (activity) => activity.id == result.activity.id,
    );
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _showWeek = false;
      _singleActivityMode = true;
      _focusedActivityIndex = index < 0 ? 0 : index;
    });
    widget.controller.selectDate(result.date);
  }

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

    final dayBadge = Container(
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
    );

    final dayInfo = Column(
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
    );

    final dayActions = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
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
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        dayBadge,
                        const SizedBox(width: 12),
                        Expanded(child: dayInfo),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerRight,
                      child: dayActions,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  dayBadge,
                  const SizedBox(width: 12),
                  Expanded(child: dayInfo),
                  dayActions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _activityDetail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(color: _ink, fontSize: 15, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleActivityView(
    BuildContext context,
    List<DayActivity> items,
  ) {
    final index = safeFocusedActivityIndex(
      _focusedActivityIndex,
      items.length,
    );
    final activity = items[index];
    final completedSteps =
        activity.stepDone.where((value) => value).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FocusedActivityAnnouncement(
              index: index,
              total: items.length,
              activityTitle: activity.title,
            ),
            const SizedBox(height: 15),
            Center(
              child: Text(
                activity.symbol,
                style: const TextStyle(fontSize: 48),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                activity.time,
                style: const TextStyle(
                  color: _green,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                activity.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (activity.photoPath.isNotEmpty &&
                File(activity.photoPath).existsSync()) ...[
              const SizedBox(height: 15),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(activity.photoPath),
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            _activityDetail('Wie?', activity.who),
            _activityDetail('Wat?', activity.what),
            _activityDetail('Waar?', activity.where),
            _activityDetail('Hoe?', activity.how),
            _activityDetail('Extra uitleg', activity.note),
            if (activity.steps.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 9),
              const Text(
                'Mijn kleine stappen',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 5),
                child: Text(
                  completedSteps.toString() + ' van ' +
                      activity.steps.length.toString() + ' afgevinkt',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              for (var stepIndex = 0;
                  stepIndex < activity.steps.length;
                  stepIndex++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  visualDensity: VisualDensity.compact,
                  value: stepIndex < activity.stepDone.length
                      ? activity.stepDone[stepIndex]
                      : false,
                  title: Text(
                    activity.steps[stepIndex],
                    style: const TextStyle(color: _ink, fontSize: 14),
                  ),
                  onChanged: (_) => widget.controller.toggleActivityStep(
                    activity.id,
                    stepIndex,
                  ),
                ),
            ],
            const SizedBox(height: 17),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => editActivity(
                    context,
                    widget.controller,
                    existing: activity,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Aanpassen'),
                ),
                OutlinedButton.icon(
                  onPressed: () => widget.controller.toggleActivity(activity.id),
                  icon: Icon(
                    activity.done
                        ? Icons.undo_rounded
                        : Icons.check_circle_outline_rounded,
                  ),
                  label: Text(
                    activity.done
                        ? 'Zet weer open'
                        : 'Markeer als afgerond',
                  ),
                ),
                SpeakButton(
                  text: activity.title + '. ' + activity.time +
                      '. Wie: ' + activity.who +
                      '. Wat: ' + activity.what +
                      '. Waar: ' + activity.where +
                      '. Hoe: ' + activity.how +
                      (activity.note.isEmpty ? '' : '. ' + activity.note) +
                      (activity.steps.isEmpty
                          ? ''
                          : '. Stappen: ' + activity.steps.join('. ')),
                  speechRate: widget.controller.preferences.speechRate,
                  enabled: widget.controller.preferences.speechEnabled,
                ),
              ],
            ),
            const Divider(height: 30),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: index > 0
                        ? () => setState(
                              () => _focusedActivityIndex = index - 1,
                            )
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Vorige'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: index < items.length - 1
                        ? () => setState(
                              () => _focusedActivityIndex = index + 1,
                            )
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('Volgende'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _singleActivityMode = false),
                icon: const Icon(Icons.view_agenda_outlined),
                label: const Text('Toon alle activiteiten'),
              ),
            ),
          ],
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
                      _selectDay(date.subtract(const Duration(days: 1))),
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
                      _selectDay(date.add(const Duration(days: 1))),
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
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _singleActivityMode = !_singleActivityMode;
                _focusedActivityIndex = 0;
              }),
              icon: Icon(
                _singleActivityMode
                    ? Icons.view_agenda_outlined
                    : Icons.filter_1_rounded,
              ),
              label: Text(
                _singleActivityMode
                    ? 'Toon alle activiteiten'
                    : 'Eén activiteit tegelijk',
              ),
            ),
          ),
        if (items.isNotEmpty && _singleActivityMode)
          _buildSingleActivityView(context, items),
        if (items.isNotEmpty && !_singleActivityMode)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _copyDayToDate(context, date),
              icon: const Icon(Icons.content_copy_rounded),
              label: const Text('Kopieer dit dagplan naar een andere datum'),
            ),
          ),
        if (items.isNotEmpty && !_singleActivityMode)
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
                  speechEnabled: widget.controller.preferences.speechEnabled,
                  toggle: () => widget.controller.toggleActivity(item.id),
                  toggleStep: (stepIndex) =>
                      widget.controller.toggleActivityStep(item.id, stepIndex),
                  edit: () => editActivity(context, widget.controller, existing: item),
                  delete: () => confirmDelete(context, widget.controller, item),
                  copy: () => _copyActivityToDate(context, date, item),
                  move: () => _moveActivityToDate(context, date, item),
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
              onPressed: () => _selectDay(DateTime.now()),
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
  const ActivityCard({
    super.key,
    required this.activity,
    required this.speechRate,
    required this.speechEnabled,
    required this.toggle,
    required this.toggleStep,
    required this.edit,
    required this.delete,
    required this.copy,
    required this.move,
    required this.reorderHandle,
  });

  final DayActivity activity;
  final double speechRate;
  final bool speechEnabled;
  final VoidCallback toggle;
  final ValueChanged<int> toggleStep;
  final VoidCallback edit;
  final VoidCallback delete;
  final VoidCallback copy;
  final VoidCallback move;
  final Widget reorderHandle;

  Widget _timeBadge() => Container(
        width: 55,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _greenPale,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          activity.time,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _green,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );

  Widget _activityContent(int completedSteps) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: edit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      activity.symbol,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        activity.title,
                        style: TextStyle(
                          color: activity.done ? _muted : _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          decoration: activity.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                if (activity.photoPath.isNotEmpty &&
                    File(activity.photoPath).existsSync()) ...[
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(activity.photoPath),
                      height: 110,
                      width: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                if (activity.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      activity.note,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 7),
                const Text(
                  'Tik om de vijf vragen te bekijken',
                  style: TextStyle(
                    color: _green,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (activity.steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Stappen: ' +
                  completedSteps.toString() +
                  ' van ' +
                  activity.steps.length.toString() +
                  ' klaar',
              style: const TextStyle(
                color: _green,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (var index = 0; index < activity.steps.length; index++)
              Row(
                children: [
                  Checkbox(
                    value: index < activity.stepDone.length
                        ? activity.stepDone[index]
                        : false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) => toggleStep(index),
                  ),
                  Expanded(
                    child: Text(
                      activity.steps[index],
                      style: const TextStyle(color: _ink, fontSize: 13),
                    ),
                  ),
                ],
              ),
          ],
        ],
      );

  String get _speechText =>
      activity.title +
      '. ' + activity.time +
      '. Wie: ' + activity.who +
      '. Wat: ' + activity.what +
      '. Waar: ' + activity.where +
      '. Hoe: ' + activity.how +
      (activity.steps.isEmpty
          ? ''
          : '. Stappen: ' + activity.steps.join('. '));

  Widget _speechButton() => SpeakButton(
        text: _speechText,
        speechRate: speechRate,
        enabled: speechEnabled,
      );

  Widget _completionButton() => IconButton(
        tooltip: activity.done ? 'Niet afgerond' : 'Markeer als afgerond',
        onPressed: toggle,
        icon: Icon(
          activity.done ? Icons.check_circle : Icons.circle_outlined,
          color: activity.done ? _green : _muted,
        ),
      );

  Widget _moreMenu() => PopupMenuButton<String>(
        tooltip: 'Meer opties',
        onSelected: (choice) {
          if (choice == 'edit') edit();
          if (choice == 'copy') copy();
          if (choice == 'move') move();
          if (choice == 'delete') delete();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('Bewerken')),
          PopupMenuItem(value: 'copy', child: Text('Kopieer naar datum')),
          PopupMenuItem(value: 'move', child: Text('Verplaatsen naar datum')),
          PopupMenuItem(value: 'delete', child: Text('Verwijderen')),
        ],
      );

  Widget _compactActions() => Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            reorderHandle,
            _speechButton(),
            _completionButton(),
            _moreMenu(),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final completedSteps = activity.stepDone.where((value) => value).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final timeBadge = _timeBadge();
            final content = _activityContent(completedSteps);

            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      timeBadge,
                      const SizedBox(width: 13),
                      Expanded(child: content),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _compactActions(),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                timeBadge,
                const SizedBox(width: 13),
                Expanded(child: content),
                reorderHandle,
                _speechButton(),
                _completionButton(),
                _moreMenu(),
              ],
            );
          },
        ),
      ),
    );
  }
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
  late final TextEditingController stepsText;
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
    stepsText = TextEditingController(text: item?.steps.join('\n') ?? '');
    symbol = item?.symbol ?? '📌';
    photoPath = item?.photoPath ?? '';
  }

  @override
  void dispose() {
    title.dispose(); time.dispose(); who.dispose(); what.dispose(); where.dispose(); how.dispose(); note.dispose(); stepsText.dispose();
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
    final nextSteps = parseActivitySteps(stepsText.text);
    final nextStepDone = nextSteps.map((step) {
      final oldIndex = old?.steps.indexOf(step) ?? -1;
      return old != null &&
              oldIndex >= 0 &&
              oldIndex < old.stepDone.length
          ? old.stepDone[oldIndex]
          : false;
    }).toList();
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
      steps: nextSteps,
      stepDone: nextStepDone,
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
                field(
                  stepsText,
                  'Stappenplan (optioneel)',
                  'Zet iedere kleine stap op een aparte regel.',
                  lines: 4,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Text(
                    'Maximaal 12 stappen. Je kunt ze straks één voor één afvinken.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
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
  const CalmPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  State<CalmPage> createState() => _CalmPageState();
}

class CalmStep {
  const CalmStep({required this.title, required this.description, required this.icon});
  final String title;
  final String description;
  final IconData icon;
}

class _PrikkelInzichtCard extends StatelessWidget {
  const _PrikkelInzichtCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _paper,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
    ),
    child: Row(
      children: [
        Icon(icon, color: _green, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CalmPageState extends State<CalmPage> {
  int step = 0;
  int _prikkelPeriode = 0;
  String _prikkelZoekterm = '';
  int _prikkelFilterNiveau = 0;
  int? selectedLevel;
  final noteController = TextEditingController();
  static const steps = [
    CalmStep(title: 'Voel de grond', description: 'Zet je voeten neer. Voel waar je voeten de grond raken.', icon: Icons.place_outlined),
    CalmStep(title: 'Kijk rustig om je heen', description: 'Noem voor jezelf drie dingen die je ziet. Je hoeft niets hardop te zeggen.', icon: Icons.remove_red_eye_outlined),
    CalmStep(title: 'Kies één kleine stap', description: 'Wat heb je nu nodig? Rust, hulp of verdergaan?', icon: Icons.spa_outlined),
  ];

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  Future<void> _saveMeasurement() async {
    final level = selectedLevel;
    if (level == null) return;
    await widget.controller.savePrikkelMeting(level, noteController.text);
    if (!mounted) return;
    setState(() {
      selectedLevel = null;
      noteController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Je meting is lokaal opgeslagen.')),
    );
  }

  Future<void> _bewerkPrikkelMeting(PrikkelMeting meting) async {
    final noteController = TextEditingController(text: meting.note);
    var selectedLevel = meting.level;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Meting bewerken'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hoeveel prikkels had je?'),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: selectedLevel,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 · Helemaal rustig')),
                    DropdownMenuItem(value: 2, child: Text('2 · Een beetje prikkels')),
                    DropdownMenuItem(value: 3, child: Text('3 · Best veel prikkels')),
                    DropdownMenuItem(value: 4, child: Text('4 · Erg veel prikkels')),
                    DropdownMenuItem(value: 5, child: Text('5 · Overprikkeld')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedLevel = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notitie',
                    hintText: 'Wat speelde er op dat moment?',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      await widget.controller.updatePrikkelMeting(
        meting.id,
        level: selectedLevel,
        note: noteController.text,
      );
    }
    noteController.dispose();
  }

  Future<void> _verwijderPrikkelMeting(PrikkelMeting meting) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Meting verwijderen?'),
        content: const Text(
          'Deze prikkelmeting en de bijbehorende notitie worden verwijderd. Dit kun je niet ongedaan maken.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.controller.deletePrikkelMeting(meting.id);
    }
  }

  Future<void> _toonPrikkelPuntDetails(
    BuildContext context,
    PrikkelGrafiekPunt point,
  ) async {
    final dateTitle = _prikkelPeriode == 2
        ? '${point.label} ${point.date.year}'
        : '${_formatDutchWeekday(point.date)} ${_formatDutchDate(point.date)}';
    final average = point.averageLevel;
    final metingen = prikkelMetingenVoorGrafiekPunt(
      widget.controller.prikkelMetingen,
      point,
      perMaand: _prikkelPeriode == 2,
    );
    const levelLabels = [
      'Helemaal rustig',
      'Een beetje prikkels',
      'Best veel prikkels',
      'Erg veel prikkels',
      'Overprikkeld',
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dateTitle),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (average == null)
                  const Text('Voor deze periode zijn nog geen metingen opgeslagen.')
                else ...[
                  Text(
                    'Gemiddeld prikkelniveau: ${average.toStringAsFixed(1)} van 5',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Aantal metingen: ${point.count}'),
                ],
                if (metingen.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Jouw metingen en notities',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...metingen.map((meting) {
                    final time = '${meting.createdAt.hour.toString().padLeft(2, '0')}:${meting.createdAt.minute.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _paper,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${time} · ${meting.level}/5 · ${levelLabels[meting.level - 1]}',
                              style: const TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              meting.note.trim().isEmpty
                                  ? 'Geen notitie toegevoegd.'
                                  : meting.note,
                              style: const TextStyle(color: _muted),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _bewerkPrikkelMeting(meting),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Bewerken'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _verwijderPrikkelMeting(meting),
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  label: const Text('Verwijderen'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  Widget _buildPrikkelInzichten() {
    final inzichten = berekenPrikkelInzichten(
      widget.controller.prikkelMetingen,
    );
    const weekdays = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];
    String levelText(double? level) =>
        level == null ? 'Nog niet genoeg gegevens' : '${level.toStringAsFixed(1)} / 5';
    String trendText;
    if (inzichten.recentAverage == null || inzichten.previousAverage == null) {
      trendText = 'Nog niet genoeg gegevens voor een vergelijking.';
    } else {
      final difference = inzichten.recentAverage! - inzichten.previousAverage!;
      if (difference.abs() < 0.05) {
        trendText = 'Je gemiddelde is ongeveer gelijk aan de vorige week.';
      } else if (difference < 0) {
        trendText = 'Je gemiddelde ligt ${(-difference).toStringAsFixed(1)} punt lager dan vorige week.';
      } else {
        trendText = 'Je gemiddelde ligt ${difference.toStringAsFixed(1)} punt hoger dan vorige week.';
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Persoonlijke inzichten', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Een overzicht van patronen in je eigen metingen.', style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _PrikkelInzichtItem(label: 'Metingen bijgehouden', value: '${inzichten.totalMeasurements}'),
                _PrikkelInzichtItem(label: 'Gemiddeld niveau', value: levelText(inzichten.averageLevel)),
                _PrikkelInzichtItem(
                  label: 'Meest gekozen niveau',
                  value: inzichten.mostCommonLevel == null
                      ? 'Nog geen metingen'
                      : '${inzichten.mostCommonLevel} · ${prikkelNiveaus[inzichten.mostCommonLevel! - 1]}',
                ),
                _PrikkelInzichtItem(
                  label: 'Hoogste gemiddelde dag',
                  value: inzichten.highestAverageWeekday == null
                      ? 'Nog geen metingen'
                      : '${weekdays[inzichten.highestAverageWeekday! - 1]} · ${levelText(inzichten.highestAverageWeekdayLevel)}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(trendText, style: const TextStyle(color: _muted, height: 1.4)),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'Gemiddelde per week · laatste 8 weken',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...maakPrikkelWeekTrend(widget.controller.prikkelMetingen)
                .map((week) {
              final datum = week.weekStart;
              final label =
                  '${datum.day.toString().padLeft(2, '0')}-${datum.month.toString().padLeft(2, '0')}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: (week.averageLevel ?? 0) / 5,
                          minHeight: 9,
                          backgroundColor: _paper,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 76,
                      child: Text(
                        week.averageLevel == null
                            ? 'Geen data'
                            : '${week.averageLevel!.toStringAsFixed(1)} / 5 · ${week.count}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: _muted, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 6),
            const Text('Dit zijn beschrijvingen van je geregistreerde metingen, geen voorspellingen of medische conclusies.', style: TextStyle(color: _muted, fontSize: 11, height: 1.35)),
          ],
        ),
      ),
    );
  }

  Widget _buildPrikkelGeschiedenis() {
    final metingen = filterPrikkelMetingen(
      widget.controller.prikkelMetingen,
      query: _prikkelZoekterm,
      niveau: _prikkelFilterNiveau,
    );
    final heeftFilters = _prikkelZoekterm.trim().isNotEmpty ||
        _prikkelFilterNiveau != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Prikkelgeschiedenis', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          onChanged: (value) => setState(() => _prikkelZoekterm = value),
          decoration: InputDecoration(
            labelText: 'Zoek in je metingen',
            hintText: 'Zoek op notitie, datum of niveau',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _prikkelZoekterm.isEmpty ? null : IconButton(
              tooltip: 'Zoekopdracht wissen',
              onPressed: () => setState(() => _prikkelZoekterm = ''),
              icon: const Icon(Icons.clear),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _prikkelFilterNiveau,
                decoration: const InputDecoration(labelText: 'Prikkelniveau', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Alle niveaus')),
                  DropdownMenuItem(value: 1, child: Text('1 · Helemaal rustig')),
                  DropdownMenuItem(value: 2, child: Text('2 · Een beetje prikkels')),
                  DropdownMenuItem(value: 3, child: Text('3 · Best veel prikkels')),
                  DropdownMenuItem(value: 4, child: Text('4 · Erg veel prikkels')),
                  DropdownMenuItem(value: 5, child: Text('5 · Overprikkeld')),
                ],
                onChanged: (value) => setState(() => _prikkelFilterNiveau = value ?? 0),
              ),
            ),
            if (heeftFilters) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  _prikkelZoekterm = '';
                  _prikkelFilterNiveau = 0;
                }),
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Wissen'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text('${metingen.length} ${metingen.length == 1 ? 'meting' : 'metingen'} gevonden', style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 6),
        if (widget.controller.prikkelMetingen.isEmpty)
          const Text('Je hebt nog geen metingen opgeslagen.', style: TextStyle(color: _muted))
        else if (metingen.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Geen metingen gevonden. Pas je zoekopdracht of filter aan.', style: TextStyle(color: _muted)),
          )
        else
          ...metingen.map((measurement) {
            final date = measurement.createdAt;
            final dateLabel = '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year} om ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(backgroundColor: _greenPale, child: Text('${measurement.level}', style: const TextStyle(color: _green, fontWeight: FontWeight.w700))),
                      title: Text(prikkelNiveaus[measurement.level - 1]),
                      subtitle: Text(measurement.note.isEmpty ? dateLabel : '$dateLabel\\n${measurement.note}'),
                      isThreeLine: measurement.note.isNotEmpty,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _bewerkPrikkelMeting(measurement),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Bewerken'),
                        ),
                        TextButton.icon(
                          onPressed: () => _verwijderPrikkelMeting(measurement),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Verwijderen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPrikkelWeekChart() {
    final points = maakPrikkelGrafiekPunten(
      widget.controller.prikkelMetingen,
      periode: _prikkelPeriode,
    );
    final hasMeasurements = points.any((point) => point.count > 0);
    final vergelijking = vergelijkPrikkelPeriodes(
      widget.controller.prikkelMetingen,
      periode: _prikkelPeriode,
    );
    final highestPoint = hoogstePrikkelGrafiekPunt(points);
    final highestDateLabel = highestPoint == null
        ? ''
        : (_prikkelPeriode == 2
            ? '${highestPoint.label} ${highestPoint.date.year}'
            : '${highestPoint.date.day}-${highestPoint.date.month}');
    final title = _prikkelPeriode == 0
        ? 'Prikkels deze week'
        : (_prikkelPeriode == 1
            ? 'Prikkels deze maand'
            : 'Prikkels dit jaar');
    final subtitle = _prikkelPeriode == 0
        ? 'Gemiddeld niveau per dag · afgelopen 7 dagen'
        : (_prikkelPeriode == 1
            ? 'Gemiddeld niveau per dag · afgelopen 30 dagen'
            : 'Gemiddeld niveau per maand · afgelopen 12 maanden');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Week')),
                ButtonSegment(value: 1, label: Text('Maand')),
                ButtonSegment(value: 2, label: Text('Jaar')),
              ],
              selected: {_prikkelPeriode},
              onSelectionChanged: (selection) {
                setState(() => _prikkelPeriode = selection.first);
              },
              showSelectedIcon: false,
            ),
            const SizedBox(height: 14),
            if (hasMeasurements) ...[
              Builder(
                builder: (context) {
                  final totalMeasurements = points.fold<int>(
                    0,
                    (total, point) => total + point.count,
                  );
                  final weightedTotal = points.fold<double>(
                    0,
                    (total, point) =>
                        total + (point.averageLevel ?? 0) * point.count,
                  );
                  final overallAverage =
                      weightedTotal / totalMeasurements;
                  return Row(
                    children: [
                      Expanded(
                        child: _PrikkelInzichtCard(
                          label: 'Gemiddeld niveau',
                          value: '${overallAverage.toStringAsFixed(1)} / 5',
                          icon: Icons.insights_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PrikkelInzichtCard(
                          label: 'Aantal metingen',
                          value: totalMeasurements.toString(),
                          icon: Icons.checklist_outlined,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              if (highestPoint != null)
                Text(
                  'Hoogste gemiddelde: ${highestPoint.averageLevel!.toStringAsFixed(1)} / 5 · $highestDateLabel (${highestPoint.count} metingen)',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 5),
              Text(
                vergelijking.vorigGemiddelde == null
                    ? 'Vergelijking: nog geen metingen in de vorige periode.'
                    : 'Vorige periode: ${vergelijking.vorigGemiddelde!.toStringAsFixed(1)} / 5 (${vergelijking.vorigAantal} metingen) · nu: ${vergelijking.huidigGemiddelde!.toStringAsFixed(1)} / 5',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (!hasMeasurements)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  'Zodra je metingen opslaat, verschijnt hier je overzicht.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: points.length * (_prikkelPeriode == 0 ? 42.0 : 34.0),
                  height: 158,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(points.length, (index) {
                      final point = points[index];
                      final average = point.averageLevel;
                      final barHeight = average == null ? 0.0 : average * 20;
                      final dateLabel = '${point.date.day}-${point.date.month}';
                      return Expanded(
                        child: Semantics(
                          button: true,
                          label: average == null
                              ? '$dateLabel: geen metingen. Tik voor details.'
                              : '$dateLabel: gemiddeld ${average.toStringAsFixed(1)} van 5, ${point.count} metingen. Tik voor details.',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _toonPrikkelPuntDetails(context, point),
                            child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 112,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: average == null
                                      ? Container(
                                          width: 12,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: _line,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        )
                                      : Container(
                                          width: _prikkelPeriode == 0 ? 22 : 16,
                                          height: barHeight,
                                          alignment: Alignment.topCenter,
                                          decoration: BoxDecoration(
                                            color: _green,
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: _prikkelPeriode == 0
                                              ? Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    average.toStringAsFixed(1),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                )
                                              : null,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              SizedBox(
                                height: 16,
                                child: Text(
                                  point.label,
                                  style: const TextStyle(color: _muted, fontSize: 10),
                                ),
                              ),
                              Text(
                                _prikkelPeriode == 2
                                    ? point.date.year.toString()
                                    : (point.label.isEmpty ? ' ' : dateLabel),
                                style: const TextStyle(color: _ink, fontSize: 9),
                              ),
                            ],
                          ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Een hoger getal betekent dat je gemiddeld meer prikkels hebt aangegeven. Dit overzicht is bedoeld voor zelfinzicht, niet als medische beoordeling.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Even rust',
    subtitle: 'Een rustig moment. Je hoeft niets goed te doen.',
    child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(color: _greenPale, borderRadius: BorderRadius.circular(23)),
          child: Column(children: [
            CircleAvatar(radius: 33, backgroundColor: Colors.white, child: Icon(steps[step].icon, color: _green, size: 29)),
            const SizedBox(height: 18),
            Text('STAP ${step + 1} VAN 3', style: const TextStyle(color: _green, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
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
        const SizedBox(height: 22),
        const Text('Prikkelmeter', style: TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Hoeveel prikkels ervaar je op dit moment? Kies wat bij je past. Je hoeft niets te kiezen of uit te leggen.', style: TextStyle(color: _muted, height: 1.45)),
        const SizedBox(height: 13),
        ...List.generate(5, (index) {
          final level = index + 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              button: true,
              selected: selectedLevel == level,
              label: 'Niveau $level: ${prikkelNiveaus[index]}',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  backgroundColor: selectedLevel == level ? _greenPale : Colors.white,
                  side: BorderSide(color: selectedLevel == level ? _green : _line, width: selectedLevel == level ? 2 : 1),
                ),
                onPressed: () => setState(() => selectedLevel = level),
                child: Row(children: [
                  CircleAvatar(radius: 14, backgroundColor: _greenPale, child: Text('$level', style: const TextStyle(color: _green, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(prikkelNiveaus[index], style: const TextStyle(color: _ink))),
                  if (selectedLevel == level) const Icon(Icons.check_circle, color: _green),
                ]),
              ),
            ),
          );
        }),
        TextField(
          controller: noteController,
          maxLines: 2,
          maxLength: 240,
          decoration: const InputDecoration(labelText: 'Notitie (optioneel)', hintText: 'Bijvoorbeeld: veel geluid om me heen'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: selectedLevel == null ? null : _saveMeasurement,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Meting opslaan'),
        ),
        const SizedBox(height: 18),
        _buildPrikkelWeekChart(),
        const SizedBox(height: 14),
        _buildPrikkelInzichten(),
        const SizedBox(height: 18),
        _buildPrikkelGeschiedenis(),
        const SizedBox(height: 12),
        const Card(child: Padding(padding: EdgeInsets.all(17), child: Text('Je prikkelniveau is persoonlijk en kan per moment verschillen. Deze meter is bedoeld voor zelfinzicht, niet als medische beoordeling. Je gegevens blijven op dit apparaat.', style: TextStyle(color: _muted, height: 1.45)))),
        if (widget.controller.storageNotice != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: StorageNotice(message: widget.controller.storageNotice!)),
      ]),
    )),
  );
}

class _PrikkelInzichtItem extends StatelessWidget {
  const _PrikkelInzichtItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ),
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
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
}

String _backupErrorMessage(Object error, {required bool importing}) {
  if (error is FormatException) return error.message.toString();
  if (error is ArgumentError) return error.message.toString();
  return importing
      ? 'De back-up kon niet worden teruggezet. Controleer het bestand en probeer opnieuw.'
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
    if (!context.mounted) return;
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
                  Icon(Icons.privacy_tip_outlined, color: _green),
                  SizedBox(width: 10),
                  Text('Privacy en jouw gegevens', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Je dagplannen, dagindelingen, weekritme, steunplan en instellingen worden op dit apparaat bewaard. MoodPress gebruikt geen account of cloud.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Je stemming-check-in is tijdelijk en wordt niet bewaard. Activiteitfoto’s blijven lokaal en kunnen in je versleutelde back-up terechtkomen.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 8),
                const Text(
                  'MoodPress is een prototype. Gebruik voor testdoeleinden alleen fictieve gegevens en deel je apparaat alleen met mensen die deze informatie mogen zien.',
                  style: TextStyle(color: _muted, height: 1.45),
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
                  Icon(Icons.info_outline_rounded, color: _green),
                  SizedBox(width: 10),
                  Text('Waar MoodPress niet voor is', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'MoodPress helpt bij dagstructuur. Het stelt geen diagnose en vervangt geen behandeling, begeleider of professionele hulp.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 8),
                const Text(
                  'MoodPress is geen crisisdienst. Als je direct gevaar loopt, bel 112. Neem bij behoefte aan hulp contact op met iemand die je vertrouwt of met je hulpverlener.',
                  style: TextStyle(color: _muted, height: 1.45),
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
                const Text('Kies of je voorlezen wilt gebruiken en stel daarna de snelheid in.', style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Voorlezen in de app'),
                  subtitle: const Text('Je kunt dit altijd weer aanzetten'),
                  value: controller.preferences.speechEnabled,
                  onChanged: controller.setSpeechEnabled,
                ),
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
                    onPressed: controller.preferences.speechEnabled
                        ? () => SpeakButtonPreview.play(context, controller.preferences.speechRate)
                        : null,
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
                const Row(children: [
                  Icon(Icons.delete_forever_outlined, color: _green),
                  SizedBox(width: 10),
                  Text('Jouw gegevens verwijderen', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 7),
                const Text(
                  'Verwijder je lokale planningen, dagindelingen, weekritme, steunplan, voorkeuren en activiteitfoto’s van dit apparaat. Eerder gemaakte back-ups worden niet verwijderd.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Alle gegevens verwijderen?'),
                        content: const Text(
                          'Dit verwijdert je MoodPress-gegevens en activiteitfoto’s van dit apparaat. Dit kan niet ongedaan worden gemaakt. Een losse back-up die je eerder hebt opgeslagen, blijft bestaan. Weet je het zeker?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('Annuleren'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Verwijder mijn gegevens'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    try {
                      await controller.deleteAllLocalData();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Je lokale MoodPress-gegevens zijn verwijderd.')),
                      );
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Niet alle gegevens konden worden verwijderd. Probeer het opnieuw.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Wis alle gegevens op dit apparaat'),
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
  const SpeakButton({
    super.key,
    required this.text,
    this.speechRate = 0.42,
    this.enabled = true,
  });
  final String text;
  final double speechRate;
  final bool enabled;

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  final FlutterTts _tts = FlutterTts();
  bool speaking = false;

  @override
  void didUpdateWidget(covariant SpeakButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled && speaking) {
      _tts.stop();
      speaking = false;
    }
  }

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
        tooltip: !widget.enabled
            ? 'Voorlezen staat uit in de instellingen'
            : speaking
                ? 'Stop voorlezen'
                : 'Lees voor',
        onPressed: widget.enabled ? _toggle : null,
        icon: Icon(
          !widget.enabled
              ? Icons.volume_off_outlined
              : speaking
                  ? Icons.stop_circle_outlined
                  : Icons.volume_up_outlined,
          color: widget.enabled ? _green : _muted,
        ),
      );
}
