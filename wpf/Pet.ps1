<#
  祀 · 桌宠（WPF 版）
  ------------------------------------------------------------------
  纯 .NET，无 Chromium 依赖。

  表情/状态机制仿 dsh-whale-widget：
    * roles/roles.json 角色图库，按状态取图，缺图回退 idle
    * 状态 = 变换（缩放/倾斜/亮度）+ 浮动节奏 + 台词 + 气泡配色
    * 换真立绘之前，先用这些参数把「高兴 / 嫌弃 / 困惑 / 犯困」区分出来
#>
param(
  [switch]$NoWatch,
  [switch]$Hidden,   # 只做初始化自检，不显示窗口
  [switch]$Demo,
  [switch]$TestAudio # 只测语音：播一次含呆货的、一次不含的，然后退出
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$here      = Split-Path -Parent $MyInvocation.MyCommand.Path      # siqu\wpf
$appRoot   = Split-Path -Parent $here                             # siqu
$assetDir  = Join-Path $appRoot 'assets'
$rolesPath = Join-Path $appRoot 'roles\roles.json'
$diagJs    = Join-Path $appRoot 'core\diagnose.js'

$siquHome = Join-Path $env:USERPROFILE '.siqu'
if (-not (Test-Path $siquHome)) { New-Item -ItemType Directory -Path $siquHome -Force | Out-Null }
$buildLog = if ($env:SIQU_LOG) { $env:SIQU_LOG } else { Join-Path $siquHome 'build.log' }
$petLog   = if ($env:SIQU_PET_LOG) { $env:SIQU_PET_LOG } else { Join-Path $siquHome 'pet.log' }

function Write-PetLog($msg) {
  try { Add-Content -Path $petLog -Value "[$(Get-Date -Format 'HH:mm:ss')] $msg" -Encoding UTF8 } catch {}
}
Write-PetLog "=== start === (Demo=$Demo)"

# ---------------- 人格（可在 persona\persona.json 里改） ----------------
$personaPath = Join-Path $appRoot 'persona\persona.json'
$script:persona = @{
  greeting      = @('你好，管理员。')
  called        = @('……听到了。你好，管理员。')
  unknownFirst  = '这个错我没见过……先记下来了。'
  unknownRepeat = '又是这个。第 {count} 次了，你上次也这么写。'
  compileOk     = '编译过了，继续。'
  compileWarn   = '过了，但是……'
  noOutput      = '这个错我也没见过……'
  idle          = @('嗯？', '干嘛。', '……', '在看什么。', '有事？')
}
try {
  if (Test-Path $personaPath) {
    $pj = Get-Content $personaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($pj.lines) {
      foreach ($prop in $pj.lines.PSObject.Properties) {
        if ($null -ne $prop.Value -and "$($prop.Value)" -ne '') { $script:persona[$prop.Name] = $prop.Value }
      }
    }
    if ($pj.audio -and $pj.audio.daigo) { $script:audioCfg = $pj.audio.daigo }
    Write-PetLog "persona 已加载: $($pj.name)"
  }
} catch {
  Write-PetLog "persona 解析失败（用默认）: $($_.Exception.Message)"
}

# ---------------- 语音（点击时说"呆货"才放） ----------------
$script:player = $null
$script:soundPlayer = $null
$script:audioReady = $false

function Get-AudioPath {
  if (-not $script:audioCfg) { return $null }
  $rel = "$($script:audioCfg.file)"
  if (-not $rel) { return $null }
  $p = Join-Path $appRoot $rel
  if (Test-Path $p) { return $p }
  return $null
}

# 预加载：程序启动时就把 MediaPlayer 打开，第一次点击不卡
function Initialize-Audio {
  try {
    $path = Get-AudioPath
    if (-not $path) {
      Write-PetLog "音频未就绪（想听声音就把文件放到 $((Join-Path $appRoot 'assets\audio'))）"
      return
    }
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if ($ext -eq '.wav') {
      $script:soundPlayer = New-Object System.Media.SoundPlayer $path
      try { $script:soundPlayer.Load() } catch { }
    } else {
      $script:player = New-Object System.Windows.Media.MediaPlayer
      try { $script:player.Volume = [double]$script:audioCfg.volume } catch { }
      $script:player.Open((New-Object System.Uri($path, [System.UriKind]::Absolute)))
    }
    $script:audioReady = $true
    Write-PetLog "audio 预加载: $([IO.Path]::GetFileName($path))"
  } catch {
    Write-PetLog "audio 预加载失败: $($_.Exception.Message)"
  }
}

function Play-Daigo([string]$line) {
  try {
    if (-not $script:audioCfg) { return }
    $trigger = "$($script:audioCfg.triggerText)"
    if (-not $trigger) { return }
    if (-not $line -or $line -notlike "*$trigger*") { return }   # 台词里没触发词就不放

    $path = Get-AudioPath
    if (-not $path) { return }

    if (-not $script:audioReady) { Initialize-Audio }

    $ext = [IO.Path]::GetExtension($path).ToLower()
    if ($ext -eq '.wav') {
      if (-not $script:soundPlayer) { $script:soundPlayer = New-Object System.Media.SoundPlayer $path }
      $script:soundPlayer.Play()
    } else {
      if (-not $script:player) {
        $script:player = New-Object System.Windows.Media.MediaPlayer
        try { $script:player.Volume = [double]$script:audioCfg.volume } catch { }
        $script:player.Open((New-Object System.Uri($path, [System.UriKind]::Absolute)))
      }
      # 重复点击时从头再放
      try { $script:player.Position = [TimeSpan]::Zero } catch { }
      $script:player.Play()
    }
    Write-PetLog "audio: played ($ext)"
  } catch {
    Write-PetLog "audio error: $($_.Exception.Message)"
  }
}

# 从人格里取一句话（数组则随机）
function Get-Line([string]$key) {
  $v = $script:persona[$key]
  if ($null -eq $v) { return '' }
  if ($v -is [array]) { if ($v.Count -eq 0) { return '' }; return ($v | Get-Random) }
  return [string]$v
}

# ---------------- 状态参数 ----------------
$stateParams = @{
  idle        = @{ scale = 1.00; rotate = 0;  dim = 1.00; amp = 3.2; speed = 1.0 }
  happy       = @{ scale = 1.06; rotate = 0;  dim = 1.00; amp = 7.0; speed = 2.0 }
  taunt       = @{ scale = 0.97; rotate = -7; dim = 1.00; amp = 2.0; speed = 1.4 }
  confused    = @{ scale = 1.00; rotate = 6;  dim = 0.98; amp = 2.5; speed = 0.6 }
  embarrassed = @{ scale = 1.04; rotate = -4; dim = 1.00; amp = 4.5; speed = 1.8 }
  jealous     = @{ scale = 0.98; rotate = -9; dim = 1.00; amp = 1.6; speed = 1.6 }
  pout        = @{ scale = 0.95; rotate = -12; dim = 0.96; amp = 1.2; speed = 0.8 }
  sleep       = @{ scale = 0.98; rotate = 3;  dim = 0.72; amp = 1.2; speed = 0.35 }
}

# ---------------- 角色图库 ----------------
$stateImages = @{}
$defaultSprite = Join-Path $assetDir 'siqu-portrait-512.png'

if (Test-Path $rolesPath) {
  try {
    $roles = (Get-Content $rolesPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    # 当前角色：roles/active.txt 优先（本地覆盖，不进 git），否则用 defaultRole
    $activeFile = Join-Path $appRoot 'roles\active.txt'
    $wantId = $roles.defaultRole
    if (Test-Path $activeFile) {
      $local = (Get-Content $activeFile -Raw -Encoding UTF8).Trim()
      if ($local) { $wantId = $local }
    }
    $role = $roles.roles | Where-Object { $_.id -eq $wantId } | Select-Object -First 1
    # 选中的角色可能缺图（比如仓库里没带立绘），退回占位角色
    if ($role) {
      $hasAny = $false
      foreach ($pp in $role.images.PSObject.Properties) {
        if (Test-Path (Join-Path $appRoot $pp.Value)) { $hasAny = $true; break }
      }
      if (-not $hasAny) {
        $ph = $roles.roles | Where-Object { $_.id -eq 'placeholder' } | Select-Object -First 1
        if ($ph) {
          Write-PetLog "角色 $($role.id) 缺立绘，回退到 placeholder"
          $role = $ph
        }
      }
    }
    if (-not $role) { $role = $roles.roles | Select-Object -First 1 }
    if ($role) {
      Write-PetLog "role: $($role.name)"
      foreach ($p in $role.images.PSObject.Properties) {
        $full = Join-Path $appRoot $p.Value
        if (Test-Path $full) { $stateImages[$p.Name] = $full }
        else { Write-PetLog "  状态图缺失: $($p.Name) -> $($p.Value)" }
      }
      if ($role.scale -and $role.scale -ne 1.0) {
        foreach ($k in @($stateParams.Keys)) { $stateParams[$k].scale *= $role.scale }
      }
      # 角色自带的语音（优先于 persona.json 里的配置）
      if ($role.audio -and $role.audio.click -and $role.audio.click.file) {
        $script:audioCfg = [pscustomobject]@{
          file = $role.audio.click.file
          volume = if ($role.audio.click.volume) { $role.audio.click.volume } else { 0.85 }
          triggerText = if ($role.audio.click.triggerText) { $role.audio.click.triggerText } else { '' }
          onClick = $true
        }
        Write-PetLog "音频来自角色包: $($role.audio.click.file)"
      } elseif ($role.audio -and $null -eq $role.audio.click) {
        $script:audioCfg = $null
        Write-PetLog "角色包声明无点击语音"
      }
    }
  } catch {
    Write-PetLog "roles.json 解析失败: $($_.Exception.Message)"
  }
}
if (-not $stateImages.ContainsKey('idle')) {
  if (Test-Path $defaultSprite) { $stateImages['idle'] = $defaultSprite }
  else { throw "找不到任何立绘：$defaultSprite" }
}

function Get-StateImage([string]$state) {
  if ($stateImages.ContainsKey($state)) { return $stateImages[$state] }
  return $stateImages['idle']
}

# ---------------- 界面 ----------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="siqu" Width="220" Height="260"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        WindowStartupLocation="Manual" SnapsToDevicePixels="True">
  <Grid Background="Transparent">
    <Image x:Name="Sprite" Width="160" VerticalAlignment="Bottom" HorizontalAlignment="Center"
           RenderTransformOrigin="0.5,1" RenderOptions.BitmapScalingMode="HighQuality" Cursor="Hand">
      <Image.RenderTransform>
        <TransformGroup>
          <ScaleTransform x:Name="SpriteScale" ScaleX="1" ScaleY="1"/>
          <RotateTransform x:Name="SpriteRotate" Angle="0"/>
          <TranslateTransform x:Name="SpriteShift" Y="0"/>
        </TransformGroup>
      </Image.RenderTransform>
    </Image>

    <TextBlock x:Name="SleepMark" Text="z z Z" FontFamily="Microsoft YaHei UI"
               FontSize="15" FontWeight="Bold" Foreground="#8899AA"
               HorizontalAlignment="Right" VerticalAlignment="Top"
               Margin="0,44,30,0" Visibility="Collapsed" IsHitTestVisible="False"/>

    <Border x:Name="Bubble" VerticalAlignment="Top" HorizontalAlignment="Center"
            Margin="6,4,6,0" MaxWidth="208" Padding="10,7"
            Background="#F7FFFFFF" BorderBrush="#7FB4A0" BorderThickness="1"
            CornerRadius="12" Visibility="Collapsed">
      <Border.Effect>
        <DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.22" Color="#000000"/>
      </Border.Effect>
      <StackPanel>
        <TextBlock x:Name="BubbleText" FontFamily="Microsoft YaHei UI" FontSize="13"
                   FontWeight="SemiBold" Foreground="#22303C" TextWrapping="Wrap"/>
        <TextBlock x:Name="BubbleDetail" FontFamily="Microsoft YaHei UI" FontSize="11"
                   Foreground="#5A6B7A" TextWrapping="Wrap" Margin="0,4,0,0" Visibility="Collapsed"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

$sprite    = $win.FindName('Sprite')
$sScale    = $win.FindName('SpriteScale')
$sRotate   = $win.FindName('SpriteRotate')
$sShift    = $win.FindName('SpriteShift')
$sleepMark = $win.FindName('SleepMark')
$bubble    = $win.FindName('Bubble')
$bText     = $win.FindName('BubbleText')
$bDetail   = $win.FindName('BubbleDetail')

# ---------------- 立绘缓存 ----------------
$script:bmpCache = @{}
function Get-Sprite([string]$path) {
  if ($script:bmpCache.ContainsKey($path)) { return $script:bmpCache[$path] }
  $b = New-Object System.Windows.Media.Imaging.BitmapImage
  $b.BeginInit()
  $b.UriSource = New-Object System.Uri($path, [System.UriKind]::Absolute)
  $b.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $b.EndInit()
  $b.Freeze()
  $script:bmpCache[$path] = $b
  return $b
}

# ---------------- 定位 ----------------
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $win.Width - 24
$win.Top  = $wa.Bottom - $win.Height - 24

# ---------------- 状态 ----------------
$script:state = 'idle'
$script:phase = 0.0
$script:brushConv = New-Object System.Windows.Media.BrushConverter

function Set-State([string]$state) {
  if (-not $stateParams.ContainsKey($state)) { $state = 'idle' }
  $script:state = $state
  $p = $stateParams[$state]

  $sScale.ScaleX = $p.scale
  $sScale.ScaleY = $p.scale
  $sRotate.Angle = $p.rotate
  $sprite.Opacity = $p.dim
  $sleepMark.Visibility = if ($state -eq 'sleep') { 'Visible' } else { 'Collapsed' }

  $img = Get-StateImage $state
  $cur = if ($sprite.Source -and $sprite.Source.UriSource) { $sprite.Source.UriSource.LocalPath } else { '' }
  if ($cur -ne $img) { $sprite.Source = Get-Sprite $img }
}

# ---------------- 气泡 ----------------
$script:hideTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:hideTimer.Interval = [TimeSpan]::FromMilliseconds(6000)
$script:hideTimer.Add_Tick({
  $script:hideTimer.Stop()
  $bubble.Visibility = 'Collapsed'
  Set-State 'idle'
})

# 说一句，可带一条"稍后追问"（用来演她的撤回机制 / 生日彩蛋）
$script:followText = ''
$script:followState = 'taunt'
$script:followTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:followTimer.Interval = [TimeSpan]::FromMilliseconds(2200)
$script:followTimer.Add_Tick({
  $script:followTimer.Stop()
  if ($script:followText) {
    Say $script:followText '' 4500 $script:followState
    $script:followText = ''
  }
})

function Queue-Say([string]$text, [int]$delayMs = 2200, [string]$state = 'taunt') {
  if (-not $text) { return }
  $script:followText = $text
  $script:followState = $state
  $script:followTimer.Stop()
  $script:followTimer.Interval = [TimeSpan]::FromMilliseconds($delayMs)
  $script:followTimer.Start()
}

function Say-WithFollow([string]$text, [string]$followUp, [string]$detail = '', [int]$ms = 8000, [string]$state = 'idle') {
  Say $text $detail $ms $state
  if ($followUp) {
    $script:followText = $followUp
    $script:followTimer.Stop()
    $script:followTimer.Start()
  }
}

# 气泡配色按状态变（仿鲸鱼娘的多套气泡样式）
$bubbleStyles = @{
  idle        = @{ bg = '#F7FFFFFF'; border = '#7FB4A0'; fg = '#22303C' }
  happy       = @{ bg = '#F6F0FFF4'; border = '#6FC08A'; fg = '#1E4D2B' }
  taunt       = @{ bg = '#F8FFF4F4'; border = '#D98C8C'; fg = '#5A2222' }
  confused    = @{ bg = '#F8F4F8FF'; border = '#8C9BD9'; fg = '#22285A' }
  embarrassed = @{ bg = '#F8FFF4F8'; border = '#E0A0C0'; fg = '#5A2242' }
  jealous     = @{ bg = '#F8F8F0FF'; border = '#C98CC9'; fg = '#48224A' }
  pout        = @{ bg = '#F8FFF6F0'; border = '#D9A08C'; fg = '#5A3A22' }
  sleep       = @{ bg = '#F5F7F7FA'; border = '#9AA5B1'; fg = '#333A44' }
}

function Say([string]$text, [string]$detail = '', [int]$ms = 6000, [string]$state = 'idle') {
  $bText.Text = $text
  if ($detail) { $bDetail.Text = $detail; $bDetail.Visibility = 'Visible' }
  else { $bDetail.Text = ''; $bDetail.Visibility = 'Collapsed' }

  $st = if ($bubbleStyles.ContainsKey($state)) { $bubbleStyles[$state] } else { $bubbleStyles['idle'] }
  $bubble.Background = $script:brushConv.ConvertFromString($st.bg)
  $bubble.BorderBrush = $script:brushConv.ConvertFromString($st.border)
  $bText.Foreground = $script:brushConv.ConvertFromString($st.fg)

  Set-State $state
  $bubble.Visibility = 'Visible'
  $script:hideTimer.Stop()
  $script:hideTimer.Interval = [TimeSpan]::FromMilliseconds($ms)
  $script:hideTimer.Start()
}

# ---------------- 浮动动画（节奏随状态变） ----------------
$script:floatTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:floatTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$script:floatTimer.Add_Tick({
  $p = $stateParams[$script:state]
  $script:phase += 0.033 * 2.0 * $p.speed
  if ($script:phase -gt [Math]::PI * 2) { $script:phase -= [Math]::PI * 2 }
  $sShift.Y = [Math]::Sin($script:phase) * $p.amp
})
$script:floatTimer.Start()

# ---------------- 交互 ----------------
$script:downLeft = $null
$script:downPoint = $null
$script:dragged = $false

# 注意：不能在 MouseLeftButtonDown 里直接 DragMove()。
# 那会捕获鼠标直到松手，把立绘的 MouseUp 吞掉，"点她"就永远不触发。
# 正确做法：按下只记位置，移动超过阈值才真正开始拖。
$win.Add_MouseLeftButtonDown({
  $script:downLeft = $win.Left
  $script:downPoint = [System.Windows.Input.Mouse]::GetPosition($win)
  $script:dragged = $false
})

$win.Add_MouseMove({
  try {
    if ($null -eq $script:downPoint) { return }
    if ([System.Windows.Input.Mouse]::LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) {
      $script:downPoint = $null
      return
    }
    $pt = [System.Windows.Input.Mouse]::GetPosition($win)
    if ([Math]::Abs($pt.X - $script:downPoint.X) -gt 4 -or [Math]::Abs($pt.Y - $script:downPoint.Y) -gt 4) {
      $script:dragged = $true
      $script:downPoint = $null
      try { $win.DragMove() } catch {}
    }
  } catch {}
})

$win.Add_MouseLeftButtonUp({ $script:downPoint = $null })

$idleLines = @($script:persona['idle'])
$sprite.Add_MouseLeftButtonUp({
  if ($script:dragged) { $script:dragged = $false; $script:downLeft = $null; return }
  $script:downLeft = $null
  $pe = Invoke-Persona 'click'
  $txt = if ($pe -and $pe.line) { $pe.line } else { ($idleLines | Get-Random) }
  $state = if ($pe) { $pe.visual } else { 'taunt' }
  Say $txt '' 2500 $state

  # 只有"点击"这条路径会放语音；编译报错那条路径永远不放
  if (-not ($script:audioCfg -and $script:audioCfg.onClick -eq $false)) {
    Play-Daigo $txt
  }
})

# ---------------- 表情轮播（Demo） ----------------
$script:demoIndex = 0
$script:demoStates = @('idle', 'happy', 'taunt', 'confused', 'embarrassed', 'jealous', 'pout', 'sleep')
$script:demoTimer = $null

function Start-Demo {
  if ($script:demoTimer) { return }
  $script:demoIndex = 0
  $script:demoTimer = New-Object System.Windows.Threading.DispatcherTimer
  $script:demoTimer.Interval = [TimeSpan]::FromMilliseconds(2500)
  $script:demoTimer.Add_Tick({
    $st = $script:demoStates[$script:demoIndex % $script:demoStates.Count]
    $script:demoIndex++
    $lines = @{ idle = '……'; happy = '这题我会。'; taunt = '呆货。'; confused = '嗯？'; embarrassed = '别、别看我。'; jealous = '你倒是专心。'; pout = '哼。'; sleep = '困……' }
    Say $lines[$st] '' 2400 $st
  })
  $script:demoTimer.Start()
}

$menu = New-Object System.Windows.Controls.ContextMenu
function Add-MenuItem($header, $onClick) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $header
  $mi.Add_Click($onClick)
  [void]$menu.Items.Add($mi)
  return $mi
}
$script:pinItem = Add-MenuItem '取消置顶' {
  $win.Topmost = -not $win.Topmost
  $script:pinItem.Header = if ($win.Topmost) { '取消置顶' } else { '置顶' }
}
$null = Add-MenuItem '说点什么' { Say '嗯？' '' 2500 'taunt' }
$null = Add-MenuItem '轮播表情' { Start-Demo }
$null = Add-MenuItem '今日三题' {
  $quiz = Join-Path $appRoot 'wpf\QuizPanel.ps1'
  if (Test-Path $quiz) {
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
      -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$quiz`"") | Out-Null
  }
}
$null = Add-MenuItem '终末地日程' {
  $sched = Join-Path $appRoot 'wpf\SchedulePanel.ps1'
  if (Test-Path $sched) {
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
      -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$sched`"") | Out-Null
  }
}
$null = Add-MenuItem '状态面板' {
  $panel = Join-Path $appRoot 'wpf\PersonaPanel.ps1'
  if (Test-Path $panel) {
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
      -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$panel`"") | Out-Null
  }
}
$null = Add-MenuItem '台词库' {
  $lines = Join-Path $appRoot 'wpf\PersonaLines.ps1'
  if (Test-Path $lines) {
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
      -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$lines`"") | Out-Null
  }
}
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$null = Add-MenuItem '森空岛登录（扫码）' {
  $login = Join-Path $appRoot 'login-skland.cmd'
  if (Test-Path $login) {
    Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "`"$login`"") -WorkingDirectory $appRoot | Out-Null
  }
}
$null = Add-MenuItem '刷新森空岛数据' {
  $schedJs = Join-Path $appRoot 'core\schedule.js'
  $cache = Join-Path $env:USERPROFILE '.siqu\endfield-cache.json'
  if (Test-Path $cache) { Remove-Item $cache -Force -ErrorAction SilentlyContinue }
  if (Test-Path $schedJs) {
    Start-Process -FilePath 'node' -ArgumentList @($schedJs, '--now') -WorkingDirectory $appRoot -WindowStyle Hidden | Out-Null
    Say '刷新了。' '' 2500 'idle'
  }
}
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$null = Add-MenuItem '打开日志' { Start-Process notepad.exe $petLog }
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$null = Add-MenuItem '退出' { $win.Close() }
$win.ContextMenu = $menu

# ---------------- 运行时崩溃监听 ----------------
# 原理：程序异常终止时 Windows 会往事件日志写一条 Application Error，
# 里面有 exe 名和异常代码。我们只读日志，不碰 Dev-C++，也不需要管理员权限。
$script:crashModule = Join-Path $appRoot 'core\crashinfo.ps1'
$script:lastCrashId = 0
$script:crashArmed = $false
$script:crashTick = 0
$script:crashTestMode = ($env:SIQU_CRASH_TEST -eq '1')

if (Test-Path $script:crashModule) {
  . $script:crashModule
  try {
    $r = Get-RecentCrashEvents -Max 1
    if ($r -and @($r).Count -gt 0) { $script:lastCrashId = [long]$r[0].RecordId }
  } catch {}
  $script:crashArmed = $true
  Write-PetLog "crash watch armed (baseline=$($script:lastCrashId), testMode=$($script:crashTestMode))"
} else {
  Write-PetLog "crashinfo.ps1 缺失，崩溃监听关闭"
}

function Check-Crashes {
  try {
    $new = @(Get-NewCrashes -SinceId $script:lastCrashId)
    if ($new.Count -eq 0) { return }
    foreach ($c in $new) {
      $script:lastCrashId = [Math]::Max($script:lastCrashId, [long]$c.RecordId)
      Write-PetLog "crash: exe=$($c.Exe) code=$($c.Code) title=$($c.Title)"
      $pe = Invoke-Persona 'crash' $c.Title -Said $c.Taunt
      $state = if ($pe) { $pe.visual } else { 'taunt' }
      Say $c.Taunt "$($c.Title)`n$($c.Fix)" 14000 $state
    }
  } catch {
    Write-PetLog "crash check error: $($_.Exception.Message)"
  }
}

