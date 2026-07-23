# Wazuh Monitoring Bundle

Stack SOC clé en main : **Wazuh 4.14 + Grafana + Alertes SMS/Email**

Surveillance d'un parc hétérogène (serveurs web, bases de données, postes Windows/Linux) avec détection d'intrusion, intégrité des fichiers (FIM), analyse VirusTotal et alertes temps réel.

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2F13-blue)
![Wazuh](https://img.shields.io/badge/Wazuh-4.14-red)

---

## Démarrage rapide

```bash
# Sur le serveur manager (Debian 12/13)
git clone <repo> wazuh-bundle.v-siem.d
cd wazuh-bundle.v-siem.d
chmod +x install.sh bash/manager/*.sh bash/agents/install_agent_linux.sh
sudo ./install.sh
```

Le menu propose chaque étape séparément ou l'installation complète (option 9).

---

## Ce que fait le bundle

| Étape | Action |
|---|---|
| 0 | SSH durci + Wazuh all-in-one (manager + indexer + dashboard) |
| 1 | FIM realtime sur `/var/www`, `/etc/nginx`, règles custom (brute force, attaques web) |
| 2 | Intégration VirusTotal (scan hash des fichiers modifiés) |
| 3 | Installation Grafana |
| 4 | Plugin OpenSearch pour Grafana (avec fallback manuel si réseau bloqué) |
| 5 | Datasource Grafana → Wazuh Indexer (contournement bug version 7.10.2) |
| 6 | Import dashboards |
| 7 | Alertes email via Postfix + Gmail SMTP |
| 8 | Alertes SMS via Africa's Talking (daemon systemd) |

---

## Ajouter un agent

Le bundle complet doit être présent sur la machine agent
(scp ou partage réseau) pour accéder aux configs et common.sh

**Linux :**
```bash
sudo ./bash/agents/install_agent_linux.sh \
  --manager-ip 192.168.1.50 \
  --role web \
  --name web01
```

sudo ./bash/agents/install_agent_linux.sh 

Rôles disponibles : `web` | `db` | `admin` | `linux`

**Windows (PowerShell admin) :**
```powershell
.\bash\agents\install_agent_windows.ps1 `
  -ManagerIP 192.168.1.50 `
  -AgentName PC-COMPTA `
  -AgentGroup windows-clients
```

---

## Structure

```
wazuh-bundle/
├── install.sh                    ← menu principal
├── bash/
│   ├── lib/common.sh             ← fonctions partagées
│   ├── manager/00→08_*.sh        ← scripts d'installation
│   └── agents/
│       ├── install_agent_linux.sh
│       └── install_agent_windows.ps1
├── configs/
│   ├── manager/                  ← XML/templates config Wazuh
│   ├── agents/                   ← configs FIM par rôle
│   └── grafana/                  ← datasource + dashboards
└── docs/
    ├── INSTALL.md
    └── TROUBLESHOOTING.md
```
## Prérequis

- Debian 12 ou 13 (recommandé)
- 4 Go RAM minimum (Wazuh Indexer = 1.5 Go seul)
- Accès internet (ou transfert manuel pour le plugin Grafana)
- Compte Africa's Talking pour les SMS
- App Password Gmail pour les emails

---

## Notes de production

- **VirusTotal** : clé gratuite = 4 req/min. Régénère ta clé après tout test public.
- **SMS Africa's Talking** : passe en compte production pour la livraison réelle (sandbox = API OK mais SMS non livrés).
- **Permissions ossec.conf** : toujours `root:wazuh 660` — le bundle le corrige automatiquement.
- **Plugin Grafana** : si `storage.googleapis.com` est bloqué, télécharge le zip depuis une autre machine et utilise le fallback manuel (étape 4).
