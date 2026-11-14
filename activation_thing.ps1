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

function Get-SystemAndLicenseDetails {
    $winAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    $foundKey = $null
    $keySource = 'None'

    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $os   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            $cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            $cpu  = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
            $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
            $sls  = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction SilentlyContinue
            $slp  = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='$winAppId' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue
        } else {
            $os   = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue
            $cs   = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
            $cpu  = Get-WmiObject -Class Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            $bios = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
            $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
            $sls  = Get-WmiObject -Class SoftwareLicensingService -ErrorAction SilentlyContinue
            $slp  = Get-WmiObject -Class SoftwareLicensingProduct -Filter "ApplicationID='$winAppId' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue
        }
    } catch {}

    if ($sls -and -not [string]::IsNullOrWhiteSpace($sls.OA3xOriginalProductKey)) {
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
            if ($digitalId) {
                $decoded = Decode-DigitalProductId -DigitalId $digitalId
                if ($decoded) {
                    $foundKey = $decoded
                    $keySource = 'Registry (DigitalProductId)'
                }
            }
        } catch {}
    }

    $activeProduct = $slp | Where-Object { $_.LicenseStatus -eq 1 } | Select-Object -First 1
    if (-not $activeProduct -and $slp) { $activeProduct = $slp | Select-Object -First 1 }

    $isActivated = ($activeProduct.LicenseStatus -eq 1)
    $gracePeriod = $activeProduct.GracePeriodRemaining
    $daysLeft = if ($gracePeriod -gt 0) { "$([math]::Round($gracePeriod / 1440, 1)) days" } else { 'Permanent / Digital' }

    $systemModel = if ($cs.Model) { "$($cs.Manufacturer) $($cs.Model)".Trim() } else { 'Unknown' }
    $processor   = if ($cpu.Name) { $cpu.Name.Trim() } else { 'Unknown' }

    # Dynamically round memory to the nearest whole integer gigabyte
    $totalRam = if ($cs.TotalPhysicalMemory) { "$([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB" } else { 'Unknown' }

    $diskInfo    = if ($disk) {
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $totalGB = [math]::Round($disk.Size / 1GB, 1)
        "$freeGB GB free of $totalGB GB"
    } else { 'Unknown' }
    $biosVersion = if ($bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion } else { 'Unknown' }

    return [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        SystemModel  = $systemModel
        Processor    = $processor
        MemoryRAM    = $totalRam
        OSDrive      = $diskInfo
        BIOSVersion  = $biosVersion
        Edition      = if ($os.Caption) { $os.Caption } else { 'Windows' }
        Build        = if ($os.Version) { "$($os.Version) (Build $($os.BuildNumber))" } else { 'Unknown' }
        Architecture = if ($os.OSArchitecture) { $os.OSArchitecture } else { 'Unknown' }
        IsActivated  = $isActivated
        StatusText   = if ($isActivated) { 'Activated' } else { 'Not Activated' }
        Channel      = if ($activeProduct.ProductKeyChannel) { $activeProduct.ProductKeyChannel } else { 'Retail / OEM' }
        FullKey      = if ($foundKey) { $foundKey } else { 'None (Digital License)' }
        HasRawKey    = [bool]$foundKey
        KeySource    = $keySource
        DaysLeft     = $daysLeft
    }
}

# Modern UI Colors (Fluent Dark Theme)
$bgDark   = [System.Drawing.Color]::FromArgb(32, 32, 32)
$bgPanel  = [System.Drawing.Color]::FromArgb(45, 45, 45)
$fgLight  = [System.Drawing.Color]::FromArgb(245, 245, 245)
$fgMuted  = [System.Drawing.Color]::FromArgb(160, 160, 160)
$danger   = [System.Drawing.Color]::FromArgb(209, 52, 56)
$success  = [System.Drawing.Color]::FromArgb(16, 124, 65)

$form = New-Object System.Windows.Forms.Form
$form.Text = "System & License Dashboard"
$form.Size = New-Object System.Drawing.Size(530, 615)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $bgDark
$form.ForeColor = $fgLight
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "System & License Audit"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(20, 50)
$panel.Size = New-Object System.Drawing.Size(475, 355)
$panel.BackColor = $bgPanel
$form.Controls.Add($panel)

