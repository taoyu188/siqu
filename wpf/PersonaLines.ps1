<#
  祀 · 台词库可视化编辑
  ------------------------------------------------------------------
  把 persona\persona.json 里的所有台词池列出来，可以：
    · 浏览每个池子（点击/问候/报错/答题反馈…）
    · 直接编辑、增删台词（一行一条）
    · 新增自定义台词池（为以后扩展留口子）
    · 保存前自动备份，JSON 不合法不会写坏原文件

  用法：
    powershell -ExecutionPolicy Bypass -File siqu\wpf\PersonaLines.ps1
    ... -RenderTo out.png     离屏渲染（开发时看界面）
#>
param([string]$RenderTo = '')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $here
$personaPath = Join-Path $appRoot 'persona\persona.json'

$brushConv = New-Object System.Windows.Media.BrushConverter
function B($hex) { $brushConv.ConvertFromString($hex) }

# ---------------- 读数据 ----------------
function Read-Persona {
  $raw = Get-Content $personaPath -Raw -Encoding UTF8
  return $raw | ConvertFrom-Json
}

$script:pj = $null
try { $script:pj = Read-Persona } catch { }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="祀 · 台词库" Width="820" Height="640"
        WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="False"
        WindowStartupLocation="CenterScreen"
        Background="#14171C" FontFamily="Microsoft YaHei UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="40"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="30"/>
    </Grid.RowDefinitions>

    <Border x:Name="TitleBar" Grid.Row="0" Background="#1B1F26">
      <Grid>
        <TextBlock Text="祀 · 台词库" Foreground="#8A93A0" FontSize="12"
                   VerticalAlignment="Center" Margin="14,0,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0">
          <TextBlock x:Name="PathText" Text="" Foreground="#4A525C" FontSize="10"
                     VerticalAlignment="Center" Margin="0,0,12,0"/>
          <Button x:Name="BtnClose" Content="✕" Width="30" Height="24"
                  Background="Transparent" Foreground="#7A838F" BorderThickness="0"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="14,12,14,8">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="230"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- 左：台词池列表 -->
      <Border Grid.Column="0" Background="#1A1E24" CornerRadius="10" Padding="8" Margin="0,0,12,0">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="台词池" Foreground="#8A93A0" FontSize="11" Margin="4,2,0,8"/>
          <ListBox x:Name="PoolList" Grid.Row="1" Background="Transparent" BorderThickness="0"
                   Foreground="#C9D1DB" FontSize="12"/>
          <StackPanel Grid.Row="2" Margin="0,8,0,0">
            <TextBox x:Name="NewPoolName" Height="26" Background="#232830" Foreground="#C9D1DB"
                     BorderThickness="0" Padding="6,4" FontSize="12" Margin="0,0,0,6"/>
            <Button x:Name="BtnAddPool" Content="新增台词池" Height="26" Background="#232830"
                    Foreground="#C9D1DB" BorderThickness="0" FontSize="12"/>
          </StackPanel>
        </Grid>
      </Border>

      <!-- 右：编辑区 -->
      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock x:Name="PoolTitle" Text="（未选择）" Foreground="#E6EAF0" FontSize="14" FontWeight="SemiBold"/>
          <TextBlock x:Name="PoolMeta" Text="" Foreground="#5F6874" FontSize="11"
                     VerticalAlignment="Bottom" Margin="10,0,0,2"/>
        </StackPanel>

        <Border Grid.Row="1" Background="#1A1E24" CornerRadius="10" Padding="10">
          <TextBox x:Name="Editor" Background="Transparent" Foreground="#DCE3EA"
                   BorderThickness="0" FontFamily="Microsoft YaHei UI" FontSize="13"
                   AcceptsReturn="True" TextWrapping="Wrap"
                   VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"/>
        </Border>

        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
          <Button x:Name="BtnSave" Content="保存" Width="80" Height="28" Background="#1E2A22"
                  Foreground="#6FC08A" BorderThickness="0" FontSize="12"/>
          <Button x:Name="BtnRevert" Content="撤销修改" Width="90" Height="28" Background="#232830"
                  Foreground="#C9D1DB" BorderThickness="0" FontSize="12" Margin="8,0,0,0"/>
          <Button x:Name="BtnDeletePool" Content="删除此池" Width="90" Height="28" Background="#2A1E22"
                  Foreground="#D98C8C" BorderThickness="0" FontSize="12" Margin="8,0,0,0"/>
          <TextBlock x:Name="Hint" Text="一行一条台词，保存后重启桌宠生效" Foreground="#4A525C"
                     FontSize="10" VerticalAlignment="Center" Margin="12,0,0,0"/>
        </StackPanel>
      </Grid>
    </Grid>

    <Border Grid.Row="2" Background="#1B1F26">
      <TextBlock x:Name="StatusBar" Text="" Foreground="#5F6874" FontSize="11"
                 VerticalAlignment="Center" Margin="14,0,0,0"/>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

