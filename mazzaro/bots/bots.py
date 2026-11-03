"""mazzabots - sobe os bots roleplay do MazzaRO no mazzakore.

Uso (da pasta do mazzakore, <ws>\\openkore):
  python -I mazzaro\\bots\\bots.py aldren                 # sobe o Aldren numa janela de console propria
  python -I mazzaro\\bots\\bots.py aldren outro ...       # varios bots, um console cada
  python -I mazzaro\\bots\\bots.py aldren --oculto        # sem janela (log em run\\logs\\bots\\aldren)
  python -I mazzaro\\bots\\bots.py aldren --esperar       # fica esperando o OpenKore sair
  python -I mazzaro\\bots\\bots.py --listar               # bots disponiveis
  python -I mazzaro\\bots\\bots.py --criar-conta aldren   # cria a conta no banco local (ver servidor\\README.md)

Cada bot e uma pasta mazzaro\\bots\\<bot>\\ com bot.yml (perfil, conta, personagem) e control\\ (config.txt so com
o que muda sobre o padrao, jornada.txt, falas.txt, mon_control.txt, pickupitems.txt).

Como o tools\\mz\\kore.py do mazzaro, nada e escrito no clone: o config final, o sys.txt e o servers.txt sao gerados
em <ws>\\run\\bots\\<bot>\\ e entram na frente via --control/--tables. O config gerado so tem dois !include (o padrao
do clone e o do bot) e o que vem do bot.yml; as mudancas que o OpenKore grava em tempo de execucao (lockMap etc.)
ficam nele. Logs e o estado da jornada (jornada_<personagem>.txt) em <ws>\\run\\logs\\bots\\<bot>\\.

Usa do mazzaro (so leitura): server\\profiles\\<perfil>.yml (bloco openkore:) e tools\\mz\\profiles.py (perfil no ar).
"""
import argparse
import os
import re
import secrets
import socket
import string
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

BOTS = Path(__file__).resolve().parent            # <mazzakore>\mazzaro\bots
KORE = BOTS.parents[1]                            # <mazzakore>
WS = KORE.parent                                  # workspace
MZ = WS / 'mazzaro'                               # repo mazzaro (perfis, tools)
NO_WINDOW, NEW_CONSOLE = 0x08000000, 0x10
PLUGINS = 'mazzaJornada,raiseStat,raiseSkill,mzctl'
CTL_BASE = 6960                                   # mzctl de cada bot: bot.yml "ctl:" ou 6960 + posicao na lista

sys.path.insert(0, str(MZ / 'tools' / 'mz'))
try:
    import profiles  # noqa: E402  (mazzaro/tools/mz/profiles.py)
except ImportError:
    profiles = None


def bots_disponiveis():
    return sorted(p.parent.name for p in BOTS.glob('*/bot.yml'))


def carregar_bot(nome):
    path = BOTS / nome / 'bot.yml'
    if not path.exists():
        sys.exit(f'bot desconhecido: {nome} (existentes: {", ".join(bots_disponiveis()) or "nenhum"})')
    bot = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
    for k in ('perfil', 'conta', 'personagem'):
        if k not in bot:
            sys.exit(f'{path}: falta "{k}"')
    return bot


def porta_ctl(nome, bot):
    """Porta do mzctl do bot (tools/mz/kore_cmd.py --porta N no mazzaro)."""
    return int(bot.get('ctl') or CTL_BASE + bots_disponiveis().index(nome))


def carregar_perfil(pid):
    if profiles is None:
        sys.exit(f'mazzaro nao encontrado em {MZ} (precisa de tools\\mz\\profiles.py e server\\profiles\\)')
    prof = profiles.load(pid)
    if 'openkore' not in prof:
        sys.exit(f'perfil {pid} nao tem bloco openkore (o mazzakore nao fala esse protocolo)')
    return prof


def porta_aberta(port, host='127.0.0.1'):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.3)
    try:
        return s.connect_ex((host, port)) == 0
    finally:
        s.close()


def segredo(nome):
    """Senha da conta do bot: gerada uma vez, fora do git (run\\bots\\<bot>\\conta.yml)."""
    path = WS / 'run' / 'bots' / nome / 'conta.yml'
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return yaml.safe_load(path.read_text(encoding='utf-8'))['senha']
    pw = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(14))
    path.write_text('# senha local da conta do bot (gerada por mazzaro/bots/bots.py); so existe no banco local\n'
                    + yaml.safe_dump({'senha': pw}), encoding='utf-8')
    return pw


