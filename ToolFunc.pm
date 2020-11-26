package ToolFunc;
use strict;
use warnings FATAL => 'all';
use MY::DB;
use Config::Any::JSON;
use utf8;
use JSON;
use Redis;
use Log::Mini;

our @EXPORT = qw/privilege config_hash set_session_cover_pre set_session_no_cover_pre/;

our $syslog = Log::Mini->new( file => '/tmp/www/syserror.log', synced=>1 );

BEGIN {
	binmode(STDIN, ":utf8");
	binmode(STDOUT, ":utf8");
	# 解决中文乱码问题
	$ENV{NLS_LANG} = "SIMPLIFIED CHINESE_CHINA.AL32UTF8";
}

=head1 privilege

    获取当前登录用户权限信息函数，通过不同到sql，来获取权限，包括但不限于角色id，角色具体权限
    入口参数: 权限查询sql，自定义字段和表信息，也可以通过连接数据库自行实现
    出口参数: 获取到的权限信息hash
=cut

sub privilege {
    my ( $path, $sessionid ) = @_;
    $path ||= '';
    my $qxarr = from_json(ToolFunc::get_session( $sessionid ));
    my $sql = "select LJDM from usr_wfw.T_FX_LJ where LJ = '/$path'";
    my $path_dm;
    my $rtn = eval {
            $path_dm = DB::get_col_list( $sql )->[0];
    };
    if ( ! defined $rtn ) {
        $ToolFunc::syslog->error("路径表被锁，无法执行查询操作");
        return -2;
    }
    if (! defined $path_dm) {
        $ToolFunc::syslog->error("路径/$path 没有写入路径表(T_FX_LJ)进行管理，无法对该路径进行正常放行，进行始终拦截策略");
        return -1;
    }
    foreach my $ljid ( @$qxarr ) {
        if ( $ljid eq $path_dm ) {
            return 1;
        }
    }
    return 0;
}


=cut

=head1 config_hash

    入口参数: 本地配置文件路径
    出口参数: 本地配置文件的hash
=cut

sub config_hash {
    my ( $config_path ) = @_;
    if ( ! defined $config_path ) {
        $ToolFunc::syslog->error("config_hash配置函数找不到配置文件路径，无法读取配置文件");
        return undef;
    }
    return Config::Any::JSON->load( $config_path );
}

=head1 get_session

    从redis里面获取用户session数据
    走默认端口, 127.0.0.1
    传入sessionid
    返回hash,没有数据查到数据返回0,
    不是json格式进入redis就返回标量
=cut

sub get_session {
    my ( $sessionid ) = @_;
    my $redis;
    my $rtn = eval {
        $redis = Redis->new();
    };
    if ( ! defined $rtn ) {
        $ToolFunc::syslog->error( "redis连接失败! redis没有启动?" );
        return -1;
    }
    if ( ! $redis->exists( $sessionid ) ) {     # 不存在
        return 0;
    }
    else {
        my %res;
        $rtn = eval {
            %res = %{from_json($redis->get($sessionid))};
        };
        if ( ! defined $rtn ) {              #    不是json就返回标量
            return $redis->get($sessionid);
        }
        return %res;
    }
}

=head1 set_session_no_cover_pre

    设置session
    如果有键在 就不存入，如果没有就存入，不会延后缓存生命
    入参：用户名，session值，过期时间 默认一小时
    出参：成功1， 失败0
=cut

sub set_session_no_cover_pre {
    my ( $sessionid, $session_value, $time ) = @_;
    my $redis;
    $time //= 3600;
    my $rtn = eval {
        $redis = Redis->new();
    };
    if ( ! defined $rtn ) {
        $ToolFunc::syslog->error( "redis连接失败! redis没有启动?" );
        return 0;
    }
    $rtn = eval {
        if ( ! $redis->exists($sessionid) ) {              # 不存在则重新设置
            $redis->set( $sessionid=>$session_value );
            $redis->expire( $sessionid, $time );
        }
    };
    if ( ! defined $rtn ) {
        $ToolFunc::syslog->error( "redis服务异常，写入失败，请检查。" );
        return 0;
    }
    return 1;
}


=head1 set_session_cover_pre

    设置session
    存在则刷新，不存在则新建
    入参：用户名，session值，过期时间 默认一小时
    出参：成功1， 失败0
=cut

sub set_session_cover_pre {
    my ( $sessionid, $session_value, $time ) = @_;
    my $redis;
    $time //= 3600;
    my $rtn = eval {
        $redis = Redis->new();
    };
    if ( ! defined $rtn ) {
        $ToolFunc::syslog->error( "redis连接失败! redis没有启动?" );
        return 0;
    }
    $rtn = eval {
        $redis->set( $sessionid=>$session_value );
        $redis->expire( $sessionid, $time );
    };
    if ( ! defined $rtn ) {
        $ToolFunc::syslog->error( "redis服务异常，写入失败，请检查。" );
        return 0;
    }
    return 1;
}
=cut

=head1 lh

    2020-10-28 11:50
=cut

1;
__END__
