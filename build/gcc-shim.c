/*
 * gcc-shim.exe —— 编译器包装器
 * ==================================================================
 * 作用：Dev-C++ / VS Code / CMake 把 gcc 路径指向本程序，
 *       本程序再去调用真正的 gcc，并做两件事：
 *         1) 把编译器的 stderr 原样转发给 IDE（行为完全不变）
 *         2) 同一份内容追加到日志，供桌宠读取诊断
 *
 * 不经过 cmd.exe，所以不存在引号转义问题；命令行用
 * GetCommandLineW 原样取回，只替换掉程序名部分。
 *
 * 环境变量：
 *   SIQU_REAL_GCC  真正的 gcc 路径（默认依次找 Dev-C++ / MinGW）
 *   SIQU_LOG       日志路径（默认 %USERPROFILE%\.siqu\build.log）
 *
 * 编译：
 *   gcc gcc-shim.c -o gcc-shim.exe -O2
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define MAX_BUF (512 * 1024)   /* 日志里最多保留 512KB 的编译器输出 */

static void fail(const wchar_t *msg, DWORD code) {
    fwprintf(stderr, L"[siqu] %ls (error %lu)\n", msg, code);
}

/* 跳过命令行里的第一个 token（即本程序路径，可能带引号） */
static wchar_t *skip_program(wchar_t *cl) {
    wchar_t *p = cl;
    while (*p == L' ' || *p == L'\t') p++;
    if (*p == L'"') {
        p++;
        while (*p && *p != L'"') p++;
        if (*p == L'"') p++;
    } else {
        while (*p && *p != L' ' && *p != L'\t') p++;
    }
    while (*p == L' ' || *p == L'\t') p++;
    return p;
}

static void resolve_gcc(wchar_t *out, size_t cch) {
    DWORD n = GetEnvironmentVariableW(L"SIQU_REAL_GCC", out, (DWORD)cch);
    if (n > 0 && n < cch && GetFileAttributesW(out) != INVALID_FILE_ATTRIBUTES) return;

    const wchar_t *cands[] = {
        L"D:\\Dev-Cpp\\MinGW64\\bin\\gcc.exe",
        L"D:\\min\\mingw64\\bin\\gcc.exe",
        L"C:\\Program Files\\Dev-Cpp\\MinGW64\\bin\\gcc.exe",
        L"C:\\MinGW\\bin\\gcc.exe",
    };
    for (int i = 0; i < 4; i++) {
        if (GetFileAttributesW(cands[i]) != INVALID_FILE_ATTRIBUTES) {
            wcsncpy(out, cands[i], cch - 1);
            out[cch - 1] = 0;
            return;
        }
    }
    out[0] = 0;
}

static void resolve_log(wchar_t *out, size_t cch) {
    DWORD n = GetEnvironmentVariableW(L"SIQU_LOG", out, (DWORD)cch);
    if (n > 0 && n < cch) return;

    wchar_t home[MAX_PATH];
    DWORD m = GetEnvironmentVariableW(L"USERPROFILE", home, MAX_PATH);
    if (m == 0 || m >= MAX_PATH) {
        wcsncpy(out, L".siqu\\build.log", cch - 1);
        out[cch - 1] = 0;
        return;
    }
    _snwprintf(out, cch, L"%ls\\.siqu\\build.log", home);
    out[cch - 1] = 0;
}

static void ensure_parent_dir(const wchar_t *file) {
    wchar_t dir[MAX_PATH * 2];
    wcsncpy(dir, file, MAX_PATH * 2 - 1);
    dir[MAX_PATH * 2 - 1] = 0;
    wchar_t *slash = wcsrchr(dir, L'\\');
    if (!slash) return;
    *slash = 0;
    for (wchar_t *p = dir + 3; *p; p++) {
        if (*p == L'\\') {
            *p = 0;
            CreateDirectoryW(dir, NULL);
            *p = L'\\';
        }
    }
    CreateDirectoryW(dir, NULL);
}

