#!/usr/bin/env bash
# ============================================================
# 07_email_alerts.sh _Alertes email via Postfix + Gmail SMTP
#
# Prérequis : un App Password Gmail (pas ton vrai mot de passe)
# Génère-le sur : https://myaccount.google.com/apppasswords
# (nécessite la 2FA activée sur le compte Google)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

echo "=== Alertes Email (Postfix → Gmail) ==="
echo
echo "Prérequis : App Password Gmail"
echo "  1. Va sur https://myaccount.google.com/apppasswords"
echo "  2. Crée un mot de passe pour 'Wazuh'"
echo "  3. Copie les 16 caractères générés"
echo

read -rp "Ton adresse Gmail : " GMAIL_FROM
read -rp "Email destinataire des alertes : " EMAIL_TO
read -rsp "App Password Gmail (16 chars) : " GMAIL_APP_PWD; echo

[[ -z "$GMAIL_FROM" || -z "$EMAIL_TO" || -z "$GMAIL_APP_PWD" ]] && {
  log_err "Champ vide, abandon."
  exit 1
}

# 1. Installation Postfix
log_info "Installation de Postfix..."
DEBIAN_FRONTEND=noninteractive apt-get install -y postfix libsasl2-modules mailutils

# 2. Config Postfix relay Gmail
log_info "Configuration du relay Gmail dans Postfix..."
backup_file /etc/postfix/main.cf

postconf -e "relayhost = [smtp.gmail.com]:587"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# 3. Credentials Gmail
echo "[smtp.gmail.com]:587 ${GMAIL_FROM}:${GMAIL_APP_PWD}" \
  > /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

systemctl restart postfix

# 4. Test d'envoi
log_info "Envoi d'un email de test vers $EMAIL_TO..."
echo "Test alerte Wazuh — $(date)" | mail -s "[WAZUH TEST] Email OK" "$EMAIL_TO" 2>/tmp/mail-test.log
if [[ $? -eq 0 ]]; then
  log_ok "Email envoyé. Vérifie ta boite de réception (et les spams)."
else
  log_warn "Echec envoi test. Vérifie : cat /tmp/mail-test.log"
fi

# 5. Configuration Wazuh pour les emails
log_info "Activation des alertes email dans ossec.conf..."
python3 - "$GMAIL_FROM" "$EMAIL_TO" <<'PYEOF'
import sys, re
gmail_from, email_to = sys.argv[1], sys.argv[2]
path = "/var/ossec/etc/ossec.conf"
with open(path) as f:
    content = f.read()

replacements = {
    "<email_notification>no</email_notification>": "<email_notification>yes</email_notification>",
    "<smtp_server>smtp.example.wazuh.com</smtp_server>": "<smtp_server>localhost</smtp_server>",
    "<email_from>wazuh@example.wazuh.com</email_from>": f"<email_from>{gmail_from}</email_from>",
    "<email_to>recipient@example.wazuh.com</email_to>": f"<email_to>{email_to}</email_to>",
}

for old, new in replacements.items():
    content = content.replace(old, new)

with open(path, "w") as f:
    f.write(content)
print("ossec.conf mis à jour.")
PYEOF

# Permissions après écriture Python
fix_ossec_permissions /var/ossec/etc/ossec.conf

# Seuil d'alerte email dans <alerts>
python3 - <<'PYEOF'
path = "/var/ossec/etc/ossec.conf"
with open(path) as f:
    content = f.read()
content = content.replace(
    "<email_alert_level>12</email_alert_level>",
    "<email_alert_level>8</email_alert_level>"
)
with open(path, "w") as f:
    f.write(content)
print("Seuil email_alert_level fixé à 8.")
PYEOF

fix_ossec_permissions /var/ossec/etc/ossec.conf
restart_wazuh_manager

log_ok "Etape 7 terminée : alertes email actives pour level >= 8."
