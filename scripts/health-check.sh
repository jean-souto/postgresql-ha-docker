#!/bin/bash
set -euo pipefail

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

check_etcd() {
    info "Verificando saúde do cluster ETCD..."
    if output=$(docker compose exec etcd-1 etcdctl endpoint health --cluster 2>&1); then
        log "Cluster ETCD está saudável."
        echo "$output"
    else
        error "Cluster ETCD reportou problemas."
        echo "$output"
        return 1
    fi
}

check_patroni() {
    info "Verificando status do cluster Patroni..."
    if output=$(docker compose exec pg-1 patronictl list 2>&1); then
        log "Status do Patroni obtido com sucesso."
        echo "$output"
        # Verifica se há um Leader
        if echo "$output" | grep -q 'Leader'; then
            log "Leader encontrado no cluster."
        else
            error "Nenhum Leader encontrado no cluster Patroni."
            return 1
        fi
    else
        error "Falha ao obter status do Patroni."
        echo "$output"
        return 1
    fi
}

check_postgres_replication() {
    info "Verificando status da replicação PostgreSQL..."
    # O patronictl list já nos dá uma boa visão.
    # Esta função pode ser expandida para queries mais detalhadas se necessário.
    local leader=$(docker compose exec pg-1 patronictl list | grep Leader | awk '{print $4}')
    if [[ -z "$leader" ]]; then
        error "Não foi possível encontrar o Leader do PostgreSQL."
        return 1
    fi
    
    log "Verificando a partir do Leader: $leader"
    if output=$(docker compose exec "$leader" psql -U postgres -c "SELECT * FROM pg_stat_replication;" 2>&1); then
        log "Status da replicação:"
        echo "$output"
    else
        error "Falha ao verificar a replicação no Leader."
        echo "$output"
        return 1
    fi
}


check_haproxy() {
    info "Verificando estatísticas do HAProxy..."
    # Este comando assume que a porta de estatísticas do HAProxy (7000) está exposta.
    if output=$(curl -s http://localhost:7000/stats); then
        log "Estatísticas do HAProxy obtidas com sucesso (via http://localhost:7000/stats)."
        # Exibe apenas as linhas contendo o status dos backends e frontends
        echo "$output" | grep -E 'pgsql|FRONTEND' | sed 's/,/ , /g' | column -t -s "," | while IFS= read -r line; do
            if echo "$line" | grep -q "UP"; then
                echo -e "${GREEN}$line${NC}"
            elif echo "$line" | grep -q "DOWN"; then
                echo -e "${RED}$line${NC}"
            else
                echo -e "${YELLOW}$line${NC}"
            fi
        done
    else
        error "Falha ao obter estatísticas do HAProxy via HTTP."
        error "Verifique se o container 'haproxy' está rodando e a porta 7000 está acessível."
        return 1
    fi
}


# --- Execução Principal ---
main() {
    log "Iniciando verificação completa de saúde do cluster PostgreSQL HA..."
    
    check_etcd
    echo "--------------------------------------------------"
    check_patroni
    echo "--------------------------------------------------"
    check_postgres_replication
    echo "--------------------------------------------------"
    check_haproxy
    
    log "Verificação de saúde concluída."
}

# Garante que o script só execute se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi

