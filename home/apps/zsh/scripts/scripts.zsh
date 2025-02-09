for file in $HOME/.config/zsh/plugins/my-zsh-scripts/*.zsh; do
  [[ "$file" == "$HOME/.config/zsh/plugins/my-zsh-scripts/scripts.zsh" ]] && continue  
  source "$file"
done
