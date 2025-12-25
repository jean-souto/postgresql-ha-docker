#!/bin/bash
set -euo pipefail

# --- Parâmetros ---
TIMEOUT=${1:-120} # Timeout em segundos, default 120s

# --- Cores ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Funções de Logging ---
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}$*${NC}"
}

info() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}$*${NC}"
}

error() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}ERROR: $*${NC}" >&2
}

# --- Funções de Verificação ---

# Retorna 0 se o etcd estiver saudável, 1 caso contrário
is_etcd_healthy() {
    info "Verificando ETCD..."
    if docker compose exec etcd-1 etcdctl endpoint health --cluster | grep -q "is healthy"; then
        return 0
    else
        return 1
    fi
}

# Retorna 0 se houver um leader, 1 caso contrário
has_patroni_leader() {
    info "Verificando Patroni..."
    if docker compose exec pg-1 patronictl list | grep -q 'Leader'; then
        return 0
    else
        return 1
    fi
}

# Retorna 0 se todos os backends do haproxy estiverem UP, 1 caso contrário
are_haproxy_backends_up() {
    info "Verificando HAProxy..."
    # Usa curl para obter o status dos backends
    local backend_stats=$(curl -s http://localhost:7000/stats | grep -E 'pgha-pg-')
    
    if [[ -z "$backend_stats" ]]; then
        info "Não foi possível obter estatísticas dos backends do HAProxy ainda."
        return 1
    fi

    # Conta o número de backends que não estão 'UP'
    local down_backends=$(echo "$backend_stats" | grep -v "UP" | wc -l)

    if [[ "$down_backends" -eq 0 ]]; then
        # Garante que há pelo menos um backend para não dar falso positivo
        if [[ $(echo "$backend_stats" | wc -l) -gt 0 ]]; then
            return 0
        else
            info "Nenhum backend do HAProxy encontrado ainda."
            return 1
        fi
    else
        return 1
    fi
}


# --- Execução Principal ---
main() {
    log "Aguardando todos os serviços ficarem saudáveis. Timeout: ${TIMEOUT}s"
    
    start_time=$(date +%s)

    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))

        if [[ $elapsed -ge $TIMEOUT ]]; then
            error "Timeout de ${TIMEOUT}s atingido. Nem todos os serviços estão saudáveis."
            exit 1
        fi

        # Executa as verificações
        if is_etcd_healthy && has_patroni_leader && are_haproxy_backends_up; then
            log "Todos os serviços estão saudáveis!"
            # Mostra o status final
            docker compose exec pg-1 patronictl list
            curl -s http://localhost:7000/stats | grep pgsql
            exit 0
        fi
        
        info "Aguardando... ($elapsed / $TIMEOUT s)"
        sleep 5
    done
}

# Garante que o script só execute se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

