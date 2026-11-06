#!/bin/bash
# runs each probe with the environments named in ENVS (local reg oldsrc-local oldsrc-reg), under the suite lock
R=/home/agent/.claude/jobs/d2d299f1/tmp/review-ps3e
cd $R/probes
for p in "$@"; do
  for e in ${ENVS:-local reg}; do
    case $e in local) env=$R/env;; reg) env=$R/repo/test;; oldsrc-local) env=$R/env-old;; oldsrc-reg) env=$R/wt-oldsrc/test;; esac
    DISPLAY=:99 flock /tmp/julia-suite.lock timeout 20m julia -t 4 --project=$env $p.jl > $p.$e.out 2>&1
    echo "exit=$?" >> $p.$e.out
  done
done