function Add-InfoRow {
    param([int]$Y, [string]$Label)
    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = $Label
    $l1.ForeColor = $fgMuted
    $l1.Location = New-Object System.Drawing.Point(12, $Y)
    $l1.Size = New-Object System.Drawing.Size(110, 22)
    $panel.Controls.Add($l1)

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = "Loading..."
    $l2.ForeColor = $fgLight
    $l2.Location = New-Object System.Drawing.Point(125, $Y)
    $l2.Size = New-Object System.Drawing.Size(335, 22)
    $panel.Controls.Add($l2)
    return $l2
}

$valHost     = Add-InfoRow -Y 10  -Label "Computer:"
$valModel    = Add-InfoRow -Y 36  -Label "Model:"
$valCPU      = Add-InfoRow -Y 62  -Label "Processor:"
$valRAM      = Add-InfoRow -Y 88  -Label "Memory (RAM):"
$valDisk     = Add-InfoRow -Y 114 -Label "OS Drive (C:):"
$valBIOS     = Add-InfoRow -Y 140 -Label "BIOS Version:"
$valEdition  = Add-InfoRow -Y 166 -Label "Edition:"
$valBuild    = Add-InfoRow -Y 192 -Label "Version:"
$valArch     = Add-InfoRow -Y 218 -Label "Architecture:"
$valStatus   = Add-InfoRow -Y 244 -Label "Status:"
$valChannel  = Add-InfoRow -Y 270 -Label "Channel:"
$valSource   = Add-InfoRow -Y 296 -Label "Key Source:"
$valKey      = Add-InfoRow -Y 322 -Label "Product Key:"
$valKey.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)

$txtNewKey = New-Object System.Windows.Forms.TextBox
$txtNewKey.Location = New-Object System.Drawing.Point(20, 422)
$txtNewKey.Size = New-Object System.Drawing.Size(315, 28)
$txtNewKey.BackColor = $bgPanel
$txtNewKey.ForeColor = $fgMuted
$txtNewKey.Font = New-Object System.Drawing.Font("Consolas", 10)
$txtNewKey.Text = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
$txtNewKey.CharacterCasing = [System.Windows.Forms.CharacterCasing]::Upper

$txtNewKey.Add_GotFocus({
    if ($this.Text -eq "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX") {
        $this.Text = ""
        $this.ForeColor = $fgLight
    }
})
$txtNewKey.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($this.Text)) {
        $this.Text = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
        $this.ForeColor = $fgMuted
    }
})
$form.Controls.Add($txtNewKey)

$btnAction = New-Object System.Windows.Forms.Button
$btnAction.Location = New-Object System.Drawing.Point(345, 421)
$btnAction.Size = New-Object System.Drawing.Size(150, 30)
$btnAction.FlatStyle = "Flat"
$btnAction.FlatAppearance.BorderSize = 0
$btnAction.ForeColor = $fgLight
$btnAction.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnAction)

$ButtonStyle = {
    param($btn)
    $btn.FlatStyle = "Flat"
    $btn.BackColor = $bgPanel
    $btn.ForeColor = $fgLight
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
}

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy Key"
$btnCopy.Location = New-Object System.Drawing.Point(20, 485)
$btnCopy.Size = New-Object System.Drawing.Size(150, 34)
&$ButtonStyle $btnCopy
$form.Controls.Add($btnCopy)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export CSV"
$btnExport.Location = New-Object System.Drawing.Point(180, 485)
$btnExport.Size = New-Object System.Drawing.Size(150, 34)
&$ButtonStyle $btnExport
$form.Controls.Add($btnExport)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(345, 485)
$btnRefresh.Size = New-Object System.Drawing.Size(150, 34)
&$ButtonStyle $btnRefresh
$form.Controls.Add($btnRefresh)

$script:currentData = $null

