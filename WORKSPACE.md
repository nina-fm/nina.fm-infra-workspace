# Nina.fm Infra Workspace

Workspace Claude Code de l'infrastructure Nina.fm : un dépôt de configuration (CLAUDE.md, commandes, plans, mémoire) qui accueille les dépôts d'infra, chacun avec son propre git.
Ce repo ne contient **pas** de code d'infrastructure : les dépôts ci-dessous sont ignorés par son `.gitignore` (`nina.fm-*/`).

---

## Écosystème

Tout tourne sur un seul droplet DigitalOcean (Debian trixie, `flux.nina.fm`), aux côtés des apps du workspace `nina.fm-apps-workspace` (api, auth, website, faceb, mixtaper).

| Repo                | Contenu                          | Rôle                                                                                                                                                        | Déploiement (push sur `main`)                                         |
| ------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `nina.fm-backup`    | bash, systemd, cron, Alloy       | Configuration de l'hôte : rotation des logs, journald, Docker, ménage hebdomadaire, sauvegardes, Alloy → Grafana Cloud (métriques, logs, mémoire par service), dashboards | `deploy-system.yml` : rsync, puis `nina-bootstrap` en root (sudoers figé) |
| `nina.fm-broadcast` | Icecast + LibreTime (Docker)     | Programmation et diffusion de la webradio                                                                                                                   | `deploy-icecast.yml`, `deploy-libretime.yml`                          |
| `nina.fm-webserver` | nginx (Docker) + acme.sh         | Reverse proxy de tous les domaines `*.nina.fm` (apps comprises), certificat wildcard Let's Encrypt (DNS OVH)                                               | `deploy-nginx.yml`                                                    |

Observabilité : Grafana Cloud, stack `ninafm.grafana.net` — voir le README de `nina.fm-backup` (section « Alloy et métriques mémoire »). Plans validés, à exécuter : `.claude/plans/`.

---

## GitHub

Toutes les opérations GitHub (PRs, merges, issues, réglages des dépôts) passent par le CLI `gh`, authentifié sur le poste (`gh auth status`), comme dans le workspace apps depuis avril 2026.

Ce workspace n'a pas de serveur MCP. L'ancien `mcp.json` n'a jamais été chargé (il lui manquait le point de `.mcp.json`) et il a été supprimé le 11 septembre 2026 : son serveur GitHub (`@modelcontextprotocol/server-github`) est abandonné, et `gh` couvre le besoin. Les outils natifs de Claude Code atteignent déjà tous les dépôts depuis la racine du workspace, sans serveur `filesystem`.

---

## Structure de ce Workspace

```
~/Sites/nina/nina.fm-infra-workspace   ← Ce repo (nina.fm-infra-workspace)
├── CLAUDE.md                          ← Règles communes, lues en cascade depuis chaque repo
├── WORKSPACE.md                       ← Ce fichier
├── .gitignore                         ← Ignore les repos de code (nina.fm-*/)
├── setup.sh                           ← Installation sur une nouvelle machine
├── .claude/
│   ├── commands/                      ← /task, /epic, /pr, /review
│   ├── memory/                        ← Mémoire persistante (ecosystem.md)
│   └── plans/                         ← Plans validés, à exécuter en session fraîche
│
├── nina.fm-backup/                    ← Son propre git
├── nina.fm-broadcast/                 ← Son propre git
└── nina.fm-webserver/                 ← Son propre git
```

Les dépôts d'infra n'ont pas de `.claude/` propre : ils utilisent les commandes et le `CLAUDE.md` du workspace. Leur qualité est vérifiée en CI (shellcheck, validations de config), pas par des hooks locaux.

---

## Installation sur une Nouvelle Machine

```bash
# 1. Cloner le workspace
git clone git@github.com:nina-fm/nina.fm-infra-workspace.git ~/Sites/nina/nina.fm-infra-workspace
cd ~/Sites/nina/nina.fm-infra-workspace

# 2. Cloner les repos d'infra (nina.fm-backup, nina.fm-broadcast, nina.fm-webserver)
bash setup.sh

# 3. Authentifier le CLI GitHub (PRs, merges, issues)
gh auth login        # puis vérifier : gh auth status
```

Les secrets de déploiement vivent dans les GitHub Secrets de chaque dépôt, pas sur le poste : aucun `.env` n'est nécessaire pour travailler sur l'infra.

---

## Commandes Disponibles

Définies dans `.claude/commands/` du workspace :

| Commande              | Description                                                                                                                                                                                                                                                                |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/task "description"` | Analyse le codebase et crée un plan d'implémentation détaillé. Accepte un prefix Conventional Commit optionnel qui détermine le type de branche créée : `/task "feat: ..."`, `/task "fix: ..."`, `/task "refactor: ..."`, etc. Sans prefix, `feat` est utilisé par défaut. |
| `/epic "description"` | Explore et décompose une grande feature en sous-features actionnables                                                                                                                                                                                                      |
| `/pr`                 | Checks qualité finaux + création de la PR                                                                                                                                                                                                                                  |
| `/review`             | Review IA du diff → commentaire structuré sur la PR                                                                                                                                                                                                                        |

## Workflow Agentique (rappel)

```
1. /epic "grande feature"          (optionnel, si périmètre large)
   → Décomposition en sous-features → tu valides

2. /task "description de la feature"
   → Plan d'implémentation → tu valides / corriges

3. Agent implémente
   → Vérifications locales (shellcheck, validations) puis CI

4. /pr
   → Qualité finale + création PR(s) sur les repos impactés

5. /review
   → Review IA du diff → commentaire structuré sur la PR

6. Tu valides la PR → merge (squash) → déploiement automatique (GitHub Actions)
```
