param([switch]$Configure, [switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$PortalUrl = 'http://111.17.200.130/a79.htm'
$ConfigDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CampusLogin-11117200130'
$CredentialFile = Join-Path $ConfigDir 'credential.xml'


if (-not $CheckOnly) { Add-Type -AssemblyName System.Windows.Forms }
if (-not $CheckOnly) { Add-Type -AssemblyName System.Drawing }
if (-not $CheckOnly) { [System.Windows.Forms.Application]::EnableVisualStyles() }
if (-not $CheckOnly -and ([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Shift)) { $Configure = $true }

function Show-Notice([string]$Message, [string]$Title = '校园网助手 1.1') {
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title)
}

function Read-LoginCredential {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = '首次设置校园网账号'
    $form.ClientSize = New-Object System.Drawing.Size(440, 250)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $note = New-Object System.Windows.Forms.Label
    $note.Text = "请输入校园网登录页使用的账号密码。`r`n密码由 Windows 加密保存，仅供当前 Windows 用户使用。"
    $note.SetBounds(20, 16, 400, 45)
    $accountLabel = New-Object System.Windows.Forms.Label
    $accountLabel.Text = '账号 / 手机号'
    $accountLabel.SetBounds(20, 78, 105, 24)
    $account = New-Object System.Windows.Forms.TextBox
    $account.SetBounds(135, 75, 280, 26)
    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.Text = '校园网密码'
    $passwordLabel.SetBounds(20, 121, 105, 24)
    $password = New-Object System.Windows.Forms.TextBox
    $password.UseSystemPasswordChar = $true
    $password.SetBounds(135, 118, 280, 26)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '保存并连接'
    $ok.SetBounds(200, 185, 110, 32)
    $ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($account.Text) -or $password.Text.Length -eq 0) {
            Show-Notice '请填写账号和密码。'
            return
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.SetBounds(320, 185, 95, 32)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Controls.AddRange(@($note, $accountLabel, $account, $passwordLabel, $password, $ok, $cancel))
    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        $secret = ConvertTo-SecureString -String $password.Text -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential($account.Text.Trim(), $secret)
    } finally {
        $password.Clear()
        $form.Dispose()
    }
}

function Write-Step([string]$Message) {
    $line = (Get-Date -Format 'HH:mm:ss') + ' ' + $Message
    Write-Host $line
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Get-LocalJson([string]$Url) {
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Proxy = $null
    $request.Timeout = 1500
    $request.ReadWriteTimeout = 1500
    $response = $request.GetResponse()
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
        finally { $reader.Dispose() }
    } finally { $response.Dispose() }
}

function Invoke-Cdp([string]$Method, [hashtable]$Params = @{}, [int]$Timeout = 10000) {
    $script:CdpId++
    $id = $script:CdpId
    $json = @{id = $id; method = $Method; params = $Params} | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $cancel = New-Object System.Threading.CancellationTokenSource
    $cancel.CancelAfter($Timeout)
    try {
        [void]($script:Socket.SendAsync([System.ArraySegment[byte]]::new($bytes),
            [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cancel.Token).GetAwaiter().GetResult())
        while ($true) {
            $memory = New-Object System.IO.MemoryStream
            try {
                do {
                    $buffer = New-Object byte[] 16384
                    $received = $script:Socket.ReceiveAsync([System.ArraySegment[byte]]::new($buffer), $cancel.Token).GetAwaiter().GetResult()
                    if ($received.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { throw '浏览器连接已关闭。' }
                    $memory.Write($buffer, 0, $received.Count)
                    if ($memory.Length -gt 8MB) { throw '浏览器响应过大。' }
                } while (-not $received.EndOfMessage)
                $message = [System.Text.Encoding]::UTF8.GetString($memory.ToArray()) | ConvertFrom-Json
            } finally { $memory.Dispose() }
            if ($message.method -eq 'Network.responseReceived') {
                $networkUri = [Uri]$message.params.response.url
                if ($networkUri.Host -eq '111.17.200.130') {
                    # Deliberately omit queries, request bodies, and response bodies.
                    Write-Step ('网页请求 HTTP ' + $message.params.response.status + ' ' + $networkUri.AbsolutePath)
                    if ($networkUri.AbsolutePath -eq '/eportal/portal/login' -and $null -ne $script:AuthResponseIds) {
                        $script:AuthResponseIds[[string]$message.params.requestId] = $true
                    }
                }
            }
            if ($message.method -eq 'Network.loadingFinished' -and $null -ne $script:AuthResponseIds) {
                $finishedId = [string]$message.params.requestId
                if ($script:AuthResponseIds.ContainsKey($finishedId)) {
                    [void]$script:AuthResponseIds.Remove($finishedId)
                    $script:ReadyAuthResponses.Add($finishedId)
                }
            }
            if ($message.id -eq $id) {
                if ($null -ne $message.error) { throw ('浏览器命令失败：' + $Method) }
                return $message.result
            }
        }
    } finally { $cancel.Dispose() }
}

function Invoke-Page([string]$Expression) {
    $result = Invoke-Cdp 'Runtime.evaluate' @{expression = $Expression; returnByValue = $true}
    if ($null -ne $result.exceptionDetails) { throw '网页程序执行失败。' }
    return $result.result.value
}

function Read-AuthenticationReply {
    foreach ($requestId in @($script:ReadyAuthResponses.ToArray())) {
        [void]$script:ReadyAuthResponses.Remove($requestId)
        try {
            $body = Invoke-Cdp 'Network.getResponseBody' @{requestId = $requestId}
            $text = $body.body
            if ($body.base64Encoded) { $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($text)) }
            $data = $text | ConvertFrom-Json -ErrorAction Stop
            foreach ($object in @($data, $data.data)) {
                if ($null -eq $object) { continue }
                foreach ($key in @('message', 'msg', 'error_msg', 'errorMessage', 'error_message', 'retmsg')) {
                    $property = $object.PSObject.Properties[$key]
                    if ($null -ne $property -and $property.Value -is [string] -and $property.Value.Length -gt 0) {
                        return Protect-Message $property.Value
                    }
                }
                foreach ($key in @('error_code', 'errorCode', 'code')) {
                    $property = $object.PSObject.Properties[$key]
                    if ($null -ne $property -and [string]$property.Value -match '^[A-Za-z0-9_-]{1,32}$') {
                        Write-Step ('服务器返回代码：' + $property.Value)
                    }
                }
            }
        } catch {
            # HTML responses and unavailable bodies are not copied to the log.
        }
    }
    return ''
}

function Test-Internet {
    try {
        $request = [System.Net.HttpWebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $request.Proxy = $null
        $request.AllowAutoRedirect = $false
        $request.Timeout = 3000
        $request.ReadWriteTimeout = 3000
        $request.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
        $response = $request.GetResponse()
        try {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            try { return ([int]$response.StatusCode -eq 200 -and $reader.ReadToEnd().Trim() -eq 'Microsoft Connect Test') }
            finally { $reader.Dispose() }
        } finally { $response.Dispose() }
    } catch { return $false }
}

function Get-ConnectionOutcome([string]$State, [bool]$Internet, [bool]$Submitted) {
    if ($State -eq 'Failed') { return 'Rejected' }
    if ($State -eq 'LoggedIn' -and $Internet) { return 'Connected' }
    if ($State -eq 'LoggedIn') { return 'AuthenticatedOnly' }
    if ($Internet -and $Submitted) { return 'InternetOnly' }
    return 'Unconfirmed'
}

function Test-RejectionMessage([string]$Message) {
    return $Message -match '错误|失败|拒绝|无效|欠费|停机|密码.{0,8}不|账号.{0,8}不|error|fail|denied|invalid'
}

function Protect-Message([string]$Message) {
    if ($null -ne $script:Credential) {
        foreach ($secret in @($script:Credential.UserName, $script:Credential.GetNetworkCredential().Password)) {
            if (-not [string]::IsNullOrEmpty($secret)) {
                $Message = $Message.Replace($secret, '[已隐藏]')
                $Message = $Message.Replace([Uri]::EscapeDataString($secret), '[已隐藏]')
            }
        }
    }
    $Message = $Message -replace '[\r\n]+', ' '
    if ($Message.Length -gt 240) { $Message = $Message.Substring(0, 240) }
    return $Message
}

if ($CheckOnly) { return }

$mutex = New-Object System.Threading.Mutex($false, 'Local\CampusLogin-11117200130')
$locked = $false
$browser = $null
$script:Socket = $null
$script:Credential = $null
$script:CdpId = 0
$script:AuthResponseIds = @{}
$script:ReadyAuthResponses = New-Object 'System.Collections.Generic.List[string]'
$stage = '初始化'
try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { Show-Notice '连接程序已在运行，请等待它完成。'; return }
    [void][System.IO.Directory]::CreateDirectory($ConfigDir)
    $script:LogFile = Join-Path $ConfigDir 'diagnostic.txt'
    Set-Content -LiteralPath $script:LogFile -Value '校园网助手 1.1：使用原网页登录按钮' -Encoding UTF8
    Write-Step '兼容修复版 1.1 开始连接；不要求事先能访问互联网。'
    $stage = '读取账号'
    if ($Configure -or -not (Test-Path -LiteralPath $CredentialFile)) {
        $script:Credential = Read-LoginCredential
        if ($null -eq $script:Credential) { return }
        $script:Credential | Export-Clixml -LiteralPath $CredentialFile
    } else {
        $script:Credential = Import-Clixml -LiteralPath $CredentialFile
    }
    if ($script:Credential -isnot [System.Management.Automation.PSCredential]) { throw '保存的账号格式不正确。' }
    Write-Step '已读取本机加密保存的账号。'

    $stage = '启动 Edge'
    $edgePaths = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
    )
    $edge = $edgePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edge) { throw '未找到 Microsoft Edge。' }
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $profile = Join-Path $ConfigDir 'browser-profile-v2'
    $arguments = @('--headless=new', '--no-first-run', '--no-default-browser-check',
        '--disable-background-networking', '--no-proxy-server', '--window-size=1400,1000',
        '--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$port",
        ('--user-data-dir="' + $profile + '"'), 'about:blank')
    $browser = Start-Process -FilePath $edge -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $target = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        try {
            $targets = @(Get-LocalJson "http://127.0.0.1:$port/json/list")
            $target = $targets | Where-Object { $_.type -eq 'page' -and $_.url -eq 'about:blank' } | Select-Object -First 1
        } catch {}
        if ($null -eq $target) { Start-Sleep -Milliseconds 500 }
    } while ($null -eq $target -and [DateTime]::UtcNow -lt $deadline)
    if ($null -eq $target) { throw 'Edge 自动化启动失败，可能被系统策略限制。' }
    $script:Socket = New-Object System.Net.WebSockets.ClientWebSocket
    $script:Socket.Options.Proxy = $null
    $cancel = New-Object System.Threading.CancellationTokenSource
    $cancel.CancelAfter(10000)
    try { [void]($script:Socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $cancel.Token).GetAwaiter().GetResult()) }
    finally { $cancel.Dispose() }
    [void](Invoke-Cdp 'Page.enable')
    [void](Invoke-Cdp 'Network.enable')
    [void](Invoke-Cdp 'Network.setCacheDisabled' @{cacheDisabled = $true})
    $automation = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PortalAutomation.js'))
    # The alert hook must exist before the page's own scripts execute.
    [void](Invoke-Cdp 'Page.addScriptToEvaluateOnNewDocument' @{source = "window.__campusLastAlert='';window.alert=function(m){window.__campusLastAlert=String(m);};window.__campusAlertHooked=true;"})
    Write-Step 'Edge 已启动，使用独立配置，不读取 Edge 保存的密码。'

    $stage = '加载校园登录页'
    [void](Invoke-Cdp 'Page.navigate' @{url = $PortalUrl})
    $status = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(50)
    $lastReload = [DateTime]::UtcNow
    do {
        Start-Sleep -Milliseconds 700
        try {
            $status = Invoke-Page $automation
            if ($status.host -ne '111.17.200.130') { $status = $null }
        } catch { $status = $null }
        if ($null -ne $status -and ($status.ready -or $status.state -eq 'LoggedIn')) { break }
        if (([DateTime]::UtcNow - $lastReload).TotalSeconds -gt 12) {
            Write-Step '登录页尚未就绪，重新加载。'
            [void](Invoke-Cdp 'Page.navigate' @{url = $PortalUrl})
            $lastReload = [DateTime]::UtcNow
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($null -eq $status) { throw '无法加载校园登录页。' }
    Write-Step ('页面状态=' + $status.state + '；可见输入框=' + $status.inputCount + '；登录按钮=' + $status.buttonCount)
    $submitted = $false
    if ($status.state -ne 'LoggedIn') {
        if (-not $status.ready) { throw '未找到唯一的账号框、密码框和登录按钮。' }
        $stage = '填写账号并点击网页登录按钮'
        if (-not (Invoke-Page "window.__campusAutomation.focusField('account')")) { throw '无法聚焦账号输入框。' }
        [void](Invoke-Cdp 'Input.insertText' @{text = $script:Credential.UserName})
        if (-not (Invoke-Page "window.__campusAutomation.focusField('password')")) { throw '无法聚焦密码输入框。' }
        [void](Invoke-Cdp 'Input.insertText' @{text = $script:Credential.GetNetworkCredential().Password})
        [void](Invoke-Cdp 'Input.dispatchKeyEvent' @{type = 'keyDown'; key = 'Tab'; code = 'Tab'; windowsVirtualKeyCode = 9})
        [void](Invoke-Cdp 'Input.dispatchKeyEvent' @{type = 'keyUp'; key = 'Tab'; code = 'Tab'; windowsVirtualKeyCode = 9})
        $userJson = ConvertTo-Json -InputObject $script:Credential.UserName -Compress
        $passwordJson = ConvertTo-Json -InputObject $script:Credential.GetNetworkCredential().Password -Compress
        try { $filled = Invoke-Page ("window.__campusAutomation.checkFilled($userJson,$passwordJson)") }
        finally { $userJson = $null; $passwordJson = $null }
        if (-not $filled) { throw '网页未完整保留输入的账号或密码。' }
        Write-Step '已通过浏览器真实输入事件填写并校验账号密码。'
        $point = Invoke-Page 'window.__campusAutomation.buttonPoint()'
        [void](Invoke-Cdp 'Input.dispatchMouseEvent' @{type = 'mousePressed'; x = $point.x; y = $point.y; button = 'left'; clickCount = 1})
        [void](Invoke-Cdp 'Input.dispatchMouseEvent' @{type = 'mouseReleased'; x = $point.x; y = $point.y; button = 'left'; clickCount = 1})
        $submitted = $true
        Write-Step '已点击原网页的登录按钮，由网页自己的 JavaScript 提交认证。'
    }

    $stage = '等待认证结果并验证联网'
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    $internet = $false
    $alert = ''
    $rejected = $false
    do {
        Start-Sleep -Milliseconds 900
        try {
            $current = Invoke-Page $automation
            if ($current.host -eq '111.17.200.130') {
                $status = $current
                $pageMessage = if ($current.alert) { $current.alert } else { $current.error }
                if ($pageMessage) {
                    $rejected = Test-RejectionMessage $pageMessage
                    $alert = Protect-Message $pageMessage
                }
            }
        } catch {}
        $serverMessage = Read-AuthenticationReply
        if ($serverMessage) {
            $alert = $serverMessage
            $rejected = $rejected -or (Test-RejectionMessage $serverMessage)
        }
        if ($status.state -eq 'Failed' -or $rejected) { break }
        $internet = Test-Internet
        if ($internet) { break }
    } while ([DateTime]::UtcNow -lt $deadline)
    $finalState = if ($rejected) { 'Failed' } else { $status.state }
    $outcome = Get-ConnectionOutcome $finalState $internet $submitted
    Write-Step ('认证后页面状态=' + $status.state + '；互联网检测=' + $internet + '；结果=' + $outcome)
    if ($alert) { Write-Step ('网页提示：' + $alert) }
    switch ($outcome) {
        'Connected' { Show-Notice '校园网认证成功，已确认可以访问互联网。' }
        'InternetOnly' { Show-Notice '已点击网页登录，并确认现在可以访问互联网。' }
        'AuthenticatedOnly' { Show-Notice "网页显示认证成功，但尚未确认互联网可访问。`r`n详细过程记录在：$script:LogFile" }
        default {
            $detail = if ($alert) { "`r`n网页提示：$alert" } else { '' }
            Show-Notice "未确认连接成功。失败阶段：$stage$detail`r`n诊断记录：$script:LogFile"
            Start-Process $PortalUrl
        }
    }
} catch {
    if ($script:LogFile) {
        Write-Step ('失败阶段：' + $stage)
        $knownErrors = @('保存的账号格式不正确。', '未找到 Microsoft Edge。',
            'Edge 自动化启动失败，可能被系统策略限制。', '无法加载校园登录页。',
            '未找到唯一的账号框、密码框和登录按钮。', '浏览器连接已关闭。', '网页程序执行失败。',
            '无法聚焦账号输入框。', '无法聚焦密码输入框。', '网页未完整保留输入的账号或密码。')
        if ($knownErrors -contains $_.Exception.Message) { Write-Step $_.Exception.Message }
        else { Write-Step ('异常类型：' + $_.Exception.GetType().Name) }
    }
    # Exception payloads may include evaluated JS, so never dump exception text.
    Show-Notice "连接失败。阶段：$stage`r`n诊断记录：$script:LogFile"
    if ($stage -ne '读取账号' -and $stage -ne '初始化') { Start-Process $PortalUrl }
} finally {
    if ($null -ne $script:Socket) {
        if ($script:Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            try { [void](Invoke-Cdp 'Browser.close' @{} 2000) } catch {}
        }
        $script:Socket.Dispose()
    }
    if ($null -ne $browser) {
        try { if (-not $browser.HasExited) { Stop-Process -Id $browser.Id -ErrorAction SilentlyContinue } } catch {}
        $browser.Dispose()
    }
    $script:Credential = $null
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
