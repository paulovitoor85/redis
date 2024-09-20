# Função para verificar se redis-cli está instalado
function Check-RedisCli {
    $redisCliPath = (Get-Command redis-cli -ErrorAction SilentlyContinue).Path
    if (-not $redisCliPath) {
        Write-Error "redis-cli não está instalado ou não está no PATH do sistema. Por favor, instale redis-cli e adicione-o ao PATH."
        exit
    }
}

# Verificar se redis-cli está instalado
Check-RedisCli

# Listar as subscriptions
$subscriptions = az account list --output json | ConvertFrom-Json
$subscriptionChoices = $subscriptions | ForEach-Object { $_.name }

# Perguntar ao usuário para selecionar a subscription
$selectedSubscription = $subscriptionChoices | Out-GridView -Title "Escolha a subscription desejada" -PassThru

# Obter o subscription_id selecionado
$selectedSubscriptionId = ($subscriptions | Where-Object { $_.name -eq $selectedSubscription }).id

# Definir a subscription selecionada
az account set --subscription $selectedSubscriptionId

# Listar os Redis Caches na subscription selecionada
$redisCaches = az redis list --output json | ConvertFrom-Json
$redisChoices = $redisCaches | ForEach-Object { $_.name }

# Perguntar ao usuário para selecionar o Redis Cache
$selectedRedis = $redisChoices | Out-GridView -Title "Escolha o Redis Cache desejado" -PassThru

# Obter os detalhes do Redis Cache selecionado
$selectedRedisDetails = $redisCaches | Where-Object { $_.name -eq $selectedRedis }
$hostname = $selectedRedisDetails.hostName
$resourceGroup = $selectedRedisDetails.resourceGroup

# Obter a chave primária do Redis
$keys = az redis list-keys --name $selectedRedis --resource-group $resourceGroup --output json | ConvertFrom-Json
$primaryKey = $keys.primaryKey

# Função para suprimir o aviso de senha
function Suppress-Warning {
    param ($ScriptBlock)
    $Output = $null
    $ErrorActionPreference = 'Stop'
    try {
        $Output = &$ScriptBlock 2>&1 | Out-String
    } catch {
        Write-Error $_.Exception.Message
    }
    return $Output
}

# Verificar se a chave primária foi obtida
if ($primaryKey) {
    $ports = @(6380, 6379)
    $connected = $false

    foreach ($port in $ports) {
        try {
            Write-Output "Tentando conectar na porta $port..."
            
            # Testar conexão na porta atual
            $testConnection = Suppress-Warning { redis-cli -h $hostname -p $port -a $primaryKey --no-auth-warning PING }
            Write-Output "Resultado do teste de conexão: $testConnection"
            
            if ($testConnection -like "*PONG*") {
                $connected = $true
                Write-Output "Conectado ao Redis Cache: $selectedRedis (Hostname: $hostname, Porta: $port)"
                break
            } else {
                Write-Error "Erro ao conectar no Redis: Resposta inesperada '$testConnection'"
            }
        } catch {
            Write-Error "Falha ao conectar na porta ${port}: $_"
        }
    }

    if ($connected) {
        # Loop interativo para executar comandos no Redis
        while ($true) {
            $command = Read-Host "Digite um comando para executar no Redis (ou 'exit' para sair)"
            if ($command -eq 'exit') {
                Write-Output "Saindo..."
                break
            }
            try {
                $scriptBlock = {
                    if ($port -eq 6380) {
                        redis-cli -h $hostname -p $port -a $primaryKey --tls --no-auth-warning $command
                    } else {
                        redis-cli -h $hostname -p $port -a $primaryKey --no-auth-warning $command
                    }
                }
                $result = Suppress-Warning $scriptBlock
                Write-Output $result
            } catch {
                Write-Error "Erro ao executar o comando: $_"
            }
        }
    } else {
        Write-Error "Não foi possível conectar ao Redis nas portas 6379 e 6380."
    }
} else {
    Write-Error "Erro ao obter a chave primária do Redis."
}
