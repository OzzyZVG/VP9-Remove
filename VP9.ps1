# Caminho para o arquivo com a lista de computadores
$computerListPath = "C:\\Temp\\computer_list3.txt"
$computerDonePath = "C:\\Temp\\VP9_removal_log.txt"

# Solicita credenciais para a sessão remota
$credentials = Get-Credential -Message "Digite as credenciais de administrador"

# Lê os hostnames dos computadores
$computers = Get-Content -Path $computerListPath

# Lista para armazenar os computadores não processados
$computersNotProcessed = @()

# Loop através de cada computador
foreach ($computer in $computers) {
    $processed = $false
    Write-Host "Verificando conectividade com o computador: $computer"

    # Testa a conectividade com ping
    $pingable = Test-Connection -ComputerName $computer -Count 1 -Quiet
    if ($pingable) {
        Write-Host "Conectando-se ao computador: $computer"

        # Testa a conectividade WS-Management
        if (Test-WSMan -ComputerName $computer -ErrorAction SilentlyContinue) {
            # Aplica parâmetros base para o processo
            $SessionArgs = @{
                ComputerName  = $computer
                SessionOption = New-CimSessionOption -Protocol Dcom
                Credential    = $credentials
            }

            # Configuração base para habilitar RemotePS
            $MethodArgs = @{
                ClassName     = 'Win32_Process'
                MethodName    = 'Create'
                CimSession    = New-CimSession @SessionArgs
                Arguments     = @{
                    CommandLine = "powershell Start-Process powershell -ArgumentList 'Enable-PSRemoting -Force'"
                }
            }

            # Executa a configuração base no host usando a declaração WMI
            Invoke-CimMethod @MethodArgs

            # Estabelece uma sessão remota com credenciais
            $session = New-PSSession -ComputerName $computer -Credential $credentials -ErrorAction SilentlyContinue

            if ($session) {
                # Verifica se o VP9 Video Extensions está instalado
                $vp9Installed = Invoke-Command -Session $session -ScriptBlock {
                    $vp9Paths = @(
                        "C:\\Program Files\\WindowsApps\\Microsoft.VP9VideoExtensions_*",
                        "C:\\Program Files\\WindowsApps\\Microsoft.VP9VideoExtensions_1.0.42791.0_x64__8wekyb3d8bbwe"
                    )
                    foreach ($path in $vp9Paths) {
                        if (Test-Path -Path $path) {
                            return $true
                        }
                    }
                    return $false
                }

                if ($vp9Installed) {
                    Write-Host "VP9 Video Extensions encontrado. Removendo..."
                    Invoke-Command -Session $session -ScriptBlock {
                        Get-AppxPackage -Name "Microsoft.VP9VideoExtensions" | Remove-AppxPackage -ErrorAction SilentlyContinue
                    }

                    # Adiciona o computador à lista de concluídos
                    Add-Content -Path $computerDonePath -Value "$computer - VP9 Video Extensions removido com sucesso"
                    $processed = $true
                } else {
                    Write-Host "VP9 Video Extensions não encontrado no computador: $computer"
                    Add-Content -Path $computerDonePath -Value "$computer - Não encontrado VP9"
                    $processed = $true
                }

                # Fecha a sessão remota
                Remove-PSSession -Session $session
            } else {
                Write-Host "Não foi possível estabelecer uma sessão remota com o computador: $computer"
            }
        } else {
            Write-Host "WS-Management não está respondendo no computador: $computer"
        }
    } else {
        Write-Host "Não foi possível conectar-se ao computador: $computer"
    }

    # Adiciona o computador à lista de não processados se necessário
    if (-not $processed) {
        $computersNotProcessed += $computer
    }
}

# Atualiza o arquivo computer_list.txt com os computadores não processados
Set-Content -Path $computerListPath -Value $computersNotProcessed

Write-Host "Processamento concluído."
