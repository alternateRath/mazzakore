# AnswerChat - responde PM e chat publico por padroes (cumprimento, pedido de zeny, "vc e bot?", ofensa...), com
# memoria por jogador, paciencia que acaba ("stress") e erros de digitacao corrigidos com "palavra*".
#
# Origem: https://github.com/Henrybk/Plugins/tree/master/AnswerChat (AnswerChat.pl, commit 473f544, 2022-09-29),
# de Henry (OpenKore Brasil). O repositorio nao declara licenca; o autor mantem o core do OpenKore (GPL) e o
# plugin roda dentro dele. O banco de respostas esta em AnswerDatabase.pm.
# mazzakore (2026-11-03): motor reescrito em cima das mesmas ideias, corrigindo os bugs que o proprio autor anotou:
#   - a correcao "palavra*" sai DEPOIS da frase com erro (o original mandava as duas juntas);
#   - o tempo de resposta e ler + digitar (letras/segundo), nao 1,5 s por palavra fixo;
#   - um jogador por vez na fila; mensagens que chegam enquanto "digita" nao geram resposta dupla;
#   - a memoria (JSON) fica na pasta de logs do bot e e salva no maximo a cada minuto, sem "reload" a cada
#     mensagem; o stress baixa com o tempo e quem foi bloqueado volta a ser respondido depois de
#     AnswerChat_forgetHours (o original bloqueava para sempre);
#   - nunca responde a si mesmo, nem a nomes de AnswerChat_ignore.
#
# config.txt:
#   AnswerChat_Pm 1              # responde PM
#   AnswerChat_Pub 0             # responde chat publico (fora de cidade e com poucos jogadores em volta)
#   AnswerChat_PubMax 1          # maximo de jogadores em volta para responder no publico
#   AnswerChat_PubName 1         # no publico, so quando a mensagem tem o nome do personagem (padrao 1)
#   AnswerChat_Error 1           # erros de digitacao
#   AnswerChat_ErrorChance 40    # 1 erro a cada N letras, em media (padrao 40)
#   AnswerChat_cps 5             # letras por segundo ao digitar (padrao 5)
#   AnswerChat_ignore            # nomes separados por virgula (outros bots, GMs...)
#   AnswerChat_forgetHours 6     # horas para esquecer contagem, stress e bloqueio de um jogador (padrao 6)
package AnswerChat;

use strict;
use utf8;
use Plugins;
use Globals qw(%config $char $field $playersList $messageSender);
use Log qw(message debug error warning);
use Misc qw(sendMessage);
use Utils::DataStructures qw(existsInList);
use Settings;
use File::Spec;
use JSON::Tiny qw(from_json to_json);
use Time::HiRes qw(time);
use lib $Plugins::current_plugin_folder;
use AnswerDatabase;

Plugins::register('AnswerChat', 'respostas de chat por padroes, com paciencia e erros de digitacao', \&on_unload, \&on_unload);
my $hooks = Plugins::addHooks(
	['packet_privMsg', \&on_PM],
	['packet_pubMsg',  \&on_Pub],
	['AI_pre',         \&tick],
	['in_game',        \&carregar],
);

my %jogadores;      # nome => {all, stress, <tipo> => vezes, blocked, time}
my @fila;           # {quando, canal, texto, para}
my ($arquivo, $sujo, $salvoEm) = (undef, 0, 0);

sub on_unload {
	salvar(1);
	Plugins::delHooks($hooks);
}

sub caminho {
	return unless $char && defined $char->{name};
	(my $nome = $char->{name}) =~ s/[^\w\-]/_/g;
	return File::Spec->catfile($Settings::logs_folder || 'logs', "AnswerChat_$nome.json");
}

sub carregar {
	my $novo = caminho() or return;
	return if defined $arquivo && $arquivo eq $novo;
	salvar(1);
	$arquivo = $novo;
	%jogadores = ();
	if (open(my $fh, '<:encoding(UTF-8)', $arquivo)) {
		local $/;
		my $json = <$fh>;
		close $fh;
		my $dados = eval { from_json($json) };
		%jogadores = %$dados if ref $dados eq 'HASH';
	}
	debug "[AnswerChat] memoria de " . scalar(keys %jogadores) . " jogadores ($arquivo)\n", 'AnswerChat';
}

sub salvar {
	my ($agora) = @_;
	return unless $sujo && defined $arquivo;
	return unless $agora || time - $salvoEm > 60;
	$salvoEm = time;
	if (open(my $fh, '>:encoding(UTF-8)', $arquivo)) {
		print $fh to_json(\%jogadores);
		close $fh;
		$sujo = 0;
	} else {
		warning "[AnswerChat] nao gravei $arquivo: $!\n";
	}
}

sub on_PM {
	my (undef, $args) = @_;
	return unless $config{AnswerChat_Pm};
	receber($args->{privMsgUser}, $args->{privMsg}, 'pm');
}

