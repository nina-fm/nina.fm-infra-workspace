# Nina.fm — Mémoire Écosystème

## Repos et leurs rôles

| Repo                | Stack               | Rôle                                |
| ------------------- | ------------------- | ----------------------------------- |
| `nina.fm-broadcast` | Icecast + Libretime | Programmation et diffusion webradio |
| `nina.fm-webserver` | Nginx               | Server web + hosts prod             |

## Conventions partagées

- Conventional Commits : `feat(icecast): change configuration`, `fix(libretime): increase upload file size`
- Squash merge sur main

## Déploiement

- Chaque repo a sa propre GitHub Actions pipeline
- Push sur `main` → build Docker → déploiement DigitalOcean
- Infrastructure : serveur Debian sur DigitalOcean

## Relations inter-repos

- Webserver défini tous les hosts pour tous les repos Nina.fm, de ce workspace (Icecast, Libretime), mais aussi du workspace apps (API, Auth, Website, FaceB, Mixtaper)