def sobrepor(texto, valores):
    """Troca 'chave ...' num arquivo de controle do OpenKore; o que nao existir vai para o fim (como o kore.py)."""
    linhas, vistas = texto.splitlines(), set()
    for i, l in enumerate(linhas):
        m = re.match(r'^(\S+)(\s|$)', l)
        if m and m.group(1) in valores and m.group(1) not in vistas:
            linhas[i] = f'{m.group(1)} {valores[m.group(1)]}'.rstrip()
            vistas.add(m.group(1))
    extra = [f'{k} {v}'.rstrip() for k, v in valores.items() if k not in vistas]
    if extra:
        linhas += ['', '# --- mazzabots (gerado por mazzaro/bots/bots.py) ---'] + extra
    return '\n'.join(linhas) + '\n'


def server_block(prof, name):
    """Mesmo bloco que o tools/mz/kore.py do mazzaro gera para o perfil."""
    ok = prof['openkore']
    keys = {
        'ip': '127.0.0.1', 'port': prof['portas']['login'], 'private': 1, 'master_version': 1, 'version': 55,
        'serverType': ok['serverType'], 'serverEncoding': 'Western', 'addTableFolders': ok['tables'],
        'charBlockSize': ok.get('charBlockSize', ''), 'masterLogin_packet': ok.get('masterLogin_packet', '0064'),
        'fieldsFolder': WS / 'run' / 'kore' / 'fields',
    }
    keys.update(ok.get('extra', {}) or {})
    return f'[{name}]\n' + ''.join(f'{k} {v}\n' for k, v in keys.items() if v != '')


def preparar(nome, bot, prof):
    """Gera run\\bots\\<bot>\\{control,tables}; devolve (control, tables, logs)."""
    gen = WS / 'run' / 'bots' / nome
    ctl, tbl = gen / 'control', gen / 'tables'
    logs = WS / 'run' / 'logs' / 'bots' / nome
    for d in (ctl, tbl, logs):
        d.mkdir(parents=True, exist_ok=True)

    # campos dos mapas mz* (zonas de 2001) e tabelas pt-BR: os mesmos que o mz kore usa
    fields = WS / 'run' / 'kore' / 'fields'
    if not any(fields.glob('*.fld2')):
        subprocess.run([sys.executable, '-I', str(MZ / 'tools' / 'kore_fields.py'), '--saida', str(fields)],
                       check=True, stdout=subprocess.DEVNULL)
    if not (KORE / 'tables' / 'mazzaro' / 'items.txt').exists():
        subprocess.run([sys.executable, '-I', str(MZ / 'tools' / 'kore_tables.py')], check=True,
                       stdout=subprocess.DEVNULL)

    server_name = f'Mazzaro {bot["perfil"]}'
    pj = bot['personagem']
    # relativo a pasta do config gerado: o File::Spec do start.exe nao reconhece "C:/..." como absoluto e o
    # junta com a pasta do arquivo ("Nao foi possivel recarregar ... control\C:/...")
    inc = lambda p: '!include ' + os.path.relpath(p, ctl).replace('\\', '/')
    linhas = [
        f'# GERADO por mazzaro/bots/bots.py para o bot "{nome}" - nao editar (regerado a cada execucao).',
        '# Edite mazzaro/bots/<bot>/control/config.txt e bot.yml no mazzakore.',
        inc(KORE / 'control' / 'config.txt'),
        inc(BOTS / nome / 'control' / 'config.txt'),
        f'master {server_name}',
        'server 0',
        f'username {bot["conta"]}',
        f'password {segredo(nome)}',
        f'char {pj.get("slot", 0)}',
        f'mazzaJornada_personagem {pj["nome"]}',
        f'mazzaJornada_sexo {pj.get("sexo", "M")}',
        f'mazzaJornada_cabelo {pj.get("cabelo", 1)}',
        f'mazzaJornada_corCabelo {pj.get("cor_cabelo", 0)}',
        # o padrao do clone espera Enter no "Bye!" e grava portais descobertos no clone
        'dcPause 0',
        'portalRecord 0',
        'logConsole 1',
        f'mzctl_porta {porta_ctl(nome, bot)}',
    ]
    (ctl / 'config.txt').write_text('\n'.join(linhas) + '\n', encoding='utf-8')
    sysv = {'loadPlugins': 2, 'loadPlugins_list': PLUGINS, 'skipPlugins_list': '',
            'sendAnonymousStatisticReport': 0, 'wxHideConsole': 0}
    padrao = (KORE / 'control' / 'sys.txt').read_text(encoding='utf-8', errors='replace')
    (ctl / 'sys.txt').write_text(sobrepor(padrao, sysv), encoding='utf-8')
    (tbl / 'servers.txt').write_text(server_block(prof, server_name), encoding='utf-8')
    return ctl, tbl, logs


