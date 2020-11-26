package ToolFunc;
use strict;
use warnings FATAL => 'all';
use MY::DB;
use Config::Any::JSON;
use utf8;
use JSON;
use Redis;
use Data::Dumper;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseExcel::FmtUnicode;
use Spreadsheet::XLSX;
use POSIX qw(strftime ceil);
our @EXPORT = qw/privilege config_hash set_session_cover_pre set_session_no_cover_pre/;

our $syslog = Log::Mini->new( file => 'syserror.log', synced=>1 );

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
    my $path_dm = DB::get_col_list( $sql )->[0];
    if (! defined $path_dm) {
        $syslog->error("路径/$path 没有写入路径表(T_FX_LJ)进行管理，无法对该路径进行正常放行，进行始终拦截策略");
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

=head2 upload_func($c, $db_name, $fields)

    excel 导入方法
    $c :
    $db_name : 用户名及表名  如: usr_wfw.T_FX_TEST
    $fields : array  写入的顺序字段 如:['XH','XM']
    调用示例
    my %res = ToolFunc::upload_func($c,'usr_wfw.T_FX_TEST',qw/XH XM XB KSH MZ NJ ZXXY ZXZY/);
=cut

sub upload_func {
    my ( $c, $db_name, @fields ) = @_;
    my %arr;
    my $upload = $c->req->upload('file');
    my $fileDate = strftime "%Y-%m-%d", localtime;  # 当天目录
    my $filename = $upload->filename;

    # 创建存储目录
    my $path = $ENV{ PWD }."/root/static/uploads/fx_".$fileDate;
    if ( ! -e $path ) {
        mkdir( $path ) or die "无法创建 $path 目录, $!";
    }

    # 获取后缀名
    my @suffix = split( '\.', $filename );
    my $fileNameCount = @suffix;
    my $fileNameSuffix = $suffix[$fileNameCount-1];

    $arr{'code'} = 0;

    # 校验文件类型
    if ( $fileNameSuffix ne 'xls' and $fileNameSuffix ne 'xlsx' ) {
        $arr{'msg'} = "不允许的文件类型!";
        return %arr;
    }

    my $target = $path.'/'.$suffix[0].'-'.time().'.'.$fileNameSuffix; # 定义文件上传目录并重命名
    # 文件上传
    unless ( $upload->link_to($target) || $upload->copy_to($target) ) {
        $arr{'msg'} = "$filename 文件写入失败 !";
        $arr{'path'} = $target;
        return %arr;
    }

    my @list; # 存储为列表
    my $index = 0; # 数组索引

    if ( $fileNameSuffix eq 'xls' ){

        my $parser   = Spreadsheet::ParseExcel->new();
        my $workbook = $parser->parse($target);

        if ( !defined $workbook ) {
            $arr{'msg'} = $parser->error();
            $c->res->body(to_json(\%arr, {allow_nonref=>1,utf8=>0}));
            return 0;
        }

        foreach my $worksheet ( $workbook->worksheets() ) {

            my ( $row_min, $row_max ) = $worksheet->row_range();
            my ( $col_min, $col_max ) = $worksheet->col_range();

            $row_min = 1; # 从第2行开始获取数据

            foreach my $row ( $row_min .. $row_max ) {

                foreach my $col ( $col_min .. $col_max ) {
                    my $cell = $worksheet->get_cell( $row, $col );
                    next unless $cell;
                    my $tmp = $cell->value();
                    $tmp =~ s/^\s+|\s+$//g;  # 去除左右空格
                    $list[$index]->{$col} = $tmp;
                }
                $index++;
            }
        }
    }
    elsif ( $fileNameSuffix eq 'xlsx' ) {
        # XLSX 格式文档
        my $excel = Spreadsheet::XLSX -> new( $target );
        foreach my $sheet (@{$excel -> {Worksheet}}) {

            # 读取 sheet 名称
            # printf("Sheet: %s\n", $sheet->{Name});

            $sheet -> {MaxRow} ||= $sheet -> {MinRow};

            my $minRow = 1; # $sheet -> {MinRow}  从第2行获取数据 第一行为字段名

            foreach my $row ($minRow .. $sheet -> {MaxRow}) {

                $sheet -> {MaxCol} ||= $sheet -> {MinCol};

                foreach my $col ($sheet -> {MinCol} ..  $sheet -> {MaxCol}) {

                    my $cell = $sheet -> {Cells} [$row] [$col];

                    if ( $cell ) {
                        my $tmp = $cell -> {Val};
                        $tmp =~ s/^\s+|\s+$//g;  # 去除左右空格
                        $list[$index]->{$col} = $tmp;
                    }
                }
                $index++;
            }
        }
    }

    my $fieldsCount = @fields; # 字段长度
    my $listCount = @list;  # 数据长度
    my $count = 0;  # 导入总条数
    foreach my $val ( 0 .. ($listCount-1) ) {
        my $info = $list[$val];
        # 组装 SQL
        my @insertValues = ();
        my @insertFields = ();
        foreach my $i (0 .. ($fieldsCount-1) ) {
            # 处理输入值
            my $data = $info->{$i};
            $data =~s/\s+//g; # 去除空格
            # 推入数组
            push(@insertValues,"\'$data\'");
            push(@insertFields,$fields[$i]);
        }
        # 拼接字符串
        my $valueStr = join(',',@insertValues);
        my $fieldStr = join(',',@insertFields);
        my $sql = "insert into ".$db_name."($fieldStr) values($valueStr)";
        my $r = DB::execute($sql);
        $count += $r;
    }
    $arr{'code'} = 1;
    $arr{'msg'} = 'success';
    $arr{'path'} = $target;
    $arr{'count'} = $count;

    return %arr;
}

=cut

=head1 lh

    2020-10-28 11:50
=cut

1;
__END__
