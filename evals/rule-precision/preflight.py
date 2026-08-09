#!/usr/bin/env python3
"""Will this batch of agents fit in the five-hour window? Ask BEFORE launching.

Round 20 launched 108 review agents without checking, exhausted the five-hour
window part way through, and lost fourteen agents mid-flight. The usage log
existed the whole time and had the numbers in it. This is the check that was
missing.

CALIBRATION, and the reason it is not just "agents times a constant". Over round
20 the five-hour window went 1% to 100% while the weekly window moved 19 points,
so one weekly point is worth about 5.2 five-hour points. But 108 review agents
cost only 13 weekly points, which would be ~68 five-hour points — and the window
still ran out. The rest is the ORCHESTRATOR: this conversation re-sends its
whole context every turn, and a long round makes that the dominant term, not a
rounding error. The constant below therefore folds in what the main loop spends
alongside its agents, measured on round 20 rather than reasoned about.

It follows that the constant is only valid for rounds shaped like this one —
long orchestration, ~90k-token review agents. Re-derive it with --calibrate when
the shape changes, and treat a batch that needs more than SAFETY of the
remaining window as not fitting.

Usage:
  preflight.py <n_agents>          # GO or WAIT, with the arithmetic
  preflight.py --calibrate         # re-derive the constant from the log
"""
import datetime
import json
import os
import pathlib
import sys

LOG = pathlib.Path(os.environ.get('CLAUDE_USAGE_LOG',
                                  pathlib.Path.home() / '.claude/usage-log.jsonl'))
POINTS_PER_AGENT = 1.5      # five-hour points, orchestrator overhead included
SAFETY = 0.80               # never plan to use the last fifth of the window


def samples():
    if not LOG.exists():
        sys.exit(f'no usage log at {LOG} — run scripts/install-usage-poller.sh')
    rows = [json.loads(l) for l in LOG.read_text().splitlines() if l.strip()]
    have = [r for r in rows if r.get('five_hour')]
    if not have:
        sys.exit('usage log has no five-hour window readings')
    return have


def main():
    rows = samples()
    last = rows[-1]
    used = last['five_hour']['used_percentage']
    reset = datetime.datetime.fromtimestamp(last['five_hour']['resets_at'])
    now = datetime.datetime.now()
    age = (now - datetime.datetime.strptime(last['at'], '%Y-%m-%dT%H:%M:%SZ')
           .replace(tzinfo=datetime.timezone.utc).astimezone().replace(tzinfo=None))

    if '--calibrate' in sys.argv:
        first, final = rows[0], rows[-1]
        d5 = final['five_hour']['used_percentage'] - first['five_hour']['used_percentage']
        d7 = final['seven_day']['used_percentage'] - first['seven_day']['used_percentage']
        print(f'{first["at"]} .. {final["at"]}')
        print(f'  five-hour moved {d5:+.0f}, weekly moved {d7:+.0f}')
        if d7:
            print(f'  1 weekly point ~= {d5 / d7:.1f} five-hour points')
        print('\nThe five-hour window resets, so it only calibrates within one window.'
              '\nDivide an observed five-hour rise by the agents launched inside THAT'
              '\nwindow, and keep the orchestrator in the numerator.')
        return

    if len(sys.argv) < 2 or not sys.argv[1].isdigit():
        sys.exit('usage: preflight.py <n_agents> | --calibrate')
    n = int(sys.argv[1])

    # An old row is not stale by itself: the log appends only on change, so a
    # row that has not moved says the figure has not moved, and `resets_at` is
    # in it either way. What DOES invalidate the row is the window turning over
    # underneath it — then `used` describes a window that no longer exists. In
    # that one case take a reading rather than warn about the old one.
    if reset <= now:
        poll = pathlib.Path.home() / '.claude/hooks/claude-usage-poll.sh'
        if poll.exists():
            print(f'window rolled over at {reset:%H:%M}; taking a fresh reading')
            os.system(f'bash {poll} >/dev/null 2>&1')
            last = samples()[-1]
            used = last['five_hour']['used_percentage']
            reset = datetime.datetime.fromtimestamp(last['five_hour']['resets_at'])
        else:
            sys.exit(f'window rolled over at {reset:%H:%M} and no poller to re-read it')
    elif age > datetime.timedelta(hours=6):
        print('WARNING: no reading this window at all — check the poller is running.\n')

    headroom = 100.0 - used
    budget = headroom * SAFETY
    cost = n * POINTS_PER_AGENT
    fits = int(budget / POINTS_PER_AGENT)

    print(f'five-hour window   {used:.0f}% used, {headroom:.0f} points left, '
          f'resets {reset:%H:%M} ({str(reset - now).split(".")[0]} from now)')
    print(f'planned            {n} agents x {POINTS_PER_AGENT} = {cost:.0f} points')
    print(f'budget at {SAFETY:.0%}      {budget:.0f} points, i.e. about {fits} agents\n')

    if cost <= budget:
        print(f'GO — {n} agents fit with {budget - cost:.0f} points of the budget to spare.')
    else:
        print(f'WAIT — {n} agents need {cost - budget:.0f} points more than the budget.')
        print(f'  Either launch at most {fits} now and the rest after {reset:%H:%M},')
        print(f'  or wait for the reset and launch all {n} then.')
        print('\nA round whose arms would be split across that boundary should wait:')
        print('an arm left short by an exhausted window is a missing reply, and round 17')
        print('showed that a missing reply is found late or not at all.')


if __name__ == '__main__':
    main()
