Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# Import ExtractIconEx from shell32.dll (for real yellow folder icon)
Add-Type -Namespace Win32 -Name IconExtractor -MemberDefinition @"
    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
    public static extern int ExtractIconEx(string lpszFile, int nIconIndex, out System.IntPtr phiconLarge, out System.IntPtr phiconSmall, int nIcons);
"@

function Get-FolderIcon {
    $largePtr = [IntPtr]::Zero
    $smallPtr = [IntPtr]::Zero
    [void][Win32.IconExtractor]::ExtractIconEx("$env:SystemRoot\System32\shell32.dll", 4, [ref]$largePtr, [ref]$smallPtr, 1)
    if ($largePtr -ne [IntPtr]::Zero) {
        return [System.Drawing.Icon]::FromHandle($largePtr)
    } else {
        return [System.Drawing.SystemIcons]::Folder
    }
}

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

# ====== ADD ICON FUNCTION ======
function Add-LauncherIcon($path, $customName = $null) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }

    if (-not $global:isLoading) {
        if ($global:entries | Where-Object { $_.Path -eq $path }) {
            [System.Windows.Forms.MessageBox]::Show("This entry already exists.","Duplicate","OK","Information")
            return
        }
    }

    if (-not $customName) {
        $defaultName = if ($path -match '^https?://') { $path } else { [System.IO.Path]::GetFileNameWithoutExtension($path) }
        $customName = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a custom name:","Custom Name",$defaultName)
        if (-not $customName) { return }
    }

    $displayName = [System.IO.Path]::GetFileNameWithoutExtension($customName)
    $entry = [PSCustomObject]@{ Path = $path; Name = $displayName }

    $panelItem = New-Object System.Windows.Forms.Panel
    $panelItem.Width = $global:iconSize + 20
    $panelItem.Height = $global:iconSize + 35
    $panelItem.Tag = $path

    # ====== ICON ======
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size($global:iconSize, $global:iconSize)
    $pic.SizeMode = 'StretchImage'

    if ($path -match '^https?://') {
        $pic.Image = [System.Drawing.SystemIcons]::Information.ToBitmap()
    } elseif (Test-Path $path -PathType Container) {
        $folderIcon = Get-FolderIcon
        $pic.Image = $folderIcon.ToBitmap()
    } elseif (Test-Path $path) {
        try { $pic.Image = [System.Drawing.Icon]::ExtractAssociatedIcon($path).ToBitmap() }
        catch { $pic.Image = [System.Drawing.SystemIcons]::Application.ToBitmap() }
    } else {
        $pic.Image = [System.Drawing.SystemIcons]::Application.ToBitmap()
    }

    $pic.Location = New-Object System.Drawing.Point(0, 0)
    $pic.Tag = $path
    $panelItem.Controls.Add($pic)

    # ====== LABEL ======
    $label = New-Object System.Windows.Forms.Label
    $label.Text = if ($displayName.Length -gt 10) { $displayName.Substring(0, 9) + "..." } else { $displayName }
    $label.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(6, [Math]::Round($global:iconSize / 6)))
    $label.Location = New-Object System.Drawing.Point(0, $global:iconSize)
    $label.Width = $panelItem.Width
    $label.TextAlign = 'MiddleCenter'
    $panelItem.Controls.Add($label)

    # ====== HOVER EFFECT ======
    $pic.Add_MouseEnter({
        param($sender, $e)
        $panel = $sender.Parent
        $newSize = $global:iconSize + 15
        $panel.Width = $newSize + 20
        $panel.Height = $newSize + 35
        $sender.Size = New-Object System.Drawing.Size($newSize, $newSize)
        $sender.Location = New-Object System.Drawing.Point([math]::Floor(($panel.Width - $newSize)/2), 0)
        $label = $panel.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }
        if ($label) { $label.Location = New-Object System.Drawing.Point(0, $newSize) }
    })

    $pic.Add_MouseLeave({
        param($sender, $e)
        $panel = $sender.Parent
        $panel.Width = $global:iconSize + 20
        $panel.Height = $global:iconSize + 35
        $sender.Size = New-Object System.Drawing.Size($global:iconSize, $global:iconSize)
        $sender.Location = New-Object System.Drawing.Point(0,0)
        $label = $panel.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }
        if ($label) { $label.Location = New-Object System.Drawing.Point(0, $global:iconSize) }
    })

    # ====== CLICK ACTION ======
    $pic.Add_MouseClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            try {
                if ($sender.Tag -match '^https?://') { Start-Process $sender.Tag }
                elseif (Test-Path $sender.Tag) { Start-Process $sender.Tag }
            } catch {}
        }
    })

    # ====== RIGHT-CLICK DELETE ======
    $pic.Add_MouseUp({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
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
        }
    })

    try {
        $panel.Controls.Add($panelItem)
        [void]$global:entries.Add($entry)
        if (-not $global:isLoading) { Save-Entries }
    } catch {}
}

# ====== FORM UI SETUP ======
$form = New-Object System.Windows.Forms.Form
$form.Text = "Quick Launcher - by drox-Ph-Ceb    Gcash no. 0945-1035-299"
$form.Size = New-Object System.Drawing.Size(797, 500)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 250)

$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Location = New-Object System.Drawing.Point(20, 80)
$panel.Size = New-Object System.Drawing.Size(740, 370)
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

# ====== BUTTONS WITH COLORS ======
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
$addFileBtn.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 160)
$form.Controls.Add($addFileBtn)

$addFolderBtn = New-Object System.Windows.Forms.Button
$addFolderBtn.Text = "Add Folder"
$addFolderBtn.Location = New-Object System.Drawing.Point(550, 18)
$addFolderBtn.Size = New-Object System.Drawing.Size(90, 30)
$addFolderBtn.BackColor = [System.Drawing.Color]::FromArgb(180, 255, 180)
$form.Controls.Add($addFolderBtn)

# ====== SLIDER LABEL ======
$sizeLabel = New-Object System.Windows.Forms.Label
$sizeLabel.Text = "Icon Size: $($global:iconSize)"
$sizeLabel.AutoSize = $true
$sizeLabel.Location = New-Object System.Drawing.Point(650, 22)
$sizeLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$form.Controls.Add($sizeLabel)

# ====== ICON SIZE SLIDER (styled) ======
$sizeSlider = New-Object System.Windows.Forms.TrackBar
$sizeSlider.Location = New-Object System.Drawing.Point(710, 10)
$sizeSlider.Width = 60
$sizeSlider.Minimum = 32
$sizeSlider.Maximum = 96
$sizeSlider.Value = $global:iconSize
$sizeSlider.TickFrequency = 8
$sizeSlider.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 250)
$form.Controls.Add($sizeSlider)

# ====== BUTTON LOGIC ======
$addFolderBtn.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Add-LauncherIcon $folderDialog.SelectedPath
    }
})

$addFileBtn.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
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

$sizeSlider.Add_ValueChanged({
    $global:iconSize = $sizeSlider.Value
    $sizeLabel.Text = "Icon Size: $($global:iconSize)"
    Refresh-IconSizes
    Save-Entries
})

# ====== LOAD DATA ======
if (Test-Path $jsonPath) {
    $data = Get-Content $jsonPath -Raw | ConvertFrom-Json
    if ($data.IconSize) { $global:iconSize = [int]$data.IconSize }
    $global:isLoading = $true
    foreach ($entry in $data.Entries) { Add-LauncherIcon $entry.Path $entry.Name }
    $global:isLoading = $false
    Refresh-IconSizes
}

# ====== SHOW FORM ======
[void]$form.ShowDialog()
