# Observabilité de l'infra nina.fm — sondes, flux, CPU, logs des conteneurs, dashboard d'ensemble, alertes

> **Statut** : rédigé le 2026-09-11 ; décisions de Vincent intégrées le même jour (voir « Décisions prises »). À exécuter dans une session fraîche.
> **Prérequis** : nina.fm-backup#6 (Alloy repris en CD + métriques mémoire) mergée et déployée, et environ une semaine de données mémoire (elles servent à calibrer les seuils d'alerte).
> Repo principal : `nina.fm-backup`. La PR 2 touche aussi nina.fm-faceb, nina.fm-website, nina.fm-auth et diun (voir PR 2). Aucune modification n'a encore été faite.

## Décisions prises (Vincent, 2026-09-11)

| Sujet | Décision |
| --- | --- |
| Logs des conteneurs vers Loki | **driver de logs journald** : Alloy expédie déjà le journal, aucun privilège en plus (PR 2) |
| Vue externe | **UptimeRobot**, qui surveille déjà `api.nina.fm/health`, est **étendu au flux uniquement**. Les autres sites sont surveillés par les sondes Grafana |
| Émissions en direct | rarement ou jamais : **retiré du plan** |
| Simulation de déploiement | **versionnée**, avec un job CI (PR 0) |
| Postgres / Redis | rien à trancher : **hors périmètre**. La mémoire des bases est déjà suivie par cgroup, et les métriques internes (connexions, cache) ne servent qu'en cas de lenteur avérée |

## Pour la session qui exécutera ce plan

**Accès et sécurité** (inchangés depuis `alloy-metriques-memoire.md`)
- Commandes serveur : `ninsh "<cmd>"`, lecture seule sans sudo ; les commandes sudo sont lancées par Vincent (préfixe `!`). `vincent` est dans le groupe `docker`.
- **Ne jamais afficher de secret.** Les comparer par empreinte, les mesurer avec `wc -c`.
- Tester un collecteur sur le serveur sans rien installer : `ninsh 'd=$(mktemp -d); cat > $d/s.sh; NINA_METRICS_DIR=$d bash $d/s.sh; cat $d/*.prom; rm -rf $d' < scripts/<script>.sh`.

**Revérifier d'abord** (faits relevés le 2026-09-11) :
```
ninsh 'curl -s 127.0.0.1:12345/metrics | grep -E "^alloy_config_(hash|last_load_successful)"; ls -la /var/lib/nina-metrics; ls /etc/systemd/system/alloy.service.d; test -e /etc/alloy/config.alloy && echo "config.alloy ENCORE LA"; curl -s -o /dev/null -w "icecast %{http_code}\n" 127.0.0.1:8000/status-json.xsl; echo | openssl s_client -servername nina.fm -connect nina.fm:443 2>/dev/null | openssl x509 -noout -enddate; command -v jq || echo "jq absent"; docker info --format "{{.LoggingDriver}}"; free -m'
```
Attendu :
- `alloy_config_last_load_successful 1` ;
- `memory.prom`, `.containers` et `.memstats.lock` dans `/var/lib/nina-metrics` ;
- seul `nina.conf` dans les drop-ins, et plus de `config.alloy` ;
- Icecast répond 200 ;
- certificat `notAfter` au 19 nov. 2026, ou plus tard s'il a été renouvelé ;
- jq absent ;
- driver de logs `json-file`.

Dans Grafana Cloud : les séries `nina_cgroup_*` arrivent et `nina-memory` est importé.

**Faits vérifiés le 2026-09-11**

- **Sites.** 8 noms servis par le conteneur nginx de cette machine : `nina.fm` (301 vers `www`), `www`, `auth`, `prog`, `flux`, `mixtaper` et `faceb` (200 sur `/`), et `api`, qui répond 404 sur `/` mais 200 sur `/health`. `auth.nina.fm/hello` répond aussi 200. Sondés depuis le serveur, les noms repassent par l'IP publique puis nginx, en 40 à 100 ms.
- **Certificat.** Un seul wildcard Let's Encrypt `*.nina.fm` couvre les 8 noms. Il est géré par **acme.sh + DNS OVH** (déployé par nina.fm-webserver dans `/var/nina/.ssl/nina.fm/`) et expire le **19 nov. 2026**.
  - **Renouvellement confirmé le 2026-09-11** : le crontab root lance `17 7 * * * /bin/sh /var/nina/.acme.sh/acme.sh --cron --home /var/nina/.acme.sh > /var/log/acme-cron.log`. Le certificat actuel a été écrit le 21 août à 7:18, donc par cette tâche. Le journal (`/var/log/acme-cron.log`, lisible sans sudo) montre un passage chaque matin ; prochain renouvellement annoncé par acme.sh : **2026-10-19T05:18Z**.
  - Cette tâche vit dans le crontab root, pas dans un dépôt ; une ancienne version commentée traîne juste au-dessus. Voir « Hors périmètre ».
