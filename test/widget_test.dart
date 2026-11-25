import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpress/main.dart';

void main() {
  test('planning search checks all saved days and activity details', () {
    final plans = <String, List<DayActivity>>{
      '2026-11-25': [
        DayActivity(
          id: 'pharmacy',
          title: 'Apotheek bezoeken',
          time: '10:30',
          who: 'Samen met Sam',
          what: 'Medicatie ophalen',
          where: 'Apotheek in de buurt',
          how: 'Rustig wandelen',
          note: 'Neem de boodschappenlijst mee',
          steps: ['Sleutels pakken', 'Naar buiten gaan'],
        ),
      ],
      '2026-11-26': [
        DayActivity(
          id: 'meeting',
          title: 'Werkafspraak',
          time: '13:00',
          who: 'Met het team',
          what: 'Overleg over de planning',
          where: 'Op kantoor',
          how: 'Aantekeningen meenemen',
        ),
      ],
    };

    expect(
      searchPlanningActivities(plans, 'APOTHEEK')
          .map((result) => result.activity.id)
          .toList(),
      ['pharmacy'],
    );
    expect(
      searchPlanningActivities(plans, 'medicatie boodschappenlijst')
          .map((result) => result.activity.id)
          .toList(),
      ['pharmacy'],
    );
    expect(
      searchPlanningActivities(plans, 'donderdag 26 november')
          .map((result) => result.activity.id)
          .toList(),
      ['meeting'],
    );
    expect(
      searchPlanningActivities(plans, '13:00')
          .single.activity.id,
      'meeting',
    );
    expect(searchPlanningActivities(plans, '   '), isEmpty);
    expect(searchPlanningActivities(plans, 'bestaat niet'), isEmpty);
  });

  testWidgets('branded splash screen is shown while local data loads', (tester) async {
    final controller = MoodPressController()
      ..preferences = const MoodPressPreferences(hasSeenWelcome: true);
    await tester.pumpWidget(MoodPressApp(controller: controller));

    expect(find.text('MoodPress'), findsOneWidget);
    expect(find.text('Rust en overzicht in je dag.'), findsOneWidget);
    expect(find.text('Je omgeving wordt klaargemaakt…'), findsOneWidget);
    expect(find.byType(MoodPressSplashScreen), findsOneWidget);

    controller.ready = true;
    controller.notifyListeners();
    await tester.pump();

    expect(find.byType(MoodPressSplashScreen), findsNothing);
    expect(find.byType(MoodPressShell), findsOneWidget);
  });

  testWidgets('first-time welcome can be completed and is not shown again', (tester) async {
    final controller = MoodPressController()..ready = true;
    await tester.pumpWidget(MoodPressApp(controller: controller));

    expect(find.byType(MoodPressWelcomeScreen), findsOneWidget);
    expect(find.text('Welkom bij MoodPress'), findsOneWidget);
    expect(find.text('Maak je dag overzichtelijk'), findsOneWidget);
    expect(find.text('Kleine stappen zijn genoeg'), findsOneWidget);
    expect(find.text('Ruimte voor rust'), findsOneWidget);

    await tester.ensureVisible(find.text('Aan de slag'));
    await tester.tap(find.text('Aan de slag'));
    await tester.pumpAndSettle();

    expect(controller.preferences.hasSeenWelcome, isTrue);
    expect(find.byType(MoodPressWelcomeScreen), findsNothing);
    expect(find.byType(MoodPressShell), findsOneWidget);
  });

  testWidgets('first-time welcome can be skipped', (tester) async {
    final controller = MoodPressController()..ready = true;
    await tester.pumpWidget(MoodPressApp(controller: controller));

    await tester.ensureVisible(find.text('Overslaan'));
    await tester.tap(find.text('Overslaan'));
    await tester.pumpAndSettle();

    expect(controller.preferences.hasSeenWelcome, isTrue);
    expect(find.byType(MoodPressWelcomeScreen), findsNothing);
    expect(find.byType(MoodPressShell), findsOneWidget);
  });

  testWidgets('Ctrl plus number opens each main section on desktop', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MoodPressController();
    await tester.pumpWidget(
      MaterialApp(home: MoodPressShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    Future<void> pressControlNumber(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await pressControlNumber(LogicalKeyboardKey.digit2);
    expect(find.text('Mijn planning').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.digit3);
    expect(find.text('Even rust').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.digit4);
    expect(find.text('Mijn steun').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.digit5);
    expect(find.text('Instellingen').last, findsOneWidget);

    expect(find.text('Privacy en jouw gegevens'), findsOneWidget);
    expect(find.textContaining('MoodPress gebruikt geen account of cloud.'), findsOneWidget);
    expect(find.textContaining('Je stemming-check-in is tijdelijk en wordt niet bewaard.'), findsOneWidget);
    expect(find.text('Waar MoodPress niet voor is'), findsOneWidget);
    expect(find.textContaining('MoodPress is geen crisisdienst.'), findsOneWidget);
    expect(find.textContaining('Als je direct gevaar loopt, bel 112.'), findsOneWidget);
    expect(find.text('Wis alle gegevens op dit apparaat'), findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.numpad2);
    expect(find.text('Mijn planning').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.numpad3);
    expect(find.text('Even rust').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.numpad4);
    expect(find.text('Mijn steun').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.numpad5);
    expect(find.text('Instellingen').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.numpad1);
    expect(find.text('DIT IS JE VOLGENDE STAP').last, findsOneWidget);

    await pressControlNumber(LogicalKeyboardKey.digit1);
    expect(find.text('DIT IS JE VOLGENDE STAP').last, findsOneWidget);
  });

  testWidgets('in-app reminder switch can be enabled and disabled in settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MoodPressController()
      ..ready = true
      ..preferences = const MoodPressPreferences(hasSeenWelcome: true);
    await tester.pumpWidget(MoodPressApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final reminderLabel = find.text('Herinneringen in de app');
    await tester.ensureVisible(reminderLabel);
    final reminderTile = find.ancestor(
      of: reminderLabel,
      matching: find.byType(SwitchListTile),
    );
    expect(controller.preferences.inAppRemindersEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(reminderTile).value, isFalse);

    // Use the real app root so controller notifications rebuild the visible
    // switch exactly as they do when MoodPress is running normally. Call the
    // tile callback directly: Flutter's compact switch hit target can be
    // unreliable in headless CI pointer tests.
    tester.widget<SwitchListTile>(reminderTile).onChanged!(true);
    expect(controller.preferences.inAppRemindersEnabled, isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(reminderTile).value, isTrue);

    tester.widget<SwitchListTile>(reminderTile).onChanged!(false);
    expect(controller.preferences.inAppRemindersEnabled, isFalse);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(reminderTile).value, isFalse);
  });

  testWidgets('speech can be switched off and on in settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MoodPressController()
      ..ready = true
      ..preferences = const MoodPressPreferences(hasSeenWelcome: true);
    await tester.pumpWidget(MoodPressApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final label = find.text('Voorlezen in de app');
    await tester.ensureVisible(label);
    final tileFinder = find.ancestor(
      of: label,
      matching: find.byType(SwitchListTile),
    );
    expect(controller.preferences.speechEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(tileFinder).value, isTrue);

    tester.widget<SwitchListTile>(tileFinder).onChanged!(false);
    expect(controller.preferences.speechEnabled, isFalse);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tileFinder).value, isFalse);

    tester.widget<SwitchListTile>(tileFinder).onChanged!(true);
    expect(controller.preferences.speechEnabled, isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tileFinder).value, isTrue);
  });

  testWidgets('canceling local data deletion keeps the settings screen unchanged', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MoodPressController();
    await tester.pumpWidget(
      MaterialApp(home: MoodPressShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final deleteButton = find.text('Wis alle gegevens op dit apparaat');
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Alle gegevens verwijderen?'), findsOneWidget);
    expect(find.text('Verwijder mijn gegevens'), findsOneWidget);

    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(find.text('Alle gegevens verwijderen?'), findsNothing);
    expect(deleteButton, findsOneWidget);
  });

  testWidgets('focused activity is announced as a live screen-reader heading', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FocusedActivityAnnouncement(
            index: 1,
            total: 4,
            activityTitle: 'Naar buiten gaan',
          ),
        ),
      ),
    );

    final node = tester.getSemantics(
      find.byType(FocusedActivityAnnouncement),
    );
    expect(node.label, 'Activiteit 2 van 4: Naar buiten gaan');
    expect(node.flagsCollection.isHeader, isTrue);
    expect(node.flagsCollection.isLiveRegion, isTrue);
    semanticsHandle.dispose();
  });


  test('in-app reminders stay optional by default and restore safely', () {
    const defaults = MoodPressPreferences();
    expect(defaults.inAppRemindersEnabled, isFalse);
    expect(defaults.hasSeenWelcome, isFalse);

    final olderPreferences = MoodPressPreferences.fromJson({
      'textScale': 1.0,
      'speechRate': 0.42,
      'reduceMotion': false,
    });
    expect(olderPreferences.inAppRemindersEnabled, isFalse);
    expect(olderPreferences.hasSeenWelcome, isTrue);

    final enabledPreferences = MoodPressPreferences.fromJson({
      ...defaults.toJson(),
      'inAppRemindersEnabled': true,
    });
    expect(enabledPreferences.inAppRemindersEnabled, isTrue);
    expect(
      MoodPressPreferences.fromJson(enabledPreferences.toJson())
          .inAppRemindersEnabled,
      isTrue,
    );
  });

  test('backup files encrypt data and require the correct password', () async {
    final source = <String, dynamic>{
      'app': 'MoodPress',
      'dataVersion': 1,
      'privateNote': 'Dit is een persoonlijke notitie.',
    };

    final bytes = await encryptMoodPressBackup(source, 'mijn-veilig-wachtwoord');

    expect(utf8.decode(bytes), isNot(contains('persoonlijke notitie')));

    final restored = await decryptMoodPressBackup(
      bytes,
      'mijn-veilig-wachtwoord',
    );
    expect(restored['app'], 'MoodPress');
    expect(restored['dataVersion'], 1);
    expect(restored['privateNote'], 'Dit is een persoonlijke notitie.');

    await expectLater(
      decryptMoodPressBackup(bytes, 'een-andere-wachtwoordzin'),
      throwsA(isA<FormatException>()),
    );
  });

  test('backup rejects encrypted data that has been changed', () async {
    final source = <String, dynamic>{
      'app': 'MoodPress',
      'dataVersion': 1,
      'privateNote': 'Deze tekst moet beschermd blijven.',
    };
    final original = await encryptMoodPressBackup(
      source,
      'mijn-veilig-wachtwoord',
    );
    const header = 'MOODPRESS_BACKUP_V1\n';
    final headerLength = utf8.encode(header).length;
    final envelope = jsonDecode(
      utf8.decode(original.sublist(headerLength)),
    ) as Map<String, dynamic>;
    final cipherText = base64Decode(envelope['cipherText'] as String);
    cipherText[0] ^= 1;
    envelope['cipherText'] = base64Encode(cipherText);
    final tampered = Uint8List.fromList([
      ...utf8.encode(header),
      ...utf8.encode(jsonEncode(envelope)),
    ]);

    await expectLater(
      decryptMoodPressBackup(tampered, 'mijn-veilig-wachtwoord'),
      throwsA(isA<FormatException>()),
    );
  });

  test('backup rejects a file with an unknown header', () async {
    await expectLater(
      decryptMoodPressBackup(
        Uint8List.fromList(utf8.encode('NOT_A_MOODPRESS_BACKUP')),
        'mijn-veilig-wachtwoord',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('backup encryption rejects passwords that are too short', () async {
    await expectLater(
      encryptMoodPressBackup(
        {'app': 'MoodPress', 'dataVersion': 1},
        'kort',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('activity, template and preferences ignore fields with wrong data types', () {
    final activity = DayActivity.fromJson({
      'id': 42,
      'title': false,
      'time': ['10:00'],
      'who': null,
      'done': 'yes',
      'steps': ['Eerste stap'],
      'stepDone': [true],
    });
    expect(activity.id, isNotEmpty);
    expect(activity.title, 'Nieuwe activiteit');
    expect(activity.time, '09:00');
    expect(activity.who, '');
    expect(activity.done, isFalse);
    expect(activity.steps, ['Eerste stap']);
    expect(activity.stepDone, [true]);

    final template = DayTemplate.fromJson({
      'id': 99,
      'name': false,
      'activities': 'geen lijst',
    });
    expect(template.id, isNotEmpty);
    expect(template.name, 'Dagindeling');
    expect(template.activities, isEmpty);

    final preferences = MoodPressPreferences.fromJson({
      'reduceMotion': 'true',
      'inAppRemindersEnabled': 1,
      'speechEnabled': null,
    });
    expect(preferences.reduceMotion, isFalse);
    expect(preferences.inAppRemindersEnabled, isFalse);
    expect(preferences.speechEnabled, isTrue);
  });

  test('restoring malformed steps keeps each progress value with its original step', () {
    final restored = DayActivity.fromJson({
      'id': 'mixed-steps',
      'title': 'Activiteit',
      'time': '10:00',
      'steps': ['Eerste stap', 42, 'Derde stap'],
      'stepDone': [true, false, 'ongeldig'],
    });

    expect(restored.steps, ['Eerste stap', 'Derde stap']);
    expect(restored.stepDone, [true, false]);
  });

  test('activity data can be saved and restored', () {
    final original = DayActivity(
      id: 'activity-1',
      title: 'Naar de winkel',
      time: '10:30',
      who: 'Ik en begeleider',
      what: 'Boodschappen doen',
      where: 'De supermarkt',
      how: 'Eerst jas pakken, dan samen lopen',
      note: 'Rustig tempo',
      symbol: '🛒',
      photoPath: '/local/moodpress/winkel.jpg',
      done: true,
      steps: ['Jas pakken', 'Tas meenemen', 'Naar de winkel lopen'],
      stepDone: [true, false, true],
    );

    final restored = DayActivity.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.time, original.time);
    expect(restored.who, original.who);
    expect(restored.what, original.what);
    expect(restored.where, original.where);
    expect(restored.how, original.how);
    expect(restored.symbol, '🛒');
    expect(restored.photoPath, '/local/moodpress/winkel.jpg');
    expect(restored.done, isTrue);
    expect(restored.steps, ['Jas pakken', 'Tas meenemen', 'Naar de winkel lopen']);
    expect(restored.stepDone, [true, false, true]);
  });
  
  test('activity steps are parsed as short non-empty lines with a maximum of 12', () {
    final parsed = parseActivitySteps(
      '  Jas pakken  \n\nTas meenemen\n Naar buiten gaan \n',
    );
    expect(parsed, ['Jas pakken', 'Tas meenemen', 'Naar buiten gaan']);

    final tooMany = List<String>.generate(14, (index) => 'Stap ' + (index + 1).toString())
        .join('\n');
    expect(parseActivitySteps(tooMany), hasLength(12));
  });

  test('restored activity data never contains more than 12 steps', () {
    final restored = DayActivity.fromJson({
      'id': 'too-many-steps',
      'title': 'Activiteit',
      'time': '10:00',
      'steps': List<String>.generate(15, (index) => 'Stap ${index + 1}'),
      'stepDone': List<bool>.filled(15, true),
    });

    expect(restored.steps, hasLength(12));
    expect(restored.steps.last, 'Stap 12');
    expect(restored.stepDone, List<bool>.filled(12, true));
  });

  test('single-activity view keeps its selected index within the day plan', () {
    expect(safeFocusedActivityIndex(2, 5), 2);
    expect(safeFocusedActivityIndex(-4, 5), 0);
    expect(safeFocusedActivityIndex(20, 5), 4);
    expect(safeFocusedActivityIndex(0, 0), 0);
  });

  test('activity steps can be checked independently', () {
    final activity = DayActivity(
      id: 'steps',
      title: 'Naar buiten gaan',
      time: '10:00',
      steps: ['Jas pakken', 'Sleutels pakken', 'Deur sluiten'],
    );

    expect(toggleDayActivityStep(activity, 1), isTrue);
    expect(activity.stepDone, [false, true, false]);
    expect(toggleDayActivityStep(activity, 1), isTrue);
    expect(activity.stepDone, [false, false, false]);
    expect(toggleDayActivityStep(activity, 9), isFalse);
  });

  test('accessibility preferences can be saved and restored', () {
    const original = MoodPressPreferences(textScale: 1.3, speechRate: 0.5, reduceMotion: true);
    final restored = MoodPressPreferences.fromJson(original.toJson());

    expect(restored.textScale, 1.3);
    expect(restored.speechRate, 0.5);
    expect(restored.reduceMotion, isTrue);
    expect(restored.inAppRemindersEnabled, isFalse);
  });

  test('in-app reminders can be enabled and survive preference restoration', () {
    const original = MoodPressPreferences(inAppRemindersEnabled: true);
    final restored = MoodPressPreferences.fromJson(original.toJson());

    expect(restored.inAppRemindersEnabled, isTrue);
  });

  test('older preferences keep reminders switched off by default', () {
    final restored = MoodPressPreferences.fromJson({
      'textScale': 1.15,
      'speechRate': 0.42,
    });

    expect(restored.inAppRemindersEnabled, isFalse);
  });

  test('activity reminder is due only at its planned minute and when unfinished', () {
    final activity = DayActivity(
      id: 'reminder-1',
      title: 'Ontbijten',
      time: '08:30',
    );

    expect(isActivityDueAt(activity, DateTime(2026, 11, 25, 8, 30)), isTrue);
    expect(isActivityDueAt(activity, DateTime(2026, 11, 25, 8, 31)), isFalse);
    expect(
      isActivityDueAt(
        DayActivity(id: 'done', title: 'Klaar', time: '08:30', done: true),
        DateTime(2026, 11, 25, 8, 30),
      ),
      isFalse,
    );
    expect(
      isActivityDueAt(
        DayActivity(id: 'bad-time', title: 'Ongeldig', time: 'later'),
        DateTime(2026, 11, 25, 8, 30),
      ),
      isFalse,
    );
    expect(
      isActivityDueAt(
        DayActivity(id: 'invalid-hour', title: 'Ongeldig uur', time: '25:30'),
        DateTime(2026, 11, 25, 8, 30),
      ),
      isFalse,
    );
    expect(
      isActivityDueAt(
        DayActivity(id: 'invalid-minute', title: 'Ongeldige minuut', time: '08:90'),
        DateTime(2026, 11, 25, 8, 30),
      ),
      isFalse,
    );
  });

  test('accessibility preferences stay within supported limits', () {
    final restored = MoodPressPreferences.fromJson({
      'textScale': 4.0,
      'speechRate': 0.05,
    });

    expect(restored.textScale, 1.4);
    expect(restored.speechRate, 0.3);
    expect(restored.reduceMotion, isFalse);
  });

  test('day templates can be saved and restored', () {
    final original = DayTemplate(
      id: 'template-1',
      name: 'Werkdag',
      activities: [
        DayActivity(
          id: 'activity-1',
          title: 'Naar werk',
          time: '08:30',
          who: 'Ik en begeleider',
          what: 'Naar mijn werk gaan',
          where: 'Werk',
          how: 'Eerst jas pakken, dan vertrekken',
          done: true,
        ),
      ],
    );

    final restored = DayTemplate.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.activities.single.title, 'Naar werk');
    expect(restored.activities.single.how, 'Eerst jas pakken, dan vertrekken');
  });

  test('using a day template creates fresh unfinished activities', () {
    final template = DayTemplate(
      id: 'template-2',
      name: 'Rustige dag',
      activities: [
        DayActivity(
          id: 'old-id',
          title: 'Ontbijten',
          time: '08:00',
          what: 'Ontbijt eten',
          done: true,
        ),
      ],
    );

    final applied = template.createActivities();

    expect(applied.single.title, 'Ontbijten');
    expect(applied.single.done, isFalse);
    expect(applied.single.id, isNot('old-id'));
  });

  test('restoring a backup template safely handles invalid id and name types', () {
    final restored = buildRestoredDayTemplate(
      {'id': 42, 'name': false},
      [DayActivity(id: 'activity-1', title: 'Ontbijten', time: '08:00')],
    );

    expect(restored.id, isNotEmpty);
    expect(restored.name, 'Dagindeling');
    expect(restored.activities.single.title, 'Ontbijten');
  });

  test('restoring a backup template keeps valid id and name values', () {
    final restored = buildRestoredDayTemplate(
      {'id': 'template-1', 'name': 'Rustige dag'},
      [],
    );

    expect(restored.id, 'template-1');
    expect(restored.name, 'Rustige dag');
  });

  test('weekly routines can be saved and restored by weekday', () {
    final original = WeeklyRoutine().withDay(
      DateTime.monday,
      DayTemplate(
        id: 'monday-template',
        name: 'Maandag',
        activities: [
          DayActivity(id: 'a1', title: 'Naar werk', time: '08:00'),
        ],
      ),
    );

    final restored = WeeklyRoutine.fromJson(original.toJson());

    expect(restored.days.length, 1);
    expect(restored.forWeekday(DateTime.monday)?.name, 'Maandag');
    expect(restored.forWeekday(DateTime.tuesday), isNull);
  });

  test('weekly routine can remove one weekday without changing others', () {
    final monday = DayTemplate(
      id: 'monday',
      name: 'Maandag',
      activities: [DayActivity(id: 'a', title: 'Werk', time: '08:00')],
    );
    final friday = DayTemplate(
      id: 'friday',
      name: 'Vrijdag',
      activities: [DayActivity(id: 'b', title: 'Vrije dag', time: '09:00')],
    );
    final original = WeeklyRoutine()
        .withDay(DateTime.monday, monday)
        .withDay(DateTime.friday, friday);
    final updated = original.withoutDay(DateTime.monday);

    expect(updated.forWeekday(DateTime.monday), isNull);
    expect(updated.forWeekday(DateTime.friday)?.name, 'Vrijdag');
  });

  test('weekly routine only fills dates without an existing plan', () {
    final routine = WeeklyRoutine()
        .withDay(
          DateTime.monday,
          DayTemplate(
            id: 'monday',
            name: 'Maandag',
            activities: [
              DayActivity(id: 'a', title: 'Ontbijt', time: '08:00'),
            ],
          ),
        )
        .withDay(
          DateTime.wednesday,
          DayTemplate(
            id: 'wednesday',
            name: 'Woensdag',
            activities: [
              DayActivity(id: 'b', title: 'Wandelen', time: '10:00'),
            ],
          ),
        );

    // Monday 23 November 2026. Wednesday already has its own plan.
    final dates = routine.datesToFill(
      DateTime(2026, 11, 23),
      existingDateKeys: {'2026-11-25'},
    );

    expect(dates.map((date) => date.weekday).toList(), [DateTime.monday]);
  });


  test('copying a day plan gives fresh ids and resets completed activities', () {
    final source = [
      DayActivity(
        id: 'source-1',
        title: 'Naar de winkel',
        time: '10:30',
        who: 'Ik en begeleider',
        what: 'Boodschappen doen',
        where: 'De supermarkt',
        how: 'Rustig samen lopen',
        note: 'Neem een tas mee',
        symbol: '🛒',
        photoPath: '/local/moodpress/winkel.jpg',
        done: true,
        steps: ['Jas pakken', 'Tas meenemen'],
        stepDone: [true, false],
      ),
      DayActivity(
        id: 'source-2',
        title: 'Rustmoment',
        time: '12:00',
        done: false,
      ),
    ];

    final copied = copyDayActivities(source, idPrefix: 'copy-20261125');

    expect(copied, hasLength(2));
    expect(copied.map((item) => item.id).toList(), [
      'copy-20261125-0',
      'copy-20261125-1',
    ]);
    expect(copied.map((item) => item.done).toList(), [false, false]);
    expect(copied.first.title, source.first.title);
    expect(copied.first.time, source.first.time);
    expect(copied.first.who, source.first.who);
    expect(copied.first.what, source.first.what);
    expect(copied.first.where, source.first.where);
    expect(copied.first.how, source.first.how);
    expect(copied.first.note, source.first.note);
    expect(copied.first.symbol, source.first.symbol);
    expect(copied.first.photoPath, source.first.photoPath);
    expect(copied.first.steps, source.first.steps);
    expect(copied.first.stepDone, [false, false]);
    expect(source.first.stepDone, [true, false]);
  });

  test('copying one activity creates a new unfinished copy and keeps the original', () {
    final original = DayActivity(
      id: 'original-activity',
      title: 'Naar de winkel',
      time: '10:30',
      who: 'Ik en begeleider',
      what: 'Boodschappen doen',
      where: 'De supermarkt',
      how: 'Rustig samen lopen',
      note: 'Neem een tas mee',
      symbol: '🛒',
      photoPath: '/local/moodpress/winkel.jpg',
      done: true,
      steps: ['Jas pakken', 'Tas meenemen'],
      stepDone: [true, false],
    );

    final copied = copyDayActivity(
      original,
      newId: 'copy-activity-123',
    );

    expect(copied.id, 'copy-activity-123');
    expect(copied.id, isNot(original.id));
    expect(copied.done, isFalse);
    expect(copied.title, original.title);
    expect(copied.time, original.time);
    expect(copied.who, original.who);
    expect(copied.what, original.what);
    expect(copied.where, original.where);
    expect(copied.how, original.how);
    expect(copied.note, original.note);
    expect(copied.symbol, original.symbol);
    expect(copied.photoPath, original.photoPath);
    expect(copied.steps, ['Jas pakken', 'Tas meenemen']);
    expect(copied.stepDone, [false, false]);
    expect(original.stepDone, [true, false]);
    expect(original.done, isTrue);
    expect(original.id, 'original-activity');
  });

  test('moving an activity to another day preserves its details and status', () {
    final source = [
      DayActivity(
        id: 'move-me',
        title: 'Naar de winkel',
        time: '10:30',
        who: 'Samen met iemand',
        what: 'Boodschappen doen',
        where: 'De supermarkt',
        how: 'Rustig stap voor stap',
        note: 'Neem een tas mee',
        symbol: '🛒',
        photoPath: '/local/moodpress/winkel.jpg',
        done: true,
      ),
      DayActivity(id: 'stay-here', title: 'Rustmoment', time: '12:00'),
    ];
    final destination = [
      DayActivity(id: 'already-there', title: 'Ontbijt', time: '08:00'),
    ];

    final moved = moveDayActivityBetweenLists(
      source,
      destination,
      activityId: 'move-me',
    );

    expect(moved, isTrue);
    expect(source.map((item) => item.id).toList(), ['stay-here']);
    expect(
      destination.map((item) => item.id).toList(),
      ['already-there', 'move-me'],
    );
    final activity = destination.last;
    expect(activity.title, 'Naar de winkel');
    expect(activity.time, '10:30');
    expect(activity.who, 'Samen met iemand');
    expect(activity.what, 'Boodschappen doen');
    expect(activity.where, 'De supermarkt');
    expect(activity.how, 'Rustig stap voor stap');
    expect(activity.note, 'Neem een tas mee');
    expect(activity.symbol, '🛒');
    expect(activity.photoPath, '/local/moodpress/winkel.jpg');
    expect(activity.done, isTrue);
  });

  test('moving an unknown activity or moving within the same day changes nothing', () {
    final activities = [
      DayActivity(id: 'one', title: 'Ontbijt', time: '08:00'),
    ];

    expect(
      moveDayActivityBetweenLists(
        activities,
        activities,
        activityId: 'one',
      ),
      isFalse,
    );
    expect(
      moveDayActivityBetweenLists(
        activities,
        <DayActivity>[],
        activityId: 'missing',
      ),
      isFalse,
    );
    expect(activities.map((item) => item.id).toList(), ['one']);
  });

  test('day activities can be reordered without changing their data', () {
    final activities = [
      DayActivity(id: 'a', title: 'Ontbijt', time: '08:00'),
      DayActivity(id: 'b', title: 'Wandelen', time: '10:00'),
      DayActivity(id: 'c', title: 'Rust', time: '12:00'),
    ];

    reorderDayActivities(activities, 0, 3);

    expect(activities.map((item) => item.id).toList(), ['b', 'c', 'a']);
    expect(activities.last.title, 'Ontbijt');
  });

  test('reordering to the same position keeps the order', () {
    final activities = [
      DayActivity(id: 'a', title: 'Ontbijt', time: '08:00'),
      DayActivity(id: 'b', title: 'Wandelen', time: '10:00'),
    ];

    reorderDayActivities(activities, 1, 1);

    expect(activities.map((item) => item.id).toList(), ['a', 'b']);
  });

  test('speech preference defaults on when loading older settings', () {
    final restored = MoodPressPreferences.fromJson({
      'textScale': 1.15,
      'speechRate': 0.5,
      'reduceMotion': true,
      'inAppRemindersEnabled': false,
    });

    expect(restored.speechEnabled, isTrue);
    expect(restored.textScale, 1.15);
    expect(restored.speechRate, 0.5);
    expect(restored.reduceMotion, isTrue);
  });

  test('speech preference is included in local settings serialization', () {
    final restored = MoodPressPreferences.fromJson({
      'speechEnabled': false,
    });

    expect(restored.speechEnabled, isFalse);
    expect(restored.toJson()['speechEnabled'], isFalse);
  });

  test('changing one preference preserves every other preference', () async {
    final controller = MoodPressController();
    controller.preferences = const MoodPressPreferences(
      textScale: 1.15,
      speechRate: 0.48,
      reduceMotion: false,
      inAppRemindersEnabled: false,
      speechEnabled: false,
    );

    await controller.setInAppRemindersEnabled(true);
    expect(controller.preferences.inAppRemindersEnabled, isTrue);
    expect(controller.preferences.speechEnabled, isFalse);
    expect(controller.preferences.textScale, 1.15);
    expect(controller.preferences.speechRate, 0.48);

    await controller.setSpeechEnabled(true);
    expect(controller.preferences.speechEnabled, isTrue);
    expect(controller.preferences.inAppRemindersEnabled, isTrue);

    await controller.setTextScale(1.3);
    expect(controller.preferences.textScale, 1.3);
    expect(controller.preferences.speechEnabled, isTrue);
    expect(controller.preferences.inAppRemindersEnabled, isTrue);

    await controller.setSpeechRate(0.6);
    expect(controller.preferences.speechRate, 0.6);
    expect(controller.preferences.textScale, 1.3);
    expect(controller.preferences.speechEnabled, isTrue);
    expect(controller.preferences.inAppRemindersEnabled, isTrue);

    await controller.setReduceMotion(true);
    expect(controller.preferences.reduceMotion, isTrue);
    expect(controller.preferences.textScale, 1.3);
    expect(controller.preferences.speechRate, 0.6);
    expect(controller.preferences.speechEnabled, isTrue);
    expect(controller.preferences.inAppRemindersEnabled, isTrue);
  });

  test('older activities without image fields remain compatible', () {
    final restored = DayActivity.fromJson({
      'id': 'old',
      'title': 'Ontbijten',
      'time': '08:00',
    });

    expect(restored.symbol, '📌');
    expect(restored.photoPath, isEmpty);
    expect(restored.steps, isEmpty);
    expect(restored.stepDone, isEmpty);
  });
  test('backup rejects malformed envelope JSON', () async {
    const header = 'MOODPRESS_BACKUP_V1\n';
    final bytes = Uint8List.fromList([
      ...utf8.encode(header),
      ...utf8.encode('{not-json'),
    ]);

    await expectLater(
      decryptMoodPressBackup(bytes, 'mijn-veilig-wachtwoord'),
      throwsA(isA<FormatException>()),
    );
  });

  test('backup rejects unsupported envelope metadata', () async {
    const header = 'MOODPRESS_BACKUP_V1\n';
    final envelope = jsonEncode({
      'format': 'MoodPressEncryptedBackup',
      'version': 999,
      'cipher': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': 150000,
    });
    final bytes = Uint8List.fromList([
      ...utf8.encode(header),
      ...utf8.encode(envelope),
    ]);

    await expectLater(
      decryptMoodPressBackup(bytes, 'mijn-veilig-wachtwoord'),
      throwsA(isA<FormatException>()),
    );
  });

  test('step progress is normalized before toggling and invalid indexes are ignored', () {
    final activity = DayActivity(
      id: 'partial-steps',
      title: 'Rustig beginnen',
      time: '09:00',
      steps: ['Gordijnen openen', 'Aankleden', 'Ontbijten'],
      // Simulate older or incomplete saved progress.
      stepDone: [true],
    );

    expect(toggleDayActivityStep(activity, 2), isTrue);
    expect(activity.stepDone, [true, false, true]);

    expect(toggleDayActivityStep(activity, -1), isFalse);
    expect(toggleDayActivityStep(activity, 3), isFalse);
    expect(activity.stepDone, [true, false, true]);

    final noSteps = DayActivity(
      id: 'no-steps',
      title: 'Vrije activiteit',
      time: '10:00',
    );
    expect(toggleDayActivityStep(noSteps, 0), isFalse);
    expect(noSteps.stepDone, isEmpty);
  });


  test('backup rejects empty and oversized files before decoding', () async {
    const header = 'MOODPRESS_BACKUP_V1\n';
    final headerOnly = Uint8List.fromList(utf8.encode(header));

    await expectLater(
      decryptMoodPressBackup(headerOnly, 'mijn-veilig-wachtwoord'),
      throwsA(isA<FormatException>()),
    );

    final oversized = Uint8List(30 * 1024 * 1024 + 1);
    await expectLater(
      decryptMoodPressBackup(oversized, 'mijn-veilig-wachtwoord'),
      throwsA(isA<FormatException>()),
    );
  });


  test('backup rejects malformed cryptographic envelope fields', () async {
    final valid = await encryptMoodPressBackup(
      {'app': 'MoodPress', 'dataVersion': 1},
      'mijn-veilig-wachtwoord',
    );
    const header = 'MOODPRESS_BACKUP_V1\n';
    final headerLength = utf8.encode(header).length;
    final envelope = jsonDecode(
      utf8.decode(valid.sublist(headerLength)),
    ) as Map<String, dynamic>;

    final invalidSalt = Map<String, dynamic>.from(envelope)
      ..['salt'] = base64Encode([1, 2, 3]);
    final invalidSaltFile = Uint8List.fromList([
      ...utf8.encode(header),
      ...utf8.encode(jsonEncode(invalidSalt)),
    ]);
    await expectLater(
      decryptMoodPressBackup(invalidSaltFile, 'mijn-veilig-wachtwoord'),
      throwsA(isA<FormatException>()),
    );

    final invalidMac = Map<String, dynamic>.from(envelope)
      ..['mac'] = 'not-base64!';
    final invalidMacFile = Uint8List.fromList([
      ...utf8.encode(header),
      ...utf8.encode(jsonEncode(invalidMac)),
    ]);
    await expectLater(
      decryptMoodPressBackup(invalidMacFile, 'mijn-veilig-wachtwoord'),
      throwsA(isA<FormatException>()),
    );
  });


  test('resetting preferences restores every accessible default', () async {
    final controller = MoodPressController();
    controller.preferences = const MoodPressPreferences(
      textScale: 1.35,
      speechRate: 0.58,
      reduceMotion: true,
      inAppRemindersEnabled: true,
      speechEnabled: false,
    );

    await controller.resetPreferences();

    expect(controller.preferences.textScale, 1.0);
    expect(controller.preferences.speechRate, 0.42);
    expect(controller.preferences.reduceMotion, isFalse);
    expect(controller.preferences.inAppRemindersEnabled, isFalse);
    expect(controller.preferences.speechEnabled, isTrue);
    expect(controller.preferences.hasSeenWelcome, isTrue);
  });


  testWidgets('mood check-in choices expose selected state to screen readers', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    var selected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FeelingChoice(
              label: 'Rustig',
              emoji: '🙂',
              selected: selected,
              onTap: () => setState(() => selected = !selected),
            ),
          ),
        ),
      ),
    );

    var node = tester.getSemantics(find.byType(FeelingChoice));
    expect(node.label, 'Rustig');
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isSelected.toBoolOrNull(), isFalse);
    // Button semantics are verified by the isButton flag above.

    await tester.tap(find.text('Rustig'));
    await tester.pump();

    node = tester.getSemantics(find.byType(FeelingChoice));
    expect(node.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    semanticsHandle.dispose();
  });

  testWidgets('today screen shows a clear date header and calm overview', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MoodPressController();
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(controller: controller, openPlan: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Vandaag,')), findsOneWidget);
    expect(find.text('We doen het rustig aan. Eén ding tegelijk.'), findsOneWidget);
    expect(find.text('DIT IS JE VOLGENDE STAP'), findsOneWidget);
    expect(find.text('Hoe is het nu met je?'), findsOneWidget);
  });


  testWidgets('planning activity text uses the available width on compact screens', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const activityTitle =
        'Een lange activiteitstitel die netjes moet doorlopen';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ActivityCard(
                activity: DayActivity(
                  id: 'responsive-test',
                  title: activityTitle,
                  time: '09:00',
                  note:
                      'Deze extra uitleg moet de beschikbare ruimte gebruiken en normaal doorlopen.',
                ),
                speechRate: 1,
                speechEnabled: false,
                toggle: () {},
                toggleStep: (_) {},
                edit: () {},
                delete: () {},
                copy: () {},
                move: () {},
                reorderHandle: const SizedBox(width: 24, height: 24),
              ),
            ),
          ),
        ),
      ),
    );

    final titleSize = tester.getSize(find.text(activityTitle));
    expect(titleSize.width, greaterThan(150));
  });


  testWidgets('planning search opens the matching activity', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MoodPressController(
      initialPlans: {
        DateTime(2026, 11, 26): [
          DayActivity(
            id: 'search-ui-activity',
            title: 'Medicatie ophalen',
            time: '09:45',
            who: 'Zelf',
            what: 'Medicatie ophalen bij de apotheek',
            where: 'Apotheek',
            how: 'Rustig wandelen',
            note: 'Neem de herhaalbrief mee',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlanningPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'herhaalbrief');
    await tester.pumpAndSettle();

    expect(find.text('1 resultaat gevonden'), findsOneWidget);
    expect(find.text('Medicatie ophalen'), findsOneWidget);

    await tester.tap(find.text('Medicatie ophalen'));
    await tester.pumpAndSettle();

    expect(find.text('Medicatie ophalen'), findsOneWidget);
    expect(find.text('Apotheek'), findsOneWidget);
    expect(find.text('Herhaalbrief'), findsNothing);
    expect(find.text('Neem de herhaalbrief mee'), findsOneWidget);
  });


  test('prikkel history search matches notes, dates and levels and sorts newest first', () {
    final measurements = [
      PrikkelMeting(id: 'older', level: 5, createdAt: DateTime(2026, 11, 20, 9), note: 'Veel geluid op kantoor'),
      PrikkelMeting(id: 'newer', level: 5, createdAt: DateTime(2026, 11, 25, 18), note: 'Veel geluid thuis'),
      PrikkelMeting(id: 'quiet', level: 1, createdAt: DateTime(2026, 11, 25, 8), note: 'Rustige ochtend'),
    ];
    expect(filterPrikkelMetingen(measurements, query: 'veel geluid').map((item) => item.id), ['newer', 'older']);
    expect(filterPrikkelMetingen(measurements, query: '25-11-2026').map((item) => item.id), ['newer', 'quiet']);
    expect(filterPrikkelMetingen(measurements, niveau: 5).map((item) => item.id), ['newer', 'older']);
    expect(filterPrikkelMetingen(measurements, query: 'thuis', niveau: 5).map((item) => item.id), ['newer']);
    expect(filterPrikkelMetingen(measurements, query: 'bestaat niet'), isEmpty);
  });

  test('prikkel meter levels and measurement data are safely represented', () {
    expect(prikkelNiveaus, [
      'Helemaal rustig',
      'Een beetje prikkels',
      'Best veel prikkels',
      'Erg veel prikkels',
      'Overprikkeld',
    ]);

    final measurement = PrikkelMeting(
      id: 'meter-test',
      level: 4,
      createdAt: DateTime(2026, 11, 25, 18, 30),
      note: 'Veel geluid',
    );
    final restored = PrikkelMeting.fromJson(measurement.toJson());

    expect(restored.id, 'meter-test');
    expect(restored.level, 4);
    expect(restored.createdAt, DateTime(2026, 11, 25, 18, 30));
    expect(restored.note, 'Veel geluid');
  });

  test('prikkel meter rejects invalid levels when saving', () async {
    final controller = MoodPressController();
    await controller.savePrikkelMeting(0, 'Ongeldig');
    await controller.savePrikkelMeting(6, 'Ongeldig');
    expect(controller.prikkelMetingen, isEmpty);
  });


  test('prikkel month overview contains thirty daily buckets', () {
    final today = DateTime(2026, 11, 25);
    final measurements = [
      PrikkelMeting(
        id: 'month-one',
        level: 2,
        createdAt: DateTime(2026, 11, 25, 9),
      ),
      PrikkelMeting(
        id: 'month-two',
        level: 4,
        createdAt: DateTime(2026, 11, 25, 18),
      ),
      PrikkelMeting(
        id: 'month-old',
        level: 5,
        createdAt: DateTime(2026, 10, 25, 12),
      ),
    ];

    final month = maakPrikkelGrafiekPunten(
      measurements,
      periode: 1,
      vandaag: today,
    );

    expect(month, hasLength(30));
    expect(month.last.date, DateTime(2026, 11, 25));
    expect(month.last.count, 2);
    expect(month.last.averageLevel, 3);
    expect(month.first.count, 0);
  });

  test('prikkel year overview groups measurements into twelve months', () {
    final today = DateTime(2026, 11, 25);
    final measurements = [
      PrikkelMeting(
        id: 'year-one',
        level: 4,
        createdAt: DateTime(2026, 11, 12),
      ),
      PrikkelMeting(
        id: 'year-two',
        level: 2,
        createdAt: DateTime(2026, 10, 4),
      ),
      PrikkelMeting(
        id: 'year-old',
        level: 5,
        createdAt: DateTime(2025, 11, 25),
      ),
    ];

    final year = maakPrikkelGrafiekPunten(
      measurements,
      periode: 2,
      vandaag: today,
    );

    expect(year, hasLength(12));
    expect(year.first.date, DateTime(2025, 12, 1));
    expect(year.last.date, DateTime(2026, 11, 1));
    expect(year.last.count, 1);
    expect(year.last.averageLevel, 4);
    expect(year[10].count, 1);
    expect(year[10].averageLevel, 2);
  });

  test('prikkel period comparison compares with previous equal period', () {
    final today = DateTime(2026, 11, 25);
    final measurements = [
      PrikkelMeting(
        id: 'current-one',
        level: 4,
        createdAt: DateTime(2026, 11, 25, 9),
      ),
      PrikkelMeting(
        id: 'current-two',
        level: 2,
        createdAt: DateTime(2026, 11, 24, 9),
      ),
      PrikkelMeting(
        id: 'previous-one',
        level: 1,
        createdAt: DateTime(2026, 11, 18, 9),
      ),
      PrikkelMeting(
        id: 'outside',
        level: 5,
        createdAt: DateTime(2026, 11, 10, 9),
      ),
    ];

    final comparison = vergelijkPrikkelPeriodes(
      measurements,
      periode: 0,
      vandaag: today,
    );

    expect(comparison.huidigAantal, 2);
    expect(comparison.huidigGemiddelde, 3);
    expect(comparison.vorigAantal, 1);
    expect(comparison.vorigGemiddelde, 1);
  });

  test('highest prikkel chart point ignores empty periods', () {
    final points = [
      PrikkelGrafiekPunt(
        date: DateTime(2026, 11, 23),
        label: 'ma',
        averageLevel: null,
        count: 0,
      ),
      PrikkelGrafiekPunt(
        date: DateTime(2026, 11, 24),
        label: 'di',
        averageLevel: 3,
        count: 2,
      ),
      PrikkelGrafiekPunt(
        date: DateTime(2026, 11, 25),
        label: 'wo',
        averageLevel: 4.5,
        count: 2,
      ),
    ];

    final highest = hoogstePrikkelGrafiekPunt(points);

    expect(highest, points.last);
    expect(hoogstePrikkelGrafiekPunt(const []), isNull);
  });

  test('personal prikkel insights summarize levels, weekdays and weekly trend', () {
    final today = DateTime(2026, 11, 25);
    final measurements = [
      PrikkelMeting(id: 'mon-low', level: 2, createdAt: DateTime(2026, 11, 23, 9)),
      PrikkelMeting(id: 'tue-high', level: 5, createdAt: DateTime(2026, 11, 24, 9)),
      PrikkelMeting(id: 'tue-mid', level: 5, createdAt: DateTime(2026, 11, 24, 18)),
      PrikkelMeting(id: 'prev-week', level: 4, createdAt: DateTime(2026, 11, 17, 9)),
    ];

    final insights = berekenPrikkelInzichten(measurements, vandaag: today);

    expect(insights.totalMeasurements, 4);
    expect(insights.averageLevel, 4.0);
    expect(insights.mostCommonLevel, 5);
    expect(insights.highestAverageWeekday, DateTime.tuesday);
    expect(insights.highestAverageWeekdayLevel, 5);
    expect(insights.highestAverageWeekdayCount, 2);
    expect(insights.recentAverage, 4);
    expect(insights.previousAverage, 4);
  });

  test('personal prikkel insights handle an empty history', () {
    final insights = berekenPrikkelInzichten(
      const [],
      vandaag: DateTime(2026, 11, 25),
    );

    expect(insights.totalMeasurements, 0);
    expect(insights.averageLevel, isNull);
    expect(insights.mostCommonLevel, isNull);
    expect(insights.highestAverageWeekday, isNull);
    expect(insights.recentAverage, isNull);
    expect(insights.previousAverage, isNull);
  });

  test('prikkel week overview calculates daily averages for seven days', () {
    final today = DateTime(2026, 11, 25);
    final measurements = [
      PrikkelMeting(
        id: 'one',
        level: 2,
        createdAt: DateTime(2026, 11, 25, 9),
      ),
      PrikkelMeting(
        id: 'two',
        level: 4,
        createdAt: DateTime(2026, 11, 25, 18),
      ),
      PrikkelMeting(
        id: 'three',
        level: 5,
        createdAt: DateTime(2026, 11, 24, 12),
      ),
    ];

    final week = maakPrikkelWeekOverzicht(measurements, vandaag: today);

    expect(week, hasLength(7));
    expect(week.last.date, DateTime(2026, 11, 25));
    expect(week.last.count, 2);
    expect(week.last.averageLevel, 3);
    expect(week[5].count, 1);
    expect(week[5].averageLevel, 5);
    expect(week.first.averageLevel, isNull);
  });


  test('chart point details include only matching measurements and sort newest first', () {
    final measurements = [
      PrikkelMeting(
        id: 'morning',
        level: 2,
        createdAt: DateTime(2026, 11, 25, 8),
        note: 'Rustig begonnen',
      ),
      PrikkelMeting(
        id: 'evening',
        level: 4,
        createdAt: DateTime(2026, 11, 25, 20),
        note: 'Drukke dag',
      ),
      PrikkelMeting(
        id: 'other-day',
        level: 5,
        createdAt: DateTime(2026, 11, 24, 12),
        note: 'Andere dag',
      ),
    ];
    final dayPoint = PrikkelGrafiekPunt(
      date: DateTime(2026, 11, 25),
      label: 'wo',
      averageLevel: 3,
      count: 2,
    );

    final dayMeasurements = prikkelMetingenVoorGrafiekPunt(
      measurements,
      dayPoint,
      perMaand: false,
    );

    expect(dayMeasurements.map((item) => item.id), ['evening', 'morning']);
    expect(dayMeasurements.first.note, 'Drukke dag');

    final monthPoint = PrikkelGrafiekPunt(
      date: DateTime(2026, 11, 1),
      label: 'nov',
      averageLevel: 3.7,
      count: 3,
    );
    expect(
      prikkelMetingenVoorGrafiekPunt(
        measurements,
        monthPoint,
        perMaand: true,
      ),
      hasLength(3),
    );
  });

}
