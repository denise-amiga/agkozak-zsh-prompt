#              _                 _
#   __ _  __ _| | _____ ______ _| | __
#  / _` |/ _` | |/ / _ \_  / _` | |/ /
# | (_| | (_| |   < (_) / / (_| |   <
#  \__,_|\__, |_|\_\___/___\__,_|_|\_\
#        |___/
#
# An asynchronous, dynamic color prompt for ZSH with Git, vi mode, and exit
# status indicators
#
#
# MIT License
#
# Copyright (c) 2017-2019 Alexandros Kozak
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#
# https://github.com/agkozak/agkozak-zsh-prompt
#

# psvar[] Usage
#
# psvar Index   Prompt String Equivalent    Usage
#
# psvar[1]      %1v                         Hostname/abbreviated hostname (only
#                                           displayed for SSH connections)
#
# psvar[2]      %2v                         Working directory or abbreviation
#                                           thereof
#
# psvar[3]      %3v                         Current working Git branch, along
#                                           with indicator of changes made
#
# psvar[4]      %4v                         Equals 'vicmd' when vi command mode
#                                           is enabled; otherwise empty
#
# psvar[5]      %5v                         Empty only when
#                                           AGKOZAK_USER_HOST_DISPLAY is 0

autoload -Uz is-at-least add-zle-hook-widget

# AGKOZAK is an associative array for storing internal information that is discarded when the
# prompt is unloaded.
#
# AGKOZAK[ARGUMENT]     An argument passed to the agkozak-zsh-prompt function
# AGKOZAK[ASYNC_METHOD] Which asynchronous method is currently in use
# AGKOZAK[FIRST_PROMPT_PRINTED] When AGKOZAK_BLANK_LINES=1, this variable
#                       prevents an unnecessary blank line before the first
#                       prompt of the session
# AGKOZAK[FUNCTIONS]    A list of the prompt's functions
# AGKOZAK[GIT_VERSION]  The version of Git on a given system
# AGKOZAK[HAS_COLORS]   Whether or not to display the prompt in color
# AGKOZAK[IS_WSL]       Whether or not the system is WSL
# AGKOZAK[OLD_NAMED_DIRS] Used to detect changes in AGKOZAK_NAMED_DIRS
# AGKOZAK[OLD_PROMPT]   The left prompt before this prompt was loaded
# AGKOZAK[OLD_PROMPT_DIRTRIM] Used to detect changes in AGKOZAK_PROMPT_DIRTRIM
# AGKOZAK[OLD RPROMPT]  The right prompt before this prompt was loaded
# AGKOZAK[PROMPT]       The current state of the left prompt
# AGKOZAK[PROMPT_DIR]   The directory the prompt source code is in
# AGKOZAK[RPROMPT]      The current state of the right prompt
# AGKOZAK[TRAPUSR1_FUNCTION]  The code of the TRAPUSR1 function. If it changes,
#                       the prompt knows to abandon the usr1 method.
# AGKOZAK[USR1_ASYNC_WORKER]  When non-zero, the PID of the asynchronous
#                       function handling Git Status (usr1 method)
typeset -gA AGKOZAK

# In case an argument is passed when the script is sourced
AGKOZAK[ARGUMENT]=$1

# Options to reset if the prompt is unloaded
typeset -gA AGKOZAK_OLD_OPTIONS
AGKOZAK_OLD_OPTIONS=(
                      'promptsubst' ${options[promptsubst]}
                      'promptbang' ${options[promptbang]}
                    )

# Store previous prompts and psvars for the unload function
typeset -ga AGKOZAK_OLD_PSVAR
AGKOZAK[OLD_PROMPT]=${PROMPT}
AGKOZAK[OLD_RPROMPT]=${RPROMPT}
AGKOZAK_OLD_PSVAR=( ${psvar[@]} )

# Names of prompt functions. Used to enable WARN_NESTED_VAR in debug mode
# and for unloading the prompt.
AGKOZAK[FUNCTIONS]='_agkozak_debug_print
                    _agkozak_has_colors
                    _agkozak_is_ssh
                    _agkozak_prompt_dirtrim
                    _agkozak_branch_status
                    _agkozak_zle-keymap-select
                    TRAPWINCH
                    _agkozak_vi_mode_indicator
                    _agkozak_load_async_lib
                    _agkozak_has_usr1
                    _agkozak_async_init
                    _agkozak_subst_async
                    _agkozak_zsh_subst_async_callback
                    _agkozak_zsh_async
                    _agkozak_zsh_async_callback
                    _agkozak_usr1_async
                    _agkozak_usr1_async_worker
                    TRAPUSR1
                    _agkozak_strip_colors
                    _agkozak_precmd
                    _agkozak_clear-screen
                    _agkozak_chpwd
                    _agkozak_prompt_strings
                    agkozak-zsh-prompt'

############################################################
# Display a message on STDERR if debug mode is enabled
#
# Globals:
#   AGKOZAK_PROMPT_DEBUG
# Arguments:
#   $1  Message to send to STDERR
############################################################
_agkozak_debug_print() {
  (( ${AGKOZAK_PROMPT_DEBUG:-0} )) && print -- "agkozak-zsh-prompt: $1" >&2
}

