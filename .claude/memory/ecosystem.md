# Nina.fm — Mémoire Écosystème

## Repos et leurs rôles

| Repo                | Stack               | Rôle                                |
| ------------------- | ------------------- | ----------------------------------- |
| `nina.fm-backup`    | bash, systemd, Alloy | Configuration de l'hôte, sauvegardes, observabilité (Grafana Cloud) |
| `nina.fm-broadcast` | Icecast + Libretime | Programmation et diffusion webradio |
| `nina.fm-webserver` | Nginx + acme.sh     | Reverse proxy de tous les domaines, certificat wildcard |

## Conventions partagées

- Conventional Commits : `feat(icecast): change configuration`, `fix(libretime): increase upload file size`
- Squash merge sur main

## Déploiement

- Chaque repo a sa propre GitHub Actions pipeline, déclenchée par un push sur `main`
- broadcast et webserver : SSH vers le droplet puis `docker compose` ; backup : rsync puis `nina-bootstrap` en root (sudoers figé)
- Infrastructure : un seul droplet DigitalOcean (Debian trixie), partagé avec les apps

## Relations inter-repos

- Webserver défini tous les hosts pour tous les repos Nina.fm, de ce workspace (Icecast, Libretime), mais aussi du workspace apps (API, Auth, Website, FaceB, Mixtaper)
