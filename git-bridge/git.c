/*
 * git.exe for Fork under Wine: runs the user's Linux git through the fork-git script.
 *
 * Fork starts this like Git for Windows, with Windows paths in its arguments, its own variables in
 * the Windows environment and pipes as standard handles. Wine starts a Unix program from here only
 * with the environment Wine itself started with, and without these handles, so this passes them on:
 *
 *     fork-git <stdin-fd> <stdout-fd> <stderr-fd> [NAME=VALUE...] -- <arguments>
 *
 * The fds stand for this process's standard handles (-1 if there is none). A handle with a Unix
 * descriptor behind it (a terminal, a file) is passed as it is. Wine's pipes, which Fork uses, live
 * in wineserver and have none (STATUS_BAD_DEVICE_TYPE), so for those git gets one end of a loopback
 * socket pair (Wine's sockets are Unix sockets) and a thread here copies between the other end and
 * the pipe. The variables are Fork's GIT_*, SSH_ASKPASS* and FORK_* ones; Windows paths in the
 * arguments, alone or after "--option=" or "key=", become Unix paths. The exit code is git's.
 *
 * FORK_GIT_BRIDGE (set by the launcher) is the Unix path of fork-git.
 */
#include <winsock2.h>
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

struct stream
{
    BOOL input;           /* data flows from the handle to git */
    HANDLE handle;        /* this process's standard handle */
    SOCKET mine, theirs;  /* the socket pair, when relaying */
    HANDLE thread;
    int fd;               /* passed to fork-git */
};

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

/* A connected pair of loopback TCP sockets. Only the connection from *theirs is accepted. */
static BOOL socket_pair(SOCKET *mine, SOCKET *theirs)
{
    struct sockaddr_in addr = { 0 }, local, peer;
    int len = sizeof(addr);
    SOCKET listener;

    *mine = *theirs = INVALID_SOCKET;
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if ((listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)) == INVALID_SOCKET) return FALSE;
    if (bind(listener, (struct sockaddr *)&addr, sizeof(addr)) || listen(listener, 1)
        || getsockname(listener, (struct sockaddr *)&addr, &len)) goto failed;
    if ((*theirs = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)) == INVALID_SOCKET
        || connect(*theirs, (struct sockaddr *)&addr, sizeof(addr))) goto failed;
    len = sizeof(local);
    if (getsockname(*theirs, (struct sockaddr *)&local, &len)) goto failed;
    for (;;)
    {
        len = sizeof(peer);
        if ((*mine = accept(listener, (struct sockaddr *)&peer, &len)) == INVALID_SOCKET) goto failed;
        if (peer.sin_port == local.sin_port && peer.sin_addr.s_addr == local.sin_addr.s_addr) break;
        closesocket(*mine);
    }
    closesocket(listener);
    return TRUE;

failed:
    closesocket(listener);
    if (*theirs != INVALID_SOCKET) closesocket(*theirs);
    *theirs = INVALID_SOCKET;
    return FALSE;
}

static DWORD WINAPI copy_to_git(void *arg)
{
    struct stream *stream = arg;
    char buf[65536];
    DWORD count;
    int sent, ret;

    while (ReadFile(stream->handle, buf, sizeof(buf), &count, NULL) && count)
    {
        for (sent = 0; sent < count; sent += ret)
            if ((ret = send(stream->mine, buf + sent, count - sent, 0)) <= 0) goto done;
    }
done:
    shutdown(stream->mine, SD_SEND);
    return 0;
}

static DWORD WINAPI copy_from_git(void *arg)
{
    struct stream *stream = arg;
    char buf[65536];
    BOOL writing = TRUE;
    DWORD written;
    int count;

    /* Keep reading after Fork stops listening, so git never blocks on a full socket. */
    while ((count = recv(stream->mine, buf, sizeof(buf), 0)) > 0)
        if (writing) writing = WriteFile(stream->handle, buf, count, &written, NULL);
    return 0;
}