int main(void) {
    wchar_t gcc[MAX_PATH];
    resolve_gcc(gcc, MAX_PATH);
    if (!gcc[0]) {
        fail(L"找不到真正的 gcc，请设置 SIQU_REAL_GCC", 9009);
        return 9009;
    }

    /* 用原始命令行，只把程序名换成真 gcc：参数一个字都不改 */
    wchar_t *orig = GetCommandLineW();
    wchar_t *args = skip_program(orig);

    /*
     * 附加编译参数：Dev-C++ 4.9.2 默认是 gnu90，for(int i...) 会直接报错；
     * 默认又不开 -Wall，scanf 忘 & 这类会静默通过。这里统一补上。
     * - 用户在 IDE 里自己写了 -std= 就不插手
     * - 可以用 SIQU_EXTRA_FLAGS 覆盖（设为空字符串则完全不加）
     */
    wchar_t extra[512] = L"-std=gnu99 -Wall";
    DWORD en = GetEnvironmentVariableW(L"SIQU_EXTRA_FLAGS", extra, 512);
    if (en > 0 && en < 512) { /* 用了环境变量的值 */ }
    else if (en >= 512) { extra[0] = 0; }
    if (wcsstr(args, L"-std=") != NULL || wcsstr(args, L"SIQU_NO_EXTRA") != NULL) {
        extra[0] = 0;
    }

    /*
     * "查询类" 调用（IDE 启动时会用它们探测编译器版本）。
     * 这类调用：不要注入参数，也不要写日志——否则桌宠会对着
     * "gcc -dumpversion" 弹一句 "编译过了"，很吵。
     */
    int is_query = (wcsstr(args, L"-dumpversion") != NULL)
                || (wcsstr(args, L"-dumpmachine") != NULL)
                || (wcsstr(args, L"--version") != NULL)
                || (wcsstr(args, L"-print-") != NULL);
    if (is_query) extra[0] = 0;

    size_t need = wcslen(gcc) + wcslen(extra) + wcslen(args) + 16;
    wchar_t *cmd = (wchar_t *)malloc(need * sizeof(wchar_t));
    if (!cmd) return 9009;
    if (extra[0]) _snwprintf(cmd, need, L"\"%ls\" %ls %ls", gcc, extra, args);
    else          _snwprintf(cmd, need, L"\"%ls\" %ls", gcc, args);
    cmd[need - 1] = 0;

    /* stderr 走管道，我们自己转发 */
    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle = TRUE;

    HANDLE rd = NULL, wr = NULL;
    if (!CreatePipe(&rd, &wr, &sa, 0)) {
        fail(L"CreatePipe 失败", GetLastError());
        free(cmd);
        return 9009;
    }
    SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = wr;

    BOOL ok = CreateProcessW(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
    free(cmd);
    CloseHandle(wr);
    if (!ok) {
        DWORD e = GetLastError();
        CloseHandle(rd);
        fail(L"启动 gcc 失败", e);
        return 9009;
    }

    /* 边转发边攒日志 */
    char *buf = (char *)malloc(MAX_BUF);
    size_t len = 0;
    HANDLE hErr = GetStdHandle(STD_ERROR_HANDLE);
    char chunk[8192];
    DWORD got = 0;
    while (ReadFile(rd, chunk, sizeof(chunk), &got, NULL) && got > 0) {
        DWORD wrote = 0;
        WriteFile(hErr, chunk, got, &wrote, NULL);
        if (buf && len + got < MAX_BUF) {
            memcpy(buf + len, chunk, got);
            len += got;
        }
    }
    CloseHandle(rd);
    WaitForSingleObject(pi.hProcess, INFINITE);

    DWORD code = 9009;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    /*
     * 落日志的条件：
     *   - 查询类调用（--version / -dumpversion）不记，避免桌宠乱弹
     *   - 有源码（.c / .cpp）的编译记录
     *   - 任何失败的调用（含链接错误，这时候参数里只有 .o 没有 .c）
     */
    int has_source = (wcsstr(args, L".c") != NULL) || (wcsstr(args, L".C") != NULL);
    if (!is_query && (code != 0 || has_source)) {
        wchar_t logPath[MAX_PATH * 2];
        resolve_log(logPath, MAX_PATH * 2);
        ensure_parent_dir(logPath);

        FILE *f = _wfopen(logPath, L"ab");
        if (f) {
            SYSTEMTIME st;
            GetLocalTime(&st);
            fprintf(f, "=== seq=%lu exit=%lu at=%04d-%02d-%02d %02d:%02d:%02d args=%ls\n",
                    (unsigned long)(GetTickCount() & 0xFFFFF), (unsigned long)code,
                    st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, args);
            if (buf && len) fwrite(buf, 1, len, f);
            if (len == 0 || buf[len - 1] != '\n') fputc('\n', f);
            fputs("---\n", f);
            fclose(f);
        }
    }
    free(buf);
    return (int)code;
}
