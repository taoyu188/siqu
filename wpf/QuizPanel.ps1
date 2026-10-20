<#
  祀 · 今日三题（独立窗口）
  ------------------------------------------------------------------
  数据来自 core/daily.js（题库 + 间隔重复），本窗口只负责显示和交互。

  用法：
    powershell -ExecutionPolicy Bypass -File siqu\wpf\QuizPanel.ps1
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
$dailyJs = Join-Path $appRoot 'core\daily.js'
$siquHome = if ($env:SIQU_HOME) { $env:SIQU_HOME } else { Join-Path $env:USERPROFILE '.siqu' }

$brushConv = New-Object System.Windows.Media.BrushConverter
function B($hex) { $brushConv.ConvertFromString($hex) }

$win = New-Object System.Windows.Window
$win.Title = '祀 · 今日三题'
$win.Width = 640
$win.Height = 660
$win.WindowStyle = 'None'
$win.ResizeMode = 'NoResize'
$win.WindowStartupLocation = 'CenterScreen'
$win.Background = B '#14171C'
$win.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')

$root = New-Object System.Windows.Controls.Grid
$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = '40' }))
$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = '*' }))

# ---- 标题栏 ----
$titleBar = New-Object System.Windows.Controls.Border
$titleBar.Background = B '#1B1F26'
$titleBar.SetValue([System.Windows.Controls.Grid]::RowProperty, 0)
$titleInner = New-Object System.Windows.Controls.Grid
$titleText = New-Object System.Windows.Controls.TextBlock
$titleText.Text = '今日三题'
$titleText.Foreground = B '#8A93A0'
$titleText.FontSize = 12
$titleText.VerticalAlignment = 'Center'
$titleText.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
$titleInner.Children.Add($titleText) | Out-Null

$dateText = New-Object System.Windows.Controls.TextBlock
$dateText.Text = ''
$dateText.Foreground = B '#5F6874'
$dateText.FontSize = 11
$dateText.VerticalAlignment = 'Center'
$dateText.HorizontalAlignment = 'Right'
$dateText.Margin = New-Object System.Windows.Thickness(0, 0, 46, 0)
$titleInner.Children.Add($dateText) | Out-Null

$btnClose = New-Object System.Windows.Controls.Button
$btnClose.Content = '✕'
$btnClose.Width = 30
$btnClose.Height = 24
$btnClose.HorizontalAlignment = 'Right'
$btnClose.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
$btnClose.Background = B '#00000000'
$btnClose.Foreground = B '#7A838F'
$btnClose.BorderThickness = 0
$btnClose.Add_Click({ $win.Close() })
$titleInner.Children.Add($btnClose) | Out-Null

$titleBar.Child = $titleInner
$root.Children.Add($titleBar) | Out-Null

# ---- 内容区 ----
$scroll = New-Object System.Windows.Controls.ScrollViewer
$scroll.SetValue([System.Windows.Controls.Grid]::RowProperty, 1)
$scroll.VerticalScrollBarVisibility = 'Auto'
$scroll.HorizontalScrollBarVisibility = 'Disabled'
$scroll.Margin = New-Object System.Windows.Thickness(14, 10, 14, 12)

$stack = New-Object System.Windows.Controls.StackPanel
$scroll.Content = $stack
$root.Children.Add($scroll) | Out-Null
$win.Content = $root

# ---- 拉数据 ----
function Get-Today {
  $tmp = Join-Path $env:TEMP "siqu-quiz-$PID.json"
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  & node $dailyJs --today --json --out $tmp 2>$null | Out-Null
  if (-not (Test-Path $tmp)) { return $null }
  return (Get-Content $tmp -Raw -Encoding UTF8) | ConvertFrom-Json
}

function Send-Answer([string]$id, [bool]$correct) {
  $flag = if ($correct) { '--right' } else { '--wrong' }
  & node $dailyJs --answer $id $flag 2>$null | Out-Null

  # 同步影响好感度 / 心情（人格引擎）
  $personaJs = Join-Path $appRoot 'core\persona.js'
  if (Test-Path $personaJs) {
    $ev = if ($correct) { 'quiz-right' } else { 'quiz-wrong' }
    & node $personaJs --event $ev 2>$null | Out-Null
  }
}

