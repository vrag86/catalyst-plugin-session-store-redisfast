package Catalyst::Plugin::Session::Store::RedisFast;

use strict;
use warnings;
use utf8;

use MRO::Compat;
use MIME::Base64 qw/encode_base64 decode_base64/;
use Redis::Fast;
use CBOR::XS qw/encode_cbor decode_cbor/;
use Carp qw/croak/;

use base qw/
    Catalyst::Plugin::Session::Store
    Class::Data::Inheritable
    /;

our $VERSION = '0.01';

__PACKAGE__->mk_classdata(qw/_session_redis_storage/);


sub get_session_data {
    my ($c, $key) = @_;

    if (my ($sid) = $key =~ /^expires:(.*)/) {
        #Return TTL of key
        my $ttl = $c->_redis_op(sub {$c->_session_redis_storage->ttl($key)});
        my $exp_time = time + $ttl;
        $c->log->debug("Getting expires key for '$sid'. TTl: $ttl. Expire time: $exp_time");
        return $exp_time;
    }

    $c->log->debug("Getting '$key'");
    my $data = $c->_redis_op(sub {$c->_session_redis_storage->get($key)}) or return;

    return decode_cbor(decode_base64($data));
}

sub setup_session {
    my ($c) = @_;

    $c->maybe::next::method(@_);
}

sub _verify_redis_connect {
    my ($c) = @_;

    my $cfg = $c->_session_plugin_config;
    croak "Config not contains 'redis_config' section" if not $cfg->{redis_config};

    my $redis_db = delete $cfg->{redis_config}->{redis_db} // 0;

    if ((not $c->_session_redis_storage) or (not $c->_session_redis_storage->ping)) {
        $c->_session_redis_storage(Redis::Fast->new(
                %{$cfg->{redis_config}},
            )
        );
        $c->_session_redis_storage->select($redis_db);
    }
}


sub _redis_op {
    #Execute Redis operation
    my ($c, $op) = @_;
    my $retry_count = 10;
    while (--$retry_count > 0) {
        my $res = eval {&$op};
        if ($@) {
            $c->_verify_redis_connect;
        }
        else {
            return $res;
        }
    }
    die $@;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Catalyst::Plugin::Session::Store::RedisFast - Redis Session store for Catalyst framework

=head1 VERSION

version 0.01

=head1 SYNOPSYS

    use Catalyst qw/
        Session
        Session::Store::RedisFast
    /;

    # Use single instance of Redis
    MyApp->config->{Plugin::Session} = {
        expires             => 3600,
        redis_config        => {
            server                  => '127.0.0.1:6300',
        },
    };

    # or
    # Use Redis Sentinel
    MyApp->config->{Plugin::Session} = {
        expires             => 3600,
        redis_config        => {
            sentinels                   => [
                '192.168.136.90:26379',
                '192.168.136.91:26379',
                '192.168.136.92:26379',
            ],
            reconnect                   => 1000,
            every                       => 100_000,
            service                     => 'master01',
            sentinels_cnx_timeout       => 0.1,
            sentinels_read_timeout      => 1,
            sentinels_write_timeout     => 1,
        },
    };

    # ... in an action:
    $c->session->{foo} = 'bar'; # will be saved

=head1 DESCRIPTION

    C<Catalyst::Plugin::Session::Store::RedisFast> - is a session storage plugin for Catalyst that uses the Redis::Fast as Redis storage module and CBOR::XS as serializing/deserealizing prel data to string

=cut
