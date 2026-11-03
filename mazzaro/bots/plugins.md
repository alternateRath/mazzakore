# Plugins de terceiros para bots com jeito de gente (2026-11-03)

Revisão e porte dos plugins que a [pesquisa](../../../mazzaro/docs/bots/pesquisa-plugins.md) marcou como úteis
para o plano v2 ([PLANO-JOGADORES.md](../../../mazzaro/docs/bots/PLANO-JOGADORES.md)). Os plugins mazza*
(mazzaRitmo, mazzaRota, mazzaPapo, mazzaSocial, mazzaMercado) vão ligar e configurar estes; **nenhum bot
existente foi ligado** — o `PLUGINS` do `bots.py` continua `mazzaJornada,raiseStat,raiseSkill,mzctl`.

Todos ficam em `plugins/<nome>/<nome>.pl` com um README curto (origem, licença, mudanças, como ligar, o que o
teste mostrou). Os originais de `plugins/needs-review/` ficaram intactos (o upstream continua batendo).

## Estado

"Carrega" = sobe na `loadPlugins_list` do start.exe (Perl 5.12) e o bot entra no jogo, sem erro. "Funciona" =
comportamento visto contra o servidor local kro-2026 com dois bots de teste (ver "Como foi testado").

| Plugin | De onde | Estado | Carrega | Teste no kro-2026 | O que mudou / por quê |
|---|---|---|---|---|---|
| timeoutRandomizer | clone (`plugins/`, 2026-02) | **corrigido no lugar** | sim (depois da correção) | faixas sorteadas a cada uso: `ai_items_take_delay 0.4 2` deu 0,64 / 0,84 / 1,00 | Não carregava no start.exe (`File::Spec::Functions` não vem no Perl 5.12; o erro de carga derruba o bot) e o `timeOut` dele devolvia falso com tempo indefinido (o bot nem entrava no jogo, log cheio de aviso). O `timeout_randomizer.txt` precisa existir antes de subir o bot. |
| breakTime | clone (`plugins/`) | funciona, sem mudança | sim | pausa `all 17:51-17:53`: "Disconnecting due to break time" às 17:51, de volta ao jogo às 17:53:47 | — (o mazzaJornada já tem janelas de horário; breakTime serve para pausas fixas por dia da semana) |
| reconnect | clone (`plugins/`) | funciona, sem mudança | sim | na volta da pausa armou `reconnect` = 10 s a partir de `reconnect_backoff 7,20` + `reconnect_random 5`; só escreve no log em tentativas repetidas | — (`reconnect_backoff`/`reconnect_random` já estão no `timeouts.txt` padrão: 30..1800 s) |
| wait4party | clone (`needs-review`) | **portado** | sim | B sumiu com `@warp`: "Party (PlugTesteB) lost" -> rota -> "found!" | mapa do membro sem depender do `.gat` |
| busParty | clone (`needs-review`, 2021) | **portado** | sim | com `bus 1`, `busParty` no A listou o B (mapa, posição, HP) fora da party | `die` sem BUS virou aviso |
| busFollow | clone (`needs-review`) | **portado** | sim | B (follow, sem party) achou o A pelo BUS: "Calculando rota para encontrar o mestre: prontera (150, 250)" | `die` -> aviso; `!=` em nome de mapa (sempre "igual") -> `ne`; posição de `$char` |
| autoshop | clone (`needs-review`) | **portado (reescrito)** | sim | com chat do A a 2 células: "lugar ocupado (peso 3)", andou para um ponto de peso 0 | lia `%players` (vazio no core atual); agora só escolhe o lugar e segura o `shopAuto_open` do core |
| shopper | clone (`needs-review`) | **portado (reescrito)** | sim | A abriu sozinho a loja do B e comprou 3 Poções Vermelhas a 40z (1000 -> 880 zeny) | nunca entrava na loja (relógio zerado a cada tick) e usava a API antiga; agora espera, lê a lista toda e compra de uma vez |
| reactOnKillSteal | clone (`needs-review`) | **portado** | sim | B bateu no Poring do A: "kill steals my Monstro Poring [1x]" + emote de raiva | lia `%monsters/%players` (nunca disparava); `checkMonsterCondition` com ID **derrubava o bot** |
| reactOnActor | clone (`needs-review`) | **portado** | sim | B parou a 1 célula: A reagiu (`e ho`) e respeitou o `actor_timeout` | lookup velho (nunca reagia); checagem a cada 1 s para `actor_dist` valer |
| kadiliman | clone (`needs-review`, 2005) | **portado** | sim | chat público do B respondido com frases emendadas ("nao tenho pocao vermelha barato") | cola reescrita (pacote cru, PM sem texto, travava a IA); módulo em UTF-8, acentos, arquivo na pasta do bot |
| lockMapSweep | [boscv/lockMapSweep](https://github.com/boscv/lockMapSweep) c0f2d45 (2026-03) | **portado** | sim | prt_fild01 3x3: blocos 0 -> 1 -> 4 -> 6, estado salvo | arquivo de estado fora do clone (pasta de logs do bot) |
| AnswerChat | [Henrybk/Plugins](https://github.com/Henrybk/Plugins) 473f544 (2022) | **portado (motor reescrito)** | sim | PMs do B: "oi" -> "falea" + "falae*"; "me da zeny" -> "tebho naum" + "tenho*"; paciência acaba | Latin-1 -> UTF-8; correção depois da frase; memória JSON na pasta de logs; "bot?" antes de "vc é ...?"; dicas de up só até 99 com lugares de 2004 |
| IdletimeSelfCond | Henrybk/Plugins | **portado (reescrito)** | sim | `doCommand e ic { whenIdleFor 8 }` disparou depois de 8 s parado | relógio começava valendo; podia desfazer reprovação de outro plugin |
| randItemsTakeTimeout | Henrybk/Plugins | **portado** | sim | 3 itens pegos 1,4 / 2,0 / 3,4 s depois do drop | unload quebrado; sorteia também a espera antes do 1º item |
| onMonsterKill | Henrybk/Plugins | **portado** | sim | `e lv` 0,5-1 s depois de "Target died" | + chance, atraso, intervalo mínimo, `@monsterName` |
| Drunk | Henrybk/Plugins (ideia) | **reescrito em Perl puro** | sim | 7 rotas de passeio com ruído e curva, todas chegaram | o original é uma DLL XS própria (não carrega com segurança no 5.12); aqui usa `randomFactor` e `secondWeightMap` do pathfinding do core |
| partyBuilder | [NandoPrates/Plugins-1](https://github.com/NandoPrates/Plugins-1) (2017, GPLv2) | **descartado** | — | — | só troca `lockMap` por faixa de nível (o mazzaJornada já faz com etapas e cidades); a parte de "montar party" ficou vazia no original (`if (AI::isIdle) {}`), e o `use constant` tem um valor faltando. A ideia de montar party fica para o mazzaSocial (convite com `party request` + `partyAuto 2` do lado de quem aceita, testado aqui) |
| aiChat | [lMuchl/plugin_openkore_aiChat](https://github.com/lMuchl/plugin_openkore_aiChat) (2025) | **só referência** | — | — | notas abaixo para a ponte de LLM |

Licenças: os do clone são GPL (cabeçalhos originais mantidos). lockMapSweep, Henrybk/Plugins e aiChat não declaram
licença no repositório (a API do GitHub devolve `license: null`); os dois autores dos portados contribuem com o
OpenKore (GPL) e os plugins só rodam dentro dele. A origem (URL + commit) está no cabeçalho de cada arquivo. Se
algum autor pedir, é só tirar a pasta. partyBuilder é GPLv2. O Drunk daqui não tem código do original.

## Como ligar (quando um mazza* for usar)

1. `sys.txt` do bot: acrescentar o nome à `loadPlugins_list` (no `bots.py`, `PLUGINS`). busParty/busFollow pedem
   também `bus 1` (com `bus_server_host` vazio o primeiro OpenKore sobe o servidor sozinho, só na máquina: um
   `start.exe ! src/Bus/bus-server.pl` filho, que **continua vivo** depois que o bot sai — matar junto ao derrubar
   os bots).
2. Chaves no `control/config.txt` do bot (cada README tem o bloco). Arquivos de controle novos
   (`timeout_randomizer.txt`, `shop.txt`, `kadiliman.txt`) precisam existir **antes** de o bot subir: o `reload`
   só relê o arquivo que foi achado na partida.
3. Chat: escolher **um** dono por canal (AnswerChat para PM, kadiliman para público, ou o mazzaPapo/LLM), e pôr os
   outros bots em `AnswerChat_ignore`/`chatBot_0_noPlayers` para eles não conversarem em loop.
4. Emote (onMonsterKill, reactOnKillSteal, reactOnActor, IdletimeSelfCond): Aprendiz precisa de Habilidades
   Básicas nível 2 (sem isso o servidor recusa).

## Achados que valem para os próximos plugins

- **Erro de carga de plugin derruba o start.exe** (ele para na tela de erro esperando tecla; com `--oculto` o bot
  some sem log, só fica o `errors.txt` na raiz do clone). Conferir sintaxe antes com o perl do Git Bash e módulos
  simulados (`perl -I<stub> -c plugin.pl`) e carregar uma vez com `plugin load ^nome$`.
- `plugin load` aceita **regex do nome** e só acha plugins até um nível abaixo de `plugins/` (nada de
  `needs-review/x/trunk`).
- Não vêm no Perl 5.12 do start.exe: `File::Spec::Functions` (usar `File::Spec->...`). Vêm: `JSON::Tiny`
  (`from_json/to_json/encode_json/decode_json`), `Time::HiRes`, `File::Path`, `LWP`, `HTTP::*`.
- `%monsters`, `%players`, `%npcs` existem em `Globals` mas **não são mais preenchidos**: usar
  `$monstersList/$playersList/...->getByID`. `Misc::checkMonsterCondition` quer o ator, `checkPlayerCondition` o ID.
- Hook `packet/<handler>` roda **depois** do handler do core (o ator já está na lista). O pacote de andar chega
  quando o ator começa a andar: distância "chegou perto" precisa de checagem periódica.
- O console (e o mzctl) corta comandos em `;;`. Para testar config com `;;`, usar `chr(59)` num `eval` ou o
  `config.txt`. `conf` não cria chave nova: `eval Misc::configModify('chave', 'valor', 1)`.
- Loja de jogador no kro-2026: o `shopAuto_open` do core falha (a tarefa da skill Comércio não vê confirmação,
  pacote `0B40` desconhecido) e deixa o personagem preso esperando a janela da loja; `ss 41 10` + `openshop` com
  `shop_useSkill 0` funciona. `shop.txt` é separado por TAB. O centro de Prontera não deixa abrir chat/loja
  (erro 83). Isso precisa de conserto no core antes dos mercadores do mazzaMercado.
- `@monster`, `@allskill`, `@job`, `@cart 1`, `@zeny`, `@blvl` com conta de grupo 99 deixam testar combate, KS e
  loja em minutos.

## aiChat (referência para a ponte de LLM)

O que aproveitar: contexto do personagem (nome, classe, níveis, mapa) como mensagem de sistema na primeira fala
com cada jogador; histórico por jogador; atraso de digitação proporcional ao tamanho da resposta; comandos de
console para ver/ajustar a configuração.

O que não repetir: a chamada HTTP é **síncrona** (LWP com timeout de 20 s) e o atraso de digitação é um
`sleep()` — os dois congelam o laço principal do OpenKore (sem andar, sem curar, sem responder ao servidor
durante a espera). A chave da API fica escrita no `api_proxy.js`; o proxy Node é iniciado por um `.bat` e morto
por `taskkill` de um PID em arquivo. Responde a todo PM, sem filtro de GM/outros bots e sem limite de custo.

Para o mazzaPapo: pedido ao LLM fora do laço (processo/thread separado ou socket não bloqueante lido no
`mainLoop_post`, como o mzctl faz), Ollama local (`/api/chat`) direto do Perl com `IO::Socket::INET` + `JSON::Tiny`
(sem Node), resposta enfileirada com tempo de ler+digitar (como o AnswerChat daqui), fallback para o AnswerChat
quando o LLM não responder a tempo, e lista de quem nunca recebe resposta (outros bots, GMs).

## Como foi testado

Dois bots de teste (`PlugTesteA`, `PlugTesteB`, contas `mzt_pluga/mzt_plugb` de grupo 99 no banco local), fora de
`mazzaro/bots/` para não mexer na lista de bots: um script no scratchpad importa o `bots.py`, troca `BOTS` por uma
pasta própria e `PLUGINS` por `mazzaJornada,mzctl,<plugins>` (sem `jornada.txt` o mazzaJornada só cria o
personagem). Comandos e estado por `python -I tools/mz/kore_cmd.py --porta 6981/6982` no mazzaro. O A subiu com os
19 plugins na `loadPlugins_list` de uma vez e entrou no jogo; depois cada comportamento foi provocado com o B e
comandos de GM em prt_fild01 e Prontera.
