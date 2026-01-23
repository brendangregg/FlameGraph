# Flame Graphs: Visualizando Código Profilado

Site Principal: http://www.brendangregg.com/flamegraphs.html

Exemplo (clique para ampliar):

[![Exemplo](http://www.brendangregg.com/FlameGraphs/cpu-bash-flamegraph.svg)](http://www.brendangregg.com/FlameGraphs/cpu-bash-flamegraph.svg)

Clique em uma caixa para ampliar o Flame Graph apenas para este quadro de pilha (stack frame).
Para pesquisar e destacar todos os quadros de pilha que correspondem a uma expressão regular, clique no botão _search_ (pesquisar) no canto superior direito ou pressione Ctrl-F.
Por padrão, a pesquisa diferencia maiúsculas de minúsculas, mas isso pode ser alternado pressionando Ctrl-I ou clicando no botão _ic_ no canto superior direito.

Outros sites:
- O artigo sobre Flame Graph na ACMQ e CACM: http://queue.acm.org/detail.cfm?id=2927301 http://cacm.acm.org/magazines/2016/6/202665-the-flame-graph/abstract
- Profiling de CPU usando Linux perf_events, DTrace, SystemTap ou ktap: http://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html
- Profiling de CPU usando XCode Instruments: http://schani.wordpress.com/2012/11/16/flame-graphs-for-instruments/
- Profiling de CPU usando Xperf.exe: http://randomascii.wordpress.com/2013/03/26/summarizing-xperf-cpu-usage-with-flame-graphs/
- Profiling de Memória: http://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html
- Outros exemplos, atualizações e notícias: http://www.brendangregg.com/flamegraphs.html#Updates

Flame graphs podem ser criados em três etapas:

1. Capturar pilhas (stacks)
2. Dobrar (fold) as pilhas
3. flamegraph.pl

1. Capturar pilhas
=================
Amostras de pilha podem ser capturadas usando Linux perf_events, FreeBSD pmcstat (hwpmc), DTrace, SystemTap e muitos outros profilers. Veja os conversores `stackcollapse-*`.

### Linux perf_events

Usando o `perf_events` do Linux (também conhecido como "perf") para capturar por 60 segundos, a 99 Hertz, amostras de pilha do kernel e do usuário, de todos os processos:

```
# perf record -F 99 -a -g -- sleep 60
# perf script > out.perf
```

Agora, capturando apenas o PID 181:

```
# perf record -F 99 -p 181 -g -- sleep 60
# perf script > out.perf
```

### DTrace

Usando DTrace para capturar por 60 segundos pilhas do kernel a 997 Hertz:

```
# dtrace -x stackframes=100 -n 'profile-997 /arg0/ { @[stack()] = count(); } tick-60s { exit(0); }' -o out.kern_stacks
```

Usando DTrace para capturar por 60 segundos pilhas de nível de usuário para o PID 12345 a 97 Hertz:

```
# dtrace -x ustackframes=100 -n 'profile-97 /pid == 12345 && arg1/ { @[ustack()] = count(); } tick-60s { exit(0); }' -o out.user_stacks
```

60 segundos de pilhas de nível de usuário, incluindo o tempo gasto no kernel, para o PID 12345 a 97 Hertz:

```
# dtrace -x ustackframes=100 -n 'profile-97 /pid == 12345/ { @[ustack()] = count(); } tick-60s { exit(0); }' -o out.user_stacks
```

Troque `ustack()` por `jstack()` se a aplicação tiver um ajudante de ustack para incluir quadros traduzidos (ex: quadros node.js). A taxa para coleta de pilha em nível de usuário é deliberadamente mais lenta que a do kernel, o que é especialmente importante ao usar `jstack()`, pois ele realiza trabalho adicional para traduzir os quadros.

2. Dobrar (fold) as pilhas
===========================
Use os programas `stackcollapse` para transformar as amostras de pilha em linhas únicas. Os programas fornecidos são:

- `stackcollapse.pl`: para pilhas DTrace
- `stackcollapse-perf.pl`: para saídas do "perf script" do Linux perf_events
- `stackcollapse-pmc.pl`: para pilhas `pmcstat -G` do FreeBSD
- `stackcollapse-stap.pl`: para pilhas SystemTap
- `stackcollapse-instruments.pl`: para XCode Instruments
- `stackcollapse-vtune.pl`: para perfis Intel VTune
- `stackcollapse-ljp.awk`: para Lightweight Java Profiler
- `stackcollapse-jstack.pl`: para saídas do jstack(1) do Java
- `stackcollapse-gdb.pl`: para pilhas gdb(1)
- `stackcollapse-go.pl`: para pilhas pprof do Golang
- `stackcollapse-vsprof.pl`: para perfis do Microsoft Visual Studio
- `stackcollapse-wcp.pl`: para saídas do wallClockProfiler

Exemplo de uso:

```
Para perf_events:
$ ./stackcollapse-perf.pl out.perf > out.folded

Para DTrace:
$ ./stackcollapse.pl out.kern_stacks > out.kern_folded
```

A saída se parece com isto:

```
unix`_sys_sysenter_post_swapgs 1401
unix`_sys_sysenter_post_swapgs;genunix`close 5
unix`_sys_sysenter_post_swapgs;genunix`close;genunix`closeandsetf 85
[...]
```

3. flamegraph.pl
================
Use `flamegraph.pl` para renderizar um SVG.

```
$ ./flamegraph.pl out.kern_folded > kernel.svg
```

Uma vantagem de ter o arquivo de entrada "dobrado" (e por que isso é separado do flamegraph.pl) é que você pode usar `grep` para funções de interesse. Ex:

```
$ grep cpuid out.kern_folded | ./flamegraph.pl > cpuid.svg
```

Exemplos Fornecidos
===================

### Linux perf_events

Uma saída de exemplo do "perf script" do Linux está incluída, compactada com gzip, como `example-perf-stacks.txt.gz`. O flame graph resultante é `example-perf.svg`:

[![Exemplo](http://www.brendangregg.com/FlameGraphs/example-perf.svg)](http://www.brendangregg.com/FlameGraphs/example-perf.svg)

Você pode criar isso usando:

```
$ gunzip -c example-perf-stacks.txt.gz | ./stackcollapse-perf.pl --all | ./flamegraph.pl --color=java --hash > example-perf.svg
```

Isso mostra meu fluxo de trabalho típico: eu compacto os perfis com gzip no sistema de destino e depois os copio para o meu laptop para análise. Como tenho centenas de perfis, eu os deixo compactados!

Como este perfil incluía Java, usei a paleta `--color=java` do `flamegraph.pl`. Também usei `stackcollapse-perf.pl --all`, que inclui todas as anotações que ajudam o `flamegraph.pl` a usar cores separadas para o código do kernel e do usuário. O flame graph resultante usa: verde == Java, amarelo == C++, vermelho == código nativo em modo de usuário, laranja == kernel.

### DTrace

Um exemplo de saída do DTrace também está incluído, `example-dtrace-stacks.txt`, e o flame graph resultante, `example-dtrace.svg`:

[![Exemplo](http://www.brendangregg.com/FlameGraphs/example-dtrace.svg)](http://www.brendangregg.com/FlameGraphs/example-dtrace.svg)

Você pode gerar isso usando:

```
$ ./stackcollapse.pl example-stacks.txt | ./flamegraph.pl > example.svg
```

Isso foi de uma investigação de desempenho específica: o Flame Graph identificou que o tempo de CPU estava sendo gasto no módulo `lofs` e quantificou esse tempo.

Opções
======
Veja a mensagem de USO (`--help`) para as opções:

USAGE: ./flamegraph.pl [opções] arquivo_de_entrada > arquivo_de_saida.svg

	--title TEXT     # muda o texto do título
	--subtitle TEXT  # título de segundo nível (opcional)
	--width NUM      # largura da imagem (padrão 1200)
	--height NUM     # altura de cada quadro (padrão 16)
	--minwidth NUM   # omite funções menores. Em pixels ou use "%" para 
	                 # porcentagem de tempo (padrão 0.1 pixels)
	--fonttype FONT  # tipo da fonte (padrão "Verdana")
	--fontsize NUM   # tamanho da fonte (padrão 12)
	--countname TEXT # rótulo do tipo de contagem (padrão "samples")
	--nametype TEXT  # rótulo do tipo de nome (padrão "Function:")
	--colors PALETTE # define a paleta de cores. opções: hot (padrão), mem,
	                 # io, wakeup, chain, java, js, perl, red, green, blue,
	                 # aqua, yellow, purple, orange
	--bgcolors COLOR # define as cores de fundo. gradientes: yellow
	                 # (padrão), blue, green, grey; cores fixas usem "#rrggbb"
	--hash           # cores são baseadas no hash do nome da função
	--cp             # usa paleta consistente (palette.map)
	--reverse        # gera um flame graph com a pilha invertida
	--inverted       # gráfico de gelo (icicle graph)
	--flamechart     # produz um flame chart (ordena por tempo, não mescla pilhas)
	--negate         # inverte as matizes diferenciais (azul<->vermelho)
	--notes TEXT     # adiciona comentário de notas no SVG (para depuração)
	--help           # esta mensagem

	ex,
	./flamegraph.pl --title="Flame Graph: malloc()" trace.txt > graph.svg

Como sugerido no exemplo, flame graphs podem processar rastros de qualquer evento, como `malloc()s`, desde que os rastros de pilha sejam coletados.

Paleta Consistente
==================
Se você usar a opção `--cp`, ele usará a seleção de `$colors` e gerará a paleta aleatoriamente como o normal. Quaisquer futuros flamegraphs criados com a opção `--cp` usarão o mesmo mapa de paleta. Quaisquer novos símbolos de futuros flamegraphs terão suas cores geradas aleatoriamente usando a seleção de `$colors`.

Se você não gostar da paleta, apenas delete o arquivo `palette.map`.

Isso permite que você mude seu esquema de cores entre flamegraphs para fazer as diferenças se destacarem BASTANTE.

Exemplo:

Digamos que temos 2 capturas, uma com um problema e outra quando estava funcionando:

```
cat working.folded | ./flamegraph.pl --cp > working.svg
# isso gera um palette.map, com a aparência normal gerada aleatoriamente.

cat broken.folded | ./flamegraph.pl --cp --colors mem > broken.svg
# este svg usará o mesmo palette.map para os mesmos eventos, mas um
# esquema de cores muito diferente para quaisquer novos eventos.
```