# ---- 编程题卡片 ----
function New-CodeCard($q, [int]$index) {
  $card = New-Object System.Windows.Controls.Border
  $card.Background = B '#1A1E24'
  $card.CornerRadius = New-Object System.Windows.CornerRadius(10)
  $card.Padding = New-Object System.Windows.Thickness(14, 12, 14, 12)
  $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

  $sp = New-Object System.Windows.Controls.StackPanel

  $head = New-Object System.Windows.Controls.Grid
  $topic = New-Object System.Windows.Controls.TextBlock
  $topic.Text = "$index.  [编程题 · $($q.topic)]"
  $topic.Foreground = B '#E0C08A'
  $topic.FontSize = 11
  $head.Children.Add($topic) | Out-Null
  $status = New-Object System.Windows.Controls.TextBlock
  $status.HorizontalAlignment = 'Right'
  $status.FontSize = 11
  if ($q.answered -eq 'right') { $status.Text = '做出来了'; $status.Foreground = B '#6FC08A' }
  elseif ($q.answered -eq 'wrong') { $status.Text = '待复习'; $status.Foreground = B '#D98C8C' }
  else { $status.Text = '未作答'; $status.Foreground = B '#5F6874' }
  $head.Children.Add($status) | Out-Null
  $sp.Children.Add($head) | Out-Null

  if ($q.title) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $q.title
    $t.Foreground = B '#E6EAF0'
    $t.FontSize = 14
    $t.FontWeight = 'SemiBold'
    $t.Margin = New-Object System.Windows.Thickness(0, 8, 0, 4)
    $sp.Children.Add($t) | Out-Null
  }

  $st = New-Object System.Windows.Controls.TextBlock
  $st.Text = $q.statement
  $st.Foreground = B '#C9D1DB'
  $st.FontSize = 12
  $st.TextWrapping = 'Wrap'
  $st.LineHeight = 20
  $sp.Children.Add($st) | Out-Null

  $ioBox = New-Object System.Windows.Controls.Border
  $ioBox.Background = B '#14171C'
  $ioBox.CornerRadius = New-Object System.Windows.CornerRadius(6)
  $ioBox.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
  $ioBox.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
  $ioText = New-Object System.Windows.Controls.TextBlock
  $ioText.Text = $q.io
  $ioText.Foreground = B '#9FB3C8'
  $ioText.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
  $ioText.FontSize = 11
  $ioText.TextWrapping = 'Wrap'
  $ioBox.Child = $ioText
  $sp.Children.Add($ioBox) | Out-Null

  $solBox = New-Object System.Windows.Controls.Border
  $solBox.Background = B '#12161B'
  $solBox.CornerRadius = New-Object System.Windows.CornerRadius(6)
  $solBox.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
  $solBox.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
  $solBox.Visibility = 'Collapsed'
  $solSp = New-Object System.Windows.Controls.StackPanel
  $solTitle = New-Object System.Windows.Controls.TextBlock
  $solTitle.Text = '参考答案'
  $solTitle.Foreground = B '#6FC08A'
  $solTitle.FontSize = 11
  $solSp.Children.Add($solTitle) | Out-Null
  $solText = New-Object System.Windows.Controls.TextBlock
  $solText.Text = $q.solution
  $solText.Foreground = B '#A8C0D0'
  $solText.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
  $solText.FontSize = 11
  $solText.TextWrapping = 'Wrap'
  $solText.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
  $solSp.Children.Add($solText) | Out-Null
  if ($q.explain) {
    $ex = New-Object System.Windows.Controls.TextBlock
    $ex.Text = "要点：$($q.explain)"
    $ex.Foreground = B '#7A838F'
    $ex.FontSize = 11
    $ex.TextWrapping = 'Wrap'
    $ex.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
    $solSp.Children.Add($ex) | Out-Null
  }
  $solBox.Child = $solSp
  $sp.Children.Add($solBox) | Out-Null

  $actions = New-Object System.Windows.Controls.StackPanel
  $actions.Orientation = 'Horizontal'
  $actions.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)

  $btnShow = New-Object System.Windows.Controls.Button
  $btnShow.Content = '看参考答案'
  $btnShow.Width = 92
  $btnShow.Height = 26
  $btnShow.Background = B '#232830'
  $btnShow.Foreground = B '#C9D1DB'
  $btnShow.BorderThickness = 0
  $btnShow.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
  $btnShow.Cursor = [System.Windows.Input.Cursors]::Hand
  $btnShow.Add_Click({ $solBox.Visibility = 'Visible' }.GetNewClosure())
  $actions.Children.Add($btnShow) | Out-Null

  $btnRight = New-Object System.Windows.Controls.Button
  $btnRight.Content = '我做出来了'
  $btnRight.Width = 96
  $btnRight.Height = 26
  $btnRight.Background = B '#1E2A22'
  $btnRight.Foreground = B '#6FC08A'
  $btnRight.BorderThickness = 0
  $btnRight.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
  $btnRight.Cursor = [System.Windows.Input.Cursors]::Hand
  $btnRight.Add_Click({ Send-Answer $q.id $true; Refresh-All }.GetNewClosure())
  $actions.Children.Add($btnRight) | Out-Null

  $btnWrong = New-Object System.Windows.Controls.Button
  $btnWrong.Content = '没做出'
  $btnWrong.Width = 80
  $btnWrong.Height = 26
  $btnWrong.Background = B '#2A1E22'
  $btnWrong.Foreground = B '#D98C8C'
  $btnWrong.BorderThickness = 0
  $btnWrong.Cursor = [System.Windows.Input.Cursors]::Hand
  $btnWrong.Add_Click({ Send-Answer $q.id $false; Refresh-All }.GetNewClosure())
  $actions.Children.Add($btnWrong) | Out-Null

  $sp.Children.Add($actions) | Out-Null
  $card.Child = $sp
  return $card
}

