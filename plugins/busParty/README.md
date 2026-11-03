# busParty

Os bots do mesmo OpenKore trocam nome, mapa, posição, HP e status pelo BUS, e cada um passa a ver os outros
como membros de party (mesmo sem party de verdade, ou fora da tela). Junto com wait4party/busFollow e
`partyAuto`, deixa grupos de bots andarem juntos sem depender do pacote de party do servidor.

- Origem: `plugins/needs-review/busParty` do openkore/openkore (Revok, 2021, GPL).
- Mudança no mazzakore: sem BUS ligado avisa uma vez e fica parado (o original dava `die` dentro do hook e
  derrubava o bot).
- Testado (2026-11-03): dois bots com `bus 1`; o comando `busParty` no A listou o B (mapa, posição, HP) depois
  que o B saiu da party de verdade.

## Ligar
`sys.txt`: `bus 1` e `loadPlugins_list ...,busParty`. Com `bus_server_host` vazio o primeiro OpenKore sobe o
servidor de BUS sozinho (127.0.0.1, porta aleatória). Comando: `busParty`.

Limitação do original: quem fecha o OpenKore continua aparecendo "online" para os outros.
