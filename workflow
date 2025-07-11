#!/bin/bash

SESSION="main"

tmux has-session -t $SESSION 2>/dev/null
if [ $? != 0 ]; then
  tmux new-session -d -s $SESSION -n ' config'
  tmux new-window -t $SESSION:2 -n ' diary' 'weekly'
  tmux split-window -h -t $SESSION:2 'diary'
  tmux new-window -t $SESSION:3 -n ' notes' 'note'

  tmux select-window -t $SESSION:2
fi

tmux attach -t $SESSION