static void open_stream(struct stream *stream, DWORD which, BOOL input)
{
    stream->input = input;
    stream->handle = GetStdHandle(which);
    stream->mine = stream->theirs = INVALID_SOCKET;
    stream->thread = NULL;
    stream->fd = -1;
    if (!stream->handle || stream->handle == INVALID_HANDLE_VALUE) return;
    if (!handle_to_fd(stream->handle, input ? FILE_READ_DATA : FILE_WRITE_DATA, &stream->fd, NULL)) return;

    stream->fd = -1;
    if (!socket_pair(&stream->mine, &stream->theirs)) return;
    if (handle_to_fd((HANDLE)stream->theirs, FILE_READ_DATA | FILE_WRITE_DATA, &stream->fd, NULL))
    {
        stream->fd = -1;
        return;
    }
    stream->thread = CreateThread(NULL, 0, input ? copy_to_git : copy_from_git, stream, 0, NULL);
}

static char *fd_arg(int fd)
{
    char buf[16];

    snprintf(buf, sizeof(buf), "%d", fd);
    return _strdup(buf);
}

int wmain(int argc, WCHAR **argv)
{
    HMODULE ntdll = GetModuleHandleW(L"ntdll"), kernel32 = GetModuleHandleW(L"kernel32");
    spawnvp_func spawnvp = (spawnvp_func)GetProcAddress(ntdll, "__wine_unix_spawnvp");
    const WCHAR *bridge = _wgetenv(L"FORK_GIT_BRIDGE");
    struct stream streams[3];
    WSADATA wsa;
    WCHAR *env, *var;
    char **unix_argv;
    int count = 0, i;
    NTSTATUS status;

    handle_to_fd = (handle_to_fd_func)GetProcAddress(ntdll, "wine_server_handle_to_fd");
    unix_name = (unix_name_func)GetProcAddress(kernel32, "wine_get_unix_file_name");
    if (!spawnvp || !handle_to_fd || !unix_name) fail("fork git bridge: this git.exe only runs under Wine\n");
    if (!bridge || !*bridge) fail("fork git bridge: FORK_GIT_BRIDGE is not set; start Fork with the fork launcher\n");
    if (WSAStartup(MAKEWORD(2, 2), &wsa)) fail("fork git bridge: cannot initialize Winsock\n");

    open_stream(&streams[0], STD_INPUT_HANDLE, TRUE);
    open_stream(&streams[1], STD_OUTPUT_HANDLE, FALSE);
    open_stream(&streams[2], STD_ERROR_HANDLE, FALSE);

    env = GetEnvironmentStringsW();
    for (var = env; *var; var += wcslen(var) + 1) if (forward_variable(var)) count++;
    if (!(unix_argv = calloc(argc + count + 6, sizeof(*unix_argv)))) fail("fork git bridge: out of memory\n");

    unix_argv[0] = utf8(bridge, -1);
    for (i = 0; i < 3; i++) unix_argv[i + 1] = fd_arg(streams[i].fd);
    count = 4;
    for (var = env; *var; var += wcslen(var) + 1) if (forward_variable(var)) unix_argv[count++] = utf8(var, -1);
    unix_argv[count++] = _strdup("--");
    for (i = 1; i < argc; i++) unix_argv[count++] = convert_arg(argv[i]);
    FreeEnvironmentStringsW(env);

    /* With wait set, this returns git's exit code, or an NTSTATUS if fork-git could not be started. */
    status = spawnvp(unix_argv, 1);

    /* git has exited: end its side of the output sockets (shutdown reaches every copy of the fd, also
     * the one Wine keeps here), so the copies drain what git wrote and finish. */
    for (i = 1; i < 3; i++)
    {
        if (!streams[i].thread) continue;
        shutdown(streams[i].theirs, SD_SEND);
        WaitForSingleObject(streams[i].thread, INFINITE);
    }

    if ((ULONG)status > 255) fail("fork git bridge: cannot start fork-git (FORK_GIT_BRIDGE)\n");
    return status;
}
