Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# JSON storage path
$jsonPath = Join-Path $env:TEMP 'launcher.json'
$global:iconSize = 40
$global:entries = New-Object System.Collections.ArrayList

# ====== SAVE FUNCTION ======
function Save-Entries {
    $data = [PSCustomObject]@{
        IconSize = $global:iconSize
        Entries  = @($global:entries)
    }
    $data | ConvertTo-Json -Compress | Set-Content -Path $jsonPath
}

# ====== REFRESH ICON SIZES ======
function Refresh-IconSizes {
    foreach ($ctrl in $panel.Controls) {
        if ($ctrl -is [System.Windows.Forms.Panel]) {
            $path = $ctrl.Tag
            if (-not $path) { continue }

            $ctrl.Width = $global:iconSize + 20
            $ctrl.Height = $global:iconSize + 35

            $pic = $ctrl.Controls | Where-Object { $_ -is [System.Windows.Forms.PictureBox] }
            $label = $ctrl.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }

            if ($pic) {
                $pic.Size = New-Object System.Drawing.Size($global:iconSize, $global:iconSize)
            }
            if ($label) {
                $label.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(6, [Math]::Round($global:iconSize / 6)), [System.Drawing.FontStyle]::Regular)
                $label.Location = New-Object System.Drawing.Point(0, $global:iconSize)
                $label.Width = $ctrl.Width
            }
        }
    }
    $panel.PerformLayout()
}

# ====== ADD ICON FUNCTION ======
function Add-LauncherIcon($path) {
    if ([string]::IsNullOrWhiteSpace($path) -or $global:entries -contains $path) { return }

    # Panel container for icon and label
    $panelItem = New-Object System.Windows.Forms.Panel
    $panelItem.Width = $global:iconSize + 20
    $panelItem.Height = $global:iconSize + 35
    $panelItem.Tag = $path

    # PictureBox for icon
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size($global:iconSize,$global:iconSize)
    $pic.SizeMode = 'StretchImage'
    $pic.Image = if ($path -match '^https?://') {
        [System.Drawing.SystemIcons]::Information.ToBitmap()
    } elseif (Test-Path $path) {
        try { [System.Drawing.Icon]::ExtractAssociatedIcon($path).ToBitmap() }
        catch { [System.Drawing.SystemIcons]::Application.ToBitmap() }
    } else { [System.Drawing.SystemIcons]::Application.ToBitmap() }
    $pic.Location = New-Object System.Drawing.Point(0,0)
    $pic.Tag = $path
    $panelItem.Controls.Add($pic)

    # Label under icon
    $label = New-Object System.Windows.Forms.Label
    $label.Text = if ($path -match '^https?://') { $path } else { Split-Path $path -Leaf }
    if ($label.Text.Length -gt 12) { $label.Text = $label.Text.Substring(0,9) + "..." }
    $label.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(6, [Math]::Round($global:iconSize / 6)), [System.Drawing.FontStyle]::Regular)
    $label.Location = New-Object System.Drawing.Point(0, $global:iconSize)
    $label.Width = $panelItem.Width
    $label.TextAlign = 'MiddleCenter'
    $panelItem.Controls.Add($label)

    # ====== LEFT CLICK: Launch ======
    $pic.Add_MouseClick({
        param($sender,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $launchPath = $sender.Tag
            if ([string]::IsNullOrWhiteSpace($launchPath)) { return }
            if ($launchPath -match '^https?://') { Start-Process $launchPath }
            elseif (Test-Path $launchPath) { Start-Process $launchPath }
        }
    })

    # ====== RIGHT CLICK: Confirm Remove ======
    $pic.Add_MouseUp({
        param($sender,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            $displayName = if ($sender.Tag -match '^https?://') { $sender.Tag } else { Split-Path $sender.Tag -Leaf }
            if ($displayName.Length -gt 12) { $displayName = $displayName.Substring(0,12) + "..." }

            $confirm = [System.Windows.Forms.MessageBox]::Show(
                "Do you want to remove '$displayName'?",
                "Confirm Delete",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                $panel.Controls.Remove($sender.Parent)
                $global:entries = $global:entries | Where-Object { $_ -ne $sender.Tag }
                Save-Entries
                $panel.PerformLayout()
            }
        }
    })

    $panel.Controls.Add($panelItem)
    [void]$global:entries.Add($path)
    Save-Entries
}