if ($script:crashArmed) {
  $script:crashTimer = New-Object System.Windows.Threading.DispatcherTimer
  $script:crashTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
  $script:crashTimer.Add_Tick({
    try {
      $script:crashTick++
      # 正常模式：只在 Dev-C++ 的 ConsolePauser 存在时密集轮询（避免空转卡动画）
      # 兜底：每 50 拍（约 60 秒）无论如何查一次，覆盖"直接双击运行 exe"的情况
      $should = $false
      if ($script:crashTestMode) { $should = $true }
      else {
        $cp = Get-Process ConsolePauser -ErrorAction SilentlyContinue
        if ($cp) { $script:crashArmed = $true; $should = ($script:crashTick % 2 -eq 0) }
        elseif ($script:crashTick % 50 -eq 0) { $should = $true }
      }
      if ($should) { Check-Crashes }
    } catch {}
  })
  $script:crashTimer.Start()
}
# ---------------- 编译日志监听 ----------------
$script:lastWrite = [DateTime]::MinValue

# 调用人格引擎：更新心情/好感度/记忆，返回它的台词和建议的立绘状态
function Invoke-Persona([string]$eventName, [string]$short = '', [switch]$Repeat, [switch]$Known, [switch]$AfterError, [string]$Said = '') {
  try {
    $pj = Join-Path $appRoot 'core\persona.js'
    if (-not (Test-Path $pj)) { return $null }
    $tmpP = Join-Path $env:TEMP "siqu-persona-$PID.json"
    Remove-Item $tmpP -Force -ErrorAction SilentlyContinue
    $a = @($pj, '--event', $eventName, '--json', '--out', $tmpP)
    if ($short) { $a += @('--short', $short) }
    if ($Said) { $a += @('--said', $Said) }
    if ($Repeat) { $a += '--repeat' }
    if ($Known) { $a += '--known' }
    if ($AfterError) { $a += '--after-error' }
    & node @a 2>$null | Out-Null
    if (-not (Test-Path $tmpP)) { return $null }
    return (Get-Content $tmpP -Raw -Encoding UTF8) | ConvertFrom-Json
  } catch {
    Write-PetLog "persona error: $($_.Exception.Message)"
    return $null
  }
}

