#!/usr/bin/env bash
# 01_configure_fim.sh — FIM realtime + active-response + règles custom
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
require_root

log_info "Injection du bloc FIM dans ossec.conf..."
merge_into_ossec_conf "$BUNDLE_ROOT/configs/manager/fim.xml"

log_info "Déploiement des règles custom..."
deploy_local_rules "$BUNDLE_ROOT/configs/manager/local_rules_bundle.xml"

restart_wazuh_manager

log_ok "Etape 1 terminée : FIM realtime actif sur /var/www, /etc/nginx, /etc/apache2, /etc/ssh"
echo
echo "  Test FIM : sudo touch /var/www/test.txt"
echo "  Résultat : sudo grep 'test.txt' /var/ossec/logs/alerts/alerts.json | tail -2"
