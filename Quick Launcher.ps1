Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ====== PATH & GLOBAL VARS ======
$jsonPath = Join-Path $env:TEMP 'launcher.json'
$global:iconSize = 40
$global:entries = New-Object System.Collections.ArrayList
$global:isLoading = $false

# ====== SAVE FUNCTION ======
function Save-Entries {
    try {
        $data = [PSCustomObject]@{
            IconSize = $global:iconSize
            Entries  = @($global:entries)
        }
        $data | ConvertTo-Json -Compress | Set-Content -Path $jsonPath -ErrorAction SilentlyContinue
    } catch {}
}

# ====== REFRESH ICON SIZES ======
function Refresh-IconSizes {
    foreach ($ctrl in $panel.Controls) {
        if ($ctrl -is [System.Windows.Forms.Panel]) {
            $ctrl.Width = $global:iconSize + 20
            $ctrl.Height = $global:iconSize + 35

            $pic = $ctrl.Controls | Where-Object { $_ -is [System.Windows.Forms.PictureBox] }
            $label = $ctrl.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }

            if ($pic) { $pic.Size = New-Object System.Drawing.Size($global:iconSize, $global:iconSize) }
            if ($label) {
                $label.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(6, [Math]::Round($global:iconSize / 6)))
                $label.Location = New-Object System.Drawing.Point(0, $global:iconSize)
                $label.Width = $ctrl.Width
            }
        }
    }
    $panel.PerformLayout()
}

function Add-LauncherIcon($path, $customName = $null) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }

    # Prevent duplicates (only when not loading)
    if (-not $global:isLoading) {
        if ($global:entries | Where-Object { $_.Path -eq $path }) {
            [System.Windows.Forms.MessageBox]::Show("This entry already exists.","Duplicate","OK","Information")
            return
        }
    }

    # Ask for custom name if not provided
    if (-not $customName) {
        $defaultName = if ($path -match '^https?://') { $path } else { [System.IO.Path]::GetFileNameWithoutExtension($path) }
        $customName = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a custom name:","Custom Name",$defaultName)
        if (-not $customName) { return }
    }

    $displayName = [System.IO.Path]::GetFileNameWithoutExtension($customName)
    $entry = [PSCustomObject]@{ Path = $path; Name = $displayName }

    # Panel item
    $panelItem = New-Object System.Windows.Forms.Panel
    $panelItem.Width = $global:iconSize + 20
    $panelItem.Height = $global:iconSize + 35
    $panelItem.Tag = $path

    # Icon
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size($global:iconSize, $global:iconSize)
    $pic.SizeMode = 'StretchImage'
    $pic.Image = if ($path -match '^https?://') {
        [System.Drawing.SystemIcons]::Information.ToBitmap()
    } elseif (Test-Path $path) {
        try { [System.Drawing.Icon]::ExtractAssociatedIcon($path).ToBitmap() }
        catch { [System.Drawing.SystemIcons]::Application.ToBitmap() }
    } else {
        [System.Drawing.SystemIcons]::Application.ToBitmap()
    }
    $pic.Location = New-Object System.Drawing.Point(0, 0)
    $pic.Tag = $path
    $panelItem.Controls.Add($pic)

    # Label
    $label = New-Object System.Windows.Forms.Label
    $label.Text = if ($displayName.Length -gt 10) { $displayName.Substring(0, 9) + "..." } else { $displayName }
    $label.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(6, [Math]::Round($global:iconSize / 6)))
    $label.Location = New-Object System.Drawing.Point(0, $global:iconSize)
    $label.Width = $panelItem.Width
    $label.TextAlign = 'MiddleCenter'
    $panelItem.Controls.Add($label)

    # ====== PANEL + ICON HOVER EFFECT ======
    $pic.Add_MouseEnter({
        param($sender, $e)
        $panel = $sender.Parent
        $newSize = $global:iconSize + 15

        # Resize panel
        $panel.Width = $newSize + 20
        $panel.Height = $newSize + 35

        # Resize icon
        $sender.Size = New-Object System.Drawing.Size($newSize, $newSize)

        # Center icon
        $sender.Location = New-Object System.Drawing.Point(
            [math]::Floor(($panel.Width - $newSize)/2),
            0
        )

        # Adjust label
        $label = $panel.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }
        if ($label) {
            $label.Location = New-Object System.Drawing.Point(0, $newSize)
            $label.Width = $panel.Width
        }
    })

    $pic.Add_MouseLeave({
        param($sender, $e)
        $panel = $sender.Parent

        # Reset panel
        $panel.Width = $global:iconSize + 20
        $panel.Height = $global:iconSize + 35

        # Reset icon
        $sender.Size = New-Object System.Drawing.Size($global:iconSize, $global:iconSize)
        $sender.Location = New-Object System.Drawing.Point(0,0)

        # Reset label
        $label = $panel.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }
        if ($label) {
            $label.Location = New-Object System.Drawing.Point(0, $global:iconSize)
            $label.Width = $panel.Width
        }
    })

    # ====== LEFT CLICK = Launch ======
    $pic.Add_MouseClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            try {
                if ($sender.Tag -match '^https?://') { Start-Process $sender.Tag }
                elseif (Test-Path $sender.Tag) { Start-Process $sender.Tag }
            } catch {}
        }
    })

    # ====== RIGHT CLICK = Remove ======
    $pic.Add_MouseUp({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            try {
                $displayName = ($global:entries | Where-Object { $_.Path -eq $sender.Tag }).Name
                $confirm = [System.Windows.Forms.MessageBox]::Show("Remove '$displayName'?", "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo)
                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $panel.Controls.Remove($sender.Parent)
                    $remaining = @($global:entries | Where-Object { $_.Path -ne $sender.Tag })
                    $global:entries = New-Object System.Collections.ArrayList
                    foreach ($r in $remaining) { [void]$global:entries.Add($r) }
                    Save-Entries
                    $panel.PerformLayout()
                }
            } catch {}
        }
    })

    # ====== Add to panel & save ======
    try {
        $panel.Controls.Add($panelItem)
        [void]$global:entries.Add($entry)
        if (-not $global:isLoading) { Save-Entries }
    } catch {}
}

