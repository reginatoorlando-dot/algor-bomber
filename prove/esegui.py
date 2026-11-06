"""Esegue tutte le prove dell'app e del database e dice quali passano.

Uso:  python3 prove/esegui.py              tutte
      python3 prove/esegui.py campo sql    solo quelle con "campo" o "sql" nel nome

Le prove dell'app (prova_*.py) aprono l'app con i dati di esempio in Chrome, come su un telefono;
quelle del database (sql/prova_*.mjs) provano gli script SQL su un Postgres in memoria (PGlite).
Servono Python con playwright e pillow, Chrome, e per il database Node con "npm ci" fatto in prove/sql.
GitHub le esegue da solo a ogni pull request (.github/workflows/prove.yml).
"""
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from comune import serve  # noqa: E402


def main():
    want = [a.lower() for a in sys.argv[1:]]
    pick = lambda name: not want or any(w in name.lower() for w in want)  # noqa: E731
    app = [f for f in sorted(HERE.glob('prova_*.py')) if pick(f.name)]
    sql = [f for f in sorted((HERE / 'sql').glob('prova_*.mjs')) if pick('sql/' + f.name)]
    url, server = serve()
    env = dict(os.environ, PROVE_URL=url, PYTHONUNBUFFERED='1')
    results = []

    def go(name, cmd, cwd):
        # le prove sul telefono simulato dipendono anche dai tempi: una seconda possibilità, segnalata nel riepilogo
        for attempt in (1, 2):
            print(f'\n=== {name}' + (' (secondo tentativo)' if attempt == 2 else ''), flush=True)
            t0 = time.time()
            r = subprocess.run(cmd, cwd=cwd, env=env)
            dt = time.time() - t0
            if r.returncode == 0:
                results.append((name, 'ok' if attempt == 1 else 'ok al secondo tentativo', dt))
                return
        results.append((name, 'FALLITA', dt))

    for f in app:
        go(f.name, [sys.executable, str(f)], HERE)
    if sql:
        node = shutil.which('node')
        if not node or not (HERE / 'sql' / 'node_modules').is_dir():
            msg = 'servono Node e "npm ci" in prove/sql'
            if os.environ.get('CI'):
                results.append(('prove del database', 'FALLITA: ' + msg, 0))
            else:
                print('\nprove del database saltate:', msg)
        else:
            for f in sql:
                go('sql/' + f.name, [node, str(f)], HERE / 'sql')
    server.terminate()

    print('\n=== Riepilogo')
    for name, st, dt in results:
        print(f'  {"✓" if st.startswith("ok") else "✗"} {name:28} {st} ({dt:.0f} s)')
    bad = [r for r in results if not r[1].startswith('ok')]
    print('\n' + ('Tutte le prove sono passate.' if not bad else f'Non passano: {len(bad)}.'))
    sys.exit(1 if bad or not results else 0)


if __name__ == '__main__':
    main()
