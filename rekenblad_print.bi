' ==================================================================
'  Rekenblad - module: rekenblad_print.bi
'  Afdrukken van het huidige tabblad, in dezelfde opzet als de
'  PrintPS/DoPrint van Woord (woord_bmp.bi): PostScript naar lpr, of
'  bij printraw=1 platte tekst rechtstreeks naar een matrixprinter.
'  Via #include in rekenblad.bas in te voegen (na rekenblad_taal.bi,
'  voor de Dim Shared-regels) -- geen zelfstandig te compileren
'  bestand.
'
'  Drukt het gevulde bereik van het HUIDIGE tabblad af, in dezelfde
'  kolombreedtes/uitlijning als op het scherm (CelToon + Uitlijn).
'  Bredere werkbladen worden in verticale "banden" van kolommen
'  verdeeld: eerst alle pagina's van kolommen A..x, dan de volgende
'  band, enzovoort -- net als bij een brede Lotus-afdruk op
'  ketting-papier.
' ==================================================================

Dim Shared optPrintRaw  As Integer
Dim Shared printPrinter As String
Dim Shared psFile       As Integer

Const PR_PGW  = 595.0     ' A4 breed, in punten
Const PR_PGH  = 842.0     ' A4 hoog, in punten
Const PR_MARG = 42.0      ' marge, ca. 1,5 cm (rekenbladen zijn vaak breed)
Const PR_FSZ  = 8.0       ' lettergrootte in punten (Courier)

Function SubstAll(ByRef bron As String, ByRef patroon As String, ByRef vervang As String) As String
    Dim res As String, p As Integer, start As Integer
    start = 1
    res   = ""
    Do
        p = InStr(start, bron, patroon)
        If p = 0 Then
            res = res + Mid(bron, start)
            Exit Do
        End If
        res   = res + Mid(bron, start, p - start) + vervang
        start = p + Len(patroon)
    Loop
    SubstAll = res
End Function

Function FmtD(ByRef v As Double) As String
    Dim iPart As Integer, fPart As Integer, t As Double
    t = v
    If t < 0.0 Then t = 0.0
    iPart = Int(t)
    fPart = Int((t - iPart) * 100.0 + 0.5)
    If fPart >= 100 Then
        iPart = iPart + 1
        fPart = fPart - 100
    End If
    FmtD = Trim(Str(iPart)) + "." + Right("0" + Trim(Str(fPart)), 2)
End Function

