
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _ink = Color(0xFF26383A);
const _muted = Color(0xFF687779);
const _paper = Color(0xFFF5F5F1);
const _green = Color(0xFF54796E);
const _greenPale = Color(0xFFE8F0EC);
const _sand = Color(0xFFF1E9DC);
const _line = Color(0xFFE3E8E4);

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
        done: json['done'] as bool? ?? false,
      );
}

class MoodPressController extends ChangeNotifier {
  static const _dayKey = 'moodpress.day.v1';
  static const _supportKey = 'moodpress.support.v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<DayActivity> activities = [];
  Map<String, String> support = {
    'help': 'Ik wil even rust en één ding tegelijk doen.',
    'place': 'Een rustige plek waar ik mij prettig voel.',
    'person': '',
  };
  String? feeling;
  String? storageNotice;
  bool ready = false;

  int get completed => activities.where((item) => item.done).length;
  double get progress => activities.isEmpty ? 0 : completed / activities.length;

  List<DayActivity> _starterPlan() => [
        DayActivity(id: '1', title: 'Rustig opstarten', time: '08:00', what: 'Opstaan en aankleden', where: 'Thuis', how: 'Stap voor stap', note: 'Neem de tijd om wakker te worden.'),
        DayActivity(id: '2', title: 'Ontbijten', time: '08:30', what: 'Ontbijt eten en iets drinken', where: 'Keuken', how: 'Pak wat je nodig hebt'),
        DayActivity(id: '3', title: 'Mijn activiteit', time: '10:00', what: 'Mijn gekozen activiteit', where: 'Op de afgesproken plek', how: 'Begin met de eerste stap'),
        DayActivity(id: '4', title: 'Rustmoment', time: '12:00', what: 'Even pauze nemen', where: 'Een fijne plek', how: 'Kies wat jou helpt'),
        DayActivity(id: '5', title: 'Middagactiviteit', time: '14:00', what: 'Een kleine activiteit doen', where: 'Thuis of buiten', how: 'Eén ding tegelijk'),
        DayActivity(id: '6', title: 'Avond rustig afronden', time: '19:30', what: 'Ontspannen en voorbereiden op de nacht', where: 'Thuis', how: 'Kies een vertrouwde activiteit'),
      ];

