package Koha::Plugin::Com::ByWaterSolutions::MessageBee;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Auth;
use C4::Context;
use C4::Log         qw(logaction);
use Koha::DateUtils qw(dt_from_string);
use Koha::Database;
use Koha::Encryption;
use Koha::File::Transport::SFTP;
use Koha::File::Transports;
use Koha::Logger;

use Data::Dumper;
use DateTime;
use File::Path  qw(make_path);
use File::Path  qw(make_path);
use File::Slurp qw(write_file);
use File::Temp  qw(tempdir);
use List::Util  qw(any);
use Mojo::JSON  qw(encode_json decode_json);
use Net::SFTP::Foreign;
use POSIX;
use Try::Tiny;
use YAML::XS qw(Load);

## Here we set our plugin version
our $VERSION         = "{VERSION}";
our $MINIMUM_VERSION = "25.11";

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
    warn "Nested directory created: $default_archive_dir\n";
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

        my $sftp_transports = Koha::File::Transports->search( { transport => 'sftp' }, { order_by => 'name' } );

        $template->param(
            file_transport_id                  => $self->retrieve_data('file_transport_id'),
            sftp_transports                    => $sftp_transports,
            archive_dir                        => $self->retrieve_data('archive_dir') || $default_archive_dir,
            skip_odue_if_other_if_sms_or_email => $self->retrieve_data('skip_odue_if_other_if_sms_or_email'),
        );

        $self->output_html($template->output());
    } else {
        $self->store_data({
            file_transport_id                  => $cgi->param('file_transport_id') || undef,
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

    $self->_migrate_sftp_to_file_transport;

    return 1;
}

=head3 _migrate_sftp_to_file_transport

One-shot migration from the legacy plugin-config SFTP settings (host,
username, password stored in plugin_data) to a Koha::File::Transport
record. Runs on plugin upgrade. Idempotent, so re-running does nothing
once the new file_transport_id is set.

=cut

sub _migrate_sftp_to_file_transport {
    my ($self) = @_;

    return if $self->retrieve_data('file_transport_id');

    my $host                = $self->retrieve_data('host');
    my $username            = $self->retrieve_data('username');
    my $encrypted_password  = $self->retrieve_data('password');
    return unless $host && $username && $encrypted_password;

    my $plain_password = Koha::Encryption->new->decrypt_hex($encrypted_password);
    my $upload_dir     = $ENV{MESSAGEBEE_SFTP_DIR} || 'cust2unique';

    my $transport = Koha::File::Transport::SFTP->new(
        {
            name             => 'MessageBee',
            transport        => 'sftp',
            host             => $host,
            port             => 22,
            user_name        => $username,
            password         => $plain_password,
            auth_mode        => 'password',
            upload_directory => $upload_dir,
        }
    )->store;

    $self->store_data({ file_transport_id => $transport->id });

    return $transport;
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

    # Log4Perl example:
    # log4perl.logger.plugin.MessageBee = WARN, MESSAGEBEE
    # log4perl.appender.MESSAGEBEE=Log::Log4perl::Appender::File
    # log4perl.appender.MESSAGEBEE.filename=/var/log/koha/kohadev/messagebee.log
    # log4perl.appender.MESSAGEBEE.mode=append
    # log4perl.appender.MESSAGEBEE.layout=PatternLayout
    # log4perl.appender.MESSAGEBEE.layout.ConversionPattern=[%d] [%p] %m%n
    # log4perl.appender.MESSAGEBEE.utf8=1
    my $log = Koha::Logger->get({interace => 'plugin', category => 'MessageBee', prefix => 0});

    my $is_cronjob = $0 =~ /process_message_queue.pl$/;

    logaction('MESSAGEBEE', 'STARTED', undef, undef, 'cron') if $is_cronjob;

    if (ref($params->{type}) eq 'ARRAY' && grep(/^skip_messagebee$/, @{$params->{type}})) {
        logaction('MESSAGEBEE', 'SKIPPED', undef, undef, 'cron') if $$is_cronjob;
        return;
    }

    my $test_mode = $ENV{MESSAGEBEE_TEST_MODE};
    my $verbose   = $ENV{MESSAGEBEE_VERBOSE} || $params->{verbose} || 0;

    my $library_name = C4::Context->preference('LibraryName');
    $library_name =~ s/ /_/g;
    my $ts       = strftime("%Y-%m-%dT%H-%M-%S", gmtime(time()));
    my $filename = "$ts-Notices-$library_name.json";

    my $archive_dir = $self->retrieve_data('archive_dir') || $default_archive_dir;
    my $pending_dir = "$archive_dir/pending";
    make_path($pending_dir) unless -d $pending_dir;
    my $pending_path = "$pending_dir/$filename";

    my $info        = {
        archive_dir  => $archive_dir,
        pending_dir  => $pending_dir,
        test_mode    => $test_mode,
        library_name => $library_name,
        timestamp    => $ts,
        filename     => $filename,
        filepath     => $pending_path,
    };

    $is_cronjob && say "MSGBEE - LOG WRITTEN TO $archive_dir/$ts-Notices-$library_name.log";

    $log->info("Running MessageBee before_send_messages hook");

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
                logaction('MESSAGEBEE', 'CREATE_DIR_FAILED', undef, JSON->new->pretty->encode($info), 'cron')
                    if $is_cronjob;
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
    $log->info("TEST MODE IS ENABLED")                  if $test_mode;

    my $search_params = { status => 'pending', content => { -like => '%messagebee: yes%' } };

    my $message_id = $params->{message_id};
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
    $log->info("SEARCH PARAMETERS: " . Data::Dumper::Dumper($search_params));
    $info->{search_params} = $search_params;

    my $other_params = {};
    $other_params->{rows} = $params->{limit} if $params->{limit};
    $is_cronjob && say "OTHER PARAMETERS: " . Data::Dumper::Dumper($other_params);
    $log->info("OTHER PARAMETERS: " . Data::Dumper::Dumper($other_params));
    $info->{other_params}         = $other_params;
    $info->{total_messages_count} = 0;

    my $results = {sent => 0, failed => 0};
    my @message_data;
    my $has_immediate      = 0;
    my $messages_seen      = {};
    my $messages_generated = 0;

    my $skip_odue_if_other_if_sms_or_email = $self->retrieve_data('skip_odue_if_other_if_sms_or_email');
    my $dbh                                = C4::Context->dbh;
    my $letter1                            = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter1) FROM overduerules});
    my $letter2                            = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter2) FROM overduerules});
    my $letter3                            = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter3) FROM overduerules});
    my @odue_letter_codes                  = (@$letter1, @$letter2, @$letter3);

    while (1) {
        my @messages = Koha::Notice::Messages->search($search_params, $other_params)->as_list;
        $log->info("FOUND " . scalar @messages . " MESSAGES TO PROCESS");
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
                $log->info("WORKING ON MESSAGE " . $m->id);
                $is_cronjob && say "MSGBEE - CONTENT:\n" . $m->content if $verbose > 2;
                $log->trace("MESSAGE CONTENTS: " . Data::Dumper::Dumper($m->unblessed));
                my $content = $m->content();

                my $patron;

                my @yaml;
                try {
                    @yaml = Load $content;
                } catch {
                    $is_cronjob && say "MSGBEE - LOADING YAML FAILED!:\n" . $m->content;
                    $log->error("MSGBEE - LOADING YAML FAILED!:" . Data::Dumper::Dumper($m->content));
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
                            $patron //= $checkout->patron;
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
                            $m->update({status => 'failed', failure_code => "Hold with id $yaml->{hold} not found"})
                                && next
                                unless $hold;

                            my $biblio = $hold->biblio;
                            $m->update({
                                status => 'failed', failure_code => "Bib for hold with id $yaml->{hold} not found"
                            })
                                && next
                                unless $biblio;

                            my $biblioitem = $biblio->biblioitem;
                            $m->update({
                                status       => 'failed',
                                failure_code => "Bib item for hold with id $yaml->{hold} not found"
                            })
                                && next
                                unless $biblioitem;

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
                            $m->update({status => 'failed', failure_code => "Hold with id $yaml->{old_hold} not found"})
                                && next
                                unless $hold;

                            my $biblio = Koha::Biblios->find($hold->biblionumber);
                            $m->update({
                                status       => 'failed',
                                failure_code => "Bib for old hold with id $yaml->{old_hold} not found"
                            })
                                && next
                                unless $biblio;

                            my $biblioitem = $biblio->biblioitem;
                            $m->update({
                                status       => 'failed',
                                failure_code => "Bib for old hold with id $yaml->{old_hold} not found"
                            })
                                && next
                                unless $biblio;

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
                        if (   $m->message_transport_type eq 'phone'
                            && $skip_odue_if_other_if_sms_or_email
                            && any { $m->{letter_code} eq $_ } @odue_letter_codes)
                        {
                            my $skip = $patron->notice_email_address || $patron->smsalertnumber;

                            if ($skip) {
                                $m->status('deleted');    # As close a status to 'skipped' as we have
                                $m->failure_code(
                                    'Patron already recieved a "hold ready for pickup" in this notice batch.');
                                $m->update();
                                next;
                            }
                        }

                        if (keys %$data) {
                            $m->update({status => 'sent'}) unless $test_mode;
                            $has_immediate ||= ( $yaml->{messagebee_immediate} || '' ) eq 'yes';
                            $messages_generated++;
                            push(@message_data, $data);
                            $is_cronjob && say "MSGBEE - MESSAGE DATA: " . Data::Dumper::Dumper($data) if $verbose > 1;
                            $results->{sent}++;
                            $log->info("MESSAGE ${\($m->id)} SENT");
                            $info->{results}->{sent}->{successful}++;
                        } else {
                            $m->update({status => 'failed', failure_code => 'NO DATA'}) unless $test_mode;
                            $results->{failed}++;
                            $info->{results}->{sent}->{failed}++;
                            $log->info("MESSAGE ${\($m->id)} FAILED");
                        }
                    } catch {
                        $is_cronjob && say "MSGBEE - ERROR - Processing Message ${\( $m->id )} Failed - $_";
                        $log->error("Processing Message ${\( $m->id )} Failed - $_");
                        $m->status('failed');
                        $m->failure_code("ERROR: $_");
                        $m->update() unless $test_mode;
                        $info->{results}->{sent}->{failed}++;
                        $results->{failed}++;
                    };
                }
            } catch {
                $is_cronjob && say "MSGBEE - ERROR - Processing Message ${\( $m->id )} Failed - $_";
                $log->error("Processing Message ${\( $m->id )} Failed - $_");
                $m->status('failed');
                $m->failure_code("ERROR: $_");
                $m->update() unless $test_mode;
                $info->{results}->{sent}->{failed}++;
                $results->{failed}++;
            };

            $log->info("FINISHED PROCESSING MESSAGE " . $m->id);
        }

        # In test mode none of the bulk-claim, mark-sent, or mark-failed
        # status updates run, so the next iteration would re-find the
        # same pending rows. Stop after one pass to avoid an infinite loop.
        last if $test_mode;
    }

    my $dev_version = '{' . 'VERSION' . '}';                                         # Prevents substitution
    my $v           = $VERSION eq $dev_version ? "DEVELOPMENT VERSION" : $VERSION;
    my $json
        = encode_json({json_structure_version => '3', messagebee_plugin_version => $v, messages => \@message_data});

    if ($archive_dir) {
        my $archive_path = $archive_dir . "/$filename";
        write_file($archive_path, $json);
        $is_cronjob && say "MSGBEE - FILE WRITTEN TO $archive_path";
        $log->info("MSGBEE - FILE WRITTEN TO $archive_path");
    }

    unless ($test_mode) {
        # Always queue the payload into the pending spool. The actual
        # SFTP upload runs either in the current process (cron context)
        # or in a detached grandchild (request context with an
        # immediate-flagged message); plain request context leaves the
        # file in the spool for the next cron tick to pick up.
        write_file($pending_path, $json);
        $is_cronjob && say "MSGBEE - FILE QUEUED AT $pending_path";
        $log->info("MSGBEE - FILE QUEUED AT $pending_path");

        if ($is_cronjob) {
            $self->_upload_pending($pending_dir, $archive_dir, $log);
        }
        elsif ($has_immediate) {
            $self->_async_upload($pending_dir, $archive_dir, $log);
        }
    }

    logaction('MESSAGEBEE', 'DONE',               undef, undef,                            'cron') if $is_cronjob;
    logaction('MESSAGEBEE', 'MESSAGES_PROCESSED', undef, JSON->new->pretty->encode($info), 'cron') if $is_cronjob;
}

