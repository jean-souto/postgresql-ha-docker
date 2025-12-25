# Changelog

> **[English](#english)** | **[Portugues](#portugues)**

---

<a name="english"></a>
## English

All notable changes to this project are documented in this file.

### [1.0.0] - 2024-12-24

#### Initial Release

First working version of the PostgreSQL High Availability Lab with automatic failover.

#### Components

- PostgreSQL 17 with streaming replication
- Patroni 4.1.0 for automatic failover management
- etcd 3.5.17 cluster (3 nodes) for distributed consensus
- PgBouncer 1.23.1 (3 instances) for connection pooling
- HAProxy LTS for load balancing and health checking

#### Features

- Automatic leader election and failover
- Streaming replication with zero lag
- Connection pooling with transaction mode
- Separate endpoints for read/write (5000) and read-only (5001) traffic
- HAProxy stats dashboard on port 7000
- Chaos testing script for failover validation

---

### Fixes Applied During Development

#### Fix 1: etcd v2 API Compatibility

**Problem**: Patroni 4.x with `patroni[etcd3]` pip package incorrectly installs `python-etcd` (v2 client library) instead of proper v3 dependencies. This causes Patroni to attempt v2 API calls (`/v2/keys/...`) which fail with 404 errors.

**Root Cause**: Known bug in Patroni packaging. See [GitHub Issue #3337](https://github.com/patroni/patroni/issues/3337).

**Solution**: Enable v2 API on etcd servers as a workaround.

**File Changed**: `docker-compose.yml`

```yaml
# Added to all etcd services
command:
  - etcd
  # ... other flags ...
  - --enable-v2=true
```

---

#### Fix 2: PostgreSQL Data Directory Permissions

**Problem**: PostgreSQL requires the data directory to have permissions `0700` and refuses to run as root. The container was failing with `initdb: error: cannot be run as root`.

**Root Cause**: Docker containers run as root by default, and the data directory permissions were not being set correctly for the postgres user.

**Solution**:
1. Install `su-exec` in the container for privilege dropping
2. Run entrypoint as root to set permissions
3. Use `su-exec postgres` to start Patroni with correct user

**Files Changed**:
- `docker/patroni/Dockerfile`
- `docker/patroni/entrypoint.sh`

```dockerfile
# Dockerfile additions
RUN apk add --no-cache ... su-exec
```

```bash
# entrypoint.sh
chmod 700 "$DATA_DIR"
exec su-exec postgres patroni "$CONFIG_FILE"
```

---

#### Fix 3: Patroni Healthcheck IPv6 Issue

**Problem**: Healthcheck command `wget -q --spider http://localhost:8008/health` was failing because `localhost` resolves to IPv6 (`::1`) in Alpine Linux, but Patroni binds to IPv4 only.

**Root Cause**: Alpine Linux default resolver behavior prioritizes IPv6.

**Solution**: Use explicit IPv4 address `127.0.0.1` instead of `localhost`.

**File Changed**: `docker-compose.yml`

```yaml
healthcheck:
  test: ['CMD-SHELL', 'wget -q --spider http://127.0.0.1:8008/health']
```

---

#### Fix 4: PgBouncer Database Host Configuration

**Problem**: PgBouncer was configured with `host=localhost` but runs in a separate container from PostgreSQL, causing connection failures.

**Root Cause**: Configuration assumed PgBouncer and PostgreSQL were co-located.

**Solution**: Configure PgBouncer to connect to PostgreSQL containers by their Docker network hostnames.

**File Changed**: `config/pgbouncer/pgbouncer.ini`

```ini
[databases]
* = host=pg-1,pg-2,pg-3 port=5432
```

---

#### Fix 5: PgBouncer MD5 Authentication Hash

**Problem**: PgBouncer with `auth_type = md5` requires password hashes in the format `md5<hash>`, not plaintext passwords. Authentication was failing silently.

**Root Cause**: `userlist.txt` contained plaintext passwords instead of MD5 hashes.

**Solution**: Generate correct MD5 hashes using the formula `md5(password + username)`.

**File Changed**: `config/pgbouncer/userlist.txt`

```bash
# Hash generation
echo -n "changemepostgres" | md5sum
# Result: md574fd9b4f4d8aa5fda0cd27a632361f79
```

```text
"postgres" "md574fd9b4f4d8aa5fda0cd27a632361f79"
"replicator" "md5b9c7379cd3aed98438505f8a76000541"
```

---

#### Fix 6: PgBouncer Healthcheck Missing Password

**Problem**: PgBouncer healthcheck command did not include password, causing authentication failure.

**Root Cause**: `psql` command in healthcheck had no `PGPASSWORD` environment variable.

**Solution**: Add `PGPASSWORD` to the healthcheck command.

**File Changed**: `docker-compose.yml`

```yaml
healthcheck:
  test: ['CMD-SHELL', 'PGPASSWORD=changeme psql -h 127.0.0.1 -p 6432 -U postgres -d pgbouncer -c "SHOW DATABASES;"']
```

---

#### Fix 7: HAProxy Healthcheck IPv6 Issue

**Problem**: Same IPv6 resolution issue as Fix 3, affecting HAProxy healthcheck.

**Root Cause**: `localhost` resolving to IPv6 in Alpine Linux.

**Solution**: Use `127.0.0.1` instead of `localhost`.

**File Changed**: `docker-compose.yml`

```yaml
healthcheck:
  test: ['CMD-SHELL', 'wget -q --spider http://127.0.0.1:7000/stats || exit 1']
```

---

#### Fix 8: Chaos Test Script Container Handling

**Problem**: The `chaos-test.sh` script only tried to get cluster status from `pg-1`. When `pg-1` was stopped (as part of the test), all subsequent status checks failed.

**Root Cause**: Hardcoded container name in `get_leader()` function.

**Solution**: Try all available containers until one responds.

**File Changed**: `scripts/chaos-test.sh`

```bash
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
```

---

### Validation Results

After all fixes were applied:

| Test | Result |
|------|--------|
| All containers healthy | PASS |
| Patroni cluster formed | PASS |
| Streaming replication active | PASS |
| Failover on primary kill | PASS |
| RTO (Recovery Time) | 4 seconds |
| Data integrity after failover | PASS |
| Old primary rejoins as replica | PASS |

---

<a name="portugues"></a>
## Português

Todas as mudanças notáveis neste projeto estão documentadas neste arquivo.

### [1.0.0] - 2024-12-24

#### Release Inicial

Primeira versão funcional do PostgreSQL High Availability Lab com failover automático.

#### Componentes

- PostgreSQL 17 com replicação streaming
- Patroni 4.1.0 para gerenciamento de failover automático
- Cluster etcd 3.5.17 (3 nós) para consenso distribuído
- PgBouncer 1.23.1 (3 instâncias) para connection pooling
- HAProxy LTS para balanceamento de carga e health checking

#### Funcionalidades

- Eleição automática de leader e failover
- Replicação streaming com zero lag
- Connection pooling em modo transação
- Endpoints separados para leitura/escrita (5000) e somente leitura (5001)
- Dashboard de stats do HAProxy na porta 7000
- Script de chaos testing para validação de failover

---

### Correções Aplicadas Durante o Desenvolvimento

#### Correção 1: Compatibilidade etcd v2 API

**Problema**: Patroni 4.x com pacote pip `patroni[etcd3]` instala incorretamente `python-etcd` (biblioteca cliente v2) em vez das dependências v3 corretas. Isso faz o Patroni tentar chamadas API v2 (`/v2/keys/...`) que falham com erros 404.

**Causa Raiz**: Bug conhecido no empacotamento do Patroni. Veja [GitHub Issue #3337](https://github.com/patroni/patroni/issues/3337).

**Solução**: Habilitar API v2 nos servidores etcd como workaround.

**Arquivo Alterado**: `docker-compose.yml`

```yaml
# Adicionado a todos os serviços etcd
command:
  - etcd
  # ... outras flags ...
  - --enable-v2=true
```

---

#### Correção 2: Permissões do Diretório de Dados PostgreSQL

**Problema**: PostgreSQL requer que o diretório de dados tenha permissões `0700` e recusa executar como root. O container estava falhando com `initdb: error: cannot be run as root`.

**Causa Raiz**: Containers Docker executam como root por padrão, e as permissões do diretório de dados não estavam sendo definidas corretamente para o usuário postgres.

**Solução**:
1. Instalar `su-exec` no container para troca de privilégios
2. Executar entrypoint como root para definir permissões
3. Usar `su-exec postgres` para iniciar Patroni com usuário correto

**Arquivos Alterados**:
- `docker/patroni/Dockerfile`
- `docker/patroni/entrypoint.sh`

```dockerfile
# Adições ao Dockerfile
RUN apk add --no-cache ... su-exec
```

```bash
# entrypoint.sh
chmod 700 "$DATA_DIR"
exec su-exec postgres patroni "$CONFIG_FILE"
```

---

#### Correção 3: Problema IPv6 no Healthcheck do Patroni

**Problema**: Comando de healthcheck `wget -q --spider http://localhost:8008/health` estava falhando porque `localhost` resolve para IPv6 (`::1`) no Alpine Linux, mas Patroni faz bind apenas em IPv4.

**Causa Raiz**: Comportamento padrão do resolver do Alpine Linux prioriza IPv6.

**Solução**: Usar endereço IPv4 explícito `127.0.0.1` em vez de `localhost`.

**Arquivo Alterado**: `docker-compose.yml`

```yaml
healthcheck:
  test: ['CMD-SHELL', 'wget -q --spider http://127.0.0.1:8008/health']
```

---

#### Correção 4: Configuração de Host do PgBouncer

**Problema**: PgBouncer estava configurado com `host=localhost` mas executa em container separado do PostgreSQL, causando falhas de conexão.

**Causa Raiz**: Configuração assumia que PgBouncer e PostgreSQL estavam co-localizados.

**Solução**: Configurar PgBouncer para conectar aos containers PostgreSQL pelos seus hostnames na rede Docker.

**Arquivo Alterado**: `config/pgbouncer/pgbouncer.ini`

```ini
[databases]
* = host=pg-1,pg-2,pg-3 port=5432
```

---

#### Correção 5: Hash MD5 de Autenticação do PgBouncer

**Problema**: PgBouncer com `auth_type = md5` requer hashes de senha no formato `md5<hash>`, não senhas em texto plano. Autenticação estava falhando silenciosamente.

**Causa Raiz**: `userlist.txt` continha senhas em texto plano em vez de hashes MD5.

**Solução**: Gerar hashes MD5 corretos usando a fórmula `md5(senha + usuário)`.

**Arquivo Alterado**: `config/pgbouncer/userlist.txt`

```bash
# Geração de hash
echo -n "changemepostgres" | md5sum
# Resultado: md574fd9b4f4d8aa5fda0cd27a632361f79
```

```text
"postgres" "md574fd9b4f4d8aa5fda0cd27a632361f79"
"replicator" "md5b9c7379cd3aed98438505f8a76000541"
```

---

#### Correção 6: Senha Faltando no Healthcheck do PgBouncer

**Problema**: Comando de healthcheck do PgBouncer não incluía senha, causando falha de autenticação.

**Causa Raiz**: Comando `psql` no healthcheck não tinha variável de ambiente `PGPASSWORD`.

**Solução**: Adicionar `PGPASSWORD` ao comando de healthcheck.

**Arquivo Alterado**: `docker-compose.yml`

```yaml
healthcheck:
  test: ['CMD-SHELL', 'PGPASSWORD=changeme psql -h 127.0.0.1 -p 6432 -U postgres -d pgbouncer -c "SHOW DATABASES;"']
```

---

#### Correção 7: Problema IPv6 no Healthcheck do HAProxy

**Problema**: Mesmo problema de resolução IPv6 da Correção 3, afetando healthcheck do HAProxy.

**Causa Raiz**: `localhost` resolvendo para IPv6 no Alpine Linux.

**Solução**: Usar `127.0.0.1` em vez de `localhost`.

**Arquivo Alterado**: `docker-compose.yml`

```yaml
healthcheck:
  test: ['CMD-SHELL', 'wget -q --spider http://127.0.0.1:7000/stats || exit 1']
```

---

#### Correção 8: Tratamento de Containers no Script de Chaos Test

**Problema**: O script `chaos-test.sh` tentava obter status do cluster apenas de `pg-1`. Quando `pg-1` era parado (como parte do teste), todas as verificações de status subsequentes falhavam.

**Causa Raiz**: Nome de container hardcoded na função `get_leader()`.

**Solução**: Tentar todos os containers disponíveis até um responder.

**Arquivo Alterado**: `scripts/chaos-test.sh`

```bash
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
```

---

### Resultados de Validação

Após todas as correções serem aplicadas:

| Teste | Resultado |
|-------|-----------|
| Todos containers saudáveis | PASSOU |
| Cluster Patroni formado | PASSOU |
| Replicação streaming ativa | PASSOU |
| Failover ao matar primary | PASSOU |
| RTO (Tempo de Recuperação) | 4 segundos |
| Integridade de dados após failover | PASSOU |
| Antigo primary reintegrado como réplica | PASSOU |
