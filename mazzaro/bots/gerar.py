"""Gerador dos bots roleplay a partir dos modelos de build (mazzaro/bots/modelos) e personalidades
(mazzaro/bots/personalidades). Usado pelo bots.py (--novo, --validar, --modelos); nada aqui sobe OpenKore.

Um modelo (modelos/<id>.yml) tem: nome, classes (ids do caminho, ex. [0, 1, 7]), troca_classe {id: job lv minimo},
stats (statsAddAuto_list), skills (skillsAddAuto_list, na ordem em que um jogador gastaria os pontos), config (blocos
crus do OpenKore) e etapas ("<lvMin> <lvMax> <classes> <mapa> <cidade-base>").

A validacao simula o raiseSkill contra a skill_tree pre-renewal do mazzathena: o plugin para de distribuir quando a
proxima skill da lista ainda nao pode ser aprendida, entao a ordem precisa respeitar pre-requisitos e os pontos de
cada classe (Aprendiz 9; primeira classe = job da troca - 1; segunda classe 49).
"""
import random
import re
from pathlib import Path

import yaml

BOTS = Path(__file__).resolve().parent
MODELOS = BOTS / 'modelos'
PERSONALIDADES = BOTS / 'personalidades'
WS = BOTS.parents[2]
SKILL_TREE = WS / 'rathena-2026' / 'db' / 'pre-re' / 'skill_tree.yml'
MAPS_YML = WS / 'mazzaro' / 'episodes' / 'data' / 'maps.yml'

JOBS = {0: 'Novice', 1: 'Swordman', 2: 'Mage', 3: 'Archer', 4: 'Acolyte', 5: 'Merchant', 6: 'Thief',
        7: 'Knight', 8: 'Priest', 9: 'Wizard', 10: 'Blacksmith', 11: 'Hunter', 12: 'Assassin'}

# instrutores do npc/custom/mazzaro/mazzabots.txt (overlay do mazzaro): classe de destino -> mapa x y
INSTRUTORES = {
    1: ('izlude_in', 72, 170), 2: ('geffen_in', 162, 122), 3: ('payon_in02', 66, 73),
    4: ('prt_church', 186, 39), 5: ('alberta_in', 56, 39), 6: ('moc_prydb1', 40, 125),
    7: ('prt_in', 85, 99), 8: ('prt_church', 18, 39), 9: ('gef_tower', 107, 33),
    10: ('geffen', 44, 162), 11: ('in_hunter', 97, 101), 12: ('in_moc_16', 17, 31),
}


def modelos_disponiveis():
    return sorted(p.stem for p in MODELOS.glob('*.yml'))


def personalidades_disponiveis():
    return sorted(p.stem for p in PERSONALIDADES.glob('*.txt'))


def carregar_modelo(mid):
    path = MODELOS / f'{mid}.yml'
    if not path.exists():
        raise SystemExit(f'modelo desconhecido: {mid} (existentes: {", ".join(modelos_disponiveis())})')
    return yaml.safe_load(path.read_text(encoding='utf-8'))


def _arvore():
    body = yaml.safe_load(SKILL_TREE.read_text(encoding='utf-8'))['Body']
    return {e['Job']: {s['Name']: s for s in e.get('Tree') or []} for e in body}


def _lista(texto):
    out = []
    for item in re.split(r'\s*,\s*', ' '.join(str(texto).split())):
        if item:
            nome, _, lv = item.rpartition(' ')
            out.append((nome, int(lv)))
    return out


