# mazzaRota

Rotas com jeito de gente para os bots fiéis do MazzaRO (fase F2 do
[plano](../../../mazzaro/docs/bots/PLANO-JOGADORES.md), regras 10-12 da
[pesquisa de comportamento](../../../mazzaro/docs/bots/pesquisa-comportamento.md)).

O `randomWalk` do OpenKore sorteia um ponto qualquer do mapa a cada passeio. A trajetória quase não repete trecho,
mas espalha o bot pelo mapa inteiro em poucos minutos. Gente faz outra coisa: fica num canto que conhece, volta
para onde tinha monstro e só depois de um tempo muda de lugar. O mazzaRota troca o `randomWalk` no `lockMap`
(hook `ai_processRandomWalk`, a mesma porta do lockMapSweep, que ele substitui) por:

- **Sub-áreas**: o mapa vira uma grade (2-4 por eixo, pelo tamanho). O bot fica 10-30 min numa e passa para uma
  vizinha; às vezes vai para uma longe. Cada bot tem uma preferência fixa por sub-área ("o canto dele"), sorteada
  da semente (conta) e do mapa, então dois bots no mesmo mapa ocupam lugares diferentes.
- **Memória de trechos** da última hora, na mesma grade de 5x5 células da régua. O próximo destino sai de 8
  candidatos: ganha o que menos repete trecho e mais passa por lugar ainda não visto.
- **Paradas** depois de chegar (3-20 s, olhando em volta com `look`) e, às vezes, **volta** a um destino anterior.
  O desvio lateral de cada rota fica com o plugin `Drunk`, ligado junto.
- **1-3 mapas por sessão**: uma etapa do `jornada.txt` pode ter `mapa1,mapa2,...`. O mazzaJornada pergunta
  `mazzaRota::mapa(\@abertos)`. O primeiro mapa da lista pesa mais, o resto vai pela preferência do bot. Depois de
  15-45 min, numa troca de sub-área, o bot pode mudar de mapa, até o número sorteado na sessão (45/35/20%).
  A sessão nova vem do hook `mazzaRitmo_chegada`.
- **Passeio na cidade**: na pausa, o mazzaJornada chama `mazzaRota::passeio($id)` antes de sentar. O bot visita
  1-3 lugares (Kafra, lojas, perto de quem está parado, o ponto da cidade do `jornada.txt`) e fica 10-60 s em
  cada um.

Os mapas alternativos dos modelos (`mazzaro/bots/modelos/*.yml`) são vizinhos da cidade-base com nível médio de
monstro parecido (spawns do rAthena pre-re + `mob_db`, mapas abertos no bro-01).

## Ligar
`bots.py` já põe `Drunk,mazzaRota` na `loadPlugins_list`, e o gerador escreve o bloco no `config.txt` sorteado por
bot:

```
mazzaRota 1
mazzaRota_permanencia 10 30     # minutos numa sub-area
mazzaRota_salto 8 30            # celulas ate o proximo destino na sub-area
mazzaRota_parada 0.35 3 20      # chance de parar ao chegar, de 3-20 s
mazzaRota_volta 0.06            # chance de voltar a um destino anterior
mazzaRota_longe 0.15            # chance de a proxima sub-area nao ser vizinha
mazzaRota_mapas 45 35 20        # % de sessoes com 1, 2 e 3 mapas
mazzaRota_troca 15 45           # minutos num mapa antes de poder trocar
mazzaRota_cidade 1 3 10 60      # lugares por pausa e segundos em cada
mazzaRota_grade 0 0             # 0 = pelo tamanho do mapa
mazzaRota_memoria 60            # minutos de memoria de trechos
mazzaRota_candidatos 8
mazzaRota_teste 0               # >0: minutos viram segundos x fator (teste rapido)
```

Console: `rota [status|grade|memoria|trocar|passeio]`.

## Não faz (ainda)
- Seguir em party com 0,5-3 s de atraso (regra 12): fica para o mazzaSocial (F5), quando houver party.
- Destino "com sentido" no campo (ir atrás de um monstro visto de longe, de um item no chão): o ataque e a coleta
  automáticos do core já cortam o passeio quando aparece alvo.
