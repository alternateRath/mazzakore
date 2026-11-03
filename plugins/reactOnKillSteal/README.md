# reactOnKillSteal

Reage quando outro jogador bate no monstro que você já estava enfrentando (KS): um comando sorteado de uma lista
(`;;` separa), com tempo de digitar se for chat, respostas que mudam conforme quantas vezes o mesmo jogador já fez
isso, e esquecimento depois de um tempo.

- Origem: `plugins/needs-review/reactOnKillSteal/trunk` do openkore/openkore (hakore; porte 2.1 de Kissa2k; GPL).
  Documentação completa das opções em `plugins/needs-review/reactOnKillSteal/trunk/doc/README.txt`.
- Mazzakore: monstros e jogadores vêm de `$monstersList`/`$playersList` (o original lia hashes que o core não
  preenche mais e nunca disparava); `checkMonsterCondition` recebe o monstro (com o ID o bot caía).
- Testado (2026-11-03): A batendo num Poring, B bateu no mesmo; A: "Jogador PlugTesteB kill steals my Monstro
  Poring [1x]" e respondeu com o emote de raiva.

## Ligar
`sys.txt`: `loadPlugins_list ...,reactOnKillSteal`. `config.txt`:

```
reactOnKillSteal 1
reactOnKillSteal_timeout 20
reactOnKillSteal_timeoutSeed 15
reactOnKillSteal_forgetReactions 900
reactOnKillSteal e an;;c ei, esse e meu;;e ... {
    attackTargetOnly 1
    player_ksCount < 3
}
```
Atenção: o console do OpenKore (e o mzctl) trata `;;` como separador de comandos; ponha no `config.txt`, não por
`conf`. Aprendiz precisa de Habilidades Básicas para usar emote.
