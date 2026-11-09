#!/bin/bash
cd /home/agent/.claude/jobs/d2d299f1/tmp/review-agent/repo
for m in crop_none crop_flipped no_lock no_apply reset_no_trigger; do
  env -u DISPLAY flock /tmp/julia-suite.lock timeout 30m julia -t 8 --project=/home/agent/.claude/jobs/d2d299f1/tmp/review-agent/env /home/agent/.claude/jobs/d2d299f1/tmp/review-agent/probes/mut.jl $m /home/agent/.claude/jobs/d2d299f1/tmp/review-agent/repo > /home/agent/.claude/jobs/d2d299f1/tmp/review-agent/probes/mut_$m.log 2>&1
  grep -E "MUTATION|Test Summary|Scripting and agent" /home/agent/.claude/jobs/d2d299f1/tmp/review-agent/probes/mut_$m.log | tail -3
done
