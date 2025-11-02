Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# Import ExtractIconEx from shell32.dll (for real yellow folder icon)
Add-Type -Namespace Win32 -Name IconExtractor -MemberDefinition @"
    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
    public static extern int ExtractIconEx(string lpszFile, int nIconIndex, out System.IntPtr phiconLarge, out System.IntPtr phiconSmall, int nIcons);
"@

function Get-FolderIcon {
    $largeIconPtr = [IntPtr]::Zero
    $smallIconPtr = [IntPtr]::Zero
    [Win32.IconExtractor]::ExtractIconEx("$env:SystemRoot\System32\shell32.dll", 4, [ref]$largeIconPtr, [ref]$smallIconPtr, 1) | Out-Null
    if ($largeIconPtr -ne [IntPtr]::Zero) {
        return [System.Drawing.Icon]::FromHandle($largeIconPtr)
    } else {
        return [System.Drawing.SystemIcons]::Folder
    }
}

# ====== GLOBALS ======
$jsonPath = Join-Path $env:TEMP 'launcher.json'
$global:iconSize = 40
$global:entries = New-Object System.Collections.ArrayList
$global:isLoading = $false
$global:isDarkMode = $false
$script:dragging = $false
$script:dragPanel = $null
$script:dragStart = [System.Drawing.Point]::Empty
$tooltip = New-Object System.Windows.Forms.ToolTip

# ====== SAVE FUNCTION ======
function Save-Entries {
    try {
        $data = [PSCustomObject]@{
            IconSize  = $global:iconSize
            Entries   = @($global:entries)
            IsDarkMode = $global:isDarkMode
        }
        $temp = "$jsonPath.tmp"
        $data | ConvertTo-Json -Compress | Set-Content -Path $temp -Encoding UTF8 -ErrorAction SilentlyContinue
        Move-Item -Force $temp $jsonPath -ErrorAction SilentlyContinue
    } catch {}
}

# ====== ICON SIZE REFRESH ======
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
    $panelItem.BackColor = if ($global:isDarkMode) { [System.Drawing.Color]::FromArgb(70,70,70) } else { [System.Drawing.Color]::FromArgb(245, 250, 255) }

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
    $tooltip.SetToolTip($pic, $path)
    $panelItem.Controls.Add($pic)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = if ($displayName.Length -gt 10) { $displayName.Substring(0, 9) + "..." } else { $displayName }
    $label.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(6, [Math]::Round($global:iconSize / 6)))
    $label.Location = New-Object System.Drawing.Point(0, $global:iconSize)
    $label.Width = $panelItem.Width
    $label.TextAlign = 'MiddleCenter'
    $label.ForeColor = if ($global:isDarkMode) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
    $panelItem.Controls.Add($label)

    # Drag and rearrange logic
    $panelItem.Add_MouseDown({
        param($sender,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:dragging = $true
            $script:dragStart = $e.Location
            $script:dragPanel = $sender
            $sender.BringToFront()
        }
    })
    $panelItem.Add_MouseMove({
        param($sender,$e)
        if ($script:dragging -and $script:dragPanel -eq $sender) {
            $panel.SuspendLayout()
            $dx = $e.X - $script:dragStart.X
            $dy = $e.Y - $script:dragStart.Y
            $sender.Left += $dx
            $sender.Top += $dy
            $panel.ResumeLayout()
        }
    })
    $panelItem.Add_MouseUp({
        param($sender,$e)
        if ($script:dragging) {
            $script:dragging = $false
            $items = @($panel.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] })
            $sorted = $items | Sort-Object { $_.Top * 10000 + $_.Left }
            $panel.SuspendLayout()
            $panel.Controls.Clear()
            foreach ($item in $sorted) { $panel.Controls.Add($item) }
            $panel.ResumeLayout()
            $global:entries = New-Object System.Collections.ArrayList
            foreach ($ctrl in $panel.Controls) {
                $path = $ctrl.Tag
                $name = ($ctrl.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }).Text
                [void]$global:entries.Add([PSCustomObject]@{ Path = $path; Name = $name })
            }
            Save-Entries
            $panel.PerformLayout()
        }
    })

    # Hover effect
    $pic.Add_MouseEnter({
        param($sender,$e)
        $parent = $sender.Parent
        $newSize = $global:iconSize + 15
        $parent.Width = $newSize + 20
        $parent.Height = $newSize + 35
        $sender.Size = New-Object System.Drawing.Size($newSize, $newSize)
        $sender.Location = New-Object System.Drawing.Point([math]::Floor(($parent.Width - $newSize)/2), 0)
        $lbl = $parent.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }
        if ($lbl) { $lbl.Location = New-Object System.Drawing.Point(0, $newSize) }
    })
    $pic.Add_MouseLeave({
        param($sender,$e)
        $parent = $sender.Parent
        $parent.Width = $global:iconSize + 20
        $parent.Height = $global:iconSize + 35
        $sender.Size = New-Object System.Drawing.Size($global:iconSize, $global:iconSize)
        $sender.Location = New-Object System.Drawing.Point(0,0)
        $lbl = $parent.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }
        if ($lbl) { $lbl.Location = New-Object System.Drawing.Point(0, $global:iconSize) }
    })

    # Click to open
