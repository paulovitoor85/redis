# Função para verificar se rdcli está instalado
function Check-Rdcli {
    $rdcliPath = (Get-Command rdcli -ErrorAction SilentlyContinue).Path
    if (-not $rdcliPath) {
        Write-Error "rdcli não está instalado ou não está no PATH do sistema. Por favor, instale rdcli e adicione-o ao PATH."
        exit
    }
}

# Função para verificar se uma porta está aberta
function Test-Port {
    param (
        [string]$hostname,
        [int]$port
    )
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    try {
        $tcpClient.Connect($hostname, $port)
        $tcpClient.Close()
        return $true
    } catch {
        return $false
    }
}

# Verificar se rdcli está instalado
Check-Rdcli

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

# Verificar se a chave primária foi obtida
if ($primaryKey) {
    Write-Output "Verificando portas disponíveis no Redis '$selectedRedis'..."

    # Verificar disponibilidade das portas
    $port = 6379
    if (Test-Port -hostname $hostname -port 6380) {
        $port = 6380
    } elseif (Test-Port -hostname $hostname -port 6379) {
        $port = 6379
    } else {
        Write-Error "Nenhuma porta disponível foi encontrada para o Redis '$selectedRedis'."
        exit
    }

    Write-Output "Conectando ao Redis '$selectedRedis' na porta $port..."

    # Estabelecer conexão com o Redis sem exibir a chave
    try {
        # Loop interativo para executar comandos no Redis
        while ($true) {
            $command = Read-Host "Digite um comando para executar no Redis (ou 'exit' para sair)"
            if ($command -eq 'exit') {
                Write-Output "Saindo..."
                break
            }
            try {
                $result = & rdcli -h $hostname -a $primaryKey $command 2>$null
                Write-Output "Resultado: $result"
            } catch {
                Write-Error "Erro ao executar o comando: $_"
            }
        }
    } catch {
        Write-Error "Erro ao conectar ao Redis: $_"
    }
} else {
    Write-Error "Erro ao obter a chave primária do Redis."
}
