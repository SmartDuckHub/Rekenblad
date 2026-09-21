' ==================================================================
'  Rekenblad - module: rekenblad_menu.bi
'  Menubalk zoals in Woord: de balk met categorieën staat altijd
'  bovenaan (rij 1), F10 of Esc "opent" 'm (dropdown + markering),
'  pijltjes-links/rechts wisselen van categorie, pijltjes-omhoog/omlaag
'  van item, Enter kiest, Esc/F10 sluit weer zonder iets te doen.
'  Vervangt het oude, Lotus-stijl "/"-opdrachtenmenu (een platte,
'  genummerde lijst).
'  Via #include in rekenblad.bas in te voegen (na rekenblad_taal.bi en
'  rekenblad_print.bi, voor de Dim Shared-regels) -- geen zelfstandig
'  te compileren bestand.
' ==================================================================

Const MN_MAX_CAT  = 8
Const MN_MAX_ITEM = 8

'' Zelfde kleuren als Woord's menubalk (thMnuFg/thMnuBg en
'' thMSelFg/thMSelBg in SetTheme) -- die zijn daar in alle drie de
'' thema's gelijk, dus hier gewoon vast:
'' normale balk/uitklaptekst: zwart op lichtgrijs (== C_DLG_FG/C_DLG_BG)
'' geopende categorie/gekozen item: lichtgrijs op zwart (spiegelbeeld)
Const C_MNU_SEL_FG = 7   : Const C_MNU_SEL_BG = 0
Const C_MNU_HOT_FG = 4   '' kleur van de eerste letter (sneltoets-hint)
Const C_MNU_SCH_FG = 8   : Const C_MNU_SCH_BG = 0   '' schaduw onder het uitklapmenu

Dim Shared mnAantal              As Integer
Dim Shared mnTitel(1 To MN_MAX_CAT)  As String
Dim Shared mnItems(1 To MN_MAX_CAT)  As Integer
Dim Shared mnKol(1 To MN_MAX_CAT)    As Integer
Dim Shared mnBreed(1 To MN_MAX_CAT)  As Integer
Dim Shared mnTekst(1 To MN_MAX_CAT, 1 To MN_MAX_ITEM) As String
Dim Shared mnToets(1 To MN_MAX_CAT, 1 To MN_MAX_ITEM) As String
Dim Shared mnActie(1 To MN_MAX_CAT, 1 To MN_MAX_ITEM) As Integer

' Bestandenlijst voor Ctrl+O, zelfde opzet als Woord's PickFile maar
' hergebruikt gewoon de bestaande Kies()-lijstdialoog: bladert map met
' patroon (";"-gescheiden, bv. "*.bld;*.txt") af, alfabetisch gesorteerd.
' Geeft de kale bestandsnaam terug, of Chr(27) bij Esc of niets gevonden.
Function KiesBestand(ByRef map As String, ByRef patroon As String, ByRef titel As String) As String
    Dim bestanden(1 To 500) As String
    Dim n As Integer, i As Integer, j As Integer
    Dim patronen(1 To 20) As String, aantalPatronen As Integer
    Dim pStart As Integer, pPos As Integer, pat As String
    Dim bestandNaam As String, dubbel As Integer, tmp As String
    Dim keuze As Integer

    aantalPatronen = 0
    pStart = 1
    Do
        pPos = InStr(pStart, patroon + ";", ";")
        pat = Trim(Mid(patroon + ";", pStart, pPos - pStart))
        If Len(pat) > 0 And aantalPatronen < 20 Then
            aantalPatronen = aantalPatronen + 1
            patronen(aantalPatronen) = pat
        End If
        pStart = pPos + 1
    Loop Until pStart > Len(patroon) + 1

    n = 0
    For i = 1 To aantalPatronen
        bestandNaam = Dir(map + patronen(i))
        Do While Len(bestandNaam) > 0 And n < 500
            dubbel = 0
            For j = 1 To n
                If LCase(bestanden(j)) = LCase(bestandNaam) Then dubbel = -1
            Next j
            If dubbel = 0 Then
                n = n + 1
                bestanden(n) = bestandNaam
            End If
            bestandNaam = Dir()
        Loop
    Next i

    '' alfabetisch, hoofdletterongevoelig (eenvoudige bubbelsort)
    For i = 1 To n - 1
        For j = 1 To n - i
            If LCase(bestanden(j)) > LCase(bestanden(j + 1)) Then
                tmp = bestanden(j) : bestanden(j) = bestanden(j + 1) : bestanden(j + 1) = tmp
            End If
        Next j
    Next i

    If n = 0 Then
        Melden Vt("Geen bestanden gevonden.")
        KiesBestand = Chr(27)
        Exit Function
    End If

    keuze = Kies(titel, bestanden(), n, 1)
    If keuze = 0 Then
        KiesBestand = Chr(27)
    Else
        KiesBestand = bestanden(keuze)
    End If
