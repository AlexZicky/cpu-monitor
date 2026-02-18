#!/bin/bash

# CONFIGURAZIONE DA VARIABILI D'AMBIENTE
GOTIFY_URL="${GOTIFY_URL}"
GOTIFY_TOKEN="${GOTIFY_TOKEN}"
CPU_THRESHOLD="${CPU_THRESHOLD:-100}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
ALERT_MINUTES="${ALERT_MINUTES:-5}"
TOP_N_PROCESSES="${TOP_N_PROCESSES}"
NET_IFACE="${NET_IFACE}"

# INFO DI SISTEMA
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -i | awk '{print $1}')

# CALCOLI INTERNI
REQUIRED_COUNT=$(( (ALERT_MINUTES * 60) / CHECK_INTERVAL ))
COUNTER=0

# Funzione per ottenere i processi più pesanti
get_top_processes() {
    N="${TOP_N_PROCESSES:-3}"

    ps -eo pid,%cpu,comm --sort=-%cpu | grep -v "ps" | head -n $((N+1)) | while read PID CPU COMM; do
        
        # Salta header
        if [ "$PID" = "PID" ]; then
            continue
        fi

        # Se il processo è morto, salta
        if [ ! -r "/proc/$PID/cmdline" ]; then
            continue
        fi

        # Comando completo
        CMDLINE=$(tr '\0' ' ' < /proc/$PID/cmdline 2>/dev/null)
        [ -z "$CMDLINE" ] && CMDLINE="$COMM"

        # Nome container (default host)
		CONTAINER="host"

		if command -v docker >/dev/null 2>&1; then
    		CGROUP=$(grep -oE 'docker-[a-f0-9]{64}' /proc/$PID/cgroup 2>/dev/null | sed 's/docker-//')

    		if [ -n "$CGROUP" ]; then
        		NAME=$(docker ps --no-trunc --format '{{.ID}} {{.Names}}' | grep "$CGROUP" | awk '{print $2}')
        		[ -n "$NAME" ] && CONTAINER="$NAME"
    		fi
		fi

        printf "%-6s %-6s %-15s %s\n" "$PID" "$CPU" "$CONTAINER" "$CMDLINE"
    done
}

# Funzione per ottenere traffico rete
get_net_usage() {
    IFACE="${NET_IFACE:-eth0}"

    RX1=$(grep "$IFACE" /host_proc/net/dev | awk '{print $2}')
    TX1=$(grep "$IFACE" /host_proc/net/dev | awk '{print $10}')

    sleep "$CHECK_INTERVAL"

    RX2=$(grep "$IFACE" /host_proc/net/dev | awk '{print $2}')
    TX2=$(grep "$IFACE" /host_proc/net/dev | awk '{print $10}')

    RX_RATE=$(( (RX2 - RX1) / 1024 / CHECK_INTERVAL ))
    TX_RATE=$(( (TX2 - TX1) / 1024 / CHECK_INTERVAL ))

    echo "$RX_RATE" "$TX_RATE"
}

send_alert() {
    TOP_PROC=$(get_top_processes)
    read RX_RATE TX_RATE <<< "$(get_net_usage)"

    curl -s -X POST "$GOTIFY_URL?token=$GOTIFY_TOKEN" \
        -F "title=CPU alta su $HOSTNAME" \
        -F "message=La CPU è sopra ${CPU_THRESHOLD}% per più di ${ALERT_MINUTES} minuti.

	Host: $HOSTNAME
	IP: $IP_ADDRESS

	Download: ${RX_RATE} KB/s
	Upload:   ${TX_RATE} KB/s

	Top processi:
	$TOP_PROC" \
        	-F "priority=5" >/dev/null
	}

while true; do
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    CPU_INT=${CPU_USAGE%.*}

    read RX_RATE TX_RATE <<< "$(get_net_usage)"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - CPU: ${CPU_USAGE}%"
    echo "Down: ${RX_RATE} KB/s | Up: ${TX_RATE} KB/s"
    echo "Top ${TOP_N_PROCESSES} processi:"
    echo "PID    CPU    HOST            Comando"
    get_top_processes
    echo "---------------------------"

    if [ "$CPU_INT" -ge "$CPU_THRESHOLD" ]; then
        COUNTER=$((COUNTER + 1))
    else
        COUNTER=0
    fi

    if [ "$COUNTER" -ge "$REQUIRED_COUNT" ]; then
        send_alert
        COUNTER=0
    fi

    sleep "$CHECK_INTERVAL"
done

