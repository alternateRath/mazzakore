# busFollow

`follow` pelo BUS: o mestre manda mapa e posição a cada segundo; quando o seguidor perde o mestre de vista, vai
direto até as coordenadas (o `follow` do core, sem party, só anda na direção em que o mestre sumiu).

- Origem: `plugins/needs-review/busFollow/trunk` do openkore/openkore (Revok, GPL).
- Mudanças no mazzakore: sem BUS avisa em vez de `die`; mapa comparado com `ne` (era `!=`, sempre "igual");
  posição tirada de `$char`; nome do mestre comparado com `eq` (era regex).
- Testado (2026-11-03): B com `follow 1`/`followTarget PlugTesteA`, fora da party; o A deu `@warp` para longe e o
  B "Calculando rota para encontrar o mestre: prontera (150, 250)" e chegou.

## Ligar
`sys.txt`: `bus 1`, `loadPlugins_list ...,busFollow` nos dois bots (o mestre também precisa do plugin para
mandar a posição). `config.txt` do seguidor: `follow 1`, `followTarget <nome>`. Em `timeouts.txt`:
`busFollow_sendInfo 1` (sem ela o plugin avisa e usa 1 s).