' let op: FreeBASIC kent geen escapes in gewone string-literals,
' dus "\" is precies een backslash en "\\" precies twee
Function PsEsc(ByRef sTxt As String) As String
    Dim t As String
    t = SubstAll(sTxt, "\", "\\")
    t = SubstAll(t, "(", "\(")
    t = SubstAll(t, ")", "\)")
    PsEsc = t
End Function

Function BaseNaam(ByRef padBestand As String) As String
    Dim naam As String, i As Integer
    naam = padBestand
    i = InStr(naam, ".")
    Do While InStr(i + 1, naam, ".") > 0
        i = InStr(i + 1, naam, ".")
    Loop
    If i > 0 Then naam = Left(naam, i - 1)
    BaseNaam = naam
End Function

' Verdeelt de kolommen 0..maxK in banden die elk op charsPerLine passen.
' bandStart()/bandEind() moeten minstens MAX_KOL/2 + 1 elementen groot zijn.
Sub BepaalKolomBanden(ByVal maxK As Integer, ByVal charsPerLine As Integer, _
                       bandStart() As Integer, bandEind() As Integer, ByRef nBanden As Integer)
    Dim k As Integer, breedteSom As Integer

    nBanden       = 0
    breedteSom    = GUT
    bandStart(0)  = 0
    For k = 0 To maxK
        If breedteSom + blad(curB).breed(k) + 1 > charsPerLine And breedteSom > GUT Then
            bandEind(nBanden) = k - 1
            nBanden = nBanden + 1
            bandStart(nBanden) = k
            breedteSom = GUT
        End If
        breedteSom = breedteSom + blad(curB).breed(k) + 1
    Next k
    bandEind(nBanden) = maxK
    nBanden = nBanden + 1
End Sub

' Bepaalt maxK/maxR (het gevulde bereik) van het huidige tabblad, net als
' ExportCsv dat doet. Geeft 0 terug (en een melding) als het blad leeg is.
Function BepaalBereik(ByRef maxK As Integer, ByRef maxR As Integer) As Integer
    Dim i As Integer
    maxK = -1 : maxR = -1
    For i = 1 To blad(curB).aantal
        If blad(curB).cel(i).k > maxK Then maxK = blad(curB).cel(i).k
        If blad(curB).cel(i).r > maxR Then maxR = blad(curB).cel(i).r
    Next
    If maxK < 0 Then
        Melden Vt("Dit tabblad is leeg.")
        BepaalBereik = 0
    Else
        BepaalBereik = -1
    End If
End Function

' Bouwt één gegevensregel op, van kolom kStart tot en met kEind. Tekst die
' niet in zijn eigen kolom past loopt door over lege buren rechts, precies
' zoals TekenRaster dat op het scherm doet. kOverMax is de verste kolom
' waar dat overlopen nog in mag komen -- die ligt vaak verder dan kEind,
' want een band stopt bij de laatst gevulde kolom, niet bij de rand van de
' pagina. Zonder dat onderscheid zou tekst in de laatste gevulde kolom nooit
' verder mogen lopen, ook al is er op papier nog volop ruimte.
Function MaakDataRegel(ByVal r As Integer, ByVal kStart As Integer, ByVal kEind As Integer, ByVal kOverMax As Integer) As String
    Dim k As Integer, kk As Integer, br As Integer, ruimte As Integer
    Dim kleur As Integer, isTxt As Integer
    Dim regel As String, veld As String

    regel = PadL(Trim(Str(r + 1)), GUT - 1) + " "

    k = kStart
    Do While k <= kEind
        br = blad(curB).breed(k)
        CelToon curB, k, r, br, veld, kleur, isTxt
        ruimte = br
        kk = k + 1

        If isTxt Then
            If Len(veld) > ruimte Then
                Do While kk <= kOverMax
                    If CelNr(curB, kk, r) <> 0 Then Exit Do
                    '' de spatie tussen twee kolommen telt mee als ruimte
                    ruimte = ruimte + 1 + blad(curB).breed(kk)
                    kk = kk + 1
                    If ruimte >= Len(veld) Then Exit Do
                Loop
            End If
        End If

        regel = regel + Uitlijn(veld, ruimte, blad(curB).uit(k), isTxt) + " "
        k = kk
    Loop

    MaakDataRegel = regel
End Function

' Hoever een band nog mag doorlopen voor overlopende tekst: vanaf het
' einde van de band (bandEind) net zo lang kolombreedtes optellen als er
' nog binnen charsPerLine past. Dat kan ruim voorbij maxK liggen.
Function BepaalOverloopGrens(ByVal bandEind As Integer, ByVal charsPerLine As Integer, ByVal breedteTotSom As Integer) As Integer
    Dim k As Integer, somBreedte As Integer

    somBreedte = breedteTotSom
    k = bandEind
    Do While k + 1 <= MAX_KOL - 1
        If somBreedte + 1 + blad(curB).breed(k + 1) > charsPerLine Then Exit Do
        k = k + 1
        somBreedte = somBreedte + 1 + blad(curB).breed(k)
    Loop
    BepaalOverloopGrens = k
End Function

Sub PrintPS(ByRef fn As String)
    Dim maxK As Integer, maxR As Integer
    Dim cw As Double, lineH As Double, usableW As Double, usableH As Double
    Dim charsPerLine As Integer, rowsPerPage As Integer
    Dim bandStart(0 To MAX_KOL \ 2) As Integer
    Dim bandEind(0 To MAX_KOL \ 2)  As Integer
    Dim nBanden As Integer, band As Integer
    Dim rijPaginas As Integer, rp As Integer, totPaginas As Integer, pgNum As Integer
    Dim rStart As Integer, rEind As Integer
    Dim k As Integer, r As Integer
    Dim yy As Double
    Dim regel As String, veld As String, s As String
    Dim kleur As Integer, isTxt As Integer
    Dim breedteSom As Integer, kOverMax As Integer

    If BepaalBereik(maxK, maxR) = 0 Then Exit Sub

    psFile = FreeFile
    If Open(fn For Output As #psFile) <> 0 Then
        Melden Tn("Kan niet schrijven naar: %1", fn, "", "")
        psFile = 0
        Exit Sub
    End If

    cw           = PR_FSZ * 0.6
    lineH        = PR_FSZ * 1.35
    usableW      = PR_PGW - 2.0 * PR_MARG
    usableH      = PR_PGH - 2.0 * PR_MARG - lineH * 2   ' kopregel + kolomkoppen
    charsPerLine = Int(usableW / cw)
    rowsPerPage  = Int(usableH / lineH) - 1
    If rowsPerPage < 1 Then rowsPerPage = 1

    BepaalKolomBanden maxK, charsPerLine, bandStart(), bandEind(), nBanden
    rijPaginas = (maxR \ rowsPerPage) + 1
    totPaginas = nBanden * rijPaginas

    Print #psFile, "%!PS-Adobe-3.0"
    Print #psFile, "%%Creator: " + APP_NAAM
    Print #psFile, "%%Title: " + bestand
    Print #psFile, "%%Pages: " + Trim(Str(totPaginas))
    Print #psFile, "%%BoundingBox: 0 0 595 842"
    Print #psFile, "%%EndComments"

    pgNum = 0
    For band = 0 To nBanden - 1
        For rp = 0 To rijPaginas - 1
            pgNum  = pgNum + 1
            rStart = rp * rowsPerPage
            rEind  = rStart + rowsPerPage - 1
            If rEind > maxR Then rEind = maxR

            Print #psFile, "%%Page: " + Trim(Str(pgNum)) + " " + Trim(Str(pgNum))
            yy = PR_PGH - PR_MARG

            s = blad(curB).naam + "   " + KolNaam(bandStart(band)) + "-" + KolNaam(bandEind(band)) + _
                "   " + Tn("Pagina %1", Trim(Str(pgNum)) + "/" + Trim(Str(totPaginas)), "", "")
            Print #psFile, "/Courier findfont " + FmtD(PR_FSZ * 0.9) + " scalefont setfont"
            Print #psFile, "0.35 0.35 0.35 setrgbcolor"
            Print #psFile, FmtD(PR_MARG) + " " + FmtD(yy) + " moveto (" + PsEsc(s) + ") show"
            yy = yy - lineH

            regel = Pad("", GUT)
            For k = bandStart(band) To bandEind(band)
                regel = regel + Uitlijn(KolNaam(k), blad(curB).breed(k), U_MIDDEN, -1) + " "
            Next k
            Print #psFile, "/Courier-Bold findfont " + FmtD(PR_FSZ) + " scalefont setfont"
            Print #psFile, "0 0 0 setrgbcolor"
            Print #psFile, FmtD(PR_MARG) + " " + FmtD(yy) + " moveto (" + PsEsc(regel) + ") show"
            yy = yy - lineH

            Print #psFile, "/Courier findfont " + FmtD(PR_FSZ) + " scalefont setfont"
            breedteSom = GUT
            For k = bandStart(band) To bandEind(band)
                breedteSom = breedteSom + blad(curB).breed(k) + 1
            Next k
            kOverMax = BepaalOverloopGrens(bandEind(band), charsPerLine, breedteSom)
            For r = rStart To rEind
                regel = MaakDataRegel(r, bandStart(band), bandEind(band), kOverMax)
                Print #psFile, FmtD(PR_MARG) + " " + FmtD(yy) + " moveto (" + PsEsc(regel) + ") show"
                yy = yy - lineH
            Next r

            Print #psFile, "showpage"
        Next rp
    Next band

    Print #psFile, "%%EOF"
    Close #psFile
    psFile = 0
    melding = Tn("PostScript geschreven: %1 (%2 pagina's)", fn, Trim(Str(totPaginas)), "")
End Sub

' Platte-tekstversie voor een matrixprinter (printraw=1): dezelfde
' banden/pagina's, maar met vormfeeds (Chr(12)) in plaats van PostScript.
Sub ExportRawText(ByRef fn As String)
    Dim maxK As Integer, maxR As Integer
    Dim charsPerLine As Integer, rowsPerPage As Integer
    Dim bandStart(0 To MAX_KOL \ 2) As Integer
    Dim bandEind(0 To MAX_KOL \ 2)  As Integer
    Dim nBanden As Integer, band As Integer
    Dim rijPaginas As Integer, rp As Integer, pgNum As Integer, totPaginas As Integer
    Dim rStart As Integer, rEind As Integer
    Dim k As Integer, r As Integer, fnum As Integer
    Dim regel As String, veld As String
    Dim kleur As Integer, isTxt As Integer
    Dim breedteSom As Integer, kOverMax As Integer

    If BepaalBereik(maxK, maxR) = 0 Then Exit Sub

    fnum = FreeFile
    If Open(fn For Output As #fnum) <> 0 Then
        Melden Tn("Kan niet schrijven naar: %1", fn, "", "")
        Exit Sub
    End If

    charsPerLine = 80          ' gangbare breedte van een matrixprinter
    rowsPerPage  = 60
    BepaalKolomBanden maxK, charsPerLine, bandStart(), bandEind(), nBanden
    rijPaginas = (maxR \ rowsPerPage) + 1
    totPaginas = nBanden * rijPaginas

    pgNum = 0
    For band = 0 To nBanden - 1
        For rp = 0 To rijPaginas - 1
            pgNum  = pgNum + 1
            rStart = rp * rowsPerPage
            rEind  = rStart + rowsPerPage - 1
            If rEind > maxR Then rEind = maxR

            Print #fnum, blad(curB).naam + "   " + KolNaam(bandStart(band)) + "-" + KolNaam(bandEind(band)) + _
                "   " + Tn("Pagina %1", Trim(Str(pgNum)) + "/" + Trim(Str(totPaginas)), "", "")

            regel = Pad("", GUT)
            For k = bandStart(band) To bandEind(band)
                regel = regel + Uitlijn(KolNaam(k), blad(curB).breed(k), U_MIDDEN, -1) + " "
            Next k
            Print #fnum, regel

            breedteSom = GUT
            For k = bandStart(band) To bandEind(band)
                breedteSom = breedteSom + blad(curB).breed(k) + 1
            Next k
            kOverMax = BepaalOverloopGrens(bandEind(band), charsPerLine, breedteSom)

            For r = rStart To rEind
                Print #fnum, MaakDataRegel(r, bandStart(band), bandEind(band), kOverMax)
            Next r

            Print #fnum, Chr(12);   ' vormfeed: volgende pagina
        Next rp
    Next band

    Close #fnum
    melding = Tn("Geexporteerd naar tekst: %1", fn, "", "")
End Sub

Sub DoPrint()
    Dim fn  As String
    Dim cmd As String
    Dim rc  As Integer
    Dim basis As String

    basis = BaseNaam(bestand)

    If optPrintRaw <> 0 Then
        fn = basis + ".txt"
        ExportRawText fn
    Else
        fn = basis + ".ps"
        PrintPS fn
    End If
    If Len(Dir(fn)) = 0 Then Exit Sub   ' schrijven is mislukt; melding is al gegeven

#ifdef __FB_WIN32__
    ' Windows kent geen lpr; "copy /b" stuurt bytes ongewijzigd naar een
    ' poort of gedeelde printer. Er is altijd een doel nodig: een poort
    ' (LPT1, COM1) of \\computernaam\printernaam. PostScript werkt alleen
    ' als de printer/driver dat begrijpt; zo niet, zet dan printraw=1.
    If Len(Trim(printPrinter)) = 0 Then
        Melden Vt("Op Windows is een poort- of printernaam nodig (Ctrl+T) - er is niet afgedrukt.")
        Exit Sub
    End If
    cmd = "cmd /c copy /b " + Chr(34) + fn + Chr(34) + " " + Chr(34) + Trim(printPrinter) + Chr(34)
#else
    If optPrintRaw <> 0 Then cmd = "lpr -o raw " Else cmd = "lpr "
    If Len(Trim(printPrinter)) > 0 Then cmd = cmd + "-P " + Trim(printPrinter) + " "
    cmd = cmd + fn
#endif

    rc = Shell(cmd)
    melding = Tn("Printopdracht verstuurd (retourcode %1).", Trim(Str(rc)), "", "")
End Sub

' Instellingenschermpje voor printer en taal, in dezelfde opzet als
' Woord's DoSettings (VraagTekst + Bevestig, afsluiten met
' BewaarInstellingen). Vanuit het Opdrachtenmenu aan te roepen.
Sub PrinterTaalInstellingen()
    Dim a As String, ok As Integer
    Dim huidigePrinter As String

    a = VraagTekst(Vt("Instellingen..."), Vt("Taal (nl/en/auto):"), TaalInstelling, ok)
    If ok <> 0 Then
        a = Trim(a)
        If Len(a) > 0 Then TaalInstelling = a
    End If

    If Bevestig(Tn("Matrixprinter gebruiken (platte tekst, raw)? (nu: %1)", JaNeeTekst(optPrintRaw), "", "")) <> 0 Then
        optPrintRaw = 1
    Else
        optPrintRaw = 0
    End If

    If Len(Trim(printPrinter)) > 0 Then huidigePrinter = printPrinter Else huidigePrinter = Vt("systeemstandaard")
    a = VraagTekst(Vt("Instellingen..."), Tn("Printer/poort (nu: %1; Linux: lpr -P-naam, Windows: LPT1, COM1 of \\pc\printer):", huidigePrinter, "", ""), printPrinter, ok)
    If ok <> 0 Then printPrinter = Trim(a)

    BewaarInstellingen
    If LCase(Trim(TaalInstelling)) = "auto" Or Len(Trim(TaalInstelling)) = 0 Then
        HuidigeTaal = DetecteerTaal()
    Else
        HuidigeTaal = LCase(Trim(TaalInstelling))
    End If

    melding = Vt("Instellingen bijgewerkt.")
End Sub