if (( ${AGKOZAK_PROMPT_DEBUG:-0} )); then
  if is-at-least 5.4.0; then
    for x in ${=AGKOZAK[FUNCTIONS]}; do
      # Enable WARN_CREATE_GLOBAL for each function of the prompt
      functions -W $x
    done
  fi
  unset x
fi

############################################################
# Legacy assignments
#
# No longer entirely necessary for the prompt, but included
# just in case someone is using an older custom prompt that
# needs them.
############################################################

# Set AGKOZAK_COLORS_* variables to any valid color
#   AGKOZAK_COLORS_EXIT_STATUS changes the exit status color      (default: red)
#   AGKOZAK_COLORS_USER_HOST changes the username/hostname color  (default: green)
#   AGKOZAK_COLORS_PATH changes the path color                    (default: blue)
#   AGKOZAK_COLORS_BRANCH_STATUS changes the branch status color  (default: yellow)
#   AGKOZAK_COLORS_PROMPT_CHAR changes the prompt character color (default: white)
: ${AGKOZAK_COLORS_EXIT_STATUS:=red}
: ${AGKOZAK_COLORS_USER_HOST:=green}
: ${AGKOZAK_COLORS_PATH:=blue}
: ${AGKOZAK_COLORS_BRANCH_STATUS:=yellow}
: ${AGKOZAK_COLORS_PROMPT_CHAR:=white}

setopt PROMPT_SUBST NO_PROMPT_BANG

######################################################################
# GENERAL FUNCTIONS
######################################################################

############################################################
# Are colors available?
#
# Globals:
#   AGKOZAK
############################################################
_agkozak_has_colors() {
  if (( ! ${+AGKOZAK[HAS_COLORS]} )); then
    case $TERM in
      *-256color) AGKOZAK[HAS_COLORS]=1 ;;
      vt100|dumb) AGKOZAK[HAS_COLORS]=0 ;;
      *)
        local colors
        case $OSTYPE in
          freebsd*|dragonfly*) colors=$(tput Co) ;;
          *) colors=$(tput colors) ;;
        esac
        AGKOZAK[HAS_COLORS]=$(( colors >= 8 ))
        ;;
    esac
  fi
  (( AGKOZAK[HAS_COLORS] ))
}

############################################################
# Is the user connected via SSH?
#
# This function works perfectly for regular users. It is
# nearly impossible to detect with accuracy how a superuser
# is connected, so this prompt opts simply to display his or
# her username and hostname in inverse video.
############################################################
_agkozak_is_ssh() {
  [[ -n "${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-}" ]]
}