  Future<void> load() async {
    try {
      final savedDay = await _storage.read(key: _dayKey);
      if (savedDay == null) {
        activities = _starterPlan();
        await _saveDay();
      } else {
        final values = jsonDecode(savedDay) as List<dynamic>;
        activities = values.whereType<Map<String, dynamic>>().map(DayActivity.fromJson).toList()
          ..sort((a, b) => a.time.compareTo(b.time));
      }
      final savedSupport = await _storage.read(key: _supportKey);
      if (savedSupport != null) {
        final values = jsonDecode(savedSupport) as Map<String, dynamic>;
        support = values.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (_) {
      activities = _starterPlan();
      storageNotice = 'Opslaan is op dit apparaat niet beschikbaar. Gebruik nog geen echte cliëntgegevens.';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _saveDay() async {
    try {
      await _storage.write(
        key: _dayKey,
        value: jsonEncode(activities.map((item) => item.toJson()).toList()),
      );
    } catch (_) {
      storageNotice = 'Je dagplan kon niet veilig worden opgeslagen.';
    }
  }

  Future<void> _saveSupport() async {
    try {
      await _storage.write(key: _supportKey, value: jsonEncode(support));
    } catch (_) {
      storageNotice = 'Je steunplan kon niet veilig worden opgeslagen.';
    }
  }

  Future<void> saveActivity(DayActivity activity) async {
    final index = activities.indexWhere((item) => item.id == activity.id);
    if (index == -1) {
      activities.add(activity);
    } else {
      activities[index] = activity;
    }
    activities.sort((a, b) => a.time.compareTo(b.time));
    await _saveDay();
    notifyListeners();
  }

  Future<void> toggleActivity(String id) async {
    final item = activities.firstWhere((activity) => activity.id == id);
    item.done = !item.done;
    await _saveDay();
    notifyListeners();
  }

  Future<void> deleteActivity(String id) async {
    activities.removeWhere((activity) => activity.id == id);
    await _saveDay();
    notifyListeners();
  }

  Future<void> saveSupport(String key, String value) async {
    support[key] = value;
    await _saveSupport();
    notifyListeners();
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
  static const labels = ['Vandaag', 'Mijn dag', 'Even rust', 'Mijn steun'];
  static const icons = [Icons.wb_sunny_outlined, Icons.calendar_month_outlined, Icons.spa_outlined, Icons.favorite_border];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        final pages = [
          TodayPage(controller: widget.controller, openPlan: () => setState(() => selected = 1)),
          PlanPage(controller: widget.controller),
          const CalmPage(),
          SupportPage(controller: widget.controller),
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
    final upcoming = controller.activities.where((item) => !item.done).toList()..sort((a, b) => a.time.compareTo(b.time));
    final next = upcoming.isEmpty ? null : upcoming.first;

    return PageFrame(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const BrandMark(),
      const SizedBox(height: 28),
      Text(greeting + '.', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text('We doen het rustig aan. Eén ding tegelijk.', style: TextStyle(color: _muted, fontSize: 16)),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, constraints) {
        final nextCard = NextStepCard(activity: next, openPlan: openPlan);
        final progressCard = ProgressCard(done: controller.completed, total: controller.activities.length, progress: controller.progress, openPlan: openPlan);
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
          FilledButton.icon(onPressed: openPlan, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _green), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Bekijk mijn dag')),
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
            TextButton.icon(onPressed: openPlan, icon: const Icon(Icons.list_alt_outlined), label: const Text('Mijn dagplan')),
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

class PlanPage extends StatelessWidget {
  const PlanPage({super.key, required this.controller});
  final MoodPressController controller;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Mijn dag',
        subtitle: 'Een duidelijk overzicht. Je mag je planning altijd aanpassen.',
        action: FilledButton.icon(onPressed: () => editActivity(context, controller), icon: const Icon(Icons.add), label: const Text('Activiteit toevoegen')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: _sand, borderRadius: BorderRadius.circular(17)), child: const Text('Kijk alleen naar de eerstvolgende activiteit. De rest komt later.', style: TextStyle(color: _ink, fontWeight: FontWeight.w600))),
          const SizedBox(height: 18),
          for (final item in controller.activities)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: ActivityCard(
                activity: item,
                toggle: () => controller.toggleActivity(item.id),
                edit: () => editActivity(context, controller, existing: item),
                delete: () => confirmDelete(context, controller, item),
              ),
            ),
          if (controller.activities.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(25), child: Text('Je dagplan is nog leeg. Voeg een activiteit toe.'))),
          if (controller.storageNotice != null) StorageNotice(message: controller.storageNotice!),
        ]),
      );
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.toggle, required this.edit, required this.delete});
  final DayActivity activity;
  final VoidCallback toggle;
  final VoidCallback edit;
  final VoidCallback delete;

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
                Text(activity.title, style: TextStyle(color: activity.done ? _muted : _ink, fontSize: 16, fontWeight: FontWeight.w700, decoration: activity.done ? TextDecoration.lineThrough : null)),
                if (activity.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(activity.note, style: const TextStyle(color: _muted, fontSize: 13))),
                const SizedBox(height: 7),
                const Text('Tik om de vijf vragen te bekijken', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            )),
            SpeakButton(text: activity.title + '. ' + activity.time + '. Wie: ' + activity.who + '. Wat: ' + activity.what + '. Waar: ' + activity.where + '. Hoe: ' + activity.how + '.'),
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

class _CalmPageState extends State<CalmPage> {
  int step = 0;
  static const steps = [
    ('Voel de grond', 'Zet je voeten neer. Voel waar je voeten de grond raken.', Icons.place_outlined),
    ('Kijk rustig om je heen', 'Noem voor jezelf drie dingen die je ziet. Je hoeft niets hardop te zeggen.', Icons.remove_red_eye_outlined),
    ('Kies één kleine stap', 'Wat heb je nu nodig? Rust, hulp of verdergaan?', Icons.spa_outlined),
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
                CircleAvatar(radius: 33, backgroundColor: Colors.white, child: Icon(steps[step].$3, color: _green, size: 29)),
                const SizedBox(height: 18),
                Text('STAP ' + (step + 1).toString() + ' VAN 3', style: const TextStyle(color: _green, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                const SizedBox(height: 11),
                Text(steps[step].$1, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(steps[step].$2, textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 16, height: 1.5)),
                const SizedBox(height: 23),
                Row(children: List.generate(3, (index) => Expanded(child: Container(height: 5, margin: EdgeInsets.only(right: index == 2 ? 0 : 7), decoration: BoxDecoration(color: index <= step ? _green : _line, borderRadius: BorderRadius.circular(5))))),
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
  const SpeakButton({super.key, required this.text});
  final String text;

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
      await _tts.setSpeechRate(0.42);
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
