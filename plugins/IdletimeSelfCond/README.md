# IdletimeSelfCond

Acrescenta `whenIdleFor <s>` (e `whenNotIdleFor <s>`) a qualquer bloco que use as condições normais
(`doCommand`, `useSelf_skill`, `useSelf_item`, `attackSkillSlot`, blocos de plugins...). Ocioso = fila da IA vazia.
Serve para "parado há um tempo -> senta, olha em volta, solta um emote, fala sozinho".

- Origem: https://github.com/Henrybk/Plugins/tree/master/IdletimeSelfCond (commit 473f544, 2022), de Henrybk.
  O repositório não declara licença; o autor mantém o core do OpenKore (GPL).
- Mazzakore: reescrito pequeno (o relógio do original começava valendo e só andava quando alguma condição era
  checada; podia desfazer a reprovação de outro plugin).
- Testado (2026-11-03): `doCommand e ic { whenIdleFor 8 }` soltou o emote depois de 8 s parado.

## Ligar
`sys.txt`: `loadPlugins_list ...,IdletimeSelfCond`. Exemplo:

```
doCommand sit {
    whenIdleFor 25
    timeout 300
    inLockOnly 1
}
```
