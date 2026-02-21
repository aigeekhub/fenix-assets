$ErrorActionPreference='Stop'
$taskName='FENIX-AssetPipeline-Watcher'
$pipeDir="$env:USERPROFILE\fenix-assets\pipelines"
$watcher=Join-Path $pipeDir 'watch-assets.ps1'
$pushPro=Join-Path $pipeDir 'push-assets.pro.ps1'
$pushBase=Join-Path $pipeDir 'push-assets.ps1'
$watchLog=Join-Path $pipeDir 'logs\watch-assets.log'

$args=@(
 '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
 '-File',('"{0}"' -f $watcher),
 '-StagingPath','"C:\app-logos"',
 '-PushScript',('"{0}"' -f $pushPro),
 '-BasePushScript',('"{0}"' -f $pushBase),
 '-LogPath',('"{0}"' -f $watchLog)
) -join ' '

$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Days 3650) -Hidden -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){ Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output "Installed and started: $taskName"

