# A greetd session can omit /usr/local/bin and ~/.local/bin.
# Keep both on PATH for fish terminals started from Apollo.
if not contains -- $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end
if not contains -- /usr/local/bin $PATH
    set -gx PATH /usr/local/bin $PATH
end
