# mazzaPapo

O chat dos bots fiéis do MazzaRO no jeito do bRO de 2004-2008 (fase F4 de
`mazzaro/docs/bots/PLANO-JOGADORES.md`; briefing em `mazzaro/docs/bots/F4-conversa.md`).

É **o dono do chat** do bot. O `mazzaJornada` e o `mazzaPessoa` continuam escolhendo *o que* falar; o mazzaPapo
cuida de *como* e *quando*, e responde PM e quem chama o nome.

| Parte | O que faz |
|---|---|
| F4.1 estilo | abreviações (vc, pq, q, naum, aki, tbm, blz, mals, vdd, msm, pra, hj...) com a intensidade da persona; caixa baixa; pontuação solta (sem ponto final, `??`, `!!`); emoticon ou risada do jeito do bot (`^^ *-* =/ ;x >< huahua rsrs kkk`); frase longa em rajada de 2-3 linhas; um erro de digitação por linha no máximo (tecla vizinha, letras trocadas, letra comida ou dobrada) e às vezes a correção `palavra*` na linha seguinte |
| F4.2 digitação | fila única: pensar/ler + 150-300 ms por letra, uma linha por vez, sem `sleep` (tique no `mainLoop_post`); o AFK do mazzaRitmo segura a fila e, na volta, o bot "lê o que perdeu" (+1-4 s); pausa grande na cidade não segura (é hora de conversar); com pressa na saída; fala pública velha (> 4 min) é descartada, PM espera |
| F4.3 assunto | 2-10 falas por hora ativa (faixa da persona × socializar do dia do `mazzaPessoa`; papel `quieto` e jeito `timido` falam menos), só com gente a até 14 células ou na cidade, nunca a menos de 2 min da última fala; eventos falam logo: carta (85%), monstro forte (55%), episódio novo (60%), mapa fechado, drop, mapa lotado; e perguntas que puxam resposta ("alguem sabe onde dropa...?") |
| F4.4 respostas | PM, chamado (nome ou apelido: "Lia" de LiaSacer), cumprimento público (35%) e pergunta pública (25%); classificação, memória por jogador, paciência e bloqueio do motor do `AnswerChat` (Henrybk); texto da persona quando ela tem (`pm`, `chamado`, `saudacao` do falas.txt e `resp_*` do papo.txt); "vc eh bot?" responde como gente, às vezes irritado, às vezes ignora; na luta, 60% só responde depois de matar o monstro; nunca responde a outro bot (`mazzaro/bots/*/bot.yml`), a GM nem a `mazzaPapo_ignorados` |
| F4.5 LLM local | opcional, só PM e chamado: Ollama `/api/chat` por socket não bloqueante (FIONBIO no Windows) lido no tique, HTTP/1.0 sem chunked, prompt de persona pt-BR 2004 (nome, classe, nível, mapa, meta do dia, jeito, papel), histórico curto por jogador, teto por hora, filtro de saída (cara de IA, palavrão pesado, acento, tamanho) e o estilo do F4.1 por cima; sem resposta em `llm_espera` s (padrão 8) responde por regra; 3 falhas seguidas = 10 min sem tentar |

## Ligar
Vem na lista `PLUGINS` do `mazzaro/bots/bots.py`, depois do `mazzaPessoa`. O gerador põe o bloco no `config.txt`:

```
mazzaPapo 1
mazzaPapo_jeito timido           # empolgado | veterano | zoeiro | timido (a personalidade)
mazzaPapo_abrev 0.54             # 0-1
mazzaPapo_minusculas 0.93
mazzaPapo_emoticon 0.34
mazzaPapo_rajada 0.16
mazzaPapo_erro 233               # 1 erro a cada ~N letras (0 = nunca)
mazzaPapo_corrige 0.68
mazzaPapo_digita 216 336         # ms por letra
mazzaPapo_ler 0.5 1.8            # s para ler antes de digitar a resposta
mazzaPapo_ignora 0.16
mazzaPapo_assunto 1 4            # falas puxadas por hora ativa (min max)
# mazzaPapo_llm http://127.0.0.1:11434
# mazzaPapo_llm_modelo qwen3:4b-instruct
mazzaPapo_llm_teto 20            # pedidos por hora
```
Outras: `mazzaPapo_respostas 0` (não responde nada), `mazzaPapo_ignorados A,B`, `mazzaPapo_gms A,B`,
`mazzaPapo_llm_espera 8`. `mazzaPapo 0` devolve tudo ao `mazzaJornada` como era.

LLM: o Ollama fica no notebook (`mazza@100.98.208.34`, Tailscale). Se a porta 11434 responder pela rede
(`curl http://100.98.208.34:11434/api/tags`), basta `mazzaPapo_llm http://100.98.208.34:11434`; se o Ollama só escutar
em localhost, abrir um túnel `ssh -N -L 11434:localhost:11434 mazza@100.98.208.34` e usar `http://127.0.0.1:11434`.

## API
- `mazzaPapo::dizer($txt, canal => 'c'|'pm', para => $nome, estilo => 0|1, origem => 'secao')`: põe na fila (com
  estilo); `"/e N texto"` vira emote + fala. O `mazzaJornada::dizer` manda tudo por aqui quando o plugin está ligado.
- `mazzaPapo::ligado()`, `mazzaPapo::respostas()`: o `mazzaJornada` não responde PM/chamado quando a segunda vale.
- Lê: `mazzaRitmo::estado()`, `mazzaJornada::emPausa()/texto()/temFala()`, `mazzaPessoa::plano()/papel()`.

## Frases
`papo.txt`: `[assunto_<tipo>]` e `[resp_<tipo>]`, com variantes `[secao@jeito]`. Uma seção `papo_<secao>` no
`falas.txt` do bot ganha das duas. Variáveis: `{nome} {lv} {prox} {pct} {falta} {zeny} {classe} {mapa} {cidade}
{item} {monstro} {periodo} {meta_dia} {jogador} {episodio} {lugar}`. Sem acento (`serverEncoding Western`).

## Log e console
`<logs>/papo_<conta>.log`: `epoch data hora canal origem texto` de cada linha mandada (canal `c` ou `pm:<nome>`,
origem = seção, `regra`, `llm`, `assunto_*`). É a fonte das linhas de bot do `mazzaro/tools/mz/papo_cego.py`.

`papo [status|fila|estilo <txt>|dizer <txt>|assunto [tipo]|resp <msg>|llm <msg>|ouvir <nome>|ignorar <nome>]`
(`ouvir` deixa um bot responder a outro até recarregar, para teste).

## Armadilhas
- O regex de despedida do AnswerChat casa "ate" dentro de nomes ("Rotateste"): o nome do bot sai da mensagem antes.
- "para" verbo ("nao para", "para de") não vira "pra".
- `$&` em qualquer regex pesa em todos os regex do Perl 5.12: o estilo usa grupo de captura.
- Perl 5.12 do start.exe: sem `s///r`, POSIX, `my $a`/`$b` com `sort`.
