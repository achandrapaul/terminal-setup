_espanso_trigger_widget() {
  local current_word=${LBUFFER##*[[:space:]]}
  if [[ $current_word != \** ]]; then
    zle fzf-tab-complete
    return
  fi

  local selection trigger
  local -a fzf_flags
  zstyle -a ':fzf-tab:*' fzf-flags fzf_flags
  selection=$(espanso match list 2>/dev/null | fzf "${fzf_flags[@]}" --query "$current_word" --select-1)
  if [[ -z $selection ]]; then
    zle reset-prompt
    return
  fi

  trigger=${${selection%% - *}%%,*}
  LBUFFER=${LBUFFER:0:$(( ${#LBUFFER} - ${#current_word} ))}
  zle reset-prompt
  ( sleep 0.15; espanso match exec -t "$trigger" ) >/dev/null 2>&1 &!
}
zle -N _espanso_trigger_widget
