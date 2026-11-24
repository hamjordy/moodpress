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
    expect(restored.done, isTrue);
  });
}