- **UptimeRobot** : il fait un seul `HEAD api.nina.fm/health`, toutes les 5 minutes environ (d'après la signature de son user agent dans `/var/log/nginx/api.nina.fm_access.log`). Aucun autre site n'apparaît dans les logs.
- **Flux vu de l'extérieur.**
  - `HEAD https://flux.nina.fm/nina.mp3` renvoie **400** : c'est inutilisable, et un `GET` ne se terminerait jamais.
  - `https://flux.nina.fm/status-json.xsl` est public et ne contient `"listenurl":".../nina.mp3"` que lorsque la source est connectée. Un moniteur UptimeRobot **mot-clé** sur ce fichier vérifie donc « flux joignable **et** alimenté ».
- **Blackbox.** `prometheus.exporter.blackbox` a été validé et exécuté avec Alloy 1.14.1 (config ci-dessous). Chaque cible produit **26 séries brutes**, dans un job `integrations/blackbox/<nom>`. `probe_ssl_earliest_cert_expiry` fonctionne.
- **Icecast.** `http://127.0.0.1:8000/status-json.xsl`, avec un seul point de montage `nina.mp3`.
  - `icestats.source` est un **objet** quand il n'y a qu'un point de montage, une **liste** sinon, et **disparaît** quand la source se déconnecte.
  - Champs utiles : `listeners`, `listener_peak`, `audio_info` (le débit y est, `bitrate=128`, car le champ `bitrate` est vide), `stream_start_iso8601`, `listenurl` et `title`.
- **cgroups v2** : `cpu.stat` (`usage_usec`), `memory.pressure`, `cpu.pressure` et `io.pressure` (`some|full … total=<µs>`), ainsi que `io.stat`. Tous sont lisibles sans root.
- **Serveur** : `jq` absent, `python3` 3.13 présent.
- **nina-api `/metrics`** (441 séries, envoyées sans liste blanche) : `http_requests_total` et `http_request_duration_seconds` (histogramme), avec les labels `app="nina-fm-api"`, `method`, `route` (18 routes) et `status_code`, plus `nodejs_*` et `process_*`. Ses logs applicatifs vont directement dans Loki (winston-loki) ; sa sortie Docker est vide.
- **Logs des conteneurs** : **21 Mo sur 24 h**, dont **18 Mo pour `libretime-nginx`**, 1,9 Mo pour libretime-legacy et 0,5 Mo pour icecast. Les conteneurs nina-* n'écrivent quasiment rien.
  - Sur une heure, `libretime-nginx` a produit 6 084 lignes, dominées par du sondage répété : `GET /api/v2/shows/5858` (1 280/h), `/api/v2/show-instances/6912` (1 280/h) et `/api/live-info` (1 203/h).
- **Docker et logs.**
  - `daemon.json` (json-file, 10m × 3) a été posé le 2 sept. à 21:26, et dockerd redémarré à 21:46 : **le démon l'applique**. Mais seuls les conteneurs **créés depuis** en profitent. 15 conteneurs sur 20 n'ont aucun plafond : leur recréation reste due, même sans ce plan.
  - 5 conteneurs définissent un bloc `logging:` dans leur compose, **qui prime sur `daemon.json`** :
    - diun : `/var/nina/diun`, install manuelle du 19 fév. 2026, versionnée nulle part ;
    - nina-faceb : dépôt nina.fm-faceb ;
    - nina-website : dépôt nina.fm-website ;
    - supertokens-core et supertokens-postgres : dépôt nina.fm-auth.
  - Emplacement des stacks sur le serveur :

    | Répertoire | Dépôt |
    | --- | --- |
    | `/var/nina/libretime`, `/var/nina/icecast` | nina.fm-broadcast |
    | `/var/nina/webserver` | nina.fm-webserver |
    | `/var/nina/api/{deploy,infra}` | nina.fm-api |
    | `/var/nina/{faceb,website,mixtaper}/deploy` | leurs dépôts |
    | `/var/nina/auth` | nina.fm-auth |
    | `/var/nina/diun` | aucun |

- **journald** (`system/journald.conf.d/99-nina.conf`) : `SystemMaxUse=500M`, `SystemMaxFileSize=50M`.
- **Bruit cron, mesuré** : chaque tâche cron génère 4 lignes de journal par exécution. D'où la règle : **une seule ligne cron par minute pour tous les collecteurs**.
- **Budget** : 900 séries actives sur 10 000 après #6.
- **Offre gratuite, logs** : le plan apps annonce 10 Go/mois. **À revérifier** ; après le filtre de la PR 2, on ajoute environ 100 Mo par mois.

**Existant à ne pas dupliquer** : `nina.fm-apps-workspace/.claude/plans/monitoring.md`, phase 2 (UptimeRobot, Sentry, Loki via winston-loki, dashboard applicatif de nina-api). Ici on ne fait que l'infra ; nina-api n'y apparaît qu'en résumé, avec un lien vers le dashboard applicatif.

**Conventions de nina.fm-backup** (lire le README en entier avant de commencer)
- Commentaires en français **sans accents**.
- `needs_apply`, valider avant d'installer, déploiement rouge explicite plutôt que panne silencieuse, pas de one-shot, rien qui s'accumule.
- Git : `git pull origin main`, une branche par PR, `/pr`, et c'est Vincent qui merge (squash).

**Principes de ce chantier**
- Toute nouvelle série passe par une liste blanche.
- Rien de résident en plus d'Alloy.
- Les collecteurs suivent le modèle de `nina-memstats.sh` : flock, écriture atomique `.tmp.*`, nettoyage des orphelins, `NINA_METRICS_DIR` surchargeable, muet quand tout va bien.
- Une ligne cron par minute pour tous les collecteurs ; chacun publie l'horodatage de son dernier passage.
- On ne teste **jamais** une alerte en coupant le vrai service : on utilise l'aperçu de règle et la notification de test de Grafana.
- Toute évolution du bootstrap passe par la simulation (PR 0) avant la PR.

## Découpage

| PR | Contenu | Dépend de |
| --- | --- | --- |
| 0 — Simulation en CI | le banc de simulation de #6 versionné et lancé par la CI | #6 |
| 1 — Collecte | CPU et pression mémoire par cgroup, collecteur Icecast, métriques ménage et backup, sondes blackbox | PR 0 |
| 2 — Logs des conteneurs | `daemon.json` passé en journald, labels et filtre dans Alloy, fin de la troncature des logs JSON, blocs `logging:` retirés dans 4 endroits, **fenêtre de maintenance** | PR 1 (les auditeurs servent à choisir l'heure) |
| 3 — Dashboards | `nina-overview.json` (nouveau), `nina-memory.json` (CPU et pression) | PR 1 ; PR 2 pour le panneau des logs |
| 4 — Alertes + Grafana piloté par la CI | règles et contact en JSON, workflow `deploy-grafana.yml` | PR 1 |

Étape manuelle, indépendante et faisable dès maintenant : **UptimeRobot sur le flux** (voir « Étapes manuelles »).

## PR 0 — Simulation de déploiement en CI (`ci/simulation-deploiement`)

Pour #6, une réplique systemd du serveur a trouvé un bug réel : la preuve était vérifiée trop tôt après un redémarrage. Ni la CI ni les tests sur la prod ne l'avaient vu. Le banc est sauvegardé à côté de ce plan, dans **`.claude/plans/sim-deploiement/`** : `Dockerfile`, `mock.py`, `mock.service`, `driver.sh` (mode d'emploi en tête) et `config-install-manuelle.masked.alloy`.

- Le déplacer dans `nina.fm-backup/tests/sim/`. Commentaires en ASCII ; `driver.sh` passe dans shellcheck, `mock.py` reste minimal.
- **Réécrire S0** : il rejouait l'install manuelle d'avant #6, qui n'existe plus. S0 devient une **reconstruction sur droplet neuf**, c'est-à-dire le bootstrap sur un trixie vierge, qui installe alloy depuis le dépôt apt. C'est le chemin de reconstruction promis par le README, jamais testé jusqu'ici. Garder `config-install-manuelle.masked.alloy` n'a d'intérêt que pour l'historique : le supprimer.
- Scénarios à garder ou adapter :
  - premier déploiement : identifiants valides, identifiants refusés (401) ;
  - rejeu, reload, rotation du token, drop-in parasite, config invalide ;
  - identifiants absents ou incomplets, Alloy arrêté ;
  - réécrire en conséquence les scénarios qui supposaient l'install manuelle (retour automatique).
- Le faux Grafana Cloud (`mock.py`) renvoie le code lu dans `/etc/mock-status`. La seule différence avec la prod : les URLs Grafana du staging pointent vers lui.
- **Job CI** : workflow `simulate.yml`, sur les PRs qui touchent `system/**`, `scripts/**` ou `tests/sim/**`. Il lance `docker build`, puis `docker run --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock`, puis `driver.sh`, qui échoue au moindre FAIL. **À valider en premier** : que systemd démarre dans un conteneur privilégié sur `ubuntu-latest` (cgroup v2). Durée : 6 à 8 minutes par exécution.
- Pièges connus :
  - `groupadd -f nina`, sinon la validation logrotate refuse `nina-icecast` ;
  - `usermod -aG adm,systemd-journal alloy`, sinon Alloy ne lit pas le journal et la preuve des logs échoue ;
  - avec un 401, la preuve peut échouer côté Loki avant Prometheus : les deux messages sont valides.

## PR 1 — Collecte (`feat/observabilite-collecte`)

### 1.1 CPU et pression mémoire dans `scripts/nina-memstats.sh`
On lit les mêmes cgroups dans la même boucle, sans aucun appel en plus.
- `nina_cgroup_cpu_seconds_total` (counter), à partir de `cpu.stat usage_usec`.
- `nina_cgroup_memory_pressure_seconds_total{level="some|full"}` (counter), à partir du `total=` de `memory.pressure` : **qui attend** la mémoire, complément de « qui la consomme ».
- Microsecondes vers secondes sans flottant bash : `printf '%d.%06d' $((v/1000000)) $((v%1000000))`.
- On garde le nom du script (le renommer imposerait de nettoyer l'ancien fichier sur le serveur, pour un gain cosmétique) ; l'en-tête et le README préciseront qu'il couvre aussi le CPU.
- Pas de `cpu.pressure` ni d'`io.pressure` par cgroup pour l'instant (+74 séries chacun) ; on les ajoutera si les données le justifient.

### 1.2 `scripts/nina-icecast.sh` (nouveau)
- `curl --max-time 5 http://127.0.0.1:8000/status-json.xsl`, analysé avec **jq**, que le bootstrap installe à l'étape [1] comme logrotate. Pourquoi jq plutôt que python3 : on reste en bash sous shellcheck, et le pic mémoire est d'environ 3 Mo contre 10 Mo ou plus pour Python.
- `ICECAST_MOUNTS="nina.mp3"` en tête, surchargeable. Un point de montage **attendu** et absent vaut 0, au lieu de faire disparaître la série.
- Normalisation objet ou liste : `[.icestats.source] | flatten | map(select(. != null))`. Le nom du point de montage est la fin de `listenurl`.
- Séries :
  - `nina_icecast_up` : 1 si le JSON répond, 0 sinon. Le fichier est écrit même quand Icecast est tombé.
  - `nina_icecast_source_connected{mount}`
  - `nina_icecast_listeners{mount}`
  - `nina_icecast_listener_peak{mount}`
  - `nina_icecast_bitrate_bits_per_second{mount}`, tiré de `audio_info`
  - `nina_icecast_stream_start_timestamp_seconds{mount}`, via `date -d` : `changes()` compte les reconnexions de la source
  - `nina_icecast_last_run_timestamp_seconds`
- Même squelette que `nina-memstats.sh`.

### 1.3 Ménage et backup
- À la fin de `nina-housekeeping.sh`, seulement en cas de succès : `housekeeping.prom` avec `nina_housekeeping_last_success_timestamp_seconds` et `nina_housekeeping_reclaimed_bytes`.
- À la fin de `backup-nina-to-s3.sh` : `backup.prom` avec `nina_backup_last_success_timestamp_seconds`. Le backup étant désactivé (#2), la série n'existe pas. Le dashboard l'affiche comme « aucun backup (voir #2) », ce qui rend l'arbitrage visible. Pas d'alerte tant que #2 n'est pas tranché.

### 1.4 Planification (`system/cron.d/nina-maintenance`)
```
* * * * * root { /var/nina/scripts/nina-memstats.sh; /var/nina/scripts/nina-icecast.sh; } 2>&1 | logger -t nina-metrics
```
Une seule session cron par minute. Requête Loki du README : `|= "nina-metrics"`.

### 1.5 Sondes blackbox (`system/alloy/config.alloy`)
Syntaxe validée le 2026-09-11 :
```
prometheus.exporter.blackbox "nina_sites" {
  config = "{ modules: { http_2xx: { prober: http, timeout: 5s, http: { preferred_ip_protocol: ip4, follow_redirects: true } } } }"

  target {
    name    = "www"
    address = "https://www.nina.fm/"
    module  = "http_2xx"
  }
  // idem : apex (https://nina.fm/), api (https://api.nina.fm/health),
  // auth (https://auth.nina.fm/hello), prog, flux, mixtaper, faceb (/)
}

prometheus.scrape "nina_sites" {
  targets    = prometheus.exporter.blackbox.nina_sites.targets
  forward_to = [prometheus.relabel.nina_sites.receiver]
}

prometheus.relabel "nina_sites" {
  forward_to = [prometheus.remote_write.metrics_service.receiver]
  rule {
    source_labels = ["__name__"]
    regex         = "up|probe_success|probe_http_status_code|probe_duration_seconds|probe_ssl_earliest_cert_expiry"
    action        = "keep"
  }
  rule {
    source_labels = ["job"]
    regex         = "integrations/blackbox/(.*)"
    target_label  = "site"
  }
}
```
- On passe de 26 à 5 séries par cible, soit 40 pour 8 sites.
- `api` et `flux` sont sondés aussi, pour le dashboard ; ce sont UptimeRobot qui alertent pour eux (PR 4).
- **Limite, à écrire dans le README** : des sondes lancées depuis la machine détectent une panne d'application, de nginx ou de certificat, mais pas une panne réseau ou DNS, ni la mort du droplet. Ce dernier cas est couvert par UptimeRobot (api, flux) et par l'alerte « plus aucune donnée ».

### 1.6 Bootstrap, CI, README
- **bootstrap** : [1] installer jq s'il est absent ; [4] installer `nina-icecast.sh` et le lancer une fois ; aucun changement de logique à l'étape Alloy.
- **validate.yml** :
  - le test memstats vérifie les séries CPU et pression ;
  - nouveau test `nina-icecast.sh` sur des fichiers d'exemple servis par `python3 -m http.server`, avec 4 cas : un point de montage (objet), plusieurs (liste), aucune source, Icecast injoignable. Chaque sortie passe `promtool`, et on vérifie que `source_connected` et `up` valent 0 dans les bons cas.
- **simulate.yml** (PR 0) : l'arborescence factice doit fournir `cpu.stat` et `memory.pressure`.
- **README** : les nouvelles séries, la limite des sondes et le budget.

### 1.7 Budget

| Source | Séries |
| --- | --- |
| Après #6 | 900 |
| CPU par cgroup | +37 |
| Pression mémoire some/full | +74 |
| Icecast (1 point de montage) | +7 |
| Ménage + backup | +3 |
| Sondes (8 × 5) | +40 |
| **Total** | **≈ 1 060 / 10 000** |

## PR 2 — Logs des conteneurs via journald (`feat/logs-conteneurs-journald`)

**Pourquoi journald**
- Alloy expédie déjà le journal vers Loki : aucun nouveau composant, aucun privilège en plus. L'autre voie, le socket Docker, équivaut à donner un accès root à Alloy.
- Le plafond du journal (500 Mo) borne le disque pour tous les conteneurs d'un coup, au lieu des plafonds json-file que 15 conteneurs sur 20 n'ont pas encore.
- `docker logs` continue de fonctionner avec ce driver.

### 2.1 nina.fm-backup
- **`system/docker/daemon.json`** :
  ```json
  { "log-driver": "journald", "log-opts": { "tag": "{{.Name}}", "labels": "com.docker.compose.project" } }
  ```
  - `tag` met le nom du conteneur dans `SYSLOG_IDENTIFIER` (par défaut, c'est l'id court).
  - `labels` ajoute le projet compose au journal. **Le nom exact du champ produit est à vérifier** dans la réplique.
  - `validate.yml` vérifie aujourd'hui `json-file` et `max-size` : l'adapter.
- **Alloy** (`journal_module`, dans le `loki.relabel` interne) :
  - `__journal_container_name` devient `container` ;
  - le champ du projet compose devient `stack`.
  - Toutes les lignes des conteneurs ont `unit="docker.service"` : le label `container` est ce qui les distingue.
- **Filtre avant Loki** (`loki.process`, `stage.drop`) : on écarte les 200 du sondage de `libretime-nginx`, soit la regex `"GET /api/(v2/(shows|show-instances)/[0-9]+|live-info) HTTP/[0-9.]+" 200` pour `container="libretime-nginx"`. On passe d'environ 18 à environ 2 Mo par jour. Les erreurs et les autres requêtes restent. Le journal local garde tout.
- **`nina-housekeeping.sh`** : retirer la troncature des logs JSON de plus de 100 Mo, **dans la même PR**. Elle n'a plus d'objet et laisserait du code mort. Mettre à jour le README (sections Docker et ménage) et le bloc « ACTION MANUELLE RESTANTE » du bootstrap, qui parle de json-file.
- **Réplique** (PR 0) : installer `docker.io` dans l'image. Vérifier qu'un conteneur de test apparaît dans le journal avec `CONTAINER_NAME`, `SYSLOG_IDENTIFIER` et le champ du projet. Vérifier les labels Loki avec un `loki.echo` temporaire, qui affiche les entrées et leurs labels sur la sortie d'Alloy.

### 2.2 Blocs `logging:` qui priment sur `daemon.json`
Les retirer, pour que ces conteneurs héritent du défaut du démon (une seule source de vérité). Une PR par dépôt :
- nina.fm-faceb (`nina-faceb`) ;
- nina.fm-website (`nina-website`) ;
- nina.fm-auth (`supertokens-core`, `supertokens-postgres`).

**diun** : `/var/nina/diun/docker-compose.yml` appartient à root et n'est versionné nulle part. Vincent le modifie à la main (sudo) pendant la fenêtre. À terme, le reprendre dans nina.fm-backup comme Alloy : c'est un sujet à part.

### 2.3 Fenêtre de maintenance (le flux coupe plusieurs fois quelques secondes)
**Avant**
- Choisir l'heure grâce à l'historique de `nina_icecast_listeners` (PR 1), au creux d'audience.
- Pour **chaque stack**, vérifier en lecture seule que `docker compose -f <fichier> config -q` passe sans variable manquante. Certains déploiements CI peuvent injecter des variables absentes du serveur : une recréation à la main les perdrait.
- Relever l'état de référence : `systemctl --failed`, `docker ps` et les statuts health.

**Pendant**
1. PR 2 de nina.fm-backup mergée et déployée : `daemon.json` est posé, mais pas encore lu.
2. `deploy-system.yml` en `workflow_dispatch`, avec `restart_docker=true` : le nouveau défaut s'applique aux conteneurs **créés ensuite**.
3. Recréer les stacks (`docker compose -f … up -d --force-recreate`, ou le déploiement du dépôt concerné), des moins sensibles aux plus sensibles :
   - diun, puis auth, puis api infra et deploy ;
   - faceb, website et mixtaper (merger leurs PRs `logging:` à ce moment-là) ;
   - webserver ;
   - en dernier, **libretime et icecast** : ce sont eux qui coupent le flux.
4. Après chaque stack : type de driver `journald` (`docker inspect -f '{{.HostConfig.LogConfig.Type}}'`), `docker logs` qui répond, conteneurs healthy, flux à l'antenne.

**Après**
- Comparer à l'état de référence.
- Dans Loki : `{container="libretime-nginx"}` arrive sans les lignes de sondage.
- Journal : `journalctl --disk-usage` reste sous 500 Mo.

**Retour arrière** : `daemon.json` de nouveau en json-file, redémarrage de Docker, puis recréation des stacks.

## PR 3 — Dashboards (`feat/observabilite-dashboards`)

### 3.1 `grafana/nina-overview.json` — « Nina.fm — Infra »
Deux entrées, `DS_PROMETHEUS` et `DS_LOKI`. **Adapter le contrôle de `validate.yml`**, qui n'accepte aujourd'hui que `${DS_PROMETHEUS}`.

| Rangée | Panneaux (PromQL de référence) |
| --- | --- |
| **État** (tuiles) | flux en ligne `max(nina_icecast_source_connected{mount="nina.mp3"})` (1 = en ligne, 0 = coupé) · auditeurs `sum(nina_icecast_listeners)` · sites OK `count(probe_success == 1)` sur `count(probe_success)` · certificat `(min(probe_ssl_earliest_cert_expiry) - time()) / 86400` jours · disque `/` · RAM disponible · swap · âge du dernier relevé (memstats, icecast) · dernier ménage · dernier backup (valeur absente affichée « aucun (voir #2) ») |
| **Flux** | auditeurs et pic dans le temps · source connectée (state timeline) · reconnexions `changes(nina_icecast_stream_start_timestamp_seconds[1h])` |
| **Sites** | `probe_success` par `site` (state timeline) · `probe_duration_seconds` · code HTTP |
| **Hôte** | CPU `node_cpu_seconds_total` par mode · charge · RAM et swap · E/S disque · réseau · PSI. Lien vers les dashboards Linux de l'intégration Grafana Cloud plutôt que de les refaire |
| **Conteneurs et services** | CPU `topk(10, sum by (name) (rate(nina_cgroup_cpu_seconds_total[$__rate_interval])))` (1 vCPU, donc directement une fraction du CPU) · pression mémoire `rate(nina_cgroup_memory_pressure_seconds_total{level="some"}[$__rate_interval])` · lien vers `nina-memory` |
| **nina-api (résumé)** | req/s `sum(rate(http_requests_total{app="nina-fm-api"}[$__rate_interval]))` · part de 5xx · p95 `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{app="nina-fm-api"}[5m])))` · lien vers le dashboard applicatif |
| **Logs** | erreurs du journal `{job="integrations/node_exporter", level=~"err|crit|alert|emerg"}` · logs d'un conteneur choisi dans une variable `container` (après la PR 2) |

### 3.2 `grafana/nina-memory.json`
Ajouter « Qui attend la mémoire » (pression `some` et `full` par service) et un panneau CPU par service. Garder l'uid `nina-memory`.

### 3.3 Import
Import manuel tant que la PR 4 n'est pas faite. Vérifier qu'aucun panneau n'est vide.

## PR 4 — Alertes et Grafana piloté par la CI (`feat/observabilite-alertes`)

### 4.1 Étape manuelle unique (Vincent)
- Dans Grafana Cloud, Administration → Service accounts : créer un compte avec le rôle **Editor** et générer un token.
- Poser le **secret** `GRAFANA_SA_TOKEN` et la **variable** `GRAFANA_URL` (`https://<stack>.grafana.net`) sur `nina-fm/nina.fm-backup`.
- Sans eux, le workflow sort en rouge explicite.

### 4.2 `.github/workflows/deploy-grafana.yml`
Il se déclenche sur `main` pour les chemins `grafana/**`, et en `workflow_dispatch`. **À vérifier à l'exécution** sur l'API Grafana Cloud.
1. Dossier `nina-infra` : `POST /api/folders`, idempotent sur l'uid.
2. uid des sources de données : `GET /api/datasources` (types `prometheus` et `loki`).
3. Dashboards : `POST /api/dashboards/import` avec `overwrite: true`, `folderUid`, et `inputs` qui associent `DS_PROMETHEUS` et `DS_LOKI` à leurs uid.
4. Alertes : `grafana/alerts/*.json`, un fichier par règle avec un uid stable, envoyé par `PUT /api/v1/provisioning/alert-rules/<uid>` (ou `POST` si nouvelle). La provenance reste « API » : règles **verrouillées dans l'interface**, git est la source de vérité.
5. Contact : e-mail `infos@nina.fm` (même canal que diun et le ménage), via `/api/v1/provisioning/contact-points`.
6. **Politique de notification : attention.** `PUT /api/v1/provisioning/policies` remplace **tout l'arbre**. Relire d'abord l'existant et n'ajouter qu'une route `team="nina-infra"`.
7. Relire chaque dashboard et chaque règle, et comparer au dépôt.

Dans `validate.yml` : contrôler avec jq la structure des règles (uid, titre, condition, requête), sans uid de source de données en dur.

### 4.3 Règles
Les seuils mémoire sont à calibrer avec la semaine de données de #6.

| Alerte | Condition | Pendant | Pourquoi |
| --- | --- | --- | --- |
| Site en panne | `probe_success{site!~"api\|flux"} == 0`, par `site` | 5 min | api et flux sont couverts par UptimeRobot (vue externe) : pas de double e-mail |
| Certificat | `min(probe_ssl_earliest_cert_expiry) - time() < 21 j` | 1 h | acme.sh renouvelle à 30 jours de l'échéance : à 21 jours, le renouvellement a échoué depuis une semaine |
| Disque | `/` rempli à plus de 85 % | 30 min | l'alerte du ménage (80 %) ne passe que le dimanche |
| Mémoire | RAM disponible < 150 Mo, ou PSI mémoire `full` > 5 % | 15 min | à calibrer |
| OOM kill | `increase(node_vmstat_oom_kill[10m]) > 0` | 0 | |
| Collecte figée | âge de `nina_memstats_last_run_timestamp_seconds` ou de `nina_icecast_last_run_timestamp_seconds` > 5 min | 5 min | sinon, les autres alertes se taisent sans bruit |
| **Plus aucune donnée** | `up{job="integrations/node_exporter"}` absent (état *No data* = alerte) | 10 min | Alloy tombé alors que le serveur répond. Si c'est le droplet qui meurt, UptimeRobot le voit aussi |
| Ménage non passé | âge de `nina_housekeeping_last_success_timestamp_seconds` > 8 jours | | |

Pas d'alerte Grafana « flux coupé » : le moniteur mot-clé d'UptimeRobot la donne déjà, et de l'extérieur. Le collecteur Icecast sert au dashboard (auditeurs, reconnexions) et au diagnostic.

Les alertes applicatives (taux de 5xx de nina-api, par exemple) relèvent du plan apps, phase 2.

## Étapes manuelles (Vincent)
1. **UptimeRobot, flux**, faisable dès maintenant : moniteur **Keyword** sur `https://flux.nina.fm/status-json.xsl`, qui alerte si le mot-clé `nina.mp3` est **absent**, à l'intervalle le plus court de l'offre. Vérifier que l'offre gratuite propose ce type de moniteur. Le monitor api existant reste tel quel.
2. ~~**acme.sh** : confirmer où tourne le renouvellement~~ — fait le 2026-09-11 (crontab root, tous les jours à 7:17).
3. **PR 2** : fenêtre de maintenance, modification à la main du compose de diun (sudo).
4. **PR 4** : compte de service et token Grafana.

## Hors périmètre
- **Postgres et Redis** : les modules existent dans Alloy, mais demandent un utilisateur en lecture seule par base. À ouvrir seulement en cas de lenteur avérée.
- **Émissions en direct** : peu ou pas utilisées. Si besoin un jour, `https://prog.nina.fm/api/live-info` (public) donne la source à l'antenne (`source_enabled`) ; `/api/v2/stream/state` demande une clé.
- État des healthchecks Docker : il faudrait interroger Docker chaque minute, ce que #6 vient d'éviter.
- Dashboard applicatif de nina-api : plan apps.
- Reprise de diun dans nina.fm-backup, comme Alloy.
- Sortir la tâche acme.sh du crontab root pour la versionner, par exemple dans le déploiement de nina.fm-webserver (qui gère déjà `/var/nina/.acme.sh`), et supprimer la ligne commentée. Même logique que la ligne de sauvegarde sortie du crontab root par nina.fm-backup. Sans urgence : l'alerte certificat (PR 4) couvre un renouvellement raté.
- **Piste d'optimisation mémoire, vue en passant** : libretime-api, le plus gros consommateur (environ 236 Mo), reçoit environ 2 700 requêtes de sondage par heure (`/api/v2/shows/…`, `/show-instances/…`, `/api/live-info`). Identifier qui sonde (nina-api via `STREAM_API_URL`, ou les lecteurs des visiteurs) et mettre ces réponses en cache pourrait permettre de réduire les workers gunicorn. À traiter avec les optimisations issues de #6.

## Vérification

**PR 0** : le job `simulate` est vert sur une PR de test, et rouge si l'on casse volontairement la preuve (vérifier que le banc attrape bien un bug, pas seulement qu'il passe).

**PR 1**
1. En local :
   - shellcheck et `alloy validate` ;
   - `nina-icecast.sh` sur les 4 fichiers d'exemple, sorties passées à `promtool` ;
   - `nina-memstats.sh` sur l'arborescence factice.
2. Sur le serveur, en lecture seule : les deux collecteurs lancés dans un répertoire temporaire, puis `promtool`. Valeurs cohérentes : auditeurs comme dans `status-json`, CPU croissant d'un passage à l'autre.
3. Job `simulate` vert.
4. Après le merge : `deploy-system` vert. Dans Explore : `probe_success` pour les 8 `site`, `nina_icecast_listeners`, `nina_cgroup_cpu_seconds_total`, et un budget d'environ 1 060 séries.

**PR 2**
- Simulation avec Docker dans la réplique (champs du journal, labels Loki via `loki.echo`).
- Fenêtre déroulée comme en 2.3.
- Après : tous les conteneurs en `journald`, état de référence retrouvé, `libretime-nginx` dans Loki sans les lignes de sondage, journal sous 500 Mo.

**PR 3** : dashboards importés, aucun panneau vide, chiffres cohérents avec `status-json` et `openssl`.

**PR 4**
1. Le workflow pousse dashboards et règles, la relecture est identique au dépôt, et les règles sont verrouillées.
2. Notification de test reçue sur `infos@nina.fm`.
3. Chaque règle testée avec l'**aperçu**, **sans couper de service réel**.
4. La politique de notification existante est intacte (comparer avant et après).
