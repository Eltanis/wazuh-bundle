#!/usr/bin/env bash
# ============================================================
# 04_opensearch_plugin.sh — Plugin OpenSearch pour Grafana
# Fallback manuel si storage.googleapis.com est bloqué
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

# unzip requis pour l'installation manuelle du plugin
if ! command -v unzip &>/dev/null; then
  log_info "Installation de unzip..."
  apt-get install -y unzip
fi

PLUGIN_ID="grafana-opensearch-datasource"
PLUGIN_VERSION="2.33.1"
PLUGIN_DIR="/var/lib/grafana/plugins"

# Déjà installé ?
if [[ -d "$PLUGIN_DIR/$PLUGIN_ID" ]]; then
  log_warn "Plugin $PLUGIN_ID déjà installé, étape ignorée."
  exit 0
fi

log_info "Tentative d'installation via grafana-cli..."
if grafana-cli plugins install "$PLUGIN_ID" 2>/tmp/grafana-plugin.log; then
  log_ok "Plugin installé via grafana-cli."
  restart_grafana
  exit 0
fi

# Echec = réseau bloqué vers storage.googleapis.com (Google Cloud)
log_warn "Echec grafana-cli — storage.googleapis.com probablement bloqué sur ce réseau."
echo
echo "  Installation manuelle :"
echo "  1. Depuis une machine avec accès internet, télécharge :"
echo "     https://storage.googleapis.com/grafana-plugins-catalog/${PLUGIN_ID}/release/${PLUGIN_VERSION}/${PLUGIN_ID}-${PLUGIN_VERSION}.linux-amd64.zip"
echo "  2. Transfère le .zip sur ce serveur :"
echo "     scp fichier.zip user@$(hostname -I | awk '{print $1}'):/tmp/"
echo

read -rp "Chemin vers le .zip transféré (Entrée pour réessayer grafana-cli) : " ZIP_PATH

if [[ -z "$ZIP_PATH" ]]; then
  log_info "Nouvelle tentative grafana-cli..."
  grafana-cli plugins install "$PLUGIN_ID"
else
  [[ -f "$ZIP_PATH" ]] || { log_err "Fichier introuvable : $ZIP_PATH"; exit 1; }
  mkdir -p "$PLUGIN_DIR"
  unzip -o "$ZIP_PATH" -d "$PLUGIN_DIR" > /dev/null
  chown -R grafana:grafana "$PLUGIN_DIR/$PLUGIN_ID"

  # Autorise le chargement si plugin non signé
  if ! grep -q "allow_loading_unsigned_plugins" /etc/grafana/grafana.ini 2>/dev/null; then
    printf "\n[plugins]\nallow_loading_unsigned_plugins = %s\n" "$PLUGIN_ID" \
      >> /etc/grafana/grafana.ini
    log_info "allow_loading_unsigned_plugins ajouté dans grafana.ini"
  fi
fi

restart_grafana
log_ok "Etape 4 terminée : plugin OpenSearch installé."
