# Troubleshooting — Wazuh Monitoring Bundle

Tous ces problèmes ont été rencontrés et résolus en production lors de la construction de ce bundle.

---

## wazuh-manager ne démarre pas

### Symptôme
```
wazuh-analysisd: ERROR: (1226): Error reading XML file 'etc/ossec.conf': (line 0)
```

### Cause 1 — Permissions incorrectes
Après toute modification de `ossec.conf` par un script Python, le fichier passe en `root:root` et Wazuh ne peut plus le lire.

```bash
# Diagnostic
ls -la /var/ossec/etc/ossec.conf

# Fix
sudo chown root:wazuh /var/ossec/etc/ossec.conf
sudo chmod 660 /var/ossec/etc/ossec.conf
sudo systemctl restart wazuh-manager
```

### Cause 2 — Double bloc `<ossec_config>`
Le fichier contient deux balises `<ossec_config>` — le parseur Wazuh rejette le fichier entier.

```bash
# Diagnostic
grep -n "<ossec_config\|</ossec_config" /var/ossec/etc/ossec.conf

# Fix : fusionner manuellement les deux blocs
sudo nano /var/ossec/etc/ossec.conf
# Supprime la seconde balise <ossec_config> et </ossec_config>
# déplace leur contenu avant le premier </ossec_config>
```

### Cause 3 — Double bloc `<global>`
ossec.conf ne supporte qu'un seul bloc `<global>`. Les white_list doivent être dans le premier.

```bash
grep -n "<global>\|</global>" /var/ossec/etc/ossec.conf
# Si deux occurrences → fusionner manuellement les deux blocs
```

---

## Règles custom ne chargent pas

### Symptôme
```
wazuh-analysisd: ERROR: Invalid option 'url_match' for rule '100200'
```

### Cause
`url_match` n'existe pas en Wazuh 4.x. Il faut utiliser `regex`.

```bash
sudo nano /var/ossec/etc/rules/local_rules.xml
# Remplacer <url_match>...</url_match> par <regex>...</regex>
```

### Symptôme
```
XMLERR: Element 'script' not closed. (line XX)
```

### Cause
`<script>` dans une regex est interprété comme une balise XML.

```bash
# Remplacer dans local_rules.xml :
# <script>  →  &lt;script
```

---

## Plugin OpenSearch Grafana — Failed to install plugin

### Symptôme
L'UI Grafana affiche "Failed to install plugin" sur la page OpenSearch.

### Cause
`storage.googleapis.com` (Google Cloud) est bloqué sur le réseau.

### Fix
```bash
# Vérifie le blocage
curl -v --max-time 10 https://storage.googleapis.com

# Télécharge depuis une machine avec accès internet
wget https://storage.googleapis.com/grafana-plugins-catalog/grafana-opensearch-datasource/release/2.33.1/grafana-opensearch-datasource-2.33.1.linux-amd64.zip

# Transfère et installe manuellement
scp fichier.zip user@IP_VM:/tmp/
sudo unzip /tmp/fichier.zip -d /var/lib/grafana/plugins/
sudo chown -R grafana:grafana /var/lib/grafana/plugins/grafana-opensearch-datasource
sudo systemctl restart grafana-server
```

---

## Grafana — "Not found" sur le champ Version du datasource

### Cause
Wazuh Indexer renvoie `7.10.2` (compatibilité Elasticsearch) au lieu d'un vrai numéro OpenSearch. Le plugin ne reconnaît pas ce numéro.

### Fix
Ne pas utiliser l'UI pour configurer le datasource. Utiliser le provisioning YAML (étape 5 du bundle) qui force `flavor: opensearch` et `version: "2.19.0"`.

---

## VirusTotal — exit code 4

### Symptôme
```
wazuh-integratord: ERROR: Exit status was: 4
```

### Cause
`ERR_NO_RESPONSE_VT` — le script atteint l'API mais ne reçoit pas de réponse. Souvent dû au blocage de `storage.googleapis.com` / plages Google Cloud.

### Note
Le **cache VirusTotal fonctionne quand même** pour les hash déjà connus (ex: EICAR). Seuls les fichiers inconnus nécessitent une connexion directe à l'API.

---

## SMS Africa's Talking — DeliveryFailure

### Cause
Compte en mode **sandbox**. Les SMS sandbox sont acceptés par l'API mais jamais livrés sur un vrai téléphone.

### Fix
1. Recharge le compte sur https://account.africastalking.com (Billing → Top Up)
2. Récupère la **clé API de production** (différente de la sandbox)
3. Met à jour le script :

```bash
sudo nano /usr/local/bin/wazuh-sms-alerter.py
# AT_USERNAME = "ton_vrai_username"  (plus "sandbox")
# AT_API_KEY  = "ta_cle_production"
sudo systemctl restart wazuh-sms-alerter
```

---

## Intégration custom Wazuh bloquée

### Symptôme
```
wazuh-integratord: ERROR: Invalid integration: 'mon-integration'. Not currently supported.
```

### Cause
Wazuh 4.14 n'accepte que les intégrations de sa whitelist interne : `slack`, `pagerduty`, `virustotal`, `shuffle`, `maltiverse`.

### Solution
Utiliser un daemon systemd qui surveille `alerts.json` directement (comme le fait `wazuh-sms-alerter.service` dans ce bundle).

---

## vulnerability-detection — Configuration error

### Symptôme
Wazuh manager ne démarre pas après ajout d'un bloc `<vulnerability-detector>`.

### Cause
Depuis Wazuh 4.8, le tag est `<vulnerability-detection>` (sans `-or`), et les sous-balises `<provider>` ont été supprimées.

### Fix
Ne pas ajouter ce bloc — l'installeur Wazuh 4.14 le configure correctement par défaut. Si tu dois le modifier :

```xml
<vulnerability-detection>
  <enabled>yes</enabled>
  <index-status>yes</index-status>
  <feed-update-interval>60m</feed-update-interval>
</vulnerability-detection>
```
