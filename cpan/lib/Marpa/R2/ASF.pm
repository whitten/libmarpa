# Copyright 2013 Jeffrey Kegler
# This file is part of Marpa::R2.  Marpa::R2 is free software: you can
# redistribute it and/or modify it under the terms of the GNU Lesser
# General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Marpa::R2 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser
# General Public License along with Marpa::R2.  If not, see
# http://www.gnu.org/licenses/.

package Marpa::R2::ASF;

use 5.010;
use strict;
use warnings;
no warnings qw(recursion);

use vars qw($VERSION $STRING_VERSION);
$VERSION        = '2.071_000';
$STRING_VERSION = $VERSION;
## no critic(BuiltinFunctions::ProhibitStringyEval)
$VERSION = eval $VERSION;
## use critic

# The code in this file, for now, breaks "the rules".  It makes use
# of internal methods not documented as part of Libmarpa.
# It is intended to create documented Libmarpa methods to underlie
# this interface, and rewrite it to use them

package Marpa::R2::Internal::ASF;

# Terms
#
# Symchset -- A set of symches, all with the same start and end locations.
#
# Choicepoint -- A symchset which is reachable from the top choicepoint.
# Choicepoints can be internal or external.
#
# Factoring -- one possible factoring of an external choicepoint.  It is a sequence
# of factors.
#
# Factor -- A list of choicepoints.
#
# Symch (Symbolic choice) -- An or-node or a terminal
#

# This is more complicated that it needs to be for the current implementation.
# It allows for LHS terminals (implemented in Libmarpa but not allowed by the SLIF).
# It also assumes that every or-node which can be constructed from preceding or-nodes
# and the input will be present.  This is currently the case, but in the future
# rules and/or symbols may have extra-syntactic conditions attached making this
# assumption false.

# Given the or-node IDs and token IDs, return the choicepoint,
# creating one if necessary.  Default is internal.
sub symchset_to_id {
    my ( $asf, @symchset ) = @_;
    my $key = join q{ }, sort { $a <=> $b } @symchset;
    my $id_by_symchset =
        $asf->[Marpa::R2::Internal::Scanless::ASF::ID_BY_SYMCHSET];
    my $id = $id_by_symchset->{$key};
    return $id if defined $id;
    $id = $asf->[Marpa::R2::Internal::Scanless::ASF::NEXT_SYMCHSET_ID]++;
    $id_by_symchset->{$key} = $id;
    return $id;
} ## end sub symchset_to_id

# No check for conflicting usage -- value(), asf(), etc.
# at this point
sub Marpa::R2::Scanless::ASF::top {
    my ($asf) = @_;
    my $slr   = $asf->[Marpa::R2::Internal::Scanless::ASF::SLR];
    my $recce = $slr->[Marpa::R2::Inner::Scanless::R::THICK_G1_RECCE];

    my $bocage = $recce->[Marpa::R2::Internal::Recognizer::B_C];
    if ( not $bocage ) {
        my $grammar   = $recce->[Marpa::R2::Internal::Recognizer::GRAMMAR];
        my $grammar_c = $grammar->[Marpa::R2::Internal::Grammar::C];
        my $recce_c   = $recce->[Marpa::R2::Internal::Recognizer::C];
        $grammar_c->throw_set(0);
        $bocage = $recce->[Marpa::R2::Internal::Recognizer::B_C] =
            Marpa::R2::Thin::B->new( $recce_c, -1 );
        $grammar_c->throw_set(1);
        die "No parse" if not defined $bocage;
    } ## end if ( not $bocage )
    my $augment_or_node_id = $bocage->_marpa_b_top_or_node();
    my $augment_and_node_id =
        $bocage->_marpa_b_or_node_first_and($augment_or_node_id);
    my $augment2_or_node_id =
        $bocage->_marpa_b_and_node_cause($augment_and_node_id);
    my @symch_set;
    AND_NODE: for my $augment2_and_node_id (
        $bocage->_marpa_b_or_node_first_and($augment2_or_node_id)
        .. $bocage->_marpa_b_or_node_last_and($augment2_or_node_id)) {
      my $cause_id = $bocage->_marpa_b_and_node_cause($augment2_and_node_id);
      if (defined $cause_id) {
          push @symch_set, $cause_id;
	  next AND_NODE;
      }
      push @symch_set, and_node_to_token_symch( $augment2_and_node_id);
    }
    my $new_cp = symchset_to_id($asf, @symch_set);
    # $new_cp->[Marpa::R2::Internal::Scanless::Choicepoint::EXTERNAL] = 1;
    return $new_cp;
} ## end sub Marpa::R2::Scanless::ASF::top_choicepoint

