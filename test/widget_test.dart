import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpress/main.dart';

void main() {
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

    final controller = MoodPressController()..ready = true;
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

    final controller = MoodPressController()..ready = true;
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

    final olderPreferences = MoodPressPreferences.fromJson({
      'textScale': 1.0,
      'speechRate': 0.42,
      'reduceMotion': false,
    });
    expect(olderPreferences.inAppRemindersEnabled, isFalse);

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
}