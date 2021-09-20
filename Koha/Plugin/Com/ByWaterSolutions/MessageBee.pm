package Koha::Plugin::Com::ByWaterSolutions::MessageBee;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Auth;
use C4::Context;

use Cwd qw(abs_path);

## Here we set our plugin version
our $VERSION = "{VERSION}";
our $MINIMUM_VERSION = "{MINIMUM_VERSION}";

our $metadata = {
    name            => 'Email Footer plugin',
    author          => 'Kyle M Hall',
    date_authored   => '2021-06-30',
    date_updated    => "1900-01-01",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin adds an "unsubscribe" footer to every outgoing email.'
};

=head3 new

=cut

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 configure

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            footers => C4::Context->config("email_footers"),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                foo => $cgi->param('foo'),
                bar => $cgi->param('bar'),
            }
        );
        $self->go_home();
    }
}

=head3 install

This is the 'install' method. Any database tables or other setup that should
be done when the plugin if first installed should be executed in this method.
The installation method should always return true if the installation succeeded
or false if it failed.

=cut

sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

=head3 upgrade

This is the 'upgrade' method. It will be triggered when a newer version of a
plugin is installed over an existing older version of a plugin

=cut

sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

=head3 uninstall

This method will be run just before the plugin files are deleted
when a plugin is uninstalled. It is good practice to clean up
after ourselves!

=cut

sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

=head3 before_send_messages

Plugin hook that runs right before the message queue is processed
in process_message_queue.pl

=cut

sub before_send_messages {
    my ( $self, $params ) = @_;

    my $email_footers = C4::Context->config("email_footers");
    my $footers;
    foreach my $f ( @{$email_footers->{footer}} ) {
        my $lang = $f->{lang} || 'default';
        my $type = $f->{type} || 'text';
        my $content = $f->{content};
        $footers->{$lang}->{$type} = $content;
	}

    my $messages = Koha::Notice::Messages->search(
        {
            status                 => 'pending',
            message_transport_type => 'email',
        }
    );

    my $TranslateNotices = C4::Context->preference('TranslateNotices');

	while ( my $m = $messages->next ) {
		my $lang = 'default';
        if ( $TranslateNotices ) {
			my $patron = Koha::Patrons->find( $m->borrowernumber );
            $lang = $patron->lang;
        }

        my $footers_for_lang = $footers->{$lang} || $footers->{default};

        my $content_type = $m->content_type // q{};
        my $type = $content_type =~ m|^text/html| ? 'html' : 'text';

        my $footer = $footers_for_lang->{$type} || $footers_for_lang->{text} || q{};

        $m->content( $m->content . $footer )->update();
	}
}

1;
