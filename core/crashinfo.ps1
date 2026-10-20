<#
  崩溃信息解析（独立模块，桌宠和测试脚本都用它）
  ------------------------------------------------------------------
  数据来源：Windows 事件日志 → Application → Provider "Application Error"
  程序异常终止时系统会写一条，里面有 exe 名和异常代码。
  好处：零侵入——不需要改 Dev-C++、不需要包装 exe、不需要管理员权限。
#>

# 异常代码 → 人话 + 她的台词
$script:CrashMap = @{
  '0xc0000005' = @{
    title = '访问了不该访问的内存'
    why   = '空指针、数组越界、或者用了已经释放的内存。C 不会帮你检查，写越界了也照跑。'
    fix   = '先看数组下标有没有超过声明的大小；再看指针用之前是不是 NULL。'
    taunt = '越界了，你这个笨蛋。'
  }
  '0xc0000094' = @{
    title = '整数除以零'
    why   = '除数在运行时变成了 0。编译期不会报，跑起来就直接崩。'
    fix   = '除法之前先判断除数 != 0。'
    taunt = '除以零？你数学谁教的。'
  }
  '0xc00000fd' = @{
    title = '栈溢出（多半是递归没停）'
    why   = '递归缺少终止条件，或者每层开了太大的局部数组，把栈耗尽了。'
    fix   = '检查递归的边界条件；大数组改成全局或 malloc。'
    taunt = '递归停不下来了吧。'
  }
  '0xc0000409' = @{
    title = '栈缓冲区溢出'
    why   = '往数组里写的数据超过了它的容量，踩坏了栈上的返回地址。'
    fix   = '检查 strcpy/scanf/循环赋值的边界，留出结束符的位置。'
    taunt = '写超了。数组多大你心里没数？'
  }
  '0xc0000374' = @{
    title = '堆内存被破坏'
    why   = 'malloc 出来的空间写越界了，或者 free 了两次。'
    fix   = '确认 malloc 的大小、free 只调一次、free 之后别再访问。'
    taunt = '内存被你踩坏了。'
  }
  '0xc000001d' = @{
    title = '非法指令'
    why   = '通常是把函数指针指到了无效地址，或者调用了一个没有实现的函数。'
    fix   = '检查函数指针是否正确赋值。'
    taunt = '你指到哪儿去了。'
  }
  '0xc000013a' = @{
    title = '程序被强制中断'
    why   = '按了 Ctrl+C，或者从任务管理器结束了进程。'
    fix   = '这不是 bug。'
    taunt = '……你自己关的。'
  }
}

# 从事件 Message 里抽 exe 名和异常码（兼容中英文系统）
function Parse-CrashEvent {
  param($Event)

  $msg = "$($Event.Message)"
  $exe = ''
  $code = ''

  $m1 = [regex]::Match($msg, '(?:出错应用程序名称|Faulting application name)[：:]\s*([^，,\r\n]+)')
  if ($m1.Success) { $exe = $m1.Groups[1].Value.Trim() }

  $m2 = [regex]::Match($msg, '(?:异常代码|Exception code)[：:]\s*(0x[0-9a-fA-F]+)')
  if ($m2.Success) { $code = $m2.Groups[1].Value.ToLower() }

  $info = $script:CrashMap[$code]
  if (-not $info) {
    $info = @{
      title = '程序异常终止'
      why   = "异常代码 $code，这个我没见过。"
      fix   = '把这个代码发给我，我加进规则库。'
      taunt = '崩了。……又崩了。'
    }
  }

  return [pscustomobject]@{
    Exe      = $exe
    Code     = $code
    Title    = $info.title
    Why      = $info.why
    Fix      = $info.fix
    Taunt    = $info.taunt
    Time     = $Event.TimeCreated
    RecordId = $Event.RecordId
  }
}

# 取最近的崩溃事件（最多 N 条，按时间倒序）
function Get-RecentCrashEvents {
  param([int]$Max = 5)
  try {
    return Get-WinEvent -FilterHashtable @{
      LogName      = 'Application'
      ProviderName = 'Application Error'
    } -MaxEvents $Max -ErrorAction Stop
  } catch {
    return @()
  }
}

# 只返回 RecordId 比 $SinceId 新的崩溃（按时间正序，先发生的先说）
function Get-NewCrashes {
  param([long]$SinceId = 0)
  $out = @()
  foreach ($e in (Get-RecentCrashEvents -Max 5)) {
    if ($e.RecordId -le $SinceId) { continue }
    $out += Parse-CrashEvent -Event $e
  }
  return ($out | Sort-Object RecordId)
}
