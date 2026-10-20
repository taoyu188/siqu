<#
  祀 · 终末地日程
  ------------------------------------------------------------------
  本地计算，不联网、不需要游戏账号：
    · 每日/每周重置倒计时（服务器 04:00）
    · 理智推算（记录一次快照，按恢复速度往后算）
    · 每日/每周任务勾选（按游戏日/游戏周自动重置）

  用法：
    powershell -ExecutionPolicy Bypass -File siqu\wpf\SchedulePanel.ps1
    ... -RenderTo out.png    离屏渲染
#>
param([string]$RenderTo = '')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $here
$schedJs = Join-Path $appRoot 'core\schedule.js'

$brushConv = New-Object System.Windows.Media.BrushConverter
function B($hex) { $brushConv.ConvertFromString($hex) }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="祀 · 终末地日程" Width="580" Height="680"
        WindowStyle="None" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
        Background="#14171C" FontFamily="Microsoft YaHei UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="38"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="28"/>
    </Grid.RowDefinitions>

    <Border x:Name="TitleBar" Grid.Row="0" Background="#1B1F26">
      <Grid>
        <TextBlock Text="祀 · 终末地日程" Foreground="#8A93A0" FontSize="12"
                   VerticalAlignment="Center" Margin="14,0,0,0"/>
        <Button x:Name="BtnClose" Content="✕" Width="30" Height="22"
                Background="Transparent" Foreground="#7A838F" BorderThickness="0"
                HorizontalAlignment="Right" Margin="0,0,8,0"/>
      </Grid>
    </Border>

    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="14,12,14,6">
      <StackPanel>
        <!-- 森空岛实时数据 -->
        <Border x:Name="RemoteCard" Background="#1A1E24" CornerRadius="10" Padding="14,12" Margin="0,0,0,12" Visibility="Collapsed">
          <StackPanel>
            <Grid>
              <TextBlock x:Name="RemoteAccount" Text="" Foreground="#E0C08A" FontSize="13" FontWeight="SemiBold"/>
              <TextBlock x:Name="RemoteTag" Text="森空岛实时" Foreground="#5F6874" FontSize="10"
                         HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
            <Grid Margin="0,10,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="16"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Text="每日活跃" Foreground="#5F6874" FontSize="10"/>
                <TextBlock x:Name="RemoteDaily" Text="—" Foreground="#C9D1DB" FontSize="15" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="2">
                <TextBlock Text="每周进度" Foreground="#5F6874" FontSize="10"/>
                <TextBlock x:Name="RemoteWeekly" Text="—" Foreground="#8FB0D0" FontSize="15" Margin="0,2,0,0"/>
              </StackPanel>
            </Grid>
          </StackPanel>
        </Border>

        <!-- 倒计时 -->
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="12"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Background="#1A1E24" CornerRadius="10" Padding="14,12">
            <StackPanel>
              <TextBlock Text="距每日重置" Foreground="#5F6874" FontSize="11"/>
              <TextBlock x:Name="DailyLeft" Text="—" Foreground="#E0C08A" FontSize="22"
                         FontWeight="SemiBold" Margin="0,4,0,0"/>
              <TextBlock x:Name="DailyAt" Text="" Foreground="#4A525C" FontSize="10" Margin="0,2,0,0"/>
            </StackPanel>
          </Border>
          <Border Grid.Column="2" Background="#1A1E24" CornerRadius="10" Padding="14,12">
            <StackPanel>
              <TextBlock Text="距每周重置" Foreground="#5F6874" FontSize="11"/>
              <TextBlock x:Name="WeeklyLeft" Text="—" Foreground="#8FB0D0" FontSize="22"
                         FontWeight="SemiBold" Margin="0,4,0,0"/>
              <TextBlock x:Name="WeeklyAt" Text="" Foreground="#4A525C" FontSize="10" Margin="0,2,0,0"/>
            </StackPanel>
          </Border>
        </Grid>

        <!-- 理智 -->
        <Border Background="#1A1E24" CornerRadius="10" Padding="14,12" Margin="0,0,0,12">
          <StackPanel>
            <Grid>
              <TextBlock x:Name="StaminaLabel" Text="理智" Foreground="#5F6874" FontSize="11"/>
              <TextBlock x:Name="StaminaValue" Text="未记录" Foreground="#C9D1DB" FontSize="13"
                         HorizontalAlignment="Right"/>
            </Grid>
            <Border x:Name="StaminaTrack" Height="8" Background="#232830" CornerRadius="4" Margin="0,8,0,0">
              <Border x:Name="StaminaFill" Height="8" Background="#6FC08A" CornerRadius="4"
                      HorizontalAlignment="Left" Width="0"/>
            </Border>
            <Grid Margin="0,10,0,0">
              <StackPanel Orientation="Horizontal">
                <TextBox x:Name="SnapInput" Width="70" Height="26" Background="#232830"
                         Foreground="#C9D1DB" BorderThickness="0" Padding="6,4" FontSize="12"
                         VerticalContentAlignment="Center"/>
                <Button x:Name="BtnSnap" Content="记录快照" Height="26" Background="#232830"
                        Foreground="#C9D1DB" BorderThickness="0" FontSize="12" Padding="10,0"
                        Margin="6,0,0,0"/>
                <TextBlock x:Name="StaminaHint" Text="" Foreground="#4A525C" FontSize="10"
                           VerticalAlignment="Center" Margin="10,0,0,0"/>
              </StackPanel>
            </Grid>
          </StackPanel>
        </Border>

        <!-- 每日任务 -->
        <Grid Margin="0,0,0,6">
          <TextBlock Text="每日任务" Foreground="#8A93A0" FontSize="12"/>
          <TextBlock x:Name="DailyMeta" Text="" Foreground="#5F6874" FontSize="10"
                     HorizontalAlignment="Right"/>
        </Grid>
        <StackPanel x:Name="DailyList"/>

        <!-- 每周任务 -->
        <Grid Margin="0,14,0,6">
          <TextBlock Text="每周任务" Foreground="#8A93A0" FontSize="12"/>
          <TextBlock x:Name="WeeklyMeta" Text="" Foreground="#5F6874" FontSize="10"
                     HorizontalAlignment="Right"/>
        </Grid>
        <StackPanel x:Name="WeeklyList"/>
      </StackPanel>
    </ScrollViewer>

    <Border Grid.Row="2" Background="#1B1F26">
      <TextBlock x:Name="StatusBar" Text="" Foreground="#5F6874" FontSize="11"
                 VerticalAlignment="Center" Margin="14,0,0,0"/>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