function Invoke-Diagnose {
  try {
    if (-not (Test-Path $buildLog)) { return }

    # 关键：不要让 PowerShell 去解码 node 的 stdout（GBK 会把 UTF-8 中文
    # 拆坏，连 JSON 引号都会被吃掉 → 解析失败 → 桌宠默默不反应）。
    # 改成 node 直接写文件，我们按 UTF-8 读。
    $tmp = Join-Path $env:TEMP "siqu-diag-$PID.json"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    & node $diagJs --file $buildLog --json --record --out $tmp 2>$null | Out-Null
    if (-not (Test-Path $tmp)) {
      Write-PetLog 'diagnose: 没有产出结果文件（node 调用失败？）'
      return
    }
    $jsonText = Get-Content $tmp -Raw -Encoding UTF8
    $res = $jsonText | ConvertFrom-Json
    $hits = @($res.hits)
    $bookInfo = if ($res.book) { " count=$($res.book.count) repeat=$($res.book.isRepeat) saved=$($res.book.saved)" } else { '' }
    Write-PetLog "diagnose: ok=$($res.ok) hits=$($hits.Count)$bookInfo"

    $short = if ($res.book -and $res.book.short) { $res.book.short } elseif ($hits.Count -gt 0) { $hits[0].title } else { '' }

    # ---- 编译通过 ----
    if ($res.ok) {
      # 1) 源码里在叫她？
      $cf = Invoke-CodeAware $res.source
      if ($cf -and $cf.kind -and $cf.kind -ne 'none') {
        Write-PetLog "codeaware: $($cf.kind)"
        $pe = Invoke-Persona 'called' $cf.kind
        $state = if ($pe) { $pe.visual } else { 'happy' }
        $fu = if ($pe) { $pe.followUp } else { '' }
        Say-WithFollow $cf.say $fu $cf.detail 8000 $state
        return
      }
      # 2) 有警告？（注意：scanf 忘 & 这类只是警告、exit=0，但台词要用规则库的）
      if ($hits.Count -gt 0) {
        $pe = Invoke-Persona 'warning' $hits[0].title -Said $hits[0].taunt
        $state = if ($pe) { $pe.visual } else { 'confused' }
        Say $hits[0].taunt "$($hits[0].title)`n$($hits[0].fix)" 10000 $state
        return
      }
      # 3) 干净通过（可能触发吃醋）
      $pe = Invoke-Persona 'compile-ok' '' -AfterError
      $state = if ($pe) { $pe.visual } else { 'happy' }
      $line = if ($pe -and $pe.line) { $pe.line } else { Get-Line 'compileOk' }
      $fu = if ($pe) { $pe.followUp } else { '' }
      Say-WithFollow $line $fu '' 5000 $state
      return
    }

    # ---- 编译失败 ----
    if ($hits.Count -gt 0) {
      # 规则库认识的错：台词用规则库的，心情/好感度交给人格引擎
      $pe = Invoke-Persona 'compile-error' $short -Known -Said $hits[0].taunt
      $state = if ($pe) { $pe.visual } else { 'taunt' }
      Say $hits[0].taunt "$($hits[0].title)`n$($hits[0].fix)" 12000 $state
      return
    }

    # 规则库没认出来 → 错题库（重复的错她认得出来）
    $detail = ''
    if ($res.book) {
      $detail = if ($res.book.short) { $res.book.short } else { $res.book.sample }
    }
    if ($res.book -and $res.book.isRepeat) {
      $pe = Invoke-Persona 'compile-error' $detail -Repeat
      $state = if ($pe) { $pe.visual } else { 'taunt' }
      $line = if ($pe -and $pe.line) { $pe.line } else { (Get-Line 'unknownRepeat').Replace('{count}', "$($res.book.count)") }
      Say $line $detail 12000 $state
    } elseif ($res.book) {
      $pe = Invoke-Persona 'compile-error' $detail
      $state = if ($pe) { $pe.visual } else { 'confused' }
      $line = if ($pe -and $pe.line) { $pe.line } else { Get-Line 'unknownFirst' }
      Say $line $detail 10000 $state
    } else {
      Say (Get-Line 'noOutput') '' 5000 'confused'
    }
  } catch {
    Write-PetLog "diagnose error: $($_.Exception.Message)"
  }
}

