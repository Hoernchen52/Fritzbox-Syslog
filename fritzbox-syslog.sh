#!/bin/bash
#
# Name:         fritzbox-syslog.sh
# Pfad:         /usr/local/bin/fritzbox-syslog.sh
# Zweck:        Holt Logs und Anrufe von der FRITZ!Box per HTTP-API
#               und schreibt sie in ein lokales Logfile.
# Aufruf:       Wird per systemd-Timer alle 5 Minuten gestartet.
#
# Installation als Dienst:
#
# 0. Abhängigkeit installieren (falls nicht vorhanden)
#  prüfen:
#  python3 -c "import requests; print(requests.__version__)"
#  bei Bedarf installieren:
#  apt install python3-requests
#
# 1. Verzeichnisse anlegen
#  getent group adm || groupadd --gid 4 adm
#  mkdir -p /var/log/fritzbox-syslog
#  chown root:adm /var/log/fritzbox-syslog
#  chmod 0750 /var/log/fritzbox-syslog
#  mkdir -p /etc/fritzbox-syslog
#  chmod 0700 /etc/fritzbox-syslog
#
# 2. Login-Datei anlegen
#  /etc/fritzbox-syslog/credentials
#  FBUSER='<Login-Name>'
#  FBPW='<Login-Passwort>'
#
#  chmod 0600 /etc/fritzbox-syslog/credentials
#  chown root:root /etc/fritzbox-syslog/credentials
#
# 3. Sicherheitstest für Login-Datei
#  ls -la /etc/fritzbox-syslog/
#  Ausgabe:
#  drwx------ 2 root root 4096 ... .
#  -rw------- 1 root root   XX ... credentials
#
# 4. Service-Datei anlegen
#  /etc/systemd/system/fritzbox-syslog.service
#  [Unit]
#  Description=Fritzbox Syslog Puller
#  After=network-online.target
#  Wants=network-online.target
#
#  [Service]
#  Type=oneshot
#  ExecStart=/bin/sh -c '/usr/local/bin/fritzbox-syslog.sh >> /var/log/fritzbox-syslog/fritzbox.log 2>&1'
#
# 5. Timer-Datei anlegen
#  /etc/systemd/system/fritzbox-syslog.timer
#  [Unit]
#  Description=Run fritzbox-syslog.sh every 5 minutes
#
#  [Timer]
#  OnBootSec=2min
#  OnUnitActiveSec=5min
#  Persistent=true
#
#  [Install]
#  WantedBy=timers.target
#
# 6. logrotate-Konfiguration
#  /etc/logrotate.d/fritzbox-syslog
#  /var/log/fritzbox-syslog/fritzbox.log {
#      weekly
#      rotate 8
#      compress
#      delaycompress
#      missingok
#      notifempty
#      create 0640 root adm
#      su root adm
#  }
#
# 7. Aktivieren und testen
#  systemctl daemon-reload
#  systemctl enable --now fritzbox-syslog.timer
#  systemctl list-timers fritzbox-syslog.timer
#
# Einmal manuell auslösen, um zu sehen, dass es schreibt
#  systemctl start fritzbox-syslog.service
#  tail -20 /var/log/fritzbox-syslog/fritzbox.log
#
# 8. Symlink für bequemen Zugriff
#  ln -s /var/log/fritzbox-syslog /root/fritzbox-syslog
#
# 9. Ansehen des Logs vom Probelauf
#  tail -f ~/fritzbox-syslog/fritzbox.log

set -euo pipefail

FBIP="192.168.178.1"
CREDENTIALS="/etc/fritzbox-syslog/credentials"
STATEFILE="/var/lib/fritzbox-syslog/seen.txt"

# Credentials einlesen
if [ ! -r "$CREDENTIALS" ]; then
    echo "Fehler: $CREDENTIALS nicht lesbar." >&2
    exit 1
fi

# shellcheck disable=SC1090
. "$CREDENTIALS"

