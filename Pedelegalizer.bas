'Pedelegalizer 0.9
$regfile = "attiny85.dat"
$crystal = 8000000
$hwstack = 32                                               ' default use 32 for the hardware stack
$swstack = 10                                               ' default use 10 for the SW stack
$framesize = 40                                             ' default use 40 for the frame space

'Analog in initialisieren

Config Adc = Single , Prescaler = Auto , Reference = Avcc
Start Adc

'Timer für PWM initialisieren

Config Timer0 = Pwm , Pwm = On , Prescale = 1 , Compare A Pwm = Clear Down , Compare B Pwm = Clear Down
Enable Timer0
Start Timer0
Ocr0a = 255

'Ein- und Ausgänge initialisieren


Config Portb.0 = Output                                     'PB0 für PWM auf Ausgang stellen
Config Portb.1 = Input                                      'PB1 für PAS einlesen auf Lesen stellen
Config Portb.2 = Input                                      'PB2 für Int0 (Tachopuls) auf Lesen stellen
Config Portb.3 = Input                                      'PB3 für Poti auswerten auf Lesen stellen
Config Portb.4 = Input                                      'PB4 für Gasgriffstellung auswerten auf Lesen stellen
Set Portb.1                                                 'Pullup aktivieren für PAS
Set Portb.2                                                 'Pullup aktivieren (Reedkontakt vom Tacho zieht Signal auf Masse)


Config debounce = 5                                         'Entprellen für 5ms


'Interrupts initialisieren

On Timer1 Tick Saveall
Enable Timer1
Config Timer1 = Timer , Prescale = 64
On Int0 Reed Saveall
Enable Int0
Config Int0 = Falling
Enable Interrupts

'Variablen definieren

Dim Flagtime As Bit                                         'Flag für Timerinterrupt
Dim Flagint0 As Bit                                         'Flag für Int0 Interrupt
Dim Poti As Word                                            'Analogwert Poti
Dim Gasgriff As Word                                        'Analogwert Gasgriffstellung
Dim Zeitpas As Word                                         'Zeitzähler für Tretkurbelumdrehung
Dim Pashigh As Word                                         'Zähler für Anzahl Zustände PAShigh
Dim Paslow As Word                                          'Zähler für Anzahl Zustände PASlow
Dim Pastimeout As Word                                      'Dauer, bis Unterstützung nach Kurbelstillstand abgeschaltet wird
Dim Zeitreed As Word                                        'Zähler für Tachosignal
Dim Tacho As Word                                           'aktuelle Dauer für eine Radumdrehung
Dim Limit As Dword                                          'Limit für Tacho aus Potistellung, Radumfang und Timereinstellung
Dim Tachosoll As Dword                                      'Sollgeschwindigkeit aus Gasgriffstellung errechnet
Dim Pwmact As Word                                          'Rechenvariable für P-Regelung
Dim Pwmout As Word                                          'Tatsächlicher PWM-Wert im 8 bit Raum
Dim Dauervmax As Word                                       'Limit für minimale Dauer Radumdrehung aus Radumfang und Timereinstellung
Dim Pwmmin As Word                                          'Gasgriffspannung bei Ruhestellung
Dim Pwmmax As Word                                          'Maximalwert in 10bit * Regelfaktor
Dim Regelfaktor As Byte                                     'Shiftfaktor für langsamere Regelung

Dim Delta As Long                                            'Reglerabweichung

'Variablen initialisieren
Delta = 0
Flagtime = 0
Flagint0 = 0
Poti = 0
Pwmmin = 65                                                 'Gasgriff Ruhestellung in der 8-Bit Ausgabewelt Versorgung 4,37V, Ruhespannung 0,87V
Gasgriff = 0
Pastimeout = 250                                            '250 Tics entspricht ca. einer halben Sekunde
Zeitpas = Pastimeout + 1                                    'Bei Programmstart erst mal "es wird nicht getreten" definieren
Zeitreed = 3925
Tacho = 3925                                                'Anzahl Tics für 1km/h
Pashigh = 300
Paslow = 300
Pwmout = 0
Limit = 0
Dauervmax = 157                                             'Anzahl Tics bei Vmax Berechnet aus 28 Zoll Rad, CPU-Takt 8MHz, Prescaler 64, Timerbreite 8bit, Vmax 25km/h
Regelfaktor = 1                                             'Erste Idee=2, Hochlauf von 0 auf Vollgas in ca.2 Sekunden
Pwmmin = Pwmmin * 4                                         'Berücksichtigung Lesen 10 Bit, schreiben 8bit
Pwmmin = Pwmmin * Regelfaktor                               'Hochrechnen mit Shiftfaktor
Pwmmax = 1024 * Regelfaktor                                 'Hochrechnen aus 10 Bit mit Shiftfaktor
Pwmact = Pwmmin                                             'Initialisieren mit Startwert

'Start Hauptschleife

Do

'PAS-Abfrage ohne Timing

If Pinb.1 = 1 Then                                          'Aufaddieren der Zustände für Vorwärtstreterkennung
        Incr Pashigh
        Else
        Incr Paslow
End If


'Kern der Auswertung mit Timing

If Flagtime = 1 Then

   Flagtime = 0                                             'Timerflag nach Timer-Interrupt zurücksetzen

