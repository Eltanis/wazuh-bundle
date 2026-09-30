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

STATIC_IP="192.x.x.x/x"
GATEWAY="192.x.x.x"
INTERFACE="enp0s3"
DNS_SERVERS="1.1.1.1 8.8.8.8"
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

configure_static_ip() {
  local iface="$1" cidr="$2" gw="$3" dns="$4"
 
  if [[ "$cidr" != */* ]]; then
    log_err "STATIC_IP doit inclure le préfixe CIDR, ex: 192.168.1.50/24 (valeur actuelle : $cidr)"
    exit 1
  fi
 
  if ! ip link show "$iface" &>/dev/null; then
    log_err "Interface '$iface' introuvable. Interfaces disponibles :"
    ip -o link show | awk -F': ' '{print "  - "$2}'
    exit 1
  fi
 
  local addr="${cidr%%/*}"
  local prefix="${cidr##*/}"
 
  if [[ -f /etc/network/interfaces ]]; then
    log_info "ifupdown détecté — écriture de la config statique dans /etc/network/interfaces"
    local netmask
    netmask="$(python3 -c "import ipaddress; print(ipaddress.IPv4Network('0.0.0.0/${prefix}').netmask)")"
 
    backup_file /etc/network/interfaces
 
    # Retire toute ancienne définition (dhcp ou static) de cette interface,
    # pour éviter un conflit de doublon (deux "auto iface", etc.).
    if grep -qE "^(auto|iface) ${iface}( |\$)" /etc/network/interfaces 2>/dev/null; then
      awk -v ifc="$iface" '
        BEGIN{skip=0}
        /^auto / && $2==ifc {skip=1; next}
        /^iface / && $2==ifc {skip=1; next}
        skip==1 && /^[[:space:]]/ {next}
        skip==1 && /^$/ {skip=0; next}
        skip==1 {skip=0}
        {print}
      ' /etc/network/interfaces > /etc/network/interfaces.new
      mv /etc/network/interfaces.new /etc/network/interfaces
      log_warn "Ancienne définition de $iface retirée de /etc/network/interfaces"
    fi
 
    # Ajoute la nouvelle définition à la fin du fichier
    cat >> /etc/network/interfaces <<EOF
 
auto ${iface}
iface ${iface} inet static
    address ${addr}
    netmask ${netmask}
    gateway ${gw}
    dns-nameservers ${dns}
EOF
 
    ifdown "$iface" 2>/dev/null || true
    ifup "$iface"
    log_ok "ifupdown appliqué sur $iface -> $cidr (config dans /etc/network/interfaces)"
 
  else
    log_err "/etc/network/interfaces introuvable (ifupdown non détecté) — configure $iface manuellement."
    return 1
  fi
}

log_info "=== 2/5 : IP statique ==="
if [[ "$SET_STATIC_IP" == "true" ]]; then
  configure_static_ip "$INTERFACE" "$STATIC_IP" "$GATEWAY" "$DNS_SERVERS"
  NODE_IP="${STATIC_IP%%/*}"
  log_ok "IP statique active : $NODE_IP sur $INTERFACE"
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
log_info "=== 4/5 : clean ==="
cd /tmp
rm -rf "$WORK_DIR"
log_info "installation terminé et nettoyé."

log_ok "Etape 0 terminée."
echo
echo "  Wazuh Dashboard : https://${NODE_IP}"
echo "  pwd    : sudo cat $SECURE_DIR/wazuh-passwords.txt"
echo
log_warn "Ne partager JAMAIS $SECURE_DIR/ | lisible root uniquement."
