/*
 * git.exe for Fork under Wine: runs the user's Linux git through the fork-git script.
 *
 * Fork starts this like Git for Windows, with Windows paths in its arguments, its own variables in
 * the Windows environment and pipes as standard handles. Wine starts a Unix program from here only
 * with the environment Wine itself started with, and without these pipes, so this passes them on:
 *
 *     fork-git <stdin-fd> <stdout-fd> <stderr-fd> [NAME=VALUE...] -- <arguments>
 *
 * The fds are the Unix descriptors behind this process's standard handles (-1 if there is none);
 * the variables are Fork's GIT_*, SSH_ASKPASS* and FORK_* ones; Windows paths in the arguments,
 * alone or after "--option=" or "key=", become Unix paths. The exit code is git's.
 *
 * FORK_GIT_BRIDGE (set by the launcher) is the Unix path of fork-git.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <wctype.h>

typedef NTSTATUS (WINAPI *spawnvp_func)(char *const argv[], int wait);
typedef NTSTATUS (CDECL *handle_to_fd_func)(HANDLE handle, unsigned int access, int *fd, unsigned int *options);
typedef char *(CDECL *unix_name_func)(const WCHAR *dos);

static handle_to_fd_func handle_to_fd;
static unix_name_func unix_name;

static void fail(const char *msg)
{
    DWORD written;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), msg, strlen(msg), &written, NULL);
    ExitProcess(128);
}

static char *utf8(const WCHAR *str, int len)
{
    int size = WideCharToMultiByte(CP_UTF8, 0, str, len, NULL, 0, NULL, NULL);
    char *ret = malloc(size + 1);

    if (!ret) fail("fork git bridge: out of memory\n");
    WideCharToMultiByte(CP_UTF8, 0, str, len, ret, size, NULL, NULL);
    ret[size] = 0;
    return ret;
}

static BOOL is_dos_path(const WCHAR *str)
{
    return iswalpha(str[0]) && str[1] == ':' && (str[2] == '\\' || str[2] == '/');
}

static char *convert_arg(const WCHAR *arg)
{
    const WCHAR *path = arg, *eq = wcschr(arg, '=');
    char *prefix, *unix_path, *ret;

    if (!is_dos_path(path) && eq) path = eq + 1;
    if (!is_dos_path(path) || !(unix_path = unix_name(path))) return utf8(arg, -1);

    prefix = utf8(arg, path - arg);
    if (!(ret = malloc(strlen(prefix) + strlen(unix_path) + 1))) fail("fork git bridge: out of memory\n");
    strcpy(ret, prefix);
    strcat(ret, unix_path);
    free(prefix);
    return ret;
}

static BOOL forward_variable(const WCHAR *var)
{
    return !wcsncmp(var, L"GIT_", 4) || !wcsncmp(var, L"SSH_ASKPASS", 11) || !wcsncmp(var, L"FORK_", 5);
}

static char *std_fd(DWORD which, unsigned int access)
{
    HANDLE handle = GetStdHandle(which);
    char buf[16];
    int fd = -1;

    if (handle && handle != INVALID_HANDLE_VALUE && handle_to_fd(handle, access, &fd, NULL)) fd = -1;
    snprintf(buf, sizeof(buf), "%d", fd);
    return _strdup(buf);
}

int wmain(int argc, WCHAR **argv)
{
    HMODULE ntdll = GetModuleHandleW(L"ntdll"), kernel32 = GetModuleHandleW(L"kernel32");
    spawnvp_func spawnvp = (spawnvp_func)GetProcAddress(ntdll, "__wine_unix_spawnvp");
    const WCHAR *bridge = _wgetenv(L"FORK_GIT_BRIDGE");
    WCHAR *env, *var;
    char **unix_argv;
    int count = 0, i;
    NTSTATUS status;

    handle_to_fd = (handle_to_fd_func)GetProcAddress(ntdll, "wine_server_handle_to_fd");
    unix_name = (unix_name_func)GetProcAddress(kernel32, "wine_get_unix_file_name");
    if (!spawnvp || !handle_to_fd || !unix_name) fail("fork git bridge: this git.exe only runs under Wine\n");
    if (!bridge || !*bridge) fail("fork git bridge: FORK_GIT_BRIDGE is not set; start Fork with the fork launcher\n");

    env = GetEnvironmentStringsW();
    for (var = env; *var; var += wcslen(var) + 1) if (forward_variable(var)) count++;
    if (!(unix_argv = calloc(argc + count + 6, sizeof(*unix_argv)))) fail("fork git bridge: out of memory\n");

    unix_argv[0] = utf8(bridge, -1);
    unix_argv[1] = std_fd(STD_INPUT_HANDLE, FILE_READ_DATA);
    unix_argv[2] = std_fd(STD_OUTPUT_HANDLE, FILE_WRITE_DATA);
    unix_argv[3] = std_fd(STD_ERROR_HANDLE, FILE_WRITE_DATA);
    count = 4;
    for (var = env; *var; var += wcslen(var) + 1) if (forward_variable(var)) unix_argv[count++] = utf8(var, -1);
    unix_argv[count++] = _strdup("--");
    for (i = 1; i < argc; i++) unix_argv[count++] = convert_arg(argv[i]);
    FreeEnvironmentStringsW(env);

    /* With wait set, this returns git's exit code, or an NTSTATUS if fork-git could not be started. */
    status = spawnvp(unix_argv, 1);
    if ((ULONG)status > 255) fail("fork git bridge: cannot start fork-git (FORK_GIT_BRIDGE)\n");
    return status;
}
