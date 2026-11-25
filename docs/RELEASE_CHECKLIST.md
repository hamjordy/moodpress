# MoodPress — releasechecklist Android en Windows

Deze checklist beschrijft wanneer een versie als releaseklaar mag worden aangemerkt. Een geslaagde GitHub-build is noodzakelijk, maar vervangt geen installatie- en praktijktest op echte apparaten.

## 1. Releasebasis

- [ ] De gewenste releasecode staat op `main`; de pull request is beoordeeld en samengevoegd.
- [ ] De versie in `pubspec.yaml` is bewust gekozen en komt overeen met de releasetag en release-notities.
- [ ] De app heeft een definitieve, unieke Android application ID (geen standaard `com.example...`).
- [ ] De Android-release is ondertekend met een eigen releasekeystore; sleutels en wachtwoorden staan niet in Git of buildlogs.
- [ ] De Windows-build heeft de juiste productnaam, versie, app-icoon en distributiebestanden.
- [ ] De licenties, gebruikte afhankelijkheden en privacy-/veiligheidsclaims zijn gecontroleerd.
- [ ] De release-notities benoemen bekende beperkingen en geven eenvoudige installatie-instructies.

## 2. Automatische controles

- [ ] Flutter dependencies ophalen lukt zonder fouten.
- [ ] `flutter analyze` slaagt.
- [ ] Alle automatische tests slagen.
- [ ] Android release-build slaagt en het APK-bestand wordt als artifact opgeslagen.
- [ ] Windows release-build slaagt en alle benodigde runtimebestanden worden als artifact opgeslagen.
- [ ] De artifacts zijn afkomstig van dezelfde releasecommit en zijn opnieuw te downloaden.

## 3. Android — praktijktest

- [ ] APK installeren op een schoon Android-toestel.
- [ ] App starten, welkomstscherm doorlopen en opnieuw starten.
- [ ] Planning, activiteiten, stappenplan en weekoverzicht gebruiken.
- [ ] Prikkelmeter, geschiedenis, grafieken, zoeken, filteren, bewerken, verwijderen en CSV-export testen.
- [ ] Dagboek en rustplan toevoegen, aanpassen, verwijderen en na herstart terugvinden.
- [ ] Voorlezen, tekstgrootte, terugnavigatie en TalkBack controleren.
- [ ] Back-up maken, verwijderen/terugzetten en testen met een verkeerd wachtwoord.
- [ ] Controleren dat gegevens lokaal blijven en dat de app bruikbaar blijft zonder internet.

## 4. Windows — praktijktest

- [ ] De volledige Windows Release-map op een schone Windows 10/11-pc uitpakken en starten.
- [ ] Controleren of ontbrekende runtimecomponenten of installatievereisten duidelijk zijn.
- [ ] Alle hoofdonderdelen met muis en toetsenbord bedienen.
- [ ] Ctrl+1 tot en met Ctrl+7 testen, inclusief numeriek toetsenblok.
- [ ] Schaal 100%, 125%, 150% en 200% en grotere tekst controleren.
- [ ] Voorlezen, schermlezer, vensters en dialoogvensters controleren.
- [ ] Planning, prikkelmeter, dagboek en rustplan na herstart controleren.
- [ ] Back-up maken en terugzetten en testen met een verkeerd wachtwoord.

## 5. Privacy, veiligheid en doelgroep

- [ ] Alleen fictieve gegevens gebruiken tijdens demonstraties en ontwikkeltests.
- [ ] Bevestigen dat verwijderen en back-up/terugzetten geen gegevens door elkaar halen.
- [ ] Controleren dat foutmeldingen geen persoonlijke inhoud of wachtwoorden lekken.
- [ ] De grenzen van MoodPress duidelijk communiceren: geen diagnose, behandeling, toezicht of crisisdienst.
- [ ] Toegankelijkheid en begrijpelijkheid laten toetsen door beoogde gebruikers en deskundigen, met vrijwillige deelname en passende waarborgen.
- [ ] Voor gebruik met echte cliëntgegevens eerst privacy-, beveiligings- en juridische beoordeling uitvoeren; beoordeel onder meer of een DPIA nodig is.

## 6. Publiceren

- [ ] Alleen publiceren nadat alle blokkerende punten hierboven zijn afgevinkt.
- [ ] Een getagde GitHub-release maken met versie, wijzigingen, bekende beperkingen en installatie-instructies.
- [ ] Android APK en Windows distributiebestand(en) aan dezelfde release toevoegen.
- [ ] Downloads na publicatie controleren en installatie nogmaals uitvoeren.

## Huidige status

De repository bevat automatische Flutter-controles en bouwt Android en Windows. De automatische controles bewijzen niet dat de apps al op echte apparaten zijn geïnstalleerd of handmatig getest. Er is nog geen officiële GitHub-release. Controleer daarom de punten hierboven voordat MoodPress als definitief releaseklaar wordt aangekondigd.
