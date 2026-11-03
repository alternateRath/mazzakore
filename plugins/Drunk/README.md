# Drunk

Rotas menos retas: um pouco de ruído por célula em todas as rotas e, numa parte delas, uma "mancha" de custo
alto perto da linha reta, de um lado sorteado, para o caminho fazer curva como quem desvia de alguma coisa.

- Ideia do plugin Drunk de Henrybk (https://github.com/Henrybk/Plugins/tree/master/Drunk), que trocava o
  pathfinding por uma DLL XS própria (não carrega com segurança no Perl 5.12 do start.exe). Aqui é uma
  reescrita em Perl puro, sem código do original: usa `randomFactor` e `customWeights/secondWeightMap`, que o
  pathfinding do core já aceita no hook `getRoute`. Convive com o avoidObstacles (junta os pesos, fica o maior).
- Não mexe em rotas de seguir, fugir, pegar item, voltar ao mestre etc.
- Testado (2026-11-03, prt_fild01, junto com lockMapSweep): 7 rotas de passeio com ruído e curva
  (`eval $Drunk::conta{curva}`), todas chegaram ao destino.

## Ligar
`sys.txt`: `loadPlugins_list ...,Drunk`. `config.txt`:

```
drunk 4              # 0 desliga; o passo reto custa 10
drunk_curves 1       # 0..3
drunk_curveWeight 40
drunk_chance 70
drunk_minDist 15
```