sub on_Pub {
	my (undef, $args) = @_;
	return unless $config{AnswerChat_Pub} && $char && $field;
	return if $field->isCity;
	my $max = defined $config{AnswerChat_PubMax} ? $config{AnswerChat_PubMax} : 1;
	return if @{$playersList->getItems} > $max;
	my $soNome = defined $config{AnswerChat_PubName} ? $config{AnswerChat_PubName} : 1;
	return if $soNome && $args->{Msg} !~ /\Q$char->{name}\E/i;
	receber($args->{MsgUser}, $args->{Msg}, 'c');
}

sub receber {
	my ($quem, $msg, $canal) = @_;
	return unless $char && defined $quem && defined $msg;
	return if $quem eq $char->{name};
	return if $config{AnswerChat_ignore} && existsInList($config{AnswerChat_ignore}, $quem);
	carregar() unless defined $arquivo;
	return if grep { $_->{para} eq $quem } @fila;   # ainda "digitando" a resposta anterior para ele

	my $info = $jogadores{$quem} ||= {};
	esquecer($info);
	return if $info->{blocked};

	$msg = lc $msg;
	$msg =~ s/[\r\n]//g;
	$msg =~ s/^[_\s]+|[_\s]+$//g;
	$info->{all}++;
	my ($resposta, %novo) = AnswerDatabase($msg, %$info);
	%$info = %novo;
	$info->{time} = time;
	$sujo = 1;
	return unless defined $resposta && length $resposta;

	my $correcao;
	($resposta, $correcao) = erros($resposta) if $config{AnswerChat_Error};
	my $cps = $config{AnswerChat_cps} || 5;
	# ler a mensagem (~15 letras/s) + pensar + digitar
	my $t = time + 1 + rand(2) + length($msg) / 15 + length($resposta) / $cps;
	push @fila, {quando => $t, canal => $canal, texto => $resposta, para => $quem};
	push @fila, {quando => $t + 1 + rand(1.5) + length($correcao) / $cps, canal => $canal, texto => $correcao,
		para => $quem} if $correcao;
	debug "[AnswerChat] $quem: '$msg' -> '$resposta'" . ($correcao ? " / '$correcao'" : '') . "\n", 'AnswerChat';
}

# stress cai 10 por hora; depois de forgetHours sem falar, o jogador e um desconhecido de novo
sub esquecer {
	my ($info) = @_;
	return unless $info->{time};
	my $horas = (time - $info->{time}) / 3600;
	my $limite = defined $config{AnswerChat_forgetHours} ? $config{AnswerChat_forgetHours} : 6;
	if ($horas >= $limite) {
		%$info = ();
		return;
	}
	$info->{stress} -= int($horas * 10) if $info->{stress};
	$info->{stress} = 0 if ($info->{stress} || 0) < 0;
}

sub tick {
	salvar(0);
	return unless @fila && $messageSender;
	@fila = sort { $a->{quando} <=> $b->{quando} } @fila;
	return if time < $fila[0]{quando};
	my $r = shift @fila;
	if ($r->{canal} eq 'c' && !grep { $_->{name} eq $r->{para} } @{$playersList->getItems}) {
		$r->{canal} = 'pm';   # foi embora da tela: responde por PM, como o original
	}
	sendMessage($messageSender, $r->{canal}, $r->{texto}, $r->{canal} eq 'pm' ? $r->{para} : undef);
}

# erros de digitacao: troca por tecla vizinha, inverte duas letras, come uma letra ou dobra uma;
# devolve (frase com erro, "palavra* outra*" com as palavras certas) ou (frase, undef)
my %vizinha = (
	q => 'asw', w => 'qasde', e => 'wsdfr', r => 'edfgt', t => 'rfghy', y => 'tghju', u => 'yhjki', i => 'ujklo',
	o => 'iklp', p => 'ol', a => 'qwsz', s => 'aqwedxz', d => 'serfcx', f => 'drtgvc', g => 'ftyhbv',
	h => 'yujnbg', j => 'uikmnh', k => 'jiolm', l => 'pok', z => 'asx', x => 'zsdc', c => 'xdfv', v => 'cfgb',
	b => 'vghn', n => 'bhjm', m => 'njk',
);

sub erros {
	my ($frase) = @_;
	my $n = $config{AnswerChat_ErrorChance} || 40;
	my @certas = split / /, $frase;
	my @saida;
	foreach my $palavra (@certas) {
		my @c = split //, $palavra;
		if (@c >= 3 && rand($n) < @c) {
			my $i = 1 + int(rand(@c - 1));
			my $tipo = int rand 4;
			my $viz = $vizinha{lc $c[$i]};
			if ($tipo == 0 && $viz) {
				$c[$i] = substr($viz, rand length $viz, 1);
			} elsif ($tipo == 1 && $i < $#c) {
				@c[$i, $i + 1] = @c[$i + 1, $i];
			} elsif ($tipo == 2) {
				splice @c, $i, 1;
			} else {
				splice @c, $i, 0, $c[$i];
			}
		}
		push @saida, join '', @c;
	}
	my @corrige = map { "$certas[$_]*" } grep { $saida[$_] ne $certas[$_] } 0 .. $#certas;
	# nem todo mundo corrige: 2 em 3
	return (join(' ', @saida), (@corrige && rand() < 0.67) ? join(' ', @corrige) : undef);
}

carregar() if $char;

1;
