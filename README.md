# MoodPress

**Rust en overzicht in je dag.** Een zelfstandige, Nederlandstalige dagstructuur-app voor Android en Windows 11.

MoodPress helpt gebruikers om activiteiten voorspelbaar en in kleine stappen te plannen. De eerste versie bevat:

- **Vandaag** — eerstvolgende stap, voortgang en een vrijwillige check-in.
- **Planning** — weekoverzicht, een apart dagplan per datum, activiteiten afronden en de volgorde zelf verslepen.
- **Dagindelingen** — bewaar een dag als sjabloon en gebruik die opnieuw op een andere datum.
- **Vast weekritme** — bewaar een vaste indeling per weekdag en vul daarmee lege dagen in.
- **Dagplan kopiëren** — kopieer een bestaande dag naar een andere datum. De volgorde en uitleg blijven behouden; activiteiten beginnen op de nieuwe dag opnieuw als niet afgerond.
- **Activiteit verplaatsen** — verplaats één losse activiteit naar een andere datum. De rest van het dagplan blijft staan en alle details van de activiteit blijven behouden.
- **Activiteit kopiëren** — zet een kopie van één activiteit op een andere datum. Het origineel blijft staan; de nieuwe kopie is nog niet afgerond.
- **Stappenplan per activiteit** — deel een activiteit op in maximaal 12 korte stappen. Vink iedere stap apart af; de voortgang blijft lokaal bewaard en gaat mee in de versleutelde back-up.
- **Eén activiteit tegelijk** — bekijk één activiteit met de uitleg, foto en kleine stappen. Ga zelf naar de vorige of volgende activiteit, zonder de hele dag tegelijk te hoeven bekijken.
- **Schermlezerondersteuning** — belangrijke paginakoppen zijn als kop herkenbaar; bij vorige of volgende activiteit wordt de titel met het activiteitnummer aangekondigd.
- **Vijf verduidelijkingsvragen** — wie, wat, waar, wanneer en hoe.
- **Voorlezen** — Nederlandse tekst-naar-spraak met instelbare snelheid.
- **Instellingen** — kies normale, grotere of extra grote tekst, pas de voorleessnelheid aan, schakel animaties uit en zet optionele herinneringen aan of uit. Lees ook waarvoor MoodPress niet bedoeld is en wat je kunt doen bij direct gevaar.
- **Toetsenbordbediening** — op Windows wissel je met Ctrl + 1 tot en met Ctrl + 5 (ook via het numerieke toetsenblok) tussen Vandaag, Planning, Even rust, Mijn steun en Instellingen. De focusvolgorde volgt de leesvolgorde. De app houdt de toetsenbordfocus vast zodat meerdere sneltoetsen achter elkaar werken.
- **Rustige herinneringen** — een melding op het geplande tijdstip zolang MoodPress open is; standaard uit en altijd uit te zetten.
- **Back-up en terugzetten** — bewaar al je dagplannen, sjablonen, weekritme, steunplan, instellingen en activiteitfoto’s in één wachtwoord-beveiligd bestand. Je kunt dit lokaal bewaren of naar een ander toestel meenemen.
- **Even rust** — een korte, optionele oriëntatieoefening die altijd kan worden overgeslagen.
- **Mijn steun** — een persoonlijk plan met wat helpt, een fijne plek en een vertrouwd persoon.
- **Volledig zelfstandig** — geen account, advertenties, analytics, cloudbackend, begeleidersportaal, server of betaalde hosting. Persoonlijke informatie blijft lokaal op het apparaat.

## Doelgroep en grenzen

De app is ontworpen met ondersteuningsbehoeften rond autisme, een licht verstandelijke beperking (LVB) en PTSS in gedachten. Niet iedere gebruiker heeft dezelfde behoeften; MoodPress biedt daarom keuzes en eigen regie.

MoodPress is een ondersteunend dagstructuurhulpmiddel. Het stelt geen diagnose, behandelt geen aandoeningen en vervangt geen begeleider, behandelaar of crisisdienst. Het is een prototype dat vóór inzet in zorg of met echte cliëntgegevens samen met de doelgroep en deskundigen moet worden getest en beoordeeld.

## Methode-inspiratie

MoodPress is een zelfstandig product en is **niet** de officiële app van *Geef me de 5*, en is niet ontwikkeld, goedgekeurd of uitgegeven door de makers daarvan. De app gebruikt een eigen, korte invulinterface met de vragen wie, wat, waar, wanneer en hoe. Er zijn geen boekteksten, officiële illustraties of beschermde vormgeving overgenomen. Zie [de methode-notitie](docs/METHODIEK_EN_INSPIRATIE.md).

## Techniek

- Flutter / Dart
- Android en Windows desktop
- `flutter_secure_storage` voor platformgebonden beveiligde opslag
- `flutter_tts` voor voorlezen
- `cryptography` voor wachtwoord-beveiligde back-ups
- Geen servercomponent, portaal, betaalde hosting of telemetrie in deze prototypeversie
- Eigen activiteitfoto's worden lokaal opgeslagen in de app-map; deel het apparaat alleen met mensen die deze afbeeldingen mogen zien

## Starten

Installeer de Flutter SDK en Android- of Windows-buildvereisten. Genereer daarna de platformbestanden en haal de dependencies op:

```bash
flutter create --platforms=android,windows .
flutter pub get
flutter run -d windows
```

Voor Android:

```bash
flutter devices
flutter run -d <android-device-id>
flutter build apk --release
```

Voor Windows:

```bash
flutter build windows --release
```

De platformmappen `android/` en `windows/` worden door `flutter create` gegenereerd met de lokaal geïnstalleerde Flutter SDK. GitHub Actions voert analyse, tests en platformbuilds uit.

## Privacy en veiligheid

De prototypecode bewaart dagplannen per datum, herbruikbare dagindelingen, vaste weekritmes, het steunplan en toegankelijkheidsvoorkeuren lokaal via platformgebonden secure storage. Een export-back-up wordt met AES-256-GCM versleuteld; het wachtwoord wordt via PBKDF2 omgezet naar een sleutel. MoodPress bewaart het back-upwachtwoord niet. Wie het wachtwoord kwijtraakt, kan die back-up niet meer openen. Bewaar het bestand en wachtwoord daarom zorgvuldig. Bestaande dagplannen uit versie 0.2.0 worden bij de eerste start gemigreerd. De stemming-check-in wordt alleen tijdelijk in het geheugen bijgehouden en niet opgeslagen. Dit is geen volledige AVG-conformiteitsverklaring of garantie voor ieder toestel.

Gebruik geen herleidbare cliëntgegevens in ontwikkel- of testomgevingen. Voor een pilot zijn onder meer een privacy- en beveiligingsbeoordeling, beoordeling van de gegevensverwerking (waaronder een DPIA indien vereist), toegangs- en verwijderbeleid, gebruikerstesten en professionele toetsing nodig. Lees [veiligheid en privacy](docs/SAFETY_AND_PRIVACY.md).

## Ontwikkelstatus

**Versie 0.15.28 — extra controle dat lege en te grote back-upbestanden direct worden geweigerd.** Zie [het productplan](docs/PRODUCT_PLAN.md) en het [toegankelijkheidstestplan](docs/TESTPLAN_TOEGANKELIJKHEID.md).
