# mazzakore — o OpenKore do projeto mazzaro

Fork do [OpenKore](https://github.com/OpenKore/openkore) (`alternateRath/mazzakore`, renomeado de
`alternateRath/openkore` em 2026-10-28). O `master` continua espelho do oficial; tudo que é nosso fica na branch
**`mazzaro`**, como no mazzathena (fork do rAthena). Clone local: `<ws>\openkore` (a pasta mantém o nome por causa da
exclusão do Defender).

Para que serve: **ferramenta de teste e de mapeamento** do MazzaRO (mazzathena `PACKETVER 20260219` + cliente kRO
2026-02-19) e do perfil de teste `kro-2020`. O bot entra como um jogador, roda um roteiro, anota os pacotes e o que vê
do mundo, e sai.

## O que a branch `mazzaro` acrescenta

| Peça | Onde | O que faz |
|---|---|---|
| serverType `kRO_RagexeRE_2026_02_19` | `src/Network/{Receive,Send}/kRO/RagexeRE_2026_02_19.pm` | protocolo do MazzaRO; base `RagexeRE_2021_11_03` (que já tinha `CZ_ENTER2` de 23 bytes), mais `ZC_REPUTE_INFO 0x0b8d` e o `ZC_CONFIG` tipo 5 |
| tabela de pacotes 2026 | `tables/kRO/RagexeRE_2026_02_19/recvpackets.txt` | 1.915 ids com nome; gerada pelo mazzaro (`tools/kore_recvpackets.py`) a partir da auditoria C1 (`g_packetLenMap` do cliente × `sizeof` do mazzathena) |
| tabelas pt-BR + 2001 | `tables/mazzaro/` (**fora do git**) | itens, descrições, skills e mapas em pt-BR (bRO 2007 > 2006 > 2005 > brAthena > inglês), as 34 zonas `mz*` e os 304 portais do alfa, o Historiador como portal com conversa; geradas localmente por `tools/kore_tables.py` do mazzaro (o `kore.py` gera se faltarem). Ficam fora do git porque trazem os textos oficiais do bRO e este fork é público (`.git/info/exclude`) |
| `plugins/mzteste` | roteiro de regressão (passos, esperas, timeout, resultado em YAML) |
| `plugins/mzmapa` | mapeamento: pacotes recebidos e enviados (tamanho visto × esperado, tratado ou não pelo OpenKore, ids fora da tabela) e censo do mundo (NPCs, monstros, portais por mapa) em `mapa.yml` |
| `mazzaro/config.txt`, `mazzaro/roteiros/` | config base do bot e os roteiros |
| XKore 2 no 2026 | `src/Base/Ragnarok/*`, `src/Network/XKore2/MapServer.pm`, ids do 2026 no Receive | o bot joga e o cliente kRO 2026 se conecta nele para mostrar (abaixo, "XKore 2") |

## Como usar (do mazzaro)
```
.\mz.ps1 up kro-2026
.\mz.ps1 kore kro-2026                            # roteiro regressao (entrar, chat, @warp 2001, @episode, volta)
.\mz.ps1 kore kro-2026 -Roteiro zonas2001         # anda de Prontera ate 2001 pelo Historiador e cruza um portal de 2001
.\mz.ps1 kore kro-2026 -Roteiro censo2001         # @warp em cada uma das 34 zonas; o mzmapa faz o censo
python tools\kore_mapa.py kro-2026 [--mundo]      # resumo do mapa.yml cruzado com a auditoria C1
.\mz.ps1 test server kro-2026                     # regressao + via pktproxy nativo + negativo (map-server derrubado)
.\mz.ps1 test server                              # o mesmo no perfil de teste kro-2020
```
- `tools/mz/kore.py` (no mazzaro) gera `run\kore\<perfil>\{control,tables}` (config do clone + `mazzaro/config.txt` +
  valores do perfil; `servers.txt` com o bloco `openkore:` de `server/profiles/<perfil>.yml`) e chama
  `start.exe --control=… --tables=… --plugins=… --logs=… --interface=Console`. A execução não escreve no clone: o que
  o OpenKore grava sozinho (`tables/npcs.txt`, `monsters.txt`, `portalsLOS.txt`, `fields/*.dist`) é ignorado pelo git.
- Recusa rodar se o perfil no ar não for o pedido (com o servidor errado o login falha sem mensagem clara).
- Roteiros: `nome | comando | espera | timeout_s`; esperas `estado:ingame`, `mapa:<nome>`, `log:<regex>`,
  `tempo:<s>`; comando `-` (nenhum) ou um comando do console (`c @warp …`, `move <mapa>`, …).
