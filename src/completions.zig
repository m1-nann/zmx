const std = @import("std");

pub const Shell = enum {
    bash,
    zsh,
    fish,

    pub fn fromString(s: []const u8) ?Shell {
        if (std.mem.eql(u8, s, "bash")) return .bash;
        if (std.mem.eql(u8, s, "zsh")) return .zsh;
        if (std.mem.eql(u8, s, "fish")) return .fish;

        return null;
    }

    pub fn getCompletionScript(self: Shell) []const u8 {
        return switch (self) {
            .bash => bash_completions,
            .zsh => zsh_completions,
            .fish => fish_completions,
        };
    }
};

const bash_completions =
    \\_zmx_completions() {
    \\  local cur prev words cword
    \\  COMPREPLY=()
    \\  cur="${COMP_WORDS[COMP_CWORD]}"
    \\  prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\
    \\  local commands="run send detach list completions kill restart rename history wait tail version help"
    \\
    \\  if [[ $COMP_CWORD -eq 1 ]]; then
    \\    # A bare first token is a session name (attach); offer both commands
    \\    # and existing session names here.
    \\    local sessions=$(zmx list --short 2>/dev/null | tr '\n' ' ')
    \\    COMPREPLY=($(compgen -W "$commands $sessions --add" -- "$cur"))
    \\    return 0
    \\  fi
    \\
    \\  case "$prev" in
    \\    run|send|kill|history)
    \\      local sessions=$(zmx list --short 2>/dev/null | tr '\n' ' ')
    \\      COMPREPLY=($(compgen -W "$sessions" -- "$cur"))
    \\      ;;
    \\    completions)
    \\      COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
    \\      ;;
    \\    list)
    \\      COMPREPLY=($(compgen -W "--short" -- "$cur"))
    \\      ;;
    \\    *)
    \\      ;;
    \\  esac
    \\}
    \\
    \\complete -o bashdefault -o default -F _zmx_completions zmx
;

const zsh_completions =
    \\_zmx() {
    \\  local context state state_descr line
    \\  typeset -A opt_args
    \\
    \\  _arguments -C \
    \\    '1: :->commands' \
    \\    '2: :->args' \
    \\    '*: :->trailing' \
    \\    && return 0
    \\
    \\  case $state in
    \\    commands)
    \\      local -a commands
    \\      commands=(
    \\        'run:Send command without attaching'
    \\        'send:Send raw input to session PTY'
    \\        'detach:Detach all clients from current session'
    \\        'list:List active sessions'
    \\        'completions:Shell completion scripts'
    \\        'kill:Kill a session'
    \\        'restart:Kill the session and respawn it in the same cwd'
    \\        'rename:Rename the current session'
    \\        'history:Output session scrollback'
    \\        'wait:Wait for session tasks to complete'
    \\        'tail:Follow session output'
    \\        'version:Show version'
    \\        'help:Show help message'
    \\      )
    \\      _describe 'command' commands
    \\      # A bare first token is a session name to attach to.
    \\      _zmx_sessions
    \\      ;;
    \\    args)
    \\      case $words[2] in
    \\        kill|k|run|r|send|s|history|hi)
    \\          _zmx_sessions
    \\          ;;
    \\        completions|c)
    \\          _values 'shell' 'bash' 'zsh' 'fish'
    \\          ;;
    \\        list|l)
    \\          _values 'options' '--short'
    \\          ;;
    \\      esac
    \\      ;;
    \\    trailing)
    \\      # Additional args for a bare-name attach or 'run'
    \\      ;;
    \\  esac
    \\}
    \\
    \\_zmx_sessions() {
    \\  local -a sessions
    \\
    \\  local local_sessions=$(zmx list --short 2>/dev/null)
    \\  if [[ -n "$local_sessions" ]]; then
    \\    sessions+=(${(f)local_sessions})
    \\  fi
    \\
    \\  _describe 'local session' sessions
    \\}
    \\
    \\compdef _zmx zmx
;

const fish_completions =
    \\complete -c zmx -f
    \\
    \\# zmx flags
    \\complete -c zmx -x -n '__fish_is_nth_token 1' -s v -l version -d 'Show version'
    \\complete -c zmx -x -n '__fish_is_nth_token 1' -s h -d 'Show help message'
    \\
    \\# zmx subcommands
    \\complete -c zmx -n "__fish_is_nth_token 1" -a run -d 'Send command without attaching'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a send -d 'Send raw input to session PTY'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a write -d 'Write stdin to file_path through the session'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a detach -d 'Detach all clients (ctrl+\ or ctrl+q for current client)'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a list -d 'List active sessions'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a kill -d 'Kill session and all attached clients'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a restart -d 'Kill the session and respawn it in the same cwd'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a rename -d 'Rename the current session (run inside it)'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a history -d 'Output session scrollback'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a wait -d 'Wait for session tasks to complete'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a tail -d 'Follow session output'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a completions -d 'Shell completions (bash, zsh, fish)'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a version -d 'Show version'
    \\complete -c zmx -n "__fish_is_nth_token 1" -a help -d 'Show help message'
    \\
    \\# A bare first token is a session name to attach to.
    \\complete -c zmx -n "__fish_is_nth_token 1" -a '(zmx list --short 2>/dev/null)' -d 'Session name'
    \\
    \\# Complete session names and shells
    \\complete -c zmx -n "__fish_is_nth_token 2; and __fish_seen_subcommand_from r run s send wr write hi history" -a '(zmx list --short 2>/dev/null)' -d 'Session name'
    \\complete -c zmx -n "not __fish_is_nth_token 1; and __fish_seen_subcommand_from k kill w wait t tail" -a '(zmx list --short 2>/dev/null)' -d 'Session name'
    \\
    \\complete -c zmx -n "__fish_is_nth_token 2; and __fish_seen_subcommand_from c completions" -a 'bash zsh fish' -d Shell
    \\
    \\# Bare-name attach flags (only when the first token is not a subcommand)
    \\complete -c zmx -n "not __fish_is_nth_token 1; and not __fish_seen_subcommand_from r run s send p print wr write d detach l list ls c completions k kill re restart ren rename hi history w wait t tail v version h help" -l add -d 'Create the session if it does not exist'
    \\complete -c zmx -n "not __fish_is_nth_token 1; and not __fish_seen_subcommand_from r run s send p print wr write d detach l list ls c completions k kill re restart ren rename hi history w wait t tail v version h help" -l limit -d 'Cap scrollback rows replayed on attach'
    \\
    \\# Subcommand flags
    \\complete -c zmx -n "__fish_seen_subcommand_from r run" -s d -d 'Detach from the calling terminal; use `wait` to track its status'
    \\complete -c zmx -n "__fish_seen_subcommand_from r run" -l fish -d 'Required when the session runs fish shell'
    \\complete -c zmx -n "__fish_seen_subcommand_from l list" -l short -d 'Short output'
    \\complete -c zmx -n "__fish_seen_subcommand_from k kill" -l force -d 'Force kill'
    \\complete -c zmx -n "__fish_seen_subcommand_from hi history" -l vt -d 'History format for escape sequences'
    \\complete -c zmx -n "__fish_seen_subcommand_from hi history" -l html -d 'History format for escape sequences'
;