############################################################
# Emulation of bash's PROMPT_DIRTRIM for ZSH
#
# Take PWD and substitute HOME with `~'. If the rest of PWD
# has more than a certain number of elements in its
# directory tree, keep the number specified by
# AGKOZAK_PROMPT_DIRTRIM (default: 2) and abbreviate the
# rest with `...'. (Set AGKOZAK_PROMPT_DIRTRIM=0 to disable
# directory trimming). For example,
#
#   $HOME/dotfiles/polyglot/img
#
# will be displayed as
#
#   ~/.../polyglot/img
#
# Named directories will by default be displayed using their
# aliases in the prompt (e.g. `~project'). Set
# AGKOZAK_NAMED_DIRS=0 to have them displayed just like any
# other directory.
#
# Globals:
#   AGKOZAK_PROMPT_DEBUG
#   AGKOZAK_NAMED_DIRS
# Arguments:
#   $@ [Optional] If `-v', store the function's output in
#        psvar[2] instead of printing it to STDOUT
#   $@ Number of directory elements to display (default: 2)
############################################################
_agkozak_prompt_dirtrim() {
  emulate -L zsh
  (( ${AGKOZAK_PROMPT_DEBUG:-0} )) && setopt LOCAL_OPTIONS WARN_CREATE_GLOBAL

  # Process arguments
  local argument
  for argument in $@; do
    [[ $argument == '-v' ]] && local var=1
  done
  until [[ $1 != '-v' ]]; do
    shift
  done
  [[ $1 -ge 0 ]] || set 2

  # Default behavior (when AGKOZAK_NAMED_DIRS is 1)
  if (( ${AGKOZAK_NAMED_DIRS:-1} )); then
    local zsh_pwd
    print -Pnz '%~'

    # IF AGKOZAK_PROMPT_DIRTRIM is not 0, trim directory
    if (( $1 )); then
      read -rz zsh_pwd
      case $zsh_pwd in
        \~) print -Pnz $zsh_pwd ;;
        \~/*) print -Pnz "%($(( $1 + 2 ))~|~/.../%${1}~|%~)" ;;
        \~*) print -Pnz "%($(( $1 + 2 ))~|${zsh_pwd%%${zsh_pwd#\~*\/}}.../%${1}~|%~)" ;;
        *) print -Pnz "%($(( $1 + 1 ))/|.../%${1}d|%d)" ;;
      esac
    fi

  # If AGKOZAK_NAMED_DIRS is 0
  else
    local dir dir_count
    case $HOME in
      /) dir=${PWD} ;;
      *) dir=${PWD#$HOME} ;;
    esac

    # If AGKOZAK_PROMPT_DIRTRIM is not 0, trim the directory
    if (( $1 > 0 )); then

      # The number of directory elements is the number of slashes in ${PWD#$HOME}
      dir_count=$(( ${#dir} - ${#${dir//\//}} ))
      if (( dir_count <= $1 )); then
        case $PWD in
          ${HOME}) print -nz '~' ;;
          ${HOME}*) print -nz "~${dir}" ;;
          *) print -nz "$PWD" ;;
        esac
      else
        local lopped_path i
        lopped_path=${dir}
        i=0
        while (( i != $1 )); do
          lopped_path=${lopped_path%\/*}
          (( i++ ))
        done
        case $PWD in
          ${HOME}*) print -nz "~/...${dir#${lopped_path}}" ;;
          *) print -nz -f '...%s' "${PWD#${lopped_path}}" ;;
        esac
      fi

    # If AGKOZAK_PROMPT_DIRTRIM is 0
    else
      case $PWD in
        ${HOME}) print -nz '~' ;;
        ${HOME}*) print -nz "~${dir}" ;;
        *) print -nz "$PWD" ;;
      esac
    fi
  fi

  local output
  read -rz output

  # Argument -v stores the output to psvar[2]; otherwise send to STDOUT
  if (( var )); then
    psvar[2]=$output
  else
    print $output
  fi
}

############################################################
# Display current branch name, followed by symbols
# representing changes to the working copy
#
# Globals:
#   AGKOZAK
#   AGKOZAK_PROMPT_DEBUG
#   AGKOZAK_SHOW_STASH
#   AGKOZAK_CUSTOM_SYMBOLS
#   AGKOZAK_BRANCH_STATUS_SEPARATOR
############################################################
_agkozak_branch_status() {
  emulate -L zsh
  (( ${AGKOZAK_PROMPT_DEBUG:-0} )) && setopt LOCAL_OPTIONS WARN_CREATE_GLOBAL

  local ref branch
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  case $? in        # See what the exit code is.
    0) ;;           # $ref contains the name of a checked-out branch.
    128) return ;;  # No Git repository here.
    # Otherwise, see if HEAD is in detached state.
    *) ref=$(command git rev-parse --short HEAD 2> /dev/null) || return ;;
  esac
  branch=${ref#refs/heads/}

  if [[ -n $branch ]]; then
    local git_status symbols i=1 k

    # Cache the Git version
    if (( ${AGKOZAK_SHOW_STASH:-1} )); then
      : ${${AGKOZAK[GIT_VERSION]:=$(command git --version)}#git version }
    fi

    if (( ${AGKOZAK_SHOW_STASH:-1} )); then
      if is-at-least 2.14 ${AGKOZAK[GIT_VERSION]}; then
        git_status="$(LC_ALL=C GIT_OPTIONAL_LOCKS=0 command git status --show-stash 2>&1)"
      else
        git_status="$(LC_ALL=C GIT_OPTIONAL_LOCKS=0 command git status 2>&1)"
      fi
    fi

    typeset -A messages
    messages=(
                '&*'  ' have diverged,'
                '&'   'Your branch is behind '
                '*'   'Your branch is ahead of '
                '+'   'new file:   '
                'x'   'deleted:    '
                '!'   'modified:   '
                '>'   'renamed:    '
                '?'   'Untracked files:'
             )

    for k in '&*' '&' '*' '+' 'x' '!' '>' '?'; do
      case $git_status in
        *${messages[$k]}*) symbols+="${AGKOZAK_CUSTOM_SYMBOLS[$i]:-$k}" ;;
      esac
      (( i++ ))
    done

    # Check for stashed changes. If there are any, add the stash symbol to the
    # list of symbols.
    if (( ${AGKOZAK_SHOW_STASH:-1} )); then
      if is-at-least 2.14 ${AGKOZAK[GIT_VERSION]}; then
        case $git_status in
          *'Your stash currently has '*)
            symbols+="${AGKOZAK_CUSTOM_SYMBOLS[$i]:-\$}"
            ;;
        esac
      else
        if command git rev-parse --verify refs/stash &> /dev/null; then
          symbols+="${AGKOZAK_CUSTOM_SYMBOLS[$i]:-\$}"
        fi
      fi
    fi

    [[ -n $symbols ]] && symbols=" ${symbols}"

    printf '%s(%s%s)' "${AGKOZAK_BRANCH_STATUS_SEPARATOR- }" "$branch" "$symbols"
  fi
}

############################################################
# Redraw the prompt when the vi mode changes. When the user
# enters vi command mode, the % or # in the prompt changes
# to a colon
############################################################
_agkozak_zle-keymap-select() {
  emulate -L zsh

  [[ $KEYMAP == 'vicmd' ]] && psvar[4]='vicmd' || psvar[4]=''
  zle .reset-prompt
  zle -R
}

############################################################
# Redraw prompt when terminal size changes
############################################################
TRAPWINCH() {
  zle && zle -R
}

############################################################
# For legacy custom prompts: print a vi mode indicator
############################################################
_agkozak_vi_mode_indicator() {
  case $KEYMAP in
    vicmd) print -n ':' ;;
    *) print -n '%#' ;;
  esac
}

######################################################################
# ASYNCHRONOUS FUNCTIONS
######################################################################

# Standarized $0 handling
# (See https://github.com/zdharma/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc)0=${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}})
0=${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}
0=${${(M)0:#/*}:-$PWD/$0}
AGKOZAK[PROMPT_DIR]="${0:A:h}"

############################################################
# If zsh-async has not already been loaded, try to load it
#
# Globals:
#   AGKOZAK
#   AGKOZAK_PROMPT_DEBUG
############################################################
_agkozak_load_async_lib() {
  if ! whence -w async_init &> /dev/null; then      # Don't load zsh-async twice
    if (( ${AGKOZAK_PROMPT_DEBUG:-0} )); then
      source "${AGKOZAK[PROMPT_DIR]}/lib/async.zsh"
    else
      source "${AGKOZAK[PROMPT_DIR]}/lib/async.zsh" &> /dev/null
    fi
    local success=$?
    return $success
  fi
}

############################################################
# Is SIGUSR1 is available and not already in use by ZSH?
############################################################
_agkozak_has_usr1() {
  if whence -w TRAPUSR1 &> /dev/null; then
    _agkozak_debug_print 'TRAPUSR1 already defined.'
    return 1
  else
    case $signals in    # Array containing names of available signals
      *USR1*) return 0 ;;
      *)
        _agkozak_debug_print 'SIGUSR1 not available.'
        return 1
        ;;
    esac
  fi
}

############################################################
# If AGKOZAK_FORCE_ASYNC_METHOD is set to a valid value,
# set AGKOZAK[ASYNC_METHOD] to that; otherwise, determine
# the optimal asynchronous method from the environment (usr1
# for MSYS2/Cygwin/WSL, zsh-async for WSL, subst-async for
# everything else), with fallbacks being available. Define
# the necessary asynchronous functions (loading async.zsh
# when necessary).
#
# Globals:
#   AGKOZAK
#   AGKOZAK_FORCE_ASYNC_METHOD
#   AGKOZAK_ASYNC_FD
#   AGKOZAK_PROMPT_DEBUG
############################################################
_agkozak_async_init() {
  emulate -L zsh
  setopt LOCAL_OPTIONS EXTENDED_GLOB NO_LOCAL_TRAPS

  # TODO: Consider removing this entirely. It is the sort of thing that should
  # go in a .zshrc. Mention in documentation.
  #
  # WSL should have BG_NICE disabled, since it does not have a Linux kernel
  # if [[ $OSTYPE == linux* ]] && [[ -e /proc/version ]] \
  #   && [[ -n ${(M)${(f)"$(</proc/version)"}:#*Microsoft*} ]]; then
  #   unsetopt BG_NICE
  #   AGKOZAK[IS_WSL]=1   # For later reference
  # fi

  # If an asynchronous method has been passed as an argument to
  # agkozak-zsh-prompt, use it
  if [[ ${AGKOZAK[ARGUMENT]} == (subst-async|usr1|zsh-async|none) ]]; then
    AGKOZAK[ASYNC_METHOD]=${AGKOZAK[ARGUMENT]}
    [[ ${AGKOZAK[ARGUMENT]} == 'zsh-async' ]] && _agkozak_load_async_lib
  elif [[ $AGKOZAK_FORCE_ASYNC_METHOD == (subst-async|zsh-async|usr1|none) ]]; then
    AGKOZAK[ASYNC_METHOD]=${AGKOZAK_FORCE_ASYNC_METHOD}
  
  # Otherwise, first provide for certain quirky systems
  else

    if [[ $OSTYPE == solaris* ]]; then
      if [[ $ZSH_VERSION != '5.0.2' ]] && _agkozak_load_async_lib; then
        AGKOZAK[ASYNC_METHOD]='zsh-async'
      elif _agkozak_has_usr1; then
        AGKOZAK[ASYNC_METHOD]='usr1'
      else
        AGKOZAK[ASYNC_METHOD]='subst-async'
      fi

    # SIGUSR1 method is still much faster on Windows (MSYS2/Cygwin/WSL).
    elif [[ $OSTYPE == (msys|cygwin) ]] || (( AGKOZAK[IS_WSL] )); then
      if _agkozak_has_usr1; then
        AGKOZAK[ASYNC_METHOD]='usr1'
      else
        AGKOZAK[ASYNC_METHOD]='subst-async'
      fi

    # Asynchronous methods don't work in Emacs shell mode (but they do in term
    # and ansi-term)
    elif [[ $TERM == 'dumb' ]]; then
      AGKOZAK[ASYNC_METHOD]='none'

    # Otherwise use subst-async
    else
      AGKOZAK[ASYNC_METHOD]='subst-async'
    fi
  fi

  ############################################################
  # Process substitution async method
  #
  # Fork a background process to fetch the Git status and feed
  # it asynchronously to a file descriptor. Install a callback
  # handler to process input from the file descriptor.
  #
  # Globals:
  #   AGKOZAK
  #   AGKOZAK_ASYNC_FD
  ############################################################
  _agkozak_subst_async() {
    emulate -L zsh
    setopt LOCAL_OPTIONS NO_IGNORE_BRACES

    typeset -g AGKOZAK_ASYNC_FD=13371

    if [[ $OSTYPE == (msys|cygwin) ]]; then
      exec {AGKOZAK_ASYNC_FD}< <(_agkozak_branch_status; command true)
    elif [[ $OSTYPE == solaris* ]]; then
      exec {AGKOZAK_ASYNC_FD}< <(_agkozak_branch_status)
      command sleep 0.01
    elif [[ $ZSH_VERSION == 5.0.[0-2] ]]; then
      exec {AGKOZAK_ASYNC_FD}< <(_agkozak_branch_status)
      command sleep 0.02
    else
      exec {AGKOZAK_ASYNC_FD}< <(_agkozak_branch_status)

      # Bug workaround; see http://www.zsh.org/mla/workers/2018/msg00966.html
      command true
    fi

    zle -F "$AGKOZAK_ASYNC_FD" _agkozak_zsh_subst_async_callback
  }

  ############################################################
  # ZLE callback handler
  #
  # Read Git status from file descriptor and set psvar[3]
  #
  # Arguments:
  #   $1  File descriptor
  ############################################################
  _agkozak_zsh_subst_async_callback() {
    emulate -L zsh
    setopt LOCAL_OPTIONS NO_IGNORE_BRACES

    local FD="$1" response

    # Read data from $FD descriptor
    IFS='' builtin read -rs -d $'\0' -u "$FD" response

    # Withdraw callback and close the file descriptor
    zle -F ${FD}; exec {FD}<&-

    # Make the changes visible
    psvar[3]="$response"
    zle && zle .reset-prompt
  }

  case ${AGKOZAK[ASYNC_METHOD]} in

    zsh-async)

      ############################################################
      # Create zsh-async worker
      ############################################################
      _agkozak_zsh_async() {
        async_start_worker agkozak_git_status_worker -n
        async_register_callback agkozak_git_status_worker _agkozak_zsh_async_callback
        async_job agkozak_git_status_worker _agkozak_branch_status
      }

      ############################################################
      # Set RPROMPT and stop worker
      ############################################################
      _agkozak_zsh_async_callback() {
        emulate -L zsh

        psvar[3]=$3
        zle && zle .reset-prompt
        async_stop_worker agkozak_git_status_worker -n
      }
      ;;

    usr1)

      ############################################################
      # Launch async workers to calculate Git status. TRAPUSR1
      # actually displays the status; if some other script
      # redefines TRAPUSR1, drop the prompt into synchronous mode.
      #
      # Globals:
      #   AGKOZAK
      ############################################################
      _agkozak_usr1_async() {
        emulate -L zsh

        if [[ "$(builtin which TRAPUSR1)" == "${AGKOZAK[TRAPUSR1_FUNCTION]}" ]]; then
          # Kill running child process if necessary
          if (( AGKOZAK[USR1_ASYNC_WORKER] )); then
            kill -s HUP "${AGKOZAK[USR1_ASYNC_WORKER]}" &> /dev/null || :
          fi

          # Start background computation of Git status
          _agkozak_usr1_async_worker &!
          AGKOZAK[USR1_ASYNC_WORKER]="$!"
        else
          _agkozak_debug_print 'TRAPUSR1 has been redefined. Switching to subst-async mode.'
          AGKOZAK[ASYNC_METHOD]='subst-async'
          psvar[3]="$(_agkozak_branch_status)"
        fi
      }

      ############################################################
      # Calculate Git status and store it in a temporary file;
      # then kill own process, sending SIGUSR1
      #
      # Globals:
      #   AGKOZAK_PROMPT_DEBUG
      ############################################################
      _agkozak_usr1_async_worker() {
        # Save Git branch status to temporary file
        _agkozak_branch_status >| /tmp/agkozak_zsh_prompt_$$

        # Signal parent process
        if (( ${AGKOZAK_PROMPT_DEBUG:-0} )); then
          kill -s USR1 $$
        else
          kill -s USR1 $$ &> /dev/null
        fi
      }

      ############################################################
      # On SIGUSR1, fetch Git status from temprary file and store
      # it in psvar[3]. This function caches its own code in
      # AGKOZAK[TRAPUSR1_FUNCTION] so that it can tell if it has
      # been redefined by another script.
      #
      # Globals:
      #   AGKOZAK
      ############################################################
      TRAPUSR1() {
        emulate -L zsh

        # Set prompt from contents of temporary file
        psvar[3]=$(print -n -- "$(< /tmp/agkozak_zsh_prompt_$$)")

        # Reset asynchronous process number
        AGKOZAK[USR1_ASYNC_WORKER]=0

        # Redraw the prompt
        zle && zle .reset-prompt
      }

      AGKOZAK[TRAPUSR1_FUNCTION]="$(builtin which TRAPUSR1)"
      ;;
  esac
}

######################################################################
# THE PROMPT
######################################################################

############################################################
# Strip color codes from a prompt string
#
# Arguments:
#   $1 Name of prompt string variable
############################################################
_agkozak_strip_colors() {
  local prompt_string=${(P)1} newprompt
  local open_braces

  while [[ -n $prompt_string ]]; do
    case $prompt_string in
      %F\{*|%K\{*)
        (( open_braces++ ))
        prompt_string=${prompt_string#%[FK]\{}
        while (( open_braces )); do
          case ${prompt_string:0:1} in
            \{) (( open_braces++ )) ;;
            \}) (( open_braces-- )) ;;
          esac
          prompt_string=${prompt_string#?}
        done
        ;;
      %f*|%k*) prompt_string=${prompt_string#%[fk]} ;;
      *)
        newprompt+="${prompt_string:0:1}"
        prompt_string=${prompt_string#?}
        ;;
    esac
  done

  print -nz -- "${(qq)newprompt}"
  read -rz $1
  typeset -g $1=${(PQQ)1}
}

############################################################
# Runs right before each prompt is displayed; hooks into
# precmd
#
# Globals:
#   AGKOZAK
#   AGKOZAK_PROMPT_DEBUG
#   AGKOZAK_SHOW_STASH
#   AGKOZAK_PROMPT_DIRTRIM
#   AGKOZAK_NAMED_DIRS
#   AGKOZAK_USER_HOST_DISPLAY
#   AGKOZAK_MULTILINE
#   AGKOZAK_PRE_PROMPT_CHAR
#   AGKOZAK_BLANK_LINES
############################################################
_agkozak_precmd() {
  emulate -L zsh
  (( ${AGKOZAK_PROMPT_DEBUG:-0} )) && setopt LOCAL_OPTIONS WARN_CREATE_GLOBAL

  # Update displayed directory when AGKOZAK_PROMPT_DIRTRIM or AGKOZAK_NAMED_DIRS
  # changes or when first sourcing this script
  if (( ${AGKOZAK_PROMPT_DIRTRIM:-2} != AGKOZAK[OLD_PROMPT_DIRTRIM] )) \
    || (( ${AGKOZAK_NAMED_DIRS:-1} != AGKOZAK[OLD_NAMED_DIRS] )) \
    || (( ! $+psvar[2] )); then
    _agkozak_prompt_dirtrim -v ${AGKOZAK_PROMPT_DIRTRIM:-2}
    AGKOZAK[OLD_PROMPT_DIRTRIM]=$AGKOZAK_PROMPT_DIRTRIM
    AGKOZAK[OLD_NAMED_DIRS]=$AGKOZAK_NAMED_DIRS
  fi

  # Clear the Git status display until it has been recalculated
  psvar[3]=''

  # It is necessary to clear the vi mode display, too
  psvar[4]=''

  # Choose whether or not to display username and hostname
  if (( ${AGKOZAK_USER_HOST_DISPLAY:-1} )); then
    psvar[5]=${AGKOZAK_USER_HOST_DISPLAY:-1}
  else
    psvar[5]=''
  fi

  # Multiline (default) or single line?
  if (( ! ${AGKOZAK_MULTILINE:-1} )) && [[ -z $INSIDE_EMACS ]]; then
    typeset -g AGKOZAK_PROMPT_WHITESPACE=${AGKOZAK_PRE_PROMPT_CHAR- }
  else
    typeset -g AGKOZAK_PROMPT_WHITESPACE=$'\n'
  fi

  # Optionally put blank lines between instances of the prompt
  if (( AGKOZAK_BLANK_LINES )); then
    if (( AGKOZAK[FIRST_PROMPT_PRINTED] )); then
      print
    fi
    AGKOZAK[FIRST_PROMPT_PRINTED]=1
  fi

  # Begin to calculate the Git status
  case ${AGKOZAK[ASYNC_METHOD]} in
    'subst-async') _agkozak_subst_async ;;
    'zsh-async') _agkozak_zsh_async ;;
    'usr1') _agkozak_usr1_async ;;
    *) psvar[3]="$(_agkozak_branch_status)" ;;
  esac

  # Construct and display PROMPT and RPROMPT
  _agkozak_prompt_strings
}

############################################################
# Set the prompt strings
#
# Globals:
#   AGKOZAK
#   AGKOZAK_CUSTOM_PROMPT
#   AGKOZAK_LEFT_PROMPT_ONLY
#   AGKOZAK_COLORS_EXIT_STATUS
#   AGKOZAK_COLORS_USER_HOST
#   AGKOZAK_COLORS_PATH
#   AGKOZAK_COLORS_BRANCH_STATUS
#   AGKOZAK_PROMPT_WHITESPACE
#   AGKOZAK_COLORS_PROMPT_CHAR
#   AGKOZAK_PROMPT_CHAR
#   AGKOZAK_CUSTOM_RPROMPT
#   AGKOZAK_MULTILINE
############################################################
_agkozak_prompt_strings() {
  emulate -L zsh

  # TODO: Document what unsetting the custom prompt strings does.
  if (( $+AGKOZAK_CUSTOM_PROMPT )); then
    AGKOZAK[PROMPT]=${AGKOZAK_CUSTOM_PROMPT}
  else
    # The color left prompt
    AGKOZAK[PROMPT]='%(?..%B%F{${AGKOZAK_COLORS_EXIT_STATUS:-red}}(%?%)%f%b )'
    AGKOZAK[PROMPT]+='%(5V.%(!.%S%B.%B%F{${AGKOZAK_COLORS_USER_HOST:-green}})%n%1v%(!.%b%s.%f%b) .)'
    AGKOZAK[PROMPT]+='%B%F{${AGKOZAK_COLORS_PATH:-blue}}%2v%f%b'
    if (( ${AGKOZAK_LEFT_PROMPT_ONLY:-0} )); then
      AGKOZAK[PROMPT]+='%(3V.%F{${AGKOZAK_COLORS_BRANCH_STATUS:-yellow}}%3v%f.)'
    fi
    AGKOZAK[PROMPT]+='${AGKOZAK_PROMPT_WHITESPACE}'
    AGKOZAK[PROMPT]+='%F{${AGKOZAK_COLORS_PROMPT_CHAR:-white}}'
    AGKOZAK[PROMPT]+='%(4V.${AGKOZAK_PROMPT_CHAR[3]:-:}.%(!.${AGKOZAK_PROMPT_CHAR[2]:-%#}.${AGKOZAK_PROMPT_CHAR[1]:-%#}))'
    AGKOZAK[PROMPT]+='%f '
  fi

  if (( $+AGKOZAK_CUSTOM_RPROMPT )); then
    AGKOZAK[RPROMPT]=${AGKOZAK_CUSTOM_RPROMPT}
  else
    # The color right prompt
    if (( ! ${AGKOZAK_LEFT_PROMPT_ONLY:-0} )); then
      typeset -g AGKOZAK[RPROMPT]='%(3V.%F{${AGKOZAK_COLORS_BRANCH_STATUS:-yellow}}%3v%f.)'
    else
      typeset -g AGKOZAK[RPROMPT]=''
    fi
  fi

  if ! _agkozak_has_colors; then
    _agkozak_strip_colors 'AGKOZAK[PROMPT]'
    _agkozak_strip_colors 'AGKOZAK[RPROMPT]'
  fi

  # ZSH multiline prompts tend to cause the last line of STDOUT to disappear
  # if the screen is redrawn. The solution is to have a precmd function output
  # all but the last line of the left prompt; that last part alone is held in
  # the variable PROMPT.
  #
  # The downside of this approach is that it does not work when the Git status
  # is in the top line of the left prompt, such as when
  # AGKOZAK_LEFT_PROMPT_ONLY == 1. The code below tries to detect if the Git
  # status is in the left prompt so that it does not interfere with its
  # display
  #
  # TODO: Create a setting to disable this workaround on the offchance that
  # it causes trouble for someone. Also, document thoroughly.
  if { { (( ${AGKOZAK_MULTILINE:-1} )) && (( ! ${AGKOZAK_LEFT_PROMPT_ONLY:-0} )); } \
    || (( $+AGKOZAK_CUSTOM_PROMPT )); } \
    && [[ ${AGKOZAK[PROMPT]} == *(\$\{AGKOZAK_PROMPT_WHITESPACE\}|$'\n')* ]] \
    && [[ ${AGKOZAK[PROMPT]} != *%3v* ]] \
    && [[ -z ${INSIDE_EMACS} ]]; then

    print -Pnz -- ${AGKOZAK[PROMPT]}
    local REPLY
    read -rz
    print -- ${REPLY%$'\n'*}
    PROMPT=${AGKOZAK[PROMPT]#*(\$\{AGKOZAK_PROMPT_WHITESPACE\}|$'\n')}
    RPROMPT=${AGKOZAK[RPROMPT]}

    ############################################################
    # When the screen clears, _agkozak_precmd must be run to
    # display the first line of the prompt
    ############################################################
    _agkozak_clear-screen() {
      echoti clear
      _agkozak_precmd
      zle .redisplay
    }

    zle -N clear-screen _agkozak_clear-screen
  else
    PROMPT=${AGKOZAK[PROMPT]}
    RPROMPT=${AGKOZAK[RPROMPT]}
  fi
}

############################################################
# Prompt setup
#
# Arguments:
#   $1  If -h or --help, display the async method and show
#       a help message; otherwise, the name of an async
#       method launches the prompt using that method
#
# Globals:
#   AGKOZAK
#   AGKOZAK_PROMPT_DEBUG
#   AGKOZAK_PROMPT_DIRTRIM
############################################################
agkozak-zsh-prompt() {
  emulate -L zsh
  (( ${AGKOZAK_PROMPT_DEBUG:-0} )) && setopt LOCAL_OPTIONS WARN_CREATE_GLOBAL

  case $1 in
    -h|--help)
      print "Using async method: ${AGKOZAK[ASYNC_METHOD]}" >&2
      print >&2
      print 'Valid arguments: -h/--help subst-async usr1 zsh-async none' >&2
      return
      ;;
    subst-async) AGKOZAK[ARGUMENT]='subst-async' ;;
    usr1) AGKOZAK[ARGUMENT]='usr1' ;;
    zsh-async)
      if [[ $OSTYPE == (msys|cygwin) ]]; then
        print "Warning: zsh-async does not work on $OSTYPE." >&2
        print >&2
      fi
      AGKOZAK[ARGUMENT]='zsh-async'
      ;;
    none) AGKOZAK[ARGUMENT]='none' ;;
  esac

  _agkozak_async_init

  case ${AGKOZAK[ASYNC_METHOD]} in
    'subst-async') ;;
    'zsh-async') async_init ;;
    'usr1') AGKOZAK[USR1_ASYNC_WORKER]=0 ;;
  esac

  if is-at-least 5.3; then
    add-zle-hook-widget zle-keymap-select _agkozak_zle-keymap-select
  else
    zle -N zle-keymap-select _agkozak_zle-keymap-select
  fi

  # Don't use ZSH hooks in Emacs classic shell
  if (( $+INSIDE_EMACS )) && [[ $TERM == 'dumb' ]]; then
    :
  else
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _agkozak_precmd

    ############################################################
    # Update the displayed directory when the PWD changes
    #
    # Globals:
    #   AGKOZAK_PROMPT_DIRTRIM
    ############################################################
    _agkozak_chpwd() {
      _agkozak_prompt_dirtrim -v ${AGKOZAK_PROMPT_DIRTRIM:-2}
    }

    add-zsh-hook chpwd _agkozak_chpwd
  fi

  # Only display the HOSTNAME for an SSH connection or for a superuser
  if _agkozak_is_ssh || (( EUID == 0 )); then
    psvar[1]="@${HOST%%.*}"
  else
    psvar[1]=''
  fi

  # The DragonFly BSD console and Emacs shell can't handle bracketed paste.
  # Avoid the ugly ^[[?2004 control sequence.
  if [[ $TERM == 'cons25' ]] || [[ $TERM == 'dumb' ]]; then
    unset zle_bracketed_paste
  fi

  # The Emacs shell has only limited support for some ZSH features, so use a
  # more limited prompt.
  if [[ $TERM == 'dumb' ]]; then
    PROMPT='%(?..(%?%) )'
    PROMPT+='%n%1v '
    PROMPT+='$(_agkozak_prompt_dirtrim "${AGKOZAK_PROMPT_DIRTRIM:-2}")'
    PROMPT+='$(_agkozak_branch_status) '
    PROMPT+='%# '
  else
    # Avoid continuation lines in Emacs term and ansi-term
    (( $+INSIDE_EMACS )) && ZLE_RPROMPT_INDENT=3

    # When VSCode is using the DOM renderer, the right prompt overflows off the
    # side of the screen
    (( $+VSCODE_PID )) && ZLE_RPROMPT_INDENT=6
  fi

  _agkozak_debug_print "Using async method: ${AGKOZAK[ASYNC_METHOD]}"
}

agkozak-zsh-prompt

############################################################
# Unload function
#
# See https://github.com/zdharma/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc#unload-fun
############################################################
agkozak-zsh-prompt_plugin_unload() {
  setopt LOCAL_OPTIONS NO_KSH_ARRAYS NO_SH_WORD_SPLIT
  local x

  [[ ${AGKOZAK_OLD_OPTIONS[promptsubst]} == 'off' ]] \
    && unsetopt PROMPT_SUBST
  [[ ${AGKOZAK_OLD_OPTIONS[promptbang]} == 'on' ]] \
    && setopt PROMPT_BANG

  PROMPT=${AGKOZAK[OLD_PROMPT]}
  RPROMPT=${AGKOZAK[OLD_RPROMPT]}

  psvar=( $AGKOZAK_OLD_PSVAR )

  add-zsh-hook -D precmd _agkozak_precmd
  add-zsh-hook -D chpwd _agkozak_chpwd

  if is-at-least 5.3; then
    add-zle-hook-widget -D zle-keymap-select _agkozak_zle-keymap-select
  else
    zle -D _agkozak_zle-keymap_select
  fi

  for x in ${=AGKOZAK[FUNCTIONS]}; do
    whence -w $x &> /dev/null && unfunction $x
  done

  zle -N clear-screen clear-screen

  unset AGKOZAK AGKOZAK_ASYNC_FD AGKOZAK_OLD_OPTIONS AGKOZAK_OLD_PSVAR \
    AGKOZAK_PROMPT_WHITESPACE

  unfunction $0
}

# vim: ts=2:et:sts=2:sw=2:
