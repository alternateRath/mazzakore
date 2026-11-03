# onMonsterKill

Roda um comando quando o alvo morre: emote de comemoração, uma fala, sentar. Com chance, atraso e intervalo
mínimo, para não virar "emote em toda morte".

- Origem: https://github.com/Henrybk/Plugins/tree/master/onMonsterKill (commit 473f544, 2022), de Henrybk.
  O repositório não declara licença; o autor mantém o core do OpenKore (GPL).
- Mazzakore: `_chance`, `_delay`, `_timeout` e `@monsterName` no comando.
- Testado (2026-11-03): matando Porings, `e lv` saiu 0,5-1 s depois de "Target died" (o B viu "*Heart*").
  Aprendiz sem Habilidades Básicas nível 2 não usa emote: o servidor recusa ("You haven't learned enough Basic
  Skills").

## Ligar
`sys.txt`: `loadPlugins_list ...,onMonsterKill`. `config.txt`:

```
onMonsterKill e lv {
    chance 10
    delay 0.5 2
    timeout 120
    name Poring          # opcional; também nameID, dmgFromYou, numAtkFromYou, moblv
}
```
