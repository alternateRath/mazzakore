# mazzaro/bots/ - bots roleplay do MazzaRO

Bots que entram no MazzaRO como jogadores e vivem uma história: treinam, viajam, mudam de classe, visitam lugares,
descansam na cidade e conversam. Rodam no mazzakore (serverType `kRO_RagexeRE_2026_02_19`) com o plugin
[`plugins/mazzaJornada`](../../plugins/mazzaJornada/mazzaJornada.pl).

## Bots

| Bot | Quem é | Horário (mazzaRitmo) | Perfil |
|---|---|---|---|
| [`aldren`](aldren/) | garoto de uma fazenda perto de Prontera que quer ser Cavaleiro e conhecer Rune-Midgard | estudante | kro-2026 |
| [`bia`](bia/) | Biazinha, `bruxo_intdex`, personalidade `empolgado` (gerada) | trabalhador | kro-2026 |
| [`tonhao`](tonhao/) | Tonhao, `ferreiro_batalha`, personalidade `zoeiro` (gerado) | estudante | kro-2026 |
| [`lia`](lia/) | LiaSacer, `sacerdote_suporte`, personalidade `timido` (gerada) | noturno, mas sempre on (`mazzaRitmo_agenda 0`) | kro-2026 |

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
  `control\config.txt` do bot, mais conta e personagem do `bot.yml`), o `sys.txt` (plugins
  `mazzaJornada,raiseStat,raiseSkill,mzctl,timeoutRandomizer,mazzaRitmo`)
  e o `servers.txt` (o mesmo bloco do `tools\mz\kore.py`). Nada é escrito no clone.