End Function

Sub BestandOpenen()
    Dim a As String, ok As Integer

    If gewijzigd Then
        If Bevestig(Vt("Niet-opgeslagen wijzigingen. Doorgaan?")) = 0 Then Exit Sub
    End If

    a = KiesBestand(dataMap + SEP, "*.bld;*.txt", Vt("Bestand kiezen"))
    If a = Chr(27) Then
        '' niets gevonden of gekozen: laat handmatig typen (ander pad of
        '' andere extensie), of gewoon annuleren met Esc
        a = VraagTekst(Vt("Bestand openen"), Vt("Bestandsnaam:"), bestand, ok)
        If ok = 0 Then Exit Sub
    End If
    a = Trim(a)
    If Len(a) = 0 Then Exit Sub
    If InStr(a, SEP) = 0 And InStr(a, "\") = 0 Then a = dataMap + SEP + a

    bestand = a
    LaadBestand
    If nBladen = 0 Then MaakDemo
    If curB < 1 Or curB > nBladen Then curB = 1
    gewijzigd = 0
    Herbereken
    melding = Tn("Geladen: %1", bestand, "", "")
End Sub

' "Over Rekenblad", zelfde inhoud en opzet als Woord's ShowAbout:
' copyright en licentie, af te sluiten met een willekeurige toets.
Sub OverRekenblad()
    Dim regels(1 To 6) As String
    Dim n As Integer, i As Integer, ext As Integer
    Dim r As Integer, c As Integer, w As Integer, h As Integer
    Dim titel As String, s As String

    n = 0
    n = n + 1 : regels(n) = Vt("COPYRIGHT")
    n = n + 1 : regels(n) = Vt("Copyright 2026 door Marcel") + " " + Chr(34) + "SmartDuck" + Chr(34) + " Beekman"
    n = n + 1 : regels(n) = ""
    n = n + 1 : regels(n) = Vt("LICENTIE")
    n = n + 1 : regels(n) = Vt("BSD 3-Clause")
    n = n + 1 : regels(n) = Vt("Deze is bijgesloten bij de broncode als separaat bestand.")

    w = 0
    For i = 1 To n
        If Len(regels(i)) + 6 > w Then w = Len(regels(i)) + 6
    Next i
    If w < 40 Then w = 40
    If w > scrW - 4 Then w = scrW - 4

    h = n + 4
    If h > scrH - 2 Then h = scrH - 2
    r = (scrH - h) \ 2 + 1
    c = (scrW - w) \ 2 + 1

    titel = APP_NAAM + " " + APP_VER
    Venster r, c, h, w, titel
    For i = 1 To n
        If i > h - 3 Then Exit For
        PutStr r + i, c + 2, Kort(regels(i), w - 4), C_DLG_FG, C_DLG_BG
    Next i
    s = Vt("druk op een toets om terug te gaan")
    PutStr r + h - 2, c + 2, Kort(s, w - 4), C_DLG_FG, C_DLG_BG

    ext = 0
    WachtToets ext
    Redraw
End Sub

Sub InitMenuBalk()
    Dim m As Integer, i As Integer, w As Integer, c As Integer

    mnAantal = 6

    mnTitel(1) = Vt("Bestand")
    mnTitel(2) = Vt("Bewerken")
    mnTitel(3) = Vt("Blad")
    mnTitel(4) = Vt("Opmaak")
    mnTitel(5) = Vt("Extra")
    mnTitel(6) = Vt("Help")

    mnItems(1) = 7
    mnTekst(1, 1) = Vt("Openen...")               : mnToets(1, 1) = "^O"  : mnActie(1, 1) = 16
    mnTekst(1, 2) = Vt("Opslaan")                 : mnToets(1, 2) = "^S"  : mnActie(1, 2) = 10
    mnTekst(1, 3) = Vt("Opslaan als...")          : mnToets(1, 3) = ""    : mnActie(1, 3) = 11
    mnTekst(1, 4) = Vt("Exporteren naar CSV...")  : mnToets(1, 4) = ""    : mnActie(1, 4) = 12
    mnTekst(1, 5) = Vt("Afdrukken...")            : mnToets(1, 5) = "^P"  : mnActie(1, 5) = 13
    mnTekst(1, 6) = Vt("Instellingen...")         : mnToets(1, 6) = "^T"  : mnActie(1, 6) = 14
    mnTekst(1, 7) = Vt("Stoppen")                 : mnToets(1, 7) = "^Q"  : mnActie(1, 7) = 15

    mnItems(2) = 5
    mnTekst(2, 1) = Vt("Kopieren")                : mnToets(2, 1) = "^K"  : mnActie(2, 1) = 20
    mnTekst(2, 2) = Vt("Plakken")                 : mnToets(2, 2) = "^V"  : mnActie(2, 2) = 21
    mnTekst(2, 3) = Vt("Bereik leegmaken")        : mnToets(2, 3) = "^W"  : mnActie(2, 3) = 22
    mnTekst(2, 4) = Vt("Zoeken")                  : mnToets(2, 4) = "F9"  : mnActie(2, 4) = 23
    mnTekst(2, 5) = Vt("Ga naar cel")             : mnToets(2, 5) = "F5"  : mnActie(2, 5) = 24

    mnItems(3) = 5
    mnTekst(3, 1) = Vt("Nieuw tabblad")           : mnToets(3, 1) = "^N"  : mnActie(3, 1) = 30
    mnTekst(3, 2) = Vt("Tabblad hernoemen")       : mnToets(3, 2) = ""    : mnActie(3, 2) = 31
    mnTekst(3, 3) = Vt("Tabblad verwijderen")     : mnToets(3, 3) = ""    : mnActie(3, 3) = 32
    mnTekst(3, 4) = Vt("Volgend tabblad")         : mnToets(3, 4) = "F6"  : mnActie(3, 4) = 33
    mnTekst(3, 5) = Vt("Vorig tabblad")           : mnToets(3, 5) = "F7"  : mnActie(3, 5) = 34

    mnItems(4) = 6
    mnTekst(4, 1) = Vt("Kolombreedte")            : mnToets(4, 1) = "F3"  : mnActie(4, 1) = 40
    mnTekst(4, 2) = Vt("Kolomopmaak")             : mnToets(4, 2) = "F4"  : mnActie(4, 2) = 41
    mnTekst(4, 3) = Vt("Rij invoegen")            : mnToets(4, 3) = ""    : mnActie(4, 3) = 42
    mnTekst(4, 4) = Vt("Rij verwijderen")         : mnToets(4, 4) = ""    : mnActie(4, 4) = 43
    mnTekst(4, 5) = Vt("Kolom invoegen")          : mnToets(4, 5) = ""    : mnActie(4, 5) = 44
    mnTekst(4, 6) = Vt("Kolom verwijderen")       : mnToets(4, 6) = ""    : mnActie(4, 6) = 45

    mnItems(5) = 4
    mnTekst(5, 1) = Vt("Alles herberekenen")      : mnToets(5, 1) = "F8"  : mnActie(5, 1) = 50
    mnTekst(5, 2) = Vt("Tekens groter")           : mnToets(5, 2) = "F12" : mnActie(5, 2) = 51
    mnTekst(5, 3) = Vt("Tekens kleiner")          : mnToets(5, 3) = "F11" : mnActie(5, 3) = 52
    mnTekst(5, 4) = Vt("Toetsproef...")           : mnToets(5, 4) = ""    : mnActie(5, 4) = 53

    mnItems(6) = 2
    mnTekst(6, 1) = Vt("Hulp")                    : mnToets(6, 1) = "F1"  : mnActie(6, 1) = 60
    mnTekst(6, 2) = Vt("Over Rekenblad")          : mnToets(6, 2) = "^Z"  : mnActie(6, 2) = 61

    For m = 1 To mnAantal
        w = 0
        For i = 1 To mnItems(m)
            If Len(mnTekst(m, i)) + Len(mnToets(m, i)) > w Then w = Len(mnTekst(m, i)) + Len(mnToets(m, i))
        Next i
        mnBreed(m) = w + 6
    Next m

    c = 2
    For m = 1 To mnAantal
        mnKol(m) = c
        c = c + Len(mnTitel(m)) + 3
    Next m
End Sub

Sub TekenMenuBalk(ByVal openM As Integer)
    Dim m As Integer, s As String

    PutStr 1, 1, Pad("", scrW), C_DLG_FG, C_DLG_BG
    For m = 1 To mnAantal
        s = " " + mnTitel(m) + " "
        If mnKol(m) + Len(s) > scrW Then Exit For
        If m = openM Then
            PutStr 1, mnKol(m), s, C_MNU_SEL_FG, C_MNU_SEL_BG
        Else
            PutStr 1, mnKol(m), s, C_DLG_FG, C_DLG_BG
            '' eerste letter in een afwijkende kleur, als visuele hint --
            '' precies zoals Woord dat met thHotFg doet
            PutStr 1, mnKol(m) + 1, Left(mnTitel(m), 1), C_MNU_HOT_FG, C_DLG_BG
        End If
    Next m
End Sub

Sub TekenMenuDropdown(ByVal m As Integer, ByVal sel As Integer)
    Dim x As Integer, y As Integer, w As Integer, h As Integer, wt As Integer
    Dim i As Integer, s As String, fg As Integer, bg As Integer
    Dim leeg As String

    w = mnBreed(m)
    x = mnKol(m)
    If x + w > scrW Then x = scrW - w + 1
    If x < 1 Then x = 1
    y = 2
    h = mnItems(m) + 2
    If y + h - 1 > scrH Then h = scrH - y + 1
    wt = w - 2

    leeg = ""
    Venster y, x, h, w, leeg

    For i = 1 To mnItems(m)
        If i > h - 2 Then Exit For
        s = " " + mnTekst(m, i)
        Do While Len(s) < wt - Len(mnToets(m, i)) - 1
            s = s + " "
        Loop
        s = s + mnToets(m, i) + " "
        s = Kort(s, wt)
        If i = sel Then
            fg = C_MNU_SEL_FG : bg = C_MNU_SEL_BG
        Else
            fg = C_DLG_FG : bg = C_DLG_BG
        End If
        PutStr y + i, x + 1, s, fg, bg
    Next i

    '' schaduw rechts en onder het uitklapmenu, net als in Woord: twee
    '' kolommen breed, één regel lager dan de bovenrand beginnend (dat
    '' geeft het "losse" effect), plus een enkele regel eronder die twee
    '' kolommen naar rechts is verschoven.
    For i = 1 To h - 1
        If x + w + 1 <= scrW - 1 Then PutStr y + i, x + w, "  ", C_MNU_SCH_FG, C_MNU_SCH_BG
    Next i
    If y + h <= scrH And x + w + 1 <= scrW - 1 Then
        PutStr y + h, x + 2, Space(w), C_MNU_SCH_FG, C_MNU_SCH_BG
    End If
End Sub

' Voert de gekozen menuactie uit. De codes lopen per categorie in
' tientallen: 10=Bestand, 20=Bewerken, 30=Blad, 40=Opmaak, 50=Extra,
' 60=Help -- zodat je meteen ziet bij welke categorie een actie hoort.
Sub MenuActie(ByVal act As Integer)
    Select Case act
    Case 10 : SlaOp bestand
    Case 11 : SlaOpAls
    Case 12 : ExportCsv
    Case 13 : DoPrint
    Case 14 : PrinterTaalInstellingen
    Case 15
        If Bevestig("Rekenblad afsluiten?") Then stoppen = -1
    Case 16 : BestandOpenen
    Case 20 : Kopieer
    Case 21 : Plak
    Case 22 : BlokWissen
    Case 23 : Zoek
    Case 24 : GaNaar
    Case 30 : NieuwBlad
    Case 31 : HernoemBlad
    Case 32 : VerwijderBlad
    Case 33 : WisselBlad 1
    Case 34 : WisselBlad -1
    Case 40 : KolomBreedte
    Case 41 : KolomOpmaak
    Case 42 : RijInvoegen
    Case 43 : RijVerwijderen
    Case 44 : KolomInvoegen
    Case 45 : KolomVerwijderen
    Case 50
        Herbereken
        melding = "Alles opnieuw uitgerekend."
    Case 51 : SchaalWijzig 1
    Case 52 : SchaalWijzig -1
    Case 53 : ToetsProef
    Case 60 : ToonHelp
    Case 61 : OverRekenblad
    End Select
End Sub

' De menubalk zelf: F10 of Esc in de hoofdlus roept dit aan.
Sub MenuBalk()
    Dim m As Integer, sel As Integer, t As Integer, ext As Integer, act As Integer

    m   = 1
    sel = 1
    act = 0

    Do
        Redraw
        TekenMenuBalk m
        TekenMenuDropdown m, sel

        ext = 0
        t = WachtToets(ext)
        If ext Then
            Select Case t
            Case 75                                 '' pijl links: vorige categorie
                m = m - 1
                If m < 1 Then m = mnAantal
                sel = 1
            Case 77                                 '' pijl rechts: volgende categorie
                m = m + 1
                If m > mnAantal Then m = 1
                sel = 1
            Case 72                                 '' pijl omhoog
                sel = sel - 1
                If sel < 1 Then sel = mnItems(m)
            Case 80                                 '' pijl omlaag
                sel = sel + 1
                If sel > mnItems(m) Then sel = 1
            Case 68                                 '' F10: menu weer dicht
                Exit Do
            Case 107                                '' sluitknop van het venster
                stoppen = -1
                Exit Do
            End Select
        Else
            Select Case t
            Case 13                                 '' Enter: item uitvoeren
                act = mnActie(m, sel)
                Exit Do
            Case 27                                 '' Esc: menu weer dicht
                Exit Do
            End Select
        End If
    Loop

    Redraw
    If act > 0 Then MenuActie act
End Sub
