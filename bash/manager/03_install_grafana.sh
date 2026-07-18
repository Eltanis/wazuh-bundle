#!/usr/bin/env bash
# ============================================================
# 03_install_grafana.sh _Installation Grafana
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

# Déjà installé ?
if systemctl list-unit-files 2>/dev/null | grep -q '^grafana-server'; then
  log_warn "Grafana déjà installé, étape ignorée."
  systemctl is-active --quiet grafana-server || restart_grafana
  exit 0
fi

log_info "Installation des prérequis..."
apt-get update -qq
# software-properties-common absent sur Debian 13, optionnel sur 12
apt-get install -y apt-transport-https wget gnupg2
apt-get install -y apt-transport-https software-properties-common 2>/dev/null || true

log_info "Ajout du dépôt officiel Grafana..."
mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key \
  | gpg --dearmor \
  | tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | tee /etc/apt/sources.list.d/grafana.list > /dev/null

apt-get update -qq
apt-get install -y grafana

systemctl enable grafana-server
restart_grafana

IP=$(hostname -I | awk '{print $1}')
log_ok "Etape 3 terminée : Grafana installé."
echo
echo "  URL     : http://${IP}:3000"
echo "  Login   : admin / admin (à changer à la première connexion)"
