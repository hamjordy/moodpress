# Veiligheid en privacy — uitgangspunten

## Doelgroepgerichte veiligheid

Autisme, LVB en PTSS zijn niet hetzelfde en niet iedere gebruiker heeft dezelfde behoeften. De app biedt daarom opties en geen vaste route die iedereen moet volgen.

- Geen opdrachten die iemand dwingen een activiteit af te maken.
- Geen exposure, traumaverwerking, diagnosevragenlijsten of klinische interpretatie.
- Geen automatische interpretatie van een stemming of check-in.
- De check-in is tijdelijk en wordt niet bewaard als gezondheidsprofiel.
- Rustoefeningen zijn optioneel en kunnen direct worden verlaten.
- Een melding over direct gevaar verwijst naar menselijke hulp; de app doet niet alsof zij een crisisdienst is.

## Gegevens

In het prototype:

- Geen account of cloudbackend.
- Geen advertenties, tracking of analytics.
- Dagplanning en persoonlijk steunplan worden lokaal opgeslagen met `flutter_secure_storage`.
- Deel geen echte cliëntgegevens in ontwikkel-, demo- of testomgevingen.

Voor een cliëntpilot moet de verantwoordelijke organisatie onder meer vaststellen wie verwerkingsverantwoordelijke is, wat de rechtsgrond is, welke data noodzakelijk zijn, wie toegang krijgt, hoe lang gegevens worden bewaard en hoe verwijdering en inzage worden geregeld. Beoordeel of een DPIA verplicht is en laat de implementatie onafhankelijk testen.

## Incidenten en noodsituaties

MoodPress kan geen toezicht houden en garandeert geen hulpverlening. Bij direct gevaar moet de gebruiker of begeleider rechtstreeks contact opnemen met hulpdiensten of het afgesproken zorgteam. Een app-scherm mag nooit de enige beschikbare veiligheidsroute zijn.

## Klinische en juridische toets

De Europese MDR-richtsnoeren beschrijven dat software, waaronder apps, op basis van het beoogde doel kan kwalificeren als medische hulpmiddelsoftware. De uiteindelijke functies en marketingclaims moeten daarom worden getoetst voordat MoodPress wordt uitgebracht of in een zorgsetting wordt ingezet.
