# MoodPress — handmatig toegankelijkheidstestplan

Dit document helpt om MoodPress zorgvuldig te testen voordat de app met echte persoonlijke of cliëntgegevens wordt gebruikt.

**Belangrijk:** dit is een testplan, geen bewijs dat de app al door de doelgroep of door deskundigen is goedgekeurd. De praktijktesten moeten nog worden uitgevoerd. Gebruik tijdens ontwikkel- en testwerk uitsluitend fictieve gegevens.

## 1. Voorwaarden voor iedere testsessie

- Vertel vooraf in eenvoudige taal wat er getest wordt en hoelang het ongeveer duurt.
- Deelname is vrijwillig. De tester mag pauzeren, een onderdeel overslaan of op ieder moment stoppen.
- Vraag toestemming voordat je observaties of feedback noteert. Leg geen onnodige persoonsgegevens vast.
- Gebruik geen vragen over trauma, diagnoses of medische voorgeschiedenis.
- Test niet tijdens een crisis en presenteer MoodPress niet als behandeling of crisisvoorziening.
- Zorg voor een rustige ruimte en bied pauzes aan.
- Noteer apparaat, besturingssysteem, app-versie en eventuele toegankelijkheidsinstellingen.

## 2. Android — aanraken en toegankelijkheid

- [ ] Alle hoofdonderdelen zijn bereikbaar met aanraken.
- [ ] Knoppen en invoervelden zijn groot genoeg en hebben begrijpelijke namen.
- [ ] De gebruiker kan tekst invoeren, opslaan, aanpassen en annuleren.
- [ ] De gebruiker kan een activiteit afronden en een stap weer uitvinken.
- [ ] Dag, week en datum zijn duidelijk herkenbaar.
- [ ] De app blijft bruikbaar met grotere systeemtekst en schermzoom.
- [ ] Controleer TalkBack: volgorde, knopnamen, koppen, statusmeldingen en focus.
- [ ] Controleer dat voorlezen niet onverwacht start en eenvoudig te stoppen is.
- [ ] Controleer dat herinneringen standaard uit staan en uitgeschakeld kunnen blijven.
- [ ] Controleer dat terugknoppen en dialoogvensters logisch werken.

## 3. Windows — toetsenbord en schermweergave

- [ ] Alle belangrijke functies zijn met Tab en Shift+Tab bereikbaar.
- [ ] De focusvolgorde volgt de zichtbare leesvolgorde.
- [ ] De focus is steeds zichtbaar.
- [ ] Ctrl+1 tot en met Ctrl+5 werken.
- [ ] Ctrl+1 tot en met Ctrl+5 werken ook met het numerieke toetsenblok.
- [ ] Enter en spatie activeren de juiste knoppen.
- [ ] De app blijft bruikbaar bij 125%, 150% en 200% Windows-schaling.
- [ ] Controleer NVDA of Narrator op koppen, knoppen, invoervelden en statusmeldingen.
- [ ] Controleer dat vensters en dialoogvensters niet buiten beeld vallen.

## 4. Rust, begrijpelijkheid en prikkelbelasting

Vraag de tester niet om persoonlijke medische informatie. Observeer alleen of de bediening begrijpelijk en prettig is.

- [ ] Per scherm is duidelijk wat de belangrijkste volgende actie is.
- [ ] Teksten zijn kort, concreet en zonder onnodig jargon.
- [ ] Iconen hebben ook tekstlabels.
- [ ] Kleur is niet de enige manier waarop informatie wordt overgebracht.
- [ ] De gebruiker kan onderdelen overslaan en later terugkomen.
- [ ] De gebruiker ervaart geen straf, score, tijdsdruk of verplichting.
- [ ] De instelling voor minder beweging werkt zoals verwacht.
- [ ] Tekstgrootte en voorleessnelheid zijn eenvoudig aan te passen.
- [ ] Geluid of voorlezen verrast de gebruiker niet.
- [ ] De oefening 'Even rust' blijft vrijblijvend en kan direct worden verlaten.

## 5. Gegevens, back-up en herstel

Voer deze controles uitsluitend uit met fictieve testgegevens.

- [ ] Plannen, voorkeuren en steuninformatie blijven na opnieuw starten beschikbaar.
- [ ] Een versleutelde back-up kan worden gemaakt.
- [ ] Een back-up kan met het juiste wachtwoord worden teruggezet.
- [ ] Een verkeerd wachtwoord geeft een begrijpelijke foutmelding.
- [ ] Een beschadigd of niet-ondersteund bestand wordt veilig geweigerd.
- [ ] De gebruiker krijgt vóór het vervangen van bestaande gegevens een duidelijke bevestiging.
- [ ] Het wachtwoord wordt niet in de app opgeslagen of in meldingen getoond.
- [ ] Er wordt geen account, cloudverbinding, begeleidersportaal of betaalde hosting vereist.

## 6. Vragen na een taak

Stel één vraag tegelijk en geef voldoende bedenktijd.

- Wat dacht je dat er zou gebeuren toen je hierop drukte?
- Was er iets onduidelijk?
- Was er iets dat te druk of te veel voelde?
- Kon je makkelijk terug of stoppen?
- Wat zou je anders willen zien?

Laat de tester ook aangeven dat een onderdeel goed genoeg is. Probeer geen gewenst antwoord uit te lokken.

## 7. Registratie van bevindingen

Noteer per bevinding:

- App-versie en apparaat.
- Onderdeel en uitgevoerde handeling.
- Wat er feitelijk gebeurde.
- Wat de tester zelf aangaf (alleen met toestemming).
- Ernst: blokkerend, belangrijk of klein.
- Voorgestelde verbetering en hertestresultaat.

Verzamel geen namen, diagnoses, trauma-informatie, contactgegevens of andere gegevens die niet nodig zijn om een softwarefout te beschrijven.

## 8. Wanneer niet vrijgeven

Gebruik MoodPress niet als enige ondersteuning in een zorgsituatie en gebruik geen echte cliëntgegevens zolang de benodigde beoordelingen ontbreken. Stel een release uit bij verlies of vermenging van gegevens, onbedoelde gegevensdeling, onveilige back-up/restore, ontoegankelijke kernfuncties of onduidelijke risicomeldingen.

Voor een praktijktest of pilot zijn afzonderlijke privacy- en beveiligingsbeoordeling, passende toestemming, doelgroepbetrokkenheid en professionele toetsing nodig. Dit testplan vervangt die stappen niet.