$pic.Add_MouseClick({
    param($sender,$e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        try {
            if ($sender.Tag -match '^https?://') {
                Start-Process $sender.Tag
            }
            elseif (Test-Path $sender.Tag) {
                $filePath = $sender.Tag
                $folderPath = [System.IO.Path]::GetDirectoryName($filePath)
                Start-Process -FilePath $filePath -WorkingDirectory $folderPath
            }
        } catch {}
    }
})

    # Right-click delete
    $pic.Add_MouseUp({
        param($sender,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            $displayName = ($global:entries | Where-Object { $_.Path -eq $sender.Tag }).Name
            $confirm = [System.Windows.Forms.MessageBox]::Show("Remove '$displayName'?", "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo)
            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                $panel.Controls.Remove($sender.Parent)
                $remaining = @($global:entries | Where-Object { $_.Path -ne $sender.Tag })
                $global:entries = New-Object System.Collections.ArrayList
                foreach ($r in $remaining) { [void]$global:entries.Add($r) }
                Save-Entries
            }
        }
    })

    try {
        $panel.Controls.Add($panelItem)
        [void]$global:entries.Add($entry)
        if (-not $global:isLoading) { Save-Entries }
    } catch {}
}

# ====== FORM ======
$form = New-Object System.Windows.Forms.Form
$form.Text = "Quick Launcher - by drox-Ph-Ceb    Gcash no. 0945-1035-299"
$form.Size = New-Object System.Drawing.Size(797,500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'Sizable'
$form.MinimumSize = New-Object System.Drawing.Size(600,400)

# ====== PANEL ======
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Location = New-Object System.Drawing.Point(20,80)
$panel.Size = New-Object System.Drawing.Size(740,370)
$panel.WrapContents = $true
$panel.AutoScroll = $true
$panel.FlowDirection = 'LeftToRight'
$panel.BorderStyle = 'FixedSingle'
$panel.Anchor = 'Top,Left,Right,Bottom'
$form.Controls.Add($panel)

# ====== SAFE RESIZE EVENT ======
$form.Add_Resize({
    try {
        $w = $form.ClientSize.Width
        $h = $form.ClientSize.Height

        # fallback if somehow $w or $h is null
        if (-not $w) { $w = 797 }
        if (-not $h) { $h = 500 }

        $panel.Width = $w - 40
        $panel.Height = $h - 110

        if ($themeCheckBox) {
            $themeCheckBox.Location = New-Object System.Drawing.Point($w - 130, 22)
        }
    } catch {}
})

# ====== INPUT + BUTTONS ======
$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location = New-Object System.Drawing.Point(20,20)
$urlBox.Width = 320
$urlBox.Font = 'Segoe UI,10'
$urlBox.ForeColor = 'Gray'
$urlBox.Text = "Enter URL here..."
$form.Controls.Add($urlBox)
$urlBox.Add_GotFocus({ if ($urlBox.ForeColor -eq 'Gray') { $urlBox.Text = ""; $urlBox.ForeColor = 'Black' } })
$urlBox.Add_LostFocus({ if ([string]::IsNullOrWhiteSpace($urlBox.Text)) { $urlBox.Text = "Enter URL here..."; $urlBox.ForeColor = 'Gray' } })

$addUrlBtn = New-Object System.Windows.Forms.Button
$addUrlBtn.Text = "Add URL"
$addUrlBtn.Location = New-Object System.Drawing.Point(350,18)
$addUrlBtn.Size = New-Object System.Drawing.Size(90,30)
$form.Controls.Add($addUrlBtn)

$addFileBtn = New-Object System.Windows.Forms.Button
$addFileBtn.Text = "Add File"
$addFileBtn.Location = New-Object System.Drawing.Point(450,18)
$addFileBtn.Size = New-Object System.Drawing.Size(90,30)
$form.Controls.Add($addFileBtn)

$addFolderBtn = New-Object System.Windows.Forms.Button
$addFolderBtn.Text = "Add Folder"
$addFolderBtn.Location = New-Object System.Drawing.Point(550,18)
$addFolderBtn.Size = New-Object System.Drawing.Size(90,30)
$form.Controls.Add($addFolderBtn)

$sizeLabel = New-Object System.Windows.Forms.Label
$sizeLabel.Text = "Icon Size: $($global:iconSize)"
$sizeLabel.AutoSize = $true
$sizeLabel.Location = New-Object System.Drawing.Point(650,22)
$form.Controls.Add($sizeLabel)

$sizeSlider = New-Object System.Windows.Forms.TrackBar
$sizeSlider.Location = New-Object System.Drawing.Point(710,10)
$sizeSlider.Width = 60
$sizeSlider.Minimum = 32
$sizeSlider.Maximum = 96
$sizeSlider.Value = $global:iconSize
$sizeSlider.TickFrequency = 8
$form.Controls.Add($sizeSlider)

# ====== THEME CHECKBOX ======
$themeCheckBox = New-Object System.Windows.Forms.CheckBox
$themeCheckBox.Text = "Dark Mode"
$themeCheckBox.Font = New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Italic)
$themeCheckBox.AutoSize = $true

