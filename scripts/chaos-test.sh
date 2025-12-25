#!/bin/bash
set -euo pipefail

# --- Cores ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Funções de Logging ---
log() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}$*${NC}"; }
info() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}$*${NC}"; }
error() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}ERROR: $*${NC}" >&2; }
highlight() { echo -e "${CYAN}$*${NC}"; }

# --- Funções Auxiliares ---

# Retorna o nome do container do Leader atual
get_leader() {
    for node in pg-1 pg-2 pg-3; do
        result=$(docker compose exec -T "$node" patronictl list --format tsv 2>/dev/null | grep 'Leader' | awk '{print $2}')
        if [[ -n "$result" ]]; then
            echo "$result"
            return 0
        fi
    done
    echo ""
}

# Retorna a lista de containers de réplica
get_replicas() {
    for node in pg-1 pg-2 pg-3; do
        result=$(docker compose exec -T "$node" patronictl list --format tsv 2>/dev/null | grep 'Replica' | awk '{print $2}')
        if [[ -n "$result" ]]; then
            echo "$result"
            return 0
        fi
    done
    echo ""
}

# Espera por um novo leader ser eleito
wait_for_new_leader() {
    local old_leader=$1
    local new_leader=""
    local timeout=60
    local start_time=$(date +%s)

    info "Aguardando a eleição de um novo Leader (Timeout: ${timeout}s)..."
    while true; do
        new_leader=$(get_leader)
        if [[ -n "$new_leader" && "$new_leader" != "$old_leader" ]]; then
            log "Novo Leader eleito: $new_leader"
            return 0
        fi

        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            error "Timeout! Nenhum novo Leader foi eleito a tempo."
            return 1
        fi
        sleep 3
    done
}

# Cria uma tabela de teste e insere um registro
write_test_data() {
    local leader=$1
    info "Escrevendo dados de teste no Leader atual ($leader)..."
    docker compose exec "$leader" psql -U postgres -c "CREATE TABLE IF NOT EXISTS chaos_test (id INT PRIMARY KEY, created_at TIMESTAMPTZ);"
    docker compose exec "$leader" psql -U postgres -c "INSERT INTO chaos_test (id, created_at) VALUES (1, NOW()) ON CONFLICT (id) DO NOTHING;"
    log "Dados de teste escritos."
}

# Verifica se os dados de teste existem no novo leader
verify_test_data() {
    local new_leader=$1
    info "Verificando integridade dos dados no novo Leader ($new_leader)..."
    local result=$(docker compose exec "$new_leader" psql -U postgres -tAc "SELECT COUNT(*) FROM chaos_test WHERE id = 1;")
    
    if [[ "$result" -eq 1 ]]; then
        log "Verificação de dados bem-sucedida! Os dados não foram perdidos."
    else
        error "Falha na verificação de dados! O registro de teste não foi encontrado."
        return 1
    fi
}

# --- Testes de Chaos ---

test_kill_primary() {
    highlight "--- INICIANDO TESTE: KILL PRIMARY ---"
    
    local old_leader=$(get_leader)
    if [[ -z "$old_leader" ]]; then
        error "Nenhum Leader encontrado para iniciar o teste."
        return 1
    fi
    log "Leader atual é: $old_leader"

    write_test_data "$old_leader"

    info "Parando o container do Leader: $old_leader"
    local start_time=$(date +%s)
    docker compose stop "$old_leader"
    
    if ! wait_for_new_leader "$old_leader"; then
        docker compose start "$old_leader" # Tenta recuperar o estado
        return 1
    fi
    local end_time=$(date +%s)
    
    local rto=$((end_time - start_time))
    log "Failover concluído! Tempo de Recuperação (RTO): ${rto} segundos."
    
    local new_leader=$(get_leader)
    verify_test_data "$new_leader"

    info "Reiniciando o antigo Leader ($old_leader) como réplica..."
    docker compose start "$old_leader"
    
    highlight "--- TESTE KILL PRIMARY CONCLUÍDO ---"
}

test_network_partition() {
    highlight "--- INICIANDO TESTE: NETWORK PARTITION ---"
    info "Este teste ainda não foi implementado."
    # Lógica para isolar um nó da rede:
    # 1. Escolher um nó para isolar (pode ser o leader ou uma réplica)
    #    local node_to_isolate=$(get_leader)
    # 2. Desconectar o container da rede principal
    #    info "Isolando $node_to_isolate da rede..."
    #    docker network disconnect <project>_default $node_to_isolate
    # 3. Aguardar o failover (se o leader foi isolado)
    # 4. Medir o tempo
    # 5. Reconectar a rede
    #    info "Reconectando $node_to_isolate à rede..."
    #    docker network connect <project>_default $node_to_isolate
    # 6. Verificar se ele se junta ao cluster como réplica
    highlight "--- TESTE NETWORK PARTITION PULADO ---"
}

# --- Execução Principal ---
main() {
    if [[ $# -eq 0 ]]; then
        error "Uso: $0 [--kill-primary | --network-partition | --full-test]"
        exit 1
    fi

    case "$1" in
        --kill-primary)
            test_kill_primary
            ;;
        --network-partition)
            test_network_partition
            ;;
        --full-test)
            log "Executando suíte de testes completa..."
            test_kill_primary
            test_network_partition
            log "Suíte de testes completa finalizada."
            ;;
        *)
            error "Opção inválida: $1"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

