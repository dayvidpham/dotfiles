#!/usr/bin/env zsh

# Only execute this file once per shell.
if [ ! -n "${__COMPINIT_WAS_RUN-}" ]; then 
    __COMPINIT_WAS_RUN=1

    ZDOTDIR="${ZDOTDIR:-$HOME}"
    ZSH_COMPDUMP="${ZSH_COMPDUMP:-${ZDOTDIR}/.zcompdump}"

    # autoload:
    #   -U: do not expand aliases
    #   -z: autoload using zsh style (?)
    autoload -Uz compinit bashcompinit

    # compinit:
    #   -u flag: use files in insecure directories without asking

    # Run faster compinit with -C, only check for new functions? don't re-check existing?
    #   Can be a source of bugs: if new completions added, will not be available
    if [[ "$ZSH_COMPDUMP"(N.mh+8) ]]; then
      compinit -C -d "$ZSH_COMPDUMP"
    else
      compinit -u -d "$ZSH_COMPDUMP"; touch "$ZSH_COMPDUMP"
    fi

    bashcompinit

    {
      autoload -Uz zcompile
      zcompare() {
        if [[ -s "${1}" && ( ! -s "${1}".zwc || "${1}" -nt "${1}".zwc) ]]; then
          zcompile "${1}"
        fi
      }

      # compile everything
      zcompare "${ZDOTDIR}/.zcompdump}"
      zcompare "${ZDOTDIR}/.zshrc}"
      zcompare "${ZDOTDIR}/.zprofile}"
      zcompare "${ZDOTDIR}/.zlogin}"
      zcompare "${ZDOTDIR}/.zshenv}"
    } &!
fi




# Pulled from: https://medium.com/@voyeg3r/holy-grail-of-zsh-performance-a56b3d72265d
#
# Function to determine the need of a zcompile. If the .zwc file
# does not exist, or the base file is newer, we need to compile.
# These jobs are asynchronous, and will not impact the interactive shell

# zcompare() {
#   if [[ -s ${1} && ( ! -s ${1}.zwc || ${1} -nt ${1}.zwc) ]]; then
#     zcompile ${1}
#   fi
# }

# zim_mods=${ZDOTDIR:-${HOME}}/**/

# zcompile the completion cache; siginificant speedup.
# for file in ${ZDOTDIR:-${HOME}}/.zcomp^(*.zwc)(.); do
#   zcompare ${file}
# done

# # zcompile .zshrc
# zcompare ${ZDOTDIR:-${HOME}}/.zshrc
#
# # zcompile some light module init scripts
# zcompare ${zim_mods}/git/init.zsh
# zcompare ${zim_mods}/utility/init.zsh
# zcompare ${zim_mods}/pacman/init.zsh
# zcompare ${zim_mods}/spectrum/init.zsh
# zcompare ${zim_mods}/completion/init.zsh
# zcompare ${zim_mods}/fasd/init.zsh
#
# # zcompile all .zsh files in the custom module
# for file in ${zim_mods}/custom/**/^(README.md|*.zwc)(.); do
#   zcompare ${file}
# done
#
# # zcompile all autoloaded functions
# for file in ${zim_mods}/**/functions/^(*.zwc)(.); do
#   zcompare ${file}
# done
#
# # syntax-highlighting
# for file in ${zim_mods}/syntax-highlighting/external/highlighters/**/*.zsh; do
#   zcompare ${file}
# done
# zcompare ${zim_mods}/syntax-highlighting/external/zsh-syntax-highlighting.zsh
# 
# # zsh-histery-substring-search
# zcompare ${zim_mods}/history-substring-search/external/zsh-history-substring-search.zsh
# 