# Place above all other controls (top-left), e.g., x=20, y=18
$themeCheckBox.Location = New-Object System.Drawing.Point(8,2)
$themeCheckBox.Anchor = 'Top,Left'

# Add to form first so it stays on top-left
$form.Controls.Add($themeCheckBox)
$themeCheckBox.BringToFront()

# ====== CHECKBOX EVENT ======
$themeCheckBox.Add_CheckedChanged({
    $global:isDarkMode = $themeCheckBox.Checked
    Apply-Theme $global:isDarkMode
})


# ====== APPLY THEME FUNCTION ======
function Apply-Theme {
    param([bool]$dark)

    if ($dark) {
        $form.BackColor = [System.Drawing.Color]::FromArgb(40,40,50)
        $panel.BackColor = [System.Drawing.Color]::FromArgb(60,60,70)
        $urlBox.BackColor = [System.Drawing.Color]::FromArgb(70,70,80)
        $urlBox.ForeColor = 'White'

        $addUrlBtn.BackColor = [System.Drawing.Color]::FromArgb(70,90,120)
        $addUrlBtn.ForeColor = 'White'

        $addFileBtn.BackColor = [System.Drawing.Color]::FromArgb(120,90,70)
        $addFileBtn.ForeColor = 'White'

        $addFolderBtn.BackColor = [System.Drawing.Color]::FromArgb(90,120,90)
        $addFolderBtn.ForeColor = 'White'

        $sizeSlider.BackColor = [System.Drawing.Color]::FromArgb(40,40,50)
        $sizeLabel.ForeColor = 'White'

        $themeCheckBox.ForeColor = 'White'
        $themeCheckBox.Checked = $true

        foreach ($ctrl in $panel.Controls) {
            if ($ctrl -is [System.Windows.Forms.Panel]) {
                $ctrl.BackColor = [System.Drawing.Color]::FromArgb(70,70,70)
                foreach ($sub in $ctrl.Controls) {
                    if ($sub -is [System.Windows.Forms.Label]) { $sub.ForeColor = [System.Drawing.Color]::White }
                }
            }
        }
    } else {
        $form.BackColor = [System.Drawing.Color]::FromArgb(230,240,250)
        $panel.BackColor = [System.Drawing.Color]::FromArgb(245,250,255)
        $urlBox.BackColor = 'White'
        $urlBox.ForeColor = 'Black'

        $addUrlBtn.BackColor = [System.Drawing.Color]::FromArgb(200,220,255)
        $addUrlBtn.ForeColor = 'Black'

        $addFileBtn.BackColor = [System.Drawing.Color]::FromArgb(255,220,160)
        $addFileBtn.ForeColor = 'Black'

        $addFolderBtn.BackColor = [System.Drawing.Color]::FromArgb(180,255,180)
        $addFolderBtn.ForeColor = 'Black'

        $sizeSlider.BackColor = [System.Drawing.Color]::FromArgb(230,240,250)
        $sizeLabel.ForeColor = [System.Drawing.Color]::FromArgb(60,60,60)

        $themeCheckBox.ForeColor = 'Black'
        $themeCheckBox.Checked = $false

        foreach ($ctrl in $panel.Controls) {
            if ($ctrl -is [System.Windows.Forms.Panel]) {
                $ctrl.BackColor = [System.Drawing.Color]::FromArgb(245,250,255)
                foreach ($sub in $ctrl.Controls) {
                    if ($sub -is [System.Windows.Forms.Label]) { $sub.ForeColor = [System.Drawing.Color]::Black }
                }
            }
        }
    }

    # Save dark mode setting
    Save-Entries
}