if [ -z "${FBUSER:-}" ] || [ -z "${FBPW:-}" ]; then
    echo "Fehler: FBUSER oder FBPW nicht in $CREDENTIALS gesetzt." >&2
    exit 1
fi

# Statefile-Verzeichnis anlegen
mkdir -p "$(dirname "$STATEFILE")"
touch "$STATEFILE"

# Python-Code ausführen
FBIP="$FBIP" FBUSER="$FBUSER" FBPW="$FBPW" STATEFILE="$STATEFILE" python3 -c "
import os, hashlib, requests, json, sys, datetime, re

fbip = os.environ['FBIP']
fbuser = os.environ['FBUSER']
fbpw = os.environ['FBPW']
statefile = os.environ['STATEFILE']

now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# --- Filter ---
# Hier können Meldungen (per Regex) ausgeschlossen werden.
# Beispiel: 'Anmeldung des Benutzers' filtert alle erfolgreichen UI-Logins heraus.
IGNORE_PATTERNS = [
    r'Anmeldung des Benutzers .* an der FRITZ!Box-Benutzeroberfläche',
    # r'Abmeldung des Benutzers', # Falls das auch nervt, einfach das # entfernen
]

def should_ignore(msg):
    for pattern in IGNORE_PATTERNS:
        if re.search(pattern, msg):
            return True
    return False

# --- Login ---
s = requests.Session()
r = s.get(f'http://{fbip}/login_sid.lua')
challenge = r.text.split('<Challenge>')[1].split('</Challenge>')[0]
md5 = hashlib.md5(f'{challenge}-{fbpw}'.encode('utf-16-le')).hexdigest()
r = s.post(f'http://{fbip}/login_sid.lua', data={'username': fbuser, 'response': f'{challenge}-{md5}'})
sid = r.text.split('<SID>')[1].split('</SID>')[0]

if sid == '0000000000000000':
    print('Login failed: no valid SID', file=sys.stderr)
    sys.exit(1)

# --- Bereits gesendete Einträge laden ---
seen = []
try:
    with open(statefile) as f:
        seen = f.read().splitlines()
except FileNotFoundError:
    pass

new_entries = 0

# --- Systemprotokoll ---
r = s.post(f'http://{fbip}/data.lua', data={'sid': sid, 'lang': 'de', 'page': 'log', 'no_sidrenew': ''})
data = json.loads(r.text)
logs = data.get('data', {}).get('log', [])

for entry in logs:
    t = entry.get('time', '')
    msg = entry.get('msg', '')
    gid = entry.get('id', '')
    
    # Filter anwenden
    if should_ignore(msg):
        continue

    h = hashlib.md5(f'sys|{t}|{gid}|{msg}'.encode()).hexdigest()
    if h not in seen:
        seen.append(h)
        print(f'{now} | Fritzbox | [{t}] {msg}')
        new_entries += 1

# --- Telefonprotokoll ---
r = s.post(f'http://{fbip}/data.lua', data={'sid': sid, 'lang': 'de', 'page': 'call', 'no_sidrenew': ''})
data2 = json.loads(r.text)
calls = data2.get('data', {}).get('foncalls', {}).get('calls', [])

for c in calls:
    t = f\"{c.get('date','')} {c.get('time','')}\"
    name = c.get('name', '') or c.get('number', 'unbekannt')
    ctype = c.get('type', '')
    msg = f\"{'Anruf an' if ctype == 'out' else 'Eingehender Anruf'}: {name}\"
    
    if should_ignore(msg):
        continue

    h = hashlib.md5(f'call|{t}|{name}|{ctype}'.encode()).hexdigest()
    if h not in seen:
        seen.append(h)
        print(f'{now} | Fritzbox-Telefon | [{t}] {msg}')
        new_entries += 1

# --- State-Datei speichern (max 500) ---
# --- Hinweis: Überlauf möglich, 500 Einträge könnten zu wenig sein ---
with open(statefile, 'w') as f:
    f.write('\n'.join(seen[-500:]))

if new_entries:
    print(f'{new_entries} neue Einträge gesendet', file=sys.stderr)
"
