FROM alpine:latest

# Installo curl, top, bash, tzdata, docker
RUN apk add --no-cache bash curl procps docker-cli tzdata

# Copio lo script
COPY cpu_monitor.sh /usr/local/bin/cpu_monitor.sh

# Rendo eseguibile
RUN chmod +x /usr/local/bin/cpu_monitor.sh

# Variabili configurabili
ENV GOTIFY_URL=""
ENV GOTIFY_TOKEN=""
ENV CPU_THRESHOLD=100
ENV CHECK_INTERVAL=1
ENV ALERT_MINUTES=5
ENV TOP_N_PROCESSES=6
ENV NET_IFACE=enp0s25
ENV TZ=Europe/Rome

# Avvio lo script
ENTRYPOINT ["/usr/local/bin/cpu_monitor.sh"]