def validar(mid):
    """Lista de problemas do modelo (vazia = ok)."""
    m = carregar_modelo(mid)
    erros = []
    arvore = _arvore()
    caminho = m['classes']
    troca = {int(k): int(v) for k, v in (m.get('troca_classe') or {}).items()}
    pontos = {0: 9}
    for i, cid in enumerate(caminho[1:], 1):
        prox = caminho[i + 1] if i + 1 < len(caminho) else None
        pontos[cid] = (troca.get(prox, 50) if prox is not None else 50) - 1
        if cid not in INSTRUTORES:
            erros.append(f'classe {cid} sem instrutor em mazzabots.txt')
    dono = {}
    for cid in caminho:
        for nome in arvore.get(JOBS[cid], {}):
            dono.setdefault(nome, cid)
    # simula o raiseSkill: gasta os pontos de cada classe na ordem da lista; skill de classe anterior pode ser comprada
    # com pontos da seguinte (o excedente da 1a classe vira skill aprendida depois da troca). Trava de verdade: a
    # proxima skill da lista ser de uma classe que ainda nao chegou com pontos sobrando - o bot fica parado com
    # pontos e o NPC de troca recusa.
    etapa = 0
    resta = pontos[caminho[0]]
    nivel = {}
    for nome, lv in _lista(m['skills']):
        cid = dono.get(nome)
        if cid is None:
            erros.append(f'{nome}: nao existe na arvore de {"/".join(JOBS[c] for c in caminho)}')
            continue
        info = arvore[JOBS[cid]][nome]
        if lv > info['MaxLevel']:
            erros.append(f'{nome} {lv}: maximo {info["MaxLevel"]}')
        for req in info.get('Requires') or []:
            if nivel.get(req['Name'], 0) < req['Level']:
                erros.append(f'{nome} {lv}: pede {req["Name"]} {req["Level"]} antes (tem {nivel.get(req["Name"], 0)})')
        precisa = caminho.index(cid)
        if precisa > etapa:
            if resta:
                erros.append(f'{nome}: e de {JOBS[cid]} mas {JOBS[caminho[etapa]]} ainda tem {resta} ponto(s) - '
                             f'o bot trava com pontos e o NPC de troca recusa')
            etapa, resta = precisa, pontos[cid]
        custo = max(0, lv - nivel.get(nome, 0))
        nivel[nome] = max(lv, nivel.get(nome, 0))
        while custo > resta and etapa + 1 < len(caminho):
            custo -= resta
            etapa += 1
            resta = pontos[caminho[etapa]]
        if custo > resta:
            erros.append(f'{nome}: sem pontos (lista maior que job 50 permite)')
            resta = 0
        else:
            resta -= custo
    if etapa < len(caminho) - 1:
        erros.append(f'a lista acaba em {JOBS[caminho[etapa]]} com {resta} ponto(s) - faltam skills para as proximas classes')
    elif resta:
        erros.append(f'{JOBS[caminho[-1]]}: sobram {resta} pontos no job 50 (aviso)')
    mapas = {x['map']: x['bro_id'] for x in yaml.safe_load(MAPS_YML.read_text(encoding='utf-8'))}
    for e in m['etapas']:
        p = str(e).split()
        if len(p) != 5:
            erros.append(f'etapa mal formada: {e}')
            continue
        for c in p[2].split(','):
            if int(c) not in caminho:
                erros.append(f'etapa {e}: classe {c} fora do caminho')
        if p[3] not in mapas:
            erros.append(f'etapa {e}: mapa {p[3]} desconhecido')
        elif mapas[p[3]] != 'bro-01':
            erros.append(f'etapa {e}: {p[3]} so abre no {mapas[p[3]]} (o plugin pula ate la) (aviso)')
    return erros


def _personagem_aleatorio(sexo):
    return {'sexo': sexo, 'cabelo': random.randint(1, 23), 'cor_cabelo': random.randint(0, 8)}


# perfis de horario do plugins/mazzaRitmo (regras 1-9 de mazzaro/docs/bots/pesquisa-comportamento.md) e o peso de
# cada um no sorteio quando --perfil-horario nao e dado (no bRO de 2006, 84% eram estudantes)
PERFIS_HORARIO = {'estudante': 0.5, 'trabalhador': 0.3, 'noturno': 0.1, 'fim-de-semana': 0.1}


def bloco_ritmo(perfil=None, rng=random):
    """Bloco mazzaRitmo_* do config.txt de um bot: perfil, janela propria, horas, dias, reacao e ping sorteados."""
    perfil = perfil or rng.choices(list(PERFIS_HORARIO), weights=list(PERFIS_HORARIO.values()))[0]
    if perfil not in PERFIS_HORARIO:
        raise SystemExit(f'perfil de horario desconhecido: {perfil} (existentes: {", ".join(PERFIS_HORARIO)})')
    horas = min(40.0, max(2.0, rng.lognormvariate(0, 0.6) * 10))            # mediana ~10 h/semana, com cauda
    dias = 3 if perfil == 'fim-de-semana' else rng.randint(3, 6)
    ping = round(min(200, max(8, rng.lognormvariate(0, 0.5) * 40)))
    mediana = rng.uniform(0.30, 0.60) / (1 + ping / 200)                      # o plugin multiplica por (1 + ping/200)
    afk = rng.randint(12, 20)
    lim = rng.randint(25, 38)
    return '\n'.join([
        '######## Ritmo e agenda (plugins/mazzaRitmo; sorteado pelo gerador) ########',
        'mazzaRitmo 1',
        f'mazzaRitmo_perfil {perfil}',
        f'mazzaRitmo_deslocamento {rng.randint(-60, 60)}',
        f'mazzaRitmo_horas_semana {horas:.1f}',
        f'mazzaRitmo_dias {dias}',
        f'mazzaRitmo_reacao {mediana:.2f} {rng.uniform(0.4, 0.6):.2f} {rng.uniform(0.04, 0.08):.2f}',
        f'mazzaRitmo_ping {ping}',
        f'mazzaRitmo_afk {afk} {afk + rng.randint(15, 25)} 1 {rng.randint(3, 5)}',
        f'mazzaRitmo_pausa {rng.randint(40, 50)} {rng.randint(65, 80)} 5 {rng.randint(12, 20)}',
        f'mazzaRitmo_meio_luta {rng.uniform(0.15, 0.35):.2f}',
        f'mazzaRitmo_limiar {lim} {min(60, lim + rng.randint(15, 25))}',
    ]) + '\n'


