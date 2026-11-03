# wait4party

Quem está em party espera e vai buscar o membro que sumiu da tela (calcula rota até a última posição que o
servidor mandou), senta junto quando ele senta e espera quando ele conjura uma skill da lista.

- Origem: `plugins/needs-review/wait4party/trunk` do openkore/openkore (Contrad, 2008-2010, GPLv3).
- Mudança no mazzakore: nome do mapa do membro sem depender do `.gat`.
- Testado (2026-11-03, kro-2026, dois bots de teste em party): o B foi para longe com `@warp`, o A disse
  "Party (PlugTesteB) lost", calculou rota até ele e "Party member PlugTesteB found!".

## Ligar
`sys.txt`: `loadPlugins_list ...,wait4party`. `config.txt`:

```
wait4party 1
wait4party_sameMapOnly 0      # 1 = só procura se o membro estiver no mesmo mapa
wait4party_waitBySitting 0    # 1 = em vez de procurar, senta e espera
wait4party_attackOnSearch 1   # 0 não, 1 revida, 2 ataca no caminho
wait4party_followSit 0        # senta quando o membro senta (desligue followSitAuto nele)
wait4party_timeout 5          # segundos sem ver o membro antes de ir buscar
wait4party_ignore             # nomes que não precisa esperar
wait4party_cast Cura, Benção  # espera enquanto um membro conjura estas skills
```
