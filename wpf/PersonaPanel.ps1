<#
  祀 · 状态面板 v2（独立可视模块）
  ------------------------------------------------------------------
  只读这两个文件，不依赖桌宠进程、不依赖 node：
    状态  %USERPROFILE%\.siqu\persona-state.json
    设定  siqu\persona\persona.json

  用法：
    powershell -ExecutionPolicy Bypass -File siqu\wpf\PersonaPanel.ps1
    ... -SelfTest             只校验数据读取，不显示窗口
    ... -RenderTo out.png     离屏渲染成图片（开发时用来看界面）
#>
param(
  [switch]$SelfTest,
  [string]$RenderTo = ''
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$here        = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot     = Split-Path -Parent $here
$personaFile = Join-Path $appRoot 'persona\persona.json'
$portrait    = Join-Path $appRoot 'assets\siqu-portrait-512.png'
$siquHome    = if ($env:SIQU_HOME) { $env:SIQU_HOME } else { Join-Path $env:USERPROFILE '.siqu' }
$stateFile   = Join-Path $siquHome 'persona-state.json'

$P = $null
if (Test-Path $personaFile) { $P = Get-Content $personaFile -Raw -Encoding UTF8 | ConvertFrom-Json }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="祀 · 状态面板" Width="660" Height="610"
        WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="False"
        WindowStartupLocation="CenterScreen"
        Background="#14171C" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style x:Key="FlatButton" TargetType="Button">
      <Setter Property="Background" Value="#232830"/>
      <Setter Property="Foreground" Value="#C9D1DB"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2E3540"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="40"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Border x:Name="TitleBar" Grid.Row="0" Background="#1B1F26">
      <Grid>
        <TextBlock Text="祀 · 状态面板" Foreground="#8A93A0" FontSize="12"
                   VerticalAlignment="Center" Margin="14,0,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0">
          <TextBlock x:Name="TitleMood" Text="" Foreground="#7FB4A0" FontSize="11"
                     VerticalAlignment="Center" Margin="0,0,12,0"/>
          <Button x:Name="BtnClose" Content="✕" Width="30" Height="24"
                  Style="{StaticResource FlatButton}" Background="Transparent" Foreground="#7A838F"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="16">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="190"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" CornerRadius="12" Margin="0,0,14,0">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#2A3038" Offset="0"/>
            <GradientStop Color="#1B1F26" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <StackPanel VerticalAlignment="Center">
          <Image x:Name="Sprite" Width="164" Height="164" Margin="0,-22,0,0" Stretch="Uniform"
                 RenderOptions.BitmapScalingMode="HighQuality">
            <Image.RenderTransform>
              <TransformGroup>
                <ScaleTransform x:Name="SpriteScale" ScaleX="1" ScaleY="1"/>
                <RotateTransform x:Name="SpriteRotate" Angle="0"/>
              </TransformGroup>
            </Image.RenderTransform>
          </Image>
          <Border x:Name="MoodChip" Background="#7FB4A0" CornerRadius="10"
                  HorizontalAlignment="Center" Padding="14,4" Margin="0,10,0,0">
            <TextBlock x:Name="MoodText" Text="待机" Foreground="#12161A"
                       FontSize="13" FontWeight="SemiBold"/>
          </Border>
          <TextBlock x:Name="NameText" Text="祀" Foreground="#6F7885" FontSize="11"
                     HorizontalAlignment="Center" Margin="0,8,0,0"/>
        </StackPanel>
      </Border>

      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
          <Grid>
            <TextBlock Text="好感度" Foreground="#8A93A0" FontSize="12" VerticalAlignment="Bottom"/>
            <TextBlock x:Name="AffText" Text="—" Foreground="#E6EAF0" FontSize="22"
                       FontWeight="SemiBold" HorizontalAlignment="Right"/>
          </Grid>

          <Grid x:Name="BarHost" Height="14" Margin="0,8,0,0">
            <Border Background="#232830" CornerRadius="7"/>
            <Border x:Name="BarFill" CornerRadius="7" HorizontalAlignment="Left" Width="0">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#5FA8A0" Offset="0"/>
                  <GradientStop Color="#8FE0C0" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
            </Border>
          </Grid>

          <Grid Margin="0,10,0,0">
            <StackPanel Orientation="Horizontal">
              <Border x:Name="LevelChip" Background="#232830" CornerRadius="8" Padding="10,3">
                <TextBlock x:Name="LevelText" Text="陌生" Foreground="#C9D1DB" FontSize="12"/>
              </Border>
              <TextBlock x:Name="NextText" Text="" Foreground="#6F7885" FontSize="11"
                         VerticalAlignment="Center" Margin="10,0,0,0"/>
            </StackPanel>
            <TextBlock x:Name="DaysText" Text="" Foreground="#5F6874" FontSize="11"
                       HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock x:Name="LevelNote" Text="" Foreground="#6F7885" FontSize="11"
                     TextWrapping="Wrap" Margin="0,8,0,0"/>
        </StackPanel>

        <Border Grid.Row="1" Background="#1A1E24" CornerRadius="10" Padding="12,10" Margin="0,14,0,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock x:Name="StatCompile" Text="0" Foreground="#CFE8DE" FontSize="18" FontWeight="SemiBold"/>
              <TextBlock Text="编译" Foreground="#5F6874" FontSize="10" Margin="0,2,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="1">
              <TextBlock x:Name="StatError" Text="0" Foreground="#D98C8C" FontSize="18" FontWeight="SemiBold"/>
              <TextBlock Text="错误" Foreground="#5F6874" FontSize="10" Margin="0,2,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="2">
              <TextBlock x:Name="StatRepeat" Text="0" Foreground="#E0A0C0" FontSize="18" FontWeight="SemiBold"/>
              <TextBlock Text="重复犯" Foreground="#5F6874" FontSize="10" Margin="0,2,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="3">
              <TextBlock x:Name="StatCalled" Text="0" Foreground="#8FD6A8" FontSize="18" FontWeight="SemiBold"/>
              <TextBlock Text="被叫" Foreground="#5F6874" FontSize="10" Margin="0,2,0,0"/>
            </StackPanel>
          </Grid>
        </Border>

        <Border Grid.Row="2" Background="#1A1E24" CornerRadius="10" Padding="10,8" Margin="0,12,0,0">
          <StackPanel>
            <TextBlock Text="好感度变化" Foreground="#8A93A0" FontSize="12"/>
            <Canvas x:Name="ChartCanvas" Height="64" Margin="0,6,0,0" ClipToBounds="True"/>
            <TextBlock x:Name="ChartCaption" Text="" Foreground="#5F6874" FontSize="10" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>

        <Grid Grid.Row="3" Margin="0,10,0,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="记忆 · 常犯的错" Foreground="#8A93A0" FontSize="12"/>
          <TextBlock x:Name="MemErrors" Grid.Row="1" Text="（还没有）" Foreground="#C9D1DB"
                     FontSize="12" TextWrapping="Wrap" LineHeight="21" Margin="0,6,0,0"/>
          <TextBlock Grid.Row="2" Text="最近" Foreground="#8A93A0" FontSize="12" Margin="0,12,0,0"/>
          <TextBlock x:Name="MemRecent" Grid.Row="3" Text="（还没有）" Foreground="#7A838F"
                     FontSize="11" TextWrapping="Wrap" LineHeight="19" Margin="0,6,0,0"/>
        </Grid>

        <StackPanel Grid.Row="4" Orientation="Horizontal" Margin="0,10,0,0">
          <Button x:Name="BtnRefresh" Content="刷新" Width="76" Style="{StaticResource FlatButton}"/>
          <Button x:Name="BtnTop" Content="置顶" Width="76" Margin="8,0,0,0" Style="{StaticResource FlatButton}"/>
          <Button x:Name="BtnReset" Content="重置好感度" Width="104" Margin="8,0,0,0" Style="{StaticResource FlatButton}"
                  Background="#2A1E22" Foreground="#D98C8C"/>
          <TextBlock x:Name="HintText" Text="" Foreground="#4A525C" FontSize="10"
                     VerticalAlignment="Center" Margin="12,0,0,0"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

$titleBar = $win.FindName('TitleBar')
$titleMood = $win.FindName('TitleMood')
$btnClose = $win.FindName('BtnClose')
$sprite   = $win.FindName('Sprite')
$sScale   = $win.FindName('SpriteScale')
$sRotate  = $win.FindName('SpriteRotate')
$moodChip = $win.FindName('MoodChip')
$moodText = $win.FindName('MoodText')
$nameText = $win.FindName('NameText')
$barFill  = $win.FindName('BarFill')
$barHost  = $win.FindName('BarHost')
$affText  = $win.FindName('AffText')
$levelChip= $win.FindName('LevelChip')
$levelText= $win.FindName('LevelText')
$levelNote= $win.FindName('LevelNote')
$nextText = $win.FindName('NextText')
$daysText = $win.FindName('DaysText')
$statCompile = $win.FindName('StatCompile')
$statError   = $win.FindName('StatError')
$statRepeat  = $win.FindName('StatRepeat')
$statCalled  = $win.FindName('StatCalled')
$memErrors   = $win.FindName('MemErrors')
$memRecent   = $win.FindName('MemRecent')
$btnRefresh  = $win.FindName('BtnRefresh')
$btnTop      = $win.FindName('BtnTop')
$btnReset    = $win.FindName('BtnReset')
$hintText    = $win.FindName('HintText')
$chartCanvas = $win.FindName('ChartCanvas')
$chartCaption= $win.FindName('ChartCaption')

# 立绘：按心情从 roles.json 里取对应表情，缺图回退
$script:stateImages = @{}
$rolesFile = Join-Path $appRoot 'roles\roles.json'
if (Test-Path $rolesFile) {
  try {
    $r = Get-Content $rolesFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $role = $r.roles | Where-Object { $_.id -eq $r.defaultRole } | Select-Object -First 1
    if (-not $role) { $role = $r.roles | Select-Object -First 1 }
    foreach ($prop in $role.images.PSObject.Properties) {
      $full = Join-Path $appRoot $prop.Value
      if (Test-Path $full) { $script:stateImages[$prop.Name] = $full }
    }
  } catch { }
}
if (-not $script:stateImages.ContainsKey('idle') -and (Test-Path $portrait)) {
  $script:stateImages['idle'] = $portrait
}

$script:bmpCache = @{}
function Get-SpriteImage([string]$state) {
  $path = if ($script:stateImages.ContainsKey($state)) { $script:stateImages[$state] } else { $script:stateImages['idle'] }
  if (-not $path) { return $null }
  if ($script:bmpCache.ContainsKey($path)) { return $script:bmpCache[$path] }
  $b = New-Object System.Windows.Media.Imaging.BitmapImage
  $b.BeginInit()
  $b.UriSource = New-Object System.Uri($path, [System.UriKind]::Absolute)
  $b.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $b.EndInit(); $b.Freeze()
  $script:bmpCache[$path] = $b
  return $b
}
$sprite.Source = Get-SpriteImage 'idle'
if ($P -and $P.name) { $nameText.Text = $P.name }

$brushConv = New-Object System.Windows.Media.BrushConverter

$visualMap = @{
  idle = @{ s = 1.0; r = 0 }; happy = @{ s = 1.05; r = 0 }
  taunt = @{ s = 0.97; r = -6 }; confused = @{ s = 1.0; r = 5 }
  sleep = @{ s = 0.98; r = 3 }; embarrassed = @{ s = 1.03; r = -3 }
  jealous = @{ s = 0.98; r = -5 }; pout = @{ s = 0.96; r = -8 }
}

$BAR_MAX = 0

function Get-LevelInfo($affinity) {
  $cur = @{ name = '陌生'; note = ''; min = 0 }
  $next = $null
  if ($P -and $P.levels) {
    $sorted = @($P.levels | Sort-Object min)
    foreach ($l in $sorted) { if ($affinity -ge $l.min) { $cur = $l } }
    foreach ($l in $sorted) { if ($l.min -gt $affinity) { $next = $l; break } }
  }
  return @{ cur = $cur; next = $next }
}

function Refresh-Panel {
  if (-not (Test-Path $stateFile)) {
    $affText.Text = '—'
    $memErrors.Text = '（去编译一次，我就开始记了）'
    $hintText.Text = '等待数据'
    return
  }
  try { $s = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { $affText.Text = '读取失败'; return }

  $aff = [double]$s.affinity
  $affText.Text = ('{0:N1}' -f $aff)
  $hostW = if ($barHost.ActualWidth -gt 0) { $barHost.ActualWidth } else { 300 }
  $barFill.Width = [Math]::Max(0, [Math]::Min($hostW, $hostW * $aff / 100))

  $info = Get-LevelInfo $aff
  $levelText.Text = $info.cur.name
  $levelNote.Text = $info.cur.note
  if ($info.next) {
    $nextText.Text = ('距【{0}】还差 {1:N1}' -f $info.next.name, ($info.next.min - $aff))
  } else {
    $nextText.Text = '已经是最高等级'
  }

  if ($s.firstSeen) {
    try {
      $days = [Math]::Max(1, [int]((Get-Date) - [datetime]$s.firstSeen).TotalDays + 1)
      $daysText.Text = "相伴 $days 天"
    } catch { $daysText.Text = '' }
  }

  $mood = "$($s.mood)"
  $meta = $null
  if ($P -and $P.moods -and $P.moods.PSObject.Properties[$mood]) { $meta = $P.moods.$mood }
  if ($meta) {
    $moodText.Text = $meta.label
    $moodChip.Background = $brushConv.ConvertFromString($meta.color)
    $titleMood.Text = $meta.label
    $titleMood.Foreground = $brushConv.ConvertFromString($meta.color)
    $vm = $visualMap[$meta.visual]
    if ($vm) { $sScale.ScaleX = $vm.s; $sScale.ScaleY = $vm.s; $sRotate.Angle = $vm.r }
    $img = Get-SpriteImage $meta.visual
    if ($img) {
      $curPath = if ($sprite.Source -and $sprite.Source.UriSource) { $sprite.Source.UriSource.LocalPath } else { '' }
      if ($curPath -ne $img.UriSource.LocalPath) { $sprite.Source = $img }
    }
  } else {
    $moodText.Text = $mood
    $titleMood.Text = $mood
  }

  $statCompile.Text = $s.counters.compiles
  $statError.Text   = $s.counters.errors
  $statRepeat.Text  = $s.counters.repeats
  $statCalled.Text  = $s.counters.called

  if ($s.memory.topErrors -and @($s.memory.topErrors).Count -gt 0) {
    $out = @(); $i = 0
    foreach ($e in @($s.memory.topErrors) | Select-Object -First 4) {
      $i++
      $short = ("$($e.short)" -replace '^error:\s*','')
      if ($short.Length -gt 44) { $short = $short.Substring(0, 44) + '…' }
      $out += ("{0}. [{1} 次] {2}" -f $i, $e.count, $short)
    }
    $memErrors.Text = ($out -join "`n")
  } else { $memErrors.Text = '（还没有）' }

  if ($s.memory.recent -and @($s.memory.recent).Count -gt 0) {
    $names = @{ 'compile-error' = '报错'; 'compile-ok' = '通过'; 'warning' = '警告'
                'called' = '叫她'; 'praise' = '夸她'; 'click' = '点击'
                'longAbsence' = '回来'; 'birthday' = '生日'; 'crash' = '崩溃' }
    $out = @()
    foreach ($r in @($s.memory.recent) | Select-Object -First 4) {
      $t = if ($names.ContainsKey("$($r.type)")) { $names["$($r.type)"] } else { $r.type }
      $note = ("$($r.note)" -replace '^error:\s*','')
      if ($note.Length -gt 40) { $note = $note.Substring(0, 40) + '…' }
      $out += ("· $t：$note")
    }
    $memRecent.Text = ($out -join "`n")
  } else { $memRecent.Text = '（还没有）' }

  $hintText.Text = '每秒自动刷新'
  Draw-Chart $s
}

# ---------------- 好感度曲线 ----------------
function Draw-Chart($state) {
  try {
    $chartCanvas.Children.Clear()
    $w = if ($chartCanvas.ActualWidth -gt 10) { $chartCanvas.ActualWidth } else { 400 }
    $h = 64

    $vals = @()
    $caption = ''

    # 优先用跨天数据（>=2 天），否则用本次会话的采样点
    if ($state.memory.daily) {
      $keys = @($state.memory.daily.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
      if ($keys.Count -ge 2) {
        foreach ($k in $keys) { $vals += [double]$state.memory.daily.$k.last }
        $caption = "近 $($keys.Count) 天"
      }
    }
    if ($vals.Count -lt 2 -and $state.memory.points) {
      $pv = @($state.memory.points | Select-Object -Last 60)
      if ($pv.Count -ge 2) {
        foreach ($p in $pv) { $vals += [double]$p.v }
        $caption = "本次 $($vals.Count) 次变化"
      }
    }

    if ($vals.Count -lt 2) {
      $chartCaption.Text = '数据还不够，多编译几次就有曲线了'
      return
    }

    $min = ($vals | Measure-Object -Minimum).Minimum
    $max = ($vals | Measure-Object -Maximum).Maximum
    $pad = [Math]::Max(1.0, ($max - $min) * 0.2)
    $lo = [Math]::Max(0, $min - $pad)
    $hi = [Math]::Min(100, $max + $pad)
    if ($hi -le $lo) { $hi = $lo + 1 }

    # 三条参考线
    foreach ($frac in 0, 0.5, 1) {
      $ln = New-Object System.Windows.Shapes.Line
      $ln.X1 = 0; $ln.X2 = $w
      $ln.Y1 = 4 + ($h - 8) * $frac; $ln.Y2 = $ln.Y1
      $ln.Stroke = $brushConv.ConvertFromString('#252B33')
      $ln.StrokeThickness = 1
      [void]$chartCanvas.Children.Add($ln)
    }

    $pts = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $vals.Count; $i++) {
      $x = 3 + ($w - 6) * $i / ($vals.Count - 1)
      $y = 4 + ($h - 8) * (1 - ($vals[$i] - $lo) / ($hi - $lo))
      $pts.Add((New-Object System.Windows.Point($x, $y)))
    }

    $poly = New-Object System.Windows.Shapes.Polyline
    $poly.Points = $pts
    $poly.Stroke = $brushConv.ConvertFromString('#8FE0C0')
    $poly.StrokeThickness = 2
    $poly.StrokeLineJoin = 'Round'
    [void]$chartCanvas.Children.Add($poly)

    $lastPt = $pts[$pts.Count - 1]
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 6; $dot.Height = 6
    $dot.Fill = $brushConv.ConvertFromString('#8FE0C0')
    [void]$chartCanvas.Children.Add($dot)
    [System.Windows.Controls.Canvas]::SetLeft($dot, $lastPt.X - 3)
    [System.Windows.Controls.Canvas]::SetTop($dot, $lastPt.Y - 3)

    $chartCaption.Text = ('{0}　最低 {1:N1}　最高 {2:N1}　当前 {3:N1}' -f $caption, $min, $max, $vals[$vals.Count-1])
  } catch {
    $chartCaption.Text = "曲线绘制失败：$($_.Exception.Message)"
  }
}

$titleBar.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$btnClose.Add_Click({ $win.Close() })

$btnRefresh.Add_Click({ Refresh-Panel })
$btnTop.Add_Click({
  $win.Topmost = -not $win.Topmost
  $btnTop.Content = if ($win.Topmost) { '取消置顶' } else { '置顶' }
})
$btnReset.Add_Click({
  $ans = [System.Windows.MessageBox]::Show('确定把好感度重置为初始值？记忆也会清空。', '祀 · 确认', 'YesNo', 'Question')
  if ($ans -eq 'Yes') {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { & node (Join-Path $appRoot 'core\persona.js') --reset | Out-Null }
    Refresh-Panel
  }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$timer.Add_Tick({ try { Refresh-Panel } catch {} })
$timer.Start()
$win.Add_Loaded({ Refresh-Panel })

# ---------------- 离屏渲染（开发时看界面用） ----------------
if ($RenderTo) {
  $w = 660; $h = 610
  $content = $win.Content
  $content.Background = $brushConv.ConvertFromString('#14171C')
  $content.Measure((New-Object System.Windows.Size($w, $h)))
  $content.Arrange((New-Object System.Windows.Rect(0, 0, $w, $h)))
  $content.UpdateLayout()
  Refresh-Panel          # 布局完成后再刷新，曲线才能拿到真实宽度
  $content.UpdateLayout()
  $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($content)
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [IO.File]::Create($RenderTo)
  $enc.Save($fs); $fs.Close()
  "已渲染: $RenderTo"
  exit 0
}

if ($SelfTest) {
  Refresh-Panel
  "自检通过"
  "  状态文件: $(if (Test-Path $stateFile) { '存在' } else { '不存在' })"
  "  心情=$($moodText.Text)  好感度=$($affText.Text)  等级=$($levelText.Text)  $($nextText.Text)"
  "  常犯的错: $($memErrors.Text -replace "`n", ' / ')"
  exit 0
}

[void]$win.ShowDialog()
