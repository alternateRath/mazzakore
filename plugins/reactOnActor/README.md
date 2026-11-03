# reactOnActor

Roda um comando quando aparece (ou está perto) um ator que casa com as condições: jogador de tal classe, guild,
chapéu, nível, distância, sentado, morto; monstro, NPC, portal, pet. Ex.: acenar para quem chega perto, pedir
cura a um sacerdote, comentar o chapéu de alguém.

- Origem: `plugins/needs-review/reactOnActor/trunk` do openkore/openkore (hakore; porte 2.1 de Kissa2k; GPL).
  Opções completas em `plugins/needs-review/reactOnActor/trunk/doc/README.txt`.
- Mazzakore: ator achado nas listas atuais (o original caía nos hashes velhos e nunca reagia); além dos pacotes,
  olha os atores uma vez por segundo, porque o pacote de andar chega quando o ator COMEÇA a andar (ainda longe) e
  `actor_dist` quase nunca casava.
- Testado (2026-11-03): o B andou até 1 célula do A; o A reagiu com `e ho` (17:24:07), e de novo só depois do
  `actor_timeout`.

## Ligar
`sys.txt`: `loadPlugins_list ...,reactOnActor`. `config.txt`:

```
reactOnActor e ho {
    actor_type player
    actor_dist < 4
    actor_timeout 120     # por bloco: sem isso repete a cada segundo
    inLockOnly 0
}
```
`$actor->{name}`, `{binID}`, `{x}`, `{y}`, `{type}` no comando viram os dados do ator.
