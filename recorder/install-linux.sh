#!/bin/bash
# Raadiosalvesti paigaldus Linuxile: venv, seaded, systemd (kasutaja) teenus, `raadio` käsk.
# Mitteinteraktiivselt (nt CI): RAADIO_NONINTERACTIVE=1 RAADIO_MODE=local|r2 RAADIO_PASS=... ./install-linux.sh
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TTY=/dev/tty; { : </dev/tty; } 2>/dev/null || TTY=/dev/stdin
ask() {  # ask muutuja "küsimus" vaikeväärtus [-s]
  local __v=""
  if [ -n "$RAADIO_NONINTERACTIVE" ]; then __v="$3"
  else read -r $4 -p "$2" __v < $TTY || __v="$3"; [ "$4" = -s ] && echo; fi
  printf -v "$1" '%s' "${__v:-$3}"
}

UNIT=raadiosalvestaja
CONF_DIR=~/.config/raadiosalvestaja
CONF=$CONF_DIR/config.env
LOG=~/.local/state/raadiosalvestaja/salvesti.log
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

command -v ffmpeg >/dev/null || { echo "ffmpeg puudub – paigalda see paketihalduriga (nt sudo apt install ffmpeg)"; exit 1; }

echo "→ Pythoni keskkond"
python3 -m venv "$DIR/.venv"
"$DIR/.venv/bin/pip" install -q --disable-pip-version-check -r "$DIR/requirements.txt"

# võivad sisaldada erimärke -> mitte sed-iga; puuduv võti lisatakse
setconf() { VAL="$2" python3 -c 'import os,re,sys
p,k=sys.argv[1:3];s=open(p).read();v=os.environ["VAL"]
s=re.sub(r"(?m)^"+k+"=.*$",lambda m:k+"="+v,s) if re.search(r"(?m)^"+k+"=",s) else s.rstrip("\n")+"\n"+k+"="+v+"\n"
open(p,"w").write(s)' "$CONF" "$1"; }

firstInstall=""
if [ ! -f "$CONF" ]; then
  firstInstall=1
  mkdir -p "$CONF_DIR"
  cp "$DIR/config.env.example" "$CONF"
  chmod 600 "$CONF"
  if [ -z "$RAADIO_MODE" ]; then
    echo
    echo "Kus salvestusi hoida?"
    echo "  1) Siin arvutis (soovitatav – pilve pole vaja, telefonist koduvõrgus)"
    echo "  2) Cloudflare R2 (kuulamine kõikjal, vajab Cloudflare'i seadistamist)"
    ask mode "Valik [1]: " 1
    [ "$mode" = 2 ] && RAADIO_MODE=r2 || RAADIO_MODE=local
  fi
  setconf LOG_FILE "$LOG"
  if [ "$RAADIO_MODE" = r2 ]; then
    setconf STORAGE r2
    echo "→ Täida R2 andmed failis $CONF (nt: nano $CONF) ja käivita installer uuesti:"
    echo "  bash $DIR/install-linux.sh"
    exit 0
  fi
  echo
  echo "Veebilehe sisselogimine (telefonis küsitakse kasutajanime ja parooli):"
  user="$RAADIO_USER"; [ -z "$user" ] && ask user "  Kasutajanimi [raadio]: " raadio
  pass="$RAADIO_PASS"; [ -z "$pass" ] && ask pass "  Parool (soovitatav, tühi = ilma parooliga): " "" -s
  setconf WEB_USER "${user:-raadio}"
  if [ -n "$pass" ]; then setconf WEB_PASS "$pass"; fi
fi
grep -q "^LOG_FILE=" "$CONF" || setconf LOG_FILE "$LOG"
if grep -q "^STORAGE=r2" "$CONF" && ! grep -q "^R2_SECRET_ACCESS_KEY=..*" "$CONF"; then
  echo "Täida R2 andmed failis $CONF"; exit 1
fi

echo "→ Taustateenus (systemd)"
mkdir -p ~/.config/systemd/user "$(dirname "$LOG")"
cat > ~/.config/systemd/user/$UNIT.service <<UNITFILE
[Unit]
Description=Raadiosalvesti
After=network-online.target
Wants=network-online.target

[Service]
ExecStart="$DIR/.venv/bin/python" -u "$DIR/kuku_recorder.py"
Environment=PATH=$(dirname "$(command -v ffmpeg)"):/usr/local/bin:/usr/bin:/bin
Restart=always
RestartSec=30

[Install]
WantedBy=default.target
UNITFILE
# linger: teenus käivitub arvuti sisselülitamisel ka ilma sisselogimiseta (nt Raspberry Pi)
if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != yes ]; then
  loginctl enable-linger "$USER" 2>/dev/null || sudo loginctl enable-linger "$USER" \
    || echo "  (loginctl enable-linger ebaõnnestus – salvesti töötab ainult siis, kui oled sisse logitud)"
fi
for i in 1 2 3 4 5 6 7 8 9 10; do systemctl --user show-environment >/dev/null 2>&1 && break; sleep 0.5; done
if ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "systemd kasutajateenus pole saadaval (nt su/sudo all). Logi selle kasutajana otse sisse (ka SSH sobib) ja käivita:"
  echo "  bash $DIR/install-linux.sh"
  exit 1
fi
systemctl --user daemon-reload
systemctl --user enable -q $UNIT
systemctl --user restart $UNIT

# käsk `raadio`
mkdir -p ~/.local/bin
cat > ~/.local/bin/raadio <<CMD
#!/bin/sh
exec "$DIR/.venv/bin/python" "$DIR/raadio.py" "\$@"
CMD
chmod +x ~/.local/bin/raadio
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  if ! grep -q '.local/bin' ~/.bashrc 2>/dev/null; then
    printf '\n# Raadiosalvesti\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.bashrc
  fi
  echo "→ Käsk 'raadio' lisatud (ava uus terminal)";;
esac

# ufw tulemüür (Ubuntu): luba telefonil lehte avada
if [ -n "$firstInstall" ] && grep -q "^ENABLED=yes" /etc/ufw/ufw.conf 2>/dev/null && ! grep -q "^STORAGE=r2" "$CONF"; then
  port=$(grep "^WEB_PORT=" "$CONF" | cut -d= -f2); port=${port:-8788}
  ask fw "Tulemüür (ufw) on sees. Kas lubada telefonil veebilehte avada (port $port)? [J/e] " j
  case "$fw" in [eEnN]*) ;; *) sudo ufw allow "$port/tcp" comment Raadiosalvestaja || true;; esac
fi

sleep 4
echo
if systemctl --user is-active -q $UNIT; then echo "✓ Valmis."; else echo "⚠ Teenus ei käivitunud – vaata: raadio log"; fi
u=$("$DIR/.venv/bin/python" "$DIR/raadio.py" url)
case "$u" in http*)
  echo "  Selles arvutis:              http://localhost:${u##*:}"
  echo "  Telefonis (samas Wi-Fi-s):   $u"
  if grep -q "^WEB_PASS=..*" "$CONF"; then
    echo "  Kasutajanimi: $(grep '^WEB_USER=' "$CONF" | cut -d= -f2- | grep . || echo raadio)   Parool: see, mille sisestasid"
  else
    echo "  (parool puudub – lehele pääseb igaüks samas võrgus)"
  fi;;
esac
echo
echo "  Arvuti peab olema sees (mitte unerežiimis). Salvesti olek: raadio"
