Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Decode-DigitalProductId {
    param([byte[]]$DigitalId)
    if (-not $DigitalId -or $DigitalId.Length -lt 67) { return $null }
    try {
        $chars = 'BCDFGHJKMPQRTVWXY2346789'
        $key = ''
        $isWin8OrNewer = [math]::Truncate($DigitalId[66] / 6) -band 1
        $DigitalId[66] = ($DigitalId[66] -band 0xF7) -bor (($isWin8OrNewer -band 2) * 4)

        for ($i = 24; $i -ge 0; $i--) {
            $current = 0
            for ($j = 14; $j -ge 0; $j--) {
                $current = $current * 256 -bxor $DigitalId[$j + 52]
                $DigitalId[$j + 52] = [math]::Truncate($current / 24)
                $current = $current % 24
            }
            $key = $chars[$current] + $key
        }

        if ($isWin8OrNewer -eq 1) {
            $insert = $key.Substring(1, $current)
            $key = $key.Substring(1).Replace($insert, $insert + 'N')
        }

        $decoded = ($key -replace '(.{5})(?!$)', '$1-')
        if ($decoded -match '^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$') {
            return $decoded
        }
    } catch {}
    return $null
}

function Get-LicenseDetails {
    $winAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    $foundKey = $null
    $keySource = 'None'

    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $sls = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction SilentlyContinue
        $slp = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='$winAppId' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue
    } else {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue
        $sls = Get-WmiObject -Class SoftwareLicensingService -ErrorAction SilentlyContinue
        $slp = Get-WmiObject -Class SoftwareLicensingProduct -Filter "ApplicationID='$winAppId' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue
    }

    if (-not [string]::IsNullOrWhiteSpace($sls.OA3xOriginalProductKey)) {
        $foundKey = $sls.OA3xOriginalProductKey
        $keySource = 'BIOS / UEFI'
    }

    if (-not $foundKey) {
        try {
            $sppPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
            $regKey = (Get-ItemProperty -Path $sppPath -Name BackupProductKeyDefault -ErrorAction SilentlyContinue).BackupProductKeyDefault
            if (-not [string]::IsNullOrWhiteSpace($regKey)) {
                $foundKey = $regKey
                $keySource = 'Registry (SPP)'
            }
        } catch {}
    }

    if (-not $foundKey) {
        try {
            $cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            $digitalId = (Get-ItemProperty -Path $cvPath -ErrorAction SilentlyContinue).DigitalProductId
            $decoded = Decode-DigitalProductId -DigitalId $digitalId
            if ($decoded) {
                $foundKey = $decoded
                $keySource = 'Registry (DigitalProductId)'
            }
        } catch {}
    }

    $isActivated = ($slp.LicenseStatus -eq 1)
    $daysLeft = if ($slp.GracePeriodRemaining -gt 0) { "$([math]::Round($slp.GracePeriodRemaining / 1440, 1)) days" } else { 'Permanent / Digital' }

    return [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        Edition      = if ($os.Caption) { $os.Caption } else { 'Unknown' }
        IsActivated  = $isActivated
        StatusText   = if ($isActivated) { 'Activated' } else { 'Not Activated' }
        Channel      = if ($slp.ProductKeyChannel) { $slp.ProductKeyChannel } else { 'Unknown' }
        FullKey      = if ($foundKey) { $foundKey } else { 'None (Digital License)' }
        HasRawKey    = [bool]$foundKey
        KeySource    = $keySource
        DaysLeft     = $daysLeft
    }
}

$bgDark   = [System.Drawing.Color]::FromArgb(30, 30, 30)
$bgPanel  = [System.Drawing.Color]::FromArgb(42, 42, 42)
$fgLight  = [System.Drawing.Color]::FromArgb(240, 240, 240)
$fgMuted  = [System.Drawing.Color]::FromArgb(170, 170, 170)
$danger   = [System.Drawing.Color]::FromArgb(196, 43, 28)
$success  = [System.Drawing.Color]::FromArgb(16, 137, 62)

$form = New-Object System.Windows.Forms.Form
$form.Text = "License & Key Check"
$form.Size = New-Object System.Drawing.Size(520, 410)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $bgDark
$form.ForeColor = $fgLight
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Windows License Info"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(20, 52)
$panel.Size = New-Object System.Drawing.Size(465, 195)
$panel.BackColor = $bgPanel
$form.Controls.Add($panel)

function Add-InfoRow {
    param([int]$Y, [string]$Label)
    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = $Label
    $l1.ForeColor = $fgMuted
    $l1.Location = New-Object System.Drawing.Point(15, $Y)
    $l1.Size = New-Object System.Drawing.Size(120, 22)
    $panel.Controls.Add($l1)

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = "..."
    $l2.ForeColor = $fgLight
    $l2.Location = New-Object System.Drawing.Point(140, $Y)
    $l2.Size = New-Object System.Drawing.Size(310, 22)
    $panel.Controls.Add($l2)
    return $l2
}

$valHost    = Add-InfoRow -Y 15  -Label "Computer:"
$valEdition = Add-InfoRow -Y 43  -Label "Edition:"
$valStatus  = Add-InfoRow -Y 71  -Label "Status:"
$valChannel = Add-InfoRow -Y 99  -Label "Channel:"
$valSource  = Add-InfoRow -Y 127 -Label "Source:"
$valKey     = Add-InfoRow -Y 155 -Label "Product Key:"
$valKey.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)

