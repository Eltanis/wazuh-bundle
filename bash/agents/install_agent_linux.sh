#!/usr/bin/env bash
# ============================================================
# install_agent_linux.sh _ Installe l'agent Wazuh sur Linux
#
# Usage :
#   sudo ./install_agent_linux.sh \
#     --manager-ip 192.168.1.50 \   (exemple)
#     --role web \
#     --name web01
#
# Rôles : web | db | admin | linux
#
# Le bundle complet doit être présent sur la machine agent
# (scp ou partage réseau) pour accéder aux configs 
# et common.sh
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

usage() {

  cat <<USAGE
Usage: sudo $0 --manager-ip <IP> --role <web|db|admin|linux> --name <nom> [--group <groupe>]
 
Rôles disponibles :
  web    → surveille /var/www, logs nginx/apache
  db     → surveille /etc/mysql|postgresql, logs DB
  admin  → surveillance renforcée (bastion/jump host)
  linux  → client Linux générique
USAGE

  exit 1
}

MANAGER_IP=""; ROLE=""; AGENT_NAME=""; AGENT_GROUP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manager-ip) MANAGER_IP="$2"; shift 2 ;;
    --role)       ROLE="$2";       shift 2 ;;
    --name)       AGENT_NAME="$2"; shift 2 ;;
    --group)      AGENT_GROUP="$2";shift 2 ;;
    --h| --help) usage ;;
    *) log_err "Argument inconnu : $1"; usage ;;
  esac
done

[[ -z "$MANAGER_IP" || -z "$ROLE" || -z "$AGENT_NAME" ]] && usage

case "$ROLE" in
  web)   CONF="ossec-web.xml";   AGENT_GROUP="${AGENT_GROUP:-web-servers}" ;;
  db)    CONF="ossec-db.xml";    AGENT_GROUP="${AGENT_GROUP:-db-servers}" ;;
  admin) CONF="ossec-admin.xml"; AGENT_GROUP="${AGENT_GROUP:-admin-servers}" ;;
  linux) CONF="ossec-linux.xml"; AGENT_GROUP="${AGENT_GROUP:-linux-clients}" ;;
  *)     log_err "Rôle inconnu : $ROLE"; usage ;;
esac

CONF_SRC="$BUNDLE_ROOT/configs/agents/$CONF"
[[ -f "$CONF_SRC" ]] || { log_err "Config introuvable : $CONF_SRC"; exit 1; }

require_root

WAZUH_CONF="/var/ossec/etc/ossec.conf"
AGENT_ALREADY_INSTALLED=false

# Détection installation existante
if systemctl list-unit-files 2>/dev/null | grep -q '^wazuh-agent'; then
  AGENT_ALREADY_INSTALLED=true
  
  # Version installée
  INSTALLED_VERSION=$(dpkg -l wazuh-agent 2>/dev/null | awk '/wazuh-agent/{print $3}' | head -1 || echo "inconnue")
 
  # Manager actuellement configuré
  CURRENT_MANAGER=$(grep -oP '(?<=<address>)[^<]+' "$WAZUH_CONF" 2>/dev/null | head -1 || echo "inconnu")

  log_warn "Agent Wazuh déjà installé (version: $INSTALLED_VERSION)"
  log_warn "Manager actuel : $CURRENT_MANAGER"
  echo
 
  if [[ "$CURRENT_MANAGER" == "$MANAGER_IP" ]]; then
    # Même manager — mise à jour config uniquement
    log_info "Même manager détecté → mise à jour de la config rôle uniquement."
  else
    # Manager différent — demande confirmation
    log_warn "Manager différent détecté !"
    log_warn "  Actuel  : $CURRENT_MANAGER"
    log_warn "  Nouveau : $MANAGER_IP"
    echo
    echo "  Options :"
    echo "  1) Reconfigurer vers le nouveau manager $MANAGER_IP"
    echo "  2) Garder le manager actuel ($CURRENT_MANAGER) et juste mettre à jour le rôle"
    echo "  3) Annuler"
    echo
    read -rp "  Choix [1/2/3] : " choice
    case "$choice" in
      1)
        log_info "Reconfiguration vers $MANAGER_IP..."
        # Met à jour l'adresse du manager dans ossec.conf
        backup_file "$WAZUH_CONF"
        sed -i "s|<address>.*</address>|<address>${MANAGER_IP}</address>|g" "$WAZUH_CONF"
        fix_ossec_permissions "$WAZUH_CONF"
        # Supprime l'ancien enrollment pour forcer la réinscription
        > /var/ossec/etc/client.keys
        log_ok "Manager reconfiguré vers $MANAGER_IP"
        ;;
      2)
        log_info "Manager conservé ($CURRENT_MANAGER) — mise à jour rôle uniquement."
        MANAGER_IP="$CURRENT_MANAGER"
        ;;
      3)
        log_info "Annulé."
        exit 0
        ;;
      *)
        log_err "Choix invalide, abandon."
        exit 1
        ;;
    esac
  fi
fi
 

# Installation si absent
if [[ "$AGENT_ALREADY_INSTALLED" == "false" ]]; then
  log_info "Ajout du dépôt Wazuh..."
  apt-get install -y curl gpg 2>/dev/null || true
  curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
    | gpg --dearmor \
    | tee /usr/share/keyrings/wazuh.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
    https://packages.wazuh.com/4.x/apt/ stable main" \
    | tee /etc/apt/sources.list.d/wazuh.list > /dev/null
  apt-get update -qq

  log_info "Installation wazuh-agent (manager=$MANAGER_IP, nom=$AGENT_NAME, groupe=$AGENT_GROUP)..."
  WAZUH_MANAGER="$MANAGER_IP" \
  WAZUH_AGENT_NAME="$AGENT_NAME" \
  WAZUH_AGENT_GROUP="$AGENT_GROUP" \
    apt-get install -y wazuh-agent
fi


# Enrollment (enregistrement auprès du manager)
# Vérifie si l'agent est déjà enregistré (client.keys non vide)

if [[ ! -s /var/ossec/etc/client.keys ]]; then
  log_info "Enregistrement de l'agent auprès du manager ($MANAGER_IP)..."
  if /var/ossec/bin/agent-auth -m "$MANAGER_IP" -A "$AGENT_NAME" 2>/tmp/agent-auth.log; then
    log_ok "Agent enregistré."
  else
    log_warn "agent-auth a échoué. Vérifie : cat /tmp/agent-auth.log"
    log_warn "Si le manager exige un mot de passe d'enrollment :"
    log_warn "  /var/ossec/bin/agent-auth -m $MANAGER_IP -A $AGENT_NAME -P MOT_DE_PASSE"
  fi
else
  log_warn "client.keys déjà présent — enrollment ignoré."
fi

# Configuration en fonction du role
log_info "Application de la config rôle '$ROLE'..."
merge_into_ossec_conf "$CONF_SRC" "$WAZUH_CONF"

# Denarrage
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent
sleep 3

if systemctl is-active --quiet wazuh-agent; then
  log_ok "Agent actif — rôle: $ROLE | nom: $AGENT_NAME | manager: $MANAGER_IP"
  echo
  echo "  Vérifie la connexion côté manager :"
  echo "  sudo /var/ossec/bin/agent_control -l"
else
  log_err "Agent non démarré."
  log_err "Détails : journalctl -u wazuh-agent -n 30" 
  exit 1
fi