# ====== FORM SETUP ======
$form = New-Object System.Windows.Forms.Form
$form.Text = "Quick Launcher - by drox-Ph-Ceb    Gcash no. 0945-1035-299"
$form.Size = New-Object System.Drawing.Size(720, 500)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(230,240,250)

# Scrollable panel
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Location = New-Object System.Drawing.Point(20,80)
$panel.Size = New-Object System.Drawing.Size(660,370)
$panel.WrapContents = $true
$panel.AutoScroll = $true
$panel.FlowDirection = 'LeftToRight'
$panel.BorderStyle = 'FixedSingle'
$form.Controls.Add($panel)

# ====== URL input ======
$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location = New-Object System.Drawing.Point(20, 20)
$urlBox.Width = 320
$urlBox.Font = 'Segoe UI,10'
$urlBox.ForeColor = 'Gray'
$urlBox.Text = "Enter URL here..."
$form.Controls.Add($urlBox)
$urlBox.Add_GotFocus({ if ($urlBox.ForeColor -eq 'Gray') { $urlBox.Text = ""; $urlBox.ForeColor = 'Black' } })
$urlBox.Add_LostFocus({ if ([string]::IsNullOrWhiteSpace($urlBox.Text)) { $urlBox.Text = "Enter URL here..."; $urlBox.ForeColor = 'Gray' } })

# ====== Buttons ======
$addUrlBtn = New-Object System.Windows.Forms.Button
$addUrlBtn.Text = "Add URL"
$addUrlBtn.Location = New-Object System.Drawing.Point(350,18)
$addUrlBtn.Size = New-Object System.Drawing.Size(90,30)
$addUrlBtn.BackColor = [System.Drawing.Color]::FromArgb(200,220,255)
$addUrlBtn.FlatStyle = 'Flat'
$form.Controls.Add($addUrlBtn)

$addFileBtn = New-Object System.Windows.Forms.Button
$addFileBtn.Text = "Add File"
$addFileBtn.Location = New-Object System.Drawing.Point(450,18)
$addFileBtn.Size = New-Object System.Drawing.Size(90,30)
$addFileBtn.BackColor = [System.Drawing.Color]::FromArgb(255,200,140)
$addFileBtn.FlatStyle = 'Flat'
$form.Controls.Add($addFileBtn)

# ====== ICON SIZE SLIDER ======
$sizeLabel = New-Object System.Windows.Forms.Label
$sizeLabel.Text = "Icon Size:"
$sizeLabel.Location = New-Object System.Drawing.Point(550, 22)
$form.Controls.Add($sizeLabel)

$sizeSlider = New-Object System.Windows.Forms.TrackBar
$sizeSlider.Location = New-Object System.Drawing.Point(610, 15)
$sizeSlider.Width = 80
$sizeSlider.Minimum = 32
$sizeSlider.Maximum = 96
$sizeSlider.Value = $global:iconSize
$sizeSlider.TickFrequency = 8
$form.Controls.Add($sizeSlider)

# ====== LOAD EXISTING ENTRIES ======
if (Test-Path $jsonPath) {
    $loaded = Get-Content $jsonPath -Raw | ConvertFrom-Json

    if ($loaded.PSObject.Properties.Name -contains 'IconSize') {
        $global:iconSize = [int]$loaded.IconSize
        foreach ($entry in @($loaded.Entries)) {
            if (-not [string]::IsNullOrWhiteSpace($entry)) { Add-LauncherIcon $entry }
        }
    }
    else {
        foreach ($entry in @($loaded)) {
            if (-not [string]::IsNullOrWhiteSpace($entry)) { Add-LauncherIcon $entry }
        }
    }

    $sizeSlider.Value = $global:iconSize
    Refresh-IconSizes
}

# ====== SLIDER CHANGE ======
$sizeSlider.Add_ValueChanged({
    $global:iconSize = $sizeSlider.Value
    Refresh-IconSizes
    Save-Entries
})

# ====== BUTTON CLICKS ======
$addFileBtn.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Select a file"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Add-LauncherIcon $ofd.FileName }
})

$addUrlBtn.Add_Click({
    $url = $urlBox.Text.Trim()
    if ($url -match '^https?://') {
        Add-LauncherIcon $url
        $urlBox.Text = "Enter URL here..."
        $urlBox.ForeColor = 'Gray'
    }
})

# Press Enter in URL box
$urlBox.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $addUrlBtn.PerformClick() } })

# ====== SHOW FORM ======
try {
    [void]$form.ShowDialog()
} catch {
    [System.Windows.Forms.MessageBox]::Show("Unexpected GUI error: $_","Error","OK","Error")
}
