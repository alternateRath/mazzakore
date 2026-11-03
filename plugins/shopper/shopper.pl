# shopper - compra itens de lojas de jogadores (vending) por preco maximo
#
# Original: plugins/needs-review/shopper/trunk (openkore/openkore), GPL. Copyright 2006 by kaliwanagan.
# mazzakore (2026-11-03): reescrito para o core atual, com jeito de gente:
#   - o original nunca entrava na loja (o relogio era zerado a cada tick) e usava a API de inventario antiga;
#   - ao ver uma loja nova, espera alguns segundos (ler o titulo) antes de abrir a lista; nao reabre a mesma
#     loja antes de shopper_revisit segundos;
#   - le a lista inteira (packet_vender_store2) e compra tudo o que casa numa so compra, depois de um tempinho;
#   - respeita o zeny que tem e as condicoes de checkSelfCondition de cada bloco.
#
# config.txt:
#   shopper_revisit 600          # segundos antes de olhar de novo a mesma loja
#   shopper_maxDist 12           # so entra em lojas ate essa distancia
#   shopper Pocao Branca {       # nome exato do item (como aparece na lista da loja)
#       maxPrice 1200            # preco maximo por unidade
#       maxAmount 20             # quanto comprar no total; desce a cada compra (0 = desliga o bloco)
#       # + condicoes de checkSelfCondition (zeny > 50000, inCity 1, ...)
#   }
package shopper;

use strict;
use Plugins;
use Globals qw(%config $char $messageSender %venderLists $playersList $net);
use Log qw(message warning error debug);
use Misc qw(configModify);
use Network;
use AI;
use Time::HiRes qw(time);

Plugins::register('shopper', 'compra de lojas de jogadores', \&Unload, \&Unload);
my $hooks = Plugins::addHooks(
	['packet_vender',        \&lojaVista,  undef],
	['packet_vender_store2', \&listaLoja,  undef],
	['AI_pre',               \&tick,       undef],
);

my %pendente;   # venderID => quando entrar
my %visitada;   # venderID => quando entrou
my $compra;     # {quando, venderID, venderCID, itens => [...]}

sub Unload { Plugins::delHooks($hooks); }

sub blocos {
	my @b;
	for (my $i = 0; exists $config{"shopper_$i"}; $i++) {
		my $p = "shopper_$i";
		next if !$config{$p} || $config{"${p}_disabled"};
		next unless $config{"${p}_maxAmount"} && $config{"${p}_maxAmount"} > 0;
		push @b, $p;
	}
	return @b;
}

sub lojaVista {
	my (undef, $args) = @_;
	return unless blocos();
	my $id = $args->{ID};
	return if $visitada{$id} && time - $visitada{$id} < ($config{shopper_revisit} || 600);
	$pendente{$id} ||= time + 2 + rand(6);
}

sub tick {
	return unless $char && $net && $net->getState() == Network::IN_GAME;
	if ($compra && time >= $compra->{quando}) {
		my $c = $compra;
		undef $compra;
		$messageSender->sendBuyBulkVender($c->{venderID}, $c->{itens}, $c->{venderCID});
		return;
	}
	foreach my $id (keys %pendente) {
		next if time < $pendente{$id};
		delete $pendente{$id};
		next unless $venderLists{$id};
		my $dono = $playersList && $playersList->getByID($id);
		next unless $dono && $dono->distance <= ($config{shopper_maxDist} || 12);
		next if AI::inQueue('attack', 'skill_use', 'items_take');
		$visitada{$id} = time;
		debug "[shopper] olhando a loja de $dono->{name}\n", 'shopper';
		$messageSender->sendEnteringVender($id);
		last;
	}
}

sub listaLoja {
	my (undef, $args) = @_;
	my @itens;
	my $zeny = $char->{zeny};
	foreach my $item (@{$args->{itemList}->getItems}) {
		foreach my $p (blocos()) {
			next unless lc $item->{name} eq lc $config{$p};
			next unless $item->{price} <= ($config{"${p}_maxPrice"} || 0);
			next unless Misc::checkSelfCondition($p);
			my $qtd = $item->{amount};
			$qtd = $config{"${p}_maxAmount"} if $qtd > $config{"${p}_maxAmount"};
			$qtd = int($zeny / $item->{price}) if $item->{price} && $qtd * $item->{price} > $zeny;
			next unless $qtd > 0;
			$zeny -= $qtd * $item->{price};
			message "[shopper] $item->{name}: $qtd x $item->{price}z\n", 'success';
			push @itens, {itemIndex => $item->{ID}, amount => $qtd};
			configModify("${p}_maxAmount", $config{"${p}_maxAmount"} - $qtd, 1);
			last;
		}
	}
	$compra = {quando => time + 1 + rand(3), venderID => $args->{venderID}, venderCID => $args->{venderCID},
		itens => \@itens} if @itens;
}

1;
