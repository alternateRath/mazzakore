# lockMapSweep

Troca o `randomWalk` no `lockMap` por uma varredura em blocos: divide a parte andável do mapa numa grade
(`blocksX` x `blocksY`), visita alguns pontos sorteados de um bloco e passa para um bloco vizinho ainda não
visitado. Fica com cara de quem "rodou o mapa" em vez de zanzar sempre no mesmo canto.

- Origem: https://github.com/boscv/lockMapSweep (commit c0f2d45, 2026-03-01), de @boscv (billabong93, o mesmo
  autor do timeoutRandomizer do core). O repositório não declara licença; está aqui como plugin do OpenKore (GPL).
  README original (em inglês) com todas as opções no repositório.
- Mazzakore: o arquivo de estado vai para `<logs do bot>/lockMapSweep/` (o original gravava em
  `plugins/lockMapSweep/state`, dentro do clone).
- Testado (2026-11-03, prt_fild01, 3x3): "Built lockMap plan", rotas para os blocos 0 -> 1 -> 4 -> 6, estado em
  `run/logs/bots/plugtestea/lockMapSweep/prt_fild01_3x3.state`.

## Ligar
`sys.txt`: `loadPlugins_list ...,lockMapSweep`. `config.txt`:

```
route_randomWalk 1
lockMapSweep_enabled 1
lockMapSweep_blocksX 3       # padrão do código: 2
lockMapSweep_blocksY 3       # padrão do código: 2
lockMapSweep_cellsPerBlock 2 # padrão do código: 3
lockMapSweep_useStateFile 1
```
Comandos: `lockMapSweep status|rebuild|clearstate`.
