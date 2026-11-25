# MoodPress — productplan

## Productdoel

De gebruiker helpen de dag in kleine, begrijpelijke en voorspelbare stappen te verdelen. De app moet ondersteunen zonder druk te zetten of de gebruiker te beoordelen.

## Ontwerpprincipes

- Rustige kleuren, veel witruimte en weinig visuele prikkels.
- Eén duidelijke hoofdactie per scherm.
- Eenvoudige Nederlandse taal, korte zinnen en vaste woorden.
- Tekst en iconen samen aanbieden; iconen nooit als enige uitleg.
- Geen streaks, strafmeldingen, aftelstress, scorebord of competitieve beloningen.
- De gebruiker kan onderdelen overslaan, aanpassen of stoppen.
- Geen automatische analyse of diagnose op basis van gedrag of stemming.
- Instelbare tekstgrootte en voorleessnelheid zijn beschikbaar in de instellingen.
- [x] Eigen pictogrammen en foto's per activiteit.
- [x] Optie voor minder animaties (rustige weergave).

## Eerste versie

| Onderdeel | Doel |
|---|---|
| Vandaag | Eerstvolgende stap en overzicht van de dag |
| Planning | Weekoverzicht en eigen dagplan per datum |
| Dagindelingen | Dagplannen bewaren als sjabloon en hergebruiken |
| Vijf vragen | Wie, wat, waar, wanneer en hoe concreet maken |
| Voorlezen | Korte teksten via spraak kunnen beluisteren |
| Even rust | Vrijwillige, niet-klinische grondingsoefening |
| Mijn steun | Persoonlijke afspraken en helpende stappen bewaren |

## Volgende ontwikkelfasen

### Fase 2 — samen instellen
- Profiel zonder diagnosevelden; voorkeuren voor taal, geluid en prikkelniveau.
- Weekoverzicht met een apart dagplan per datum.
- Herbruikbare dagindelingen bewaren, toepassen en verwijderen.
- Vast weekritme per weekdag bewaren en toepassen op lege dagen.
- Gebruikertesten van tekstgrootte, voorleessnelheid en planning.
- [x] Activiteiten met herkenbare pictogrammen en eigen foto's die de gebruiker of begeleider toevoegt (lokaal op het apparaat).
- [x] Rustige weergave met minder animaties, instelbaar en lokaal bewaard.
- [x] Activiteiten in de dagplanning verslepen; de gekozen volgorde blijft bewaard.
- [x] Rustige herinneringen die volledig uit te zetten zijn (in-app, zolang MoodPress open is; standaard uit).
- [x] Volledige lokale back-up en terugzetten van planning, sjablonen, weekritme, steunplan, voorkeuren en activiteitfoto’s, versleuteld met een eigen wachtwoord.
- [x] Een bestaand dagplan rechtstreeks naar een andere datum kopiëren, met behoud van volgorde en terugzetten van alle activiteiten op niet-afgerond.
- [x] Eén losse activiteit naar een andere datum verplaatsen; de overige activiteiten blijven staan en alle details van de verplaatste activiteit blijven behouden.
- [x] Eén losse activiteit naar een andere datum kopiëren; het origineel blijft staan en de kopie begint als niet-afgerond.
- [x] Optioneel stappenplan per activiteit met maximaal 12 korte stappen, afzonderlijk af te vinken en lokaal te bewaren.
- [x] Optionele één-activiteit-tegelijk-weergave met vorige/volgende navigatie, uitleg, foto's en afvinkbare stappen.
- [x] Bij wisselen van dag begint de één-activiteit-tegelijk-weergave opnieuw bij activiteit 1.
- [x] Schermlezers herkennen paginakoppen; de focusweergave kondigt het activiteitnummer en de titel aan als live regio.
- [x] Hoofdnavigatie op Windows is rechtstreeks met Ctrl + 1 tot en met Ctrl + 5 bereikbaar; focusvolgorde volgt de leesvolgorde. De app krijgt bij openen direct toetsenbordfocus zodat de sneltoetsen beschikbaar zijn.

### Fase 3 — zorgvuldig testen
- [x] In de app-instellingen staat in begrijpelijke taal welke gegevens lokaal blijven, wat tijdelijk is en dat foto's in een versleutelde back-up kunnen staan.
- [x] In de app-instellingen staat duidelijk dat MoodPress geen diagnose, behandeling of crisisdienst vervangt, met een verwijzing naar 112 bij direct gevaar.
- [x] Gebruiker kan alle lokale MoodPress-gegevens en activiteitfoto’s bewust verwijderen, na een extra bevestiging. Losse back-upbestanden blijven buiten de app en worden niet verwijderd.
- [x] Widgettest controleert dat de gebruiker het verwijderen van lokale gegevens kan annuleren zonder de wisactie te starten.
- [x] Handmatig testplan opgesteld voor Android, Windows, toetsenbord, schermlezers, prikkelbelasting, privacy en veilige gebruikerstesten. Dit is een voorbereiding; de praktijktesten zelf zijn nog niet uitgevoerd.
- Co-designsessies met autistische deelnemers, mensen met LVB en mensen met PTSS.
- Testen met schermlezers, toetsenbord, touch, Windows scaling en Android toegankelijkheidsinstellingen.
- Evalueren of woorden, beelden, geluiden en rustoefeningen voor verschillende gebruikers prettig en veilig zijn.
- Privacy/security review en besluit over eventuele gegevensuitwisseling.

### Fase 4 — releasevoorbereiding
- Android signing, Windows installer, crash reporting alleen na privacybeoordeling.
- DPIA/AVG-documentatie, verwerkersafspraken indien van toepassing.
- MDR-kwalificatie op basis van definitieve intended purpose.
- Klinische en juridische review vóór claims over effect, behandeling of symptoomvermindering.

## Bewuste productgrens

MoodPress blijft een zelfstandige app voor Android en Windows. Er komt geen begeleidersportaal, online begeleidersomgeving, account, server of betaalde hosting. Plannen en persoonlijke instellingen blijven op het eigen apparaat. Een gebruiker kan zelf een versleutelde back-up opslaan en handmatig meenemen naar een ander apparaat. Ontwikkeling richt zich op functies die zonder terugkerende hostingkosten werken.

## Buiten scope van het prototype

- Diagnose, screening of symptoomscores.
- Traumaverwerking, exposure-oefeningen of het ophalen van traumatische herinneringen.
- Medicatieadvies of medische beslisondersteuning.
- Automatische meldingen aan begeleiders of familie.
- Cloudsync en cliëntdossiers.
