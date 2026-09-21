# Changelog - Rekenblad

Alle noemenswaardige wijzigingen aan Rekenblad staan hier, nieuwste bovenaan.

## 0.5 

### Toegevoegd
- Inplaats van 8 tabbladen nu 12 tabladen. Dit is handiger om per
  maand een blad te hebben.
- Matrix groter gemaakt, 260 x 4096.

### Opgelost
- Printen van tekst over meerdere kolommen.
- Rest van de vertaling verwerkt in het vertaalbestand.

## 0.4

### Toegevoegd
- "Over Rekenblad" (Ctrl+Z, of onder Help in het menu), met copyright
  en licentie, zelfde opzet als Woord's Over-scherm.
- Volledige Engelse vertaling van de interface in
  `rekenblad_taal_en.txt` (~185 regels, gegroepeerd per onderdeel).
  De functienamen (SOM, GEM, AFROND, ALS...) en de foutcodes
  (`#NAAM?`, `#DEEL/0`) blijven bewust onvertaald: die zitten in het
  bestandsformaat, vertalen zou bestaande werkmappen onleesbaar maken.

### Opgelost
- Bij het afdrukken werd tekst die breder was dan de kolom afgekapt op
  de kolombreedte. Op papier loopt zulke tekst nu, net als op het
  scherm, door over lege buurcellen rechts (nieuwe gedeelde functie
  `MaakDataRegel`, gebruikt door zowel de PostScript- als de
  platte-tekstafdruk).

### Nog te doen
- De Nederlandse teksten in `rekenblad.bas` zelf lopen nog niet door
  `Vt(...)`/`Tn(...)`. Het vertaalbestand is compleet, maar pas als de
  code de teksten erdoorheen haalt, doet `taal=en` daadwerkelijk iets.
  De modules (menu, print, instellingen, Over-scherm) zijn al wel om.

## 0.3

### Toegevoegd
- Menubalk zoals in Woord (`rekenblad_menu.bi`): staat altijd bovenaan,
  F10 of Esc opent 'm, categorieën Bestand/Bewerken/Blad/Opmaak/Extra/
  Help, pijltjes links/rechts wisselen van categorie en omhoog/omlaag
  van item, Enter kiest. Vervangt het oude platte "/"-opdrachtenmenu.
  Dezelfde kleuren als Woord's menubalk, met de eerste letter van elke
  categorie in een afwijkende kleur.
- Afdrukken van het huidige tabblad (`rekenblad_print.bi`, Ctrl+P):
  PostScript via `lpr`, of platte tekst naar een matrixprinter
  (`printraw=1` in `Rekenblad.cfg`). Bredere werkbladen worden
  automatisch in verticale kolombanden en pagina's van rijen verdeeld,
  met dezelfde opmaak (breedte/uitlijning) als op het scherm.
- Vertaalsysteem (`rekenblad_taal.bi`), zelfde opzet als in Woord:
  `Vt(...)`/`Tn(...)`, taaldetectie via de omgeving, `taal=nl/en/auto`
  in `Rekenblad.cfg`, vertaalbestand `rekenblad_taal_<code>.txt`.
- Instellingenscherm (Ctrl+T, of "Instellingen..." in het Bestand-menu)
  voor taal, matrixprinter aan/uit en printer/poort -- zoals Woord dat
  met F6 doet.

### Gewijzigd
- De titelbalk is vervangen door de menubalk; de `*` voor een gewijzigd
  document staat nu vooraan in de statusregel.
- Afsluiten gaat via Ctrl+Q of Stoppen in het Bestand-menu; Esc en F10
  openen voortaan het menu in plaats van het programma te beëindigen.

### Verwijderd
- Alle verwijzingen naar Lotus 1-2-3 uit code, hulptekst en
  documentatie (Rekenblad is altijd al een eigen ontwerp geweest, de
  invoerregels en het oude "/"-menu waren er alleen op geïnspireerd).

### Opgelost
- Naamsbotsingen tussen eigen parameternamen en bestaande
  Subs/Functions in `rekenblad.bas` (fblite is niet hoofdlettergevoelig
  en laat geen parameter toe die dezelfde naam heeft als een bestaande
  Sub/Function): `zoek` -> `patroon` in `VervangEerste`/`SubstAll`,
  `pad` -> `padBestand` in `BaseNaam`.
- Crash ("free(): invalid size") bij het openen van het menu, doordat
  de itemlijst van het oude opdrachtenmenu te klein was gedimensioneerd
  voor de toegevoegde regels.

## 0.2

### Bekend probleem
- F11/F12 (tekens kleiner/groter) reageren op sommige systemen niet.
  Mogelijke oorzaken: de desktopomgeving vangt F11/F12 systeembreed af
  (controleer de sneltoetsen in je systeeminstellingen), of het
  inlezen van het lettertype bij het opstarten (`LeesFont`) faalt
  stil, waardoor schalen boven 1x geblokkeerd blijft. Zie de README
  onder "Bekende problemen".

## 0.1 - eerste versie
- Basiswerking: tabbladen, cellen, formules, klembord, zoeken, rij en
  kolom invoegen en verwijderen, CSV-export, eigen platte-tekst
  bestandsformaat.