sub _upload_pending {
    my ( $self, $pending_dir, $archive_dir, $log ) = @_;

    return unless -d $pending_dir;

    opendir my $dh, $pending_dir or do {
        $log->error("MSGBEE - cannot open spool dir $pending_dir: $!");
        return;
    };
    my @files = sort grep { /\.json$/ } readdir $dh;
    closedir $dh;

    return unless @files;

    my $file_transport_id = $self->retrieve_data('file_transport_id');
    unless ($file_transport_id) {
        $log->warn( "MSGBEE - no file_transport_id configured, " . scalar(@files) . " files remain in spool" );
        return;
    }

    my $transport = Koha::File::Transports->find($file_transport_id);
    unless ($transport) {
        $log->warn(
            "MSGBEE - file_transport_id $file_transport_id no longer exists, " . scalar(@files) . " files remain in spool"
        );
        return;
    }

    my $connected;
    try { $connected = $transport->connect } catch { $log->warn("MSGBEE - SFTP connect threw: $_") };
    unless ($connected) {
        $log->warn( "MSGBEE - SFTP connect failed, " . scalar(@files) . " files remain in spool" );
        return;
    }

    for my $f (@files) {
        my $path = "$pending_dir/$f";
        try {
            $transport->upload_file( $path, $f )
                or die "upload_file failed";
            unlink $path or die "unlink $path failed: $!";
            $log->info("MSGBEE - uploaded $f");
        } catch {
            $log->warn("MSGBEE - failed to upload $f, left in spool. $_");
        };
    }

    $transport->disconnect;
}

sub _async_upload {
    my ( $self, $pending_dir, $archive_dir, $log ) = @_;

    my $pid = fork();
    if ( !defined $pid ) {
        $log->error("MSGBEE - fork failed: $!  -- file left in spool for next cron tick");
        return;
    }
    if ( $pid == 0 ) {
        # Intermediate child opens a new session and double-forks so the
        # grandchild is reparented to init, so nobody has to wait on it.
        POSIX::setsid();
        if ( fork() == 0 ) {
            # Grandchild is the actual SFTP worker.
            open STDIN,  '<',  '/dev/null';
            open STDOUT, '>>', '/dev/null';

            # The parent's DB handle is not fork-safe; force a reconnect on
            # next access.
            try { Koha::Database->schema->storage->disconnect } catch { };

            try {
                $log->info("MSGBEE - detached upload starting");
                $self->_upload_pending( $pending_dir, $archive_dir, $log );
                $log->info("MSGBEE - detached upload complete");
            } catch {
                $log->error("MSGBEE - detached upload crashed: $_");
            };
            exit 0;
        }
        exit 0;
    }
    waitpid $pid, 0;
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
