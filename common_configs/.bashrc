# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
    *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
	xterm*|rxvt*)
		PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
		;;
	*)
		;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  	if [ -f /usr/share/bash-completion/bash_completion ]; then
    	. /usr/share/bash-completion/bash_completion
  	elif [ -f /etc/bash_completion ]; then
	    . /etc/bash_completion
  	fi
fi

# Function to determine Docker installation type
detect_docker_install_type() {
	# Check if docker is installed
	if ! command -v docker &> /dev/null; then
		DOCKER_TYPE="none"
		DOCKER_SOCK=""
		return
	else
		local DOCKER_CONTEXT
		local SOCKET
		DOCKER_CONTEXT=$(docker context show 2>/dev/null)
		SOCKET=$(docker context inspect "${DOCKER_CONTEXT:-default}" --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
		case "$SOCKET" in
			unix:///run/user/*/docker.sock)
				DOCKER_TYPE="rootless"
				DOCKER_SOCK=$(expr "$SOCKET" : 'unix://\(.*\)')		## Strip out the unix prefix
				;;
			unix://*)
				DOCKER_TYPE="rootful"
				DOCKER_SOCK=$(expr "$SOCKET" : 'unix://\(.*\)')		## Strip out the unix prefix
				;;
			*)
				DOCKER_TYPE="unknown (unexpected context: $DOCKER_CONTEXT)"
				DOCKER_SOCK="$SOCKET"
				;;
		esac
	fi
}

####### Variable used for Docker #######
## HOST_IP: Check that the Interface (eth0, ens0) is correct or updated
# export HOST_IFACE=ens18																			## User defined specific interface to use
# export HOST_IFACE=$(ip -o link show | awk -F': ' '!/lo/ {print $2; exit}')		## Pick the first non-loopback interface
export HOST_IFACE=$(ip route show default | awk '{print $5}')									## Pick the default route interface
export HOST_IP=$(ip -o -4 addr show dev "$HOST_IFACE" | awk '{print $4}' | cut -d/ -f1)

export HOSTNAME=${HOSTNAME}
export TZ="Europe/Berlin"

## Determine and export Docker install type variables
detect_docker_install_type
export DOCKER_TYPE
export DOCKER_SOCK

export PUID=$(id -u $USER)
export PGID=$(id -g $USER)
export PUID_DOCKER=$PUID
export PGID_DOCKER=$PGID
## If a docker user and group has been created.
# export PUID_DOCKER=$(id -u docker)
# export PGID_DOCKER=$(getent group docker | awk -F: '{printf "%d", $3}')


export DOCKER_VOLUMES="/home/${USER}/docker/volumes"
export DOCKER_SECRETS="/home/${USER}/docker/.secrets"

export DOMAIN_NAME=$(cat ${DOCKER_SECRETS}/domain_name_personal_public)
export INTERNAL_DOMAIN_NAME=$(cat ${DOCKER_SECRETS}/domain_name_personal_internal)

## Service specific variables
export TRAEFIK_URL_NAS_PUBLIC_FILE=$(cat ${DOCKER_SECRETS}/nas_3P_public__domain_url)
