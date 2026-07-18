#!/usr/bin/env bash
# ============================================================
# 06_import_dashboards.sh _Dashboards Grafana
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

PROV_DIR="/etc/grafana/provisioning/dashboards"
DASH_DIR="/var/lib/grafana/dashboards/wazuh"
TARGET_UID="wazuh-opensearch"
TARGET_TYPE="grafana-opensearch-datasource"

mkdir -p "$PROV_DIR" "$DASH_DIR"

# Fichier de provisioning : Grafana surveille DASH_DIR toutes les 30s
cat > "$PROV_DIR/wazuh.yaml" <<EOF
apiVersion: 1

providers:
  - name: "Wazuh Dashboards"
    orgId: 1
    folder: "Wazuh"
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: ${DASH_DIR}
EOF


JSON_COUNT=$(find "$BUNDLE_ROOT/configs/grafana/dashboards" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)

if [[ "$JSON_COUNT" -eq 0 ]]; then
  log_warn "Aucun .json trouvé dans configs/grafana/dashboards/"
  echo
  echo "  Pour utiliser ton dashboard exporté depuis Grafana :"
  echo "  1. Grafana → ton dashboard → Partager → Export → Save to file"
  echo "  2. Copie le .json dans : $BUNDLE_ROOT/configs/grafana/dashboards/"
  echo "  3. Relance ce script"
  exit 0
fi


 
fix_dashboard() {
  local src="$1"
  local dest="$2"
 
  cp "$src" "$dest"
 
  # Parcours complet du JSON — remplace toutes les références datasource
  python3 - "$dest" "$TARGET_UID" "$TARGET_TYPE" << 'PYEOF'
import sys, json, re
 
path, target_uid, target_type = sys.argv[1], sys.argv[2], sys.argv[3]
 
with open(path) as f:
    content = f.read()
 
original = content
 
# --- Approche 1 : remplacement texte brut ---
# Trouve tous les uid et noms qui ressemblent à des IDs Grafana auto-générés
# (alphanumériques, pas "wazuh-opensearch", pas "-- Grafana --")
grafana_id_pattern = re.compile(r'"([A-Z0-9]{8,})"')
found_ids = set(grafana_id_pattern.findall(content))
found_ids.discard(target_uid)
 
for gid in found_ids:
    content = content.replace(f'"name": "{gid}"', f'"uid": "{target_uid}"')
    content = content.replace(f'"uid": "{gid}"', f'"uid": "{target_uid}"')
 
# --- Approche 2 : parcours JSON structurel ---
def fix_datasource(obj):
    if isinstance(obj, dict):
        # Si c'est un objet datasource avec name ou uid étranger
        if "name" in obj and obj.get("name") not in [target_uid, "-- Grafana --", "Wazuh-OpenSearch", None]:
            name = obj["name"]
            if re.match(r'^[A-Z0-9]{8,}$', str(name)):
                obj.pop("name", None)
                obj["type"] = target_type
                obj["uid"] = target_uid
        if "uid" in obj and obj["uid"] not in [target_uid, "-- Grafana --", None]:
            uid = obj["uid"]
            if re.match(r'^[A-Z0-9]{8,}$', str(uid)):
                obj["type"] = target_type
                obj["uid"] = target_uid
        for v in obj.values():
            fix_datasource(v)
    elif isinstance(obj, list):
        for item in obj:
            fix_datasource(item)
 
try:
    data = json.loads(content)
    fix_datasource(data)
    content = json.dumps(data, indent=2, ensure_ascii=False)
except Exception as e:
    sys.stderr.write(f"[WARN] Parcours JSON échoué ({e}), texte brut appliqué.\n")
 
with open(path, "w") as f:
    f.write(content)
 
# Compte les changements
remaining = len(re.findall(r'[A-Z0-9]{16}', content))
print(f"OK")
PYEOF


  # Vérification finale avec sed — filet de sécurité
  # Remplace tout ce qui ressemble encore à un UID Grafana auto-généré
  REMAINING=$(grep -oE '"[A-Z0-9]{16}"' "$dest" | grep -v "wazuh-opensearch" | sort -u)
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    raw="${match//\"/}"
    sed -i "s|\"name\": \"${raw}\"|\"uid\": \"${TARGET_UID}\"|g" "$dest"
    sed -i "s|\"uid\": \"${raw}\"|\"uid\": \"${TARGET_UID}\"|g" "$dest"
    log_info "Filet de sécurité : '$raw' → '$TARGET_UID'"
  done <<< "$REMAINING"
 
  COUNT=$(grep -c "$TARGET_UID" "$dest" || true)
  log_ok "$(basename "$dest") : $COUNT références datasource → '$TARGET_UID'"
}
 
for json_src in "$BUNDLE_ROOT"/configs/grafana/dashboards/*.json; do
  filename="$(basename "$json_src")"
  fix_dashboard "$json_src" "$DASH_DIR/$filename"
done
 
chown -R grafana:grafana "$DASH_DIR"
chown root:grafana "$PROV_DIR/wazuh.yaml"
 
log_info "Rechargement complet de Grafana..."
systemctl stop grafana-server
sleep 2
systemctl start grafana-server
sleep 3
 
if systemctl is-active --quiet grafana-server; then
  log_ok "Etape 6 terminée : dashboards disponibles dans le dossier 'Wazuh' de Grafana."
else
  log_err "Grafana non démarré. Vérifie : journalctl -u grafana-server -n 20"
  exit 1
fi
 
