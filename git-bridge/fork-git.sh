# fork-git: the Linux side of Fork's git bridge. git.exe in the Wine prefix runs it as
#
#     fork-git <stdin-fd> <stdout-fd> <stderr-fd> [NAME=VALUE...] -- <git arguments>
#
# with the Unix fds behind its standard handles and the variables Fork set for git (see git.c), and
# this runs the user's own git with them, so git reads the user's configuration, credential helpers
# and ssh setup as it does on the command line.
#
# The launcher sets FORK_LINUX_GIT (git to run), FORK_WINE (to run Fork's Windows helpers),
# FORK_GIT_HELPERS (a directory for the wrappers around them) and, for debugging, FORK_GIT_TRACE
# (a file that logs each call). Everything else comes from the user's PATH, as git's own helpers,
# hooks and ssh do.

# Make git.exe's standard handles ours. fds that Wine hands out without close-on-exec are inherited;
# the others are reopened through /proc from git.exe, which waits for us.
fds=""
reopen() {
  local target=$1 fd=$2 mode=$3
  if [ "$fd" -lt 0 ]; then
    fds+=" $target:none"
  elif { true >&"$fd"; } 2>/dev/null; then
    eval "exec $target$mode&$fd $fd>&-"
    fds+=" $target:$fd"
  elif [ "$mode" = '<' ]; then
    eval "exec $target<\"/proc/$PPID/fd/$fd\""
    fds+=" $target:$fd(proc)"
  else
    eval "exec $target>>\"/proc/$PPID/fd/$fd\""
    fds+=" $target:$fd(proc)"
  fi
}
reopen 0 "$1" '<'
reopen 1 "$2" '>'
reopen 2 "$3" '>'
shift 3

# A command that runs a Windows program: "C:\...\x.exe" or /unix/path/x.exe, maybe quoted, maybe with
# arguments.
is_windows_program() {
  [[ $1 =~ ^\"?[^\"]*\.[Ee][Xx][Ee](\"|[[:space:]]|$) ]]
}

# Wrap a Windows program Fork hands git (its askpass and editors) in a script that runs it on Wine,
# converting file arguments to Windows paths. Prints the wrapper's path.
windows_helper() {
  local command=$1 exe rest wrapper
  [[ $command =~ ^\"?([^\"]*\.[Ee][Xx][Ee])\"?(.*)$ ]]
  exe=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
  wrapper="$FORK_GIT_HELPERS/$(printf '%s' "$command" | sha1sum | cut -c1-16)"
  if [ ! -x "$wrapper" ]; then
    mkdir -p "$FORK_GIT_HELPERS"
    # shellcheck disable=SC2016  # the expansions are the wrapper's own
    {
      printf '#!/usr/bin/env bash\n# %s\n' "$command"
      printf 'args=()\nfor arg in "$@"; do\n'
      printf '  if [ -e "$arg" ]; then args+=("$(winepath -w "$arg")"); else args+=("$arg"); fi\n'
      printf 'done\n'
      printf 'exec %q %q%s "${args[@]}"\n' "$FORK_WINE" "$exe" "$rest"
    } > "$wrapper.tmp"
    chmod 755 "$wrapper.tmp"
    mv -f "$wrapper.tmp" "$wrapper"
  fi
  printf '%s' "$wrapper"
}

is_windows_path() {
  [[ $1 =~ ^\"?[A-Za-z]:[\\/] ]]
}

vars=()
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
  name=${1%%=*} value=${1#*=}
  case "$name" in
    # Fork points this at the configuration of the Git for Windows it bundles (core.autocrlf=true,
    # its credential manager); the user's /etc/gitconfig applies instead.
    GIT_CONFIG_SYSTEM) ;;
    GIT_ASKPASS|SSH_ASKPASS|GIT_EDITOR|GIT_SEQUENCE_EDITOR)
      if is_windows_program "$value"; then vars+=("$name=$(windows_helper "$value")"); else vars+=("$1"); fi ;;
    # Any other Windows path for git (GIT_SSH, ...) would point Linux git at a Windows program.
    GIT_*) is_windows_path "$value" || vars+=("$1") ;;
    *) vars+=("$1") ;;
  esac
  shift
done
shift

# Find the git subcommand after the global options. Fork passes its rebase editor among them as
# configuration (-c sequence.editor=..., -c core.editor=...); wrap Windows programs there too.
subcommand="" args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      [ "$#" -gt 1 ] || break
      if is_windows_program "${2#*=}"; then args+=(-c "${2%%=*}=$(windows_helper "${2#*=}")"); else args+=(-c "$2"); fi
      shift 2 ;;
    -C|--git-dir|--work-tree|--namespace|--exec-path|--config-env)
      args+=("$1"); shift; [ "$#" -gt 0 ] && { args+=("$1"); shift; } ;;
    -*) args+=("$1"); shift ;;
    *) subcommand=$1; break ;;
  esac
done
set -- "${args[@]}" "$@"

if [ -n "${FORK_GIT_TRACE:-}" ]; then
  { printf '%s %s:' "$(date +%T.%3N)" "$PWD"; printf ' [%s]' "$@"; printf '\n  fds:%s\n  env:' "$fds"; printf ' %s' "${vars[@]}"; printf '\n'; } >> "$FORK_GIT_TRACE"
fi

# Fork expects Windows paths where git prints absolute paths; "/" is Wine's drive Z:.
to_windows=""
case "$subcommand" in
  rev-parse)
    case " $* " in
      *" --show-toplevel "*|*" --git-dir "*|*" --absolute-git-dir "*|*" --git-common-dir "*|*" --show-superproject-working-tree "*)
        to_windows='s|^/|Z:/|' ;;
    esac ;;
  worktree)
    case " $* " in *" list "*) to_windows='s|^/|Z:/|; s|^worktree /|worktree Z:/|' ;; esac ;;
  config)
    case " $* " in *" --show-origin "*) to_windows='s|^file:/|file:Z:/|' ;; esac ;;
esac

if [ -z "$to_windows" ]; then
  exec env "${vars[@]}" "$FORK_LINUX_GIT" "$@"
fi
case " $* " in *" -z "*) sed_args=(-z) ;; *) sed_args=() ;; esac
env "${vars[@]}" "$FORK_LINUX_GIT" "$@" | sed "${sed_args[@]}" "$to_windows"
exit "${PIPESTATUS[0]}"
