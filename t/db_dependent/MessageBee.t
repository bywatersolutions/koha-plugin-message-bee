#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 10;
use Test::MockModule;

use File::Slurp qw( read_file write_file );
use File::Temp  qw( tempdir );

use Koha::Database;
use Koha::Encryption;
use Koha::Logger;
use Koha::Plugin::Com::ByWaterSolutions::MessageBee;

use t::lib::TestBuilder;
use t::lib::Mocks;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

sub _new_plugin {
    my (%args) = @_;
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::MessageBee->new(
        { enable_plugins => 1 }
    );
    $plugin->store_data(
        {
            host     => $args{host}     // '192.0.2.1',
            username => $args{username} // 'testuser',
            password => Koha::Encryption->new->encrypt_hex( $args{password} // 'testpw' ),
            ( exists $args{archive_dir} ? ( archive_dir => $args{archive_dir} ) : () ),
        }
    );
    return $plugin;
}

sub _enqueue_message {
    my (%args) = @_;
    my $immediate = $args{immediate} ? "messagebee_immediate: yes\n" : '';
    return $builder->build_object(
        {
            class => 'Koha::Notice::Messages',
            value => {
                status                 => 'pending',
                content                => "messagebee: yes\n${immediate}foo: bar\n",
                message_transport_type => 'email',
                letter_code            => 'MBTEST',
            },
        }
    );
}

sub _new_logger {
    return Koha::Logger->get( { interface => 'plugin', category => 'MessageBee', prefix => 0 } );
}

subtest 'before_send_messages writes payload to pending spool' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;

    my $archive_dir = tempdir( CLEANUP => 1 );
    my $plugin      = _new_plugin( archive_dir => $archive_dir );

    no warnings 'redefine';
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_upload_pending = sub { };
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_async_upload   = sub { };

    local $0 = '/some/cgi-script.pl';
    my $msg = _enqueue_message();
    $plugin->before_send_messages( { message_id => $msg->message_id, type => ['email'] } );

    $msg->discard_changes;
    is( $msg->status, 'sent', 'message marked sent' );

    my @pending = glob("$archive_dir/pending/*.json");
    is( scalar @pending, 1, 'one file written to pending spool' );
    like( read_file( $pending[0] ), qr/"messages":/, 'pending payload contains messages array' );

    my @archive = grep { !/pending/ } glob("$archive_dir/*.json");
    cmp_ok( scalar @archive, '>=', 1, 'audit copy written to archive_dir' );

    $schema->storage->txn_rollback;
};

subtest 'request context, no immediate flag, does not upload' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;

    my $archive_dir = tempdir( CLEANUP => 1 );
    my $plugin      = _new_plugin( archive_dir => $archive_dir );

    my ( $sync, $async ) = ( 0, 0 );
    no warnings 'redefine';
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_upload_pending = sub { $sync++ };
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_async_upload   = sub { $async++ };

    local $0 = '/some/cgi-script.pl';
    my $msg = _enqueue_message( immediate => 0 );
    $plugin->before_send_messages( { message_id => $msg->message_id, type => ['email'] } );

    is( $sync,  0, '_upload_pending not called in request context' );
    is( $async, 0, '_async_upload not called when no immediate flag is set' );
    my @pending = glob("$archive_dir/pending/*.json");
    is( scalar @pending, 1, 'file still queued in pending spool for next cron tick' );

    $schema->storage->txn_rollback;
};

subtest 'request context, immediate flag, fires async upload' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my $archive_dir = tempdir( CLEANUP => 1 );
    my $plugin      = _new_plugin( archive_dir => $archive_dir );

    my ( $sync, $async ) = ( 0, 0 );
    no warnings 'redefine';
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_upload_pending = sub { $sync++ };
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_async_upload   = sub { $async++ };

    local $0 = '/some/cgi-script.pl';
    my $msg = _enqueue_message( immediate => 1 );
    $plugin->before_send_messages( { message_id => $msg->message_id, type => ['email'] } );

    is( $sync,  0, '_upload_pending not called directly in request context' );
    is( $async, 1, '_async_upload called once when an immediate-flagged message is in the batch' );

    $schema->storage->txn_rollback;
};