'Aktualsierung analoger Messwert

   Poti = Getadc(3)                                         'Potiwert für Speedlimit einlesen
   Limit = Dauervmax * 1024                                 'Limit aus Potieinstellung, Timereinstellung und Radumfang berechnen 8Mhz, 256bit Timer, Prescaler 64, Radgröße 28 Zoll
   Limit = Limit / Poti                                     '

   Gasgriff = Getadc(2)                                     'Gasgriffstellung einlesen
   Tachosoll = Dauervmax * 570                              '662                              ' Hub des Gasgriffsignals: Maximalausschlag ist 3,67V bei 4,27V Versorgungsspannung, ist 880 Digits bei 10Bit, Minus 0,91V=218 Digits Digits für Ruhespannung
   Gasgriff = Gasgriff - 200                                'eigentlich 218 Digits für Ruhespannung  18 Digits Sicherheit um negativen Wert zu vermeiden
   Tachosoll = Tachosoll / Gasgriff                         'Aus Gasgriffstellung soll Geschwindigkeit berechnen  und Bereich erzwingen
   If Tachosoll > 3925 Then Tachosoll = 3925
   If Tachosoll < Dauervmax then Tachosoll = Dauervmax
   Gasgriff = Gasgriff + 200
   Gasgriff = Gasgriff * Regelfaktor                        'Hochskalieren für Regelung

'Auswertung PAS und Tacho
   Incr Zeitreed                                            'Zeitzähler für Radumdrehung hochsetzen
   If Zeitreed > 3925 Then Zeitreed = 3925                  'Überlauf Zähler bei Radstillstand vemeiden, auf 1km/h setzen, damit Regler beim ersten Start nicht aus dem Nirvana anlaufen muß

   Incr Zeitpas                                             'Zeitzähler für Tretkurbelbewegung hochsetzen
   If Zeitpas > 65000 Then Zeitpas = 65000                  'Überlauf Zähler bei Kurbelstillstand vemeiden

   If Pashigh > 65000 Then Pashigh = 65000                  'Überlauf Zähler bei Kurbelstillstand vemeiden, um Stacküberlauf zu vermeiden in der getimten Schleife
   If Paslow > 65000 Then Paslow = 65000                    'Überlauf Zähler bei Kurbelstillstand vemeiden, um Stacküberlauf zu vermeiden in der getimten Schleife


   Debounce Pinb.1 , 1 , Pastick , Sub                      'Entprelltes Erkennen von Steigender Flanke am PAS-Eingang




'Stellwert Ausgang neu berechnen
'Geschwindigkeitswerte beziehen sich auf Dauer der Radumdrehung, darum Logik umgedreht.

If Zeitreed = 3925 And Gasgriff > Pwmmin Then               'Wenn aus dem Stand Gasgegeben wird, dann Tachotic auslösen
   Flagint0 = 1                                             'und halbgas geben
   Pwmact = Pwmmax / 2                                      'Tacho auf Limit setzen
   Zeitreed = Limit
   End If
If Zeitpas > Pastimeout And Tachosoll < Limit Then Tachosoll = Limit       ' Wenn nicht getreten wird und zuviel Gas gegeben wird, dann auf Limit begrenzen

If Flagint0 = 1 Then                                        'Stellwert neu berechnen wenn Tachotic aus Interrupt erkannt.
   If Zeitreed > 2 Then                                     'Tachowert setzen, Größer zwei Abfrage für Entprellung
      Tacho = Zeitreed
      Zeitreed = 0
      End If
   Delta = Tachosoll - Tacho
Delta = Delta * 3925                                        'eins durch x Charakteristik rausrechnen!
Delta = Delta / Tachosoll
Delta = Delta / Tacho
   Pwmact = Pwmact - Delta
   Flagint0 = 0
End If


'Werteüberprüfung und Anpassen

      If Gasgriff < Pwmmin Then Pwmact = Pwmmin             'Wenn Gas in Ruhestellung, Ausgang auf Pwmmin

      If Pwmact > Pwmmax Then Pwmout = Pwmmax               'Sicherheitshalber um Überlauf zu vermeiden, kann eigentlich nicht passieren
      If Pwmact < Pwmmin Then Pwmact = Pwmmin               'Sicherheitshalber umd Unterlauf zu vermeiden

      Pwmout = Pwmact / 4                                   'Zurückrechnen von 10bit auf 8bit
      Pwmout = Pwmout / Regelfaktor                         'Zurückrechnen des Shiftfaktors


      Pwmout = 255 - Pwmout                                 'Logik umkehren, da 255 = 0V Ausgang, 0=5V Ausgang

      Ocr0a = Pwmout


End If                                                      'Ende der durch Timer1 getakteten Schleife
Loop

End

Pastick:                                                    'PAS-Routine wird angesprungen aus der Debounce-Zeile

        If Pashigh < Paslow Then Zeitpas = 0                'Wenn mehr Low-Zustände als High-Zustände erkannt wurden wird Vorwärts getreten, ggf. ist Logik andersrum

        Pashigh = 0
        Paslow = 0

Return



Tick:                                                       'interruptroutine für Timer1
Flagtime = 1
Return

Reed:
Flagint0 = 1                                                'interruptroutine für Int0
Return
