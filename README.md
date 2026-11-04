# fritzbox-syslog

Holt Systemprotokoll und Anrufliste einer FRITZ!Box per HTTP-API ab und
schreibt neue Einträge in ein lokales Logfile. Gedacht für den Betrieb
auf einem Debian-/Ubuntu-System (z. B. Proxmox VE oder OPNsense) als
systemd-Timer.

## Was das Skript macht

- Meldet sich per HTTP-API an der FRITZ!Box an.
- Ruft das Systemprotokoll und die Anrufliste ab.
- Filtert bereits bekannte Einträge über eine State-Datei heraus.
- Schreibt nur neue Einträge in ein Logfile (stdout).
- Ausgeschlossene Meldungen (z. B. UI-Logins) werden per Regex gefiltert.

## Voraussetzungen

- Debian-/Ubuntu-basiertes System mit `bash`, `systemd` und `python3`.
- Python-Modul `requests` (`apt install python3-requests`).
- Erreichbarkeit der FRITZ!Box im Netz.
- Ein FRITZ!Box-Benutzerkonto mit Zugriff auf Systemprotokoll und
  Anrufliste (die FRITZ!Box erlaubt das nicht für das Standard-Passwort
  des Administrators, sondern nur für angelegte Benutzer).

## Installation

Die vollständige Installationsanleitung steht als Kommentarblock im
Kopf des Skripts `fritzbox-syslog.sh`. Kurzfassung:

1. Abhängigkeit installieren: `apt install python3-requests`
2. Verzeichnisse anlegen (siehe Skriptkopf)
3. Zugangsdaten ablegen unter `/etc/fritzbox-syslog/credentials`
   (Rechte `0600`, Eigentümer `root:root`)
4. Skript nach `/usr/local/bin/fritzbox-syslog.sh` kopieren,
   ausführbar machen
5. systemd-Service und -Timer anlegen (siehe Skriptkopf)
6. logrotate-Konfiguration anlegen (siehe Skriptkopf)
7. Timer aktivieren: `systemctl enable --now fritzbox-syslog.timer`

## Konfiguration

- **FRITZ!Box-IP:** `FBIP` im Skript (Standard: `192.168.178.1`)
- **Zugangsdaten:** `/etc/fritzbox-syslog/credentials`
- **State-Datei:** `/var/lib/fritzbox-syslog/seen.txt`
- **Ausgabe:** stdout (wird vom systemd-Service in ein Logfile
  umgeleitet), Statusmeldungen nach stderr
- **Filter:** `IGNORE_PATTERNS` im Python-Teil des Skripts (Regex-Liste)

## Ausgabeformat