- Saída: `run\logs\kore\<perfil>\resultado.yml`, `mapa.yml`, `console_<conta>_<slot>.txt`; com `-Pacotes`, o log
  de pacotes vai para `run\captures\`.
- Regerar as tabelas depois de mudar zonas, itens ou a auditoria: `python tools\kore_tables.py` e
  `python tools\kore_recvpackets.py` (do mazzaro); só o `recvpackets.txt` e o `censo2001.txt` são commitados aqui.

## XKore 2: o bot joga, o cliente 2026 mostra (X0, 2026-10-28)
```
.\mz.ps1 kore kro-2026 -Xkore -Janela [-Roteiro xkore-demo]    # bot no MazzaRO + login/char/map falsos 6905/6906/6907
python tools\pktproxy.py --perfil kro-2026 --cliente kro-2026 --alvo 6905   # opcional: captura cliente <-> bot
.\mz.ps1 cliente kro-2026 -Porta 6901                          # 6901 = pelo pktproxy; 6905 = direto no bot
python tools\mz\visual.py kro-2026 --xkore --manter            # loga com o username do bot + xkore_senha
```
- O cliente entra com o `username` do bot e a `xkore_senha` de `client/teste-visual.local.yml` (o `kore.py` gera e
  grava como `adminPassword`, com `secureAdminPassword 0`; com 1 o OpenKore sorteia outra a cada início).
- **Visto em jogo**: login, servidor "MazzaRO XKore", escolha de personagem e mapa no cliente 2026. Cliente → bot →
  servidor: chat e `@warp mzprtvilg00` (o cliente carregou a zona de 2001). Bot → cliente: o roteiro `xkore-demo`
  fala e anda (`move 150 170`) e o cliente mostra o chat e o personagem andando. O bot vê o que o cliente faz.
- **`XKore_ressincronia 0`** (o `kore.py --xkore` liga): ao entrar, o `MapServer` só manda `ZC_NOTIFY_ACTORINIT
  0x0B1B` (sem ele o cliente 2026 carrega o mapa e ignora teclado e mouse). A ressincronia original (`send_player_info`,
  `send_inventory`, atores, skills, amigos…) empacota à mão formatos antigos (`01D7` de 11 bytes, `00A4`, `010F`,
  `0078`…) e o cliente 2026 trava/fecha no primeiro que não bate. Sem ela, o cliente só vê o que chegar do servidor
  depois de entrar: NPCs/monstros já parados em volta não aparecem até se mexerem ou o mapa mudar, inventário vazio
  até atualizar. Depois de um `@warp` pelo cliente o sprite do próprio personagem sumiu (só a barra de HP).
- Correções para o 2026: `packet_lut` do serverType (`0AC4`, `082D`, `09A0`, `0B72`, `0AC5`, `08B9`); o char falso
  trata `0B72` como `099D`; login e char falsos **não fecham** a conexão depois de responder (o cliente 2026 vê o
  fechamento como "Desconectado do servidor"; era uma corrida); sessão nunca 0 (o cliente não segue com
  `login_id1 = 0`); oito formatos que o ServerType0 escolhe pelo tamanho do `recvpackets.txt` fixados no serverType
  (os parsers do XKore 2 nascem antes da tabela carregar).
- O `AC_ACCEPT_LOGIN` do OpenKore preenche o texto "ip:porta" (128 bytes) da entrada do char-server, que o rAthena
  manda zerado; quem tem o texto conecta nele, então o `pktproxy` reescreve os dois.

## Fatos (verificados em 2026-10-28)
- **kro-2026**: `serverType kRO_RagexeRE_2026_02_19`, `charBlockSize 175` (o `CHARACTER_INFO` do mazzathena tem nome
  de 24 bytes), tabelas `mazzaro;translated/kRO_english;kRO/RagexeRE_2026_02_19;kRO`. Login `0x0064` com a versão do
  `servers.txt` (55) passa. Regressão em ~8 s; `zonas2001` em ~63 s; `censo2001` em ~150 s. Nos 44 ids que o
  servidor mandou nessas sessões, nenhum ficou sem handler e nenhum tamanho divergiu da tabela.
- **kro-2020**: `serverType kRO_RagexeRE_2020_03_04a`, tabelas `mazzaro;translated/kRO_english;kRO/RagexeRE_2020_04_01b;kRO`,
  `charBlockSize 155`, `masterLogin_packet 0064` (o Send 2020 usa `0x0ACF`, o login OTP do kRO oficial).
- A pasta listada primeiro no `addTableFolders` vence, e o arquivo é usado inteiro (não mescla): por isso as tabelas de
  `tables/mazzaro/` são completas (o inglês como base).
- Conta `mazzabot`/`mazzabot` (account_id 2000001, `group_id 99`), personagem `mazzabot` no slot 0; conta local de
  teste, só existe no banco local.
- Armadilhas: `start.exe` embute o **Perl 5.12** (sem `s///r`); a interface `Console::Win32` precisa de console de
  verdade (console oculto próprio, log pelo `logConsole`); `dcPause 0`; `portalRecord 0`; o log da sessão é
  `console_<conta>_<slot>.txt` e sai em cp1252 (locale do sistema); um `sub q` num plugin colide com o operador `q()`.
- O censo enxerga só o raio de visão a partir do ponto de chegada do Historiador (25 dos 35 mapas tiveram algo).

## Não verificado
- Combate, itens, troca, grupo e guilda pelo bot no 2026 (o OpenKore tem as rotinas; nenhum roteiro as exercita ainda).
- XKore 2: ressincronia no formato 2026 (estado, inventário, atores em volta); troca de mapa iniciada pelo bot;
  comandos para o bot sem roteiro (hoje só pelo console visível ou por roteiro); perfil `kro-2020` em XKore 2.
- Perfis Sabine (`alpha-2001`, `beta1-2002`): sem bloco `openkore`; o OpenKore não tem serverType para 2001-2002.
- `kro-2021`: bloco `openkore` escrito, servidor ainda não compilado com 20211103.
