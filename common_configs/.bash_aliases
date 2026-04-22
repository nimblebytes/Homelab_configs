alias grep='grep --color=auto'
alias ls='ls -l --color=auto'
alias la='ls -al --color=auto'

##Docker Container build info
alias dls='docker ps -a --format "table {{.State}}\t{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}"'
##Docker Container network info
alias dlsn='docker ps -a --format "table {{.State}}\t{{.ID}}\t{{.Names}}\t{{.Networks}}"'
##Docker Container network + port info
alias dlsnp='docker ps -a --format "table {{.State}}\t{{.ID}}\t{{.Names}}\t{{.Networks}}\t{{.Ports}}"'