function Update-UI {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    
    $script:currentData = Get-SystemAndLicenseDetails
    $d = $script:currentData

    $valHost.Text    = $d.ComputerName
    $valModel.Text   = $d.SystemModel
    $valCPU.Text     = $d.Processor
    $valRAM.Text     = $d.MemoryRAM
    $valDisk.Text    = $d.OSDrive
    $valBIOS.Text    = $d.BIOSVersion
    $valEdition.Text = $d.Edition
    $valBuild.Text   = $d.Build
    $valArch.Text    = $d.Architecture
    $valChannel.Text = $d.Channel
    $valSource.Text  = $d.KeySource
    $valKey.Text     = $d.FullKey

    if ($d.IsActivated) {
        $valStatus.Text = "$($d.StatusText) ($($d.DaysLeft))"
        $valStatus.ForeColor = [System.Drawing.Color]::FromArgb(57, 197, 107)
        $btnAction.Text = "Deactivate"
        $btnAction.BackColor = $danger
        
        # Hide the input box and stretch the Deactivate button across the full width
        $txtNewKey.Visible = $false
        $btnAction.Location = New-Object System.Drawing.Point(20, 421)
        $btnAction.Size = New-Object System.Drawing.Size(475, 34)
    } else {
        $valStatus.Text = $d.StatusText
        $valStatus.ForeColor = [System.Drawing.Color]::FromArgb(249, 105, 108)
        $btnAction.Text = "Activate"
        $btnAction.BackColor = $success
        
        # Show input box and position the Activate button normally
        $txtNewKey.Visible = $true
        $txtNewKey.Location = New-Object System.Drawing.Point(20, 422)
        $txtNewKey.Size = New-Object System.Drawing.Size(315, 28)
        $btnAction.Location = New-Object System.Drawing.Point(345, 421)
        $btnAction.Size = New-Object System.Drawing.Size(150, 30)
    }

    $btnCopy.Enabled = $d.HasRawKey
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
}

$btnCopy.Add_Click({
    if ($script:currentData.HasRawKey) {
        [System.Windows.Forms.Clipboard]::SetText($script:currentData.FullKey)
        [System.Windows.Forms.MessageBox]::Show("Product key copied to clipboard.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})

$btnExport.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "CSV Files (*.csv)|*.csv"
    $sfd.FileName = "$($env:COMPUTERNAME)_SystemLicenseAudit.csv"
    if ($sfd.ShowDialog() -eq "OK") {
        $script:currentData | Select-Object ComputerName, SystemModel, Processor, MemoryRAM, OSDrive, BIOSVersion, Edition, Build, Architecture, StatusText, Channel, KeySource, FullKey |
            Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
        [System.Windows.Forms.MessageBox]::Show("Report successfully saved to $($sfd.FileName)", "Export Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})

$btnRefresh.Add_Click({ Update-UI })

$btnAction.Add_Click({
    if (-not (Test-Admin)) {
        [System.Windows.Forms.MessageBox]::Show("Administrative privileges are required to modify activation state.", "Admin Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $slmgr = "$env:SystemRoot\System32\slmgr.vbs"

    if ($script:currentData.IsActivated) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Are you sure you want to uninstall the current product key and deactivate Windows?",
            "Confirm Deactivation",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -eq "Yes") {
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /upk" -Wait -WindowStyle Hidden
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /cpky" -Wait -WindowStyle Hidden
            Update-UI
        }
    } else {
        $inputKey = $txtNewKey.Text.Trim()
        if ($inputKey -notmatch '^[A-Za-z0-9]{5}-[A-Za-z0-9]{5}-[A-Za-z0-9]{5}-[A-Za-z0-9]{5}-[A-Za-z0-9]{5}$') {
            [System.Windows.Forms.MessageBox]::Show("Please enter a valid 25-character product key format.", "Invalid Format", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Install key $inputKey and attempt online activation?",
            "Confirm Activation",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -eq "Yes") {
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /ipk $inputKey" -Wait -WindowStyle Hidden
            Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /ato" -Wait -WindowStyle Hidden
            Update-UI
        }
    }
})

$form.Add_Shown({ Update-UI })
[void]$form.ShowDialog()