subtest 'cron context drains the spool synchronously' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my $archive_dir = tempdir( CLEANUP => 1 );
    my $plugin      = _new_plugin( archive_dir => $archive_dir );

    my ( $sync, $async ) = ( 0, 0 );
    no warnings 'redefine';
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_upload_pending = sub { $sync++ };
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_async_upload   = sub { $async++ };

    # Plugin detects cron context by checking $0 ends with process_message_queue.pl.
    local $0 = '/kohadevbox/koha/misc/cronjobs/process_message_queue.pl';
    my $msg = _enqueue_message( immediate => 1 );
    $plugin->before_send_messages( { message_id => $msg->message_id, type => ['email'] } );

    is( $sync,  1, '_upload_pending called once in cron context' );
    is( $async, 0, '_async_upload not called in cron context, even with immediate flag' );

    $schema->storage->txn_rollback;
};

subtest '_upload_pending uploads each file and removes it on success' => sub {
    plan tests => 3;

    my $pending_dir = tempdir( CLEANUP => 1 );
    write_file( "$pending_dir/file_a.json", '{"messages":[]}' );
    write_file( "$pending_dir/file_b.json", '{"messages":[]}' );

    my $put_count = 0;
    my $sftp_mock = Test::MockModule->new('Net::SFTP::Foreign');
    $sftp_mock->mock( 'new',          sub { bless { ok => 1 }, shift } );
    $sftp_mock->mock( 'die_on_error', sub { } );
    $sftp_mock->mock( 'setcwd',       sub { 1 } );
    $sftp_mock->mock( 'put',          sub { $put_count++; return 1 } );
    $sftp_mock->mock( 'error',        sub { undef } );

    my $plugin = _new_plugin();
    $plugin->_upload_pending( $pending_dir, $pending_dir, _new_logger() );

    is( $put_count, 2, 'put called once per pending file' );
    ok( !-e "$pending_dir/file_a.json", 'file_a removed after successful upload' );
    ok( !-e "$pending_dir/file_b.json", 'file_b removed after successful upload' );
};

subtest '_upload_pending leaves a failed file in the spool and continues' => sub {
    plan tests => 2;

    my $pending_dir = tempdir( CLEANUP => 1 );
    write_file( "$pending_dir/good.json", '{}' );
    write_file( "$pending_dir/bad.json",  '{}' );

    my $sftp_mock = Test::MockModule->new('Net::SFTP::Foreign');
    $sftp_mock->mock( 'new',          sub { bless { ok => 1 }, shift } );
    $sftp_mock->mock( 'die_on_error', sub { } );
    $sftp_mock->mock( 'setcwd',       sub { 1 } );
    $sftp_mock->mock(
        'put',
        sub {
            my ( $self, $local, $remote ) = @_;
            return $remote eq 'bad.json' ? undef : 1;
        }
    );
    $sftp_mock->mock( 'error', sub { 'simulated put failure' } );

    my $plugin = _new_plugin();
    $plugin->_upload_pending( $pending_dir, $pending_dir, _new_logger() );

    ok( !-e "$pending_dir/good.json", 'successful upload removed from spool' );
    ok( -e "$pending_dir/bad.json",   'failed upload left in spool for retry' );
};

