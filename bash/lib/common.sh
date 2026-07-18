#!/usr/bin/env bash
#common.sh — Fonctions partagées du bundle Wazuh Monitoring
# Usage : source "$(dirname "$0")/../lib/common.sh"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[FAIL]${NC} $*" >&2; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_err "Ce script doit être lancé avec sudo... mieux en mode root"
    exit 1
  fi
}

pause() {
  read -rp "Appuie sur Entrée pour continuer..." _
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local bak="${f}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$f" "$bak"
    log_info "Sauvegarde : $bak"
  fi
}


# Fixe les permissions ossec.conf après toute modification
# (root:root après écriture Python = wazuh-manager ne peut plus lire)
fix_ossec_permissions() {
  local f="${1:-/var/ossec/etc/ossec.conf}"
  chown root:wazuh "$f"
  chmod 660 "$f"
  log_ok "Permissions ossec.conf : root:wazuh 660"
}


# Insère un bloc XML juste avant </ossec_config>
# Vérifie les doublons, fixe les permissions après écriture
merge_into_ossec_conf() {
  local additions_file="$1"
  local target="${2:-/var/ossec/etc/ossec.conf}"

  [[ -f "$additions_file" ]] || { log_err "Fichier introuvable : $additions_file"; return 1; }
  [[ -f "$target" ]]         || { log_err "ossec.conf introuvable : $target"; return 1; }

  backup_file "$target"

  python3 - "$target" "$additions_file" <<'PYEOF'
import sys

target, additions = sys.argv[1], sys.argv[2]

with open(target) as f:
    content = f.read()
with open(additions) as f:
    add = f.read().strip()

marker = "</ossec_config>"
if marker not in content:
    sys.stderr.write("ERREUR : marqueur </ossec_config> introuvable\n")
    sys.exit(1)

if add in content:
    print("INFO : bloc déjà présent, aucune modification.")
    sys.exit(0)

# Insère avant le DERNIER </ossec_config> (évite les doubles blocs)
last = content.rfind(marker)
content = content[:last] + "\n" + add + "\n\n" + marker + content[last+len(marker):]

with open(target, "w") as f:
    f.write(content)

print("Bloc ajouté dans " + target)
PYEOF

  # Permissions systématiquement corrigées après écriture
  fix_ossec_permissions "$target"
}

deploy_local_rules() {
  local src="$1"
  local dest="${2:-/var/ossec/etc/rules/local_rules_bundle.xml}"

  [[ -f "$src" ]] || { log_err "Fichier introuvable : $src"; return 1; }

  backup_file "$dest"
  cp "$src" "$dest"
  chown wazuh:wazuh "$dest" 2>/dev/null || true
  chmod 640 "$dest"
  log_ok "Règles custom déployées : $dest"
}

replace_placeholder() {
  local file="$1"
  local placeholder="$2"
  local value="$3"
  sed -i "s|${placeholder}|${value}|g" "$file"
}

restart_wazuh_manager() {
  log_info "Redémarrage wazuh-manager..."
  systemctl restart wazuh-manager
  sleep 3
  if systemctl is-active --quiet wazuh-manager; then
    log_ok "wazuh-manager actif"
  else
    log_err "wazuh-manager n'a pas démarré"
    log_err "Détails : journalctl -xeu wazuh-manager --no-pager | tail -20"
    return 1
  fi
}

restart_grafana() {
  log_info "Redémarrage grafana-server..."
  systemctl restart grafana-server
  sleep 2
  if systemctl is-active --quiet grafana-server; then
    log_ok "grafana-server actif"
  else
    log_err "grafana-server n'a pas démarré"
    log_err "Détails : journalctl -xeu grafana-server --no-pager | tail -20"
    return 1
  fi
}
