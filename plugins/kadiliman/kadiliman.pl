# kadiliman - respostas de chat que aprendem frases (sem LLM)
#
# Original: plugins/needs-review/kadiliman/trunk (openkore/openkore), GPL.
#   Copyright 2005 by kaliwanagan (Kali); ported by Thrice aka Noface; adds by Mucilon (v1.3, 2008).
# mazzakore (2026-11-03): cola do plugin reescrita para o core atual:
#   - le o chat ja decodificado (packet_pubMsg/privMsg/partyMsg/guildMsg) em vez de packet/public_chat cru,
#     onde o nome vinha grudado na mensagem e o PM nao tinha texto;
#   - a resposta espera o tempo de digitar numa fila propria (nao empilha "chatBot" no AI, que travava a IA);
#   - o arquivo de frases fica na pasta de controle do bot (nao na raiz do OpenKore) e e salvo no maximo
#     a cada minuto, em UTF-8;
#   - nunca responde a si mesmo; system chat nao e respondido (o original respondia ao anuncio do servidor).
#
# config.txt (um bloco por "cerebro"):
#   chatBot Kadiliman {
#       scriptfile kadiliman.txt   # frases; relativo a pasta de controle do bot (criado se faltar)
#       learn 1                    # aprende as frases que le
#       replyRate 30               # 0..100: chance de responder
#       onPublicChat 1
#       onPrivateMessage 1
#       onPartyChat 0
#       onGuildChat 0
#       inLockOnly 0               # chat publico so no lockMap
#       wpm 65                     # palavras por minuto ao "digitar"
#       smileys ^^,xD,:)
#       smileyRate 20
#       noPlayers                  # nomes (ou /regex/i) que nunca recebem resposta, separados por virgula
#       noWords                    # palavras (ou /regex/i) que fazem nao responder
#       timesToBlockPM 10          # PMs de um mesmo jogador antes de ignora-lo (0 = nunca)
#       timeToResetCount 300       # segundos para zerar a contagem
#       # + condicoes de checkSelfCondition (hp, inLockOnly, whenIdle...)
#   }
package kadiliman;

use strict;
use Plugins;
use Globals qw(%config $char $field $messageSender);
use Log qw(message warning error debug);
use Misc qw(sendMessage);
use Settings;
use File::Spec;
use Time::HiRes qw(time);
use lib $Plugins::current_plugin_folder;
use Chatbot::Kadiliman;

Plugins::register('kadiliman', 'respostas de chat que aprendem frases', \&Unload, \&Reload);
my $hooks = Plugins::addHooks(
	['packet_pubMsg',   \&onPub,   undef],
	['packet_privMsg',  \&onPriv,  undef],
	['packet_partyMsg', \&onParty, undef],
	['packet_guildMsg', \&onGuild, undef],
	['start3',          \&Reload,  undef],
	['AI_pre',          \&tick,    undef],
);

my $prefix = 'chatBot_';
my %bot;          # i => Chatbot::Kadiliman
my %count;        # i => {jogador => mensagens}
my %countStart;   # i => time
my @fila;         # respostas esperando o tempo de digitar
my $lastSave = 0;

sub Unload {
	salvar(1);
	Plugins::delHooks($hooks);
}

sub arquivo {
	my ($nome) = @_;
	$nome = 'kadiliman.txt' if !$nome || $nome eq '1';
	return $nome if File::Spec->file_name_is_absolute($nome);
	return Settings::getControlFilename($nome) || File::Spec->catfile($Settings::controlFolders[0], $nome);
}

sub Reload {
	salvar(1);
	%bot = ();
	for (my $i = 0; exists $config{$prefix.$i}; $i++) {
		$bot{$i} = Chatbot::Kadiliman->new({
			name       => $config{$prefix.$i},
			scriptfile => arquivo($config{$prefix.$i.'_scriptfile'}),
			learn      => $config{$prefix.$i.'_learn'},
			reply      => 1,
			debug      => 0,
		});
	}
}