$titleBar    = $win.FindName('TitleBar')
$btnClose    = $win.FindName('BtnClose')
$dailyLeft   = $win.FindName('DailyLeft')
$dailyAt     = $win.FindName('DailyAt')
$weeklyLeft  = $win.FindName('WeeklyLeft')
$weeklyAt    = $win.FindName('WeeklyAt')
$remoteCard  = $win.FindName('RemoteCard')
$remoteAcc   = $win.FindName('RemoteAccount')
$remoteTag   = $win.FindName('RemoteTag')
$remoteDaily = $win.FindName('RemoteDaily')
$remoteWeek  = $win.FindName('RemoteWeekly')
$staminaLabel= $win.FindName('StaminaLabel')
$staminaValue= $win.FindName('StaminaValue')
$staminaFill = $win.FindName('StaminaFill')
$staminaTrack= $win.FindName('StaminaTrack')
$snapInput   = $win.FindName('SnapInput')
$btnSnap     = $win.FindName('BtnSnap')
$staminaHint = $win.FindName('StaminaHint')
$dailyMeta   = $win.FindName('DailyMeta')
$dailyList   = $win.FindName('DailyList')
$weeklyMeta  = $win.FindName('WeeklyMeta')
$weeklyList  = $win.FindName('WeeklyList')
$statusBar   = $win.FindName('StatusBar')

$script:busy = $false

function Get-Status {
  $tmp = Join-Path $env:TEMP ("sched-" + [guid]::NewGuid().ToString('N') + ".json")
  & node $schedJs --json --out $tmp 2>$null | Out-Null
  if (-not (Test-Path $tmp)) { return $null }
  $s = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $s
}

