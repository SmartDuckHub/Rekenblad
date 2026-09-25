# Rekenblad

Een rekenblad in een grafisch venster, in de stijl van Schrijf en
Kalender (FreeBASIC / fblite-dialect, gfxlib). Twaalf tabbladen van 260
kolommen (A..IZ) bij 4096 rijen, met formules.

## Vertalen en starten

```
fbc -lang fblite rekenblad.bas
```

```
rekenblad [bestand] [-zN] [-wBxH] [-a|-c]
```

- `bestand` - werkmap om te openen (standaard: `<exepad>/bladen/werkblad.bld`)
- `-zN` - tekens N keer zo groot (1..6); anders de laatst gekozen
  schaal uit `Rekenblad.cfg`. Tijdens het draaien met F11/F12.
- `-wBxH` - venster nooit groter dan B bij H pixels, bv. `-w640x480`
- `-a` - ASCII-randen in plaats van lijntekens
- `-c` - CP437-lijntekens (standaard)

## Invoer

Een getal is een getal, een formule begint met `=`, `+` of `@`, al het
andere is tekst. Met een apostrof vooraf (`'123`) wordt een getal
alsnog tekst. F10 of Esc opent het menu.

## Bestandsformaat

Platte tekst, dus ook buiten Rekenblad te lezen:

```
# Rekenblad 1
## blad Begroting
! kolom A breedte=18
! kolom B breedte=12 dec=2
A1: Omschrijving
B1: Bedrag
A2: Huur
B2: 850
B9: =SOM(B2:B8)
```

## Menu

F10 of Esc opent de menubalk (net als in Woord): pijltjes-links/rechts
wisselen van categorie, pijltjes-omhoog/omlaag van item, Enter kiest,
Esc of F10 sluit het menu weer zonder iets te doen. Categorieën:
Bestand, Bewerken, Blad, Opmaak, Extra, Help. De balk zelf blijft
altijd bovenaan staan.

Afsluiten gaat met Ctrl+Q of via Stoppen in het Bestand-menu; Esc
sluit het programma dus niet meer af, die opent het menu.

## Sneltoetsen

| Toets | Werking |
|---|---|
| Pijltjes / Home / End / PgUp / PgDn | Cursor verplaatsen |
| Enter / Insert | Cel bewerken |
| Tab | Een cel naar rechts |
| Backspace / Delete | Huidige cel wissen |
| F10 / Esc | Menu openen |
| F1 | Hulp |
| F2 | Cel bewerken |
| F3 | Kolombreedte |
| F4 | Kolomopmaak |
| F5 | Ga naar cel |
| F6 / F7 | Volgend / vorig tabblad |
| F8 | Alles herberekenen |
| F9 | Zoeken |
| F11 / F12 | Tekens kleiner / groter |
| Ctrl+Q | Afsluiten |
| Ctrl+S | Opslaan |
| Ctrl+P | Afdrukken |
| Ctrl+T | Instellingen (printer, taal) |
| Ctrl+Z | Over Rekenblad |
| Ctrl+K / Ctrl+V | Kopiëren / plakken |
| Ctrl+W | Bereik leegmaken |
| Ctrl+G | Ga naar cel |
| Ctrl+F | Zoeken |
| Ctrl+N | Nieuw tabblad |

## Instellingen (`Rekenblad.cfg`)

Wordt automatisch aangemaakt naast de werkmap. Met de hand aan te
passen mag:

```
schaal=1
taal=auto
printraw=0
printer=
```

- `schaal` - tekengrootte (1-6), ook te wijzigen via F11/F12
- `taal` - `nl`, `en`, of `auto` (systeemtaal, valt terug op Engels
  als die niet is te bepalen)
- `printraw` - `1` = platte tekst naar een matrixprinter, `0` =
  PostScript naar de standaardprinter
- `printer` - printernaam voor `lpr -P`; leeg = systeemstandaard

Alles ook in te stellen tijdens het draaien met Ctrl+T, of via
"Instellingen..." in het Bestand-menu.

## Afdrukken

Ctrl+P, of "Afdrukken..." in het Bestand-menu, drukt het huidige
tabblad af, met dezelfde kolombreedtes en uitlijning als op het
scherm; tekst die breder is dan zijn kolom loopt op papier net als op
het scherm door over lege buurcellen rechts. Bredere
werkbladen worden automatisch in verticale kolombanden verdeeld (eerst
alle pagina's van kolommen A..x, dan de volgende band), en elke band
weer in pagina's van rijen. Op Linux gaat dit via `lpr` (CUPS
vertaalt PostScript zelf naar wat de printer nodig heeft); op Windows
is een poort- of printernaam nodig (zie `printer` hierboven).

## Vertalen naar een andere taal

Zet `taal=en` (of een andere taalcode) in `Rekenblad.cfg`, en leg een
bestand `rekenblad_taal_<code>.txt` naast de werkmap of naast het
programma, met regels van de vorm:

```
nederlandse tekst => vertaalde tekst
```

Regels die met `'` beginnen zijn commentaar; ontbrekende vertalingen
vallen terug op de Nederlandse brontekst. `%1`, `%2` en `%3` zijn
invulplekken die in de vertaling moeten blijven staan; hun volgorde
mag wel wijzigen.

Een volledige Engelse vertaling zit erbij als `rekenblad_taal_en.txt`.
Let op: de teksten in `rekenblad.bas` zelf lopen nog niet allemaal
door het vertaalsysteem, dus in deze versie blijft een deel van de
interface Nederlands ook als `taal=en` aan staat. De menubalk, het
afdrukken, het instellingenscherm en "Over Rekenblad" zijn al wel om.

## Bekende problemen

- **F11/F12 (tekens kleiner/groter) reageren soms niet.** Twee
  mogelijke oorzaken: (1) de desktopomgeving vangt F11/F12 systeembreed
  af (vaak gebonden aan "volledig scherm" e.d.) — controleer de
  sneltoetsen in je systeeminstellingen; (2) het inlezen van het
  lettertype bij het opstarten faalt stil op sommige grafische
  backends, waardoor schalen boven 1x geblokkeerd blijft. Gebruik
  "Toetsproef..." onder Extra in het menu om te zien of de toetsen
  überhaupt bij het programma aankomen.

## Bouwtechniek

Altijd een venster van gfxlib, nooit de tekstconsole: de
console-driver van FB vangt op Unix de speciale toetsen niet
betrouwbaar af en kent daar geen CP437, terwijl gfxlib overal
`Chr(255)` + scancode levert en een compleet CP437-font meebrengt.
32 bpp, met een zelf ingesteld palet. Bij schaal 1 tekent FB zelf met
het ingebouwde 8x16-font; bij een hogere schaal worden de tekens zelf
getekend, vergroot (via het lettertype dat bij het opstarten wordt
ingelezen — zie "Bekende problemen" hierboven).
