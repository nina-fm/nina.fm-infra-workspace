# Replique de flow.nina.fm pour simuler le deploiement : trixie + systemd,
# alloy 1.14.1-1 installe a la main depuis un .deb (aucune source apt),
# comme le 27 mars 2026.
FROM debian:trixie
ENV container=docker DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq \
 && apt-get install -y -qq systemd systemd-sysv dbus cron curl ca-certificates python3 procps sudo >/dev/null \
 && apt-get clean
RUN f=$(curl -fsSL https://apt.grafana.com/dists/stable/main/binary-amd64/Packages \
        | awk '/^Package: /{p=($2=="alloy")} p&&/^Version: /{v=($2=="1.14.1-1")} p&&v&&/^Filename: /{print $2; exit}') \
 && echo "deb: $f" && curl -fsSL -o /tmp/alloy.deb "https://apt.grafana.com/$f" \
 && dpkg -i /tmp/alloy.deb && rm /tmp/alloy.deb \
 && useradd -m deployer
COPY mock.py /usr/local/bin/mock.py
COPY mock.service /etc/systemd/system/mock.service
RUN systemctl enable mock.service cron alloy
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
