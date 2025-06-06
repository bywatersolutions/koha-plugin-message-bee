package Koha::Plugin::Com::ByWaterSolutions::MessageBee;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Auth;
use C4::Context;
use C4::Log qw(logaction);
use Koha::DateUtils qw(dt_from_string);

use Data::Dumper;
use DateTime;
use File::Path qw(make_path);
use File::Path qw(make_path);
use File::Slurp qw(write_file);
use File::Temp qw(tempdir);
use List::Util qw(any);
use Log::Log4perl qw(:easy);
use Log::Log4perl;
use Mojo::JSON qw(encode_json decode_json);
use Net::SFTP::Foreign;
use POSIX;
use Try::Tiny;
use YAML::XS qw(Load);

## Here we set our plugin version
our $VERSION         = "{VERSION}";
our $MINIMUM_VERSION = "{MINIMUM_VERSION}";

our $metadata = {
    name            => 'Unique Management Services - MessageBee',
    author          => 'Kyle M Hall',
    date_authored   => '2021-09-20',
    date_updated    => "1900-01-01",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Plugin to forward messages to MessageBee for processing and sending',
};

our $instance = C4::Context->config('database');
$instance =~ s/koha_//;


our $default_archive_dir = $ENV{MESSAGEBEE_ARCHIVE_PATH} || "/var/lib/koha/$instance/messagebee_archive";

unless (-d $default_archive_dir) {
    make_path($default_archive_dir) or die "Failed to create path '$default_archive_dir': $!";
    print "Nested directory created: $default_archive_dir\n";
} else {
    print "Directory already exists: $default_archive_dir\n";
}


=head3 new

=cut

sub new {
    my ($class, $args) = @_;

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
    my ($self, $args) = @_;
    my $cgi = $self->{'cgi'};

    unless ($cgi->param('save')) {
        my $template = $self->get_template({file => 'configure.tt'});

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            host                               => $self->retrieve_data('host'),
            username                           => $self->retrieve_data('username'),
            password                           => $self->retrieve_data('password'),
            archive_dir                        => $self->retrieve_data('archive_dir') || $default_archive_dir,
            skip_odue_if_other_if_sms_or_email => $self->retrieve_data('skip_odue_if_other_if_sms_or_email'),
        );

        $self->output_html($template->output());
    } else {
        $self->store_data({
            host                               => $cgi->param('host'),
            username                           => $cgi->param('username'),
            password                           => $cgi->param('password'),
            archive_dir                        => $cgi->param('archive_dir'),
            skip_odue_if_other_if_sms_or_email => $cgi->param('skip_odue_if_other_if_sms_or_email'),
        });
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
    my ($self, $args) = @_;

    return 1;
}

=head3 upgrade

This is the 'upgrade' method. It will be triggered when a newer version of a
plugin is installed over an existing older version of a plugin

=cut

sub upgrade {
    my ($self, $args) = @_;

    return 1;
}

=head3 uninstall

This method will be run just before the plugin files are deleted
when a plugin is uninstalled. It is good practice to clean up
after ourselves!

=cut

sub uninstall() {
    my ($self, $args) = @_;

    return 1;
}

=head3 before_send_messages

Plugin hook that runs right before the message queue is processed
in process_message_queue.pl

=cut