# ====== FORM ======
$form = New-Object System.Windows.Forms.Form
$form.Text = "Quick Launcher - by drox-Ph-Ceb    Gcash no. 0945-1035-299"
$form.Size = New-Object System.Drawing.Size(720, 500)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 250)
$form.Add_FormClosed({ $form.Dispose() })

# ====== PANEL ======
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Location = New-Object System.Drawing.Point(20, 80)
$panel.Size = New-Object System.Drawing.Size(660, 370)
$panel.WrapContents = $true
$panel.AutoScroll = $true
$panel.FlowDirection = 'LeftToRight'
$panel.BorderStyle = 'FixedSingle'
$form.Controls.Add($panel)

# ====== URL BOX ======
$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location = New-Object System.Drawing.Point(20, 20)
$urlBox.Width = 320
$urlBox.Font = 'Segoe UI,10'
$urlBox.ForeColor = 'Gray'
$urlBox.Text = "Enter URL here..."
$form.Controls.Add($urlBox)

$urlBox.Add_GotFocus({ if ($urlBox.ForeColor -eq 'Gray') { $urlBox.Text = ""; $urlBox.ForeColor = 'Black' } })
$urlBox.Add_LostFocus({ if ([string]::IsNullOrWhiteSpace($urlBox.Text)) { $urlBox.Text = "Enter URL here..."; $urlBox.ForeColor = 'Gray' } })

# ====== BUTTONS ======
$addUrlBtn = New-Object System.Windows.Forms.Button
$addUrlBtn.Text = "Add URL"
$addUrlBtn.Location = New-Object System.Drawing.Point(350, 18)
$addUrlBtn.Size = New-Object System.Drawing.Size(90, 30)
$addUrlBtn.BackColor = [System.Drawing.Color]::FromArgb(200, 220, 255)
$form.Controls.Add($addUrlBtn)

$addFileBtn = New-Object System.Windows.Forms.Button
$addFileBtn.Text = "Add File"
$addFileBtn.Location = New-Object System.Drawing.Point(450, 18)
$addFileBtn.Size = New-Object System.Drawing.Size(90, 30)
$addFileBtn.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 140)
$form.Controls.Add($addFileBtn)

# ====== ICON SIZE SLIDER ======
$sizeLabel = New-Object System.Windows.Forms.Label
$sizeLabel.Text = "Icon Size:"
$sizeLabel.AutoSize = $true
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

# ====== LOAD JSON ======
if (Test-Path $jsonPath) {
    try {
        $panel.Controls.Clear()  # Clear existing icons
        $global:entries.Clear()  # Clear current list

        $data = Get-Content $jsonPath -Raw | ConvertFrom-Json
        if ($data.IconSize) { $global:iconSize = [int]$data.IconSize }

        $global:isLoading = $true
        foreach ($entry in $data.Entries) {
            Add-LauncherIcon $entry.Path $entry.Name  # Add only through function
        }
        $global:isLoading = $false
        Refresh-IconSizes
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Launcher data corrupted. Resetting.","Error","OK","Error")
        $panel.Controls.Clear()
        $global:entries = New-Object System.Collections.ArrayList
    }
}

# ====== ICON SIZE SLIDER & LABEL ======
$sizeLabel.Text = "Icon Size: $($global:iconSize)"
$sizeSlider.Value = $global:iconSize
$sizeSlider.Add_ValueChanged({
    $global:iconSize = $sizeSlider.Value
    $sizeLabel.Text = "Icon Size: $($global:iconSize)"
    Refresh-IconSizes
    Save-Entries
})

# ====== BUTTON ACTIONS ======
$addFileBtn.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Select a file"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Add-LauncherIcon $ofd.FileName
    }
})

$addUrlBtn.Add_Click({
    $url = $urlBox.Text.Trim()
    if ($url -match '^https?://') {
        Add-LauncherIcon $url
        $urlBox.Text = "Enter URL here..."
        $urlBox.ForeColor = 'Gray'
    }
})

$urlBox.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $addUrlBtn.PerformClick() } })

# ====== SHOW FORM ======
try { [void]$form.ShowDialog() } catch {}
