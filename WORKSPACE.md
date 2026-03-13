# Nina.fm Infra Workspace

Workspace de configuration Claude Code pour l'écosystème infrastructure de Nina.fm.
Ce repo ne contient **pas** de code applicatif — uniquement la config Claude (CLAUDE.md, MCP, hooks, skills, memory).

---

## Écosystème

| Repo                | Stack                | Rôle                                      |
| ------------------- | -------------------- | ----------------------------------------- |
| `nina.fm-broadcast` | Icecast + Libretime  | Programmation et diffusion de la webradio |
| `nina.fm-webserver` | SolidJS + SolidStart | App de création de mixtapes               |

---

## MCP Servers

Configurés dans `.mcp.json` :

| MCP          | Rôle                                                                      |
| ------------ | ------------------------------------------------------------------------- |
| `filesystem` | Accès à `~/Sites/nina/nina.fm-infra-workspace` pour navigation cross-repo |
| `github`     | Branches, PRs, reviews (nécessite `GITHUB_PERSONAL_ACCESS_TOKEN`)         |

---

## Structure de ce Workspace

```
~/Sites/nina/nina.fm-infra-workspace   ← Ce repo (nina.fm-infra-workspace)
├── WORKSPACE.md                       ← Ce fichier
├── .gitignore                         ← Ignore les repos de code
├── .mcp.json                          ← Config MCP partagée
├── setup.sh                           ← Script d'installation sur nouvelle machine
└── .claude/
    └── memory/                        ← Mémoire persistante (cross-session)

nina.fm-broadcast/                           ← Repo NestJS (son propre git)
├── CLAUDE.md
└── .claude/
    ├── commands/                      ← Skills disponibles dans ce repo
    │   ├── task.md                    ← /task — plan d'implémentation
    │   ├── epic.md                    ← /epic — décomposition feature
    │   ├── pr.md                      ← /pr — qualité + création PR
    │   └── review.md                  ← /review — review IA
    ├── settings.json                  ← Hooks qualité (eslint .ts, type-check avant commit)
    ├── settings.local.json
    └── memory/
        ├── architecture.md
        ├── migrations.md
        └── workflow.md

nina.fm-webserver/                      ← Repo SolidJS (son propre git)
├── CLAUDE.md
└── .claude/
    ├── commands/                      ← Skills disponibles dans ce repo
    │   ├── task.md                    ← /task — plan d'implémentation
    │   ├── epic.md                    ← /epic — décomposition feature
    │   ├── pr.md                      ← /pr — qualité + création PR
    │   ├── review.md                  ← /review — review IA
    │   └── sync-types.md              ← /sync-types — regénère types API
    ├── settings.json                  ← Hooks qualité (eslint .ts/.tsx, type-check avant commit)
    ├── settings.local.json
    ├── worktrees/                     ← Git worktrees (Claude Code)
    └── memory/
        ├── architecture.md
        └── workflow.md
```

---

## Installation sur une Nouvelle Machine

```bash
# 1. Cloner le workspace (crée ~/Sites/nina/nina.fm-infra-workspace avec la config)
mkdir -p ~/Sites/nina/nina.fm-infra-workspace
git clone git@github.com:YOUR_ORG/nina.fm-infra-workspace.git ~/Sites/nina/nina.fm-infra-workspace

# 2. Cloner les repos de code
cd ~/Sites/nina/nina.fm-infra-workspace
git clone git@github.com:YOUR_ORG/nina.fm-broadcast.git
git clone git@github.com:YOUR_ORG/nina.fm-webserver.git

# 3. Configurer les variables d'environnement
cp nina.fm-broadcast/.env.example nina.fm-broadcast/.env
# → Éditer les fichiers .env avec les vraies valeurs

# 4. Configurer le GITHUB_PERSONAL_ACCESS_TOKEN pour le MCP GitHub
export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxxx
# → Ajouter à ~/.zshrc ou ~/.bashrc pour persistance

# 5. Installer les MCPs (la première fois)
npx -y @modelcontextprotocol/server-filesystem --help
npx -y @modelcontextprotocol/server-github --help
```

---

## Commandes Disponibles

Disponibles dans chaque repo via `.claude/commands/` :

| Commande              | Description                                                                                                                                                                                                                                                                |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/task "description"` | Analyse le codebase et crée un plan d'implémentation détaillé. Accepte un prefix Conventional Commit optionnel qui détermine le type de branche créée : `/task "feat: ..."`, `/task "fix: ..."`, `/task "refactor: ..."`, etc. Sans prefix, `feat` est utilisé par défaut. |
| `/epic "description"` | Explore et décompose une grande feature en sous-features actionnables                                                                                                                                                                                                      |
| `/pr`                 | Checks qualité finaux + création de la PR                                                                                                                                                                                                                                  |
| `/review`             | Review IA du diff → commentaire structuré sur la PR                                                                                                                                                                                                                        |
| `/sync-types`         | Regénère les types API depuis l'OpenAPI (mixtaper + faceb uniquement)                                                                                                                                                                                                      |

## Workflow Agentique (rappel)

```
1. /epic "grande feature"          (optionnel, si périmètre large)
   → Décomposition en sous-features → tu valides

2. /task "description de la feature"
   → Plan d'implémentation → tu valides / corriges

3. Agent implémente
   → Hooks qualité : lint + type-check automatiques à chaque édition

4. /pr
   → Qualité finale + création PR(s) sur les repos impactés

5. /review
   → Review IA du diff → commentaire structuré sur la PR

6. Tu valides la PR → merge → déploiement automatique (GitHub Actions)
```
