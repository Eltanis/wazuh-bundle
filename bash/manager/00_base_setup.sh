#!/usr/bin/env bash
# ============================================================
# 00_base_setup.sh _SSH hardening + installation Wazuh all-in-one
# - Sauvegarde wazuh-install-files.tar dans /root/.wazuh-bundle/
# - Extrait et affiche les mots de passe à la fin
# - Nettoie le dossier home_lab après usage
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_root

STATIC_IP="192.x.x.x"
GATEWAY="192.x.x.x"
INTERFACE="enp0s3"
SET_STATIC_IP=false

# Dossier de sauvegarde sécurisé (lisible root uniquement)
SECURE_DIR="/root/.wazuh-bundle"
mkdir -p "$SECURE_DIR"
chmod 700 "$SECURE_DIR"

apt-get update -qq
apt-get install -y openssh-server curl

# 1. SSH
log_info "=== 1/5 : SSH ==="
systemctl enable --now ssh
backup_file /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
systemctl restart ssh
log_ok "SSH durci (root login désactivé, 3 tentatives max)"

# 2. IP statique (optionnel)
log_info "=== 2/5 : IP statique ==="
if [[ "$SET_STATIC_IP" == "true" ]]; then
  NODE_IP="$STATIC_IP"
  log_warn "TODO : configurer le bloc netplan/ifupdown pour $INTERFACE -> $STATIC_IP"
else
  NODE_IP="$(hostname -I | awk '{print $1}')"
  log_warn "Mode DHCP — IP détectée : $NODE_IP"
fi

# 3. Wazuh all-in-one
log_info "=== 3/5 : Wazuh ==="
if systemctl list-unit-files 2>/dev/null | grep -q '^wazuh-manager'; then
  log_warn "wazuh-manager déjà installé, étape ignorée."
  log_ok "Etape 0 terminée (Wazuh pré-existant détecté)."
  exit 0
fi
  
# Dossier temporaire pour l'installation 
WORK_DIR="$(mktemp -d /tmp/wazuh-install-XXXXXX)"
cd "$WORK_DIR"

curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh

cat > config.yml <<EOF
nodes:
  indexer:
    - name: node-1
      ip: "${NODE_IP}"
  server:
    - name: wazuh-1
      ip: "${NODE_IP}"
  dashboard:
    - name: dashboard
      ip: "${NODE_IP}"
EOF

bash wazuh-install.sh -a 2>&1 | tee "$WORK_DIR/wazuh-install.log"

# 4.Sauvegarde Mot de passe
log_info "=== 4/5 : Save ==="
if [[ -f "$WORK_DIR/wazuh-install-files.tar" ]]; then
  cp "$WORK_DIR/wazuh-install-files.tar" "$SECURE_DIR/wazuh-install-files.tar"
  chmod 600 "$SECURE_DIR/wazuh-install-files.tar"

  # Extrait et sauvegarde les mots de passe en clair
  tar -O -xf "$SECURE_DIR/wazuh-install-files.tar" \
    wazuh-install-files/wazuh-passwords.txt \
    > "$SECURE_DIR/wazuh-passwords.txt" 2>/dev/null || true
  chmod 600 "$SECURE_DIR/wazuh-passwords.txt"

  log_ok "Mot de passe sauvegardés dans $SECURE_DIR/wazuh-passwords.txt"
else
  log_warn "wazuh-install-files.tar introuvable — vérifie $WORK_DIR/"
fi


# 5.Nettoyage
cd /tmp
rm -rf "$WORK_DIR"
log_info "installation terminé et nettoyé."

log_ok "Etape 0 terminée."
echo
echo "  Wazuh Dashboard : https://${NODE_IP}"
echo "  pwd    : sudo cat $SECURE_DIR/wazuh-passwords.txt"
echo
log_warn "Ne partager JAMAIS $SECURE_DIR/ | lisible root uniquement."