# 编译成功后，瞄一眼源码里有没有对她说话
function Invoke-CodeAware([string]$srcPath) {
  try {
    if (-not $srcPath -or -not (Test-Path $srcPath)) { return $null }
    $codeJs = Join-Path $appRoot 'core\codeaware.js'
    if (-not (Test-Path $codeJs)) { return $null }
    $tmp2 = Join-Path $env:TEMP "siqu-code-$PID.json"
    Remove-Item $tmp2 -Force -ErrorAction SilentlyContinue
    & node $codeJs --file $srcPath --json --out $tmp2 2>$null | Out-Null
    if (-not (Test-Path $tmp2)) { return $null }
    return (Get-Content $tmp2 -Raw -Encoding UTF8) | ConvertFrom-Json
  } catch {
    Write-PetLog "codeaware error: $($_.Exception.Message)"
    return $null
  }
}

if (-not $NoWatch) {
  try {
    if (-not (Test-Path $buildLog)) { New-Item -ItemType File -Path $buildLog -Force | Out-Null }
    $script:lastWrite = (Get-Item $buildLog).LastWriteTime
  } catch {
    Write-PetLog "watch 初始化失败: $($_.Exception.Message)"
  }
  $script:watchTimer = New-Object System.Windows.Threading.DispatcherTimer
  $script:watchTimer.Interval = [TimeSpan]::FromMilliseconds(900)
  $script:watchTimer.Add_Tick({
    try {
      $f = Get-Item $buildLog -ErrorAction SilentlyContinue
      if ($f -and $f.LastWriteTime -gt $script:lastWrite) {
        $script:lastWrite = $f.LastWriteTime
        Invoke-Diagnose
      }
    } catch {}
  })
  $script:watchTimer.Start()
  Write-PetLog "watching $buildLog"
}

