#!/usr/bin/env bash

# Window management only makes sense in interactive shells
[[ $- != *i* ]] && return 0

run_tmux
resize_to_full
print_logo