def novo(nome, mid, pers, sexo=None, personagem=None, perfil_horario=None, ctl=None, perfil='kro-2026'):
    """Cria mazzaro/bots/<nome>/ a partir do modelo e da personalidade."""
    if not re.fullmatch(r'[a-z0-9_]{3,20}', nome):
        raise SystemExit('nome do bot: 3-20 letras minusculas, digitos ou _')
    dst = BOTS / nome
    if dst.exists():
        raise SystemExit(f'{dst} ja existe')
    m = carregar_modelo(mid)
    ptxt = PERSONALIDADES / f'{pers}.txt'
    if not ptxt.exists():
        raise SystemExit(f'personalidade desconhecida: {pers} (existentes: {", ".join(personalidades_disponiveis())})')
    erros = [e for e in validar(mid) if not e.endswith('(aviso)')]
    if erros:
        raise SystemExit(f'modelo {mid} com problemas:\n  ' + '\n  '.join(erros))
    sexo = (sexo or random.choice('MF')).upper()
    pj = {'nome': personagem or nome.capitalize(), 'slot': 0, **_personagem_aleatorio(sexo)}
    usados = {int(yaml.safe_load((p / 'bot.yml').read_text(encoding='utf-8')).get('ctl') or 0)
              for p in BOTS.iterdir() if (p / 'bot.yml').exists()}
    ctl = ctl or next(p for p in range(6961, 7100) if p not in usados)

    ritmo = bloco_ritmo(perfil_horario)
    horario = re.search(r'^mazzaRitmo_perfil (\S+)', ritmo, re.M).group(1)

    (dst / 'control').mkdir(parents=True)
    bot = {'descricao': f'{pj["nome"]}, {m["nome"]} ({pers}, {horario})', 'perfil': perfil, 'conta': f'mzb_{nome}',
           'ctl': ctl, 'modelo': mid, 'personalidade': pers, 'horario': horario, 'personagem': pj}
    (dst / 'bot.yml').write_text(f'# gerado por bots.py --novo {nome} --modelo {mid} --personalidade {pers}\n'
                                 + yaml.safe_dump(bot, allow_unicode=True, sort_keys=False), encoding='utf-8')

    cfg = (MODELOS / '_base' / 'config.txt').read_text(encoding='utf-8')
    cfg += (f'\n######## Build: {m["nome"]} (modelos/{mid}.yml) ########\n'
            f'statsAddAuto_list {m["stats"]}\n'
            f'skillsAddAuto_list {" ".join(str(m["skills"]).split())}\n\n{m.get("config") or ""}')
    cfg += '\n' + ritmo
    (dst / 'control' / 'config.txt').write_text(cfg, encoding='utf-8')

    troca = {int(k): int(v) for k, v in (m.get('troca_classe') or {}).items()}
    jl = [f'# {pj["nome"]} - {m["nome"]} - gerado de modelos/{mid}.yml (editar a vontade)', '']
    jl += [f'etapa {e}' for e in m['etapas']]
    jl.append('')
    caminho = m['classes']
    for de, para in zip(caminho, caminho[1:]):
        mapa, x, y = INSTRUTORES[para]
        jl.append(f'classe {de} {para} {troca.get(para, 10 if de == 0 else 40)} {mapa} {x} {y} c r0 c')
    jl.append('')
    jl.append((MODELOS / '_base' / 'jornada_comum.txt').read_text(encoding='utf-8').rstrip())
    jl.append('')
    jl.append('opcao chance_fala_ambiente ' + str(random.choice([2, 3, 4, 6])))
    jl.append('opcao pausa_a_cada_min ' + str(random.randint(30, 60)))
    jl.append('opcao pausa_a_cada_max ' + str(random.randint(70, 120)))
    (dst / 'control' / 'jornada.txt').write_text('\n'.join(jl) + '\n', encoding='utf-8')

    falas = ptxt.read_text(encoding='utf-8')
    (dst / 'control' / 'falas.txt').write_text(falas, encoding='utf-8')
    for f in ('mon_control.txt', 'pickupitems.txt'):
        (dst / 'control' / f).write_text((MODELOS / '_base' / f).read_text(encoding='utf-8'), encoding='utf-8')
    return dst, bot
