# mazzaro/bots/ - bots roleplay do MazzaRO

Bots que entram no MazzaRO como jogadores e vivem uma história: treinam, viajam, mudam de classe, visitam lugares,
descansam na cidade e conversam. Rodam no mazzakore (serverType `kRO_RagexeRE_2026_02_19`) com o plugin
[`plugins/mazzaJornada`](../../plugins/mazzaJornada/mazzaJornada.pl).

## Bots

| Bot | Quem é | Perfil |
|---|---|---|
| [`aldren`](aldren/) | garoto de uma fazenda perto de Prontera que quer ser Cavaleiro e conhecer Rune-Midgard | kro-2026 |

### Jornada do Aldren
| Nível base | Classe | Onde treina | Cidade base |
|---|---|---|---|
| 1-12 | Aprendiz | prt_fild08 (Poring, Lunatic, Pupa) | Prontera |
| job 10 | → **Espadachim** | guilda em Izlude (`izlude_in`) | |
| 1-17 | Espadachim | prt_fild08 | Prontera |
| 18-26 | Espadachim | pay_dun00 (Zombie, Skeleton) | Payon |
| 27-35 | Espadachim | iz_dun00 (Hydra, Marina, Vadon) | Izlude |
| 36-45 | Espadachim | anthell01 (Andre, Piere, Deniro) | Morroc |
| 46+ | Espadachim | orcsdun01 (Orc Zombie, Orc Skeleton) | Geffen |
| job 50 | → **Cavaleiro** | Ordem em Prontera (`prt_in`) | |
| até 58 | Cavaleiro | orcsdun01 | Geffen |
| 59-79 | Cavaleiro | c_tower1 (Punk, Rideword) | Al De Baran |
| 80+ | Cavaleiro | gl_knt01 (Raydric, Abysmal Knight) | Geffen |

Na primeira passagem por Prontera ele visita a fonte e, pelo **Historiador**, a Prontera e a Morroc de 2001, voltando
pelo **Eco do presente**. Todos os mapas da rota abrem no `bro-01`.

## Como rodar
```
.\mz.ps1 up kro-2026                                   # no mazzaro
python -I mazzaro\bots\bots.py --criar-conta aldren    # uma vez (conta no grupo 5 = Bot, senha MD5)
python -I mazzaro\bots\bots.py aldren                  # abre o OpenKore do Aldren num console proprio
python -I mazzaro\bots\bots.py --listar
```
- `bots.py` gera em `<ws>\run\bots\<bot>\` o `config.txt` (dois `!include`: o padrão do clone e o
  `control\config.txt` do bot, mais conta e personagem do `bot.yml`), o `sys.txt` (plugins `mazzaJornada,raiseStat,raiseSkill`)
  e o `servers.txt` (o mesmo bloco do `tools\mz\kore.py`). Nada é escrito no clone.
- Recusa subir se o perfil no ar não for o do bot (lido do `tools\mz\profiles.py` do mazzaro).
- Logs e o estado da jornada (`jornada_<personagem>.txt`: cidades visitadas, Kafras, turismo) em
  `<ws>\run\logs\bots\<bot>\`. Senha da conta em `<ws>\run\bots\<bot>\conta.yml` (fora do git).
- Conta vazia: o plugin cria o personagem do `bot.yml` no slot pedido.

No console do OpenKore: `jornada` (estado), `jornada pausa`, `jornada retomar`, `jornada reset`.

## Novo bot
1. Copiar `aldren\` para `<nome>\`, trocar `bot.yml` (conta, personagem).
2. Reescrever `control\jornada.txt` (etapas, classes, turismo) e `control\falas.txt` (personalidade).
3. Ajustar `control\config.txt` (build, skills, poções). Só o que muda sobre o padrão.

### jornada.txt
```
etapa  <lvMin> <lvMax> <classes,sep,virgula> <lockMap> <cidadeBase>
classe <deID> <paraID> <jobLvMin> <mapa> <x> <y> <sequencia talknpc>
ponto  <cidade> <mapa> <x> <y> [volta <x> <y> <sequencia>]
cidade <mapa> ...
opcao  <chave> <valor>
```
### falas.txt
Seções `[levelup] [classe] [rumo_classe] [cidade_nova] [turismo] [turismo_<mapa>] [turismo_<cidade>] [chegou_campo]
[ambiente] [morte] [indo_pausa] [pausa] [fim_pausa] [chamado] [saudacao] [pm] [bloqueado]`; variáveis `{nome} {lv}
{cidade} {jogador}`; `/e N texto` faz um emote antes. Sem acentos (serverEncoding Western).

## Motor de Episódios
O plugin lê o aviso do `episodios.txt` ("Esta regiao ainda nao foi descoberta ... <mapa> chega em ...") e pula a etapa
ou o ponto turístico daquele mapa por `bloqueio_horas` (padrão 6). Com o episódio avançado (`@episode next`), ele volta
a tentar sozinho.

## Servidor
O grupo **Bot** (`conf/import/groups.yml`, id 5, jogador comum sem nível de GM) e os instrutores de classe só para
bots (`npc/custom/mazzaro/mazzabots.txt`, dentro das guildas oficiais: izlude_in 72,170 e prt_in 85,99) estão no
overlay do **mazzaro** (`server/overlay/`), aplicados desde 2026-11-03. As linhas `classe` do `jornada.txt` de cada bot
precisam bater com essas coordenadas.

## Controle de fora
Cada bot carrega o plugin `mzctl` numa porta própria (`ctl:` no `bot.yml`, senão 6960 + posição na lista do
`--listar`). Do mazzaro: `python -I tools\mz\kore_cmd.py --estado --porta 6960` e
`python -I tools\mz\kore_cmd.py "jornada" --porta 6960`.

## Verificado (2026-11-03, kro-2026 local)
Conta criada, login, criação do personagem no slot vazio e entrada automática no mapa; `raiseStat` distribuindo;
turismo na fonte de Prontera com fala; rota até o Historiador para a Prontera de 2001. Ainda não visto: volta pelo
Eco, Kafra salvando, treino em campo, mudança de classe pelos instrutores, `raiseSkill` depois da classe nova.