function New-TaskRow($task, [string]$group) {
  $row = New-Object System.Windows.Controls.Border
  $row.Background = B '#1A1E24'
  $row.CornerRadius = New-Object System.Windows.CornerRadius(8)
  $row.Padding = New-Object System.Windows.Thickness(12, 8, 12, 8)
  $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)

  $grid = New-Object System.Windows.Controls.Grid
  $c1 = New-Object System.Windows.Controls.ColumnDefinition
  $c1.Width = [System.Windows.GridLength]::new(26)
  $c2 = New-Object System.Windows.Controls.ColumnDefinition
  $c2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
  [void]$grid.ColumnDefinitions.Add($c1)
  [void]$grid.ColumnDefinitions.Add($c2)

  $cb = New-Object System.Windows.Controls.CheckBox
  $cb.IsChecked = [bool]$task.done
  $cb.VerticalAlignment = 'Center'
  $cb.Tag = @{ id = $task.id; group = $group }
  [System.Windows.Controls.Grid]::SetColumn($cb, 0)

  $tb = New-Object System.Windows.Controls.StackPanel
  $name = New-Object System.Windows.Controls.TextBlock
  $name.Text = $task.name
  $name.FontSize = 12
  $name.Foreground = if ($task.done) { B '#5F6874' } else { B '#DCE3EA' }
  if ($task.done) { $name.TextDecorations = 'Strikethrough' }
  [void]$tb.Children.Add($name)
  if (-not $task.done -and $task.hint) {
    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = $task.hint
    $hint.FontSize = 10
    $hint.Foreground = B '#4A525C'
    $hint.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    $hint.TextWrapping = 'Wrap'
    [void]$tb.Children.Add($hint)
  }
  $tb.VerticalAlignment = 'Center'
  [System.Windows.Controls.Grid]::SetColumn($tb, 1)

  [void]$grid.Children.Add($cb)
  [void]$grid.Children.Add($tb)
  $row.Child = $grid

  $cb.Add_Click({
    if ($script:busy) { return }
    $script:busy = $true
    try {
      $info = $this.Tag
      $flag = if ($this.IsChecked) { '--done' } else { '--undo' }
      & node $schedJs $flag $info.id 2>$null | Out-Null
      $script:busy = $false
      Refresh-All
    } catch {
      $script:busy = $false
      $statusBar.Text = "更新失败：$($_.Exception.Message)"
    }
  }.GetNewClosure())

  return $row
}

function Refresh-All {
  $s = Get-Status
  if (-not $s) { $statusBar.Text = '读取日程失败'; return }

  # 森空岛实时数据
  if ($s.remote -and $s.remote.ok) {
    $remoteCard.Visibility = 'Visible'
    $a = $s.remote.account
    $remoteAcc.Text = if ($a) { "$($a.nickName)  Lv.$($a.level)  $($a.serverName)" } else { '（已连接）' }
    if ($s.remote.dailyActivation) {
      $d = $s.remote.dailyActivation
      $remoteDaily.Text = "$($d.value) / $($d.max)"
      $remoteDaily.Foreground = if ($d.value -ge $d.max) { B '#6FC08A' } else { B '#E0C08A' }
    } else { $remoteDaily.Text = '—' }
    if ($s.remote.weeklyScore) {
      $w = $s.remote.weeklyScore
      $remoteWeek.Text = "$($w.value) / $($w.total)"
    } else { $remoteWeek.Text = '—' }
  } else {
    $remoteCard.Visibility = 'Collapsed'
  }

  $dailyLeft.Text  = $s.daily.resetInText
  $dailyAt.Text    = '每天 ' + ([datetime]$s.daily.resetAt).ToString('HH:mm') + ' · 今日 ' + $s.daily.gameDay
  $weeklyLeft.Text = $s.weekly.resetInText
  $weeklyAt.Text   = '每周一 ' + ([datetime]$s.weekly.resetAt).ToString('HH:mm')

  $dailyMeta.Text  = "待办 $($s.daily.pending)/$($s.daily.tasks.Count)"
  $weeklyMeta.Text = "待办 $($s.weekly.pending)/$($s.weekly.tasks.Count)"

  $dailyList.Children.Clear()
  foreach ($t in $s.daily.tasks) { [void]$dailyList.Children.Add((New-TaskRow $t 'daily')) }
  $weeklyList.Children.Clear()
  foreach ($t in $s.weekly.tasks) { [void]$weeklyList.Children.Add((New-TaskRow $t 'weekly')) }

  $staminaLabel.Text = if ($s.staminaSource -eq 'remote') { "$($s.staminaCfg.unit)（森空岛实时）" } elseif ($s.staminaSource -eq 'local') { "$($s.staminaCfg.unit)（本地推算）" } else { $s.staminaCfg.unit }
  if ($s.stamina) {
    $staminaValue.Text = "$($s.stamina.value) / $($s.stamina.max)"
    $trackW = 524.0
    if ($staminaTrack.ActualWidth -gt 1) { $trackW = $staminaTrack.ActualWidth }
    $staminaFill.Width = [Math]::Max(1, [Math]::Round($trackW * $s.stamina.percent / 100))
    $staminaFill.Background = if ($s.stamina.percent -ge 90) { B '#D98C8C' } elseif ($s.stamina.percent -ge 70) { B '#E0C08A' } else { B '#6FC08A' }
    if ($s.stamina.full) { $staminaHint.Text = '已满，会溢出' ; $staminaHint.Foreground = B '#D98C8C' }
    else {
      $mins = [int]$s.stamina.fillMinutes
      $d = [Math]::Floor($mins / 1440); $h = [Math]::Floor(($mins % 1440) / 60); $m = $mins % 60
      $staminaHint.Text = if ($d -gt 0) { "回满还需 ${d}天${h}小时" } elseif ($h -gt 0) { "回满还需 ${h}小时${m}分" } else { "回满还需 ${m}分" }
      $staminaHint.Foreground = B '#4A525C'
    }
  } else {
    $staminaValue.Text = '未记录'
    $staminaFill.Width = 1
    $staminaHint.Text = '上面填当前数值，点「记录快照」'
    $staminaHint.Foreground = B '#4A525C'
  }

  $statusBar.Text = if ($s.remote -and $s.remote.ok) {
    '数据来自森空岛；任务勾选为本地记录'
  } elseif ($s.remote -and $s.remote.error) {
    "森空岛读取失败：$($s.remote.error)"
  } else {
    '未登录森空岛，用本地推算（node core\skland.js --qr 登录）'
  }
}