- Recusa subir se o perfil no ar não for o do bot (lido do `tools\mz\profiles.py` do mazzaro).
- Logs e o estado da jornada (`jornada_<personagem>.txt`: cidades visitadas, Kafras, turismo) em
  `<ws>\run\logs\bots\<bot>\`. Senha da conta em `<ws>\run\bots\<bot>\conta.yml` (fora do git).
- Conta vazia: o plugin cria o personagem do `bot.yml` no slot pedido.

No console do OpenKore: `jornada` (estado), `jornada pausa`, `jornada retomar`, `jornada reset`;
`ritmo` (estado), `ritmo agenda [dias]`, `ritmo simular [semanas]`, `ritmo sair`, `ritmo afk`, `ritmo pausa` (AFK e pausa na hora).

## Novo bot (gerador)
```
python -I mazzaro\bots\bots.py --modelos       # modelos de build e personalidades
python -I mazzaro\bots\bots.py --validar       # modelos contra a skill_tree pre-renewal do mazzathena
python -I mazzaro\bots\bots.py --novo bia --modelo bruxo_intdex --personalidade empolgado --sexo F --perfil-horario estudante
python -I mazzaro\bots\bots.py --criar-conta bia
```
- **Modelos** (`modelos/<id>.yml`): caminho de classes, troca de classe, stats, skills (na ordem em que se gasta),
  blocos de skill do OpenKore e etapas de treino. Fonte de cada build no topo do arquivo (iRO Wiki Classic).
  A parte comum fica em `modelos/_base/` (config, mon_control, pickupitems, turismo/lojas/cidades).
- **Personalidades** (`personalidades/<p>.txt`): `empolgado`, `veterano`, `zoeiro`, `timido`. Seções como no
  `falas.txt` do Aldren, mais `[chegada]` e `[saida]` (sessões) e as variáveis `{classe}` e `{meta}`.
- O `--validar` simula o `raiseSkill`: pré-requisito fora de ordem ou pontos sobrando na hora da troca de classe
  (o bot fica parado e o NPC recusa) viram erro. `--novo` recusa modelo com erro.
- `--perfil-horario estudante|trabalhador|noturno|fim-de-semana` (sem ele: sorteado, metade estudante): o gerador
  escreve no `control\config.txt` o bloco `mazzaRitmo_*` com perfil, janela própria, horas por semana, dias, reação,
  ping, AFK, pausa e limiares sorteados para o bot (ver "Ritmo e agenda" abaixo).
- O `items_control.txt` é gerado em `run\bots\<bot>\control`: vende o loot no Tool Dealer da cidade-base
  (linhas `loja`) e guarda poção, asa, gema, flecha, minério, caixa e todas as cartas.

## Ritmo e agenda (`plugins/mazzaRitmo`)
Fase F1 do [plano](../../../mazzaro/docs/bots/PLANO-JOGADORES.md), regras 1-9 da
[pesquisa](../../../mazzaro/docs/bots/pesquisa-comportamento.md). O `mazzaJornada` não cuida mais de horário: as linhas
`horario` do `jornada.txt` foram aposentadas (viram aviso).
- **Agenda** determinística (semente = conta + data): por semana, horas lognormais em volta de
  `mazzaRitmo_horas_semana` e 3-6 dias de jogo (`mazzaRitmo_dias` ±1) escolhidos pelo perfil; as sessões (35% passadas
  rápidas de 2-15 min, 65% Weibull forma 0,8 escala 90 min, teto 8 h, < 2% acima de 5 h) enchem as horas da semana e
  começam numa hora sorteada na curva do Brasil (pico 19h-0h, vale de madrugada e de manhã em dia útil, tarde de
  sábado), mudada pelo perfil e deslocada pela janela do bot (`mazzaRitmo_deslocamento`, ±60 min). Entre duas sessões,
  3-25 min no mínimo. Reiniciar o OpenKore cai na mesma sessão planejada; fora de sessão ele nem entra (espera com
  `relog`). Na hora de sair: fala de despedida (`[saida]` das falas, pelo `mazzaJornada`) e `relog <segundos>` até a
  próxima; às vezes (`mazzaRitmo_meio_luta`) sai no meio da luta.
- **Reação**: os timeouts de reação (`ai_attack_auto`, `ai_attack_waitAfterKill`, `ai_items_take_start`, ...) viram
  atrasos lognormais (mediana `mazzaRitmo_reacao`, cauda Pareto até ~10 s, nunca < 120 ms, × (1 + ping/200)) e outros
  dez ganham faixas largas; tudo pelo `timeoutRandomizer` do clone (o plugin gera `logs\ritmo_timeouts.txt` e troca o
  sorteio uniforme dele). O laço principal dorme 4-18 ms sorteados a cada volta (sem grade fixa).
- **AFK** de 1-5 min a cada 15-40 min (IA em manual, às vezes sentado; apanhando, "volta" depois de um tempo de
  reação), **pausa** de 5-20 min a cada 45-75 min (o `mazzaJornada` leva pra cidade e senta), **limiar** de sentar e de
  poção sorteado entre 25-60% a cada sessão (só na memória).
- `mazzaRitmo_agenda 0`: sempre on (AFK, pausa e reação seguem); `mazzaRitmo 0` desliga o plugin.
  `mazzaRitmo_teste <sessao_s> <volta_s>`: sessões curtas para teste, com AFK e pausa na mesma escala.
- `ritmo simular 4` mostra 4 semanas da agenda do bot (sessões, horas e dias por semana, histograma de início por
  hora, forma da reação) e grava `logs\ritmo_simulado.csv`. Entradas, saídas, AFK e pausas reais vão para
  `logs\ritmo_<conta>.log` (para a régua).
- Hooks para os outros plugins: `mazzaRitmo_chegada {fala}`, `mazzaRitmo_saida {luta, falou}`,
  `mazzaRitmo_pausa {dur, tratado}`; `mazzaRitmo::parado()`, `mazzaRitmo::agenda()`, `mazzaRitmo::estado()`.

Bot feito à mão: copiar `aldren\`, trocar `bot.yml` (conta, personagem, `ctl`) e reescrever o `control\`.

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
turismo na fonte de Prontera com fala; ida às zonas de 2001 pelo Historiador e volta pelo Eco do presente; 4 bots
juntos (Aldren + 3 gerados) com as falas de cada personalidade e cumprimentos entre eles; ouvem os moradores das
cidades (mazzathena) no chat. Corrigido no teste: `getItems` da Kafra (derrubava o bot), `/e` nas respostas.
Ainda não visto: Kafra salvando, treino em campo por horas, mudança de classe pelos instrutores, `raiseSkill`
depois da classe nova, venda/compra na loja.

### mazzaRitmo (2026-11-03, kro-2026 local)
Bot de teste com `mazzaRitmo_teste 120 45`: duas sessões seguidas de ~100 s com fala de chegada ("CHEGUEI, podem
comemorar"), AFK curto, despedida pelo `[saida]` ("fui, a janta chegou") e `relog` de ~50 s até a próxima;
`ritmo pausa` levou o `mazzaJornada` ao modo `retorno`; sem o modo teste, fora de sessão o bot nem conectou
("fora de sessao; entra ter 03/11 20:28"). `ritmo simular 4` no bot vivo. Ainda não visto: AFK apanhando, sessão
acabando no meio da luta, uma sessão planejada inteira (horas) e a régua sobre os logs `ritmo_<conta>.log`.
