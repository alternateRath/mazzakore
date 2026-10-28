# kore/ — OpenKore como teste sem tela (E3)

O OpenKore (clone `<ws>\openkore`, fork `alternateRath/openkore`, **nunca editado**) entra no servidor como um
jogador de verdade, roda um roteiro e sai. É a regressão do mazzathena sem abrir o cliente gráfico.
Roda no **perfil de teste `kro-2020`** (`deps.lock` `server.perfil_teste`): o OpenKore não tem serverType para o
protocolo 2026 do MazzaRO. O que ele testa (scripts, zonas, Motor de Episódios, quedas) é o mesmo código das duas
pastas de build.

```
.\mz.ps1 test server                 # sobe o perfil se preciso, regressao (passa) + negativo (falha) + restaura
.\mz.ps1 kore                        # so o roteiro 'regressao' contra o perfil atual (kro-2020)
.\mz.ps1 kore kro-2020 -Roteiro negativo -Derrubar map@espera
.\mz.ps1 kore -Pacotes               # idem, com debugPacket_*: log de pacotes copiado para run\captures\
.\mz.ps1 kore -Janela                # o OpenKore numa janela visivel (para olhar o que ele faz)
```

## Como funciona
- [`tools/mz/kore.py`](../tools/mz/kore.py) gera em `run\kore\<perfil>\` o `control\config.txt` e o `control\sys.txt`
  (padrões do clone + [`config.txt`](config.txt) daqui + valores do perfil) e o `tables\servers.txt` com um único
  bloco `[Mazzaro <perfil>]` montado do bloco `openkore:` de `server/profiles/<perfil>.yml`. Tudo entra **na frente**
  dos caminhos do clone via `start.exe --control=… --tables=… --plugins=… --logs=…` (o OpenKore procura em ordem).
- `tools/kore_fields.py` converte o `map_cache.dat` do overlay em `.fld2` para os 34 mapas que o pacote oficial de
  fields não tem (zonas históricas `mz*`); o bloco do servidor aponta `fieldsFolder` para `run\kore\fields`.
- O plugin [`plugins/mzteste`](plugins/mzteste/mzteste.pl) lê o roteiro, executa um passo por vez e grava
  `run\logs\kore\<perfil>\resultado.yml`. Queda da conexão com o map-server depois de entrar = falha imediata.
- Roteiros em [`roteiros/`](roteiros/): `nome | comando | espera | timeout_s`; esperas `estado:ingame`, `mapa:<nome>`,
  `log:<regex>`, `tempo:<s>`. `regressao`: entrar → chat → `@warp mzprtvilg00` → `@episode` → `@go 0`.

## Fatos (verificados em 2026-10-27, perfil kro-2020)
- `serverType kRO_RagexeRE_2020_03_04a`, tabelas `translated/kRO_english;kRO/RagexeRE_2020_04_01b;kRO`,
  `charBlockSize 155` (2017-08 a 2020-10; 175 a partir de 20201007, 247 a partir de 20211103).
- Login: o Send `RagexeRE_2020_03_04a` usa `0x0ACF` (login OTP do kRO oficial). O rAthena aceita `0x0064`, então o
  bloco gerado põe `masterLogin_packet 0064` (o OpenKore manda o `CA_LOGIN` clássico).
- `use_web_auth_token: yes` do rAthena **não** atrapalhou: login → char → mapa em ~2 s.
- Conta `mazzabot`/`mazzabot` (account_id 2000001, `group_id 99` para `@warp`/`@episode`), personagem `mazzabot`
  no slot 0. Conta local de teste, só existe no banco local. Se sumir: `new_account: yes` cria com `mazzabot_M`.
- Armadilhas resolvidas: `start.exe` embute o **Perl 5.12** (sem `s///r`); a interface `Console::Win32` precisa de
  console de verdade (stdout em arquivo = avisos do `Text::Wrap` e não sai no quit) → console oculto próprio e log pelo
  `logConsole`; `dcPause 1` do padrão espera Enter no "Bye!" (desligado aqui); `portalRecord 0` para não gravar
  `tables\portals.txt` no clone; o log da sessão é `console_<conta>_<slot>.txt`, não o `console.txt`.
- Saída do OpenKore está em pt-BR (locale do sistema) e em cp1252.

## Bot mínimo para o MazzaRO (C2, 2026-10-27)
O OpenKore não fala o protocolo 2026; para o `kro-2026` (perfil sem bloco `openkore:`) a regressão roda com
[`tools/mz/bot.py`](../tools/mz/bot.py), um bot em Python com os **mesmos roteiros** e o mesmo `resultado.yml`:
```
.\mz.ps1 test server kro-2026        # regressao (passa) + via pktproxy nativo (sem dessincronizacao) + negativo (falha)
.\mz.ps1 bot kro-2026                # so a regressao; --roteiro negativo --derrubar map@espera; --porta 6901 (proxy)
```
- Enquadra os pacotes pela tabela do cliente 2026 (`client/profiles/kro-2026.yml`, `nativo`); manda os C>S como o
  cliente real (capturas nativas): `CA_LOGIN 0x64` com versão `0x80000000`, `0x65`, `0x09a1`, `0x66`, `CZ_ENTER2
  0x0436` de 23 bytes, `0x007d`, `0x0447`, `0x00f3` (chat `"<nome> : <texto>"`), keepalive `0x0360` + `0x0b1c` a cada
  10 s, `0x018a` ao sair. Offsets S>C medidos por `offsetof` (nome do personagem em +108 do `CHARACTER_INFO`, slot em
  +138).
- **Entrada no mapa**: o rAthena manda `ZC_ACCEPT_ENTER` e logo um `ZC_NPCACK_MAPMOVE 0x0091` para o mesmo mapa; o
  cliente responde com um único `LoadEndAck`. O `LoadEndAck` só vale depois que os dados do personagem chegam do
  char-server, e até lá o map-server **ignora qualquer outro pacote** (`sd->prev == nullptr`). O bot, como o cliente,
  espera o `ZC_INVENTORY_END 0x0b0b`, manda `CZ_BLOCKING_PLAY_CANCEL 0x0447` e só se considera no mapa com
  `ZC_NOTIFY_ACTORINIT 0x0b1b`; o mesmo depois de cada `@warp`. Sem isso o primeiro chat some sem erro.
- Saída em `run\logs\bot\<perfil>\`: `resultado.yml` (com os últimos textos recebidos) e `pacotes.txt` (um pacote
  por linha, com o texto legível de cada S>C).
- Não faz: andar, combate, itens, NPC, pincode, troca de map-server (`0x0ac7` implementado, não exercitado).

## Não verificado
- **XKore 2** (OpenKore como proxy entre o `mazzaro.exe` e o rAthena: `XKore 2`, `XKore_listenIp 127.0.0.1`,
  `XKore_listenPort 6901`, cliente apontando o `clientinfo.xml` para 6901) — documentado, não testado. É a forma de
  capturar o cliente oficial com o mesmo decodificador; o E4 (`pktproxy`) cobre isso por outro caminho.
- Perfis Sabine (`alpha-2001`, `beta1-2002`): sem bloco `openkore` (OpenKore não tem serverType para 2001-2002).
- `kro-2021`: bloco `openkore` escrito (`kRO_RagexeRE_2021_11_03`, tabelas `Ragexe_2021_11_03`, `charBlockSize 175`:
  o `CHARACTER_INFO` do rAthena mantém nome de 24 bytes; o 247 do OpenKore é o kRO oficial com nome de 96 — conferir
  no E5), servidor ainda não compilado com 20211103.
