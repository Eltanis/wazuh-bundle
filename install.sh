#!/usr/bin/env bash
# ============================================================
# install.sh — Menu principal du Wazuh Monitoring Bundle
# A lancer SUR LE SERVEUR MANAGER : sudo ./install.sh
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MGR="$SCRIPT_DIR/bash/manager"
source "$SCRIPT_DIR/bash/lib/common.sh"

header() {
  clear
  echo "+------------------------------------------------------+"
  echo "+                                                      +"
  echo "+           WAZUH MONITORING BUNDLE — v1.2             +"
  echo "+   => Stack : Wazuh 4.14 + Grafana + Alerting Sys.    +"
  echo "+                                                      +"
  echo "+------------------------------------------------------+"
  echo
}

menu() {
  cat <<'EOF'
  -- Boîte d'installation ------------------------- 
  0) Wazuh        : Installation SSH + Wazuh all-in-one.
  1) FIM          : Surveillance fichiers + règles custom.
  2) VT           : Intégration VirusTotal.
  3) Grafana      : Installation Grafana
  4) Plugin       : OpenSearch datasource pour Grafana
  5) Link Grafana : Connexion Grafana => Wazuh Indexer
  6) DashBoard    : Import dashboard(s)
  7) Email        : Alertes email via Gmail SMTP

  -- API optionel ----------------------------------
  8) SMS       : Alertes SMS via Africa's Talking

  -- AGENTS ----------------------------------------
  a) Aide : ajouter un agent Linux ou Windows

  0x) Quitter
EOF
}

run() {
  local script="$1" label="$2"
  echo
  log_info "-- $label --"
  if bash "$script"; then
    log_ok "$label : OK"
  else
    log_err "$label : ECHEC => corrige avant de continuer."
    pause
    return 1
  fi
  pause
}

agent_help() {
  cat <<EOF

  -- AJOUTER UN AGENT LINUX -----------------------------
  Copie le bundle sur la machine cible, puis :

    cd bash/agents
    sudo ./install_agent_linux.sh \\
      --manager-ip IP_MANAGER \\
      --role web|db|admin|linux \\
      --name nom-machine

  -- AJOUTER UN AGENT WINDOWS ---------------------------
  PowerShell (en Administrateur) :

    .\\install_agent_windows.ps1 \\
      -ManagerIP IP_MANAGER \\
      -AgentName NOM-PC \\
      -AgentGroup windows-clients

  -- RÔLES DISPONIBLES -----------------------------------
  web    => surveille /var/www, logs nginx/apache
  db     => surveille /etc/mysql|postgresql, logs DB
  admin  => surveillance renforcée (bastion/jump host)
  linux  => client Linux générique

EOF
  pause
}

require_root

while true; do
  header
  menu
  echo
  read -rp "  Choix : " choice

  case "$choice" in
    0)  run "$MGR/00_base_setup.sh"          "SSH + Wazuh" ;;
    1)  run "$MGR/01_configure_fim.sh"       "FIM + règles custom" ;;
    2)  run "$MGR/02_configure_vt.sh"        "VirusTotal" ;;
    3)  run "$MGR/03_install_grafana.sh"     "Grafana" ;;
    4)  run "$MGR/04_opensearch_plugin.sh"   "Plugin OpenSearch" ;;
    5)  run "$MGR/05_provision_datasource.sh" "Datasource Grafana" ;;
    6)  run "$MGR/06_import_dashboards.sh"   "Dashboards Grafana" ;;
    7)  run "$MGR/07_email_alerts.sh"        "Alertes Email" ;;
    8)  run "$MGR/08_sms_alerts.sh"          "Alertes SMS" ;;
    a)  agent_help ;;
    0x) echo "Au revoir."; exit 0 ;;
    *)  echo "  Choix invalide."; sleep 1 ;;
  esac
done