$titleBar = $win.FindName('TitleBar')
$pathText = $win.FindName('PathText')
$btnClose = $win.FindName('BtnClose')
$poolList = $win.FindName('PoolList')
$newPoolName = $win.FindName('NewPoolName')
$btnAddPool = $win.FindName('BtnAddPool')
$poolTitle = $win.FindName('PoolTitle')
$poolMeta = $win.FindName('PoolMeta')
$editor = $win.FindName('Editor')
$btnSave = $win.FindName('BtnSave')
$btnRevert = $win.FindName('BtnRevert')
$btnDeletePool = $win.FindName('BtnDeletePool')
$hint = $win.FindName('Hint')
$statusBar = $win.FindName('StatusBar')

$pathText.Text = 'persona\persona.json'
$script:currentPool = ''

# 台词池的显示名（把 key 翻译成中文，方便认）
$poolNames = [ordered]@{
  clickTaunt    = '点击（呆货，会放语音）'
  idle          = '点击（备用闲话）'
  pout          = '赌气'
  idleClick     = '点击（旧版）'
  compileErrorFirst  = '编译报错 · 第一次见'
  compileErrorRepeat = '编译报错 · 重复犯'
  compileOk     = '编译通过'
  compileOkAfterStruggle = '编译通过 · 挣扎过'
  warning       = '编译警告'
  called        = '在代码里叫她'
  praise        = '被夸'
  jealous       = '吃醋'
  night         = '深夜'
  longAbsence   = '离开回来'
  sleep         = '犯困'
  retract       = '撤回（说漏嘴后）'
  burst         = '崩溃'
  crash         = '运行时崩溃'
  quizRight     = '每日三题 · 答对'
  quizWrong     = '每日三题 · 答错'
  greeting      = '问候'
  unknownFirst  = '未知错误 · 第一次'
  unknownRepeat = '未知错误 · 重复'
  noOutput      = '无输出'
}

function Get-PoolLabel([string]$key) {
  if ($poolNames.Contains($key)) { return "$($poolNames[$key])" }
  return $key
}

# 把对象写回 persona.json：ConvertTo-Json 会把中文转成 \uXXXX，这里还原成可读中文
function Write-PersonaJson($obj) {
  $json = $obj | ConvertTo-Json -Depth 12
  # 还原 \uXXXX 转义
  $json = [regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
    param($m)
    [string][char][Convert]::ToInt32($m.Groups[1].Value, 16)
  })
  # 写前校验：必须还能解析回来
  $null = $json | ConvertFrom-Json
  [IO.File]::WriteAllText($personaPath, $json, (New-Object Text.UTF8Encoding($true)))
}

function Get-PoolLines($value) {
  if ($null -eq $value) { return @() }
  if ($value -is [array]) { return @($value) }
  return @("$value")
}

function Refresh-PoolList([string]$selectKey = '') {
  $poolList.Items.Clear()
  if (-not $script:pj -or -not $script:pj.lines) { return }
  foreach ($prop in $script:pj.lines.PSObject.Properties) {
    $lines = Get-PoolLines $prop.Value
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Content = "$(Get-PoolLabel $prop.Name)  ($($lines.Count))"
    $item.Tag = $prop.Name
    [void]$poolList.Items.Add($item)
    if ($selectKey -and $prop.Name -eq $selectKey) { $poolList.SelectedItem = $item }
  }
}

