import json
import os
import sys
import time

mode, audit = sys.argv[1:]
with open(audit, 'a') as f:
    f.write('pid:' + str(os.getpid()) + '\n')
for line in sys.stdin:
    request = json.loads(line)
    kind = request['type']
    with open(audit, 'a') as f:
        f.write(kind + '\n')
    result = dict(id=request['id'], ok=True, status='ready')
    if kind == 'apply':
        if mode == 'partial':
            result.update(ok=False, error='input_partial')
        elif mode == 'secret':
            result.update(ok=False, error='private-text-must-not-escape')
        elif mode == 'wrong_id':
            result['id'] = '00000000-0000-0000-0000-000000000000'
        elif mode == 'not_ready':
            result['status'] = 'permission_denied'
        elif mode == 'oversized':
            print('x' * 10000, flush=True)
            continue
        elif mode == 'eof':
            break
        elif mode == 'blocked':
            time.sleep(30)
    print(json.dumps(result), flush=True)
    if kind == 'status' and mode in ('blocked_write', 'closed_input'):
        if mode == 'closed_input':
            os.close(0)
        time.sleep(30)
    if kind == 'quit':
        break
