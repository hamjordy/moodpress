import 'package:flutter_test/flutter_test.dart';
import 'package:moodpress/main.dart';

void main() {
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
  });
  
  test('accessibility preferences can be saved and restored', () {
    const original = MoodPressPreferences(textScale: 1.3, speechRate: 0.5);
    final restored = MoodPressPreferences.fromJson(original.toJson());

    expect(restored.textScale, 1.3);
    expect(restored.speechRate, 0.5);
  });

  test('accessibility preferences stay within supported limits', () {
    final restored = MoodPressPreferences.fromJson({
      'textScale': 4.0,
      'speechRate': 0.05,
    });

    expect(restored.textScale, 1.4);
    expect(restored.speechRate, 0.3);
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

  test('older activities without image fields remain compatible', () {
    final restored = DayActivity.fromJson({
      'id': 'old',
      'title': 'Ontbijten',
      'time': '08:00',
    });

    expect(restored.symbol, '📌');
    expect(restored.photoPath, isEmpty);
  });
}