$txtNewKey = New-Object System.Windows.Forms.TextBox
$txtNewKey.Location = New-Object System.Drawing.Point(20, 265)
$txtNewKey.Size = New-Object System.Drawing.Size(310, 26)
$txtNewKey.BackColor = $bgPanel
$txtNewKey.ForeColor = $fgMuted
$txtNewKey.Font = New-Object System.Drawing.Font("Consolas", 10)
$txtNewKey.Text = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
$txtNewKey.Add_GotFocus({
    if ($this.Text -eq "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX") {
        $this.Text = ""
        $this.ForeColor = $fgLight
    }
})
$form.Controls.Add($txtNewKey)

$btnAction = New-Object System.Windows.Forms.Button
$btnAction.Location = New-Object System.Drawing.Point(340, 263)
$btnAction.Size = New-Object System.Drawing.Size(145, 28)
$btnAction.FlatStyle = "Flat"
$btnAction.FlatAppearance.BorderSize = 0
$btnAction.ForeColor = $fgLight
$btnAction.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnAction)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy Key"
$btnCopy.Location = New-Object System.Drawing.Point(20, 315)
$btnCopy.Size = New-Object System.Drawing.Size(145, 32)
$btnCopy.BackColor = $bgPanel
$btnCopy.FlatStyle = "Flat"
$form.Controls.Add($btnCopy)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export CSV"
$btnExport.Location = New-Object System.Drawing.Point(180, 315)
$btnExport.Size = New-Object System.Drawing.Size(145, 32)
$btnExport.BackColor = $bgPanel
$btnExport.FlatStyle = "Flat"
$form.Controls.Add($btnExport)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(340, 315)
$btnRefresh.Size = New-Object System.Drawing.Size(145, 32)
$btnRefresh.BackColor = $bgPanel
$btnRefresh.FlatStyle = "Flat"
$form.Controls.Add($btnRefresh)

$script:currentData = $null

function Update-UI {
    $script:currentData = Get-LicenseDetails
    $d = $script:currentData

    $valHost.Text    = $d.ComputerName
    $valEdition.Text = $d.Edition
    $valChannel.Text = $d.Channel
    $valSource.Text  = $d.KeySource
    $valKey.Text     = $d.FullKey

    if ($d.IsActivated) {
        $valStatus.Text = "$($d.StatusText) ($($d.DaysLeft))"
        $valStatus.ForeColor = [System.Drawing.Color]::LightGreen
        $btnAction.Text = "Deactivate"
        $btnAction.BackColor = $danger
        $txtNewKey.Enabled = $false
    } else {
        $valStatus.Text = $d.StatusText
        $valStatus.ForeColor = [System.Drawing.Color]::Salmon
        $btnAction.Text = "Activate"
        $btnAction.BackColor = $success
        $txtNewKey.Enabled = $true
    }

    $btnCopy.Enabled = $d.HasRawKey
}

$btnCopy.Add_Click({
    if ($script:currentData.HasRawKey) {
        [System.Windows.Forms.Clipboard]::SetText($script:currentData.FullKey)
        [System.Windows.Forms.MessageBox]::Show("Copied.", "Clipboard", "OK", "Information") | Out-Null
    }
})

$btnExport.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "CSV Files (*.csv)|*.csv"
    $sfd.FileName = "$($env:COMPUTERNAME)_LicenseAudit.csv"
    if ($sfd.ShowDialog() -eq "OK") {
        $script:currentData | Select-Object ComputerName, Edition, StatusText, Channel, KeySource, FullKey |
            Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
        [System.Windows.Forms.MessageBox]::Show("Saved to $($sfd.FileName)", "Export", "OK", "Information") | Out-Null
    }
})

$btnRefresh.Add_Click({ Update-UI })

$btnAction.Add_Click({
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Run as Administrator to change activation.", "Admin Required", "OK", "Warning") | Out-Null
        return
    }

    $slmgr = "$env:SystemRoot\System32\slmgr.vbs"

    if ($script:currentData.IsActivated) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Uninstall current product key and deactivate Windows?",
            "Deactivate",
            "YesNo",
            "Warning"
        )
        if ($confirm -eq "Yes") {
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /upk" -Wait -WindowStyle Hidden
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /cpky" -Wait -WindowStyle Hidden
            Update-UI
        }
    } else {
        $inputKey = $txtNewKey.Text.Trim()
        if ($inputKey -notmatch '^[A-Za-z0-9]{5}-[A-Za-z0-9]{5}-[A-Za-z0-9]{5}-[A-Za-z0-9]{5}-[A-Za-z0-9]{5}$') {
            [System.Windows.Forms.MessageBox]::Show("Invalid key format.", "Error", "OK", "Error") | Out-Null
            return
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Install key $inputKey and activate?",
            "Activate",
            "YesNo",
            "Question"
        )
        if ($confirm -eq "Yes") {
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /ipk $inputKey" -Wait -WindowStyle Hidden
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /ato" -Wait -WindowStyle Hidden
            Update-UI
        }
    }
})

Update-UI
[void]$form.ShowDialog()