sub make_token_cp { return -($_[0] + 43); }
sub unmake_token_cp { return -$_[0] - 43; }

# Range from -1 to -42 reserved for special values
sub and_node_to_token_symch { return -$_[0] - 43; }
sub token_symch_to_and_node { return -$_[0] - 43; }

sub normalize_asf_blessing {
    my ($name) = @_;
    $name =~ s/\A \s * //xms;
    $name =~ s/ \s * \z//xms;
    $name =~ s/ \s+ / /gxms;
    $name =~ s/ [^\w] /_/gxms;
    return $name;
} ## end sub normalize_asf_blessing

sub Marpa::R2::Internal::ASF::blessings_set {
    my ( $asf, $default_blessing, $force ) = @_;
    my $slr       = $asf->[Marpa::R2::Internal::Scanless::ASF::SLR];
    my $recce     = $slr->[Marpa::R2::Inner::Scanless::R::THICK_G1_RECCE];
    my $grammar   = $recce->[Marpa::R2::Internal::Recognizer::GRAMMAR];
    my $grammar_c = $grammar->[Marpa::R2::Internal::Grammar::C];

    my @rule_blessing   = ();
    my $highest_rule_id = $grammar_c->highest_rule_id();
    RULE: for ( my $rule_id = 0; $rule_id <= $highest_rule_id; $rule_id++ ) {
        my $lhs_id = $grammar_c->rule_lhs($rule_id);
        my $name   = $grammar->symbol_name($lhs_id);
        if ( defined $force ) {
            $rule_blessing[$rule_id] = join q{::}, $force,
                normalize_asf_blessing($name);
            next RULE;
        }
        my $blessing =
            Marpa::R2::Internal::Recognizer::rule_blessing_find( $recce,
            $rule_id );
        if ( '::' ne substr $blessing, 0, 2 ) {
            $rule_blessing[$rule_id] = $blessing;
            next RULE;
        }
        $rule_blessing[$rule_id] = join q{::}, $default_blessing,
            normalize_asf_blessing($name);
    } ## end RULE: for ( my $rule_id = 0; $rule_id <= $highest_rule_id; ...)

    my @symbol_blessing   = ();
    my $highest_symbol_id = $grammar_c->highest_symbol_id();
    SYMBOL:
    for ( my $symbol_id = 0; $symbol_id <= $highest_symbol_id; $symbol_id++ )
    {
        my $name = $grammar->symbol_name($symbol_id);
        if ( defined $force ) {
            $symbol_blessing[$symbol_id] = join q{::}, $force,
                normalize_asf_blessing($name);
            next SYMBOL;
        }
        my $blessing =
            Marpa::R2::Internal::Recognizer::lexeme_blessing_find( $recce,
            $symbol_id );
        if ( '::' ne substr $blessing, 0, 2 ) {
            $symbol_blessing[$symbol_id] = $blessing;
            next SYMBOL;
        }
        $symbol_blessing[$symbol_id] = join q{::}, $default_blessing,
            normalize_asf_blessing($name);
    } ## end SYMBOL: for ( my $symbol_id = 0; $symbol_id <= $highest_symbol_id...)
    $asf->[Marpa::R2::Internal::Scanless::ASF::RULE_BLESSING] =
        \@rule_blessing;
    $asf->[Marpa::R2::Internal::Scanless::ASF::SYMBOL_BLESSING] =
        \@symbol_blessing;
    return $asf;
} ## end sub Marpa::R2::Internal::ASF::blessings_set

