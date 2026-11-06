#!/bin/bash
# runs each probe with both environments, under the suite lock
R=/home/agent/.claude/jobs/d2d299f1/tmp/review-ps3e
cd $R/probes
for p in "$@"; do
  for e in local reg; do
    env=$R/env; [ $e = reg ] && env=$R/repo/test
    DISPLAY=:99 flock /tmp/julia-suite.lock timeout 20m julia -t 4 --project=$env $p.jl > $p.$e.out 2>&1
    echo "exit=$?" >> $p.$e.out
  done
done