# ---------------- 启动 ----------------
$aliveFile = Join-Path $siquHome 'pet-alive.json'

$win.Add_Loaded({
  Write-PetLog "loaded at ($($win.Left),$($win.Top)) visible=$($win.IsVisible)"
  try {
    @{ pid = $PID; stage = 'shown'; at = (Get-Date -Format 'o') } |
      ConvertTo-Json | Set-Content -Path $aliveFile -Encoding UTF8
  } catch { Write-PetLog "存活标记写入失败: $($_.Exception.Message)" }

  Set-State 'idle'
  Initialize-Audio
  Say '我在。' '' 3000 'idle'

  # 生日彩蛋：九月十五，她会假装什么都没发生，然后说漏嘴
  try {
    $pb = Invoke-Persona 'birthday'
    if ($pb -and $pb.line) {
      Write-PetLog "birthday egg fired"
      Queue-Say $pb.line 2600 'happy'
    }
  } catch { Write-PetLog "birthday check failed: $($_.Exception.Message)" }

  if ($Demo) { Start-Demo }
})

$win.Add_Closed({
  try { Remove-Item $aliveFile -Force -ErrorAction SilentlyContinue } catch {}
  Write-PetLog 'window closed'
})

# ---------------- Python 报错监视 ----------------
$script:pyLog = Join-Path $env:USERPROFILE '.siqu\python.log'
$script:pyPos = -1
$script:pyDiagJs = Join-Path $appRoot 'core\pydiag.js'

