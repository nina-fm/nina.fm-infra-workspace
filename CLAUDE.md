# CLAUDE.md — nina.fm-infra-workspace

Guidelines globales pour tous les repos du workspace infra Nina.fm.
Ces règles s'appliquent à tous les repos sauf mention contraire.

> Ce fichier est lu en **cascade** par Claude depuis n'importe quel repo du workspace.
> Voir `WORKSPACE.md` pour l'infrastructure, l'écosystème et le workflow git.

---

## Workflow Git & GitHub

- **GitHub** : tout passe par le CLI `gh` (PRs, merges, issues, réglages) — ce workspace n'a pas de serveur MCP
- **Merger une PR** : `gh pr merge --squash --delete-branch <numéro>` — jamais `git merge` + `git push`
- **Squash merge** sur `main` — un commit par PR, historique propre
- **Pas de changeset** : les repos infra n'ont ni `package.json` ni versionnement — l'historique, c'est le message du squash (Conventional Commits) et la description de la PR
- **Sync avant de tirer une branche** : `git pull origin main` avant `git checkout -b`
- **Suppression automatique des branches** au merge (`delete_branch_on_merge` activé sur tous les repos)
- **Mémoire projet** : consigner les conventions dans `CLAUDE.md` (workspace ou repo) — jamais dans la mémoire user (`~/.claude/`) sauf préférences vraiment personnelles