$btnSnap.Add_Click({
  try {
    $v = ($snapInput.Text + '').Trim()
    if (-not $v) { $statusBar.Text = '先填当前理智数值'; return }
    & node $schedJs --snapshot $v 2>$null | Out-Null
    $snapInput.Text = ''
    Refresh-All
    $statusBar.Text = "已记录快照：$v"
  } catch {
    $statusBar.Text = "记录失败：$($_.Exception.Message)"
  }
})

$btnClose.Add_Click({ $win.Close() })
$titleBar.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })

$win.Add_Loaded({ Refresh-All })

if ($RenderTo) {
  $w = 580; $h = 680
  $root = $win.Content
  $root.Background = B '#14171C'
  # 先刷新数据（此时没有 ActualWidth，用高度近似算进度条宽度）
  $s = Get-Status
  if ($s) {
    if ($s.remote -and $s.remote.ok) {
      $remoteCard.Visibility = 'Visible'
      $a = $s.remote.account
      if ($a) { $remoteAcc.Text = "$($a.nickName)  Lv.$($a.level)  $($a.serverName)" }
      if ($s.remote.dailyActivation) { $remoteDaily.Text = "$($s.remote.dailyActivation.value) / $($s.remote.dailyActivation.max)" }
      if ($s.remote.weeklyScore) { $remoteWeek.Text = "$($s.remote.weeklyScore.value) / $($s.remote.weeklyScore.total)" }
    }
    $dailyLeft.Text = $s.daily.resetInText
    $dailyAt.Text = '每天 ' + ([datetime]$s.daily.resetAt).ToString('HH:mm') + ' · 今日 ' + $s.daily.gameDay
    $weeklyLeft.Text = $s.weekly.resetInText
    $weeklyAt.Text = '每周一 ' + ([datetime]$s.weekly.resetAt).ToString('HH:mm')
    $dailyMeta.Text = "待办 $($s.daily.pending)/$($s.daily.tasks.Count)"
    $weeklyMeta.Text = "待办 $($s.weekly.pending)/$($s.weekly.tasks.Count)"
    foreach ($t in $s.daily.tasks) { [void]$dailyList.Children.Add((New-TaskRow $t 'daily')) }
    foreach ($t in $s.weekly.tasks) { [void]$weeklyList.Children.Add((New-TaskRow $t 'weekly')) }
    $staminaLabel.Text = if ($s.staminaSource -eq 'remote') { "$($s.staminaCfg.unit)（森空岛实时）" } elseif ($s.staminaSource -eq 'local') { "$($s.staminaCfg.unit)（本地推算）" } else { $s.staminaCfg.unit }
    if ($s.stamina) {
      $staminaValue.Text = "$($s.stamina.value) / $($s.stamina.max)"
      $mi = [int]$s.stamina.fillMinutes; $dd = [Math]::Floor($mi/1440); $hh = [Math]::Floor(($mi%1440)/60); $staminaHint.Text = if ($dd -gt 0) { "回满还需 $dd 天 $hh 小时" } else { "回满还需 $hh 小时" }
    } else {
      $staminaValue.Text = '未记录'
      $staminaHint.Text = '上面填当前数值，点「记录快照」'
    }
    $statusBar.Text = if ($s.remote -and $s.remote.ok) { '数据来自森空岛；任务勾选为本地记录' } else { '未登录森空岛，用本地推算' }
  }

  $root.Measure((New-Object System.Windows.Size($w, $h)))
  $root.Arrange((New-Object System.Windows.Rect(0, 0, $w, $h)))
  $root.UpdateLayout()
  if ($s -and $s.stamina) {
    $staminaFill.Width = [Math]::Max(1, [Math]::Round($staminaTrack.ActualWidth * $s.stamina.percent / 100))
    $root.UpdateLayout()
  }
  $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($root)
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [IO.File]::Create($RenderTo); $enc.Save($fs); $fs.Close()
  "已渲染: $RenderTo"
  exit 0
}

[void]$win.ShowDialog()
