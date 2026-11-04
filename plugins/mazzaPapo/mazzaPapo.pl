# =============================================================================
#  mazzaPapo - o chat dos bots fieis do MazzaRO, do jeito do bRO de 2004-2008
#  (mazzakore, branch mazzaro; fase F4 de mazzaro/docs/bots/PLANO-JOGADORES.md)
#
#  Dono do chat do bot: os outros plugins escolhem O QUE falar (mazzaJornada,
#  mazzaPessoa) e o mazzaPapo cuida de COMO e QUANDO.
#   F4.1 estilo     abreviacoes (vc pq q naum aki tbm blz mals vdd msm), caixa
#                   baixa, pontuacao solta, emoticons e risada do jeito do bot,
#                   frase longa em rajada de linhas curtas, erro de digitacao com
#                   correcao "palavra*" na linha seguinte
#   F4.2 digitacao  fila: ler (0,5-2 s) + 150-300 ms por letra, uma linha por vez,
#                   sem sleep (tique no mainLoop_post); o AFK do mazzaRitmo segura
#                   a fila; as vezes ignora, as vezes so responde depois da luta
#   F4.3 assunto    2-10 falas por hora ativa conforme a persona (socializar do
#                   vetor do dia do mazzaPessoa), so com gente perto ou na cidade,
#                   sobre o que acontece: carta, drop, monstro forte, mapa cheio,
#                   morte, xp, zeny, episodio novo, perguntas ("alguem sabe...?")
#   F4.4 respostas  PM, quem chama o nome, cumprimento e pergunta no publico (o
#                   mazzaJornada deixa de responder quando o mazzaPapo esta on):
#                   regras do AnswerChat (memoria, paciencia, bloqueio) + falas da
#                   persona; nunca responde a outro bot (mazzaro/bots/*/bot.yml) nem GM
#   F4.5 LLM local  opcional, so PM e chamado: Ollama (/api/chat) por socket nao
#                   bloqueante lido no tique; teto por hora, filtro de saida e o
#                   estilo do F4.1 por cima; sem resposta em ~8 s cai nas regras
#
#  API:  mazzaPapo::dizer($txt, canal => 'c'|'pm', para => $nome, estilo => 0|1)
#        mazzaPapo::ligado()      (o mazzaJornada::dizer manda tudo por aqui)
#        mazzaPapo::respostas()   (o mazzaJornada nao responde PM/chamado)
#
#  config.txt do bot (o gerador sorteia por personalidade; todos opcionais):
#   mazzaPapo 1                     0 desliga (tudo volta para o mazzaJornada)
#   mazzaPapo_jeito veterano        empolgado | veterano | zoeiro | timido
#   mazzaPapo_abrev 0.6             0-1: quanto abrevia
#   mazzaPapo_minusculas 0.85       chance de escrever tudo em minusculas
#   mazzaPapo_emoticon 0.2          chance de emoticon/risada no fim
#   mazzaPapo_rajada 0.35           chance de quebrar frase longa em linhas
#   mazzaPapo_erro 150              1 erro a cada ~N letras (0 = nunca erra)
#   mazzaPapo_corrige 0.6           chance de mandar a correcao "palavra*"
#   mazzaPapo_digita 150 300        ms por letra
#   mazzaPapo_ler 0.5 2             s para ler a mensagem antes de digitar
#   mazzaPapo_ignora 0.1            chance de nem responder
#   mazzaPapo_assunto 2 10          falas por hora ativa (min..max pelo socializar)
#   mazzaPapo_respostas 1           0 = nao responde nada (so o estilo e a fila)
#   mazzaPapo_ignorados A,B         nomes extras sem resposta automatica
#   mazzaPapo_gms A,B               GMs (sem resposta automatica)
#   mazzaPapo_llm http://127.0.0.1:11434    vazio = sem LLM
#   mazzaPapo_llm_modelo qwen3:4b-instruct
#   mazzaPapo_llm_teto 20           pedidos por hora
#   mazzaPapo_llm_espera 8          segundos ate desistir e responder por regra
#
#  Frases: plugins/mazzaPapo/papo.txt ([assunto_*], [resp_*], com variantes
#  [secao@jeito]); uma secao papo_<nome> no falas.txt do bot ganha da do arquivo.
#  Log: <logs>/papo_<conta>.log (epoch, canal, origem, texto) para a regua.
#  Console: papo [status|fila|estilo <txt>|dizer <txt>|assunto [tipo]|resp <msg>|llm <msg>|ouvir <nome>|ignorar <nome>]
#  Perl 5.12 (o do start.exe): nada de s///r, sem POSIX, sem my $a/$b junto de sort.
# =============================================================================
package mazzaPapo;

use strict;
use warnings;
use Time::HiRes qw(time);
use IO::Socket::INET;
use IO::Select;
use Socket qw(inet_aton sockaddr_in);
use JSON::Tiny qw(encode_json decode_json);

use Plugins;
use Globals qw($char %config $field $net $playersList $monstersList $messageSender);
use Log qw(message warning debug);
use Misc qw(sendMessage);
use Commands;
use Settings;
use Network;
use Utils qw(distance);
use AI;

my $NAME = 'mazzaPapo';
my $PASTA = $Plugins::current_plugin_folder;
Plugins::register($NAME, 'Chat dos bots do MazzaRO no jeito do bRO 2004', \&unload, \&unload);

my $hooks = Plugins::addHooks(
	['start3',             \&carregar],
	['mainLoop_post',      \&tique],
	['packet_privMsg',     \&onPM],
	['packet_pubMsg',      \&onPub],
	['item_gathered',      \&onItem],
	['add_monster_list',   \&onMonstro],
	['target_died',        \&onMatou],
	['self_died',          \&onMorte],
);
my $logHook = Log::addHook(\&onLog);
my $cmds = Commands::register(['papo', 'Chat do bot (status|fila|estilo|dizer|assunto|resp|llm)', \&cmdPapo]);

sub unload {
	Plugins::delHooks($hooks);
	Log::delHook($logHook);
	Commands::unregister($cmds);
	llmFechar();
}