# ---- 渲染一张卡片 ----
function New-Card($q, [int]$index) {
  if ("$($q.type)" -eq 'code') { return New-CodeCard $q $index }
  $card = New-Object System.Windows.Controls.Border
  $card.Background = B '#1A1E24'
  $card.CornerRadius = New-Object System.Windows.CornerRadius(10)
  $card.Padding = New-Object System.Windows.Thickness(14, 12, 14, 12)
  $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

  $sp = New-Object System.Windows.Controls.StackPanel

  # 头部：序号 + 主题 + 状态
  $head = New-Object System.Windows.Controls.Grid
  $topic = New-Object System.Windows.Controls.TextBlock
  $topic.Text = "$index.  [$($q.topic)]"
  $topic.Foreground = B '#7FB4A0'
  $topic.FontSize = 11
  $head.Children.Add($topic) | Out-Null

  $status = New-Object System.Windows.Controls.TextBlock
  $status.HorizontalAlignment = 'Right'
  $status.FontSize = 11
  if ($q.answered -eq 'right') { $status.Text = '已会'; $status.Foreground = B '#6FC08A' }
  elseif ($q.answered -eq 'wrong') { $status.Text = '待复习'; $status.Foreground = B '#D98C8C' }
  else { $status.Text = '未作答'; $status.Foreground = B '#5F6874' }
  $head.Children.Add($status) | Out-Null
  $sp.Children.Add($head) | Out-Null

  # 题干
  $qt = New-Object System.Windows.Controls.TextBlock
  $qt.Text = $q.q
  $qt.Foreground = B '#E6EAF0'
  $qt.FontSize = 13
  $qt.TextWrapping = 'Wrap'
  $qt.Margin = New-Object System.Windows.Thickness(0, 8, 0, 8)
  $sp.Children.Add($qt) | Out-Null

  # 选项
  $optButtons = @()
  for ($k = 0; $k -lt $q.options.Count; $k++) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = "$([char](65 + $k)). $($q.options[$k])"
    $b.HorizontalContentAlignment = 'Left'
    $b.Padding = New-Object System.Windows.Thickness(10, 5, 10, 5)
    $b.Margin = New-Object System.Windows.Thickness(0, 2, 0, 2)
    $b.Background = B '#232830'
    $b.Foreground = B '#C9D1DB'
    $b.BorderThickness = 0
    $b.FontSize = 12
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Tag = $k
    $optButtons += $b
    $sp.Children.Add($b) | Out-Null
  }

  # 答案区（默认隐藏）
  $answerBox = New-Object System.Windows.Controls.TextBlock
  $answerBox.Visibility = 'Collapsed'
  $answerBox.TextWrapping = 'Wrap'
  $answerBox.FontSize = 12
  $answerBox.Foreground = B '#9FB3C8'
  $answerBox.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
  $answerBox.Text = "答案：$([char](65 + $q.answer))　$($q.explain)"
  $sp.Children.Add($answerBox) | Out-Null

  # 操作行
  $actions = New-Object System.Windows.Controls.StackPanel
  $actions.Orientation = 'Horizontal'
  $actions.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)

  $reveal = New-Object System.Windows.Controls.Button
  $reveal.Content = '看答案'
  $reveal.Width = 70
  $reveal.Height = 26
  $reveal.Background = B '#232830'
  $reveal.Foreground = B '#C9D1DB'
  $reveal.BorderThickness = 0
  $reveal.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
  $reveal.Cursor = [System.Windows.Input.Cursors]::Hand
  $reveal.Add_Click({
    $answerBox.Visibility = 'Visible'
  }.GetNewClosure())
  $actions.Children.Add($reveal) | Out-Null

  $btnRight = New-Object System.Windows.Controls.Button
  $btnRight.Content = '我会'
  $btnRight.Width = 70
  $btnRight.Height = 26
  $btnRight.Background = B '#1E2A22'
  $btnRight.Foreground = B '#6FC08A'
  $btnRight.BorderThickness = 0
  $btnRight.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
  $btnRight.Cursor = [System.Windows.Input.Cursors]::Hand
  $actions.Children.Add($btnRight) | Out-Null

  $btnWrong = New-Object System.Windows.Controls.Button
  $btnWrong.Content = '不会'
  $btnWrong.Width = 70
  $btnWrong.Height = 26
  $btnWrong.Background = B '#2A1E22'
  $btnWrong.Foreground = B '#D98C8C'
  $btnWrong.BorderThickness = 0
  $btnWrong.Cursor = [System.Windows.Input.Cursors]::Hand
  $actions.Children.Add($btnWrong) | Out-Null

  $sp.Children.Add($actions) | Out-Null
  $card.Child = $sp

  # 选项点击：高亮选中
  foreach ($b in $optButtons) {
    $b.Add_Click({
      param($s, $e)
      $idx = [int]$s.Tag
      $isRight = ($idx -eq $q.answer)
      foreach ($ob in $optButtons) {
        if ([int]$ob.Tag -eq $q.answer) { $ob.Background = B '#1E2A22'; $ob.Foreground = B '#6FC08A' }
        elseif ([int]$ob.Tag -eq $idx -and -not $isRight) { $ob.Background = B '#2A1E22'; $ob.Foreground = B '#D98C8C' }
      }
      $answerBox.Visibility = 'Visible'
    }.GetNewClosure())
  }

  $btnRight.Add_Click({
    Send-Answer $q.id $true
    Refresh-All
  }.GetNewClosure())
  $btnWrong.Add_Click({
    Send-Answer $q.id $false
    Refresh-All
  }.GetNewClosure())

  return $card
}

function Refresh-All {
  $stack.Children.Clear()
  $data = Get-Today
  if (-not $data) {
    $err = New-Object System.Windows.Controls.TextBlock
    $err.Text = '读不到题库。检查 core/questions.json 和 node 是否可用。'
    $err.Foreground = B '#D98C8C'
    $err.FontSize = 12
    $stack.Children.Add($err) | Out-Null
    return
  }
  $dateText.Text = "$($data.date)　已完成 $($data.done)/$($data.total)"

  $i = 0
  foreach ($q in $data.questions) {
    $i++
    $stack.Children.Add((New-Card $q $i)) | Out-Null
  }

  $stat = & node $dailyJs --stats 2>$null
  $footer = New-Object System.Windows.Controls.TextBlock
  $footer.Text = "$stat"
  $footer.Foreground = B '#5F6874'
  $footer.FontSize = 11
  $footer.Margin = New-Object System.Windows.Thickness(2, 4, 0, 0)
  $stack.Children.Add($footer) | Out-Null
}

$titleBar.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$win.Add_Loaded({ Refresh-All })

if ($RenderTo) {
  Refresh-All
  $w = 640; $h = 660
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