sub before_send_messages {
    my ($self, $params) = @_;

    my $is_cronjob = $0 =~ /process_message_queue.pl$/;

    logaction('MESSAGEBEE', 'STARTED', undef, undef, 'cron') if $is_cronjob;

    if (ref($params->{type}) eq 'ARRAY' && grep(/^skip_messagebee$/, @{$params->{type}})) {
        logaction('MESSAGEBEE', 'SKIPPED', undef, undef, 'cron') if $$is_cronjob;
        return;
    }

    my $test_mode = $ENV{MESSAGEBEE_TEST_MODE};
    my $verbose   = $ENV{MESSAGEBEE_VERBOSE} || $params->{verbose};

    my $library_name = C4::Context->preference('LibraryName');
    $library_name =~ s/ /_/g;
    my $dir      = tempdir(CLEANUP => 0);
    my $ts       = strftime("%Y-%m-%dT%H-%M-%S", gmtime(time()));
    my $filename = "$ts-Notices-$library_name.json";
    my $realpath = "$dir/$filename";

    my $archive_dir = $self->retrieve_data('archive_dir') || $default_archive_dir;
    my $info        = {
        archive_dir  => $archive_dir,
        test_mode    => $test_mode,
        library_name => $library_name,
        timestamp    => $ts,
        filename     => $filename,
        filepath     => $realpath,
    };

    Log::Log4perl->easy_init({level => $DEBUG, file => ">>$archive_dir/$ts-Notices-$library_name.log"});
    $is_cronjob && say "MSGBEE - LOG WRITTEN TO $archive_dir/$ts-Notices-$library_name.log";

    INFO("Running MessageBee before_send_messages hook");

    if ($archive_dir) {
        unless (-d $archive_dir) {
            make_path $archive_dir or die "Failed to create path: $archive_dir";
        }

        if (-d $archive_dir) {
            my $dt = dt_from_string();
            $dt->subtract(days => 30);
            my $age_threshold = $dt->datetime;
            my $dirh;
            try {
                opendir $dirh, $archive_dir or die "Cannot open directory: $!";
            } catch {
                $info->{error_message} = $_;
                logaction('MESSAGEBEE', 'CREATE_DIR_FAILED', undef, JSON->new->pretty->encode($info), 'cron') if $is_cronjob;
                die "Cannot open directory $archive_dir: $_";
            };
            my @files = readdir $dirh;
            closedir $dirh;

            foreach my $f (@files) {
                next unless $f =~ /log|json$/;
                if ($f lt $age_threshold) {
                    unlink($archive_dir . "/" . $f);
                }
            }
        }
    }

    $is_cronjob && say "MSGBEE - MESSAGE BEE TEST MODE" if $test_mode;
    INFO("TEST MODE IS ENABLED")         if $test_mode;

    my $search_params = {status => 'pending', content => {-like => '%messagebee: yes%'},};

    my $message_id  = $params->{message_id};
    $search_params->{message_id} = $message_id if $message_id;

    # 22.11.00, 22.05.8, 21.11.14 +, bug 27265
    $search_params->{message_transport_type} = $params->{type}
        if ref($params->{type}) eq 'ARRAY' && scalar @{$params->{type}} && $params->{type}->[0] ne 'messagebee';

    # Older versions of Koha
    $search_params->{message_transport_type} = $params->{type}
        if ref($params->{type}) eq q{} && $params->{type} && $params->{type} ne 'messagebee';

    # 22.11.00, 22.05.8, 21.11.14 +, bug 27265
    $search_params->{letter_code} = $params->{letter_code}
        if ref($params->{letter_code}) eq 'ARRAY' && scalar @{$params->{letter_code}};

    # Older versions of Koha
    $search_params->{letter_code} = $params->{letter_code}
        if ref($params->{letter_code}) eq q{} && $params->{letter_code};

    $is_cronjob && say "MSGBEE - SEARCH PARAMETERS: " . Data::Dumper::Dumper($search_params) if $verbose;
    INFO("SEARCH PARAMETERS: " . Data::Dumper::Dumper($search_params));
    $info->{search_params} = $search_params;

    my $other_params = {};
    $other_params->{rows} = $params->{limit} if $params->{limit};
    $is_cronjob && say "OTHER PARAMETERS: " . Data::Dumper::Dumper($other_params);
    INFO("OTHER PARAMETERS: " . Data::Dumper::Dumper($other_params));
    $info->{other_params}         = $other_params;
    $info->{total_messages_count} = 0;

    my $results = {sent => 0, failed => 0};
    my @message_data;
    my $messages_seen      = {};
    my $messages_generated = 0;

    my $skip_odue_if_other_if_sms_or_email = $self->retrieve_data('skip_odue_if_other_if_sms_or_email');
    my $dbh = C4::Context->dbh;
    my $letter1 = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter1) FROM overduerules});
    my $letter2 = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter2) FROM overduerules});
    my $letter3 = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter3) FROM overduerules});
    my @odue_letter_codes = ( @$letter1, @$letter2, @$letter3 );

    while (1) {
        my @messages = Koha::Notice::Messages->search($search_params, $other_params)->as_list;
        INFO("FOUND " . scalar @messages . " MESSAGES TO PROCESS");
        last unless scalar @messages;

        $info->{total_messages_count} += scalar @messages;

        unless ($test_mode) {
            foreach my $m (@messages) {
                $m->update({status => 'deleted'});
            }
        }

        foreach my $m (@messages) {
            $info->{results}->{types}->{$m->letter_code}->{$m->message_transport_type}++;

            try {
                $is_cronjob && say "MSGBEE - WORKING ON MESSAGE " . $m->id if $verbose;
                INFO("WORKING ON MESSAGE " . $m->id);
                $is_cronjob && say "MSGBEE - CONTENT:\n" . $m->content if $verbose > 2;
                TRACE("MESSAGE CONTENTS: " . Data::Dumper::Dumper($m->unblessed));
                my $content = $m->content();

                my $patron;

                my @yaml;
                try {
                    @yaml = Load $content;
                } catch {
                    $is_cronjob && say "MSGBEE - LOADING YAML FAILED!:\n" . $m->content;
                    ERROR("MSGBEE - LOADING YAML FAILED!:" . Data::Dumper::Dumper($m->content));
                    @yaml = undef;
                };

                foreach my $yaml (@yaml) {
                  try {

                    next unless $yaml;
                    next unless ref $yaml eq 'HASH';
                    next unless $yaml->{messagebee};
                    next unless $yaml->{messagebee} eq 'yes';

                    $messages_seen->{$m->message_id} = 1;

                    my $data;
                    $data->{message} = $self->scrub_message($m->unblessed);

                    # Handle patron key first in case old checkouts or holds have been anonymized
                    try {
                        $patron         //= Koha::Patrons->find($yaml->{patron})    if $yaml->{patron};
                        $data->{patron} //= $self->scrub_patron($patron->unblessed) if $patron;
                    } catch {
                        $is_cronjob && say "MSGBEE - Fetching patron failed - $_";
                    };


                    ## Handle 'checkout' / 'old_checkout'
                    my $checkout;
                    if ($yaml->{checkout}) {
                        $checkout = Koha::Checkouts->find($yaml->{checkout});
                    }
                    if ($yaml->{old_checkout}) {
                        $checkout = Koha::Old::Checkouts->find($yaml->{old_checkout});
                    }
                    if ($checkout) {
                        $patron          //= $checkout->patron;
                        $data->{patron}  = $self->scrub_patron($patron->unblessed);
                        $data->{library} = $checkout->library->unblessed;

                        my $subdata;
                        my $item = $checkout->item;
                        $subdata->{checkout}   = $checkout->unblessed;
                        $subdata->{item}       = $item->unblessed;
                        $subdata->{biblio}     = $self->scrub_biblio($item->biblio->unblessed);
                        $subdata->{biblioitem} = $item->biblioitem->unblessed;
                        $subdata->{itemtype}   = $item->itemtype->unblessed;

                        $data->{checkouts} = [$subdata];
                    }

                    ## Handle 'checkouts'
                    if ($yaml->{checkouts}) {
                        my @checkouts = split(/,/, $yaml->{checkouts});

                        foreach my $id (@checkouts) {
                            my $checkout = Koha::Checkouts->find($id);
                            next unless $checkout;

                            $patron //= $checkout->patron;
                            $data->{patron} //= $self->scrub_patron($patron->unblessed);

                            my $subdata;
                            my $item = $checkout->item;
                            $subdata->{checkout}   = $checkout->unblessed;
                            $subdata->{library}    = $checkout->library->unblessed;
                            $subdata->{item}       = $item->unblessed;
                            $subdata->{biblio}     = $self->scrub_biblio($item->biblio->unblessed);
                            $subdata->{biblioitem} = $item->biblioitem->unblessed;
                            $subdata->{itemtype}   = $item->itemtype->unblessed;

                            $data->{checkouts} //= [];
                            push(@{$data->{checkouts}}, $subdata);
                        }
                    }

                    ## Handle 'hold'
                    if ($yaml->{hold}) {
                        my $hold = Koha::Holds->find($yaml->{hold});
                        $m->update({status => 'failed', failure_code => "Hold with id $yaml->{hold} not found"}) && next unless $hold;

                        my $biblio = $hold->biblio;
                        $m->update({status => 'failed', failure_code => "Bib for hold with id $yaml->{hold} not found"}) && next unless $biblio;

                        my $biblioitem = $biblio->biblioitem;
                        $m->update({status => 'failed', failure_code => "Bib item for hold with id $yaml->{hold} not found"}) && next unless $biblioitem;

                        $patron //= $hold->patron;
                        $data->{patron} //= $self->scrub_patron($patron->unblessed);

                        my $subdata;
                        $subdata->{hold}           = $hold->unblessed;
                        $subdata->{pickup_library} = $hold->branch->unblessed;
                        $subdata->{biblio}         = $self->scrub_biblio($biblio->unblessed);
                        $subdata->{biblioitem}     = $biblioitem->unblessed;

                        if (my $item = $hold->item) {
                            $subdata->{item}     = $item->unblessed;
                            $subdata->{itemtype} = $item->itemtype->unblessed;
                        }

                        $data->{holds} = [$subdata];
                    }

                    ## Handle 'old_hold'
                    if ($yaml->{old_hold}) {
                        my $hold = Koha::Old::Holds->find($yaml->{old_hold});
                        $m->update({status => 'failed', failure_code => "Hold with id $yaml->{old_hold} not found"}) && next unless $hold;

                        my $biblio = Koha::Biblios->find($hold->biblionumber);
                        $m->update({status => 'failed', failure_code => "Bib for old hold with id $yaml->{old_hold} not found"}) && next unless $biblio;

                        my $biblioitem = $biblio->biblioitem;
                        $m->update({status => 'failed', failure_code => "Bib for old hold with id $yaml->{old_hold} not found"}) && next unless $biblio;

                        $patron //= $hold->patron;
                        $data->{patron} //= $self->scrub_patron($patron->unblessed);

                        my $subdata;
                        $subdata->{holds}          = [$hold->unblessed];
                        $subdata->{pickup_library} = Koha::Libraries->find($hold->branchcode);
                        $subdata->{biblio}         = $self->scrub_biblio($biblio->unblessed);
                        $subdata->{biblioitem}     = $biblioitem->unblessed;

                        if (my $item = $hold->item) {
                            $subdata->{item}     = $item->unblessed;
                            $subdata->{itemtype} = $item->itemtype->unblessed;
                        }

                        $data->{holds} = [$subdata];
                    }

                    ## Handle 'holds'
                    if ($yaml->{holds}) {
                        my @holds = split(/,/, $yaml->{holds});

                        foreach my $id (@holds) {
                            my $hold = Koha::Holds->find($id);
                            next unless $hold;

                            $patron //= $hold->patron;
                            $data->{patron} //= $self->scrub_patron($patron->unblessed);

                            my $subdata;
                            my $item = $hold->item;
                            $subdata->{hold}           = $hold->unblessed;
                            $subdata->{pickup_library} = $hold->branch->unblessed;
                            if ($item) {
                                $subdata->{item}       = $item->unblessed;
                                $subdata->{itemtype}   = $item->itemtype->unblessed;
                                $subdata->{biblio}     = $self->scrub_biblio($item->biblio->unblessed);
                                $subdata->{biblioitem} = $item->biblioitem->unblessed;
                            }

                            $data->{holds} //= [];
                            push(@{$data->{holds}}, $subdata);
                        }
                    }

                    ## Handle misc key/value pairs
                    try {
                        $data->{library} ||= Koha::Libraries->find($yaml->{library})->unblessed if $yaml->{library};
                    } catch {
                        $is_cronjob && say "MSGBEE - Fetching library failed - $_";
                    };

                    try {
                        $data->{item} ||= Koha::Items->find($yaml->{item})->unblessed if $yaml->{item};
                    } catch {
                        $is_cronjob && say "MSGBEE - Fetching item failed - $_";
                    };

                    try {
                        $data->{biblio} ||= $self->scrub_biblio(Koha::Biblios->find($yaml->{biblio})->unblessed)
                            if $yaml->{biblio};
                    } catch {
                        $is_cronjob && say "MSGBEE - Fetching biblio failed - $_";
                    };

                    try {
                        $data->{biblioitem} ||= Koha::Biblioitems->find($yaml->{biblioitem})->unblessed
                            if $yaml->{biblioitem};
                    } catch {
                        $is_cronjob && say "MSGBEE - Fetching biblioitem failed - $_";
                    };

                    try {
                        $data->{patron}->{account_balance} = $patron->account->balance if $patron;
                    } catch {
                        $is_cronjob && say "MSGBEE - Fetching patron account balance failed - $_";
                    };

                    # If enabled, skip sending if this is an overdue notice *and* the patron has an sms number or email address
                    if ($m->message_transport_type eq 'phone' && $skip_odue_if_other_if_sms_or_email && any { $m->{letter_code} eq $_ } @odue_letter_codes) {
                        my $skip = $patron->notice_email_address || $patron->smsalertnumber;

                        if ($skip) {
                            $m->status('deleted');    # As close a status to 'skipped' as we have
                            $m->failure_code('Patron already recieved a "hold ready for pickup" in this notice batch.');
                            $m->update();
                            next;
                        }
                    }

                    if (keys %$data) {
                        $m->update({status => 'sent'}) unless $test_mode;
                        $messages_generated++;
                        push(@message_data, $data);
                        $is_cronjob && say "MSGBEE - MESSAGE DATA: " . Data::Dumper::Dumper($data) if $verbose > 1;
                        $results->{sent}++;
                        INFO("MESSAGE ${\($m->id)} SENT");
                        $info->{results}->{sent}->{successful}++;
                    } else {
                        $m->update({status => 'failed', failure_code => 'NO DATA'}) unless $test_mode;
                        $results->{failed}++;
                        $info->{results}->{sent}->{failed}++;
                        INFO("MESSAGE ${\($m->id)} FAILED");
                    }
                } catch {
                    $is_cronjob && say "MSGBEE - ERROR - Processing Message ${\( $m->id )} Failed - $_";
                    ERROR("Processing Message ${\( $m->id )} Failed - $_");
                    $m->status('failed');
                    $m->failure_code("ERROR: $_");
                    $m->update() unless $test_mode;
                    $info->{results}->{sent}->{failed}++;
                    $results->{failed}++;
                };
              }
            } catch {
                $is_cronjob && say "MSGBEE - ERROR - Processing Message ${\( $m->id )} Failed - $_";
                ERROR("Processing Message ${\( $m->id )} Failed - $_");
                $m->status('failed');
                $m->failure_code("ERROR: $_");
                $m->update() unless $test_mode;
                $info->{results}->{sent}->{failed}++;
                $results->{failed}++;
            };

            INFO("FINISHED PROCESSING MESSAGE " . $m->id);
        }
    }

    my $dev_version = '{' . 'VERSION' . '}';                                         # Prevents substitution
    my $v           = $VERSION eq $dev_version ? "DEVELOPMENT VERSION" : $VERSION;
    my $json
        = encode_json({json_structure_version => '3', messagebee_plugin_version => $v, messages => \@message_data});

    if ($archive_dir) {
        my $archive_path = $archive_dir . "/$filename";
        write_file($archive_path, $json);
        $is_cronjob && say "MSGBEE - FILE WRITTEN TO $archive_path";
        INFO("MSGBEE - FILE WRITTEN TO $archive_path");
    }

    unless ($test_mode) {
        write_file($realpath, $json);
        $is_cronjob && say "MSGBEE - FILE WRITTEN TO $realpath";
        INFO("MSGBEE - FILE WRITTEN TO $realpath");

        my $host      = $self->retrieve_data('host');
        my $username  = $self->retrieve_data('username');
        my $password  = $self->retrieve_data('password');
        my $directory = $ENV{MESSAGEBEE_SFTP_DIR} || 'cust2unique';

        my $sftp = Net::SFTP::Foreign->new(host => $host, user => $username, port => 22, password => $password);

        try {
            $sftp->die_on_error("Unable to establish SFTP connection");
            $sftp->setcwd($directory)        or die "unable to change cwd: " . $sftp->error;
            $sftp->put($realpath, $filename) or die "put failed: " . $sftp->error;
        } catch {
            $info->{sftp_error_message} = $_;
        }
    }

    logaction('MESSAGEBEE', 'DONE',               undef, undef,                            'cron') if $is_cronjob;
    logaction('MESSAGEBEE', 'MESSAGES_PROCESSED', undef, JSON->new->pretty->encode($info), 'cron') if $is_cronjob;
}

sub scrub_biblio {
    my ($self, $biblio) = @_;

    delete $biblio->{abstract};

    return $biblio;
}

sub scrub_patron {
    my ($self, $patron) = @_;

    delete $patron->{password};
    delete $patron->{borrowernotes};

    return $patron;
}

sub scrub_message {
    my ($self, $message) = @_;

    delete $message->{content};
    delete $message->{metadata};

    return $message;
}

sub api_routes {
    my ($self, $args) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'messagebee';
}

1;
