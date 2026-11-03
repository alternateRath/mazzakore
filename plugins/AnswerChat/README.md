# AnswerChat

Responde PM (e, se ligado, chat público com o nome do personagem) por padrões em pt-BR: cumprimento, despedida,
"vc é bot?", pedido de zeny/item, convite para grupo, ofensa, "qual seu level/atributo/skill", "onde upo no nível
N". Cada jogador tem memória: na 2ª e 3ª vez a resposta muda, a paciência ("stress") acaba e ele para de
responder (bloqueio que passa depois de algumas horas). Escreve com erros de digitação e às vezes manda a
correção "palavra*" logo depois.

- Origem: https://github.com/Henrybk/Plugins/tree/master/AnswerChat (commit 473f544, 2022-09-29), de Henry
  (OpenKore Brasil). O repositório não declara licença; o autor mantém o core do OpenKore (GPL).
- Mazzakore: motor reescrito (correção sai depois da frase, tempo de ler+digitar, fila por jogador, memória em
  JSON na pasta de logs, esquecimento); banco convertido para UTF-8, "bot?" testado antes de "vc é ...?", dicas de
  up só até 99 com lugares de 2004. As frases são um ponto de partida: o conteúdo por personalidade é do mazzaPapo.
- Testado (2026-11-03, PM do B para o A): "oi" -> "falea" + "falae*"; "me da zeny" -> "tebho naum" + "tenho*";
  "qual seu level?" -> "1"; depois de várias: "ta me incomodanod" + "incomodando*". Classificação conferida direto
  na função: "vc e bot?" -> bot, "onde upo no lvl 40?" -> "orc zumbi", "lvl 90" -> "gh".

## Ligar
`sys.txt`: `loadPlugins_list ...,AnswerChat`. `config.txt`:

```
AnswerChat_Pm 1
AnswerChat_Pub 0
AnswerChat_PubMax 1
AnswerChat_PubName 1
AnswerChat_Error 1
AnswerChat_ErrorChance 40
AnswerChat_cps 5
AnswerChat_ignore Aldren,Biazinha
AnswerChat_forgetHours 6
```
Não ligue junto com o `kadiliman` no mesmo canal (os dois responderiam) nem com as respostas de PM do
mazzaJornada sem decidir quem fala.