# Returns undef if no parse
sub Marpa::R2::Scanless::ASF::new {
    my ( $class, @arg_hashes ) = @_;
    my $asf       = bless [], $class;

    my $choice_blessing = 'My_ASF::choice';
    my $force;
    my $default_blessing;
    my $slr;

    for my $args (@arg_hashes) {
        if ( defined( my $value = $args->{slr} ) ) {
            $asf->[Marpa::R2::Internal::Scanless::ASF::SLR] = $slr = $value;
        }
        if ( defined( my $value = $args->{choice} ) ) {
    $asf->[Marpa::R2::Internal::Scanless::ASF::CHOICE_BLESSING] =
            $choice_blessing = $value;
        }
        if ( defined( my $value = $args->{force} ) ) {
            $force = $value;
        }
        if ( defined( my $value = $args->{default} ) ) {
            $default_blessing = $value;
        }
    } ## end for my $args (@arg_hashes)

    Marpa::R2::exception(
        q{The "slr" named argument must be specified with the Marpa::R2::Scanless::ASF::new method}
    ) if not defined $slr;
    $asf->[Marpa::R2::Internal::Scanless::ASF::SLR] = $slr;

    Marpa::R2::exception(
        q{The "force" or "default" named argument must be specified },
        {with the Marpa::R2::Scanless::ASF::new method}
    ) if not defined $force and not defined $default_blessing;

    my $recce     = $slr->[Marpa::R2::Inner::Scanless::R::THICK_G1_RECCE];

    if ( defined $recce->[Marpa::R2::Internal::Recognizer::TREE_MODE] ) {
        # If we already in ASF mode, or are in valuation mode, we cannot create an ASF
        Marpa::R2::exception(
            "An attempt was made to create an ASF for a SLIF recognizer already in use\n",
            "   The recognizer must be reset first\n",
            '  The current SLIF recognizer mode is "',
            $recce->[Marpa::R2::Internal::Recognizer::TREE_MODE],
            qq{"\n}
        );
    }
    $recce->[Marpa::R2::Internal::Recognizer::TREE_MODE] = 'forest';

    $asf->[Marpa::R2::Internal::Scanless::ASF::ID_BY_SYMCHSET] = {};
    $asf->[Marpa::R2::Internal::Scanless::ASF::NEXT_SYMCHSET_ID] = 0;

    my $slg       = $slr->[Marpa::R2::Inner::Scanless::R::GRAMMAR];
    my $thin_slr  = $slr->[Marpa::R2::Inner::Scanless::R::C];
    my $grammar   = $recce->[Marpa::R2::Internal::Recognizer::GRAMMAR];
    my $grammar_c = $grammar->[Marpa::R2::Internal::Grammar::C];
    my $recce_c   = $recce->[Marpa::R2::Internal::Recognizer::C];

    my $bocage = $recce->[Marpa::R2::Internal::Recognizer::B_C];
    if ( not $bocage ) {
        my $grammar   = $recce->[Marpa::R2::Internal::Recognizer::GRAMMAR];
        my $grammar_c = $grammar->[Marpa::R2::Internal::Grammar::C];
        my $recce_c   = $recce->[Marpa::R2::Internal::Recognizer::C];
        $grammar_c->throw_set(0);
        $bocage = $recce->[Marpa::R2::Internal::Recognizer::B_C] =
            Marpa::R2::Thin::B->new( $recce_c, -1 );
        $grammar_c->throw_set(1);
        return if not defined $bocage;
    } ## end if ( not $bocage )

    blessings_set($asf, $default_blessing, $force);

    return $asf;

} ## end sub Marpa::R2::Scanless::ASF::new

package Marpa::R2::Internal::Choicepoint;

# Memoization is heavily used -- it needs to be to keep the worst cases from
# going exponential.  The need to memoize is the reason for the very heavy use of
# hashes.  For example, quite often an HOH (hash of hashes) is used where
# an HoL (hash of lists) would usually be preferred.  But the HOL would leave me
# with the problem of having duplicates, which if followed up upon, would make
# the algorithm go exponential.

sub first_factoring {
    my ( $choicepoint, $top_or_node ) = @_;

    # return undef if we were passed a symch which is not
    # an or-node
    return if $top_or_node < 0;

    my $asf = $choicepoint->[Marpa::R2::Internal::Scanless::Choicepoint::ASF];
    my $slr = $asf->[Marpa::R2::Internal::Scanless::ASF::SLR];
    my $recce     = $slr->[Marpa::R2::Inner::Scanless::R::THICK_G1_RECCE];
    my $grammar   = $recce->[Marpa::R2::Internal::Recognizer::GRAMMAR];
    my $grammar_c = $grammar->[Marpa::R2::Internal::Grammar::C];
    my $bocage    = $recce->[Marpa::R2::Internal::Recognizer::B_C];
    my $ordering  = $recce->[Marpa::R2::Internal::Recognizer::O_C];

    my %internal_predecessors = ();
    my %initial_by_whole      = ();
    my %seen                  = ();
    my @finals                = ();

    my @stack = ( [$top_or_node, -1] );
    $seen{$top_or_node}{-1} = 1;
    STACK_ELEMENT: while ( defined( my $stack_element = pop @stack ) ) {

        # memoization of or-nodes on stack ?
        my ( $or_node, $whole ) = @{$stack_element};
        for my $and_node_id (
            $ordering->_marpa_o_or_node_and_node_ids($top_or_node) )
        {
            my $predecessor_id =
                $bocage->_marpa_b_and_node_predecessor($and_node_id);

            my $cause_id = $bocage->_marpa_b_and_node_cause($and_node_id);
            if ( not defined $cause_id ) {
                $cause_id = and_node_to_token_symch($and_node_id);
            }
            if ( defined $predecessor_id ) {
                $internal_predecessors{$cause_id}{$predecessor_id} = 1;
                if ( not $seen{$predecessor_id}{$whole} ) {
                    push @stack, [ $predecessor_id, $whole ];
                    $seen{$predecessor_id}{$whole} = 1;
                }
            } ## end if ( defined $predecessor_id )
            else {
                $initial_by_whole{$whole}{$cause_id} = 1 if $whole >= 0;
            }
            if ( $cause_id < 0 or _marpa_b_or_node_is_semantic($cause_id) ) {
                push @finals, $cause_id;
            }
            else {
                if ( not $seen{$cause_id}{$cause_id} ) {
                    push @stack, [ $cause_id, $cause_id ];
                    $seen{$cause_id}{$cause_id} = 1;
                }
            } ## end else [ if ( $cause_id < 0 or _marpa_b_or_node_is_semantic(...))]
        } ## end for my $and_node_id ( $ordering...)
    } ## end STACK_ELEMENT: while ( defined( my $stack_element = pop @stack ) )

    for my $whole_or_node_id ( keys %initial_by_whole ) {
        my $initials     = $initial_by_whole{$whole_or_node_id};
        my $predecessors = $internal_predecessors{$whole_or_node_id};
        for my $initial ( @{$initials} ) {
            for my $predecessor ( @{$predecessors} ) {
                $internal_predecessors{$initial}{$predecessor} = 1;
            }
        }
    } ## end for my $whole_or_node_id ( keys %initial_by_whole )

    # Find the semantics causes for each predecessor
    my %semantic_cause = ();
    %seen = ();
    my %and_node_seen = ();

    # This re-initializes a stack to a list of or-nodes whose cause's should be examined,
    # recursively, until a semantic or-node or a terminal is found.
    for my $outer_cause_id ( keys %internal_predecessors ) {
        for my $predecessor_id (
            keys %{ $internal_predecessors{$outer_cause_id} } )
        {
            next PREDECESSOR_ID if $seen{$predecessor_id};
            $seen{$predecessor_id} = 1;

            # Not the most efficient Perl implementation -- intended for conversion to C
            # Outer seen, for predecessors, can be bit vector
            # Inner seen, for and_nodes, must be array to track current predecessor,
            #   because and-node is "seen" only if seen FOR THIS PREDECESSOR
            my @and_node_stack = ();
            for my $and_node_id (
                $ordering->_marpa_o_or_node_and_node_ids($predecessor_id) )
            {
                next AND_NODE
                    if ( $and_node_seen{$and_node_id} // -1 )
                    == $predecessor_id;
                $and_node_seen{$and_node_id} = $predecessor_id;
                push @and_node_stack, $and_node_id;
            } ## end for my $and_node_id ( $ordering...)
            AND_NODE: while ( my $and_node_id = pop @and_node_stack ) {
                my $cause_id = $bocage->_marpa_b_and_node_cause($and_node_id);
                if ( not defined $cause_id ) {
                    $semantic_cause{$predecessor_id}
                        { and_node_to_token_symch($and_node_id) } = 1;
                    next AND_NODE;
                }
                if ( $bocage->_marpa_b_or_node_is_semantic($cause_id) ) {
                    $semantic_cause{$predecessor_id}{$cause_id} = 1;
                    next AND_NODE;
                }
                INNER_AND_NODE:
                for my $inner_and_node_id (
                    $ordering->_marpa_o_or_node_and_node_ids($predecessor_id)
                    )
                {
                    next INNER_AND_NODE
                        if ( $and_node_seen{$inner_and_node_id} // -1 )
                        == $predecessor_id;
                    $and_node_seen{$inner_and_node_id} = $predecessor_id;
                    push @and_node_stack, $inner_and_node_id;
                } ## end INNER_AND_NODE: for my $inner_and_node_id ( $ordering...)
            } ## end AND_NODE: while ( my $and_node_id = pop @and_node_stack )
        } ## end for my $predecessor_id ( keys %{ $internal_predecessors...})
    } ## end for my $outer_cause_id ( keys %internal_predecessors )

    my %prior_cause = ();
    for my $cause_id ( keys %internal_predecessors ) {
        for my $predecessor_id ( keys %{ $internal_predecessors{$cause_id} } )
        {
            for my $prior_cause_id (
                keys %{ $semantic_cause{$predecessor_id} } )
            {
                $prior_cause{$cause_id}{$prior_cause_id} = 1;
            }
        } ## end for my $predecessor_id ( keys %{ $internal_predecessors...})
    } ## end for my $cause_id ( keys %internal_predecessors )

} ## end sub first_factoring

1;

# vim: expandtab shiftwidth=4:
