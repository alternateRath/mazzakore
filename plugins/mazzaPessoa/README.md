# mazzaPessoa

Persona e papel social dos bots fiéis do MazzaRO (fase F3 do
[plano](../../../mazzaro/docs/bots/PLANO-JOGADORES.md)).

Cada bot ganha:
- **Um papel tirado do bRO real** ([pesquisa-bro.md](../../../mazzaro/docs/bots/pesquisa-bro.md), seção 2), com
  hábitos e falas próprios. As falas ficam nas seções `papel_*` do `falas.txt`, que o gerador junta de
  `mazzaro/bots/papeis/<papel>.txt`. O plugin fala pelo `mazzaJornada` e respeita o intervalo dele entre falas.

  | Papel | O que faz |
  |---|---|
  | `novato` | pergunta em público quando tem gente perto ("como q eu salvo na kafra?"), até o nível 40 |
  | `mentor` | do nível 30 em diante, puxa conversa com aprendiz perto (uma vez por dia por pessoa) |
  | `familia` | recruta na cidade para a "família" da guilda |
  | `vendedor` | anuncia `S>`/`C>` na cidade durante a pausa (só modelo ferreiro) |
  | `buff` | responde "buff plis" de quem está a até 14 células, com Bênção e Agilidade e atraso de gente; sem a skill, "naum tenho buff ainda" (só sacerdote) |
  | `pedinte` | na pausa, depois do passeio e sentado, abre a sala "Doa 7z e seja feliz" e pede poção |
  | `quieto` | upa calado: fala quase nada, não passeia na cidade |
  | `zoeiro` | implica e ri com gente perto |
  | `casual` | joga pouco (o gerador põe o perfil fim-de-semana do mazzaRitmo) |

- **Um vetor de Yee** com 10 motivações de 0 a 1: progresso, mecânica, competição, socializar, relação, equipe,
  descoberta, roleplay, customização e escapismo. A base vem do papel ±0,15, e por cima dela entra uma
  **deriva diária**: AR(1) com coeficiente 0,5, desvio estacionário `mazzaPessoa_deriva` (0,08-0,14) e semente
  conta + data. Cada dia sai diferente sem a pessoa virar outra (Lee 2016: o bot se entrega por ser
  auto-semelhante entre janelas de tempo). O vetor do dia escolhe a **meta do dia** (upar, conversar, explorar,
  enrolar, enfeitar) e ajusta os outros plugins, só na memória (regra 20 da pesquisa):

  | Motivações | O que muda |
  |---|---|
  | socializar, relação, equipe | `chance_fala_ambiente` do mazzaJornada; lugares e tempo do passeio na cidade (`mazzaRota_cidade`) |
  | progresso, mecânica, competição | mais tempo no mesmo canto e menos paradas (`mazzaRota_permanencia`, `mazzaRota_parada`) |
  | descoberta | mais mapas por sessão e sub-áreas longe (`mazzaRota_mapas`, `mazzaRota_longe`) |

  Com o mazzaPessoa ligado, essas chaves do mazzaRota saem do plano do dia; o bloco `mazzaRota_*` que o gerador
  escreve vale quando ele está desligado.

## Ligar
`bots.py` põe `mazzaPessoa` na `loadPlugins_list`. `bots.py --novo ... [--papel P]` sorteia o papel entre os
que servem ao modelo e escreve:

```
mazzaPessoa 1
mazzaPessoa_papel buff
mazzaPessoa_yee 0.18 0.50 0.29 0.66 0.49 0.83 0.20 0.49 0.25 0.60
mazzaPessoa_deriva 0.11
```

Console: `pessoa` (estado: papel, meta, vetor do dia, o que mudou), `pessoa simular [dias]` (os próximos dias),
`pessoa dia` (reaplica o dia).

API usada do mazzaJornada: `opcao(k, v)`, `falar(secoes, chance, force, vars)`, `texto(secao)`, `modo()`.

## Não faz (ainda)
- Guilda de verdade (`familia`), party com o novato (`mentor`), loja aberta (`vendedor`): mazzaSocial (F5) e
  mazzaMercado (F6). O `shopAuto_open` do core falha no kro-2026 ([plugins.md](../../mazzaro/bots/plugins.md)).
- Responder a quem dá esmola, KS de propósito (`zoeiro`): F4/F5.
