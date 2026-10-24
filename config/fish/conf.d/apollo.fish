# greetd often omits /usr/local/bin. fish then reports
# "Unknown command: apollo-theme-nt" inside kitty.
if not contains -- $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end
if not contains -- /usr/local/bin $PATH
    set -gx PATH /usr/local/bin $PATH
end
