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
- **Workflows d'un même push** : ils tournent en parallèle, `needs:` ne lie que les jobs d'un même workflow. Un déploiement qui doit attendre la validation l'appelle (`uses: ./.github/workflows/validate.yml`, `workflow_call`) puis `needs: validate` (nina.fm-backup#15). Le statut d'un run peut rester `in_progress` plusieurs minutes après la fin de ses jobs : lire les jobs (`gh run view <id> --json jobs`)

## Serveur

- **Lecture seule** par `ninsh "<cmd>"` ; `sudo` y demande un mot de passe, il se lance par Vincent. Aucun secret en sortie (`.env`, `docker inspect` Env, config Alloy, `account.conf` d'acme) : comparer par hash, ne sortir que les noms de clés
- **Pas de `docker run` d'une image absente** pour un test : l'image reste sur le serveur. Tester depuis un conteneur existant (`docker exec … getent hosts`, `wget`)
- **`userland-proxy: false`** (nina.fm-backup#14) : un port publié sur `127.0.0.1` passe par le NAT, plus aucun `docker-proxy`, et rien n'écoute sur `::1`. nginx joint les services par `127.0.0.1`, jamais `localhost`, qu'il essaie d'abord en `::1` (nina.fm-webserver#1)
- **Redémarrer Docker** coupe le flux environ 1 min, et relance tous les conteneurs en même temps, sans tenir compte des `depends_on`. Il passe par « Deploy system config » (`restart_docker`), après accord : demander à Raph (LibreTime) avant tout ce qui touche la diffusion
- **Mesurer un gain** : comparer des fenêtres de même durée, aux mêmes heures, sur Grafana Cloud (`ninafm.grafana.net`, depuis Chrome : `/api/datasources/proxy/uid/grafanacloud-prom/api/v1/query`, `avg_over_time(…[21h:1m] @ <ts>)`). Avant d'attribuer une variation, lister les commits de **tous** les repos sur la fenêtre : la baisse de CPU de 45 % à 22 % du 22/10 venait d'un index LibreTime, pas de nos réglages. Les métriques par cgroup (`nina_cgroup_*`) n'existent que depuis le 22/10/2026 10 h UTC
- **`nina-network` est partagé par toutes les stacks** (apps et LibreTime) : chaque nom de service y devient un alias DNS, et `postgres`, `redis`, `api` y désignent plusieurs conteneurs. Joindre par `container_name`, et laisser une base hors de ce réseau (nina.fm-auth#17)
