"""Pass/fail for a kemu.py log: kemu prints results next to the expected
values; this checks them.

usage: check_kemu.py KEMU_LOG fm|io
"""
import re
import sys

log_path, core = sys.argv[1:3]
text = open(log_path).read()
errors = []

def need(pattern, what):
    if not re.search(pattern, text, re.M):
        errors.append('missing: ' + what)

need(r'^identify OK: .*MCU=upc_%s ' % core, 'identify of upc_%s' % core)
need(r'^heartbeat \d+ state 1$', 'final heartbeat with the core running')

if core == 'fm':
    pairs = re.findall(r'(-?\d+) steps \(expected (-?\d+)\)', text)
    pairs += re.findall(r'position (-?\d+) \(expected (-?\d+)\)', text)
    if len(pairs) < 10:
        errors.append('only %d step/position checks found' % len(pairs))
    for got, want in pairs:
        if got != want:
            errors.append('got %s, expected %s' % (got, want))
    for n in re.findall(r'overruns (\d+)', text):
        if n != '0':
            errors.append('engine overruns: ' + n)
    need(r'^after slow then fast: is_shutdown 0$', 'no shutdown after slow then fast')
    need(r'^trsync stop: \d+ of 300 steps, 0 after the stop', 'no steps after a trsync stop')
    m = re.search(r'trsync stop: .* position (-?\d+) \(expected (-?\d+)\)', text)
    if not m or m.group(1) != m.group(2):
        errors.append('position after the trsync stop')
else:
    need(r'adc0 = 4800 \(expect', 'adc0 sum 4800')
    need(r'adc1 = 2400 \(expect', 'adc1 sum 2400')

if errors:
    print('kemu %s FAILED:\n  %s' % (core, '\n  '.join(errors)))
    sys.exit(1)
print('kemu %s passed' % core)
