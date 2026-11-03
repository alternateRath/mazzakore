# shopper

Compra de lojas de jogadores (vending) o que está numa lista, até um preço máximo, como quem passa olhando as
lojas da rua: espera uns segundos ao ver uma loja nova, abre a lista, compra tudo o que casa de uma vez e não
volta na mesma loja antes de `shopper_revisit`.

- Origem: `plugins/needs-review/shopper/trunk` do openkore/openkore (kaliwanagan, 2006, GPL).
- Mazzakore: reescrito (o original nunca entrava na loja: o relógio era zerado a cada tick; e usava a API de
  inventário antiga). Respeita o zeny que tem e `checkSelfCondition` por bloco.
- Testado (2026-11-03, Prontera): o B abriu loja com 10 Poções Vermelhas a 40z; o A (shopper com
  `maxPrice 50`, `maxAmount 3`) abriu a lista sozinho e comprou 3 (zeny 1000 -> 880).

## Ligar
`sys.txt`: `loadPlugins_list ...,shopper`. `config.txt`:

```
shopper_revisit 600
shopper_maxDist 12
shopper Poção Vermelha {
    maxPrice 50
    maxAmount 20      # desce a cada compra; 0 desliga o bloco
    zeny > 2000       # condições normais de checkSelfCondition
}
```
