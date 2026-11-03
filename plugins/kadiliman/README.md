# kadiliman

Chat sem LLM: guarda as frases que lê e responde emendando o começo de uma frase conhecida com o fim de outra,
a partir de uma palavra da mensagem (estilo "Borg"). Sai coisa meio torta, como chat de MMO. Espera o tempo de
ler e digitar antes de responder.

- Origem: `plugins/needs-review/kadiliman/trunk` do openkore/openkore (kaliwanagan 2005; Thrice; Mucilon; GPL).
- Mazzakore: a cola do plugin foi reescrita (lia o pacote cru, onde o nome vinha grudado e o PM vinha sem texto;
  empilhava "chatBot" na IA e travava o resto); o `Chatbot/Kadiliman.pm` foi limpo (UTF-8, palavras com acento,
  regex escapado, arquivo na pasta de controle do bot, salva no máximo a cada minuto, até 5000 frases).
- Testado (2026-11-03): com 8 frases-semente, B no chat público "alguem vende pocao" -> A "nao tenho pocao
  vermelha barato"; "o esgoto ta bom pra upar?" -> "prontera ta cheio de barata hoje".

## Ligar
`sys.txt`: `loadPlugins_list ...,kadiliman`. `config.txt`:

```
chatBot Kadiliman {
    scriptfile kadiliman.txt   # na pasta de controle do bot; semeie com frases do personagem
    learn 1
    replyRate 30
    onPublicChat 1
    onPrivateMessage 0
    inLockOnly 0
    wpm 65
    smileys ^^,xD,:)
    smileyRate 20
    noPlayers Aldren,Biazinha  # outros bots
    noWords bot,macro
    timesToBlockPM 10
    timeToResetCount 300
}
```
Com `learn 1` ele aprende tudo o que lê (inclusive besteira); para personalidade fixa use `learn 0` e um arquivo
curado.
