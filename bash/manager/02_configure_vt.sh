#!/usr/bin/env bash
# ============================================================
# 02_configure_vt.sh _Intégration VirusTotal
# Injecte le bloc <integration> dans ossec.conf
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

echo "=== Intégration VirusTotal ==="
echo "Clé API gratuite : https://www.virustotal.com/gui/join-us"
echo "Limite gratuite  : 4 requêtes/min, 500/jour"
echo
read -rp "Collé votre clé API VirusTotal ici : " VT_API_KEY

if [[ -z "$VT_API_KEY" ]]; then
  log_err "Clé vide, abandon."
  exit 1
fi

# Vérifie que l-intégration n'est pas déjà présente
if grep -q "<name>virustotal</name>" /var/ossec/etc/ossec.conf 2>/dev/null; then
  log_warn "Intégration VirusTotal déjà présente dans ossec.conf."
  read -rp "Mettre à jour la clé API ? [o/N] " confirm
  [[ "$confirm" =~ ^[oOyY]$ ]] || exit 0
  # Supprime l-ancien bloc avant d-injecter le nouveau
  python3 - "$VT_API_KEY" <<'PYEOF'
import sys, re
key = sys.argv[1]
path = "/var/ossec/etc/ossec.conf"
with open(path) as f:
    content = f.read()
content = re.sub(
    r'\s*<integration>\s*<name>virustotal</name>.*?</integration>',
    '',
    content,
    flags=re.DOTALL
)
with open(path, "w") as f:
    f.write(content)
print("Ancien bloc supprimé.")
PYEOF
  fix_ossec_permissions /var/ossec/etc/ossec.conf
fi

TMP="$(mktemp)"
cp "$BUNDLE_ROOT/configs/manager/virustotal.xml.template" "$TMP"
replace_placeholder "$TMP" "__VT_API_KEY__" "$VT_API_KEY"

log_info "Injection du bloc VirusTotal dans ossec.conf..."
merge_into_ossec_conf "$TMP"
rm -f "$TMP"

restart_wazuh_manager

log_ok "Etape 2 terminée : intégration VirusTotal active."
echo
echo "  Test : sudo python3 -c \\"
echo "    open('/var/www/eicar.txt','w').write('X5O!P%@AP[4\PZX54(P^)7CC)7}\\\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\\\$H+H*')\""
echo "  Résultat attendu : rule 100300 level 15 dans alerts.json"
echo
log_warn "Si exit code 4 dans integrations.log : storage.googleapis.com bloqué sur ton réseau."
log_warn "Le cache VT fonctionne quand même pour les hash connus (ex: EICAR)."
