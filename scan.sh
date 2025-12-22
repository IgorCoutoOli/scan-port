#!/bin/bash
set -euo pipefail

THREADS=254
NO_THREAD=0
MODE_OPEN=0
LIST_MODE=0
FORCE=0

TMP_NOTPING=$(mktemp)
TMP_OPEN=$(mktemp)
TMP_CLOSED=$(mktemp)

cleanup() {
    rm -f "$TMP_NOTPING" "$TMP_OPEN" "$TMP_CLOSED"
}
trap cleanup EXIT

show_help() {
    cat <<EOF
Scan Barramento – Scanner de porta TCP em redes IPv4

Uso:
  scan [OPÇÕES] <rede> <porta>

Exemplos:
  scan 192.168.1.0/24 80       Escaneia a porta 80 em toda a /24
  scan 192.168.1 443           Detecta máscara automaticamente
  scan --open 10.0 22          Exibe somente hosts com porta aberta
  scan -nt 50 172.16 3306      Usa até 50 threads

Opções:
  -h, --help
      Exibe esta ajuda.

  --no-thread
      Executa de forma sequencial (equivalente a -nt 1).

  -nt N
      Define o número máximo de threads para escaneamento paralelo.
      Padrão: 254.

  -o, --open
      Exibe APENAS os hosts que responderem com porta aberta.

  -L, --list
      Lista todos os IPs encontrados com o status:
        • OPEN       Porta aberta
        • CLOSED     Porta fechada
        • NOT PING   Sem resposta ao ping

  --force
      Ignora avisos de segurança para redes grandes (ex.: /8).
      Utilize com cautela.

EOF
    exit 0
}

ARGS=()
while (( "$#" )); do
    case "$1" in
        -h|--help) show_help ;;
        --no-thread) NO_THREAD=1; shift ;;
        -o|--open) MODE_OPEN=1; shift ;;
        -L|--list) LIST_MODE=1; shift ;;
        -nt) THREADS="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -*) echo "Opção desconhecida: $1"; exit 1 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

if [ "${#ARGS[@]}" -lt 2 ]; then
    echo "Uso incorreto."
    exit 1
fi

NETWORK_RAW="${ARGS[0]}"
PORT="${ARGS[1]}"

if [[ "$NETWORK_RAW" == */* ]]; then
    BASE="${NETWORK_RAW%%/*}"
    MASK="${NETWORK_RAW##*/}"
else
    BASE="$NETWORK_RAW"
    MASK=""
fi

IFS='.' read -r -a OCT <<< "$BASE"
OCT_N=${#OCT[@]}

if [ -z "$MASK" ]; then
    case $OCT_N in
        4) MASK=32 ;;
        3) MASK=24 ;;
        2) MASK=16 ;;
        1) MASK=8 ;;
    esac
fi

FIXED_OCT=$(( MASK / 8 ))
(( FIXED_OCT > 4 )) && FIXED_OCT=4

FIXED_PART=()
for i in $(seq 0 $((FIXED_OCT-1))); do
    FIXED_PART+=("${OCT[i]:-0}")
done
PREFIX_STR="$(IFS=.; echo "${FIXED_PART[*]}")"

VAR_OCT=$((4 - FIXED_OCT))

[[ "$NO_THREAD" -eq 1 ]] && THREADS=1

scan() {
    IP="$1"

    if ! ping -c1 -W1 "$IP" >/dev/null 2>&1; then
        echo "$IP" >> "$TMP_NOTPING"
        return
    fi

    if nc -z -w1 "$IP" "$PORT" >/dev/null 2>&1; then
        echo "$IP" >> "$TMP_OPEN"
    else
        echo "$IP" >> "$TMP_CLOSED"
    fi
}

export -f scan
export PORT TMP_NOTPING TMP_OPEN TMP_CLOSED

gen_ips() {
    case "$VAR_OCT" in
        0) echo "$PREFIX_STR" ;;
        1)
            for d in $(seq 1 254); do echo "$PREFIX_STR.$d"; done ;;
        2)
            for c in $(seq 1 254); do
                for d in $(seq 1 254); do echo "$PREFIX_STR.$c.$d"; done
            done ;;
        3)
            for b in $(seq 1 254); do
                for c in $(seq 1 254); do
                    for d in $(seq 1 254); do echo "$PREFIX_STR.$b.$c.$d"; done
                done
            done ;;
    esac
}

if [ "$THREADS" -le 1 ]; then
    while read -r ip; do scan "$ip"; done < <(gen_ips)
else
    gen_ips | xargs -P "$THREADS" -I {} bash -c 'scan "$@"' _ {}
fi

if [ "$LIST_MODE" -eq 1 ]; then
    echo "===== Don't ping ====="
    cat "$TMP_NOTPING"

    echo ""
    echo "===== Open ====="
    cat "$TMP_OPEN"

    echo ""
    echo "===== Closed ====="
    cat "$TMP_CLOSED"

    exit 0
fi

if [ "$MODE_OPEN" -eq 1 ]; then
    cat "$TMP_OPEN"
else
    cat "$TMP_CLOSED"
fi

exit 0
