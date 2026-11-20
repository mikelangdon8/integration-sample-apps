# Generate the load that the Microsoft IIS integration's panels and alerts read
param(
    [int]$DurationSeconds = 600,
    [int]$FailureIntervalSeconds = 40
)

$ErrorActionPreference = "Continue"
Import-Module WebAdministration

$helpers = {
    function Invoke-Http {
        param([string]$Method, [string]$Url, [string]$Body = "", [switch]$UseDefaultCredentials, [int]$TimeoutMs = 10000)
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = $Method
        $request.Timeout = $TimeoutMs
        $request.UseDefaultCredentials = [bool]$UseDefaultCredentials
        try {
            if ($Body) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
                $request.ContentType = "text/xml"
                $request.ContentLength = $bytes.Length
                $stream = $request.GetRequestStream()
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Close()
            } elseif ($Method -eq "PUT") {
                $request.ContentLength = 0
            }
            $response = $request.GetResponse()
            $code = [int]$response.StatusCode
            $response.Close()
        } catch [System.Net.WebException] {
            $code = 0
            if ($_.Exception.Response) {
                $code = [int]$_.Exception.Response.StatusCode
                $_.Exception.Response.Close()
            }
        } catch {
            $code = 0
        }
        return $code
    }
}

$endTime = (Get-Date).AddSeconds($DurationSeconds)
$jobs = @()

Write-Host "Starting web traffic to every site..."
$jobs += Start-Job -InitializationScript $helpers -ArgumentList $endTime -ScriptBlock {
    param($EndTime)
    $i = 0
    while ((Get-Date) -lt $EndTime) {
        $i++
        foreach ($port in 8081, 8083, 8084, 8085, 8086) {
            foreach ($path in "/", "/static/site.css", "/static/logo.svg", "/cached.aspx", "/missing-$i.html", "/broken/") {
                Invoke-Http -Method GET -Url "http://localhost:$port$path" | Out-Null
            }
            Invoke-Http -Method HEAD -Url "http://localhost:$port/" | Out-Null
            Invoke-Http -Method POST -Url "http://localhost:$port/cached.aspx" -Body "<form />" | Out-Null
        }
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "Starting slow requests, so worker threads are busy when Alloy collects..."
for ($n = 1; $n -le 8; $n++) {
    $port = if ($n % 2) { 8081 } else { 8088 }
    $jobs += Start-Job -InitializationScript $helpers -ArgumentList $endTime, $port -ScriptBlock {
        param($EndTime, $Port)
        while ((Get-Date) -lt $EndTime) {
            Invoke-Http -Method GET -Url "http://localhost:$Port/slow.aspx" -TimeoutMs 15000 | Out-Null
            Start-Sleep -Milliseconds 100
        }
    }
}

Write-Host "Starting WebSocket connections..."
$jobs += Start-Job -ArgumentList $endTime -ScriptBlock {
    param($EndTime)
    $none = [System.Threading.CancellationToken]::None
    while ((Get-Date) -lt $EndTime) {
        foreach ($url in "ws://localhost:8081/echo.ashx", "ws://localhost:8081/index.html") {
            $socket = New-Object System.Net.WebSockets.ClientWebSocket
            try {
                $socket.ConnectAsync([Uri]$url, $none).Wait(10000) | Out-Null
                if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                    $message = [System.Text.Encoding]::UTF8.GetBytes("hello")
                    $buffer = New-Object byte[] 1024
                    for ($m = 1; $m -le 3; $m++) {
                        $socket.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(, $message)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $none).Wait(5000) | Out-Null
                        $socket.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList @(, $buffer)), $none).Wait(5000) | Out-Null
                    }
                    $socket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $none).Wait(5000) | Out-Null
                }
            } catch {
            } finally {
                $socket.Dispose()
            }
        }
        Start-Sleep -Seconds 2
    }
}