function Invoke-PyDiagnose {
  try {
    if (-not (Test-Path $script:pyDiagJs)) { return $null }
    $tmp = Join-Path $env:TEMP ("pydiag-" + [guid]::NewGuid().ToString('N') + ".json")
    & node $script:pyDiagJs --json --out $tmp 2>$null | Out-Null
    if (-not (Test-Path $tmp)) { return $null }
    $d = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $d
  } catch {
    Write-PetLog "pydiag failed: $($_.Exception.Message)"
    return $null
  }
}

# 启动时先记住当前日志长度，避免把历史错误再吐槽一遍
try {
  $script:pyPos = if (Test-Path $script:pyLog) { [long](Get-Item $script:pyLog).Length } else { [long]0 }
} catch { $script:pyPos = [long]0 }

$script:pyTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pyTimer.Interval = [TimeSpan]::FromSeconds(3)
$script:pyTimer.Add_Tick({
  try {
    if (-not (Test-Path $script:pyLog)) { return }
    $len = (Get-Item $script:pyLog).Length

    if ($len -le $script:pyPos) {
      if ($len -lt $script:pyPos) { $script:pyPos = $len }   # 日志被清空过
      return
    }
    $script:pyPos = $len
    if ($NoWatch) { return }

    $d = Invoke-PyDiagnose
    if (-not $d -or $d.ok -ne $false) { return }

    $rule = $d.rule
    $loc = ''
    if ($d.file) {
      $loc = "位置：$([IO.Path]::GetFileName($d.file)):$($d.line)"
      if ($d.source) { $loc = $loc + "`n代码：$($d.source)" }
    }
    $mood = if ($rule.id -eq 'py-generic') { 'confused' } else { 'taunt' }
    Say-WithFollow $rule.taunt ("怎么改：" + $rule.fix) ("● " + $rule.title + "`n" + $rule.why + "`n" + $loc) 14000 $mood
    Write-PetLog "python error: $($d.type) @ $($d.file):$($d.line)  rule=$($rule.id)"
  } catch {
    Write-PetLog "py watch error: $($_.Exception.Message)"
  }
})
$script:pyTimer.Start()
# ---------------- 终末地日程提醒（每 10 分钟检查一次） ----------------
$script:schedJs = Join-Path $appRoot 'core\schedule.js'
$script:schedRemindedDay = ''
$script:schedRemindedStamina = ''

