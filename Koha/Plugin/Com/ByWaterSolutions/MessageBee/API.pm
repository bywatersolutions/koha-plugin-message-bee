package Koha::Plugin::Com::ByWaterSolutions::MessageBee::API;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Koha::Notice::Messages;

=head1 API

=head2 Class Methods

=cut

sub update_message_status {
    my $c = shift->openapi->valid_input or return;

    my $message_id = $c->validation->param('message_id');
    my $status     = $c->validation->param('status');
    my $subject    = $c->validation->param('subject');
    my $content    = $c->validation->param('content');

    my $message = Koha::Notice::Messages->find($message_id);
    unless ($message) {
        return $c->render(
            status  => 404,
            openapi => { error => "Message not found." }
        );
    }

    unless ( $status eq 'sent' || $status eq 'failed' ) {
        return $c->render(
            status  => 500,
            openapi => {
                error =>
                  "Invalid status value, must be 'sent', 'pending' or 'failed'"
            }
        );
    }

    $message->status($status);
    $message->subject($subject) if $subject;
    $message->content($content) if $content;
    $message->store();

    return $c->render( status => 204, text => q{} );
}

sub update_message_content {
    my $c = shift->openapi->valid_input or return;

    my $message_id = $c->validation->param('message_id');
    my $subject    = $c->validation->param('subject');
    my $content    = $c->validation->param('content');

    my $message = Koha::Notice::Messages->find($message_id);
    unless ($message) {
        return $c->render(
            content => 404,
            openapi => { error => "Message not found." }
        );
    }

    unless ($content) {
        return $c->render(
            content => 500,
            openapi => { error => "No message content provided" }
        );
    }

    $message->content($content);
    $message->subject($subject) if $subject;
    $message->store();

    return $c->render( content => 204, text => q{} );
}

1;