Write-Host "Starting WebDAV uploads and locked-file writes..."
$jobs += Start-Job -InitializationScript $helpers -ArgumentList $endTime -ScriptBlock {
    param($EndTime)
    $dav = "http://localhost:8081/dav"
    $lockBody = '<?xml version="1.0" encoding="utf-8"?><D:lockinfo xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype><D:owner>sample-app</D:owner></D:lockinfo>'
    Invoke-Http -Method PUT -Url "$dav/locked.txt" -Body "locked" -UseDefaultCredentials | Out-Null
    Invoke-Http -Method LOCK -Url "$dav/locked.txt" -Body $lockBody -UseDefaultCredentials | Out-Null
    $i = 0
    while ((Get-Date) -lt $EndTime) {
        $i++
        Invoke-Http -Method PUT -Url "$dav/upload-$($i % 20).txt" -Body "upload $i" -UseDefaultCredentials | Out-Null
        Invoke-Http -Method PUT -Url "$dav/locked.txt" -Body "write $i" -UseDefaultCredentials | Out-Null
        Start-Sleep -Seconds 1
    }
}

Write-Host "Starting downloads from the bandwidth-throttled site..."
# A download that IIS rejects returns at once, so each loop pauses before the next attempt.
for ($n = 1; $n -le 4; $n++) {
    $jobs += Start-Job -InitializationScript $helpers -ArgumentList $endTime -ScriptBlock {
        param($EndTime)
        while ((Get-Date) -lt $EndTime) {
            Invoke-Http -Method GET -Url "http://localhost:8082/download.bin" -TimeoutMs 20000 | Out-Null
            Start-Sleep -Seconds 1
        }
    }
}

Write-Host "Suspending each new pool-slowstart worker as soon as it appears..."
$jobs += Start-Job -ArgumentList $endTime -ScriptBlock {
    param($EndTime)
    Add-Type -Namespace SampleApp -Name Native -MemberDefinition '[DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr processHandle);'
    $seen = @{}
    while ((Get-Date) -lt $EndTime) {
        foreach ($process in Get-Process -Name w3wp -ErrorAction SilentlyContinue) {
            if ($seen.ContainsKey($process.Id)) { continue }
            $seen[$process.Id] = $true
            $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
            if ($commandLine -match '-ap "pool-slowstart"') {
                [SampleApp.Native]::NtSuspendProcess($process.Handle) | Out-Null
            }
        }
        Start-Sleep -Milliseconds 100
    }
}

Add-Type -Namespace SampleApp -Name Native -MemberDefinition '[DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr processHandle);'
. $helpers

function Get-PoolWorker([string]$pool) {
    Get-CimInstance Win32_Process -Filter "Name='w3wp.exe'" |
        Where-Object { $_.CommandLine -match "-ap `"$pool`"" } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
}

Write-Host "Causing worker process failures every $FailureIntervalSeconds seconds..."
while ((Get-Date) -lt $endTime) {
    Invoke-Http -Method GET -Url "http://localhost:8083/" | Out-Null
    Get-PoolWorker "pool-crash" | Stop-Process -Force -ErrorAction SilentlyContinue

    Invoke-Http -Method GET -Url "http://localhost:8084/" | Out-Null
    Get-PoolWorker "pool-hang" | ForEach-Object { [SampleApp.Native]::NtSuspendProcess($_.Handle) | Out-Null }

    Invoke-Http -Method GET -Url "http://localhost:8085/" | Out-Null
    Get-PoolWorker "pool-stuck" | ForEach-Object { [SampleApp.Native]::NtSuspendProcess($_.Handle) | Out-Null }
    Restart-WebAppPool -Name "pool-stuck" -ErrorAction SilentlyContinue

    Invoke-Http -Method GET -Url "http://localhost:8087/" -TimeoutMs 2000 | Out-Null

    if ((Get-WebAppPoolState -Name "pool-badid").Value -ne "Started") {
        Start-WebAppPool -Name "pool-badid" -ErrorAction SilentlyContinue
    }
    Invoke-Http -Method GET -Url "http://localhost:8086/" | Out-Null

    Start-Sleep -Seconds $FailureIntervalSeconds
}

$jobs | Stop-Job -PassThru | Remove-Job
Write-Host "Load generation completed."