function Test-ScheduleReminder {
  try {
    if (-not (Test-Path $script:schedJs)) { return }
    $tmp = Join-Path $env:TEMP ("sched-pet-" + [guid]::NewGuid().ToString('N') + ".json")
    & node $script:schedJs --json --out $tmp 2>$null | Out-Null
    if (-not (Test-Path $tmp)) { return }
    $s = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not $s -or -not $s.reminders.enabled) { return }

    # 1) 重置前提醒：还差 < 阈值 且 有未完成的
    $before = [int]$s.reminders.beforeResetMinutes
    $hasRemote = $s.remote -and $s.remote.ok
    $remoteDaily = if ($hasRemote -and $s.remote.dailyActivation) { $s.remote.dailyActivation } else { $null }
    $remoteWeekly = if ($hasRemote -and $s.remote.weeklyScore) { $s.remote.weeklyScore } else { $null }

    $unfinished = 0
    $parts = @()
    if ($remoteDaily) {
      if ($remoteDaily.value -lt $remoteDaily.max) { $unfinished++; $parts += "每日活跃 $($remoteDaily.value)/$($remoteDaily.max)" }
    }
    if ($remoteWeekly) {
      if ($remoteWeekly.value -lt $remoteWeekly.total) { $unfinished++; $parts += "每周 $($remoteWeekly.value)/$($remoteWeekly.total)" }
    }
    if (-not $hasRemote) {
      $unfinished = [int]$s.daily.pending + [int]$s.weekly.pending
      $names = @($s.daily.tasks | Where-Object { -not $_.done } | ForEach-Object { $_.name })
      if ($names.Count) { $parts += '还有 ' + ($names -join '、') + ' 没做' }
    }

    if ($s.daily.resetInMinutes -le $before -and $unfinished -gt 0 -and $script:schedRemindedDay -ne $s.daily.gameDay) {
      $script:schedRemindedDay = $s.daily.gameDay
      $text = '……还有 ' + $s.daily.resetInMinutes + ' 分钟就重置了。' + ($parts -join '，') + '。'
      Say $text '' 9000 'taunt'
      Write-PetLog "schedule reminder: resetIn=$($s.daily.resetInMinutes)m  $($parts -join '; ')"
      return
    }

    # 2) 理智快满提醒（每档只提醒一次）
    if ($s.stamina -and $s.stamina.percent -ge [int]$s.reminders.staminaWarnPercent) {
      $key = "$($s.daily.gameDay)-$([Math]::Floor($s.stamina.percent / 10))"
      if ($script:schedRemindedStamina -ne $key) {
        $script:schedRemindedStamina = $key
        $unit = $s.staminaCfg.unit
        Say "$unit 快满了（$($s.stamina.value)/$($s.stamina.max)），溢出就浪费了。" '' 8000 'pout'
        Write-PetLog "schedule reminder: stamina $($s.stamina.value)/$($s.stamina.max)"
      }
    }
  } catch {
    Write-PetLog "schedule check failed: $($_.Exception.Message)"
  }
}

