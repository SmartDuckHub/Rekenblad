#lang "fblite"

'' ==========================================================================
''  Rekenblad 0.5  --  rekenblad in een grafisch venster
''  In de stijl van Woord (FreeBASIC / fblite dialect)
''
''  Copyright 2026 door Marcel "Smart Duck" Beekman
'' 
''  Licentie :  BSD 3-Clause
''
''  Vertalen:   fbc rekenblad.bas
''  Starten :   rekenblad [bestand] [-zN] [-wBxH] [-a|-c]
''                bestand = werkmap (standaard: <exepad>/bladen/werkblad.bld)
''                -zN = tekens N keer zo groot (1..6); anders de laatst gekozen
''                      schaal uit Rekenblad.cfg. Tijdens het draaien met F11/F12.
''                -wBxH = venster nooit groter dan B bij H pixels, bv. -w640x480
''                -a  = ASCII-randen in plaats van lijntekens
''                -c  = CP437-lijntekens (standaard)
''
''  Een werkmap heeft maximaal 12 tabbladen van 256 kolommen (A..IV) bij 1024
''  rijen. Alleen gevulde cellen kosten geheugen; per tabblad passen er
''  MAX_CEL van.
''
''  Bestandsformaat: platte tekst, dus ook buiten Rekenblad te lezen:
''
''      # Rekenblad 1
''      ## blad Begroting
''      ! kolom A breedte=18
''      ! kolom B breedte=12 dec=2
''      A1: Omschrijving
''      B1: Bedrag
''      A2: Huur
''      B2: 850
''      B9: =SOM(B2:B8)
''
''  Invoer werkt als volgt: een getal is een getal, een formule
''  begint met =, + of @, al het andere is tekst. Met een apostrof vooraf
''  ('183) wordt een getal alsnog tekst. F10 of Esc opent het menu.
'' ==========================================================================

Const APP_NAAM  = "Rekenblad"
Const APP_VER   = "0.5"
Const SEP       = "/"

Const MAX_KOL   = 260           '' A .. IZ
Const MAX_RIJ   = 4096
Const MAX_BLAD  = 12            '' tabbladen
Const MAX_CEL   = 6000          '' gevulde cellen per tabblad
Const MAX_TXT   = 200           '' langste celinvoer
Const MAX_HITS  = 200
Const MAX_KLEM  = 2000          '' cellen op het klembord

Const MIN_BREED = 3             '' kolombreedte
Const MAX_BREED = 40
Const STD_BREED = 10

'' --- grafische modus -----------------------------------------------------
''  Altijd een venster van gfxlib, nooit de tekstconsole: de console-driver van
''  FB vangt op Unix de speciale toetsen niet betrouwbaar af en kent daar geen
''  CP437, terwijl gfxlib overal Chr(255) + scancode levert en een compleet
''  CP437-font meebrengt. We kiezen 32 bpp en geven het palet zelf op.
''
''  De vensterafmeting volgt uit de indeling:
''      pixels = kolommen * 8 * schaal  bij  rijen * 16 * schaal
''  Bij schaal 1 tekent FB zelf met het ingebouwde 8x16 font (snel); bij een
''  hogere schaal tekenen we de tekens zelf, vergroot.
Const VEN_KOL   = 96      '' gewenst aantal tekstkolommen (een raster is breed)
Const VEN_RIJ   = 32      '' gewenst aantal tekstrijen
Const MIN_KOL   = 40
Const MIN_RIJ   = 12
Const MAX_SCH   = 6

Const GUT       = 6       '' breedte van de rijkoppenkolom, inclusief streep

'' --- kleuren (indices in het zelf ingestelde palet) ----------------------
Const C_BALK_FG = 0     : Const C_BALK_BG = 7     '' titel- en helpbalk
Const C_BG      = 1                               '' achtergrond werkvlak
Const C_RAND    = 7                               '' randen
Const C_KOP_FG  = 8     : Const C_KOP_BG  = 7     '' kolom- en rijkoppen
Const C_KOPA_FG = 15    : Const C_KOPA_BG = 8     '' kop van de actieve rij/kolom
Const C_GETAL   = 15                              '' getalcel
Const C_TEKST   = 11                              '' tekstcel
Const C_FORM    = 10                              '' uitkomst van een formule
Const C_FOUT    = 12                              '' foutwaarde
Const C_SEL_FG  = 15  : Const C_SEL_BG = 3        '' cursorcel
Const C_INV_FG  = 14  : Const C_INV_BG = 0        '' invoerregel
Const C_TAB_FG  = 7                               '' inactief tabblad
Const C_DLG_FG  = 0   : Const C_DLG_BG = 7        '' dialoogvenster

'' --- celsoorten ----------------------------------------------------------
Const S_LEEG    = 0
Const S_GETAL   = 1
Const S_TEKST   = 2
Const S_FORM    = 3

'' --- foutcodes -----------------------------------------------------------
Const F_GEEN    = 0
Const F_DEEL    = 1       '' delen door nul
Const F_NAAM    = 2       '' onbekende naam of functie
Const F_SYNT    = 3       '' onbegrijpelijke formule
Const F_KRING   = 4       '' kringverwijzing
Const F_VERW    = 5       '' verwijzing bestaat niet meer
Const F_GETAL   = 6       '' rekenkundig onmogelijk
Const F_ARG     = 7       '' verkeerd aantal argumenten
Const F_DIEP    = 8       '' te lange ketting van verwijzingen

'' Hoe diep formules naar elkaar mogen verwijzen. Iedere stap kost stapelruimte,
'' dus ergens moet een grens liggen; 120 is voor gewoon rekenwerk ruim genoeg.
Const MAX_DIEP  = 120

'' --- uitlijning ----------------------------------------------------------
Const U_AUTO    = 0
Const U_LINKS   = 1
Const U_RECHTS  = 2
Const U_MIDDEN  = 3

'' --- gegevensstructuren --------------------------------------------------
Type CelType
    tekst    As String        '' de ruwe invoer, precies zoals getypt
    waarde   As Double        '' laatst berekende getalswaarde
    k        As Integer       '' kolom 0..MAX_KOL-1  (de cel kent zijn plek,
    r        As Integer       '' rij   0..MAX_RIJ-1   zodat opruimen simpel is)
    soort    As Integer
    fout     As Integer
    merk     As Integer       '' generatie van de laatste herberekening
    bezig    As Integer       '' -1 tijdens het berekenen: vangt kringen af
End Type

'' Het tabblad houdt een verwijstabel bij van kolom/rij naar celnummer. Die
'' kost 256 * 1024 * 4 byte = 1 MB per tabblad, en daarmee is opzoeken gratis.
'' Vandaar Long en niet Integer: Integer is op een 64-bits build 8 byte breed.
Type BladType
    naam     As String
    aantal   As Integer
    curK     As Integer
    curR     As Integer
    topK     As Integer
    topR     As Integer
    breed(0 To MAX_KOL - 1) As Integer
    dec(0 To MAX_KOL - 1)   As Integer     '' -1 = algemeen, 0..6 = vast
    uit(0 To MAX_KOL - 1)   As Integer
    idx(0 To MAX_KOL - 1, 0 To MAX_RIJ - 1) As Long
    cel(1 To MAX_CEL) As CelType
End Type

Dim Shared blad(1 To MAX_BLAD) As BladType
Dim Shared nBladen    As Integer
Dim Shared curB       As Integer
Dim Shared tabTop     As Integer          '' eerste zichtbare tabblad
Dim Shared bestand    As String
Dim Shared dataMap    As String
Dim Shared gewijzigd  As Integer
Dim Shared melding    As String
Dim Shared stoppen    As Integer

'' --- klembord ------------------------------------------------------------
Dim Shared klemN      As Integer
Dim Shared klemK(1 To MAX_KLEM) As Integer
Dim Shared klemR(1 To MAX_KLEM) As Integer
Dim Shared klemT(1 To MAX_KLEM) As String
Dim Shared klemK1     As Integer
Dim Shared klemR1     As Integer
Dim Shared klemK2     As Integer
Dim Shared klemR2     As Integer

'' --- rekenmachine --------------------------------------------------------
Dim Shared fTxt       As String           '' formule die nu ontleed wordt
Dim Shared fPos       As Integer
Dim Shared fBlad      As Integer          '' blad waarin die formule staat
Dim Shared fFout      As Integer
Dim Shared gen        As Integer          '' generatieteller voor herberekenen
Dim Shared fDiepte    As Integer          '' hoe diep we in verwijzingen zitten

'' --- scherm --------------------------------------------------------------
Dim Shared scrW       As Integer
Dim Shared scrH       As Integer
Dim Shared pal(0 To 15) As UInteger
Dim Shared fontSchaal As Integer
Dim Shared celB       As Integer
Dim Shared celH       As Integer
Dim Shared venMaxB    As Integer
Dim Shared venMaxH    As Integer
Dim Shared bureauB    As Integer
Dim Shared bureauH    As Integer
Dim Shared fontBits(0 To 255, 0 To 15) As UByte
Dim Shared fontOk     As Integer
Dim Shared rTop       As Integer          '' eerste rasterregel
Dim Shared rBot       As Integer          '' laatste rasterregel

'' --- tekens voor randen en symbolen --------------------------------------
Dim Shared gTL As String, gTR As String, gBL As String, gBR As String
Dim Shared gH  As String, gV  As String, gTd As String, gBd As String
Dim Shared dbTL As String, dbTR As String, dbBL As String, dbBR As String
Dim Shared dbH  As String, dbV  As String
Dim Shared gPijl As String, gPunt As String

'' --- declaraties ---------------------------------------------------------
Declare Sub ZetGlyphs(ByVal asciiModus As Integer)
Declare Sub ZetPalet()
Declare Sub Indeling()
Declare Function SetScale(ByVal nieuw As Integer) As Integer
Declare Sub SchaalWijzig(ByVal delta As Integer)
Declare Sub LaadInstellingen()
Declare Sub BewaarInstellingen()
Declare Sub LeesFont()
Declare Sub TekenCellen(ByVal r As Integer, ByVal c As Integer, ByRef s As String, ByVal fgc As UInteger, ByVal bgc As UInteger)
Declare Function SchermInit() As Integer
Declare Function Pad(ByRef s As String, ByVal n As Integer) As String
Declare Function PadL(ByRef s As String, ByVal n As Integer) As String
Declare Function Kort(ByRef s As String, ByVal n As Integer) As String
Declare Sub PutStr(ByVal r As Integer, ByVal c As Integer, ByRef s As String, ByVal fg As Integer, ByVal bg As Integer)
Declare Function LeesTeken(ByVal msWacht As Integer) As String
Declare Function WachtToets(ByRef ext As Integer) As Integer

Declare Sub Venster(ByVal r As Integer, ByVal c As Integer, ByVal h As Integer, ByVal w As Integer, ByRef titel As String)
Declare Sub Melden(ByRef tekst As String)
Declare Function Bevestig(ByRef vraag As String) As Integer
Declare Function RegelEdit(ByVal r As Integer, ByVal c As Integer, ByVal w As Integer, ByRef start As String, ByRef ok As Integer) As String
Declare Function VraagTekst(ByRef titel As String, ByRef prompt As String, ByRef start As String, ByRef ok As Integer) As String
Declare Function Kies(ByRef titel As String, items() As String, ByVal n As Integer, ByVal start As Integer) As Integer
Declare Sub ToonHelp()

Declare Function KolNaam(ByVal k As Integer) As String
Declare Function KolNummer(ByRef s As String) As Integer
Declare Function CelNaam(ByVal k As Integer, ByVal r As Integer) As String
Declare Function BladNummer(ByRef naam As String) As Integer
Declare Function IsGetal(ByRef s As String) As Integer
Declare Function VastGetal(ByVal w As Double, ByVal n As Integer) As String
Declare Function AlgGetal(ByVal w As Double, ByVal breedte As Integer) As String
Declare Function FoutTekst(ByVal code As Integer) As String
Declare Function SchoneNaam(ByRef s As String) As String

Declare Function CelNr(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As Integer
Declare Function MaakCel(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As Integer
Declare Sub KopieerCelData(ByVal bd As Integer, ByVal id As Integer, ByVal bs As Integer, ByVal is1 As Integer)
Declare Sub WisCel(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer)
Declare Sub ZetCelTekst(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer, ByRef s As String)
Declare Function CelTekst(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As String
Declare Sub HerbouwIndex(ByVal b As Integer)
Declare Sub LeegBlad(ByVal b As Integer, ByRef naam As String)

Declare Function LeesRefOp(ByRef s As String, ByVal p As Integer, ByRef eind As Integer, ByRef bn As String, ByRef absK As Integer, ByRef k As Integer, ByRef absR As Integer, ByRef r As Integer) As Integer
Declare Function RefTekst(ByRef bn As String, ByVal absK As Integer, ByVal k As Integer, ByVal absR As Integer, ByVal r As Integer) As String
Declare Function VerschuifFormule(ByRef s As String, ByVal dk As Integer, ByVal dr As Integer) As String
Declare Sub PasRefsAan(ByVal doelB As Integer, ByVal isKolom As Integer, ByVal vanaf As Integer, ByVal delta As Integer)

Declare Sub SlaSpatiesOver()
Declare Function Volgende() As String
Declare Function LeesCelRef(ByRef b As Integer, ByRef k As Integer, ByRef r As Integer) As Integer
Declare Function LeesBereik(ByRef b As Integer, ByRef k1 As Integer, ByRef r1 As Integer, ByRef k2 As Integer, ByRef r2 As Integer) As Integer
Declare Function CelWaarde(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As Double
Declare Function BerekenCel(ByVal b As Integer, ByVal ci As Integer) As Double
Declare Function Vergelijking() As Double
Declare Function Som() As Double
Declare Function Term() As Double
Declare Function Macht() As Double
Declare Function Unair() As Double
Declare Function Primair() As Double
Declare Function Functie(ByRef naam As String) As Double
Declare Function Aggregeer(ByVal soort As Integer) As Double
Declare Sub LeesArgs(a() As Double, ByRef n As Integer, ByVal maxN As Integer)
Declare Sub VerwachtSluit()
Declare Sub Verzamel(ByVal w As Double, ByRef n As Integer, ByRef tot As Double, ByRef mn As Double, ByRef mx As Double)
Declare Sub Herbereken()

Declare Sub LaadBestand()
Declare Sub SlaOp(ByRef naam As String)
Declare Sub SlaOpAls()
Declare Sub ExportCsv()
Declare Sub MaakDemo()

Declare Sub Invoer(ByRef start As String)
Declare Sub BewerkCel()
Declare Sub WisHuidige()
Declare Sub KolomBreedte()
Declare Sub KolomOpmaak()
Declare Function VraagBereik(ByRef titel As String, ByRef prompt As String, ByRef start As String, ByRef k1 As Integer, ByRef r1 As Integer, ByRef k2 As Integer, ByRef r2 As Integer) As Integer
Declare Sub Kopieer()
Declare Sub Plak()
Declare Sub BlokWissen()
Declare Sub RijInvoegen()
Declare Sub RijVerwijderen()
Declare Sub KolomInvoegen()
Declare Sub KolomVerwijderen()
Declare Sub GaNaar()
Declare Sub Zoek()

Declare Sub NieuwBlad()
Declare Sub HernoemBlad()
Declare Sub VerwijderBlad()
Declare Sub WisselBlad(ByVal delta As Integer)
Declare Sub KopieerBlad(ByVal bd As Integer, ByVal bs As Integer)
Declare Sub HernoemVerwijzingen(ByRef oud As String, ByRef nieuw As String)
Declare Sub ToetsProef()

Declare Sub ZorgZichtbaar()
Declare Function LaatsteKolom() As Integer
Declare Sub CelToon(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer, ByVal breedte As Integer, ByRef uit1 As String, ByRef kleur As Integer, ByRef isTxt As Integer)
Declare Function Uitlijn(ByRef s As String, ByVal breedte As Integer, ByVal uit As Integer, ByVal isTxt As Integer) As String
Declare Sub TekenInvoerregel()
Declare Sub TekenKoppen()
Declare Sub TekenRaster()
Declare Sub TekenTabs()
Declare Sub TekenStatus()
Declare Sub TekenHelp()
Declare Sub Redraw()

#include "rekenblad_taal.bi"
#include "rekenblad_print.bi"
#include "rekenblad_menu.bi"

'' ==========================================================================
''  Scherm, font en toetsen
'' ==========================================================================

Sub ZetGlyphs(ByVal asciiModus As Integer)
    If asciiModus Then
        gTL = "+" : gTR = "+" : gBL = "+" : gBR = "+"
        gH  = "-" : gV  = "|" : gTd = "+" : gBd = "+"
        dbTL = "+" : dbTR = "+" : dbBL = "+" : dbBR = "+"
        dbH  = "=" : dbV  = "|"
        gPijl = ">" : gPunt = "-"
    Else
        gTL = Chr(218) : gTR = Chr(191) : gBL = Chr(192) : gBR = Chr(217)
        gH  = Chr(196) : gV  = Chr(179) : gTd = Chr(194) : gBd = Chr(193)
        dbTL = Chr(201) : dbTR = Chr(187) : dbBL = Chr(200) : dbBR = Chr(188)
        dbH  = Chr(205) : dbV  = Chr(186)
        gPijl = Chr(16) : gPunt = Chr(250)
    End If
End Sub

'' Het klassieke VGA-16 palet, expliciet als RGB. Omdat we in 32 bpp werken zijn
'' dit echte kleurwaarden en geen palet-indices meer, dus overlap is uitgesloten.
Sub ZetPalet()
    pal(0)  = RGB(  0,   0,   0)    '' zwart
    pal(1)  = RGB(  0,   0, 160)    '' blauw        (achtergrond werkvlak)
    pal(2)  = RGB(  0, 150,   0)    '' groen
    pal(3)  = RGB(  0, 140, 150)    '' cyaan        (cursorcel)
    pal(4)  = RGB(170,   0,   0)    '' rood
    pal(5)  = RGB(170,   0, 170)    '' magenta
    pal(6)  = RGB(170,  85,   0)    '' bruin
    pal(7)  = RGB(180, 180, 180)    '' lichtgrijs   (randen, balken)
    pal(8)  = RGB( 90,  90,  90)    '' donkergrijs
    pal(9)  = RGB( 85,  85, 255)    '' lichtblauw
    pal(10) = RGB( 85, 255,  85)    '' lichtgroen   (formule-uitkomst)
    pal(11) = RGB(120, 235, 255)    '' lichtcyaan   (tekstcel)
    pal(12) = RGB(255,  95,  95)    '' lichtrood    (fout)
    pal(13) = RGB(255, 120, 255)    '' lichtmagenta
    pal(14) = RGB(255, 230, 120)    '' geel         (invoerregel)
    pal(15) = RGB(255, 255, 255)    '' wit          (getalcel)
End Sub

'' Herberekent de indeling uit scrW/scrH. Wordt na elke schaalwijziging
'' opnieuw aangeroepen.
''   rij 1          menubalk
''   rij 2          invoerregel (celverwijzing + ruwe inhoud)
''   rij 3          kolomkoppen
''   rij 4..scrH-3  het raster
''   rij scrH-2     tabbladen
''   rij scrH-1     statusregel
''   rij scrH       helpbalk
Sub Indeling()
    rTop = 4
    rBot = scrH - 3
End Sub

'' Zet de schaal tijdens het draaien. Geeft -1 bij succes en 0 als de gevraagde
'' schaal niet past; in dat laatste geval blijft de oude toestand ongemoeid.
Function SetScale(ByVal nieuw As Integer) As Integer
    Dim kol As Integer, rij As Integer
    Dim nb As Integer, nh As Integer
    Dim grensB As Integer, grensH As Integer

    SetScale = 0
    If nieuw < 1 Then nieuw = 1
    If nieuw > MAX_SCH Then nieuw = MAX_SCH
    If nieuw > 1 And fontOk = 0 Then Exit Function

    nb = 8  * nieuw
    nh = 16 * nieuw

    grensB = venMaxB
    grensH = venMaxH
    If grensB <= 0 Then
        If bureauB > 0 Then grensB = bureauB - bureauB \ 20 Else grensB = 0
    End If
    If grensH <= 0 Then
        If bureauH > 0 Then grensH = bureauH - bureauH \ 12 Else grensH = 0
    End If

    kol = VEN_KOL
    rij = VEN_RIJ
    If grensB > 0 Then
        If kol * nb > grensB Then kol = grensB \ nb
    End If
    If grensH > 0 Then
        If rij * nh > grensH Then rij = grensH \ nh
    End If

    If kol < MIN_KOL Or rij < MIN_RIJ Then Exit Function

    ScreenRes kol * nb, rij * nh, 32
    WindowTitle APP_NAAM + " " + APP_VER

    fontSchaal = nieuw
    celB = nb
    celH = nh
    scrW = kol
    scrH = rij

    If fontSchaal = 1 Then Width scrW, scrH

    Indeling
    Color pal(C_RAND), pal(C_BG)
    Cls
    Locate , , 0
    SetScale = -1
End Function

Sub SchaalWijzig(ByVal delta As Integer)
    Dim gevraagd As Integer

    gevraagd = fontSchaal + delta
    If gevraagd < 1 Or gevraagd > MAX_SCH Then
        melding = Tn("Schaal %1x is al de grens.", Trim(Str(fontSchaal)), "", "")
        Exit Sub
    End If

    If SetScale(gevraagd) Then
        BewaarInstellingen
        melding = Tn("Schaal %1x %2 tekens van %3 pixels", Trim(Str(fontSchaal)), _
                  Trim(Str(scrW)) + "x" + Trim(Str(scrH)), Trim(Str(celB)) + "x" + Trim(Str(celH)))
    Else
        melding = Tn("Schaal %1x past niet op dit scherm.", Trim(Str(gevraagd)), "", "")
    End If
End Sub

Sub LaadInstellingen()
    Dim fnum As Integer
    Dim s As String, sleutel As String, waarde As String
    Dim p As Integer

    TaalInstelling = "auto"
    optPrintRaw    = 0
    printPrinter   = ""

    fnum = FreeFile
    If Open(dataMap + SEP + "Rekenblad.cfg" For Input As #fnum) <> 0 Then
        HuidigeTaal = DetecteerTaal()
        Exit Sub
    End If
    Do While Not EOF(fnum)
        Line Input #fnum, s
        If Right(s, 1) = Chr(13) Then s = Left(s, Len(s) - 1)
        p = InStr(s, "=")
        If p > 0 Then
            sleutel = LCase(Trim(Left(s, p - 1)))
            waarde  = Trim(Mid(s, p + 1))
            Select Case sleutel
            Case "schaal"
                fontSchaal = Val(waarde)
                If fontSchaal < 1 Then fontSchaal = 1
                If fontSchaal > MAX_SCH Then fontSchaal = MAX_SCH
            Case "taal"
                TaalInstelling = waarde
            Case "printraw"
                optPrintRaw = Val(waarde)
            Case "printer"
                printPrinter = waarde
            End Select
        End If
    Loop
    Close #fnum

    If LCase(Trim(TaalInstelling)) = "auto" Or Len(Trim(TaalInstelling)) = 0 Then
        HuidigeTaal = DetecteerTaal()
    Else
        HuidigeTaal = LCase(Trim(TaalInstelling))
    End If
End Sub

Sub BewaarInstellingen()
    Dim fnum As Integer
    fnum = FreeFile
    If Open(dataMap + SEP + "Rekenblad.cfg" For Output As #fnum) <> 0 Then Exit Sub
    Print #fnum, "'' instellingen van " + APP_NAAM + " -- met de hand aanpassen mag"
    Print #fnum, "schaal=" + Trim(Str(fontSchaal))
    Print #fnum, "taal=" + Trim(TaalInstelling)
    Print #fnum, "printraw=" + Trim(Str(optPrintRaw))
    Print #fnum, "printer=" + printPrinter
    Close #fnum
End Sub

Function SchermInit() As Integer
    ZetPalet

    If fontSchaal < 1 Then fontSchaal = 1
    If fontSchaal > MAX_SCH Then fontSchaal = MAX_SCH

    '' Zolang er nog geen modus is gezet geeft ScreenInfo de afmeting van het
    '' bureaublad; daarna die van het venster. Dus nu opvragen en bewaren.
    ScreenInfo bureauB, bureauH

    LeesFont
    If fontOk = 0 Then fontSchaal = 1

    '' Past de gevraagde schaal niet, dan stapsgewijs kleiner tot het wel past.
    If SetScale(fontSchaal) = 0 Then
        Do
            fontSchaal = fontSchaal - 1
            If fontSchaal < 1 Then
                SchermInit = 0
                Exit Function
            End If
        Loop Until SetScale(fontSchaal) <> 0
    End If

    SchermInit = -1
End Function

'' Vult fontBits() met het ingebouwde 8x16 font. Zet zelf een klein tijdelijk
'' venster op van 32 x 8 tekens, drukt alle tekens af en tast ze pixel voor
'' pixel af. Wordt één keer bij het opstarten aangeroepen, vóór het echte
'' venster.
Sub LeesFont()
    Dim code As Integer, x As Integer, y As Integer
    Dim cx As Integer, cy As Integer, b As Integer
    Dim wit As UInteger

    fontOk = 0
    For code = 0 To 255
        For y = 0 To 15
            fontBits(code, y) = 0
        Next
    Next

    wit = RGB(255, 255, 255)

    ScreenRes 32 * 8, 8 * 16, 32
    Width 32, 8                     '' 256\8 = 32 en 128\16 = 8, dus het 8x16 font
    Color wit, RGB(0, 0, 0)
    Cls
    ScreenSync

    For code = 1 To 255
        cx = (code Mod 32) * 8
        cy = (code \ 32) * 16
        Draw String (cx, cy), Chr(code), wit
    Next
    ScreenSync

    For code = 0 To 255
        cx = (code Mod 32) * 8
        cy = (code \ 32) * 16
        For y = 0 To 15
            b = 0
            For x = 0 To 7
                If (Point(cx + x, cy + y) And &hFFFFFF) <> 0 Then
                    b = b Or (1 Shl (7 - x))
                End If
            Next
            fontBits(code, y) = b
        Next
    Next

    '' Controle: de "A" moet pixels hebben. Zo niet, dan is de tabel onbruikbaar
    '' en vallen we terug op schaal 1.
    b = 0
    For y = 0 To 15
        b = b Or fontBits(65, y)
    Next
    If b = 0 Then Exit Sub

    fontOk = -1
End Sub

'' Tekent een tekst zelf, teken voor teken, met het uitgelezen 8x16 font
'' vergroot met fontSchaal. Alleen nodig zodra fontSchaal > 1.
Sub TekenCellen(ByVal r As Integer, ByVal c As Integer, ByRef s As String, ByVal fgc As UInteger, ByVal bgc As UInteger)
    Dim i As Integer, x As Integer, y As Integer
    Dim px As Integer, py As Integer, x0 As Integer
    Dim bits As Integer, code As Integer, sch As Integer

    sch = fontSchaal
    py  = (r - 1) * celH
    x0  = (c - 1) * celB

    Line (x0, py)-(x0 + Len(s) * celB - 1, py + celH - 1), bgc, bf

    For i = 1 To Len(s)
        code = Asc(Mid(s, i, 1))
        If code <> 32 Then
            px = x0 + (i - 1) * celB
            For y = 0 To 15
                bits = fontBits(code, y)
                If bits <> 0 Then
                    For x = 0 To 7
                        If (bits And (1 Shl (7 - x))) <> 0 Then
                            Line (px + x * sch, py + y * sch)- _
                                 (px + x * sch + sch - 1, py + y * sch + sch - 1), fgc, bf
                        End If
                    Next
                End If
            Next
        End If
    Next
End Sub

Function Pad(ByRef s As String, ByVal n As Integer) As String
    If n <= 0 Then
        Pad = ""
    ElseIf Len(s) >= n Then
        Pad = Left(s, n)
    Else
        Pad = s + Space(n - Len(s))
    End If
End Function

'' Rechts uitlijnen in een vak van n tekens.
Function PadL(ByRef s As String, ByVal n As Integer) As String
    If n <= 0 Then
        PadL = ""
    ElseIf Len(s) >= n Then
        PadL = Left(s, n)
    Else
        PadL = Space(n - Len(s)) + s
    End If
End Function

Function Kort(ByRef s As String, ByVal n As Integer) As String
    If n <= 0 Then
        Kort = ""
    ElseIf Len(s) <= n Then
        Kort = s
    ElseIf n < 2 Then
        Kort = Left(s, n)
    Else
        Kort = Left(s, n - 1) + gPijl
    End If
End Function

'' Schrijf tekst op het scherm, veilig geclipt. De laatste cel van het
'' scherm blijft altijd leeg, anders scrollt het beeld weg.
Sub PutStr(ByVal r As Integer, ByVal c As Integer, ByRef s As String, ByVal fg As Integer, ByVal bg As Integer)
    Dim t As String
    Dim ruimte As Integer

    If r < 1 Then Exit Sub
    If r > scrH Then Exit Sub
    If c < 1 Then Exit Sub
    If c > scrW Then Exit Sub

    ruimte = scrW - c + 1
    If r = scrH Then ruimte = ruimte - 1
    If ruimte <= 0 Then Exit Sub

    t = s
    If Len(t) > ruimte Then t = Left(t, ruimte)
    If Len(t) = 0 Then Exit Sub

    If fontSchaal > 1 Then
        TekenCellen r, c, t, pal(fg And 15), pal(bg And 15)
        Exit Sub
    End If
    Color pal(fg And 15), pal(bg And 15)
    Locate r, c
    Print t;
End Sub

Function LeesTeken(ByVal msWacht As Integer) As String
    Dim k As String
    Dim n As Integer

    LeesTeken = ""
    n = 0
    Do
        k = Inkey
        If Len(k) > 0 Then
            LeesTeken = k
            Exit Function
        End If
        If n >= msWacht Then Exit Function
        Sleep 5, 1
        n = n + 5
    Loop
End Function

'' Wacht op een toets. ext = -1 bij een uitgebreide toets (pijlen, F-toetsen);
'' de teruggegeven waarde is dan de DOS-scancode, anders de ASCII-code.
Function WachtToets(ByRef ext As Integer) As Integer
    Dim k As String
    Dim a As Integer

    ext = 0

    Do
        k = LeesTeken(1000)
        If Len(k) > 0 Then Exit Do
    Loop

    '' Uitgebreide toetsen komen binnen als Chr(255) of Chr(0) plus scancode.
    If Len(k) = 2 Then
        a = Asc(Left(k, 1))
        If a = 255 Or a = 0 Then
            ext = -1
            WachtToets = Asc(Right(k, 1))
            Exit Function
        End If
    End If

    WachtToets = Asc(k)
End Function

'' ==========================================================================
''  Vensters en dialogen
'' ==========================================================================

Sub Venster(ByVal r As Integer, ByVal c As Integer, ByVal h As Integer, ByVal w As Integer, ByRef titel As String)
    Dim i As Integer
    Dim s As String

    s = dbTL + String(w - 2, dbH) + dbTR
    PutStr r, c, s, C_DLG_FG, C_DLG_BG

    If Len(titel) > 0 Then
        s = " " + Kort(titel, w - 6) + " "
        PutStr r, c + 2, s, C_DLG_FG, C_DLG_BG
    End If

    For i = 1 To h - 2
        s = dbV + Space(w - 2) + dbV
        PutStr r + i, c, s, C_DLG_FG, C_DLG_BG
    Next

    s = dbBL + String(w - 2, dbH) + dbBR
    PutStr r + h - 1, c, s, C_DLG_FG, C_DLG_BG
End Sub

Sub Melden(ByRef tekst As String)
    Dim w As Integer, r As Integer, c As Integer
    Dim ext As Integer
    Dim s As String

    w = Len(tekst) + 8
    If w < 30 Then w = 30
    If w > scrW - 4 Then w = scrW - 4
    r = (scrH - 6) \ 2
    c = (scrW - w) \ 2 + 1

    Venster r, c, 6, w, APP_NAAM
    s = Kort(tekst, w - 4)
    PutStr r + 2, c + 2, s, C_DLG_FG, C_DLG_BG
    s = "[ Enter ]"
    PutStr r + 4, c + (w - Len(s)) \ 2, s, C_DLG_FG, C_DLG_BG

    Do
        ext = 0
        Select Case WachtToets(ext)
        Case 13, 27, 32
            If ext = 0 Then Exit Do
        End Select
    Loop
    Redraw
End Sub

Function Bevestig(ByRef vraag As String) As Integer
    Dim w As Integer, r As Integer, c As Integer
    Dim ext As Integer, t As Integer
    Dim s As String

    w = Len(vraag) + 8
    If w < 34 Then w = 34
    If w > scrW - 4 Then w = scrW - 4
    r = (scrH - 7) \ 2
    c = (scrW - w) \ 2 + 1

    Venster r, c, 7, w, Vt("Bevestigen")
    s = Kort(vraag, w - 4)
    PutStr r + 2, c + 2, s, C_DLG_FG, C_DLG_BG
    s = Vt("J = ja      N = nee (Esc)")
    PutStr r + 4, c + (w - Len(s)) \ 2, s, C_DLG_FG, C_DLG_BG

    Bevestig = 0
    Do
        ext = 0
        t = WachtToets(ext)
        If ext = 0 Then
            Select Case t
            Case Asc("j"), Asc("J"), Asc("y"), Asc("Y")
                Bevestig = -1 : Exit Do
            Case Asc("n"), Asc("N"), 27
                Bevestig = 0 : Exit Do
            End Select
        End If
    Loop
    Redraw
End Function

'' Eenregelige editor op een vaste schermpositie, met horizontaal schuiven.
Function RegelEdit(ByVal r As Integer, ByVal c As Integer, ByVal w As Integer, ByRef start As String, ByRef ok As Integer) As String
    Dim txt As String
    Dim vis As String
    Dim cch As String
    Dim cpos As Integer, off As Integer
    Dim t   As Integer, ext As Integer

    txt = start
    cpos = Len(txt) + 1
    off = 0
    ok  = 0
    If w < 4 Then w = 4

    Do
        If cpos - off > w Then off = cpos - w
        If cpos - off < 1 Then off = cpos - 1
        If off < 0 Then off = 0

        vis = Pad(Mid(txt, off + 1, w), w)
        PutStr r, c, vis, 0, 7
        '' Eigen blokcursor. In grafische modus tekent FB geen tekstcursor, dus
        '' keren we de kleuren van het teken onder de cursor om.
        cch = Mid(vis, cpos - off, 1)
        If Len(cch) = 0 Then cch = " "
        PutStr r, c + (cpos - off - 1), cch, 7, 0

        ext = 0
        t = WachtToets(ext)

        If ext Then
            Select Case t
            Case 75                             '' pijl links
                If cpos > 1 Then cpos = cpos - 1
            Case 77                             '' pijl rechts
                If cpos <= Len(txt) Then cpos = cpos + 1
            Case 71                             '' Home
                cpos = 1
            Case 79                             '' End
                cpos = Len(txt) + 1
            Case 83                             '' Delete
                If cpos <= Len(txt) Then txt = Left(txt, cpos - 1) + Mid(txt, cpos + 1)
            End Select
        Else
            Select Case t
            Case 13                             '' Enter
                ok = -1 : Exit Do
            Case 27                             '' Esc
                ok = 0 : Exit Do
            Case 8                              '' Backspace
                If cpos > 1 Then
                    txt = Left(txt, cpos - 2) + Mid(txt, cpos)
                    cpos = cpos - 1
                End If
            Case 21                             '' Ctrl+U: regel leegmaken
                txt = "" : cpos = 1 : off = 0
            Case Else
                If t >= 32 Then
                    If Len(txt) < MAX_TXT Then
                        txt = Left(txt, cpos - 1) + Chr(t) + Mid(txt, cpos)
                        cpos = cpos + 1
                    End If
                End If
            End Select
        End If
    Loop

    Locate , , 0
    RegelEdit = txt
End Function

Function VraagTekst(ByRef titel As String, ByRef prompt As String, ByRef start As String, ByRef ok As Integer) As String
    Dim w As Integer, r As Integer, c As Integer
    Dim res As String

    w = 60
    If w > scrW - 4 Then w = scrW - 4
    r = (scrH - 7) \ 2
    c = (scrW - w) \ 2 + 1

    Venster r, c, 7, w, titel
    PutStr r + 2, c + 2, Kort(prompt, w - 4), C_DLG_FG, C_DLG_BG
    PutStr r + 5, c + 2, Kort(Vt("Enter = ok   Esc = annuleren   Ctrl+U = leegmaken"), w - 4), C_DLG_FG, C_DLG_BG

    res = RegelEdit(r + 3, c + 2, w - 4, start, ok)
    Redraw
    VraagTekst = res
End Function

'' Keuzelijst. Geeft het gekozen nummer terug, of 0 bij Esc.
Function Kies(ByRef titel As String, items() As String, ByVal n As Integer, ByVal start As Integer) As Integer
    Dim r As Integer, c As Integer, w As Integer, h As Integer
    Dim rijen As Integer, top As Integer, sel As Integer
    Dim i As Integer, t As Integer, ext As Integer
    Dim fg As Integer, bg As Integer
    Dim s As String

    Kies = 0
    If n < 1 Then Exit Function

    w = Len(titel) + 8
    For i = 1 To n
        If Len(items(i)) + 6 > w Then w = Len(items(i)) + 6
    Next
    If w < 30 Then w = 30
    If w > scrW - 4 Then w = scrW - 4

    rijen = n
    If rijen > scrH - 8 Then rijen = scrH - 8
    If rijen < 3 Then rijen = 3
    h = rijen + 4
    r = (scrH - h) \ 2 + 1
    c = (scrW - w) \ 2 + 1

    sel = start
    If sel < 1 Or sel > n Then sel = 1
    top = 1

    Do
        If sel < top Then top = sel
        If sel > top + rijen - 1 Then top = sel - rijen + 1
        If top > n - rijen + 1 Then top = n - rijen + 1
        If top < 1 Then top = 1

        Venster r, c, h, w, titel
        For i = 0 To rijen - 1
            If top + i <= n Then
                If top + i = sel Then
                    fg = C_SEL_FG : bg = C_SEL_BG
                Else
                    fg = C_DLG_FG : bg = C_DLG_BG
                End If
                PutStr r + 1 + i, c + 2, Pad(Kort(items(top + i), w - 4), w - 4), fg, bg
            End If
        Next
        s = Vt("Enter = kiezen   Esc = terug")
        If n > rijen Then s = s + "   " + Trim(Str(sel)) + "/" + Trim(Str(n))
        PutStr r + h - 2, c + 2, Kort(s, w - 4), C_DLG_FG, C_DLG_BG

        ext = 0
        t = WachtToets(ext)
        If ext Then
            Select Case t
            Case 72 : sel = sel - 1
            Case 80 : sel = sel + 1
            Case 73 : sel = sel - rijen
            Case 81 : sel = sel + rijen
            Case 71 : sel = 1
            Case 79 : sel = n
            End Select
            If sel < 1 Then sel = 1
            If sel > n Then sel = n
        Else
            Select Case t
            Case 13
                Kies = sel : Exit Do
            Case 27
                Kies = 0 : Exit Do
            End Select
        End If
    Loop

    Redraw
End Function

Sub ToonHelp()
    Const HELP_N = 48
    Dim r As Integer, c As Integer, w As Integer, h As Integer
    Dim i As Integer, ext As Integer, t As Integer
    Dim hTop As Integer, rijen As Integer
    Dim h1(1 To HELP_N) As String
    Dim s As String

    h1(1)  = Vt("BEWEGEN")
    h1(2)  = Vt("  Pijltoetsen ...... cel voor cel          Tab .. cel naar rechts")
    h1(3)  = Vt("  PgUp / PgDn ...... scherm omhoog/omlaag")
    h1(4)  = Vt("  Home / End ....... eerste / laatste gevulde kolom van deze rij")
    h1(5)  = Vt("  F5 / Ctrl+G ...... ga naar cel, bv. B12 of Kosten!A1")
    h1(6)  = Vt("  F6 / F7 .......... volgend / vorig tabblad")
    h1(7)  = ""
    h1(8)  = Vt("INVOEREN")
    h1(9)  = Vt("  Gewoon typen ..... begint meteen met invoeren in de cursorcel")
    h1(10) = Vt("  Enter / F2 ....... de huidige cel bewerken")
    h1(11) = Vt("  Del / Backspace .. cel wissen")
    h1(12) = Vt("  Een getal wordt een getal, = + of @ vooraf maakt een formule,")
    h1(13) = Vt("  al het andere is tekst. Een apostrof dwingt tekst af: '007")
    h1(14) = ""
    h1(15) = Vt("FORMULES")
    h1(16) = Vt("  Rekenen .......... + - * / ^ en haakjes, bv. =(A1+A2)*1.21")
    h1(17) = Vt("  Vergelijken ...... = <> < > <= >= geven 1 (waar) of 0 (onwaar)")
    h1(18) = Vt("  Verwijzen ........ A1   $A$1 blijft staan bij kopieren")
    h1(19) = Vt("                     Kosten!B3 wijst naar een ander tabblad")
    h1(20) = Vt("  Bereik ........... A1:B10  (ook A1..B10 mag)")
    h1(21) = Vt("  Over bereiken .... SOM GEM MIN MAX AANTAL")
    h1(22) = Vt("  Over getallen .... ABS INT WORTEL AFROND(x;n) REST(x;y) MACHT(x;y)")
    h1(23) = Vt("                     EXP LN LOG SIN COS TAN PI()")
    h1(24) = Vt("  Kiezen ........... ALS(voorwaarde;dan;anders)")
    h1(25) = Vt("  Argumenten scheiden met ; of , ; de decimale punt is een punt.")
    h1(26) = Vt("  Fouten: #DEEL/0 #NAAM? #SYNTAX #KRING! #VERW! #GETAL! #ARG! #DIEP!")
    h1(27) = ""
    h1(28) = Vt("KOLOMMEN EN OPMAAK")
    h1(29) = Vt("  F3 ............... breedte van deze kolom (3..40)")
    h1(30) = Vt("  F4 ............... decimalen en uitlijning van deze kolom")
    h1(31) = ""
    h1(32) = Vt("BLOKKEN")
    h1(33) = Vt("  Ctrl+K ........... kopieren; vraagt welk bereik")
    h1(34) = Vt("  Ctrl+V ........... plakken; vraagt waar. Verwijzingen schuiven")
    h1(35) = Vt("                     mee, tenzij er een $ voor staat. Een enkele")
    h1(36) = Vt("                     gekopieerde cel vult een heel doelbereik.")
    h1(37) = Vt("  Ctrl+W ........... een bereik leegmaken")
    h1(38) = ""
    h1(39) = Vt("MENU EN BESTAND")
    h1(40) = Vt("  F10 of Esc ....... menu: bestand, bewerken, opmaak, tabbladen, extra")
    h1(41) = Vt("  Pijltjes links/rechts wisselen van categorie, omhoog/omlaag van item")
    h1(42) = Vt("  Ctrl+S ........... opslaan          F8 ..... alles herberekenen")
    h1(43) = Vt("  Ctrl+N ........... nieuw tabblad    F9 ..... zoeken in alle bladen")
    h1(44) = Vt("  Ctrl+P ........... afdrukken        Ctrl+T .. instellingen (printer/taal)")
    h1(45) = Vt("  Ctrl+Z ........... over Rekenblad")
    h1(46) = Vt("  F11 / F12 ........ tekens kleiner / groter (ook via Extra in het menu)")
    h1(47) = Vt("  Ctrl+Q ........... afsluiten (vraagt eerst of er opgeslagen moet)")
    h1(48) = Vt("                     Stoppen in het Bestand-menu doet hetzelfde")

    w = 72
    If w > scrW - 2 Then w = scrW - 2
    h = HELP_N + 4
    If h > scrH - 2 Then h = scrH - 2
    rijen = h - 4
    If rijen < 3 Then rijen = 3
    r = (scrH - h) \ 2 + 1
    c = (scrW - w) \ 2 + 1
    hTop = 1

    Do
        If hTop > HELP_N - rijen + 1 Then hTop = HELP_N - rijen + 1
        If hTop < 1 Then hTop = 1

        Venster r, c, h, w, Vt("Hulp")
        For i = 0 To rijen - 1
            If hTop + i <= HELP_N Then
                PutStr r + 1 + i, c + 2, Kort(h1(hTop + i), w - 4), C_DLG_FG, C_DLG_BG
            End If
        Next

        If rijen >= HELP_N Then
            s = Vt("Druk op een toets...")
        Else
            s = Tn("Pijl op/neer schuift %1 regel %2-%3 van %4 %5 Esc sluit", gPunt, _
                Trim(Str(hTop)) + "-" + Trim(Str(hTop + rijen - 1)), Trim(Str(HELP_N)))
        End If
        PutStr r + h - 2, c + 2, Kort(s, w - 4), C_DLG_FG, C_DLG_BG

        If rijen >= HELP_N Then
            ext = 0
            WachtToets ext
            Exit Do
        End If

        ext = 0
        t = WachtToets(ext)
        If ext Then
            Select Case t
            Case 72 : hTop = hTop - 1
            Case 80 : hTop = hTop + 1
            Case 73 : hTop = hTop - rijen
            Case 81 : hTop = hTop + rijen
            Case 71 : hTop = 1
            Case 79 : hTop = HELP_N
            Case Else
                Exit Do
            End Select
        Else
            If t <> 0 Then Exit Do
        End If
    Loop

    Redraw
End Sub

'' ==========================================================================
''  Namen, getallen en opmaak
'' ==========================================================================

'' 0 -> "A", 25 -> "Z", 26 -> "AA", 255 -> "IV"
Function KolNaam(ByVal k As Integer) As String
    If k < 0 Then
        KolNaam = "?"
    ElseIf k < 26 Then
        KolNaam = Chr(65 + k)
    Else
        KolNaam = Chr(65 + k \ 26 - 1) + Chr(65 + k Mod 26)
    End If
End Function

'' "A" -> 0, "IV" -> 255. Geeft -1 als het geen geldige kolomnaam is.
Function KolNummer(ByRef s As String) As Integer
    Dim t As String
    Dim k As Integer

    t = UCase(Trim(s))
    If Len(t) = 1 Then
        k = Asc(t) - 65
    ElseIf Len(t) = 2 Then
        k = (Asc(Left(t, 1)) - 65 + 1) * 26 + (Asc(Right(t, 1)) - 65)
    Else
        KolNummer = -1
        Exit Function
    End If
    If k < 0 Or k >= MAX_KOL Then k = -1
    KolNummer = k
End Function

Function CelNaam(ByVal k As Integer, ByVal r As Integer) As String
    CelNaam = KolNaam(k) + Trim(Str(r + 1))
End Function

Function BladNummer(ByRef naam As String) As Integer
    Dim i As Integer
    BladNummer = 0
    For i = 1 To nBladen
        If LCase(blad(i).naam) = LCase(Trim(naam)) Then
            BladNummer = i
            Exit Function
        End If
    Next
End Function

'' Alleen letters, cijfers en liggende streepjes: dan kan een bladnaam zonder
'' gedoe in een formule worden gebruikt (Kosten!A1).
Function SchoneNaam(ByRef s As String) As String
    Dim i As Integer, a As Integer
    Dim ch As String, res As String

    res = ""
    For i = 1 To Len(s)
        ch = Mid(s, i, 1)
        a = Asc(ch)
        If (a >= 48 And a <= 57) Or (a >= 65 And a <= 90) Or (a >= 97 And a <= 122) Then
            res = res + ch
        ElseIf a = 32 Or a = 45 Or a = 95 Then
            res = res + "_"
        End If
    Next
    Do While Left(res, 1) = "_"
        res = Mid(res, 2)
    Loop
    Do While Right(res, 1) = "_"
        res = Left(res, Len(res) - 1)
    Loop
    '' een naam mag niet met een cijfer beginnen, anders lijkt hij op een getal
    If Len(res) > 0 Then
        a = Asc(Left(res, 1))
        If a >= 48 And a <= 57 Then res = "B" + res
    End If
    If Len(res) > 16 Then res = Left(res, 16)
    SchoneNaam = res
End Function

'' Is de hele tekst een getal? Toegestaan: [+-]cijfers[.cijfers][e[+-]cijfers]
Function IsGetal(ByRef s As String) As Integer
    Dim t As String, ch As String
    Dim i As Integer, a As Integer
    Dim cijfers As Integer, punt As Integer, exp1 As Integer

    IsGetal = 0
    t = Trim(s)
    If Len(t) = 0 Then Exit Function

    i = 1
    ch = Mid(t, i, 1)
    If ch = "+" Or ch = "-" Then i = i + 1

    cijfers = 0 : punt = 0 : exp1 = 0
    Do While i <= Len(t)
        ch = Mid(t, i, 1)
        a = Asc(ch)
        If a >= 48 And a <= 57 Then
            cijfers = cijfers + 1
        ElseIf ch = "." Then
            If punt Or exp1 Then Exit Function
            punt = -1
        ElseIf ch = "e" Or ch = "E" Then
            If exp1 Or cijfers = 0 Then Exit Function
            exp1 = -1
            cijfers = 0
            If i < Len(t) Then
                ch = Mid(t, i + 1, 1)
                If ch = "+" Or ch = "-" Then i = i + 1
            End If
        Else
            Exit Function
        End If
        i = i + 1
    Loop

    If cijfers = 0 Then Exit Function
    IsGetal = -1
End Function

'' Een getal met een vast aantal decimalen, netjes afgerond.
Function VastGetal(ByVal w As Double, ByVal n As Integer) As String
    Dim s As String
    Dim t As Double, sch As Double
    Dim i As Integer, neg As Integer

    If n < 0 Then n = 0
    If n > 9 Then n = 9

    neg = 0
    If w < 0 Then
        neg = -1
        w = -w
    End If

    sch = 1
    For i = 1 To n
        sch = sch * 10
    Next

    t = w * sch
    If t >= 1e15 Then
        '' te groot om nog exact af te ronden; laat Str het maar doen
        s = Trim(Str(w))
        If neg Then s = "-" + s
        VastGetal = s
        Exit Function
    End If

    '' Een tiende van een cent hoort naar boven, maar 1.005 ligt in dubbele
    '' precisie net onder de helft (1.00499999...). Een piepklein duwtje,
    '' evenredig met het getal zelf, haalt die kromme gevallen recht zonder
    '' eerlijke afrondingen te verstoren.
    If t < 1e12 Then t = t + t * 1e-12
    t = Int(t + 0.5)
    s = Trim(Str(t))
    Do While Len(s) <= n
        s = "0" + s
    Loop
    If n > 0 Then s = Left(s, Len(s) - n) + "." + Right(s, n)
    If neg Then
        If Val(s) <> 0 Then s = "-" + s
    End If
    VastGetal = s
End Function

'' Algemene notatie: zo veel cijfers als er passen, zonder onnodige nullen.
Function AlgGetal(ByVal w As Double, ByVal breedte As Integer) As String
    Dim s As String
    Dim n As Integer

    s = Trim(Str(w))
    If Len(s) <= breedte Then
        AlgGetal = s
        Exit Function
    End If

    For n = 6 To 0 Step -1
        s = VastGetal(w, n)
        If Len(s) <= breedte Then
            AlgGetal = s
            Exit Function
        End If
    Next

    '' past echt niet: laat zien dat de kolom te smal is
    AlgGetal = String(breedte, "#")
End Function

Function FoutTekst(ByVal code As Integer) As String
    Select Case code
    Case F_DEEL  : FoutTekst = "#DEEL/0"
    Case F_NAAM  : FoutTekst = "#NAAM?"
    Case F_SYNT  : FoutTekst = "#SYNTAX"
    Case F_KRING : FoutTekst = "#KRING!"
    Case F_VERW  : FoutTekst = "#VERW!"
    Case F_GETAL : FoutTekst = "#GETAL!"
    Case F_ARG   : FoutTekst = "#ARG!"
    Case F_DIEP  : FoutTekst = "#DIEP!"
    Case Else    : FoutTekst = "#FOUT"
    End Select
End Function

'' ==========================================================================
''  Celopslag
''
''  Per tabblad staat de inhoud in cel(1..aantal); idx(kolom,rij) wijst naar
''  het nummer daarin, of is 0 voor een lege cel. Bij het wissen schuift de
''  laatste cel in het gat, zodat er geen gaten ontstaan -- daarom weet elke
''  cel zelf op welke kolom en rij hij staat.
'' ==========================================================================

Function CelNr(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As Integer
    If b < 1 Or b > nBladen Then
        CelNr = 0
    ElseIf k < 0 Or k >= MAX_KOL Or r < 0 Or r >= MAX_RIJ Then
        CelNr = 0
    Else
        CelNr = blad(b).idx(k, r)
    End If
End Function

'' Kopieert de inhoud van een cel veld voor veld: een UDT met een string mag
'' je niet zomaar als blok verplaatsen.
Sub KopieerCelData(ByVal bd As Integer, ByVal id As Integer, ByVal bs As Integer, ByVal is1 As Integer)
    blad(bd).cel(id).tekst  = blad(bs).cel(is1).tekst
    blad(bd).cel(id).waarde = blad(bs).cel(is1).waarde
    blad(bd).cel(id).k      = blad(bs).cel(is1).k
    blad(bd).cel(id).r      = blad(bs).cel(is1).r
    blad(bd).cel(id).soort  = blad(bs).cel(is1).soort
    blad(bd).cel(id).fout   = blad(bs).cel(is1).fout
    blad(bd).cel(id).merk   = blad(bs).cel(is1).merk
    blad(bd).cel(id).bezig  = blad(bs).cel(is1).bezig
End Sub

Function MaakCel(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As Integer
    Dim i As Integer

    MaakCel = 0
    If k < 0 Or k >= MAX_KOL Or r < 0 Or r >= MAX_RIJ Then Exit Function

    i = blad(b).idx(k, r)
    If i > 0 Then
        MaakCel = i
        Exit Function
    End If

    If blad(b).aantal >= MAX_CEL Then Exit Function

    blad(b).aantal = blad(b).aantal + 1
    i = blad(b).aantal
    blad(b).idx(k, r) = i
    blad(b).cel(i).tekst  = ""
    blad(b).cel(i).waarde = 0
    blad(b).cel(i).k      = k
    blad(b).cel(i).r      = r
    blad(b).cel(i).soort  = S_LEEG
    blad(b).cel(i).fout   = 0
    blad(b).cel(i).merk   = 0
    blad(b).cel(i).bezig  = 0
    MaakCel = i
End Function

Sub WisCel(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer)
    Dim i As Integer, n As Integer

    i = CelNr(b, k, r)
    If i = 0 Then Exit Sub

    n = blad(b).aantal
    If i <> n Then
        KopieerCelData b, i, b, n
        blad(b).idx(blad(b).cel(i).k, blad(b).cel(i).r) = i
    End If
    blad(b).cel(n).tekst = ""
    blad(b).cel(n).soort = S_LEEG
    blad(b).aantal = n - 1
    blad(b).idx(k, r) = 0
End Sub

'' Zet de ruwe invoer in een cel en bepaalt meteen de soort.
Sub ZetCelTekst(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer, ByRef s As String)
    Dim t As String, eerste As String
    Dim i As Integer

    t = RTrim(s)
    Do While Left(t, 1) = " "
        t = Mid(t, 2)
    Loop

    If Len(t) = 0 Then
        WisCel b, k, r
        Exit Sub
    End If

    i = MaakCel(b, k, r)
    If i = 0 Then
        melding = Tn("Dit tabblad zit vol (%1 cellen).", Trim(Str(MAX_CEL)), "", "")
        Exit Sub
    End If

    blad(b).cel(i).tekst  = t
    blad(b).cel(i).fout   = 0
    blad(b).cel(i).merk   = 0
    blad(b).cel(i).bezig  = 0

    eerste = Left(t, 1)
    If eerste = "'" Then
        blad(b).cel(i).soort  = S_TEKST
        blad(b).cel(i).waarde = 0
    ElseIf IsGetal(t) Then
        blad(b).cel(i).soort  = S_GETAL
        blad(b).cel(i).waarde = Val(t)
    ElseIf eerste = "=" Or eerste = "+" Or eerste = "@" Then
        blad(b).cel(i).soort  = S_FORM
        blad(b).cel(i).waarde = 0
    Else
        blad(b).cel(i).soort  = S_TEKST
        blad(b).cel(i).waarde = 0
    End If
End Sub

Function CelTekst(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As String
    Dim i As Integer
    i = CelNr(b, k, r)
    If i = 0 Then CelTekst = "" Else CelTekst = blad(b).cel(i).tekst
End Function

'' Bouwt de verwijstabel opnieuw op uit cel(). Nodig nadat cellen zijn
'' verschoven door het invoegen of verwijderen van rijen of kolommen.
Sub HerbouwIndex(ByVal b As Integer)
    Dim k As Integer, r As Integer, i As Integer

    For r = 0 To MAX_RIJ - 1
        For k = 0 To MAX_KOL - 1
            blad(b).idx(k, r) = 0
        Next
    Next
    For i = 1 To blad(b).aantal
        blad(b).idx(blad(b).cel(i).k, blad(b).cel(i).r) = i
    Next
End Sub

Sub LeegBlad(ByVal b As Integer, ByRef naam As String)
    Dim k As Integer, i As Integer

    For i = 1 To blad(b).aantal
        blad(b).cel(i).tekst = ""
    Next
    blad(b).aantal = 0
    blad(b).naam   = naam
    blad(b).curK   = 0
    blad(b).curR   = 0
    blad(b).topK   = 0
    blad(b).topR   = 0
    For k = 0 To MAX_KOL - 1
        blad(b).breed(k) = STD_BREED
        blad(b).dec(k)   = -1
        blad(b).uit(k)   = U_AUTO
    Next
    HerbouwIndex b
End Sub

'' ==========================================================================
''  Celverwijzingen in tekstvorm
''
''  Eén functie leest een verwijzing, en die wordt op twee plaatsen gebruikt:
''  door de rekenmachine (die hem op fPos verwacht) en door het herschrijven
''  van formules bij kopieren, invoegen en verwijderen.
''
''  Vorm:  [bladnaam!] [$] kolomletters [$] rijnummer      bv. Kosten!$B$12
'' ==========================================================================

Function LeesRefOp(ByRef s As String, ByVal p As Integer, ByRef eind As Integer, ByRef bn As String, ByRef absK As Integer, ByRef k As Integer, ByRef absR As Integer, ByRef r As Integer) As Integer
    Dim i As Integer, j As Integer, a As Integer
    Dim ch As String, id As String, lett As String, cijf As String

    LeesRefOp = 0
    bn = "" : absK = 0 : absR = 0 : k = 0 : r = 0
    i = p
    If i < 1 Or i > Len(s) Then Exit Function

    '' eventueel een bladnaam, herkenbaar aan het uitroepteken erachter
    j = i
    id = ""
    Do While j <= Len(s)
        ch = Mid(s, j, 1)
        a = Asc(ch)
        If (a >= 48 And a <= 57) Or (a >= 65 And a <= 90) Or (a >= 97 And a <= 122) Or a = 95 Then
            id = id + ch
            j = j + 1
        Else
            Exit Do
        End If
    Loop
    If Len(id) > 0 Then
        If Mid(s, j, 1) = "!" Then
            bn = id
            i = j + 1
        End If
    End If

    If Mid(s, i, 1) = "$" Then
        absK = -1
        i = i + 1
    End If

    lett = ""
    Do While Len(lett) < 2
        ch = UCase(Mid(s, i, 1))
        If Len(ch) = 0 Then Exit Do
        a = Asc(ch)
        If a >= 65 And a <= 90 Then
            lett = lett + ch
            i = i + 1
        Else
            Exit Do
        End If
    Loop
    If Len(lett) = 0 Then Exit Function

    If Mid(s, i, 1) = "$" Then
        absR = -1
        i = i + 1
    End If

    cijf = ""
    Do While Len(cijf) < 5
        ch = Mid(s, i, 1)
        If Len(ch) = 0 Then Exit Do
        a = Asc(ch)
        If a >= 48 And a <= 57 Then
            cijf = cijf + ch
            i = i + 1
        Else
            Exit Do
        End If
    Loop
    If Len(cijf) = 0 Then Exit Function

    '' er mag geen letter, cijfer of streepje meer op volgen: AB12C is geen cel
    ch = UCase(Mid(s, i, 1))
    If Len(ch) > 0 Then
        a = Asc(ch)
        If (a >= 48 And a <= 57) Or (a >= 65 And a <= 90) Or a = 95 Then Exit Function
    End If

    k = KolNummer(lett)
    If k < 0 Then Exit Function
    r = Val(cijf) - 1
    If r < 0 Or r >= MAX_RIJ Then Exit Function

    eind = i
    LeesRefOp = -1
End Function

Function RefTekst(ByRef bn As String, ByVal absK As Integer, ByVal k As Integer, ByVal absR As Integer, ByVal r As Integer) As String
    Dim s As String

    s = ""
    If Len(bn) > 0 Then s = bn + "!"
    If absK Then s = s + "$"
    s = s + KolNaam(k)
    If absR Then s = s + "$"
    s = s + Trim(Str(r + 1))
    RefTekst = s
End Function

'' Verschuift alle betrekkelijke verwijzingen in een formule. Wordt gebruikt
'' bij het plakken: =A1+$B$2 wordt een rij lager =A2+$B$2.
Function VerschuifFormule(ByRef s As String, ByVal dk As Integer, ByVal dr As Integer) As String
    Dim res As String, bn As String, ch As String
    Dim i As Integer, e As Integer, a As Integer, vorig As Integer
    Dim absK As Integer, absR As Integer, k As Integer, r As Integer
    Dim gedaan As Integer

    res = ""
    i = 1
    vorig = 0                       '' -1 = vorig teken hoorde bij een naam
    Do While i <= Len(s)
        gedaan = 0
        ch = Mid(s, i, 1)
        a = Asc(UCase(ch))
        If vorig = 0 And ((a >= 65 And a <= 90) Or ch = "$") Then
            If LeesRefOp(s, i, e, bn, absK, k, absR, r) Then
                If absK = 0 Then k = k + dk
                If absR = 0 Then r = r + dr
                If k < 0 Or k >= MAX_KOL Or r < 0 Or r >= MAX_RIJ Then
                    res = res + "#VERW!"
                Else
                    res = res + RefTekst(bn, absK, k, absR, r)
                End If
                i = e
                vorig = 0
                gedaan = -1
            End If
        End If
        If gedaan = 0 Then
            res = res + ch
            If (a >= 48 And a <= 57) Or (a >= 65 And a <= 90) Or a = 95 Or ch = "$" Or ch = "!" Then
                vorig = -1
            Else
                vorig = 0
            End If
            i = i + 1
        End If
    Loop

    VerschuifFormule = res
End Function

'' Past alle formules aan nadat er in blad doelB een rij of kolom is
'' ingevoegd (delta = 1) of verwijderd (delta = -1).
Sub PasRefsAan(ByVal doelB As Integer, ByVal isKolom As Integer, ByVal vanaf As Integer, ByVal delta As Integer)
    Dim b As Integer, ci As Integer
    Dim s As String, res As String, bn As String, ch As String
    Dim i As Integer, e As Integer, a As Integer, vorig As Integer
    Dim absK As Integer, absR As Integer, k As Integer, r As Integer
    Dim plek As Integer, hoortBij As Integer, weg As Integer, gedaan As Integer

    For b = 1 To nBladen
        For ci = 1 To blad(b).aantal
            If blad(b).cel(ci).soort = S_FORM Then
                s = blad(b).cel(ci).tekst
                res = ""
                i = 1
                vorig = 0
                Do While i <= Len(s)
                    gedaan = 0
                    ch = Mid(s, i, 1)
                    a = Asc(UCase(ch))
                    If vorig = 0 And ((a >= 65 And a <= 90) Or ch = "$") Then
                        If LeesRefOp(s, i, e, bn, absK, k, absR, r) Then
                            If Len(bn) > 0 Then
                                hoortBij = 0
                                If BladNummer(bn) = doelB Then hoortBij = -1
                            Else
                                hoortBij = 0
                                If b = doelB Then hoortBij = -1
                            End If

                            weg = 0
                            If hoortBij Then
                                If isKolom Then plek = k Else plek = r
                                If delta > 0 Then
                                    If plek >= vanaf Then plek = plek + delta
                                Else
                                    If plek = vanaf Then
                                        weg = -1
                                    ElseIf plek > vanaf Then
                                        plek = plek + delta
                                    End If
                                End If
                                If isKolom Then k = plek Else r = plek
                            End If

                            If weg Or k < 0 Or k >= MAX_KOL Or r < 0 Or r >= MAX_RIJ Then
                                res = res + "#VERW!"
                            Else
                                res = res + RefTekst(bn, absK, k, absR, r)
                            End If
                            i = e
                            vorig = 0
                            gedaan = -1
                        End If
                    End If
                    If gedaan = 0 Then
                        res = res + ch
                        If (a >= 48 And a <= 57) Or (a >= 65 And a <= 90) Or a = 95 Or ch = "$" Or ch = "!" Then
                            vorig = -1
                        Else
                            vorig = 0
                        End If
                        i = i + 1
                    End If
                Loop
                blad(b).cel(ci).tekst = res
            End If
        Next
    Next
End Sub

'' ==========================================================================
''  Rekenmachine
''
''  Een formule wordt ontleed en meteen uitgerekend, van links naar rechts en
''  met de gebruikelijke voorrang:
''      vergelijking  =  som [ = <> < > <= >= som ]
''      som           =  term { + | - term }
''      term          =  macht { * | / macht }
''      macht         =  primair { ^ unair }
''      unair         =  [ + | - ] macht
''      primair       =  getal | cel | ( vergelijking ) | functie( ... )
''
''  Verwijst een cel naar een andere cel, dan wordt die onderweg uitgerekend.
''  De stand van de ontleder gaat daarbij even op de stapel, en "bezig" vangt
''  kringverwijzingen af.
'' ==========================================================================

Sub SlaSpatiesOver()
    Do While fPos <= Len(fTxt)
        If Mid(fTxt, fPos, 1) <> " " Then Exit Do
        fPos = fPos + 1
    Loop
End Sub

Function Volgende() As String
    SlaSpatiesOver
    If fPos > Len(fTxt) Then
        Volgende = ""
    Else
        Volgende = Mid(fTxt, fPos, 1)
    End If
End Function

Function LeesCelRef(ByRef b As Integer, ByRef k As Integer, ByRef r As Integer) As Integer
    Dim e As Integer, absK As Integer, absR As Integer
    Dim bn As String

    LeesCelRef = 0
    SlaSpatiesOver
    If LeesRefOp(fTxt, fPos, e, bn, absK, k, absR, r) = 0 Then Exit Function

    If Len(bn) > 0 Then
        b = BladNummer(bn)
        If b = 0 Then
            fFout = F_NAAM
            b = fBlad
        End If
    Else
        b = fBlad
    End If
    fPos = e
    LeesCelRef = -1
End Function

Function LeesBereik(ByRef b As Integer, ByRef k1 As Integer, ByRef r1 As Integer, ByRef k2 As Integer, ByRef r2 As Integer) As Integer
    Dim bew As Integer, b2 As Integer, h As Integer

    LeesBereik = 0
    bew = fPos
    If LeesCelRef(b, k1, r1) = 0 Then
        fPos = bew
        Exit Function
    End If

    SlaSpatiesOver
    If Mid(fTxt, fPos, 2) = ".." Then
        fPos = fPos + 2
    ElseIf Mid(fTxt, fPos, 1) = ":" Then
        fPos = fPos + 1
    Else
        fPos = bew                  '' losse cel, geen bereik
        Exit Function
    End If

    If LeesCelRef(b2, k2, r2) = 0 Then
        fFout = F_SYNT
        k2 = k1
        r2 = r1
    End If

    If k1 > k2 Then
        h = k1 : k1 = k2 : k2 = h
    End If
    If r1 > r2 Then
        h = r1 : r1 = r2 : r2 = h
    End If
    LeesBereik = -1
End Function

Function CelWaarde(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer) As Double
    Dim ci As Integer

    CelWaarde = 0
    ci = CelNr(b, k, r)
    If ci = 0 Then Exit Function

    Select Case blad(b).cel(ci).soort
    Case S_GETAL
        CelWaarde = blad(b).cel(ci).waarde
    Case S_FORM
        CelWaarde = BerekenCel(b, ci)
    Case Else
        CelWaarde = 0
    End Select
End Function

Function BerekenCel(ByVal b As Integer, ByVal ci As Integer) As Double
    Dim bewT As String, bewP As Integer, bewB As Integer, bewF As Integer
    Dim s As String
    Dim v As Double

    If blad(b).cel(ci).merk = gen Then
        If blad(b).cel(ci).fout <> 0 Then fFout = blad(b).cel(ci).fout
        BerekenCel = blad(b).cel(ci).waarde
        Exit Function
    End If

    If blad(b).cel(ci).bezig Then
        '' deze cel verwijst, via via, naar zichzelf
        blad(b).cel(ci).waarde = 0
        blad(b).cel(ci).fout   = F_KRING
        blad(b).cel(ci).merk   = gen
        fFout = F_KRING
        BerekenCel = 0
        Exit Function
    End If

    If fDiepte >= MAX_DIEP Then
        '' de ketting van formules die naar elkaar verwijzen wordt te lang
        blad(b).cel(ci).waarde = 0
        blad(b).cel(ci).fout   = F_DIEP
        blad(b).cel(ci).merk   = gen
        fFout = F_DIEP
        BerekenCel = 0
        Exit Function
    End If
    fDiepte = fDiepte + 1

    bewT = fTxt : bewP = fPos : bewB = fBlad : bewF = fFout

    s = blad(b).cel(ci).tekst
    If Left(s, 1) = "=" Then s = Mid(s, 2)

    blad(b).cel(ci).bezig = -1
    fTxt  = s
    fPos  = 1
    fBlad = b
    fFout = 0

    v = Vergelijking()
    SlaSpatiesOver
    If fFout = 0 And fPos <= Len(fTxt) Then fFout = F_SYNT
    If fFout <> 0 Then v = 0

    blad(b).cel(ci).waarde = v
    blad(b).cel(ci).fout   = fFout
    blad(b).cel(ci).merk   = gen
    blad(b).cel(ci).bezig  = 0

    fDiepte = fDiepte - 1
    fTxt = bewT : fPos = bewP : fBlad = bewB
    If blad(b).cel(ci).fout <> 0 Then
        fFout = blad(b).cel(ci).fout
    Else
        fFout = bewF
    End If

    BerekenCel = v
End Function

Function Vergelijking() As Double
    Dim v As Double, w As Double
    Dim op As String, ch As String
    Dim uitkomst As Integer

    v = Som()

    ch = Volgende()
    op = ""
    If ch = "=" Then
        op = "="
        fPos = fPos + 1
    ElseIf ch = "<" Then
        If Mid(fTxt, fPos + 1, 1) = "=" Then
            op = "<=" : fPos = fPos + 2
        ElseIf Mid(fTxt, fPos + 1, 1) = ">" Then
            op = "<>" : fPos = fPos + 2
        Else
            op = "<"  : fPos = fPos + 1
        End If
    ElseIf ch = ">" Then
        If Mid(fTxt, fPos + 1, 1) = "=" Then
            op = ">=" : fPos = fPos + 2
        Else
            op = ">"  : fPos = fPos + 1
        End If
    End If

    If Len(op) = 0 Then
        Vergelijking = v
        Exit Function
    End If

    w = Som()
    uitkomst = 0
    Select Case op
    Case "="  : If v =  w Then uitkomst = -1
    Case "<>" : If v <> w Then uitkomst = -1
    Case "<"  : If v <  w Then uitkomst = -1
    Case ">"  : If v >  w Then uitkomst = -1
    Case "<=" : If v <= w Then uitkomst = -1
    Case ">=" : If v >= w Then uitkomst = -1
    End Select

    If uitkomst Then Vergelijking = 1 Else Vergelijking = 0
End Function

Function Som() As Double
    Dim v As Double
    Dim ch As String

    v = Term()
    Do
        ch = Volgende()
        If ch = "+" Then
            fPos = fPos + 1
            v = v + Term()
        ElseIf ch = "-" Then
            fPos = fPos + 1
            v = v - Term()
        Else
            Exit Do
        End If
        If fFout <> 0 Then Exit Do
    Loop
    Som = v
End Function

Function Term() As Double
    Dim v As Double, w As Double
    Dim ch As String

    v = Macht()
    Do
        ch = Volgende()
        If ch = "*" Then
            fPos = fPos + 1
            v = v * Macht()
        ElseIf ch = "/" Then
            fPos = fPos + 1
            w = Macht()
            If w = 0 Then
                fFout = F_DEEL
                v = 0
            Else
                v = v / w
            End If
        Else
            Exit Do
        End If
        If fFout <> 0 Then Exit Do
    Loop
    Term = v
End Function

Function Macht() As Double
    Dim v As Double, e As Double

    v = Primair()
    Do While Volgende() = "^"
        fPos = fPos + 1
        e = Unair()
        If v = 0 And e < 0 Then
            fFout = F_DEEL
            v = 0
        ElseIf v < 0 And e <> Int(e) Then
            fFout = F_GETAL
            v = 0
        Else
            v = v ^ e
        End If
        If fFout <> 0 Then Exit Do
    Loop
    Macht = v
End Function

Function Unair() As Double
    Dim ch As String

    ch = Volgende()
    If ch = "-" Then
        fPos = fPos + 1
        Unair = -Unair()
    ElseIf ch = "+" Then
        fPos = fPos + 1
        Unair = Unair()
    Else
        Unair = Macht()
    End If
End Function

Function Primair() As Double
    Dim v As Double
    Dim ch As String, naam As String, getal As String
    Dim a As Integer, b As Integer, k As Integer, r As Integer

    Primair = 0
    ch = Volgende()
    If Len(ch) = 0 Then
        fFout = F_SYNT
        Exit Function
    End If

    '' haakjes
    If ch = "(" Then
        fPos = fPos + 1
        v = Vergelijking()
        SlaSpatiesOver
        If Mid(fTxt, fPos, 1) = ")" Then
            fPos = fPos + 1
        Else
            fFout = F_SYNT
        End If
        Primair = v
        Exit Function
    End If

    '' voorteken
    If ch = "-" Or ch = "+" Then
        Primair = Unair()
        Exit Function
    End If

    '' een foutwaarde die bij het herschrijven is achtergelaten
    If ch = "#" Then
        Do While fPos <= Len(fTxt)
            ch = Mid(fTxt, fPos, 1)
            a = Asc(UCase(ch))
            If (a >= 65 And a <= 90) Or (a >= 48 And a <= 57) Or ch = "#" Or ch = "/" Or ch = "?" Then
                fPos = fPos + 1
            ElseIf ch = "!" Then
                fPos = fPos + 1
                Exit Do
            Else
                Exit Do
            End If
        Loop
        fFout = F_VERW
        Exit Function
    End If

    '' getal
    a = Asc(ch)
    If (a >= 48 And a <= 57) Or ch = "." Then
        getal = ""
        Do While fPos <= Len(fTxt)
            ch = Mid(fTxt, fPos, 1)
            a = Asc(ch)
            If (a >= 48 And a <= 57) Or ch = "." Then
                getal = getal + ch
                fPos = fPos + 1
            ElseIf ch = "e" Or ch = "E" Then
                '' alleen als er echt een macht van tien volgt
                ch = Mid(fTxt, fPos + 1, 1)
                a = 0
                If ch = "+" Or ch = "-" Then
                    ch = Mid(fTxt, fPos + 2, 1)
                    a = 1
                End If
                If Len(ch) > 0 Then
                    If Asc(ch) >= 48 And Asc(ch) <= 57 Then
                        getal = getal + Mid(fTxt, fPos, 1 + a)
                        fPos = fPos + 1 + a
                    Else
                        Exit Do
                    End If
                Else
                    Exit Do
                End If
            Else
                Exit Do
            End If
        Loop
        Primair = Val(getal)
        Exit Function
    End If

    '' het apenstaartje hoort bij de functienaam, bv. @SOM(...)
    If ch = "@" Then
        fPos = fPos + 1
        ch = Volgende()
    End If

    '' celverwijzing?
    If LeesCelRef(b, k, r) Then
        Primair = CelWaarde(b, k, r)
        Exit Function
    End If

    '' anders een naam: functie of vaste waarde
    naam = ""
    Do While fPos <= Len(fTxt)
        ch = Mid(fTxt, fPos, 1)
        a = Asc(UCase(ch))
        If (a >= 65 And a <= 90) Or (a >= 48 And a <= 57) Or ch = "_" Then
            naam = naam + ch
            fPos = fPos + 1
        Else
            Exit Do
        End If
    Loop

    If Len(naam) = 0 Then
        fFout = F_SYNT
        Exit Function
    End If

    naam = UCase(naam)
    If Volgende() = "(" Then
        fPos = fPos + 1
        Primair = Functie(naam)
        Exit Function
    End If

    Select Case naam
    Case "PI"     : Primair = 3.14159265358979323846
    Case "WAAR"   : Primair = 1
    Case "ONWAAR" : Primair = 0
    Case Else     : fFout = F_NAAM
    End Select
End Function

Sub VerwachtSluit()
    SlaSpatiesOver
    If Mid(fTxt, fPos, 1) = ")" Then
        fPos = fPos + 1
    Else
        fFout = F_SYNT
    End If
End Sub

Sub LeesArgs(a() As Double, ByRef n As Integer, ByVal maxN As Integer)
    Dim ch As String

    n = 0
    If Volgende() <> ")" Then
        Do
            If n >= maxN Then
                fFout = F_ARG
                Exit Do
            End If
            n = n + 1
            a(n) = Vergelijking()
            If fFout <> 0 Then Exit Do
            ch = Volgende()
            If ch = ";" Or ch = "," Then
                fPos = fPos + 1
            Else
                Exit Do
            End If
        Loop
    End If
    VerwachtSluit
End Sub

'' Telt één waarde mee in een optelling, gemiddelde, minimum of maximum.
Sub Verzamel(ByVal w As Double, ByRef n As Integer, ByRef tot As Double, ByRef mn As Double, ByRef mx As Double)
    n = n + 1
    tot = tot + w
    If n = 1 Then
        mn = w
        mx = w
    Else
        If w < mn Then mn = w
        If w > mx Then mx = w
    End If
End Sub

'' soort: 1 = som, 2 = gemiddelde, 3 = minimum, 4 = maximum, 5 = aantal
Function Aggregeer(ByVal soort As Integer) As Double
    Dim b As Integer, k1 As Integer, r1 As Integer, k2 As Integer, r2 As Integer
    Dim k As Integer, r As Integer, ci As Integer, n As Integer, sr As Integer
    Dim tot As Double, mn As Double, mx As Double, w As Double
    Dim ch As String

    n = 0 : tot = 0 : mn = 0 : mx = 0

    If Volgende() <> ")" Then
        Do
            If LeesBereik(b, k1, r1, k2, r2) Then
                For r = r1 To r2
                    For k = k1 To k2
                        ci = CelNr(b, k, r)
                        If ci > 0 Then
                            sr = blad(b).cel(ci).soort
                            If sr = S_GETAL Or sr = S_FORM Then
                                w = CelWaarde(b, k, r)
                                Verzamel w, n, tot, mn, mx
                            End If
                        End If
                    Next
                Next
            Else
                w = Vergelijking()
                Verzamel w, n, tot, mn, mx
            End If
            If fFout <> 0 Then Exit Do

            ch = Volgende()
            If ch = ";" Or ch = "," Then
                fPos = fPos + 1
            Else
                Exit Do
            End If
        Loop
    End If
    VerwachtSluit

    Select Case soort
    Case 1
        Aggregeer = tot
    Case 2
        If n = 0 Then
            fFout = F_DEEL
            Aggregeer = 0
        Else
            Aggregeer = tot / n
        End If
    Case 3
        Aggregeer = mn
    Case 4
        Aggregeer = mx
    Case 5
        Aggregeer = n
    Case Else
        Aggregeer = 0
    End Select
End Function

Function Functie(ByRef naam As String) As Double
    Dim a(1 To 8) As Double
    Dim n As Integer
    Dim f0 As Integer, fa As Integer, fb As Integer
    Dim v As Double, d1 As Double, d2 As Double, sch As Double
    Dim ch As String

    Functie = 0

    '' functies die over een bereik werken lezen hun eigen argumenten
    Select Case naam
    Case "SOM", "SUM"
        Functie = Aggregeer(1)
        Exit Function
    Case "GEM", "GEMIDDELDE", "AVG", "AVERAGE"
        Functie = Aggregeer(2)
        Exit Function
    Case "MIN"
        Functie = Aggregeer(3)
        Exit Function
    Case "MAX"
        Functie = Aggregeer(4)
        Exit Function
    Case "AANTAL", "COUNT"
        Functie = Aggregeer(5)
        Exit Function
    Case "ALS", "IF"
        '' de tak die niet gekozen wordt mag geen fout opleveren
        v = Vergelijking()
        ch = Volgende()
        If ch = ";" Or ch = "," Then
            fPos = fPos + 1
        Else
            fFout = F_ARG
        End If

        f0 = fFout
        fFout = 0
        d1 = Vergelijking()
        fa = fFout

        fFout = 0
        d2 = 0
        fb = 0
        ch = Volgende()
        If ch = ";" Or ch = "," Then
            fPos = fPos + 1
            d2 = Vergelijking()
            fb = fFout
        End If

        fFout = f0
        VerwachtSluit

        If v <> 0 Then
            If fa <> 0 Then fFout = fa
            Functie = d1
        Else
            If fb <> 0 Then fFout = fb
            Functie = d2
        End If
        Exit Function
    End Select

    LeesArgs a(), n, 8
    If fFout <> 0 Then Exit Function

    Select Case naam
    Case "PI"
        If n <> 0 Then fFout = F_ARG Else Functie = 3.14159265358979323846
    Case "ABS"
        If n <> 1 Then fFout = F_ARG Else Functie = Abs(a(1))
    Case "INT", "GEHEEL"
        If n <> 1 Then fFout = F_ARG Else Functie = Int(a(1))
    Case "WORTEL", "SQR", "SQRT"
        If n <> 1 Then
            fFout = F_ARG
        ElseIf a(1) < 0 Then
            fFout = F_GETAL
        Else
            Functie = Sqr(a(1))
        End If
    Case "EXP"
        If n <> 1 Then fFout = F_ARG Else Functie = Exp(a(1))
    Case "LN"
        If n <> 1 Then
            fFout = F_ARG
        ElseIf a(1) <= 0 Then
            fFout = F_GETAL
        Else
            Functie = Log(a(1))
        End If
    Case "LOG"
        If n <> 1 Then
            fFout = F_ARG
        ElseIf a(1) <= 0 Then
            fFout = F_GETAL
        Else
            Functie = Log(a(1)) / Log(10)
        End If
    Case "SIN"
        If n <> 1 Then fFout = F_ARG Else Functie = Sin(a(1))
    Case "COS"
        If n <> 1 Then fFout = F_ARG Else Functie = Cos(a(1))
    Case "TAN"
        If n <> 1 Then fFout = F_ARG Else Functie = Tan(a(1))
    Case "AFROND", "ROUND"
        If n < 1 Or n > 2 Then
            fFout = F_ARG
        Else
            d2 = 0
            If n = 2 Then d2 = Int(a(2))
            If d2 < -9 Then d2 = -9
            If d2 > 9 Then d2 = 9
            sch = 10 ^ d2
            d1 = a(1) * sch
            If d1 < 0 Then
                Functie = -Int(-d1 + 0.5) / sch
            Else
                Functie = Int(d1 + 0.5) / sch
            End If
        End If
    Case "REST", "MOD"
        If n <> 2 Then
            fFout = F_ARG
        ElseIf a(2) = 0 Then
            fFout = F_DEEL
        Else
            Functie = a(1) - Int(a(1) / a(2)) * a(2)
        End If
    Case "MACHT", "POWER"
        If n <> 2 Then
            fFout = F_ARG
        ElseIf a(1) = 0 And a(2) < 0 Then
            fFout = F_DEEL
        ElseIf a(1) < 0 And a(2) <> Int(a(2)) Then
            fFout = F_GETAL
        Else
            Functie = a(1) ^ a(2)
        End If
    Case "TEKEN", "SGN"
        If n <> 1 Then
            fFout = F_ARG
        Else
            Functie = Sgn(a(1))
        End If
    Case Else
        fFout = F_NAAM
    End Select
End Function

'' Rekent alle formules van alle tabbladen opnieuw uit. Cellen die tijdens dat
'' rondje al aan de beurt zijn geweest, herkennen we aan hun generatiemerk.
Sub Herbereken()
    Dim b As Integer, i As Integer

    gen = gen + 1
    fDiepte = 0
    For b = 1 To nBladen
        For i = 1 To blad(b).aantal
            blad(b).cel(i).bezig = 0
        Next
    Next

    For b = 1 To nBladen
        For i = 1 To blad(b).aantal
            If blad(b).cel(i).soort = S_FORM Then
                If blad(b).cel(i).merk <> gen Then
                    fFout = 0
                    BerekenCel b, i
                End If
            End If
        Next
    Next
    fFout = 0
End Sub

'' ==========================================================================
''  Bestanden
''
''  Het formaat is platte tekst en zo eenvoudig dat je het met elke editor
''  kunt nakijken:
''      ## blad <naam>          begint een tabblad
''      ! kolom B breedte=12 dec=2 uit=r
''      ! cursor B4
''      B4: 850                 celverwijzing, dubbele punt, ruwe invoer
'' ==========================================================================

Sub SlaOp(ByRef naam As String)
    Dim fnum As Integer
    Dim b As Integer, k As Integer, r As Integer, ci As Integer
    Dim s As String

    fnum = FreeFile
    If Open(naam For Output As #fnum) <> 0 Then
        melding = Tn("Kan %1 niet schrijven!", naam, "", "")
        Exit Sub
    End If

    Print #fnum, "# " + APP_NAAM + " " + APP_VER + " werkmap"
    For b = 1 To nBladen
        Print #fnum, ""
        Print #fnum, "## blad " + blad(b).naam
        For k = 0 To MAX_KOL - 1
            If blad(b).breed(k) <> STD_BREED Or blad(b).dec(k) <> -1 Or blad(b).uit(k) <> U_AUTO Then
                s = "! kolom " + KolNaam(k) + " breedte=" + Trim(Str(blad(b).breed(k)))
                If blad(b).dec(k) >= 0 Then s = s + " dec=" + Trim(Str(blad(b).dec(k)))
                Select Case blad(b).uit(k)
                Case U_LINKS  : s = s + " uit=l"
                Case U_RECHTS : s = s + " uit=r"
                Case U_MIDDEN : s = s + " uit=m"
                End Select
                Print #fnum, s
            End If
        Next
        Print #fnum, "! cursor " + CelNaam(blad(b).curK, blad(b).curR)

        For r = 0 To MAX_RIJ - 1
            For k = 0 To MAX_KOL - 1
                ci = blad(b).idx(k, r)
                If ci > 0 Then
                    If Len(blad(b).cel(ci).tekst) > 0 Then
                        Print #fnum, CelNaam(k, r) + ": " + blad(b).cel(ci).tekst
                    End If
                End If
            Next
        Next
    Next

    Close #fnum
    gewijzigd = 0
    melding = Tn("Opgeslagen in %1", naam, "", "")
End Sub

Sub LaadBestand()
    Dim fnum As Integer
    Dim s As String, w As String, sleutel As String, wrd As String
    Dim b As Integer, k As Integer, r As Integer
    Dim e As Integer, p As Integer, absK As Integer, absR As Integer
    Dim bn As String

    nBladen = 0

    fnum = FreeFile
    If Open(bestand For Input As #fnum) <> 0 Then Exit Sub

    Do While Not EOF(fnum)
        Line Input #fnum, s
        If Right(s, 1) = Chr(13) Then s = Left(s, Len(s) - 1)

        If Left(s, 8) = "## blad " Then
            If nBladen < MAX_BLAD Then
                nBladen = nBladen + 1
                w = SchoneNaam(Mid(s, 9))
                If Len(w) = 0 Then w = "Blad" + Trim(Str(nBladen))
                LeegBlad nBladen, w
                b = nBladen
            Else
                b = 0
            End If

        ElseIf Left(s, 1) = "#" Then
            '' opmerkingsregel

        ElseIf Left(s, 1) = "!" Then
            If b > 0 Then
                w = LTrim(Mid(s, 2))
                If LCase(Left(w, 6)) = "kolom " Then
                    w = LTrim(Mid(w, 7))
                    p = InStr(w, " ")
                    If p = 0 Then p = Len(w) + 1
                    k = KolNummer(Left(w, p - 1))
                    w = LTrim(Mid(w, p))
                    If k >= 0 Then
                        Do While Len(w) > 0
                            p = InStr(w, " ")
                            If p = 0 Then
                                wrd = w
                                w = ""
                            Else
                                wrd = Left(w, p - 1)
                                w = LTrim(Mid(w, p))
                            End If
                            p = InStr(wrd, "=")
                            If p > 0 Then
                                sleutel = LCase(Left(wrd, p - 1))
                                wrd = Mid(wrd, p + 1)
                                Select Case sleutel
                                Case "breedte"
                                    blad(b).breed(k) = Val(wrd)
                                    If blad(b).breed(k) < MIN_BREED Then blad(b).breed(k) = MIN_BREED
                                    If blad(b).breed(k) > MAX_BREED Then blad(b).breed(k) = MAX_BREED
                                Case "dec"
                                    blad(b).dec(k) = Val(wrd)
                                    If blad(b).dec(k) < -1 Then blad(b).dec(k) = -1
                                    If blad(b).dec(k) > 6 Then blad(b).dec(k) = 6
                                Case "uit"
                                    Select Case LCase(wrd)
                                    Case "l" : blad(b).uit(k) = U_LINKS
                                    Case "r" : blad(b).uit(k) = U_RECHTS
                                    Case "m" : blad(b).uit(k) = U_MIDDEN
                                    Case Else : blad(b).uit(k) = U_AUTO
                                    End Select
                                End Select
                            End If
                        Loop
                    End If
                ElseIf LCase(Left(w, 7)) = "cursor " Then
                    w = Trim(Mid(w, 8))
                    If LeesRefOp(w, 1, e, bn, absK, k, absR, r) Then
                        blad(b).curK = k
                        blad(b).curR = r
                    End If
                End If
            End If

        ElseIf Len(Trim(s)) > 0 Then
            '' een met de hand getikt bestand hoeft niet met ## blad te beginnen
            If b = 0 And nBladen = 0 Then
                nBladen = 1
                w = "Blad1"
                LeegBlad 1, w
                b = 1
            End If
            If b > 0 Then
                If LeesRefOp(s, 1, e, bn, absK, k, absR, r) Then
                    If Mid(s, e, 1) = ":" Then
                        w = Mid(s, e + 1)
                        If Left(w, 1) = " " Then w = Mid(w, 2)
                        If Len(w) > MAX_TXT Then w = Left(w, MAX_TXT)
                        ZetCelTekst b, k, r, w
                    End If
                End If
            End If
        End If
    Loop

    Close #fnum
End Sub

Sub SlaOpAls()
    Dim ok As Integer
    Dim naam As String

    naam = VraagTekst(Vt("Opslaan als"), Vt("Bestandsnaam:"), bestand, ok)
    If ok = 0 Then Exit Sub
    naam = Trim(naam)
    If Len(naam) = 0 Then Exit Sub
    If InStr(naam, SEP) = 0 And InStr(naam, "\") = 0 Then naam = dataMap + SEP + naam
    bestand = naam
    SlaOp bestand
End Sub

'' Zet het huidige tabblad om naar CSV: puntkomma's als scheiding en een komma
'' als decimaalteken, want daar zijn Excel en LibreOffice hier op ingesteld.
'' Eén regel aanpassen is genoeg als je het anders wilt.
Sub ExportCsv()
    Dim fnum As Integer, ok As Integer
    Dim k As Integer, r As Integer, i As Integer, ci As Integer
    Dim maxK As Integer, maxR As Integer, kleur As Integer, isTxt As Integer
    Dim naam As String, regel As String, veld As String, s As String

    naam = bestand
    i = InStr(naam, ".")
    Do While InStr(i + 1, naam, ".") > 0
        i = InStr(i + 1, naam, ".")
    Loop
    If i > 0 Then naam = Left(naam, i - 1)
    naam = naam + "_" + blad(curB).naam + ".csv"

    naam = VraagTekst(Vt("Exporteren naar CSV"), Vt("Bestandsnaam:"), naam, ok)
    If ok = 0 Then Exit Sub
    naam = Trim(naam)
    If Len(naam) = 0 Then Exit Sub
    If InStr(naam, SEP) = 0 And InStr(naam, "\") = 0 Then naam = dataMap + SEP + naam

    maxK = -1
    maxR = -1
    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).k > maxK Then maxK = blad(curB).cel(i).k
        If blad(curB).cel(i).r > maxR Then maxR = blad(curB).cel(i).r
    Next
    If maxK < 0 Then
        Melden Vt("Dit tabblad is leeg.")
        Exit Sub
    End If

    fnum = FreeFile
    If Open(naam For Output As #fnum) <> 0 Then
        Melden Tn("Kan %1 niet schrijven!", naam, "", "")
        Exit Sub
    End If

    For r = 0 To maxR
        regel = ""
        For k = 0 To maxK
            CelToon curB, k, r, 20, veld, kleur, isTxt
            veld = Trim(veld)
            If isTxt = 0 Then
                '' decimale punt wordt een komma
                i = InStr(veld, ".")
                If i > 0 Then veld = Left(veld, i - 1) + "," + Mid(veld, i + 1)
            End If
            If InStr(veld, ";") > 0 Or InStr(veld, Chr(34)) > 0 Then
                s = ""
                For i = 1 To Len(veld)
                    If Mid(veld, i, 1) = Chr(34) Then
                        s = s + Chr(34) + Chr(34)
                    Else
                        s = s + Mid(veld, i, 1)
                    End If
                Next
                veld = Chr(34) + s + Chr(34)
            End If
            If k > 0 Then regel = regel + ";"
            regel = regel + veld
        Next
        Print #fnum, regel
    Next

    Close #fnum
    melding = Tn("Tabblad %1 staat in %2", blad(curB).naam, naam, "")
End Sub

Sub MaakDemo()
    Dim b As Integer

    nBladen = 2
    LeegBlad 1, "Begroting"
    LeegBlad 2, "Rente"

    b = 1
    blad(b).breed(0) = 20
    blad(b).breed(1) = 12
    blad(b).dec(1)   = 2
    ZetCelTekst b, 0, 0, "Maandbegroting"
    ZetCelTekst b, 0, 2, "Post"
    ZetCelTekst b, 1, 2, "Bedrag"
    ZetCelTekst b, 0, 3, "Huur"
    ZetCelTekst b, 1, 3, "850"
    ZetCelTekst b, 0, 4, "Energie"
    ZetCelTekst b, 1, 4, "145.50"
    ZetCelTekst b, 0, 5, "Boodschappen"
    ZetCelTekst b, 1, 5, "420"
    ZetCelTekst b, 0, 6, "Verzekeringen"
    ZetCelTekst b, 1, 6, "96.25"
    ZetCelTekst b, 0, 7, "Vervoer"
    ZetCelTekst b, 1, 7, "78"
    ZetCelTekst b, 0, 9, "Totaal per maand"
    ZetCelTekst b, 1, 9, "=SOM(B4:B8)"
    ZetCelTekst b, 0, 10, "Per week"
    ZetCelTekst b, 1, 10, "=AFROND(B10/4.33;2)"
    ZetCelTekst b, 0, 12, "Saldo na een jaar"
    ZetCelTekst b, 1, 12, "=Rente!B6"
    ZetCelTekst b, 0, 14, "Typ over een cel heen om hem te wijzigen, F1 geeft hulp."

    b = 2
    blad(b).breed(0) = 14
    blad(b).breed(1) = 14
    blad(b).dec(1)   = 2
    ZetCelTekst b, 0, 0, "Startbedrag"
    ZetCelTekst b, 1, 0, "1000"
    ZetCelTekst b, 0, 1, "Rente in %"
    ZetCelTekst b, 1, 1, "4.5"
    ZetCelTekst b, 0, 3, "Jaar"
    ZetCelTekst b, 1, 3, "Saldo"
    ZetCelTekst b, 0, 4, "0"
    ZetCelTekst b, 1, 4, "=$B$1"
    ZetCelTekst b, 0, 5, "1"
    ZetCelTekst b, 1, 5, "=$B$1*(1+$B$2/100)^A6"
    ZetCelTekst b, 0, 6, "2"
    ZetCelTekst b, 1, 6, "=$B$1*(1+$B$2/100)^A7"
    ZetCelTekst b, 0, 7, "3"
    ZetCelTekst b, 1, 7, "=$B$1*(1+$B$2/100)^A8"

    curB = 1
    gewijzigd = 0
End Sub

'' ==========================================================================
''  Bewerken
'' ==========================================================================

'' Invoeren of wijzigen van de cursorcel, op de invoerregel bovenin.
Sub Invoer(ByRef start As String)
    Dim ok As Integer
    Dim c As Integer, w As Integer
    Dim kop As String, res As String

    kop = " " + CelNaam(blad(curB).curK, blad(curB).curR) + ": "
    PutStr 2, 1, Pad(kop, scrW), C_INV_FG, C_INV_BG
    PutStr scrH, 1, Pad(Vt(" Enter = vastleggen   Esc = annuleren   Ctrl+U = leegmaken"), scrW), C_BALK_FG, C_BALK_BG

    c = Len(kop) + 1
    w = scrW - c
    res = RegelEdit(2, c, w, start, ok)

    If ok Then
        ZetCelTekst curB, blad(curB).curK, blad(curB).curR, res
        gewijzigd = -1
        Herbereken
        If blad(curB).curR < MAX_RIJ - 1 Then blad(curB).curR = blad(curB).curR + 1
    End If
End Sub

Sub BewerkCel()
    Dim s As String
    s = CelTekst(curB, blad(curB).curK, blad(curB).curR)
    Invoer s
End Sub

Sub WisHuidige()
    If CelNr(curB, blad(curB).curK, blad(curB).curR) = 0 Then Exit Sub
    WisCel curB, blad(curB).curK, blad(curB).curR
    gewijzigd = -1
    Herbereken
End Sub

Sub KolomBreedte()
    Dim ok As Integer, k As Integer, n As Integer
    Dim s As String, t As String

    k = blad(curB).curK
    t = Trim(Str(blad(curB).breed(k)))
    s = VraagTekst(Vt("Kolombreedte"), Tn("Breedte van kolom %1 (%2..%3):", KolNaam(k), _
                   Trim(Str(MIN_BREED)), Trim(Str(MAX_BREED))), t, ok)
    If ok = 0 Then Exit Sub

    n = Val(s)
    If n < MIN_BREED Then n = MIN_BREED
    If n > MAX_BREED Then n = MAX_BREED
    blad(curB).breed(k) = n
    gewijzigd = -1
    melding = Tn("Kolom %1 is nu %2 tekens breed.", KolNaam(k), Trim(Str(n)), "")
End Sub

Sub KolomOpmaak()
    Dim it(1 To 8) As String
    Dim k As Integer, n As Integer, start As String

    k = blad(curB).curK

    it(1) = Vt("Algemeen (zoveel cijfers als nodig)")
    it(2) = Vt("0 decimalen")
    it(3) = Vt("1 decimaal")
    it(4) = Vt("2 decimalen")
    it(5) = Vt("3 decimalen")
    it(6) = Vt("4 decimalen")
    start = Tn("Decimalen in kolom %1", KolNaam(k), "", "")
    n = Kies(start, it(), 6, blad(curB).dec(k) + 2)
    If n = 0 Then Exit Sub
    blad(curB).dec(k) = n - 2

    it(1) = Vt("Automatisch (tekst links, getallen rechts)")
    it(2) = Vt("Links")
    it(3) = Vt("Rechts")
    it(4) = Vt("Midden")
    start = Tn("Uitlijning in kolom %1", KolNaam(k), "", "")
    n = Kies(start, it(), 4, blad(curB).uit(k) + 1)
    If n > 0 Then blad(curB).uit(k) = n - 1

    gewijzigd = -1
End Sub

'' Vraagt om een bereik als "B2" of "B2:D10" (ook "B2..D10" mag).
Function VraagBereik(ByRef titel As String, ByRef prompt As String, ByRef start As String, ByRef k1 As Integer, ByRef r1 As Integer, ByRef k2 As Integer, ByRef r2 As Integer) As Integer
    Dim ok As Integer, e As Integer, p As Integer, h As Integer
    Dim absK As Integer, absR As Integer, tweede As Integer
    Dim s As String, bn As String

    VraagBereik = 0
    s = VraagTekst(titel, prompt, start, ok)
    If ok = 0 Then Exit Function
    s = Trim(s)
    If Len(s) = 0 Then Exit Function

    If LeesRefOp(s, 1, e, bn, absK, k1, absR, r1) = 0 Then
        Melden Tn("Dat is geen geldig bereik: %1", s, "", "")
        Exit Function
    End If

    tweede = 0
    p = e
    If Mid(s, p, 2) = ".." Then
        p = p + 2
        tweede = -1
    ElseIf Mid(s, p, 1) = ":" Then
        p = p + 1
        tweede = -1
    End If

    If tweede Then
        If LeesRefOp(s, p, e, bn, absK, k2, absR, r2) = 0 Then
            Melden Tn("Dat is geen geldig bereik: %1", s, "", "")
            Exit Function
        End If
    Else
        k2 = k1
        r2 = r1
    End If

    If k1 > k2 Then
        h = k1 : k1 = k2 : k2 = h
    End If
    If r1 > r2 Then
        h = r1 : r1 = r2 : r2 = h
    End If
    VraagBereik = -1
End Function

Sub Kopieer()
    Dim k1 As Integer, r1 As Integer, k2 As Integer, r2 As Integer
    Dim k As Integer, r As Integer, n As Integer
    Dim s As String, start As String

    start = CelNaam(blad(curB).curK, blad(curB).curR)
    If VraagBereik(Vt("Kopieren"), Vt("Welk bereik wil je kopieren?"), start, k1, r1, k2, r2) = 0 Then Exit Sub

    n = 0
    For r = r1 To r2
        For k = k1 To k2
            s = CelTekst(curB, k, r)
            If Len(s) > 0 Then
                If n >= MAX_KLEM Then
                    Melden Vt("Zoveel cellen passen niet op het klembord.")
                    Exit Sub
                End If
                n = n + 1
                klemK(n) = k - k1
                klemR(n) = r - r1
                klemT(n) = s
            End If
        Next
    Next

    klemN  = n
    klemK1 = k1 : klemR1 = r1
    klemK2 = k2 : klemR2 = r2
    melding = Tn("Gekopieerd: %1:%2 %3 gevulde cel(len)", CelNaam(k1, r1), CelNaam(k2, r2), _
              Trim(Str(n)))
End Sub

Sub Plak()
    Dim k1 As Integer, r1 As Integer, k2 As Integer, r2 As Integer
    Dim bh As Integer, bv As Integer
    Dim dk As Integer, dr As Integer
    Dim k As Integer, r As Integer, i As Integer, n As Integer
    Dim sk As Integer, sr As Integer
    Dim s As String, start As String, eerste As String

    If klemK2 < klemK1 Then
        Melden Vt("Er staat nog niets op het klembord (Ctrl+K).")
        Exit Sub
    End If

    bh = klemK2 - klemK1 + 1
    bv = klemR2 - klemR1 + 1

    start = CelNaam(blad(curB).curK, blad(curB).curR)
    If VraagBereik(Vt("Plakken"), Vt("Waar moet het naartoe?"), start, k1, r1, k2, r2) = 0 Then Exit Sub

    '' Eén cel op het klembord vult een heel doelbereik; een blok wordt één
    '' keer neergezet, linksboven in het doel.
    If bh > 1 Or bv > 1 Then
        k2 = k1 + bh - 1
        r2 = r1 + bv - 1
    End If
    If k2 >= MAX_KOL Then k2 = MAX_KOL - 1
    If r2 >= MAX_RIJ Then r2 = MAX_RIJ - 1

    n = 0
    For r = r1 To r2 Step bv
        For k = k1 To k2 Step bh
            '' eerst het doelblok leegmaken, ook waar de bron leeg was
            For sr = 0 To bv - 1
                For sk = 0 To bh - 1
                    If k + sk <= k2 And r + sr <= r2 Then WisCel curB, k + sk, r + sr
                Next
            Next

            dk = k - klemK1
            dr = r - klemR1
            For i = 1 To klemN
                sk = k + klemK(i)
                sr = r + klemR(i)
                If sk <= k2 And sr <= r2 And sk < MAX_KOL And sr < MAX_RIJ Then
                    s = klemT(i)
                    eerste = Left(s, 1)
                    If eerste = "=" Or eerste = "+" Or eerste = "@" Then
                        If IsGetal(s) = 0 Then s = VerschuifFormule(s, dk, dr)
                    End If
                    ZetCelTekst curB, sk, sr, s
                    n = n + 1
                End If
            Next
        Next
    Next

    gewijzigd = -1
    Herbereken
    melding = Tn("%1 cel(len) geplakt.", Trim(Str(n)), "", "")
End Sub

Sub BlokWissen()
    Dim k1 As Integer, r1 As Integer, k2 As Integer, r2 As Integer
    Dim k As Integer, r As Integer, n As Integer
    Dim start As String

    start = CelNaam(blad(curB).curK, blad(curB).curR)
    If VraagBereik(Vt("Leegmaken"), Vt("Welk bereik moet leeg?"), start, k1, r1, k2, r2) = 0 Then Exit Sub

    n = 0
    For r = r1 To r2
        For k = k1 To k2
            If CelNr(curB, k, r) > 0 Then
                WisCel curB, k, r
                n = n + 1
            End If
        Next
    Next

    gewijzigd = -1
    Herbereken
    melding = Tn("%1 cel(len) leeggemaakt.", Trim(Str(n)), "", "")
End Sub

Sub RijInvoegen()
    Dim i As Integer, r As Integer

    r = blad(curB).curR
    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).r = MAX_RIJ - 1 Then
            Melden Vt("De onderste rij is niet leeg; er kan niets bij.")
            Exit Sub
        End If
    Next

    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).r >= r Then blad(curB).cel(i).r = blad(curB).cel(i).r + 1
    Next
    HerbouwIndex curB
    PasRefsAan curB, 0, r, 1

    gewijzigd = -1
    Herbereken
    melding = Tn("Rij %1 ingevoegd.", Trim(Str(r + 1)), "", "")
End Sub

Sub RijVerwijderen()
    Dim ks(0 To MAX_KOL - 1) As Integer
    Dim i As Integer, n As Integer, r As Integer

    r = blad(curB).curR

    n = 0
    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).r = r Then
            ks(n) = blad(curB).cel(i).k
            n = n + 1
        End If
    Next
    For i = 0 To n - 1
        WisCel curB, ks(i), r
    Next

    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).r > r Then blad(curB).cel(i).r = blad(curB).cel(i).r - 1
    Next
    HerbouwIndex curB
    PasRefsAan curB, 0, r, -1

    gewijzigd = -1
    Herbereken
    melding = Tn("Rij %1 verwijderd.", Trim(Str(r + 1)), "", "")
End Sub

Sub KolomInvoegen()
    Dim i As Integer, k As Integer

    k = blad(curB).curK
    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).k = MAX_KOL - 1 Then
            Melden Vt("De laatste kolom (IV) is niet leeg; er kan niets bij.")
            Exit Sub
        End If
    Next

    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).k >= k Then blad(curB).cel(i).k = blad(curB).cel(i).k + 1
    Next
    For i = MAX_KOL - 1 To k + 1 Step -1
        blad(curB).breed(i) = blad(curB).breed(i - 1)
        blad(curB).dec(i)   = blad(curB).dec(i - 1)
        blad(curB).uit(i)   = blad(curB).uit(i - 1)
    Next
    blad(curB).breed(k) = STD_BREED
    blad(curB).dec(k)   = -1
    blad(curB).uit(k)   = U_AUTO

    HerbouwIndex curB
    PasRefsAan curB, -1, k, 1

    gewijzigd = -1
    Herbereken
    melding = Tn("Kolom %1 ingevoegd.", KolNaam(k), "", "")
End Sub

Sub KolomVerwijderen()
    Dim rs(0 To MAX_RIJ - 1) As Integer
    Dim i As Integer, n As Integer, k As Integer

    k = blad(curB).curK

    n = 0
    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).k = k Then
            rs(n) = blad(curB).cel(i).r
            n = n + 1
        End If
    Next
    For i = 0 To n - 1
        WisCel curB, k, rs(i)
    Next

    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).k > k Then blad(curB).cel(i).k = blad(curB).cel(i).k - 1
    Next
    For i = k To MAX_KOL - 2
        blad(curB).breed(i) = blad(curB).breed(i + 1)
        blad(curB).dec(i)   = blad(curB).dec(i + 1)
        blad(curB).uit(i)   = blad(curB).uit(i + 1)
    Next
    blad(curB).breed(MAX_KOL - 1) = STD_BREED
    blad(curB).dec(MAX_KOL - 1)   = -1
    blad(curB).uit(MAX_KOL - 1)   = U_AUTO

    HerbouwIndex curB
    PasRefsAan curB, -1, k, -1

    gewijzigd = -1
    Herbereken
    melding = Tn("Kolom %1 verwijderd.", KolNaam(k), "", "")
End Sub

Sub GaNaar()
    Dim ok As Integer, e As Integer, b As Integer
    Dim absK As Integer, absR As Integer, k As Integer, r As Integer
    Dim s As String, bn As String, start As String

    start = CelNaam(blad(curB).curK, blad(curB).curR)
    s = VraagTekst(Vt("Ga naar"), Tn("Naar welke cel? (bv. C12 of %1!A1)", blad(curB).naam, "", ""), start, ok)
    If ok = 0 Then Exit Sub
    s = Trim(s)
    If Len(s) = 0 Then Exit Sub

    If LeesRefOp(s, 1, e, bn, absK, k, absR, r) = 0 Then
        Melden Tn("Dat is geen celverwijzing: %1", s, "", "")
        Exit Sub
    End If

    If Len(bn) > 0 Then
        b = BladNummer(bn)
        If b = 0 Then
            Melden Tn("Er is geen tabblad dat %1 heet.", bn, "", "")
            Exit Sub
        End If
        curB = b
    End If

    blad(curB).curK = k
    blad(curB).curR = r
End Sub

Sub Zoek()
    Dim hitB(1 To MAX_HITS) As Integer
    Dim hitK(1 To MAX_HITS) As Integer
    Dim hitR(1 To MAX_HITS) As Integer
    Dim it(1 To MAX_HITS) As String
    Dim b As Integer, i As Integer, n As Integer, ok As Integer
    Dim zoekt As String, leeg As String, s As String

    leeg = ""
    ok = 0
    zoekt = VraagTekst(Vt("Zoeken"), Vt("Zoek naar (in alle tabbladen):"), leeg, ok)
    If ok = 0 Then Exit Sub
    zoekt = Trim(zoekt)
    If Len(zoekt) = 0 Then Exit Sub

    n = 0
    For b = 1 To nBladen
        For i = 1 To blad(b).aantal
            If InStr(LCase(blad(b).cel(i).tekst), LCase(zoekt)) > 0 Then
                If n < MAX_HITS Then
                    n = n + 1
                    hitB(n) = b
                    hitK(n) = blad(b).cel(i).k
                    hitR(n) = blad(b).cel(i).r
                    it(n) = Pad(blad(b).naam + "!" + CelNaam(hitK(n), hitR(n)), 24) + _
                            blad(b).cel(i).tekst
                End If
            End If
        Next
    Next

    If n = 0 Then
        Melden Tn("Niets gevonden voor: %1", zoekt, "", "")
        Exit Sub
    End If

    s = Tn("Gevonden: %1", zoekt, "", "")
    i = Kies(s, it(), n, 1)
    If i > 0 Then
        curB = hitB(i)
        blad(curB).curK = hitK(i)
        blad(curB).curR = hitR(i)
    End If
End Sub

'' ==========================================================================
''  Tabbladen
'' ==========================================================================

'' Kopieert een heel tabblad, cel voor cel. Een BladType in zijn geheel
'' toewijzen zou een megabyte verplaatsen én de strings erin verwarren.
Sub KopieerBlad(ByVal bd As Integer, ByVal bs As Integer)
    Dim i As Integer, k As Integer
    Dim naam As String

    naam = blad(bs).naam
    LeegBlad bd, naam
    For k = 0 To MAX_KOL - 1
        blad(bd).breed(k) = blad(bs).breed(k)
        blad(bd).dec(k)   = blad(bs).dec(k)
        blad(bd).uit(k)   = blad(bs).uit(k)
    Next
    blad(bd).aantal = blad(bs).aantal
    For i = 1 To blad(bs).aantal
        KopieerCelData bd, i, bs, i
    Next
    blad(bd).curK = blad(bs).curK
    blad(bd).curR = blad(bs).curR
    blad(bd).topK = blad(bs).topK
    blad(bd).topR = blad(bs).topR
    HerbouwIndex bd
End Sub

'' Past formules aan als een tabblad een andere naam krijgt.
Sub HernoemVerwijzingen(ByRef oud As String, ByRef nieuw As String)
    Dim b As Integer, ci As Integer
    Dim s As String, res As String, bn As String, ch As String
    Dim i As Integer, e As Integer, a As Integer, vorig As Integer, gedaan As Integer
    Dim absK As Integer, absR As Integer, k As Integer, r As Integer

    For b = 1 To nBladen
        For ci = 1 To blad(b).aantal
            If blad(b).cel(ci).soort = S_FORM Then
                s = blad(b).cel(ci).tekst
                res = ""
                i = 1
                vorig = 0
                Do While i <= Len(s)
                    gedaan = 0
                    ch = Mid(s, i, 1)
                    a = Asc(UCase(ch))
                    If vorig = 0 And ((a >= 65 And a <= 90) Or ch = "$") Then
                        If LeesRefOp(s, i, e, bn, absK, k, absR, r) Then
                            If LCase(bn) = LCase(oud) Then bn = nieuw
                            res = res + RefTekst(bn, absK, k, absR, r)
                            i = e
                            vorig = 0
                            gedaan = -1
                        End If
                    End If
                    If gedaan = 0 Then
                        res = res + ch
                        If (a >= 48 And a <= 57) Or (a >= 65 And a <= 90) Or a = 95 Or ch = "$" Or ch = "!" Then
                            vorig = -1
                        Else
                            vorig = 0
                        End If
                        i = i + 1
                    End If
                Loop
                blad(b).cel(ci).tekst = res
            End If
        Next
    Next
End Sub

Sub NieuwBlad()
    Dim ok As Integer
    Dim naam As String, voorstel As String

    If nBladen >= MAX_BLAD Then
        Melden Tn("Meer dan %1 tabbladen kan niet.", Trim(Str(MAX_BLAD)), "", "")
        Exit Sub
    End If

    voorstel = "Blad" + Trim(Str(nBladen + 1))
    naam = VraagTekst(Vt("Nieuw tabblad"), Vt("Naam (letters, cijfers, liggend streepje):"), voorstel, ok)
    If ok = 0 Then Exit Sub
    naam = SchoneNaam(naam)
    If Len(naam) = 0 Then naam = voorstel
    If BladNummer(naam) > 0 Then
        Melden Tn("Er is al een tabblad dat %1 heet.", naam, "", "")
        Exit Sub
    End If

    nBladen = nBladen + 1
    LeegBlad nBladen, naam
    curB = nBladen
    gewijzigd = -1
    melding = Tn("Tabblad %1 aangemaakt.", naam, "", "")
End Sub

Sub HernoemBlad()
    Dim ok As Integer, b As Integer
    Dim naam As String, oud As String

    oud = blad(curB).naam
    naam = VraagTekst(Vt("Tabblad hernoemen"), Vt("Nieuwe naam:"), oud, ok)
    If ok = 0 Then Exit Sub
    naam = SchoneNaam(naam)
    If Len(naam) = 0 Then Exit Sub
    If LCase(naam) = LCase(oud) Then Exit Sub

    b = BladNummer(naam)
    If b > 0 Then
        Melden Tn("Er is al een tabblad dat %1 heet.", naam, "", "")
        Exit Sub
    End If

    blad(curB).naam = naam
    HernoemVerwijzingen oud, naam
    gewijzigd = -1
    Herbereken
    melding = Tn("%1 heet nu %2.", oud, naam, "")
End Sub

Sub VerwijderBlad()
    Dim i As Integer
    Dim naam As String, leeg As String

    If nBladen <= 1 Then
        Melden Vt("Er moet minstens een tabblad overblijven.")
        Exit Sub
    End If

    naam = blad(curB).naam
    If Bevestig(Tn("Tabblad %1 verwijderen?", naam, "", "")) = 0 Then Exit Sub

    For i = curB To nBladen - 1
        KopieerBlad i, i + 1
    Next
    leeg = ""
    LeegBlad nBladen, leeg
    nBladen = nBladen - 1
    If curB > nBladen Then curB = nBladen

    gewijzigd = -1
    Herbereken
    melding = Tn("Tabblad %1 is weg. Formules die ernaar verwezen geven nu #NAAM?.", naam, "", "")
End Sub

Sub WisselBlad(ByVal delta As Integer)
    curB = curB + delta
    If curB < 1 Then curB = nBladen
    If curB > nBladen Then curB = 1
End Sub

'' Laat zien welke code een toets oplevert. Handig als een toets niets lijkt
'' te doen: zo is meteen te zien of hij het programma bereikt, en met welke
'' code. De vensterbeheerder pikt sommige toetsen namelijk zelf in.
Sub ToetsProef()
    Dim t As Integer, ext As Integer
    Dim r As Integer, c As Integer, h As Integer, w As Integer
    Dim titel As String, s As String

    w = 46
    If w > scrW - 4 Then w = scrW - 4
    h = 8
    r = (scrH - h) \ 2 + 1
    c = (scrW - w) \ 2 + 1
    titel = Vt("Toetsproef")
    s = Vt("(nog geen toets)")

    Do
        Venster r, c, h, w, titel
        PutStr r + 1, c + 2, Kort(Vt("Druk op een toets."), w - 4), C_DLG_FG, C_DLG_BG
        PutStr r + 3, c + 2, Pad(Kort(s, w - 4), w - 4), C_SEL_FG, C_SEL_BG
        PutStr r + h - 2, c + 2, Kort(Vt("Ctrl+Q = terug"), w - 4), C_DLG_FG, C_DLG_BG

        ext = 0
        t = WachtToets(ext)
        If ext = 0 And t = 17 Then Exit Do

        If ext Then
            s = Tn("uitgebreid, scancode %1", Trim(Str(t)), "", "")
        Else
            s = Tn("gewoon, code %1", Trim(Str(t)), "", "")
            If t >= 32 And t <= 126 Then s = s + "  " + Tn("teken %1", Chr(t), "", "")
        End If
    Loop

    Redraw
End Sub

'' ==========================================================================
''  Tekenen
'' ==========================================================================

'' De laatste kolom die nog helemaal op het scherm past.
Function LaatsteKolom() As Integer
    Dim k As Integer, br As Integer, laatste As Integer

    br = 0
    laatste = blad(curB).topK
    For k = blad(curB).topK To MAX_KOL - 1
        br = br + blad(curB).breed(k)
        If br > scrW - GUT Then Exit For
        laatste = k
    Next
    LaatsteKolom = laatste
End Function

Sub ZorgZichtbaar()
    Dim rijen As Integer

    If blad(curB).curK < 0 Then blad(curB).curK = 0
    If blad(curB).curK > MAX_KOL - 1 Then blad(curB).curK = MAX_KOL - 1
    If blad(curB).curR < 0 Then blad(curB).curR = 0
    If blad(curB).curR > MAX_RIJ - 1 Then blad(curB).curR = MAX_RIJ - 1

    rijen = rBot - rTop + 1
    If blad(curB).topR < 0 Then blad(curB).topR = 0
    If blad(curB).curR < blad(curB).topR Then blad(curB).topR = blad(curB).curR
    If blad(curB).curR > blad(curB).topR + rijen - 1 Then blad(curB).topR = blad(curB).curR - rijen + 1
    If blad(curB).topR < 0 Then blad(curB).topR = 0

    If blad(curB).topK < 0 Then blad(curB).topK = 0
    If blad(curB).curK < blad(curB).topK Then blad(curB).topK = blad(curB).curK
    Do While blad(curB).curK > LaatsteKolom()
        If blad(curB).topK >= MAX_KOL - 1 Then Exit Do
        blad(curB).topK = blad(curB).topK + 1
    Loop
End Sub

Function Uitlijn(ByRef s As String, ByVal breedte As Integer, ByVal uit As Integer, ByVal isTxt As Integer) As String
    Dim t As String
    Dim links As Integer

    t = Kort(s, breedte)
    If uit = U_AUTO Then
        If isTxt Then uit = U_LINKS Else uit = U_RECHTS
    End If

    Select Case uit
    Case U_LINKS
        Uitlijn = Pad(t, breedte)
    Case U_RECHTS
        Uitlijn = PadL(t, breedte)
    Case Else
        links = (breedte - Len(t)) \ 2
        If links < 0 Then links = 0
        Uitlijn = Pad(Space(links) + t, breedte)
    End Select
End Function

'' Wat er in de cel te zien is: tekst zonder apostrof, getallen volgens de
'' opmaak van de kolom, formules als hun uitkomst of als foutwaarde.
Sub CelToon(ByVal b As Integer, ByVal k As Integer, ByVal r As Integer, ByVal breedte As Integer, ByRef uit1 As String, ByRef kleur As Integer, ByRef isTxt As Integer)
    Dim ci As Integer, d As Integer
    Dim s As String

    uit1  = ""
    kleur = C_GETAL
    isTxt = 0

    ci = CelNr(b, k, r)
    If ci = 0 Then Exit Sub

    d = blad(b).dec(k)

    Select Case blad(b).cel(ci).soort
    Case S_TEKST
        s = blad(b).cel(ci).tekst
        If Left(s, 1) = "'" Then s = Mid(s, 2)
        uit1  = s
        kleur = C_TEKST
        isTxt = -1
    Case S_GETAL
        If d < 0 Then
            uit1 = AlgGetal(blad(b).cel(ci).waarde, breedte)
        Else
            uit1 = VastGetal(blad(b).cel(ci).waarde, d)
        End If
        kleur = C_GETAL
    Case S_FORM
        If blad(b).cel(ci).fout <> 0 Then
            uit1  = FoutTekst(blad(b).cel(ci).fout)
            kleur = C_FOUT
            isTxt = 0
        Else
            If d < 0 Then
                uit1 = AlgGetal(blad(b).cel(ci).waarde, breedte)
            Else
                uit1 = VastGetal(blad(b).cel(ci).waarde, d)
            End If
            kleur = C_FORM
        End If
    End Select
End Sub

Sub TekenInvoerregel()
    Dim s As String, inhoud As String

    inhoud = CelTekst(curB, blad(curB).curK, blad(curB).curR)
    s = " " + blad(curB).naam + "!" + CelNaam(blad(curB).curK, blad(curB).curR) + ": " + inhoud
    PutStr 2, 1, Pad(s, scrW), C_INV_FG, C_INV_BG
End Sub

Sub TekenKoppen()
    Dim k As Integer, c As Integer, br As Integer, laatste As Integer
    Dim fg As Integer, bg As Integer
    Dim s As String

    PutStr 3, 1, Space(GUT - 1) + gV, C_KOP_FG, C_KOP_BG

    laatste = LaatsteKolom()
    c = GUT + 1
    For k = blad(curB).topK To laatste
        br = blad(curB).breed(k)
        s = KolNaam(k)
        s = Space((br - Len(s)) \ 2) + s
        If k = blad(curB).curK Then
            fg = C_KOPA_FG : bg = C_KOPA_BG
        Else
            fg = C_KOP_FG  : bg = C_KOP_BG
        End If
        PutStr 3, c, Pad(s, br), fg, bg
        c = c + br
    Next
    If c <= scrW Then PutStr 3, c, Space(scrW - c + 1), C_KOP_FG, C_KOP_BG
End Sub

Sub TekenRaster()
    Dim i As Integer, k As Integer, kk As Integer, r As Integer
    Dim c As Integer, br As Integer, ruimte As Integer, laatste As Integer
    Dim kleur As Integer, isTxt As Integer, fg As Integer, bg As Integer
    Dim s As String, veld As String

    laatste = LaatsteKolom()

    For i = 0 To rBot - rTop
        r = blad(curB).topR + i

        '' rijkop
        If r = blad(curB).curR Then
            fg = C_KOPA_FG : bg = C_KOPA_BG
        Else
            fg = C_KOP_FG  : bg = C_KOP_BG
        End If
        s = PadL(Trim(Str(r + 1)), GUT - 1)
        PutStr rTop + i, 1, s, fg, bg
        PutStr rTop + i, GUT, gV, C_RAND, C_BG

        '' de cellen zelf
        c = GUT + 1
        k = blad(curB).topK
        Do While k <= laatste
            br = blad(curB).breed(k)
            CelToon curB, k, r, br, veld, kleur, isTxt
            ruimte = br
            kk = k + 1

            '' Tekst die niet past mag doorlopen over lege buren rechts,
            '' zo blijft lange tekst leesbaar. De cursorcel blijft altijd vrij.
            If isTxt Then
                If Len(veld) > ruimte Then
                    Do While kk <= laatste
                        If CelNr(curB, kk, r) <> 0 Then Exit Do
                        If kk = blad(curB).curK And r = blad(curB).curR Then Exit Do
                        ruimte = ruimte + blad(curB).breed(kk)
                        kk = kk + 1
                        If ruimte >= Len(veld) Then Exit Do
                    Loop
                End If
            End If

            s = Uitlijn(veld, ruimte, blad(curB).uit(k), isTxt)
            PutStr rTop + i, c, s, kleur, C_BG
            c = c + ruimte
            k = kk
        Loop

        If c <= scrW Then PutStr rTop + i, c, Space(scrW - c + 1), C_RAND, C_BG
    Next

    '' de cursorcel er nog eens overheen, met de selectiekleur
    r = blad(curB).curR
    If r >= blad(curB).topR And r <= blad(curB).topR + (rBot - rTop) Then
        If blad(curB).curK >= blad(curB).topK And blad(curB).curK <= laatste Then
            c = GUT + 1
            For k = blad(curB).topK To blad(curB).curK - 1
                c = c + blad(curB).breed(k)
            Next
            k = blad(curB).curK
            br = blad(curB).breed(k)
            CelToon curB, k, r, br, veld, kleur, isTxt
            s = Uitlijn(veld, br, blad(curB).uit(k), isTxt)
            PutStr rTop + (r - blad(curB).topR), c, s, C_SEL_FG, C_SEL_BG
        End If
    End If
End Sub

Sub TekenTabs()
    Dim b As Integer, c As Integer, w As Integer
    Dim fg As Integer, bg As Integer
    Dim s As String

    '' zorg dat het huidige tabblad zichtbaar is
    If tabTop < 1 Then tabTop = 1
    If tabTop > curB Then tabTop = curB
    Do
        w = 0
        For b = tabTop To curB
            w = w + Len(blad(b).naam) + 3
        Next
        If w <= scrW - 1 Then Exit Do
        If tabTop >= curB Then Exit Do
        tabTop = tabTop + 1
    Loop

    PutStr scrH - 2, 1, Space(scrW), C_TAB_FG, C_BG

    c = 2
    For b = tabTop To nBladen
        s = " " + blad(b).naam + " "
        If c + Len(s) > scrW Then Exit For
        If b = curB Then
            fg = C_BALK_FG : bg = C_BALK_BG
        Else
            fg = C_TAB_FG  : bg = C_BG
        End If
        PutStr scrH - 2, c, s, fg, bg
        c = c + Len(s) + 1
    Next
End Sub

Sub TekenStatus()
    Dim ci As Integer
    Dim s As String, soort As String

    If Len(melding) > 0 Then
        s = " " + melding
        melding = ""
    Else
        ci = CelNr(curB, blad(curB).curK, blad(curB).curR)
        If ci = 0 Then
            soort = Vt("leeg")
        Else
            Select Case blad(curB).cel(ci).soort
            Case S_GETAL : soort = Tn("getal %1", Trim(Str(blad(curB).cel(ci).waarde)), "", "")
            Case S_TEKST : soort = Vt("tekst")
            Case S_FORM
                If blad(curB).cel(ci).fout <> 0 Then
                    soort = Tn("formule %1", FoutTekst(blad(curB).cel(ci).fout), "", "")
                Else
                    soort = Tn("formule = %1", Trim(Str(blad(curB).cel(ci).waarde)), "", "")
                End If
            Case Else    : soort = Vt("leeg")
            End Select
        End If
        s = " "
        If gewijzigd Then s = s + "* "
        s = s + CelNaam(blad(curB).curK, blad(curB).curR) + "  " + gPunt + "  " + soort + _
            "  " + gPunt + "  " + Tn("%1 cellen gevuld", Trim(Str(blad(curB).aantal)), "", "") + _
            "  " + gPunt + "  " + Tn("tabblad %1/%2", Trim(Str(curB)), Trim(Str(nBladen)), "")
    End If
    PutStr scrH - 1, 1, Pad(s, scrW), 15, C_BG
End Sub

Sub TekenHelp()
    Dim s As String

    s = Vt(" F1 Hulp  F2 Bewerk  F3 Breedte  F5 Ganaar  F6/F7 Tabblad  F9 Zoek  ^K Kopieer  ^V Plak ^Q Stop")
    PutStr scrH, 1, Pad(s, scrW), C_BALK_FG, C_BALK_BG
End Sub

Sub Redraw()
    ZorgZichtbaar
    ScreenLock
    TekenMenuBalk 0
    TekenInvoerregel
    TekenKoppen
    TekenRaster
    TekenTabs
    TekenStatus
    TekenHelp
    ScreenUnlock
    Locate , , 0
End Sub

'' ==========================================================================
''  Hoofdprogramma
'' ==========================================================================

Dim i As Integer, t As Integer, ext As Integer, p As Integer
Dim asciiModus As Integer, schaalGezet As Integer, rijen As Integer
Dim arg As String, s As String

'asciiModus  = 0
fontSchaal  = 1
venMaxB     = 0
venMaxH     = 0
schaalGezet = 0
stoppen     = 0
klemN       = 0
klemK1      = 0
klemK2      = -1
klemR1      = 0
klemR2      = -1
gen         = 0
tabTop      = 1
bestand     = ExePath + SEP + "bladen" + SEP + "werkblad.bld"

For i = 1 To 8
    arg = Command(i)
    If Len(arg) = 0 Then Exit For
    If LCase(arg) = "-a" Then
        asciiModus = -1
    ElseIf LCase(arg) = "-c" Then
        asciiModus = 0
    ElseIf LCase(Left(arg, 2)) = "-z" Then
        fontSchaal  = Val(Mid(arg, 3))
        If fontSchaal < 1 Then fontSchaal = 1
        If schaalGezet = 0 Then LaadInstellingen
		

		If SchermInit() = 0 Then
			schaalGezet = -1
        End If
        
        
    ElseIf LCase(Left(arg, 2)) = "-w" Then
        '' -wBREEDTExHOOGTE, bijvoorbeeld -w640x480
        s = LCase(Mid(arg, 3))
        p = InStr(s, "x")
        If p > 0 Then
            venMaxB = Val(Left(s, p - 1))
            venMaxH = Val(Mid(s, p + 1))
        End If
    ElseIf Left(arg, 1) <> "-" Then
        bestand = arg
    End If
Next

ZetGlyphs asciiModus

'' de map waarin het bestand staat; daar komt ook Rekenblad.cfg terecht
dataMap = ""
For i = Len(bestand) To 1 Step -1
    s = Mid(bestand, i, 1)
    If s = SEP Or s = "\" Then
        dataMap = Left(bestand, i - 1)
        Exit For
    End If
Next
If Len(dataMap) = 0 Then dataMap = ExePath
MkDir dataMap

If schaalGezet = 0 Then LaadInstellingen

InitMenuBalk

If SchermInit() = 0 Then
    Print APP_NAAM + ": er is te weinig ruimte (minimaal " + _
          Trim(Str(MIN_KOL)) + " x " + Trim(Str(MIN_RIJ)) + " tekens)."
    Print "Kies een kleinere schaal met -z1, of gebruik een groter beeldscherm."
    End 1
End If

LaadBestand
If nBladen = 0 Then
    MaakDemo
    melding = Tn("Nieuw bestand %1 %2 F1 geeft hulp", bestand, gPunt, "")
Else
    melding = Tn("Geladen: %1 %2 F1 geeft hulp", bestand, gPunt, "")
End If

If curB < 1 Or curB > nBladen Then curB = 1
gewijzigd = 0
Herbereken
Redraw

Do
    ext = 0
    t = WachtToets(ext)
    rijen = rBot - rTop + 1

    If ext Then
        '' ---------------- uitgebreide toetsen ----------------
        Select Case t
        Case 59                                     '' F1
            ToonHelp
        Case 60                                     '' F2
            BewerkCel
        Case 61                                     '' F3
            KolomBreedte
        Case 62                                     '' F4
            KolomOpmaak
        Case 63                                     '' F5
            GaNaar
        Case 64                                     '' F6
            WisselBlad 1
        Case 65                                     '' F7
            WisselBlad -1
        Case 66                                     '' F8
            Herbereken
            melding = Vt("Alles opnieuw uitgerekend.")
        Case 67                                     '' F9
            Zoek
        Case 68                                     '' F10
            MenuBalk
        Case 107                                    '' sluitknop van het venster
            stoppen = -1
        Case 87, 133                                '' F11: kleiner
            '' gfxlib levert de scancode (87/88); 133/134 zijn de DOS-codes,
            '' die op sommige platformen langskomen. Allebei maar aannemen.
            SchaalWijzig -1
        Case 88, 134                                '' F12: groter
            SchaalWijzig 1
        Case 72                                     '' pijl omhoog
            If blad(curB).curR > 0 Then blad(curB).curR = blad(curB).curR - 1
        Case 80                                     '' pijl omlaag
            If blad(curB).curR < MAX_RIJ - 1 Then blad(curB).curR = blad(curB).curR + 1
        Case 75                                     '' pijl links
            If blad(curB).curK > 0 Then blad(curB).curK = blad(curB).curK - 1
        Case 77                                     '' pijl rechts
            If blad(curB).curK < MAX_KOL - 1 Then blad(curB).curK = blad(curB).curK + 1
        Case 73                                     '' PgUp
            blad(curB).curR = blad(curB).curR - rijen
            If blad(curB).curR < 0 Then blad(curB).curR = 0
        Case 81                                     '' PgDn
            blad(curB).curR = blad(curB).curR + rijen
            If blad(curB).curR > MAX_RIJ - 1 Then blad(curB).curR = MAX_RIJ - 1
        Case 71                                     '' Home: naar kolom A
            blad(curB).curK = 0
        Case 79                                     '' End: laatste gevulde kolom
            p = 0
            For i = 1 To blad(curB).aantal
                If blad(curB).cel(i).r = blad(curB).curR Then
                    If blad(curB).cel(i).k > p Then p = blad(curB).cel(i).k
                End If
            Next
            blad(curB).curK = p
        Case 82                                     '' Insert
            BewerkCel
        Case 83                                     '' Delete
            WisHuidige
        End Select
    Else
        '' ---------------- gewone toetsen ----------------
        Select Case t
        Case 13                                     '' Enter
            BewerkCel
        Case 9                                      '' Tab: een cel naar rechts
            If blad(curB).curK < MAX_KOL - 1 Then blad(curB).curK = blad(curB).curK + 1
        Case 8                                      '' Backspace
            WisHuidige
        Case 27                                     '' ESC
            MenuBalk
        Case 17                                     '' Ctrl+Q
            stoppen = -1
        Case 19                                     '' Ctrl+S
            SlaOp bestand
        Case 11                                     '' Ctrl+K
            Kopieer
        Case 22                                     '' Ctrl+V
            Plak
        Case 23                                     '' Ctrl+W
            BlokWissen
        Case 7                                      '' Ctrl+G
            GaNaar
        Case 6                                      '' Ctrl+F
            Zoek
        Case 14                                     '' Ctrl+N
            NieuwBlad
        Case 16                                     '' Ctrl+P
            DoPrint
        Case 20                                     '' Ctrl+T
            PrinterTaalInstellingen
        Case 26                                     '' Ctrl+Z
            OverRekenblad
        Case Else
            '' alles wat je gewoon kunt typen begint meteen de invoer
            If t >= 32 And t <= 126 Then
                s = Chr(t)
                Invoer s
            End If
        End Select
    End If

    If stoppen Then Exit Do
    Redraw
Loop

If gewijzigd Then
    If Bevestig(Tn("Wijzigingen opslaan in %1?", bestand, "", "")) Then SlaOp bestand
End If

Screen 0
Color 7, 0
Cls
Locate , , 1
Print APP_NAAM + " " + APP_VER + " - " + bestand
Print Tn("%1 tabblad(en). Tot ziens!", Trim(Str(nBladen)), "", "")
End