sub onPub   { recebido('pub',   $_[1]{MsgUser},     $_[1]{Msg}); }
sub onPriv  { recebido('pm',    $_[1]{privMsgUser}, $_[1]{privMsg}); }
sub onParty { recebido('party', $_[1]{MsgUser},     $_[1]{Msg}); }
sub onGuild { recebido('guild', $_[1]{MsgUser},     $_[1]{Msg}); }

sub casa {
	my ($padrao, $texto) = @_;
	return 0 unless defined $texto;
	if (my ($re, $ci) = $padrao =~ /^\/(.+?)\/(i?)$/) {
		return $ci ? $texto =~ /$re/i : $texto =~ /$re/;
	}
	return lc $texto eq lc $padrao;
}

sub recebido {
	my ($tipo, $quem, $msg) = @_;
	return unless $char && defined $msg && length $msg;
	return if defined $quem && $quem eq $char->{name};
	my %liga = (pub => 'onPublicChat', pm => 'onPrivateMessage', party => 'onPartyChat', guild => 'onGuildChat');
	my %canal = (pub => 'c', pm => 'pm', party => 'p', guild => 'g');

	foreach my $i (sort { $a <=> $b } keys %bot) {
		my $p = $prefix.$i;
		next if $config{$p.'_disabled'};
		next unless $config{$p.'_'.$liga{$tipo}};
		next if grep { casa($_, $quem) } split /\s*,+\s*/, ($config{$p.'_noPlayers'} || '');
		next if grep { length $_ && casa($_, $msg) } split /\s*,+\s*/, ($config{$p.'_noWords'} || '');
		next if $tipo eq 'pub' && $config{$p.'_inLockOnly'} && $field && $field->baseName ne $config{lockMap};

		if ($tipo eq 'pm' && $config{$p.'_timesToBlockPM'}) {
			if (++$count{$i}{$quem} >= $config{$p.'_timesToBlockPM'}) {
				message "[kadiliman] $quem mandou PM demais: ignorando\n", 'plugins';
				Commands::run("ignore 1 $quem");
				next;
			}
		}

		my $reply = $bot{$i}->transform($msg);
		next unless defined $reply && $reply =~ /\S/;
		my $rate = defined $config{$p.'_replyRate'} ? $config{$p.'_replyRate'} : 80;
		next unless rand(100) < $rate;
		next unless Misc::checkSelfCondition($p);
		next if @fila;   # um jogador digita uma coisa de cada vez

		my @smileys = split /\s*,+\s*/, ($config{$p.'_smileys'} || '');
		$reply =~ s/\s+$//;
		$reply .= ' ' . $smileys[rand @smileys] if @smileys && rand(100) < ($config{$p.'_smileyRate'} || 0);

		# 65 ppm de ~4,25 letras = ~4,6 letras/s, mais um tempo para ler e pensar
		my $cps = ($config{$p.'_wpm'} || 65) * 4.25 / 60;
		push @fila, {quando => time + 1 + rand(2) + length($reply) / $cps,
			canal => $canal{$tipo}, texto => $reply, para => $quem};
		debug "[kadiliman] vai responder a $quem: $reply\n", 'kadiliman';
		last;
	}
}

sub tick {
	if (@fila && time >= $fila[0]{quando} && $messageSender) {
		my $r = shift @fila;
		sendMessage($messageSender, $r->{canal}, $r->{texto}, $r->{canal} eq 'pm' ? $r->{para} : undef);
	}
	foreach my $i (keys %bot) {
		my $reset = $config{$prefix.$i.'_timeToResetCount'};
		next unless $reset;
		$countStart{$i} ||= time;
		next if time - $countStart{$i} < $reset;
		delete $count{$i};
		$countStart{$i} = time;
	}
	salvar(0);
}

sub salvar {
	my ($agora) = @_;
	return unless $agora || time - $lastSave > 60;
	$lastSave = time;
	$_->saveScriptData foreach grep { $_->{dirty} } values %bot;
}

# carregado com "plugin load" no meio do jogo (o start3 ja passou): monta os cerebros agora
Reload() if $char;

1;