$script:schedTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:schedTimer.Interval = [TimeSpan]::FromMinutes(10)
$script:schedTimer.Add_Tick({ Test-ScheduleReminder })
$script:schedTimer.Start()

if ($TestAudio) {
  Write-PetLog "=== TestAudio begin ==="
  Initialize-Audio
  $caseA = '呆货。'
  $caseB = '编译过了，继续。'
  Write-PetLog "case A (含呆货，应播放): $caseA"
  Play-Daigo $caseA
  Start-Sleep -Milliseconds 300
  Write-PetLog "case B (不含呆货，不应播放): $caseB"
  Play-Daigo $caseB
  Start-Sleep -Milliseconds 300
  Write-PetLog "audioReady=$($script:audioReady)  player=$($null -ne $script:player)  soundPlayer=$($null -ne $script:soundPlayer)"
  Write-PetLog "=== TestAudio end ==="
  exit 0
}

if ($Hidden) {
  Write-PetLog 'Hidden 自检通过'
  Write-Host "自检通过：可用状态图 $($stateImages.Count) 个，状态 $($stateParams.Count) 个"
  exit 0
}

Write-PetLog "ShowDialog"
try { $win.ShowDialog() | Out-Null; Write-PetLog 'ShowDialog 正常返回' }
catch { Write-PetLog "!! ShowDialog 异常: $($_.Exception.Message)"; throw }
Write-PetLog '=== end ==='
