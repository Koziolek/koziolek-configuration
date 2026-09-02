# Lista aliasów do różnych poleceń
# Aliasy swoiste dla systemu (in-window, alert, ls --color/-G, time, cozy, iotop,
# fd, fix-net) mieszkają w bash/contexts/{linux,debian,vanilla,darwin,wsl}.sh —
# ładowane po tym pliku i nadpisują wspólne definicje.
# Instalacja `hub` też jest per-kontekst (apt / brew); tu tylko alias, gdy jest.
alias g=git

if command -v hub >/dev/null 2>&1; then
    alias git='hub'
fi

alias gst='git status'

alias workspace="cd $HOME/workspace"
alias ll='ls -al'
alias la='ls -alt'
alias l='ls -CF'

alias ..="cd .."
alias cd..="cd .."

alias pack-repo='rm p p.zip; zip -r p.zip .; base64 p.zip > p; md5sum p p.zip'
alias unpack-repo='base64 --decode p > p.zip; unzip -u p.zip; fd _remot | xargs rm'

# Aliases if you need other fluff
alias order66="exterminatus"
alias omega-protocol="exterminatus"
alias claude-local='ANTHROPIC_BASE_URL="http://localhost:11434" ANTHROPIC_API_KEY="ollama" claude --model qwen3-coder'
alias rc="reload_config"
