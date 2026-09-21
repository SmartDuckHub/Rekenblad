' ==================================================================
'  Rekenblad - module: rekenblad_taal.bi
'  Het vertaalsysteem, in dezelfde opzet als woord_taal.bi in Woord.
'  Via #include in rekenblad.bas in te voegen (vlak na de Const-
'  declaraties, voor de Dim Shared-regels) -- geen zelfstandig te
'  compileren bestand.
'
'  Gebruik in de rest van rekenblad.bas:
'     Melden Vt("Dit tabblad is leeg.")
'     s = Tn("Pagina %1 van %2", Trim(Str(pg)), Trim(Str(n)), "")
'
'  Vertaalbestand naast de exe: rekenblad_taal_en.txt (regels van de
'  vorm "nederlandse tekst => english text"), zelfde formaat als bij
'  Woord. taal=auto/nl/en in Rekenblad.cfg.
' ==================================================================

Const TAAL_MAX = 500

Dim Shared HuidigeTaal        As String
Dim Shared TaalInstelling     As String
Dim Shared GeladenTaalcode    As String
Dim Shared AantalVertalingen  As Integer
Dim Shared VertaalSleutel(1 To TAAL_MAX) As String
Dim Shared VertaalWaarde(1 To TAAL_MAX)  As String

Function DetecteerTaal() As String
    Dim v As String

    v = Environ("LC_ALL")
    If Len(v) = 0 Then v = Environ("LC_MESSAGES")
    If Len(v) = 0 Then v = Environ("LANG")
    If Len(v) = 0 Then v = Environ("LANGUAGE")

    v = LCase(v)
    If Left(v, 2) = "nl" Then
        DetecteerTaal = "nl"
    ElseIf Left(v, 2) = "en" Then
        DetecteerTaal = "en"
    Else
        ' Engels is de terugvaltaal wanneer de OS-taal niet is te bepalen
        ' (bijv. op Windows) of niet wordt ondersteund. Forceer zo nodig
        ' met taal=nl/taal=en in Rekenblad.cfg.
        DetecteerTaal = "en"
    End If
End Function

Sub LaadVertaalTabel(ByRef code As String)
    Dim f As Integer, p As Integer
    Dim s As String, bestandspad As String, sleutel As String, waarde As String

    AantalVertalingen = 0
    GeladenTaalcode = LCase(Trim(code))

    If GeladenTaalcode = "" Or GeladenTaalcode = "nl" Then
        ' Nederlands is de brontaal: geen bestand nodig, vertaalTekst geeft
        ' dan gewoon de originele tekst terug
        Exit Sub
    End If

    ' zoek het bestand naast de werkmap, net als Rekenblad.cfg
    bestandspad = dataMap + SEP + "rekenblad_taal_" + GeladenTaalcode + ".txt"
    If Len(Dir(bestandspad)) = 0 Then
        ' val terug op de map van de exe zelf
        bestandspad = ExePath + SEP + "rekenblad_taal_" + GeladenTaalcode + ".txt"
        If Len(Dir(bestandspad)) = 0 Then Exit Sub
    End If

    f = FreeFile
    If Open(bestandspad For Input As #f) <> 0 Then Exit Sub
    Do While Not Eof(f) And AantalVertalingen < TAAL_MAX
        Line Input #f, s
        If Right(s, 1) = Chr(13) Then s = Left(s, Len(s) - 1)
        If Len(s) > 0 And Left(s, 1) <> "'" Then
            ' let op: " => " (met spaties), niet kaal "=" -- sommige
            ' sleutels bevatten zelf een "=" of een dubbele punt
            p = InStr(s, " => ")
            If p > 0 Then
                sleutel = Left(s, p - 1)
                waarde  = Mid(s, p + 4)
                AantalVertalingen += 1
                VertaalSleutel(AantalVertalingen) = sleutel
                VertaalWaarde(AantalVertalingen) = waarde
            End If
        End If
    Loop
    Close #f
End Sub

Function vertaalTekst(ByRef tekst As String, ByRef taalcode As String) As String
    Dim i As Integer
    Dim code As String

    code = LCase(Trim(taalcode))
    If code = "" Then code = "nl"

    If code <> GeladenTaalcode Then LaadVertaalTabel code

    If code = "nl" Then
        vertaalTekst = tekst
        Exit Function
    End If

    For i = 1 To AantalVertalingen
        If VertaalSleutel(i) = tekst Then
            vertaalTekst = VertaalWaarde(i)
            Exit Function
        End If
    Next i

    ' geen vertaling gevonden: val terug op de Nederlandse brontekst
    vertaalTekst = tekst
End Function

Function Vt(ByRef tekst As String) As String
    Vt = vertaalTekst(tekst, HuidigeTaal)
End Function

Function VervangEerste(ByRef bron As String, ByRef patroon As String, ByRef vervang As String) As String
    Dim p As Integer
    p = InStr(bron, patroon)
    If p > 0 Then
        VervangEerste = Left(bron, p - 1) + vervang + Mid(bron, p + Len(patroon))
    Else
        VervangEerste = bron
    End If
End Function

Function Tn(ByRef sjabloon As String, ByRef a1 As String, ByRef a2 As String, ByRef a3 As String) As String
    Dim vert As String
    vert = Vt(sjabloon)
    vert = VervangEerste(vert, "%1", a1)
    vert = VervangEerste(vert, "%2", a2)
    vert = VervangEerste(vert, "%3", a3)
    Tn = vert
End Function

Function JaNeeTekst(ByVal v As Integer) As String
    If v <> 0 Then JaNeeTekst = Vt("aan") Else JaNeeTekst = Vt("uit")
End Function
