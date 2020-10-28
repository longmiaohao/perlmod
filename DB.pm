package DB;

use strict;
use DBI;
use JSON;
use Log::Mini;
use utf8;
use Data::Dumper;

BEGIN {
	binmode(STDIN, ":utf8");
	binmode(STDOUT, ":utf8");
	# 解决中文乱码问题
	$ENV{NLS_LANG} = "SIMPLIFIED CHINESE_CHINA.AL32UTF8";
	our @EXPORT = qw/connect_oracle execute get_json get_list close/;
}

=head1 连接Oracle数据库

	传入参数:
	数据库IP， 端口号， 数据库， 用户名， 密码
	hash参数引用 \%hash
	{
		"log_msg": "自定义,将显示在每条日志的末尾",
		"info_log_path"： "自定义正常日志文件位置",
		"err_log_path": "自定义错误日志文件位置"
	}
=cut

our $err_msg = undef;
our $dbh = undef;
our $file_logger = undef;	# 日志记录
our $error_logger = undef;	# 错误日志记录
our $log_msg = "";			# 自定义信息
sub connect_oracle {

	my ( $host, $port, $database, $username, $password , $refconfig ) = @_;
	$DB::log_msg{ log_msg } = $$refconfig{ log_msg };
	$$refconfig{ info_log_path } //= "my_sql_info.log";
	$$refconfig{ err_log_path } //= "my_sql_error.log";
	$DB::file_logger = Log::Mini->new( file => $$refconfig{ info_log_path }, level => 'info', synced => 1);
	$DB::error_logger = Log::Mini->new( file => $$refconfig{ err_log_path } , synced => 1);

	if ( $DB::dbh != undef ){		# 单例模式
		$DB::err_msg = "数据库已经连接过";
		return 1;
	}

	my $driver = 'Oracle';           # 接口类型 默认为 localhost
	# 驱动程序对象的句柄
	my $dsn = "DBI:$driver:$host:$port/$database";
   	# 连接数据库
	$dbh = DBI->connect( $dsn, $username, $password ) or $err_msg="$DBI::errstr";
	$dbh->{LongReadLen} = 5242880;
	$dbh->{LongTruncOk} = 0;
	if ( !ref($dbh) =~ m/DBI::db/ ) {
		$DB::error_logger->error("$DB::err_msg $log_msg");
		return 0;
	}
	return 1;
}

=head1 执行操作类语句

	传入参数
	增删改类型sql语句, 不支持执行查询操作
	操作成功返回true
=cut
sub execute {
	if ( ! defined $DB::dbh){		# 句柄为空 数据库为连接
		$DB::err_msg = "数据库未连接\n";
		warn($DB::err_msg);
		return 0;
	}
	my ( $sql_str ) = @_;
	if( $sql_str =~ /\s*select\s*/gi ) {
		$DB::err_msg = "execute 函数只能传入非查询类语句";
		return 0;
	}
	my $sth;
	my $rtn = eval {
		$sth = $DB::dbh->prepare( $sql_str ); 	# sql预处理
		$sth->execute() or $DB::err_msg = "$sql_str  ".$DBI::errstr;
		$sth->finish;
	};
	if (! defined $rtn){
		$DB::error_logger->error("$DB::err_msg $log_msg");
		return -1;
	} else {
		$DB::file_logger->info("$sql_str $log_msg");
		return $sth->rows;
	}
}

=head1 执行json查询

	传入参数:
	查询类sql，不支持增删改, 所有传入sql均需要带rownum
	查询成功返回json数据
	Dumper(from_json($json))
=cut
sub get_json {
	if ( ! defined $DB::dbh ){		# 句柄为空 数据库为连接
		$DB::err_msg = "数据库未连接, 执行SQL操作失败\n";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str ) = @_;
	if ( $sql_str =~ m/\s*update\s*|\s*delete\s*|\s*insert\s*/ig ){
		$DB::err_msg = "get_json函数只能传入查询类语句";
		return 0;
	}
	my $sth;
	my $data = "";
	my $rtn = eval{
					$sth = $DB::dbh->prepare( $sql_str ); 	# sql预处理
					$sth->execute()  or $DB::err_msg = $DBI::errstr;
					my $rt = eval {
						$data = $sth->fetchall_hashref("ROWNUM"); # hash键 该值排除hash冲突
					};
					if ( ! defined $rt ) {
						$DB::err_msg = "查询列不包括ROWNUM, HASH返回失败";
						$DB::error_logger->error("$DB::err_msg $log_msg");
				}
	};
	if(! defined $rtn){
		$DB::error_logger->error($DB::err_msg);
		return 0;
	};
	$DB::file_logger->info($sql_str);
	if ( $sth->rows ) {	# 有数据返回Json格式数据[{},{}]
		my $json = '[';		# 构造json字符串
		foreach my $key ( sort keys %{ $data } ) {
			$json .= to_json( %{ $data }{ $key }, { allow_nonref=>1 } ).',';
		}
		$sth->finish();
		$json =~ s/,$//;
		$json .= ']';
		$json =~ s/null/""/g;
		return $json;
	}
	else {	# 没有查到数据返回空数组
		$sth->finish;
		return "[]";
	}
}

=head1 获取数组

=cut

sub get_list {
	if ( ! defined $DB::dbh ){		# 句柄为空 数据库为连接
		$DB::err_msg = "数据库未连接\n";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str ) = @_;
	my $sth = "";
	my $rtn = eval{
		$sth = $DB::dbh->prepare( $sql_str ); 	# sql预处理
		$sth->execute() or $DB::err_msg= $DBI::errstr;
	};
	if ( ! defined $rtn){
		$DB::error_logger->error("$DB::err_msg $log_msg");
		return 0;
	} else {
		my @data = $sth->fetchall_arrayref();
		$sth->finish;
		$DB::file_logger->info("$sql_str $log_msg");
		return @data;
	}
}

=head1 关闭连接

	关闭数据库连接
=cut
sub close {
	if ( ref($DB::dbh) =~ m/DBI::db/ ){
		if ( $DB::dbh->disconnect() ){
			$DB::dbh = undef;
			return 1;
		}
		$DB::err_msg = $DBI::errstr;
		$DB::error_logger->error("$DB::err_msg $log_msg");
		return 0;
	} else {
		$DB::err_msg = "数据库未连接\n";
		warn( $DB::err_msg );
		return 0;
	}
}
1;
