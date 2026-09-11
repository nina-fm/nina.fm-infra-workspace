#!/usr/bin/env bash
# Scenarios de deploiement, joues en root dans le conteneur ninasim.
#   /repo : le depot nina.fm-backup (lecture seule)
#   /s    : ce repertoire (sim-deploiement), en lecture seule
#
#   docker build -t ninasim .
#   docker run -d --name ninasim --privileged --cgroupns=private \
#     --tmpfs /run --tmpfs /run/lock -v <depot>:/repo:ro -v <ce repertoire>:/s:ro ninasim
#   docker exec ninasim bash /s/driver.sh
#
# Ecrit pour la migration de nina.fm-backup#6 (install manuelle -> nina.alloy) :
# S0 rejoue l etat du serveur AVANT #6. Pour les evolutions suivantes, S0 doit
# partir de l etat reel apres #6 (voir le plan observabilite-infra.md, PR 0).
set -u
FAILS=0
ST=/home/deployer/nina.fm-backup
MOCK=http://127.0.0.1:9999
pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
check() { local d="$1"; shift; if "$@"; then pass "$d"; else fail "$d"; fi; }
scen() { echo; echo "=== $*"; }

m()        { curl -fsS --max-time 5 http://127.0.0.1:12345/metrics 2>/dev/null; }
run_hash() { m | sed -n 's/^alloy_config_hash{.*sha256="\([0-9a-f]*\)".*/\1/p'; }
started()  { systemctl show alloy -p ActiveEnterTimestamp --value; }
wait_hash() { # <hash attendu> : 90 s au plus
  local i; for i in $(seq 1 45); do [[ "$(run_hash)" == "$1" ]] && return 0; sleep 2; done; return 1; }

stage() {
  rm -rf "${ST}/system" "${ST}/scripts"
  mkdir -p "${ST}"
  cp -a /repo/system /repo/scripts "${ST}/"
  # Seule difference avec la prod : Grafana Cloud remplace par le faux.
  sed -i -e "s#https://prometheus-prod-65-prod-eu-west-2.grafana.net/api/prom/push#${MOCK}/api/prom/push#" \
         -e "s#https://logs-prod-012.grafana.net/loki/api/v1/push#${MOCK}/loki/api/v1/push#" \
         "${ST}/system/alloy/config.alloy"
  chown -R deployer: "${ST}"
}
creds() { # comme la CI : par stdin, umask 077, proprietaire deployer
  printf 'GRAFANA_CLOUD_PROM_USER=%s\nGRAFANA_CLOUD_LOKI_USER=%s\nGRAFANA_CLOUD_TOKEN=%s\n' "$1" "$2" "$3" \
    | su deployer -c "umask 077 && cat > ${ST}/alloy.env"
}
boot() { # comme la CI : installe la copie root puis l'appelle
  install -m 0700 -o root -g root "${ST}/system/bootstrap.sh" /usr/local/sbin/nina-bootstrap
  /usr/local/sbin/nina-bootstrap "${ST}" > /tmp/boot.log 2>&1
  RC=$?
  echo "  (bootstrap rc=${RC})"
}
services_ok() { systemctl is-active -q cron systemd-journald mock && [[ -z "$(systemctl --failed --no-legend)" ]]; }

systemctl is-system-running --wait >/dev/null 2>&1
echo "systemd : $(systemctl is-system-running)"

# --------------------------------------------------------------------------
scen "S0  replique de l'install manuelle du 27 mars"
# Comme sur le serveur (et comme en CI) : nina-icecast utilise le groupe nina.
groupadd -f nina
# remotecfg retire de la replique : le faux serveur ne parle pas le protocole
# Fleet Management, et Alloy refuse alors de demarrer.
awk '/^remotecfg \{/{skip=1} !skip{print} skip&&/^\}/{skip=0}' /s/config-install-manuelle.masked.alloy \
  | sed -e "s#https://prometheus-prod-65-prod-eu-west-2.grafana.net/api/prom/push#${MOCK}/api/prom/push#" \
        -e "s#https://logs-prod-012.grafana.net/loki/api/v1/push#${MOCK}/loki/api/v1/push#" \
        -e 's#username = <MASQUE>#username = "1234567"#' \
        -e 's#password = <MASQUE>#password = sys.env("GCLOUD_RW_API_KEY")#' \
  > /etc/alloy/config.alloy
systemctl reset-failed alloy 2>/dev/null
chmod 0644 /etc/alloy/config.alloy
install -d /etc/systemd/system/alloy.service.d
printf '[Service]\nEnvironment="GCLOUD_RW_API_KEY=ancien-token"\nEnvironment="GCLOUD_FM_COLLECTOR_ID=x"\n' \
  > /etc/systemd/system/alloy.service.d/env.conf
chmod 0600 /etc/systemd/system/alloy.service.d/env.conf
# Comme sur le serveur : alloy lit le journal.
usermod -aG adm,systemd-journal alloy
echo 204 > /etc/mock-status
systemctl daemon-reload && systemctl restart alloy
OLD_HASH="$(sha256sum /etc/alloy/config.alloy | cut -d' ' -f1)"
check "l'ancienne install tourne sur config.alloy" wait_hash "${OLD_HASH}"
check "sans dependre de quoi que ce soit du depot" test ! -e /etc/alloy/nina.alloy
check "aucune unite en echec au depart" services_ok

# --------------------------------------------------------------------------
scen "S1  premier deploiement, identifiants refuses par Grafana Cloud (401)"
echo 401 > /etc/mock-status
stage; creds 1234567 7654321 mauvais-token; boot
check "deploiement rouge" test "${RC}" -ne 0
check "cause : identifiants refuses (Prometheus ou Loki)" grep -qE "preuve en echec : (echantillons refuses|lignes de journal rejetees)" /tmp/boot.log
grep -E "preuve en echec|retour a l'install|Retour automatique" /tmp/boot.log | sed 's/^/        | /'
check "le reste du bootstrap est alle au bout ([7/7])" grep -q '\[7/7\]' /tmp/boot.log
check "config.alloy conserve" test -f /etc/alloy/config.alloy
check "env.conf conserve" test -f /etc/systemd/system/alloy.service.d/env.conf
check "retour automatique annonce" grep -q "Retour automatique a l'installation manuelle" /tmp/boot.log
check "nina.conf retire" test ! -e /etc/systemd/system/alloy.service.d/nina.conf
check "alloy.env retire du staging" test ! -e "${ST}/alloy.env"
check "autres services intacts" services_ok

# --------------------------------------------------------------------------
scen "S2  apres le retour automatique : l'install manuelle tourne comme avant"
echo 204 > /etc/mock-status
check "alloy tourne sur config.alloy" test "$(run_hash)" = "${OLD_HASH}"
check "et envoie de nouveau (echantillons en hausse)" bash -c '
  a=$(curl -s 127.0.0.1:12345/metrics | awk "/^prometheus_remote_storage_samples_total/{s+=\$NF} END{printf \"%.0f\", s}")
  sleep 70
  b=$(curl -s 127.0.0.1:12345/metrics | awk "/^prometheus_remote_storage_samples_total/{s+=\$NF} END{printf \"%.0f\", s}")
  [ "$b" -gt "$a" ]'

# --------------------------------------------------------------------------
scen "S3  premier deploiement, identifiants valides"
stage; creds 1234567 7654321 bon-token; boot
check "deploiement vert" test "${RC}" -eq 0
grep -E "preuve :|  - /etc|alloy redemarre|hold" /tmp/boot.log | sed 's/^/        | /'
NEW_HASH="$(sha256sum /etc/alloy/nina.alloy | cut -d' ' -f1)"
check "alloy tourne sur nina.alloy" test "$(run_hash)" = "${NEW_HASH}"
check "config.alloy supprime" test ! -e /etc/alloy/config.alloy
check "env.conf supprime" test ! -e /etc/systemd/system/alloy.service.d/env.conf
check "seul nina.conf reste dans alloy.service.d" test "$(ls /etc/systemd/system/alloy.service.d)" = "nina.conf"
check "nina.env root:alloy 0640" test "$(stat -c '%U:%G %a' /etc/alloy/nina.env)" = "root:alloy 640"
check "nina.alloy root:alloy 0640" test "$(stat -c '%U:%G %a' /etc/alloy/nina.alloy)" = "root:alloy 640"
check "alloy tenu (apt-mark hold)" bash -c 'apt-mark showhold | grep -qx alloy'
check "depot grafana en place" test -f /etc/apt/sources.list.d/grafana.list -a -s /etc/apt/keyrings/grafana.asc
check "version inchangee (1.14.1-1)" test "$(dpkg-query -W -f='${Version}' alloy)" = "1.14.1-1"
check "token absent de systemctl show" bash -c '! systemctl show alloy | grep -q bon-token'
check "systemctl show ne donne que le chemin de nina.env" bash -c 'systemctl show alloy -p EnvironmentFiles | grep -q /etc/alloy/nina.env'
check "memory.prom present et lisible" test -r /var/lib/nina-metrics/memory.prom
check "pas de NeedDaemonReload" test "$(systemctl show alloy -p NeedDaemonReload --value)" = "no"
check "autres services intacts" services_ok
# Etape Verifier du workflow, jouee telle quelle par deployer.
sed -n "/bash -s <<'CHECK'/,/^ *CHECK$/p" /repo/.github/workflows/deploy-system.yml | sed '1d;$d' > /tmp/verifier.sh
if su deployer -c 'bash -s' < /tmp/verifier.sh > /tmp/verifier.log 2>&1; then pass "etape Verifier du workflow"; else fail "etape Verifier du workflow"; tail -5 /tmp/verifier.log; fi

# --------------------------------------------------------------------------
scen "S4  redeploiement sans changement"
T0="$(started)"
stage; creds 1234567 7654321 bon-token; boot
check "vert" test "${RC}" -eq 0
check "alloy a jour, ni restart ni reload" grep -q "= alloy a jour" /tmp/boot.log
check "processus non redemarre" test "$(started)" = "${T0}"

# --------------------------------------------------------------------------
scen "S5  config modifiee dans le depot"
stage; echo "// modif" >> "${ST}/system/alloy/config.alloy"; creds 1234567 7654321 bon-token; boot
check "vert" test "${RC}" -eq 0
check "rechargement (SIGHUP)" grep -q "alloy recharge" /tmp/boot.log
check "sans redemarrage" test "$(started)" = "${T0}"
check "nouvelle config chargee" test "$(run_hash)" = "$(sha256sum /etc/alloy/nina.alloy | cut -d' ' -f1)"

# --------------------------------------------------------------------------
scen "S6  rotation du token"
sleep 1
stage; creds 1234567 7654321 nouveau-token; boot
check "vert" test "${RC}" -eq 0
check "redemarrage" grep -q "alloy redemarre" /tmp/boot.log
check "processus redemarre" test "$(started)" != "${T0}"

# --------------------------------------------------------------------------
scen "S7  drop-in ajoute a la main, config.alloy recree"
printf '[Service]\nEnvironment=FOO=1\n' > /etc/systemd/system/alloy.service.d/zz-main.conf
cp /etc/alloy/nina.alloy /etc/alloy/config.alloy
stage; creds 1234567 7654321 nouveau-token; boot
check "vert" test "${RC}" -eq 0
check "drop-in supprime" test ! -e /etc/systemd/system/alloy.service.d/zz-main.conf
check "config.alloy supprime" test ! -e /etc/alloy/config.alloy

# --------------------------------------------------------------------------
scen "S7b token refuse APRES la migration (rotation ratee) : rouge, rien vers quoi revenir"
echo 401 > /etc/mock-status
stage; creds 1234567 7654321 token-revoque; boot
check "rouge" test "${RC}" -ne 0
check "cause : identifiants refuses (Prometheus ou Loki)" grep -qE "(echantillons refuses|lignes de journal rejetees)" /tmp/boot.log
check "pas de retour automatique (plus d'install manuelle)" bash -c '! grep -q "Retour automatique" /tmp/boot.log'
check "autres services intacts" services_ok
echo 204 > /etc/mock-status
stage; creds 1234567 7654321 nouveau-token; boot
check "corrige au deploiement suivant" test "${RC}" -eq 0

# --------------------------------------------------------------------------
scen "S8  config invalide dans le depot"
T1="$(started)"; H1="$(run_hash)"
stage; echo "ceci n'est pas de l'alloy {" >> "${ST}/system/alloy/config.alloy"; creds 1234567 7654321 nouveau-token; boot
check "rouge" test "${RC}" -ne 0
check "refusee par alloy validate" grep -q "alloy validate" /tmp/boot.log
check "nina.alloy non modifie" test "$(sha256sum /etc/alloy/nina.alloy | cut -d' ' -f1)" = "${H1}"
check "alloy non touche" test "$(started)" = "${T1}" -a "$(run_hash)" = "${H1}"

# --------------------------------------------------------------------------
scen "S9  identifiants incomplets deposes par la CI"
stage; printf 'GRAFANA_CLOUD_TOKEN=\n' | su deployer -c "umask 077 && cat > ${ST}/alloy.env"; boot
check "rouge" test "${RC}" -ne 0
check "cause : incomplets" grep -q "incomplets" /tmp/boot.log
check "alloy.env retire du staging" test ! -e "${ST}/alloy.env"
check "alloy non touche" test "$(started)" = "${T1}"

# --------------------------------------------------------------------------
scen "S10 secrets GitHub absents (CI n'envoie rien) : nina.env en place conserve"
stage; boot
check "vert" test "${RC}" -eq 0
check "alloy a jour" grep -q "= alloy a jour" /tmp/boot.log

# --------------------------------------------------------------------------
scen "S11 droplet reconstruit sans aucun identifiant"
rm -f /etc/alloy/nina.env
stage; boot
check "rouge" test "${RC}" -ne 0
check "cause : aucun identifiant" grep -q "aucun identifiant" /tmp/boot.log
check "alloy non touche" test "$(started)" = "${T1}"

# --------------------------------------------------------------------------
scen "S12 alloy arrete avant le deploiement"
stage; creds 1234567 7654321 nouveau-token; boot   # restaure nina.env
systemctl stop alloy
stage; creds 1234567 7654321 nouveau-token; boot
check "vert" test "${RC}" -eq 0
check "alloy relance" systemctl is-active -q alloy
check "sur nina.alloy" test "$(run_hash)" = "$(sha256sum /etc/alloy/nina.alloy | cut -d' ' -f1)"
check "autres services intacts" services_ok

echo
echo "=== ${FAILS} echec(s)"
