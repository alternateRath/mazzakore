# randItemsTakeTimeout

O tempo de pegar o loot varia: a espera antes do primeiro item ("olhar o drop") e o intervalo entre um item e o
outro são sorteados em volta do `timeouts.txt` a cada vez.

- Origem: https://github.com/Henrybk/Plugins/tree/master/randItemsTakeTimeout (commit 473f544, 2022), de
  Henrybk. O repositório não declara licença; o autor mantém o core do OpenKore (GPL).
- Mazzakore: também sorteia a espera inicial, faixa configurável, unload corrigido (`delHook` -> `delHooks`).
- Testado (2026-11-03): três drops de um Poring pegos 1,4 s, 2,0 s e 3,4 s depois de aparecerem (intervalos
  0,6 s e 1,45 s; sem o plugin o timeouts.txt daria 0,3 s e depois 1 s fixo).

## Ligar
`sys.txt`: `loadPlugins_list ...,randItemsTakeTimeout`. `config.txt`:

```
randItemsTakeTimeout 1
randItemsTakeTimeout_min -60
randItemsTakeTimeout_max 40
randItemsTakeTimeout_startMax 1.5
```
