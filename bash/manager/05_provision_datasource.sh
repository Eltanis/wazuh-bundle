#!/usr/bin/env bash
# ============================================================
# 05_provision_datasource.sh _Datasource Grafana → Wazuh Indexer
#
# On passe par le provisioning YAML plutôt que l'UI car :
# - Le bouton "Get Version and Save" échoue avec Wazuh Indexer
#   (renvoie 7.10.2 au lieu d'une version OpenSearch reconnue)
# - flavor + version forcés en dur = contournement du bug
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

TARGET="/etc/grafana/provisioning/datasources/wazuh-opensearch.yaml"

if [[ -f "$TARGET" ]]; then
  log_warn "Datasource déjà provisionné ($TARGET)."
  read -rp "Reconfigurer ? [o/N] " confirm
  [[ "$confirm" =~ ^[oOyY]$ ]] || exit 0
fi

echo "=== Connexion Wazuh Indexer ==="
read -rp "URL de l'indexer [https://localhost:9200] : " INDEXER_URL
INDEXER_URL="${INDEXER_URL:-https://localhost:9200}"

read -rp "Utilisateur [admin] : " INDEXER_USER #admin wazuh
INDEXER_USER="${INDEXER_USER:-admin}"

read -rsp "Mot de passe : " INDEXER_PASSWORD; echo  # son mot de passe

read -rp "Version OpenSearch réelle [2.19.0] : " OS_VERSION
OS_VERSION="${OS_VERSION:-2.19.0}"

[[ -z "$INDEXER_PASSWORD" ]] && { log_err "Mot de passe vide, abandon."; exit 1; }

mkdir -p /etc/grafana/provisioning/datasources

cat > "$TARGET" <<EOF
apiVersion: 1

datasources:
  - name: Wazuh-OpenSearch
    uid: wazuh-opensearch
    type: grafana-opensearch-datasource
    access: proxy
    url: ${INDEXER_URL}
    basicAuth: true
    basicAuthUser: ${INDEXER_USER}
    isDefault: true
    editable: true
    jsonData:
      flavor: opensearch
      version: "${OS_VERSION}"
      database: "wazuh-alerts-4.x-*"
      timeField: "@timestamp"
      pplEnabled: true
      tlsSkipVerify: true
      maxConcurrentShardRequests: 5
      timeInterval: "10s"
    secureJsonData:
      basicAuthPassword: ${INDEXER_PASSWORD}
EOF

chown root:grafana "$TARGET"
chmod 640 "$TARGET"

# Stop/start complet
log_info "Rechargement complet de Grafana..."
systemctl stop grafana-server
sleep 2
systemctl start grafana-server
sleep 3

if systemctl is-active --quiet grafana-server; then
  log_ok "Grafana rechargé."
else
  log_err "Grafana non démarré. Vérifie : journalctl -u grafana-server -n 20"
  exit 1
fi

log_ok "Etape 5 terminée : datasource 'Wazuh-OpenSearch' provisionné."
echo
echo "  Vérifie : Connections > Data sources > Wazuh-OpenSearch > Save & test"
echo "  Si absent : sudo systemctl restart grafana-server"
echo "  Dernier recours : sudo reboot"