def subir(nome, oculto=False, esperar=False):
    bot = carregar_bot(nome)
    prof = carregar_perfil(bot['perfil'])
    no_ar = profiles.detect()['perfil']
    if no_ar != bot['perfil']:
        sys.exit(f'{nome}: perfil no ar = {no_ar or "nenhum"}, o bot pede {bot["perfil"]} '
                 f'(no mazzaro: .\\mz.ps1 up {bot["perfil"]})')
    if not porta_aberta(prof['portas']['login']):
        sys.exit(f'{nome}: login-server fechado na porta {prof["portas"]["login"]}')
    start = KORE / 'start.exe'
    if not start.exists():
        sys.exit(f'start.exe ausente em {KORE}')
    ctl, tbl, logs = preparar(nome, bot, prof)
    cmd = [str(start),
           f'--control={ctl};{BOTS / nome / "control"};{KORE / "control"}',
           f'--tables={tbl};{KORE / "tables"}',
           f'--plugins={KORE / "plugins"}',
           f'--logs={logs}', '--interface=Console']
    p = subprocess.Popen(cmd, cwd=str(KORE), creationflags=NO_WINDOW if oculto else NEW_CONSOLE)
    print(f'{nome}: OpenKore pid {p.pid} no {bot["perfil"]} (conta {bot["conta"]}, personagem {bot["personagem"]["nome"]})')
    print(f'  log: {logs}  |  estado: python -I tools\\mz\\kore_cmd.py --estado --porta {porta_ctl(nome, bot)} (no mazzaro)')
    if esperar:
        print(f'  saiu com {p.wait()}')


def criar_conta(nome, grupo):
    """Cria a conta do bot no banco local (como o tools/mz/conta_teste.py do mazzaro: senha em MD5, use_MD5_passwords).
    O personagem o plugin cria."""
    bot = carregar_bot(nome)
    cred = dict(l.split('=', 1) for l in (WS / 'mariadb' / 'credentials.local.txt').read_text().splitlines()
                if '=' in l and not l.startswith('#'))

    def sql(q):
        with tempfile.NamedTemporaryFile('w', suffix='.cnf', delete=False) as f:
            f.write(f"[client]\nuser=ragnarok\npassword={cred['ragnarok']}\nhost=127.0.0.1\n")
            cnf = f.name
        try:
            r = subprocess.run([str(WS / 'mariadb' / 'bin' / 'mariadb.exe'), f'--defaults-extra-file={cnf}',
                                '--batch', '--skip-column-names', 'ragnarok', '-e', q], capture_output=True, text=True)
        finally:
            Path(cnf).unlink()
        if r.returncode:
            sys.exit(f'mariadb: {r.stderr.strip()}')
        return r.stdout.strip()

    conta, pw = bot['conta'], segredo(nome)
    sexo = 'F' if str(bot['personagem'].get('sexo', 'M')).upper().startswith('F') else 'M'
    if not sql(f"SELECT account_id FROM login WHERE userid='{conta}'"):
        sql(f"INSERT INTO login (userid, user_pass, sex, email, group_id) "
            f"VALUES ('{conta}', MD5('{pw}'), '{sexo}', 'bot@mazzaro.local', {grupo})")
    else:
        sql(f"UPDATE login SET user_pass=MD5('{pw}'), group_id={grupo} WHERE userid='{conta}'")
    aid = sql(f"SELECT account_id FROM login WHERE userid='{conta}'")
    print(f'conta {conta} (account_id {aid}, group {grupo}); senha em run\\bots\\{nome}\\conta.yml')


def main():
    sys.stdout.reconfigure(line_buffering=True, errors='replace')
    ap = argparse.ArgumentParser(description='bots roleplay do MazzaRO')
    ap.add_argument('bots', nargs='*')
    ap.add_argument('--oculto', action='store_true', help='sem janela de console')
    ap.add_argument('--esperar', action='store_true', help='espera o OpenKore sair (um bot so)')
    ap.add_argument('--listar', action='store_true')
    ap.add_argument('--criar-conta', metavar='BOT')
    ap.add_argument('--grupo', type=int, default=5, help='group_id da conta (padrao 5 = Bot, servidor\\groups.yml)')
    a = ap.parse_args()
    if a.listar:
        for n in bots_disponiveis():
            b = carregar_bot(n)
            print(f'{n:16} {b.get("descricao", "")} [{b["perfil"]}]')
        return
    if a.criar_conta:
        criar_conta(a.criar_conta, a.grupo)
        return
    if not a.bots:
        ap.error('diga qual bot subir (ou --listar)')
    for n in a.bots:
        subir(n, a.oculto, a.esperar and len(a.bots) == 1)


if __name__ == '__main__':
    main()