# ====== CHECKBOX EVENT ======
$themeCheckBox.Add_CheckedChanged({
    $global:isDarkMode = $themeCheckBox.Checked
    Apply-Theme $global:isDarkMode
})

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
$urlBox.Add_KeyDown({ param($s,$e) if ($e.KeyCode -eq "Enter") { $addUrlBtn.PerformClick() } })
$sizeSlider.Add_ValueChanged({
    $global:iconSize = $sizeSlider.Value
    $sizeLabel.Text = "Icon Size: $($global:iconSize)"
    Refresh-IconSizes
    Save-Entries
})

# ====== DRAG-DROP ======
$panel.AllowDrop = $true
$panel.Add_DragEnter({
    param($s,$e)
    $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    $s.BackColor = [System.Drawing.Color]::FromArgb(210,235,255)
    $s.BorderStyle = 'Fixed3D'
})
$panel.Add_DragLeave({
    param($s,$e)
    $s.BackColor = if ($global:isDarkMode) { [System.Drawing.Color]::FromArgb(60,60,70) } else { [System.Drawing.Color]::FromArgb(230,240,250) }
    $s.BorderStyle = 'FixedSingle'
})
$panel.Add_DragDrop({
    param($s,$e)
    $s.BackColor = if ($global:isDarkMode) { [System.Drawing.Color]::FromArgb(60,60,70) } else { [System.Drawing.Color]::FromArgb(230,240,250) }
    $s.BorderStyle = 'FixedSingle'
    if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
        foreach ($f in $files) { Add-LauncherIcon $f }
    } elseif ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::Text)) {
        $t = $e.Data.GetData([Windows.Forms.DataFormats]::Text)
        if ($t -match '^https?://') { Add-LauncherIcon $t }
    }
})

# ====== LOAD EXISTING ======
if (Test-Path $jsonPath) {
    try {
        $data = Get-Content $jsonPath -Raw | ConvertFrom-Json
        if ($null -ne $data.IconSize) {
            $global:iconSize = [int]$data.IconSize
            $sizeSlider.Value = $global:iconSize
            $sizeLabel.Text = "Icon Size: $($global:iconSize)"
        }
        if ($null -ne $data.IsDarkMode) {
            $global:isDarkMode = [bool]$data.IsDarkMode
        }
        $global:isLoading = $true
        if ($data.Entries) {
            foreach ($e in $data.Entries) { Add-LauncherIcon $e.Path $e.Name }
        }
        $global:isLoading = $false
        Apply-Theme $global:isDarkMode
    } catch {
        $global:isLoading = $false
        Apply-Theme $global:isDarkMode
    }
} else {
    Apply-Theme $global:isDarkMode
}

# ====== RUN FORM ======
[void]$form.ShowDialog()
