#!/bin/bash
set -euo pipefail

# CONFIGURAÇÕES PADRÃO
THREADS=5       # Número padrão de threads (paralelismo)
NO_THREAD=0     # Flag para modo sequencial
MODE_OPEN=0     # Mostrar somente hosts com porta aberta
LIST_MODE=0     # Listar todos os hosts com status (open/closed/not ping)
FORCE=0         # Ignorar avisos de segurança
OUTPUT_FILE=""  # Arquivo de saída

# ARQUIVOS TEMPORÁRIOS
TMP_NOTPING=$(mktemp)   # Hosts que não responderam ao ping
TMP_OPEN=$(mktemp)      # Hosts com porta aberta
TMP_CLOSED=$(mktemp)    # Hosts com porta fechada

# Função de limpeza de arquivos temporários
cleanup() {
    rm -f "$TMP_NOTPING" "$TMP_OPEN" "$TMP_CLOSED"
}
trap cleanup EXIT

# Função de exibição de ajuda
show_help() {
    cat <<EOF
Scan Port – Scanner de porta TCP em redes IPv4

Uso:
  scan-port [OPÇÕES] <rede> <porta>

Exemplos:
  scan-port 192.168.1.0/24 80       Escaneia a porta 80 em toda a /24
  scan-port 192.168.1 443           Detecta máscara automaticamente
  scan-port --open 10.0 22          Exibe somente hosts com porta aberta
  scan-port -nt 50 172.16 3306      Usa até 50 threads

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
        • Open         Porta aberta
        • Closed       Porta fechada
        • Don't ping   Sem resposta ao ping

  --force
      Ignora avisos de segurança para redes grandes (ex.: /8).
      Utilize com cautela.

  --output <arquivo>
      Salva o resultado em um arquivo ao invés de exibir na tela, obrigatório para redes maiores que /23.

EOF
    exit 0
}

# Análise de argumentos
ARGS=()
while (( "$#" )); do
    case "$1" in
        -h|--help) show_help ;;
        --no-thread) NO_THREAD=1; shift ;;
        -o|--open) MODE_OPEN=1; shift ;;
        -L|--list) LIST_MODE=1; shift ;;
        -nt) THREADS="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -*) echo "Opção desconhecida: $1"; exit 1 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

# Validação de argumentos
if [ "${#ARGS[@]}" -lt 2 ]; then
    echo "Uso incorreto."
    exit 1
fi

# Análise da rede e porta
NETWORK_RAW="${ARGS[0]}"
PORT="${ARGS[1]}"

BASE=""
MASK=""

# Verificando se a porta é válida
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || {
    echo "Porta inválida: $PORT"
    exit 1
}

if [[ "$NETWORK_RAW" == */* ]]; then
    BASE="${NETWORK_RAW%%/*}"
    MASK_RAW="${NETWORK_RAW##*/}"

    if [[ "$MASK_RAW" =~ ^[0-9]{1,2}$ ]] && (( MASK_RAW >= 0 && MASK_RAW <= 32 )); then
        MASK="$MASK_RAW"
    elif [[ "$MASK_RAW" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r m1 m2 m3 m4 <<< "$MASK_RAW"

        mask_bits() {
            case "$1" in
                255) echo 8 ;;
                254) echo 7 ;;
                252) echo 6 ;;
                248) echo 5 ;;
                240) echo 4 ;;
                224) echo 3 ;;
                192) echo 2 ;;
                128) echo 1 ;;
                0)   echo 0 ;;
                *)   echo -1 ;;
            esac
        }

        b1=$(mask_bits "$m1")
        b2=$(mask_bits "$m2")
        b3=$(mask_bits "$m3")
        b4=$(mask_bits "$m4")

        if (( b1 < 0 || b2 < 0 || b3 < 0 || b4 < 0 )); then
            echo "Netmask inválida: $MASK_RAW"
            exit 1
        fi

        MASK=$(( b1 + b2 + b3 + b4 ))
    else
        echo "Máscara inválida: $MASK_RAW"
        exit 1
    fi
