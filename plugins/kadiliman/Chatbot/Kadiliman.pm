# Inspired by perlBorg, pyBorg, and seeBorg
# Licensed under the GPL
# Copyright by kaliwanagan
# Ported by Thrice aka Noface
#
# mazzakore (2026-11-03), a partir de plugins/needs-review/kadiliman/trunk/Chatbot/Kadiliman.pm (v0.06):
#   - arquivo de frases em UTF-8, criado no caminho pedido (o original caia em lines.txt na raiz do OpenKore);
#   - palavras com acento (\w Unicode em vez de A-Za-z), palavra escapada no regex (\Q..\E);
#   - debug desligado por padrao; aprender so marca {dirty} (quem usa decide quando salvar com saveScriptData);
#   - limite de frases (maxLines, padrao 5000) e frases vazias ignoradas.
# A ideia e a mesma: escolhe uma palavra conhecida da mensagem e uma palavra que costuma vir depois dela,
# e emenda o comeco de uma frase que tem a primeira com o fim de uma frase que tem a segunda.

package Chatbot::Kadiliman;

use strict;
use Log qw(message warning error);

our $VERSION = '0.06-mz';

sub new {
	my ($class, $opts) = @_;
	my $self = bless {
		name       => 'Kadiliman',
		scriptfile => '',
		learn      => 1,
		reply      => 1,
		debug      => 0,
		maxLines   => 5000,
		lines      => [],
		count      => {},
		after      => {},
		linenum    => {},
		dirty      => 0,
		parsed     => 0,
		(ref $opts eq 'HASH' ? %$opts : ()),
	}, ref($class) || $class;
	$self->parseScriptData($self->{scriptfile});
	return $self;
}

sub parseScriptData {
	my ($self, $scriptfile) = @_;
	if ($scriptfile) {
		if (open(my $fh, '<:encoding(UTF-8)', $scriptfile)) {
			while (my $line = <$fh>) {
				$self->learn($_) foreach split /\.+/, $line;
			}
			close $fh;
		} else {
			message "[Kadiliman] $scriptfile ainda nao existe; sera criado ao aprender.\n", 'plugins';
		}
	}
	message "[Kadiliman] conheco " . scalar(@{$self->{lines}}) . " frases.\n", 'plugins';
	$self->{parsed} = 1;
}

sub saveScriptData {
	my ($self) = @_;
	my $scriptfile = $self->{scriptfile} or return;
	my $fh;
	unless (open($fh, '>:encoding(UTF-8)', $scriptfile)) {
		warning "[Kadiliman] nao consegui gravar $scriptfile: $!\n";
		return;
	}
	print $fh "$_\n" foreach @{$self->{lines}};
	close $fh;
	$self->{dirty} = 0;
}

sub palavras {
	my ($string) = @_;
	my $tmp = lc $string;
	utf8::upgrade($tmp);
	$tmp =~ s/[^\w\s']/ /g;
	return grep { length } split /\s+/, $tmp;
}

sub learn {
	my ($self, $string) = @_;
	$string = $self->preProcess($string);
	return unless length $string;
	my $numLines = @{$self->{lines}};
	return if $numLines >= $self->{maxLines};

	my @words = palavras($string);
	for (my $i = 0; $i < @words; $i++) {
		$self->{count}{$words[$i]}++;
		$self->{after}{$words[$i]}{$words[$i+1]}++ if defined $words[$i+1];
		push @{$self->{linenum}{$words[$i]}}, $numLines;
	}
	push @{$self->{lines}}, $string;
	if ($self->{parsed}) {
		$self->debug("aprendi: $string");
		$self->{dirty} = 1;
	}
}

sub preProcess {
	my ($self, $string) = @_;
	$string = '' unless defined $string;
	$string =~ s/[\r\n]//g;
	$string =~ s/^[_\s]+//;
	$string =~ s/[_\s]+$//;
	return $string;
}

sub transform {
	my ($self, $inputString) = @_;
	my $reply;

	# so as palavras que ja conhecemos
	my @leftWords = grep { exists $self->{count}{$_} } palavras($self->preProcess($inputString));
	my $leftWord = $leftWords[int rand(@leftWords)];

	if (!defined $leftWord) {
		# nenhuma palavra conhecida: uma frase qualquer
		$reply = @{$self->{lines}} ? $self->{lines}[int rand(@{$self->{lines}})] : undef;
	} else {
		my @rightWords = keys %{$self->{after}{$leftWord} || {}};
		my $rightWord = $rightWords[int rand(@rightWords)];

		# comeco: uma frase com a palavra da esquerda, ate ela
		my @leftLines = map { $self->{lines}[$_] } @{$self->{linenum}{$leftWord}};
		my $leftSide = '';
		foreach my $word (split /\s+/, $leftLines[int rand(@leftLines)]) {
			$leftSide .= $word . ' ';
			last if $word =~ /\b\Q$leftWord\E\b/i;
		}

		# fim: uma frase com a palavra da direita, a partir dela
		my $rightSide = '';
		if (defined $rightWord) {
			my @rightLines = map { $self->{lines}[$_] } @{$self->{linenum}{$rightWord}};
			my $achou = 0;
			foreach my $word (split /\s+/, $rightLines[int rand(@rightLines)]) {
				$achou ||= $word =~ /\b\Q$rightWord\E\b/i;
				$rightSide .= $word . ' ' if $achou;
			}
		}
		$reply = $leftSide . $rightSide;
	}
	$self->learn($inputString) if $self->{learn};
	$reply =~ s/\s+$// if defined $reply;
	return $reply;
}

sub debug {
	my ($self, $string) = @_;
	message "[Kadiliman] $string\n", 'plugins' if $self->{debug};
}

1;
