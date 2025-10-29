Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# JSON storage path
$jsonPath = Join-Path $env:TEMP 'launcher.json'
$iconSize = 64
$global:entries = New-Object System.Collections.ArrayList

# ====== SAVE FUNCTION ======
function Save-Entries {
    @($global:entries) | ConvertTo-Json -Compress | Set-Content -Path $jsonPath
}

# ====== ADD ICON FUNCTION ======
function Add-LauncherIcon($path) {
    if ([string]::IsNullOrWhiteSpace($path) -or $global:entries -contains $path) { return }

    # Panel container for icon and label
    $panelItem = New-Object System.Windows.Forms.Panel
    $panelItem.Width = $iconSize + 20
    $panelItem.Height = $iconSize + 30
    $panelItem.Tag = $path

    # PictureBox for icon
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size($iconSize,$iconSize)
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
    if ($label.Text.Length -gt 12) { $label.Text = $label.Text.Substring(0,12) + "..." }
    $label.Location = New-Object System.Drawing.Point(0, $iconSize)
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
                $panel.Controls.Remove($sender.Parent) # remove panel container
                $global:entries = $global:entries | Where-Object { $_ -ne $sender.Tag }
                Save-Entries
                $panel.PerformLayout()  # refresh layout
            }
        }
    })

    # Add to panel and global entries
    $panel.Controls.Add($panelItem)
    [void]$global:entries.Add($path)
    Save-Entries
}

# ====== FORM SETUP ======
$form = New-Object System.Windows.Forms.Form
$form.Text = "Quick Launcher - by drox-Ph-Ceb"
$form.Size = New-Object System.Drawing.Size(700, 450)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(230,240,250)

# Scrollable panel
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Location = New-Object System.Drawing.Point(20,60)
$panel.Size = New-Object System.Drawing.Size(640,360)
$panel.WrapContents = $true
$panel.AutoScroll = $true
$panel.FlowDirection = 'LeftToRight'
$panel.BorderStyle = 'FixedSingle'
$form.Controls.Add($panel)

# ====== LOAD EXISTING ENTRIES ======
if (Test-Path $jsonPath) {
    $loaded = Get-Content $jsonPath -Raw | ConvertFrom-Json
    foreach ($entry in @($loaded)) { if (-not [string]::IsNullOrWhiteSpace($entry)) { Add-LauncherIcon $entry } }
}

# URL input
$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location = New-Object System.Drawing.Point(20, 20)
$urlBox.Width = 400
$urlBox.Font = 'Segoe UI,10'
$urlBox.ForeColor = 'Gray'
$urlBox.Text = "Enter URL here..."
$form.Controls.Add($urlBox)
$urlBox.Add_GotFocus({ if ($urlBox.ForeColor -eq 'Gray') { $urlBox.Text = ""; $urlBox.ForeColor = 'Black' } })
$urlBox.Add_LostFocus({ if ([string]::IsNullOrWhiteSpace($urlBox.Text)) { $urlBox.Text = "Enter URL here..."; $urlBox.ForeColor = 'Gray' } })

# Add File button
$addFileBtn = New-Object System.Windows.Forms.Button
$addFileBtn.Text = "Add File"
$addFileBtn.Location = New-Object System.Drawing.Point(550,18) 
$addFileBtn.Width = 100
$addFileBtn.Height = 30
$addFileBtn.BackColor = [System.Drawing.Color]::FromArgb(255,200,140)
$addFileBtn.FlatStyle = 'Flat'
$form.Controls.Add($addFileBtn)

# Add URL button
$addUrlBtn = New-Object System.Windows.Forms.Button
$addUrlBtn.Text = "Add URL"
$addUrlBtn.Location = New-Object System.Drawing.Point(440,18)
$addUrlBtn.Width = 100
$addUrlBtn.Height = 30
$addUrlBtn.BackColor = [System.Drawing.Color]::FromArgb(200,220,255)
$addUrlBtn.FlatStyle = 'Flat'
$form.Controls.Add($addUrlBtn)

# Button clicks
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
[void]$form.ShowDialog()