else
    BASE="$NETWORK_RAW"
    IFS='.' read -r -a OCT <<< "$BASE"
    OCT_N=${#OCT[@]}

    case $OCT_N in
        4) MASK=32 ;;
        3) MASK=24 ;;
        2) MASK=16 ;;
        1) MASK=8 ;;
    esac
fi

# Redes maiores que /23 só é possivel ler se ativar a flag --output
if (( MASK < 23 )) && [[ -z "$OUTPUT_FILE" ]]; then
    echo "Atenção: a rede $BASE/$MASK contém muitos IPs."
    echo "Use --output para salvar os resultados em um arquivo."
    exit 1
fi

# Validação de máscara
if (( MASK < 16 )) && [[ "$FORCE" -eq 0 ]]; then
    echo "Atenção: a rede $BASE/$MASK contém muitos IPs."
    echo "Use --force para confirmar o escaneamento."
    exit 1
fi

[[ "$NO_THREAD" -eq 1 ]] && THREADS=1

# Função de escaneamento
scan() {
    IP="$1"

    if nc -z -w0.5 "$IP" "$PORT" >/dev/null 2>&1; then
        echo "$IP" >> "$TMP_OPEN"
        return
    fi

    # Se não conectou, tenta ping apenas para classificar
    if ping -c1 -W0.3 "$IP" >/dev/null 2>&1; then
        echo "$IP" >> "$TMP_CLOSED"
    else
        echo "$IP" >> "$TMP_NOTPING"
    fi
}

export -f scan
export PORT TMP_NOTPING TMP_OPEN TMP_CLOSED

# Geração de IPs a partir do prefixo
ip_to_int() {
    local a b c d
    IFS='.' read -r a b c d <<< "$1"
    echo $(( a*16777216 + b*65536 + c*256 + d ))
}

int_to_ip() {
    local ip=$1
    printf "%d.%d.%d.%d\n" \
        $(( (ip >> 24) & 255 )) \
        $(( (ip >> 16) & 255 )) \
        $(( (ip >> 8) & 255 )) \
        $(( ip & 255 ))
}

gen_ips() {
    local base_int mask_int network_int broadcast_int

    base_int=$(ip_to_int "$BASE")
    mask_int=$(( (0xFFFFFFFF << (32 - MASK)) & 0xFFFFFFFF ))
    network_int=$(( base_int & mask_int ))
    broadcast_int=$(( network_int | (~mask_int & 0xFFFFFFFF) ))

    for (( ip=network_int; ip<=broadcast_int; ip++ )); do
        int_to_ip "$ip"
    done
}

# Sequencial ou multithread?
if [ "$THREADS" -le 1 ]; then
    while read -r ip; do scan "$ip"; done < <(gen_ips)
else
    gen_ips | xargs -P "$THREADS" -I {} bash -c 'scan "$@"' _ {}
fi

# Exibição dos resultados em modo lista
if [ "$LIST_MODE" -eq 1 ]; then
    if [ -n "$OUTPUT_FILE" ]; then
        {
            echo "===== Don't ping ====="
            cat "$TMP_NOTPING"
            echo ""
            echo "===== Open ====="
            cat "$TMP_OPEN"
            echo ""
            echo "===== Closed ====="
            cat "$TMP_CLOSED"
        } > "$OUTPUT_FILE"
        echo "Resultados salvos em $OUTPUT_FILE"
    else
        echo "===== Don't ping ====="
        cat "$TMP_NOTPING"

        echo ""
        echo "===== Open ====="
        cat "$TMP_OPEN"

        echo ""
        echo "===== Closed ====="
        cat "$TMP_CLOSED"
    fi
    exit 0
fi

# Exibição dos resultados em modo normal
if [ "$MODE_OPEN" -eq 1 ]; then
    if [ -n "$OUTPUT_FILE" ]; then
        mv "$TMP_OPEN" "$OUTPUT_FILE"
        echo "Resultados salvos em $OUTPUT_FILE"
    else
        cat "$TMP_OPEN"
    fi
else
    if [ -n "$OUTPUT_FILE" ]; then
        mv "$TMP_CLOSED" "$OUTPUT_FILE"
        echo "Resultados salvos em $OUTPUT_FILE"
    else
        cat "$TMP_CLOSED"
    fi
fi

exit 0