subtest '_upload_pending bails when the SFTP connection cannot be established' => sub {
    plan tests => 2;

    my $pending_dir = tempdir( CLEANUP => 1 );
    write_file( "$pending_dir/a.json", '{}' );

    my $put_count = 0;
    my $sftp_mock = Test::MockModule->new('Net::SFTP::Foreign');
    $sftp_mock->mock( 'new',          sub { die "could not connect" } );
    $sftp_mock->mock( 'die_on_error', sub { } );
    $sftp_mock->mock( 'setcwd',       sub { 1 } );
    $sftp_mock->mock( 'put',          sub { $put_count++; return 1 } );
    $sftp_mock->mock( 'error',        sub { 'simulated' } );

    my $plugin = _new_plugin();
    $plugin->_upload_pending( $pending_dir, $pending_dir, _new_logger() );

    is( $put_count, 0, 'no put attempted when connect fails' );
    ok( -e "$pending_dir/a.json", 'file left in spool after connect failure' );
};

subtest 'test_mode short-circuits the spool write and DB updates' => sub {
    plan tests => 5;
    $schema->storage->txn_begin;

    my $archive_dir = tempdir( CLEANUP => 1 );
    my $plugin      = _new_plugin( archive_dir => $archive_dir );

    my ( $sync, $async ) = ( 0, 0 );
    no warnings 'redefine';
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_upload_pending = sub { $sync++ };
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_async_upload   = sub { $async++ };

    local $ENV{MESSAGEBEE_TEST_MODE} = 1;
    local $0 = '/some/cgi-script.pl';
    my $msg = _enqueue_message();
    $plugin->before_send_messages( { message_id => $msg->message_id, type => ['email'] } );

    $msg->discard_changes;
    is( $msg->status, 'pending', 'message status unchanged in test mode' );
    is( $sync,        0,         '_upload_pending not called in test mode' );
    is( $async,       0,         '_async_upload not called in test mode' );

    my @pending = glob("$archive_dir/pending/*.json");
    is( scalar @pending, 0, 'no file written to pending spool in test mode' );

    my @archive = grep { !/pending/ } glob("$archive_dir/*.json");
    cmp_ok( scalar @archive, '>=', 1, 'audit copy still written to archive_dir in test mode' );

    $schema->storage->txn_rollback;
};

subtest 'mixed batch with one immediate message fires async upload for the whole batch' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my $archive_dir = tempdir( CLEANUP => 1 );
    my $plugin      = _new_plugin( archive_dir => $archive_dir );

    my $async = 0;
    no warnings 'redefine';
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_upload_pending = sub { };
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_async_upload   = sub { $async++ };

    _enqueue_message( immediate => 0 );
    _enqueue_message( immediate => 1 );

    local $0 = '/some/cgi-script.pl';
    $plugin->before_send_messages( { type => ['email'], letter_code => ['MBTEST'] } );

    is( $async, 1, '_async_upload called once for the whole batch when any message is immediate' );

    my @pending = glob("$archive_dir/pending/*.json");
    is( scalar @pending, 1, 'a single combined payload was queued' );

    $schema->storage->txn_rollback;
};

subtest 'messages without a messagebee: yes tag are excluded from the batch' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;

    my $archive_dir = tempdir( CLEANUP => 1 );
    my $plugin      = _new_plugin( archive_dir => $archive_dir );

    no warnings 'redefine';
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_upload_pending = sub { };
    local *Koha::Plugin::Com::ByWaterSolutions::MessageBee::_async_upload   = sub { };

    # An untagged message sharing letter_code and transport with a tagged one.
    my $untagged = $builder->build_object(
        {
            class => 'Koha::Notice::Messages',
            value => {
                status                 => 'pending',
                content                => "subject: hello\nbody: world\n",
                message_transport_type => 'email',
                letter_code            => 'MBTEST',
            },
        }
    );
    my $tagged = _enqueue_message();

    local $0 = '/some/cgi-script.pl';
    $plugin->before_send_messages( { type => ['email'], letter_code => ['MBTEST'] } );

    $tagged->discard_changes;
    $untagged->discard_changes;

    is( $tagged->status,   'sent',    'tagged message was processed' );
    is( $untagged->status, 'pending', 'untagged message was not touched' );

    my @pending = glob("$archive_dir/pending/*.json");
    is( scalar @pending, 1, 'only one batch file queued' );

    $schema->storage->txn_rollback;
};