function Show-Pool([string]$key) {
  $script:currentPool = $key
  if (-not $key) { return }
  $lines = Get-PoolLines $script:pj.lines.$key
  $poolTitle.Text = Get-PoolLabel $key
  $poolMeta.Text = "key: $key   共 $($lines.Count) 条"
  $editor.Text = ($lines -join "`n")
}

$poolList.Add_SelectionChanged({
  $sel = $poolList.SelectedItem
  if ($sel) { Show-Pool ([string]$sel.Tag) }
})

$btnRevert.Add_Click({
  if ($script:currentPool) {
    Show-Pool $script:currentPool
    $statusBar.Text = '已撤销未保存的修改'
  }
})

$btnSave.Add_Click({
  try {
    if (-not $script:currentPool) { return }
    $text = $editor.Text
    $lines = @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

    # 备份
    $bak = "$personaPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $personaPath $bak -Force

    # 写回：保持其他字段不变，只替换这个池
    $raw = Get-Content $personaPath -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json
    if ($lines.Count -eq 1) { $obj.lines.$($script:currentPool) = $lines[0] }
    else { $obj.lines.$($script:currentPool) = $lines }
    Write-PersonaJson $obj
    $script:pj = Read-Persona
    Refresh-PoolList $script:currentPool
    Show-Pool $script:currentPool
    $statusBar.Text = "已保存 $($lines.Count) 条台词（备份：$(Split-Path $bak -Leaf)）"
  } catch {
    $statusBar.Text = "保存失败：$($_.Exception.Message)"
  }
})

$btnAddPool.Add_Click({
  try {
    $name = ($newPoolName.Text + '').Trim()
    if (-not $name) { $statusBar.Text = '请先在左下输入框写池子名（英文，如 quizPerfect）'; return }
    if ($script:pj.lines.PSObject.Properties[$name]) { $statusBar.Text = "台词池 $name 已存在"; return }

    $bak = "$personaPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $personaPath $bak -Force

    $obj = Get-Content $personaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $obj.lines | Add-Member -NotePropertyName $name -NotePropertyValue @('（在这里写台词）') -Force
    Write-PersonaJson $obj

    $script:pj = Read-Persona
    $newPoolName.Text = ''
    Refresh-PoolList $name
    Show-Pool $name
    $statusBar.Text = "已新增台词池 $name"
  } catch {
    $statusBar.Text = "新增失败：$($_.Exception.Message)"
  }
})

$btnDeletePool.Add_Click({
  try {
    $key = $script:currentPool
    if (-not $key) { return }
    $ans = [System.Windows.MessageBox]::Show("确定删除台词池 `"$key`" ？", '祀 · 确认', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    $bak = "$personaPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $personaPath $bak -Force

    $obj = Get-Content $personaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $obj.lines.PSObject.Properties.Remove($key)
    Write-PersonaJson $obj

    $script:pj = Read-Persona
    $script:currentPool = ''
    $poolTitle.Text = '（未选择）'
    $poolMeta.Text = ''
    $editor.Text = ''
    Refresh-PoolList
    $statusBar.Text = "已删除台词池 $key"
  } catch {
    $statusBar.Text = "删除失败：$($_.Exception.Message)"
  }
})

$titleBar.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$btnClose.Add_Click({ $win.Close() })

$win.Add_Loaded({
  Refresh-PoolList 'clickTaunt'
  Show-Pool 'clickTaunt'
  $statusBar.Text = '保存后需重启桌宠才能生效；原文件会自动备份'
})

if ($RenderTo) {
  Refresh-PoolList 'clickTaunt'
  Show-Pool 'clickTaunt'
  $statusBar.Text = '保存后需重启桌宠才能生效；原文件会自动备份'
  $w = 820; $h = 640
  $root = $win.Content
  $root.Background = B '#14171C'
  $root.Measure((New-Object System.Windows.Size($w, $h)))
  $root.Arrange((New-Object System.Windows.Rect(0, 0, $w, $h)))
  $root.UpdateLayout()
  $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($root)
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [IO.File]::Create($RenderTo)
  $enc.Save($fs); $fs.Close()
  "已渲染: $RenderTo"
  exit 0
}

[void]$win.ShowDialog()
