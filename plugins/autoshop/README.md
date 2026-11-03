# autoshop

Antes de abrir a loja, o mercador procura um ponto que não fique colado em outra loja, chat ou jogador (mapa de
pesos 29x29 em volta: jogador = 5 na célula; loja/chat = 5 no dono caindo até 4 células), como gente que
procura "um cantinho" na rua.

- Origem: `plugins/needs-review/autoshop/trunk` do openkore/openkore (Arachno, v0.8, GPLv2).
- Mazzakore: reescrito para o core atual (o original lia `%players`, que não é mais preenchido). Não abre a loja
  sozinho: segura o `shopAuto_open` do core enquanto o ponto está ocupado e anda até um ponto livre; lá o core
  abre a loja com o `shop.txt`.
- Testado (2026-11-03, Prontera): com um chat aberto a 2 células, o B disse "lugar ocupado (peso 3)", andou de
  (151,99) para (146,96) e lá o peso era 0. Comandos `autoshop` e `autoshop mapa` ok.

## Ligar
`sys.txt`: `loadPlugins_list ...,autoshop`. `config.txt`:

```
autoshop 1
autoshop_maxweight 0      # 0..5
autoshop_radius 5         # 1..14
autoshop_tries 16
autoshop_inTownOnly 1
shopAuto_open 1           # quem abre a loja é o core
lockMap prontera          # o shopAuto_open do core só abre no lockMap
```
Comandos: `autoshop` (sugere ponto), `autoshop mapa` (grava `autoshop_mapa.txt` na pasta de logs).

## Cuidado (core, não o plugin)
No kro-2026 a abertura automática do core falha: a tarefa da skill Comércio espera uma confirmação que não chega
("Não foi possível usar a habilidade Comércio em 3 tentativas") e o personagem fica preso esperando a janela da
loja. Na mão funciona: `ss 41 10` e depois `openshop` com `shop_useSkill 0`. O pacote `0B40` aparece como
desconhecido. `shop.txt` separa nome, preço e quantidade por TAB. Precisa resolver isso antes dos bots mercadores.