# ------------------------------------------------------------ parametros ---
sub cfg { my ($k, $d) = @_; my $v = $config{"${NAME}_$k"}; return defined $v && length $v ? $v : $d; }
sub nums { my ($k, @d) = @_; my @v = grep { length } split /[\s,]+/, cfg($k, ''); return @v >= @d ? @v[0 .. $#d] : @d; }
sub ligado { return !defined $config{$NAME} || !length $config{$NAME} || $config{$NAME} ? 1 : 0; }
sub respostas { return ligado() && cfg('respostas', 1) ? 1 : 0; }
sub jeito { my $j = lc cfg('jeito', 'veterano'); return $j =~ /^(empolgado|veterano|zoeiro|timido)$/ ? $j : 'veterano'; }
sub rnd { my ($x, $y) = @_; return $x + rand($y - $x); }
sub escolhe { return @_ ? $_[int rand @_] : undef; }
sub noJogo { return $net && $net->getState() == Network::IN_GAME && $char && $field; }

# ------------------------------------------------------------------ frases ---
my (%frases, %ignorados, $carregado, $temAnswer);
our (%llm, $ultMonstro);   # pedido ao LLM em andamento; ultimo monstro morto

sub carregar {
	%frases = ();
	my $sec = 'geral';
	if (open(my $fh, '<:encoding(UTF-8)', "$PASTA/papo.txt")) {
		while (my $l = <$fh>) {
			chomp $l; $l =~ s/\r//g;
			next if $l =~ /^\s*(#|$)/;
			if ($l =~ /^\s*\[(.+?)\]\s*$/) { $sec = lc $1; next; }
			$l =~ s/^\s+|\s+$//g;
			push @{ $frases{$sec} }, $l;
		}
		close $fh;
	} else {
		warning "[$NAME] $PASTA/papo.txt nao encontrado: sem assuntos proprios.\n";
	}
	# motor de respostas do AnswerChat (Henrybk), sem ligar o plugin dele
	$temAnswer = defined &AnswerDatabase::AnswerDatabase ? 1 : 0;
	unless ($temAnswer) {
		my $arq = "$PASTA/../AnswerChat/AnswerDatabase.pm";
		$temAnswer = (-f $arq && eval { require $arq; 1 }) ? 1 : 0;
		warning "[$NAME] AnswerDatabase nao carregou ($@): respostas so pela persona.\n" if !$temAnswer && $@;
	}
	carregarIgnorados();
	$carregado = 1;
	message sprintf("[%s] %s, jeito %s, %d secoes de frases, %d nomes ignorados, respostas %s, LLM %s.\n", $NAME,
		ligado() ? 'ligado' : 'DESLIGADO', jeito(), scalar keys %frases, scalar keys %ignorados,
		respostas() ? ($temAnswer ? 'AnswerChat+persona' : 'persona') : 'nao', cfg('llm', '') || 'nao'), 'success';
}

# outros bots fieis (mazzaro/bots/*/bot.yml, campo "nome:" do personagem) + mazzaPapo_ignorados + GMs
sub carregarIgnorados {
	%ignorados = ();
	my $dir = "$PASTA/../../mazzaro/bots";
	if (opendir(my $dh, $dir)) {
		for my $b (readdir $dh) {
			next if $b =~ /^\./;
			open(my $fh, '<', "$dir/$b/bot.yml") or next;
			while (my $l = <$fh>) {
				$l =~ s/\s+#.*//;
				$ignorados{ lc $1 } = 1 if $l =~ /^\s+nome:\s*['"]?([^'"\r\n]+?)['"]?\s*$/;
			}
			close $fh;
		}
		closedir $dh;
	}
	for my $k ('ignorados', 'gms') { $ignorados{ lc $_ } = 1 for grep { length } split /\s*,\s*/, cfg($k, ''); }
}

sub ignorado {
	my ($quem) = @_;
	return 1 unless defined $quem && length $quem;
	return 1 if $char && $quem eq $char->{name};
	return 1 if $ignorados{ lc $quem };
	return 1 if $quem =~ /^\[?GM[\]\s_-]/i;
	return 0;
}

# texto de uma secao: papo_<s> do falas.txt do bot > <s>@<jeito> > <s> do papo.txt; com as variaveis
sub frase {
	my ($sec, %v) = @_;
	my $txt;
	if (defined &mazzaJornada::temFala && mazzaJornada::temFala("papo_$sec")) {
		$txt = mazzaJornada::texto("papo_$sec", %{ varsPadrao() }, %v);
	} else {
		my $l = $frases{ "$sec\@" . jeito() } || $frases{$sec} or return undef;
		$txt = $l->[int rand @$l];
	}
	return undef unless defined $txt;
	%v = (%{ varsPadrao() }, %v);
	$txt =~ s/\{(\w+)\}/defined $v{$1} ? $v{$1} : ''/ge;
	return $txt;
}

# variaveis que toda frase pode usar
sub varsPadrao {
	my %v;
	return \%v unless $char;
	$v{nome} = $char->{name};
	$v{lv} = $char->{lv};
	$v{prox} = $char->{lv} + 1;
	$v{pct} = $char->{exp_max} ? int(100 * ($char->{exp} || 0) / $char->{exp_max}) : 0;
	$v{falta} = 100 - $v{pct};
	$v{zeny} = kzeny($char->{zeny} || 0);
	$v{mapa} = $field ? $field->baseName : '';
	$v{cidade} = $v{mapa};
	my %job = (0 => 'aprendiz', 1 => 'espadachim', 2 => 'mago', 3 => 'arqueiro', 4 => 'novico', 5 => 'mercador',
		6 => 'gatuno', 7 => 'cavaleiro', 8 => 'sacerdote', 9 => 'bruxo', 10 => 'ferreiro', 11 => 'cacador', 12 => 'mercenario');
	$v{classe} = $job{ $char->{jobID} || 0 } || 'aventureiro';
	$v{monstro} = $ultMonstro || 'poring';
	my @inv = $char->inventory ? grep { $_->{name} && !$_->{equipped} } @{ $char->inventory->getItems } : ();
	$v{item} = @inv ? semAcento($inv[int rand @inv]{name}) : 'pocao vermelha';
	my @h = localtime; $v{periodo} = $h[2] < 5 ? 'madrugada' : $h[2] < 12 ? 'dia' : $h[2] < 18 ? 'tarde' : 'noite';
	$v{meta_dia} = (defined &mazzaPessoa::plano ? mazzaPessoa::plano()->{meta} : undef) || 'upar';
	return \%v;
}

sub kzeny { my ($z) = @_; return $z >= 1000000 ? sprintf('%.1fkk', $z / 1000000) : $z >= 1000 ? int($z / 1000) . 'k' : "$z"; }

# sem acento (serverEncoding Western; as falas dos bots sao todas sem acento)
sub semAcento {
	my ($t) = @_;
	return '' unless defined $t;
	$t =~ tr/\x{e1}\x{e0}\x{e2}\x{e3}\x{e4}\x{c1}\x{c0}\x{c2}\x{c3}\x{e9}\x{ea}\x{e8}\x{c9}\x{ca}\x{ed}\x{cd}\x{f3}\x{f4}\x{f5}\x{d3}\x{d4}\x{d5}\x{fa}\x{fc}\x{da}\x{e7}\x{c7}\x{f1}/aaaaaAAAAeeeEEiIoooOOOuuUcCn/;
	$t =~ s/[^\x20-\x7e]//g;
	return $t;
}

# ============================================================ F4.1 estilo ===
# [regex, trocas, peso]: cada ocorrencia troca com chance abrev * peso
my @ABREV = (
	[qr/\bvoces\b/i, ['vcs'], 1], [qr/\bvoce\b/i, ['vc'], 1], [qr/\bpor ?que\b/i, ['pq'], 0.9],
	[qr/\btambem\b/i, ['tb', 'tbm', 'tmb'], 0.9], [qr/\bnao\b/i, ['naum', 'naum', 'n'], 0.6],
	[qr/\baqui\b/i, ['aki'], 0.8], [qr/\bbeleza\b/i, ['blz', 'blza'], 0.9], [qr/\bverdade\b/i, ['vdd'], 0.8],
	[qr/\bmesmo\b/i, ['msm'], 0.7], [qr/\btodo mundo\b/i, ['td mundo'], 0.7], [qr/\btudo\b/i, ['td'], 0.6],
	[qr/\btodos\b/i, ['tds'], 0.6], [qr/\bmuito\b/i, ['mt', 'mto'], 0.6], [qr/(?<!nao )(?<!n )(?<!naum )\bpara\b(?! (?:de|com|o|a|na|no|ai)\b)/i, ['pra'], 0.9],   # "nao para"/"para de" e o verbo
	[qr/\bestou\b/i, ['to'], 0.9], [qr/\bestava\b/i, ['tava'], 0.9], [qr/\besta\b/i, ['ta'], 0.8],
	[qr/\bhoje\b/i, ['hj'], 0.8], [qr/\bque\b/i, ['q'], 0.55], [qr/\bquando\b/i, ['qdo', 'qnd'], 0.5],
	[qr/\bquanto\b/i, ['qto', 'qnt'], 0.6], [qr/\bobrigad[oa]\b/i, ['vlw', 'brigado', 'obg'], 0.7],
	[qr/\bvaleu\b/i, ['vlw', 'valew'], 0.8], [qr/\bfalou\b/i, ['flw', 'falow'], 0.7], [qr/\bfoi mal\b/i, ['mals'], 0.6],
	[qr/\bentao\b/i, ['entaum', 'ent'], 0.3], [qr/\bqualquer\b/i, ['qq', 'qlqr'], 0.5], [qr/\bdepois\b/i, ['dps', 'dpois'], 0.6],
	[qr/\bcomigo\b/i, ['cmg'], 0.3], [qr/\bcerteza\b/i, ['ctz'], 0.5], [qr/\bnossa\b/i, ['nuss', 'nossa'], 0.4],
	[qr/\bbeijos?\b/i, ['bjs', 'bjo'], 0.8], [qr/\bpessoal\b/i, ['povo', 'galera', 'pessoal'], 0.3],
	[qr/\bagora\b/i, ['agr'], 0.2], [qr/\bmais\b/i, ['+', 'mais'], 0.15],
);
my %EMO = (
	empolgado => ['^^', '*-*', ':D', '=D', '^^', '\o/', 'xD', 'rsrsrs'],
	veterano  => ['=/', ';x', '=P', '^^', 'hehe', '-.-'],
	zoeiro    => ['huahuahua', 'huahua', 'kkkk', '=P', 'xD', 'rsrsrs', 'hauhauha'],
	timido    => ['^^', '><', '^^\'', '=/', 'hehe', 'rs'],
);
my $RE_EMO = qr/(\^\^|\*-\*|=\/|;x|><|=p|=d|:d|xd|\\o\/|-\.-|rs(rs)+|hu?a(hu?a)+|ha(ha)+|k{3,}|hehe)/i;

sub estilo {
	my ($txt, %o) = @_;
	$txt = semAcento($txt);
	$txt =~ s/^\s+|\s+$//g;
	return () unless length $txt;
	my $ab = cfg('abrev', 0.6);
	for my $r (@ABREV) {
		my ($re, $tr, $peso) = @$r;
		$txt =~ s/($re)/rand() < $ab * $peso ? $tr->[int rand @$tr] : $1/ge;
	}
	# pontuacao solta: sem ponto final, virgula some as vezes, ?? e !! repetidos
	$txt =~ s/\.$// if rand() < 0.9 && $txt !~ /\.\.$/;
	$txt =~ s/,(?=\s)//g if rand() < 0.5;
	$txt =~ s/\?$/escolhe('?', '?', '??', '?!', '???')/e;
	if (jeito() eq 'empolgado') { $txt =~ s/!$/escolhe('!!', '!!!', '!')/e; }
	elsif (jeito() eq 'timido')  { $txt =~ s/!$/escolhe('', '...', '!')/e; }
	if (rand() < cfg('minusculas', 0.85)) { $txt = lc $txt; }
	elsif (jeito() eq 'empolgado' && length $txt < 22 && rand() < 0.15) { $txt = uc $txt; }
	else { $txt = ucfirst $txt; }
	# emoticon ou risada no fim, do jeito do bot
	if (!$o{semEmo} && $txt !~ $RE_EMO && rand() < cfg('emoticon', 0.2)) { $txt .= ' ' . escolhe(@{ $EMO{ jeito() } }); }
	# rajada: frase longa vira 2-3 linhas curtas
	my @linhas = ($txt);
	if (length $txt > 26 && rand() < cfg('rajada', 0.35)) {
		@linhas = rajada($txt);
	}
	# erro de digitacao + correcao
	my @saida;
	for my $l (@linhas) {
		my ($erro, $cor) = errar($l);
		push @saida, $erro;
		push @saida, $cor if defined $cor;
	}
	return @saida;
}

sub rajada {
	my ($t) = @_;
	my @p;
	while (length $t > 22 && @p < 2) {
		# corta numa virgula, ou antes de "mas", "e", "pq", "q", "ai" depois de pelo menos 8 letras
		if ($t =~ /^(.{8,}?)(?:,\s+|\s+(?=(?:mas|e|pq|ai|so q|tipo|alguem|vc|se)\s))(.{6,})$/i) {
			push @p, $1; $t = $2;
		} else { last; }
	}
	return (@p, $t);
}

my %VIZINHA = (
	q => 'asw', w => 'qasde', e => 'wsdfr', r => 'edfgt', t => 'rfghy', y => 'tghju', u => 'yhjki', i => 'ujklo',
	o => 'iklp', p => 'ol', a => 'qwsz', s => 'aqwedxz', d => 'serfcx', f => 'drtgvc', g => 'ftyhbv',
	h => 'yujnbg', j => 'uikmnh', k => 'jiolm', l => 'pok', z => 'asx', x => 'zsdc', c => 'xdfv', v => 'cfgb',
	b => 'vghn', n => 'bhjm', m => 'njk',
);

# no maximo um erro por linha (tecla vizinha, letras trocadas, letra comida ou dobrada); devolve (linha, correcao)
sub errar {
	my ($l) = @_;
	my $n = cfg('erro', 150);
	return ($l, undef) unless $n > 0;
	my @w = split / /, $l;
	my @cand = grep { $w[$_] =~ /^[a-z]{4,}$/i && $w[$_] !~ $RE_EMO } 0 .. $#w;
	return ($l, undef) unless @cand;
	my $letras = 0; $letras += length $w[$_] for @cand;
	my $p = $letras / $n;                        # chance da linha ter erro, no maximo metade
	return ($l, undef) unless rand() < ($p > 0.5 ? 0.5 : $p);
	my $i = $cand[int rand @cand];
	my @c = split //, $w[$i];
	my $j = 1 + int rand(@c - 1);
	my $tipo = int rand 4;
	my $viz = $VIZINHA{ lc $c[$j] };
	if ($tipo == 0 && $viz) { $c[$j] = substr($viz, int rand length $viz, 1); }
	elsif ($tipo == 1 && $j < $#c) { @c[$j, $j + 1] = @c[$j + 1, $j]; }
	elsif ($tipo == 2) { splice @c, $j, 1; }
	else { splice @c, $j, 0, $c[$j]; }
	my $errada = join '', @c;
	return ($l, undef) if $errada eq $w[$i];
	my $certa = $w[$i];
	$w[$i] = $errada;
	my $cor = rand() < cfg('corrige', 0.6) ? (rand() < 0.85 ? "$certa*" : "*$certa") : undef;
	return (join(' ', @w), $cor);
}

# ====================================================== F4.2 fila e envio ===
my @fila;          # {txt, canal, para, tipo(msg|e), espera, naoAntes, criado, origem, depoisLuta, lote}
my ($ultPub, $segurando, $soltouEm, $lote) = (0, 0, 0, 0);
my %digitando;     # nome => 1 enquanto ha resposta na fila para ele

# API: poe o texto na fila (com estilo) e devolve 1
sub dizer {
	my ($txt, %o) = @_;
	return 0 unless defined $txt && $char;
	my $canal = $o{canal} || 'c';
	my @itens;
	if ($txt =~ s/^\/e\s+(\S+)\s*//) { push @itens, { tipo => 'e', txt => $1, espera => rnd(0.2, 0.6) }; }
	my @linhas = length $txt ? (defined $o{estilo} && !$o{estilo} ? (semAcento($txt)) : estilo($txt, %o)) : ();
	my ($ms1, $ms2) = nums('digita', 150, 300);
	for my $l (@linhas) {
		push @itens, { tipo => 'msg', txt => $l, espera => length($l) * rnd($ms1, $ms2) / 1000 };
	}
	return 0 unless @itens;
	$lote++;
	my $antes = defined $o{ler} ? $o{ler} : rnd(0.3, 1.2);    # pensar antes de comecar a digitar
	$itens[0]{espera} += $antes;
	$itens[0]{naoAntes} = $o{naoAntes} if $o{naoAntes};
	$itens[0]{depoisLuta} = $o{depoisLuta};
	for my $it (@itens) {
		@$it{qw(canal para criado origem lote)} = ($canal, $o{para}, time, $o{origem} || 'fala', $lote);
		push @fila, $it;
	}
	$digitando{ $o{para} } = 1 if $o{para};
	return 1;
}

# o AFK do mazzaRitmo segura a fila; a pausa grande na cidade (mazzaJornada) nao: e hora de conversar
sub segura {
	return 0 unless defined &mazzaRitmo::estado;
	my $e = mazzaRitmo::estado();
	return 1 if $e eq 'afk';
	return 1 if $e eq 'pausa' && !(defined &mazzaJornada::emPausa && mazzaJornada::emPausa());
	return 0;
}

sub processarFila {
	return unless @fila;
	if (segura()) { $segurando = 1; delete $fila[0]{pronto}; return; }
	if ($segurando) { $segurando = 0; $soltouEm = time; }
	my $it = $fila[0];
	# fala publica velha demais (ficou presa no AFK, trocou de mapa): some; PM espera
	if ($it->{canal} ne 'pm' && time - $it->{criado} > 240) { descartarLote($it->{lote}); return; }
	unless (defined $it->{pronto}) {
		my $esp = $it->{espera};
		$esp *= 0.35 if defined &mazzaRitmo::estado && mazzaRitmo::estado() eq 'saindo';   # com pressa
		$esp += rnd(1, 4) if $soltouEm && time - $soltouEm < 1;                            # voltou do AFK: le o que perdeu
		my $ini = time;
		$ini = $it->{naoAntes} - $esp * 0.5 if $it->{naoAntes} && $it->{naoAntes} - $esp * 0.5 > $ini;
		$it->{pronto} = $ini + $esp;
	}
	# "depois de matar o monstro": espera a luta acabar (ate 40 s)
	if ($it->{depoisLuta} && AI::is('attack') && time - $it->{criado} < 40) { $it->{pronto} = time + 0.5; return; }
	return if time < $it->{pronto};
	shift @fila;
	enviar($it);
	delete $digitando{ $it->{para} } if $it->{para} && !grep { ($_->{para} || '') eq $it->{para} } @fila;
}

sub descartarLote {
	my ($l) = @_;
	@fila = grep { $_->{lote} != $l } @fila;
	%digitando = map { $_->{para} => 1 } grep { $_->{para} } @fila;
}

sub enviar {
	my ($it) = @_;
	return unless $messageSender;
	if ($it->{tipo} eq 'e') { Commands::run("e $it->{txt}"); return; }
	if ($it->{canal} eq 'pm') { sendMessage($messageSender, 'pm', $it->{txt}, $it->{para}); }
	else { sendMessage($messageSender, $it->{canal}, $it->{txt}); $ultPub = time if $it->{canal} eq 'c'; }
	registro($it->{canal} eq 'pm' ? "pm:$it->{para}" : $it->{canal}, $it->{origem}, $it->{txt});
}

sub registro {
	my ($canal, $origem, $txt) = @_;
	my $n = $config{username} || 'bot'; $n =~ s/[^\w\-]/_/g;
	if (open(my $fh, '>>', ($Settings::logs_folder || 'logs') . "/papo_$n.log")) {
		my @t = localtime;
		printf $fh "%.2f %04d-%02d-%02d %02d:%02d:%02d %s %s %s\n", time, $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0],
			$canal, $origem, $txt;
		close $fh;
	}
}

# ===================================================== F4.3 puxar assunto ===
my @eventos;       # {tipo, quando, vars, chance}: o que aconteceu e pode virar assunto
my ($ultAssunto, $ultTique, $ultMapa, $lotadoVisto) = (0, 0, '', 0);

sub evento {
	my ($tipo, $chance, %v) = @_;
	push @eventos, { tipo => $tipo, quando => time, vars => \%v, chance => $chance };
	shift @eventos while @eventos > 12;
}

sub gentePerto {
	my ($d) = @_;
	return () unless $playersList && $char;
	my $pos = $char->position;
	return grep { $_->{pos_to} && distance($pos, $_->{pos_to}) <= $d } @{ $playersList->getItems };
}

sub social {
	my $s = defined &mazzaPessoa::plano ? mazzaPessoa::plano()->{social} : undef;
	return defined $s ? $s : 0.5;
}

sub taxaHora {
	my ($a1, $b1) = nums('assunto', 2, 10);
	my $t = $a1 + ($b1 - $a1) * social();
	$t *= 0.4 if defined &mazzaPessoa::papel && mazzaPessoa::papel() eq 'quieto';
	$t *= 0.5 if jeito() eq 'timido';
	return $t;
}

sub assuntos {
	return if time - $ultTique < 5;
	my $dt = time - $ultTique;
	$dt = 5 if $dt > 60;
	$ultTique = time;
	return if $char->{dead} || segura() || @fila;
	my $mapa = $field->baseName;
	my @gente = gentePerto(14);
	my $cidade = $field->isCity;
	# mapa cheio fora da cidade (uma vez por mapa)
	if ($mapa ne $ultMapa) { $ultMapa = $mapa; $lotadoVisto = 0; }
	if (!$cidade && !$lotadoVisto && $playersList && @{ $playersList->getItems } >= 7) { $lotadoVisto = 1; evento('lotado', 35); }
	@eventos = grep { time - $_->{quando} < 600 } @eventos;
	return unless @gente || $cidade;
	return if time - $ultPub < 45;
	# evento forte (carta, monstro raro, episodio): fala logo, com a chance dele
	for my $e (@eventos) {
		next if $e->{feito} || time - $e->{quando} < 2;
		$e->{feito} = 1;
		if (rand(100) < $e->{chance}) { falarAssunto($e->{tipo}, %{ $e->{vars} }); return; }
	}
	# o resto: Poisson pela taxa da persona
	return if time - $ultPub < 120 || time - $ultAssunto < 180;
	return unless rand() < taxaHora() * $dt / 3600;
	my @t = ('pergunta', 'pergunta', 'geral', 'geral', 'xp', 'zeny', 'monstro', 'horario', 'lag', 'meta');
	push @t, 'cidade', 'cidade', 'vende' if $cidade;
	push @t, 'morreu' if grep { $_->{tipo} eq 'morte' } @eventos;
	push @t, 'aprendiz' if grep { ($_->{jobID} || 0) == 0 } @gente;
	falarAssunto(escolhe(@t));
}

sub falarAssunto {
	my ($tipo, %v) = @_;
	my $txt = frase("assunto_$tipo", %v);
	return 0 unless defined $txt && length $txt;
	$ultAssunto = time;
	return dizer($txt, origem => "assunto_$tipo");
}

sub onItem {
	my (undef, $a) = @_;
	return unless $char && defined $a->{item};
	my $n = semAcento($a->{item});
	if ($n =~ /\b(carta|card)\b/i) { evento('carta', 85, item => $n); }
	elsif ($n =~ /\b(elunium|oridecon|diamante|jellopy dourado|gema|chapeu|tiara|aros|manto|elmo|botas|escudo|adaga|espada|arco|cajado|livro|ovo)\b/i
		|| rand() < 0.03) { evento('drop', 30, item => $n); }
}

# monstro forte/raro na tela (mini-chefe e MVP de 2004)
my %FORTE = map { lc($_) => 1 } ('Angeling', 'Deviling', 'Ghostring', 'Arcangeling', 'Eclipse', 'Vagabond Wolf',
	'Lobo Vagabundo', 'Mastering', 'Toad', 'Sapo Rei', 'Dragon Fly', 'Vocal', 'Orc Lord', 'Senhor dos Orcs',
	'Orc Hero', 'Heroi Orc', 'Golden Thief Bug', 'Besouro-Ladrao Dourado', 'Baphomet', 'Osiris', 'Moonlight Flower',
	'Flor do Luar', 'Phreeoni', 'Maya', 'Doppelganger', 'Pharaoh', 'Fara', 'Drake', 'Mistress', 'Eddga',
	'Dark Lord', 'Lorde das Trevas', 'Chimera', 'Quimera', 'Kobold Archer', 'Dragon Tail', 'Rotar Zairo', 'Mutant Dragon',
	'Dragao Mutante', 'Stormy Knight', 'Cavaleiro da Tempestade', 'Garm', 'Hatii');
my %vistoForte;
sub onMonstro {
	my (undef, $m) = @_;
	return unless $char && $m && defined $m->{name};
	my $n = semAcento($m->{name});
	return unless $FORTE{ lc $n };
	return if time - ($vistoForte{$n} || 0) < 900;
	$vistoForte{$n} = time;
	evento('forte', 55, monstro => $n);
}

sub onMatou { my (undef, $a) = @_; $ultMonstro = semAcento($a->{monster}{name}) if $a && $a->{monster} && $a->{monster}{name}; }
sub onMorte { evento('morte', 0); }

# Motor de Episodios: anuncio de episodio novo e regiao fechada
sub onLog {
	my (undef, undef, undef, undef, $msg) = @_;
	return unless defined $msg;
	if ($msg =~ /\[Midgard\] Chegou o episodio (.+?) \(/) { evento('episodio', 60, episodio => semAcento($1)); }
	elsif (index($msg, 'ainda nao foi descoberta') >= 0 && $msg =~ /;\s*(\S+)\s+chega em\s+(.+?)\s+\(/) {
		evento('fechado', 40, lugar => $1, episodio => semAcento($2));
	}
}

# =================================================== F4.4 respostas ======
my %mem;           # nome => memoria do AnswerChat (all, stress, <tipo> => vezes, blocked, time)
my %hist;          # nome => [[role, texto], ...] para o LLM
my %ultResp;       # nome => quando respondeu

sub nomeEhMeu {
	my ($msg) = @_;
	my $nome = $char->{name};
	my $n = quotemeta $nome;
	return 1 if $msg =~ /\b$n\b/i;
	# apelido: o primeiro pedaco de um nome composto ("Lia" de LiaSacer) ou o comeco de um nome longo ("rotad")
	if ($nome =~ /^([A-Z]?[a-z]{2,})[A-Z0-9_]/) { my $p = quotemeta lc $1; return 1 if lc($msg) =~ /\b$p\b/; }
	if (length $nome >= 7) { my $p = quotemeta lc substr($nome, 0, 5); return 1 if lc($msg) =~ /\b$p\w*/; }
	return 0;
}

sub semMeuNome {
	my ($m) = @_;
	return $m unless $char;
	my $nome = $char->{name};
	my $n = quotemeta lc $nome;
	$m =~ s/\b$n\b//gi;
	if ($nome =~ /^([A-Z]?[a-z]{2,})[A-Z0-9_]/) { my $p = quotemeta lc $1; $m =~ s/\b$p\b//gi; }
	if (length $nome >= 7) { my $p = quotemeta lc substr($nome, 0, 5); $m =~ s/\b$p\w*//gi; }
	$m =~ s/\s{2,}/ /g;
	return $m;
}

sub onPM {
	my (undef, $a) = @_;
	return unless ligado() && respostas() && $char && defined $a->{privMsgUser};
	receber($a->{privMsgUser}, defined $a->{privMsg} ? $a->{privMsg} : '', 'pm');
}

sub onPub {
	my (undef, $a) = @_;
	return unless ligado() && respostas() && $char;
	my ($quem, $msg) = (defined $a->{pubMsgUser} ? $a->{pubMsgUser} : '', defined $a->{pubMsg} ? $a->{pubMsg} : '');
	return if ignorado($quem);
	my $m = semAcento($msg);
	if (nomeEhMeu($m)) { receber($quem, $m, 'chamado'); }
	elsif ($m =~ /\b(oi+e?|ola|eae|eai|salve|opa|bom dia|boa tarde|boa noite|hi|hello|iae)\b/i) {
		receber($quem, $m, 'saudacao') if rand() < 0.35;
	} elsif ($m =~ /\b(alguem|algm)\b.*\?|\b(onde|como|qual|qnt|quanto)\b.*\?/i) {
		receber($quem, $m, 'pergunta') if rand() < 0.25;
	}
}

sub receber {
	my ($quem, $msg, $tipo) = @_;
	return if ignorado($quem);
	$msg = semAcento($msg);
	push @{ $hist{$quem} }, ['user', $msg];
	shift @{ $hist{$quem} } while @{ $hist{$quem} } > 8;
	return if $digitando{$quem} || $llm{quem} && $llm{quem} eq $quem;     # ja esta respondendo para ele
	# publico: nao fica respondendo a mesma pessoa toda hora
	return if $tipo ne 'pm' && time - ($ultResp{$quem} || 0) < 60;
	my $ign = cfg('ignora', 0.1);
	return if rand() < ($tipo eq 'pm' ? $ign * 0.6 : $ign);
	my $canal = $tipo eq 'pm' ? 'pm' : 'c';
	# perceber a mensagem: PM pisca na hora, publico demora mais; na luta, as vezes so depois
	my $nota = $tipo eq 'pm' ? reacao(2.5) : reacao(4);
	my $luta = AI::is('attack') && rand() < 0.6 ? 1 : 0;
	my $chegou = time;
	my $resp = sub {
		my ($txt, $origem) = @_;
		return unless defined $txt && length $txt;
		push @{ $hist{$quem} }, ['assistant', $txt];
		$ultResp{$quem} = time;
		dizer($txt, canal => $canal, para => $canal eq 'pm' ? $quem : undef, origem => $origem,
			ler => rnd(nums('ler', 0.5, 2)) + length($msg) / 15, naoAntes => $chegou + $nota, depoisLuta => $luta);
	};
	if (($tipo eq 'pm' || $tipo eq 'chamado') && llmPode()) {
		llmPedir($quem, $msg, $tipo, $resp, sub { $resp->(regra($quem, $msg, $tipo), 'regra'); });
	} else {
		$resp->(regra($quem, $msg, $tipo), 'regra');
	}
}

# atraso de perceber: lognormal em volta da mediana (s)
sub reacao {
	my ($med) = @_;
	my ($u1, $u2) = (rand() || 0.5, rand());
	my $z = sqrt(-2 * log($u1)) * cos(6.283185307179586 * $u2);
	my $t = $med * exp(0.6 * $z);
	return $t < 0.8 ? 0.8 : $t > 40 ? 40 : $t;
}

# resposta por regra: categoria e paciencia do AnswerChat, texto da persona quando ela tem
sub regra {
	my ($quem, $msg, $tipo) = @_;
	my $info = $mem{$quem} ||= {};
	if ($info->{time} && time - $info->{time} > 6 * 3600) { %$info = (); }
	return undef if $info->{blocked};
	# o nome do bot sai antes de classificar ("Rotateste" tem "ate", que o AnswerChat le como despedida)
	my $m = semMeuNome(lc $msg);
	$m =~ s/^[_\s,.:!]+|[_\s,]+$//g;
	if (!length $m || $m =~ /^\?+$/) {                         # so chamou o nome
		return defined &mazzaJornada::texto ? mazzaJornada::texto('chamado', jogador => $quem) : 'oi?';
	}
	# cumprimento de quem passa: a fala da persona, sem gastar a paciencia
	if ($tipo eq 'saudacao' && defined &mazzaJornada::texto && rand() < 0.75) {
		my $t = mazzaJornada::texto('saudacao', jogador => $quem);
		return $t if defined $t;
	}
	my ($resp, $cat);
	if ($temAnswer) {
		$info->{all}++;
		$info->{$_} ||= 0 for qw(stress stressed Block all);
		my %novo;
		{ no warnings; ($resp, %novo) = AnswerDatabase::AnswerDatabase($m, %$info); }
		%$info = %novo;
		$cat = $info->{lastrecived} || 'unkown';
	} else {
		$cat = $m =~ /\b(bot|macro)\b/ ? 'bot' : $m =~ /^(oi|ola|eae|opa|salve)/ ? 'cumprimento' : 'unkown';
	}
	$info->{time} = time;
	return $resp if $info->{blocked};
	my $vezes = $info->{$cat} || 1;
	# elogio e xingamento (o banco do AnswerChat junta tudo em "ofensa"/"unkown")
	if ($m =~ /\b(lind[oa]|fof[oa]|gat[oa]|bonit[oa]|legal|maneir[oa]|top|show|massa|mt bom|parabens|pro)\b/ && $cat =~ /unkown|perguntapessoa/) {
		return frase('resp_elogio', jogador => $quem);
	}
	if ($cat eq 'ofensa' || $m =~ /\b(noob|nub|lixo|idiota|burr[oa]|otari[oa]|trouxa|retardad[oa]|ks)\b/) {
		$info->{stress} += 10;
		return rand() < 0.3 ? undef : frase($info->{stress} > 40 ? 'resp_raiva' : 'resp_xingado', jogador => $quem);
	}
	if ($cat eq 'bot') {
		return undef if rand() < 0.25;                         # as vezes nem liga
		return rand() < 0.65 ? frase($vezes > 1 ? 'resp_bot_de_novo' : 'resp_bot', jogador => $quem) : $resp;
	}
	if ($cat eq 'cumprimento' && $vezes <= 1 && rand() < 0.6 && defined &mazzaJornada::texto) {
		my $sec = $tipo eq 'pm' ? 'pm' : $tipo eq 'saudacao' ? 'saudacao' : 'chamado';
		my $t = mazzaJornada::texto($sec, jogador => $quem);
		return $t if defined $t;
	}
	if ($cat eq 'dinheiro' || $cat eq 'pedido') {
		return rand() < 0.6 ? frase('resp_pedido', jogador => $quem) : $resp;
	}
	if ($tipo eq 'chamado' && $cat eq 'unkown' && defined &mazzaJornada::texto) {
		my $t = mazzaJornada::texto('chamado', jogador => $quem);
		return $t if defined $t && rand() < 0.5;
	}
	if ($tipo eq 'pergunta' && $cat !~ /perguntaondeup|perguntacomofaz|level/) { return undef; }   # nao sabe, fica quieto
	return $resp;
}

# ======================================================= F4.5 LLM local ===
my @llmHora;       # instantes dos pedidos da ultima hora
my ($llmFalhou, $llmFora) = (0, 0);   # falhas seguidas; ate quando nao tenta (notebook desligado)

sub llmPode {
	my $url = cfg('llm', '');
	return 0 unless length $url;
	return 0 if %llm && $llm{sock};
	return 0 if time < $llmFora;
	@llmHora = grep { time - $_ < 3600 } @llmHora;
	return @llmHora < cfg('llm_teto', 20) ? 1 : 0;
}

sub llmFechar { close $llm{sock} if $llm{sock}; %llm = (); }

my %JEITO_TXT = (
	empolgado => 'empolgado, animado, usa muito ^^ e !!, chama todo mundo pra party',
	veterano  => 'veterano que joga desde o beta, seco, responde curto, sabe onde upar e quanto custa as coisas',
	zoeiro    => 'zoeiro, faz piada de tudo, ri com huahuahua, chama os outros de noob de brincadeira',
	timido    => 'timido, educado, fala pouco, usa ^^ e ><, pede desculpa',
);
my %PAPEL_TXT = (
	novato => 'e novato, ainda pergunta tudo', mentor => 'gosta de ajudar aprendiz', familia => 'e de um cla que chama de familia',
	vendedor => 'vende coisas na cidade (S> e C>)', buff => 'e o sacerdote que da buff pros outros', pedinte => 'vive pedindo zeny e pocao',
	quieto => 'quase nao conversa, so upa', zoeiro => 'implica com todo mundo', casual => 'so joga fim de semana',
);

sub llmPrompt {
	my ($tipo) = @_;
	my $v = varsPadrao();
	my $papel = defined &mazzaPessoa::papel ? mazzaPessoa::papel() : 'casual';
	my $quem = ($char->{sex} || 0) == 1 ? 'um garoto brasileiro' : 'uma garota brasileira';
	return join(' ',
		"Voce e $v->{nome}, $quem de 16 anos jogando Ragnarok Online no servidor bRO em 2004.",
		"Seu personagem e $v->{classe} nivel $v->{lv}, agora no mapa $v->{mapa}; sua meta de hoje e $v->{meta}.",
		"Seu jeito: $JEITO_TXT{ jeito() }; voce $PAPEL_TXT{$papel}.",
		($tipo eq 'pm' ? 'Alguem te mandou uma mensagem privada (PM).' : 'Alguem falou com voce no chat publico do jogo.'),
		'Responda como num chat de jogo: UMA linha curta (no maximo 12 palavras), portugues informal da internet de 2004,',
		'minusculas, sem acento, com abreviacoes (vc, pq, q, naum, blz, aki, tbm, vlw, flw), sem emoji (pode ^^ =/ =P),',
		'sem aspas, sem explicar. Voce e uma pessoa jogando: nunca diga que e IA, bot, programa ou assistente; se perguntarem',
		'se voce e bot, negue do seu jeito ou zoe. Nao ofereca ajuda como atendente. Se nao souber, diga que nao sabe.');
}

sub llmPedir {
	my ($quem, $msg, $tipo, $ok, $falha) = @_;
	my $url = cfg('llm', '');
	my ($host, $porta) = $url =~ m{^(?:https?://)?([^:/]+)(?::(\d+))?} or return $falha->();
	$porta ||= 11434;
	my @msgs = ({ role => 'system', content => llmPrompt($tipo) });
	push @msgs, { role => $_->[0], content => $_->[1] } for @{ $hist{$quem} || [] };
	push @msgs, { role => 'user', content => semAcento($msg) } if $msgs[-1]{role} ne 'user';
	my $corpo = encode_json({ model => cfg('llm_modelo', 'qwen3:4b-instruct'), messages => \@msgs, stream => \0,
		keep_alive => '30m', options => { temperature => 0.9, top_p => 0.9, num_predict => 48 } });
	my $ip = inet_aton($host) or return $falha->();
	my $s = IO::Socket::INET->new(Proto => 'tcp') or return $falha->();
	naoBloqueia($s);
	connect($s, sockaddr_in($porta, $ip));      # em andamento (EWOULDBLOCK/EINPROGRESS): o tique confere
	%llm = (sock => $s, fase => 'conectando', t0 => time, quem => $quem, ok => $ok, falha => $falha, in => '',
		out => "POST /api/chat HTTP/1.0\r\nHost: $host:$porta\r\nContent-Type: application/json\r\n"
		     . 'Content-Length: ' . length($corpo) . "\r\nConnection: close\r\n\r\n$corpo");
	push @llmHora, time;
	debug "[$NAME] LLM: pedido para $quem ($tipo)\n", $NAME;
}

sub naoBloqueia {
	my ($s) = @_;
	if ($^O eq 'MSWin32') { my $v = pack('L', 1); ioctl($s, 0x8004667e, $v); }   # FIONBIO
	else { $s->blocking(0); }
}

sub llmTique {
	return unless %llm && $llm{sock};
	my $s = $llm{sock};
	my $espera = cfg('llm_espera', 8);
	if (time - $llm{t0} > $espera) { return llmErro("sem resposta em $espera s"); }
	if ($llm{fase} eq 'conectando') {
		my ($r, $w, $e) = IO::Select->select(undef, IO::Select->new($s), IO::Select->new($s), 0);
		return llmErro('conexao recusada') if $e && @$e;
		return unless $w && @$w;
		my $err = getsockopt($s, Socket::SOL_SOCKET(), Socket::SO_ERROR());
		return llmErro('conexao recusada') if defined $err && unpack('i', $err);
		$llm{fase} = 'enviando';
	}
	if ($llm{fase} eq 'enviando') {
		my $n = syswrite($s, $llm{out});
		return llmErro("escrita: $!") if !defined $n && !$!{EWOULDBLOCK} && !$!{EAGAIN} && ($! + 0) != 10035;
		substr($llm{out}, 0, $n, '') if $n;
		$llm{fase} = 'lendo' unless length $llm{out};
		return;
	}
	while (IO::Select->new($s)->can_read(0)) {
		my $n = sysread($s, my $buf, 65536);
		return llmErro("leitura: $!") unless defined $n;
		if ($n == 0) { return llmFim(); }
		$llm{in} .= $buf;
	}
}

sub llmErro {
	my ($motivo) = @_;
	my $f = $llm{falha};
	llmFechar();
	$llmFalhou++;
	# notebook desligado: depois de 3 falhas seguidas, so tenta de novo em 10 min
	$llmFora = time + 600 if $llmFalhou >= 3;
	debug "[$NAME] LLM: $motivo; responde por regra\n", $NAME;
	message "[$NAME] LLM fora ($motivo): regras por 10 min.\n", 'info' if $llmFalhou == 3;
	$f->() if $f;
}

sub llmFim {
	my ($ok, $falha, $in) = @llm{qw(ok falha in)};
	llmFechar();
	my ($cab, $corpo) = split /\r?\n\r?\n/, $in, 2;
	unless (defined $cab && $cab =~ m{^HTTP/\d\.\d 200}) { %llm = (falha => $falha); return llmErro('HTTP ' . (defined $cab ? (split /\r?\n/, $cab)[0] : 'vazio')); }
	my $d = eval { decode_json($corpo) };
	my $txt = $d && ref $d eq 'HASH' && $d->{message} ? $d->{message}{content} : undef;
	$txt = llmFiltro($txt);
	unless (defined $txt) { %llm = (falha => $falha); return llmErro('resposta filtrada'); }
	$llmFalhou = 0;
	debug "[$NAME] LLM: '$txt'\n", $NAME;
	$ok->($txt, 'llm');
}

# saida do LLM: uma linha curta, sem acento, sem cara de IA nem palavrao pesado
sub llmFiltro {
	my ($t) = @_;
	return undef unless defined $t;
	$t =~ s/<think>.*?<\/think>//gs;
	($t) = grep { /\S/ } split /\n/, $t;
	return undef unless defined $t;
	$t = semAcento($t);
	$t =~ s/^\s*["'*]+|["'*]+\s*$//g;
	$t =~ s/^\s*\w+\s*:\s+//;                                  # "Fulano: ..."
	$t =~ s/^\s+|\s+$//g;
	return undef unless length $t;
	return undef if $t =~ /\b(intelig[e]ncia artificial|modelo de linguagem|assistente|sou (um |uma )?(ia|bot|programa|robo)|como posso (te )?ajudar|chatgpt|openai|qwen|language model|as an ai)\b/i;
	return undef if $t =~ /\b(viado|macaco|preto imundo|estupr|nazi|suicid|se mata)\w*/i;
	if (length $t > 100) { $t = substr($t, 0, 100); $t =~ s/\s+\S*$//; }
	return $t;
}

# ================================================================= tique ===
sub tique {
	carregar() unless $carregado;
	llmTique();
	return unless ligado() && noJogo();
	processarFila();
	assuntos();
}

# ============================================================= console ====
sub cmdPapo {
	my (undef, $arg) = @_;
	$arg = '' unless defined $arg;
	my ($sub, $resto) = $arg =~ /^\s*(\S*)\s*(.*)$/;
	$sub ||= 'status';
	if ($sub eq 'estilo') {
		message "[$NAME] estilo: $_\n", 'list' for estilo($resto);
	} elsif ($sub eq 'dizer') {
		dizer($resto, origem => 'console');
	} elsif ($sub eq 'assunto') {
		falarAssunto($resto || escolhe(qw(pergunta geral xp zeny monstro horario lag meta)));
	} elsif ($sub eq 'resp') {
		my $r = regra('Teste', $resto, 'pm');
		message "[$NAME] regra: '" . semAcento($resto) . "' -> " . (defined $r ? join(' / ', estilo($r)) : '(nada)') . "\n", 'list';
	} elsif ($sub eq 'llm') {
		my $url = cfg('llm', '');
		return message "[$NAME] sem mazzaPapo_llm.\n", 'info' unless length $url;
		($llmFora, $llmFalhou) = (0, 0);
		@{ $hist{Teste} } = (['user', semAcento($resto)]);
		llmPedir('Teste', $resto, 'pm', sub { message "[$NAME] LLM ($_[1]): $_[0] -> " . join(' / ', estilo($_[0])) . "\n", 'list'; },
			sub { message "[$NAME] LLM falhou; regra: " . (regra('Teste', $resto, 'pm') || '(nada)') . "\n", 'list'; });
	} elsif ($sub eq 'ouvir' || $sub eq 'ignorar') {   # teste: deixa um bot responder a outro (so na memoria)
		if ($sub eq 'ouvir') { delete $ignorados{ lc $resto }; } else { $ignorados{ lc $resto } = 1; }
		message "[$NAME] " . ($sub eq 'ouvir' ? "respondendo a '$resto'" : "ignorando '$resto'") . " ate recarregar.\n", 'info';
	} elsif ($sub eq 'fila') {
		message sprintf("[%s] fila (%d)%s:\n", $NAME, scalar @fila, $segurando ? ' SEGURA (AFK)' : ''), 'list';
		message sprintf("  %-4s %-14s %5.1fs %s\n", $_->{canal}, $_->{para} || '', ($_->{pronto} || time) - time, $_->{txt}), 'list' for @fila;
	} else {
		@llmHora = grep { time - $_ < 3600 } @llmHora;
		message sprintf("[%s] %s | jeito %s | %.1f assuntos/h (social %.2f) | fila %d%s | ultima fala publica ha %s | "
			. "eventos: %s | LLM %s (%d/%d na hora%s) | ignorados %d\n", $NAME, ligado() ? 'ligado' : 'desligado', jeito(),
			taxaHora(), social(), scalar @fila, $segurando ? ' (segura)' : '', $ultPub ? int(time - $ultPub) . ' s' : 'nunca',
			join(', ', map { $_->{tipo} } @eventos) || 'nenhum', cfg('llm', '') || 'desligado', scalar @llmHora,
			cfg('llm_teto', 20), time < $llmFora ? ', fora: notebook nao respondeu' : '', scalar keys %ignorados), 'info';
	}
}

1;
