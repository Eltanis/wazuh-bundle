#!/usr/bin/env bash
# ============================================================
# 08_sms_alerts.sh — Alertes SMS via Africa's Talking
#
# Déploie un daemon systemd qui surveille alerts.json en temps
# réel et envoie un SMS pour chaque alerte level >= seuil.
#
# On n-utilise PAS le mécanisme d-intégration natif Wazuh car
# il bloque les intégrations custom non whitelistées en 4.14.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

echo "=== Alertes SMS (Africa's Talking) ==="
echo "Inscris-toi sur : https://account.africastalking.com/auth/register"
echo "Utilise 'sandbox' comme username pour les tests gratuits."
echo

read -rp "Username Africa's Talking [sandbox] : " AT_USERNAME
AT_USERNAME="${AT_USERNAME:-sandbox}"

read -rsp "Clé API Africa's Talking : " AT_API_KEY; echo
read -rp "Numéro destinataire (ex: +241xxxxxxxx) : " SMS_TO
read -rp "Niveau d'alerte minimum [8] : " ALERT_LEVEL
ALERT_LEVEL="${ALERT_LEVEL:-8}"

[[ -z "$AT_API_KEY" || -z "$SMS_TO" ]] && { log_err "Champ vide, abandon."; exit 1; }

# Vérifie/installe le module Python africastalking
ensure_africastalking() {
  if python3 -c "import africastalking" 2>/dev/null; then
    log_ok "Module africastalking présent."
    return 0
  fi
  log_info "Installation du module africastalking..."
  if command -v pip3 &>/dev/null; then
    pip3 install africastalking --break-system-packages
  elif python3 -m pip --version &>/dev/null 2>&1; then
    python3 -m pip install africastalking --break-system-packages
  else
    log_info "pip absent, installation de python3-pip..."
    apt-get install -y python3-pip
    pip3 install africastalking --break-system-packages
  fi
  python3 -c "import africastalking" 2>/dev/null \
    || { log_err "Echec installation africastalking"; return 1; }
  log_ok "Module africastalking installé."
}

ensure_africastalking

# Génère le script daemon depuis le template
SCRIPT_DEST="/usr/local/bin/wazuh-sms-alerter.py"
cp "$BUNDLE_ROOT/configs/manager/wazuh-sms-alerter.py.template" "$SCRIPT_DEST"
replace_placeholder "$SCRIPT_DEST" "__AT_USERNAME__"   "$AT_USERNAME"
replace_placeholder "$SCRIPT_DEST" "__AT_API_KEY__"    "$AT_API_KEY"
replace_placeholder "$SCRIPT_DEST" "__SMS_RECIPIENT__" "$SMS_TO"
replace_placeholder "$SCRIPT_DEST" "__ALERT_LEVEL__"   "$ALERT_LEVEL"
chmod 750 "$SCRIPT_DEST"
log_ok "Script daemon déployé : $SCRIPT_DEST"

# Déploie le service systemd
cp "$BUNDLE_ROOT/configs/manager/wazuh-sms-alerter.service" \
   /etc/systemd/system/wazuh-sms-alerter.service

systemctl daemon-reload
systemctl enable wazuh-sms-alerter
systemctl restart wazuh-sms-alerter
sleep 3

if systemctl is-active --quiet wazuh-sms-alerter; then
  log_ok "Service wazuh-sms-alerter actif."
else
  log_err "Service non démarré. Vérifie : journalctl -u wazuh-sms-alerter -n 20"
  exit 1
fi

log_ok "Etape 8 terminée : alertes SMS actives pour level >= ${ALERT_LEVEL}."
echo
echo "  Test SMS : sudo python3 -c \\"
echo "    open('/var/www/eicar.txt','w').write('X5O!P%@AP[4\PZX54(P^)7CC)7}\\\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\\\$H+H*')\""
echo
log_warn "Sandbox Africa's Talking = SMS non livrés sur vrai téléphone."
log_warn "Pour la prod : recharge ton compte AT et utilise ta clé de production."
