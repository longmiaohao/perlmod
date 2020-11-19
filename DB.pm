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
our $log_flag = 1;			# 日志开关 默认不开启
our $err_msg = undef;
our $dbh = undef;
our $file_logger = undef;	# 日志记录
our $error_logger = undef;	# 错误日志记录
our $log_msg = "";			# 自定义信息


=head1 auth

	认证函数，通过传入预处理sql，和用户名密码进行认证，防止sql注入
    sql类似
        'select count(*) from user where username=? and password=?'
    格式
    然后带入值传入username和password具体到值即可
    认证成功返回1 失败返回0
=cut
sub auth {
	my ( $sql, @params) = @_;
	my $sth = "";
	my $rtn = eval {
		$sth = $DB::dbh->prepare( "select count(*) count from (".$sql.") t" ) or $DB::err_msg = $DBI::errstr;
		$sth->execute( @params ) or $DB::err_msg = $DBI::errstr;
	};
	if (! defined $rtn ) {
		if ( $DB::log_flag eq 1 ) {
			$error_logger->error("$DB::err_msg");
		}
		return -1;
	}
	else {
		if ( $DB::log_flag eq 1 ) {
			$file_logger->info($sql . "  " . join(',', @params));
		}
		my @data = $sth->fetchall_arrayref();
		$sth->finish;
		if ( @data[0]->[0]->[0] == 1 ) {
			return 1;
		}
	}
	return 0;
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

sub connect_oracle {

	my ( $host, $port, $database, $username, $password , $refconfig ) = @_;
	if ( $DB::log_flag eq 1 ) {
		$DB::log_msg{ log_msg } = $$refconfig{ log_msg };
		$$refconfig{ info_log_path } //= "/tmp/www/my_sql_info.log";
		$$refconfig{ err_log_path } //= "/tmp/www/my_sql_error.log";
		$DB::file_logger = Log::Mini->new( file => $$refconfig{ info_log_path }, level => 'info', synced => 1);
		$DB::error_logger = Log::Mini->new( file => $$refconfig{ err_log_path } , synced => 1);
	}
	if ( $DB::dbh != undef ){		# 单例模式
		return 1;
	}

	my $driver = 'Oracle';           # 接口类型 默认为 localhost
	# 驱动程序对象的句柄
	my $dsn = "DBI:$driver:$host:$port/$database";
   	# 连接数据库
	eval {
		$dbh = DBI->connect( $dsn, $username, $password ) or die $err_msg="$DBI::errstr";
		$dbh->{LongReadLen} = 5242880;
		$dbh->{LongTruncOk} = 0;
	};
	if ( $@ ) {
		eval {
			if( $DB::log_flag eq 1 ) {
				$DB::error_logger->error("$DB::err_msg $log_msg");
			}
		};
		return 0;
	}
	return 1;
}

=head1 connect_sqlserver

	连接sqlserver数据库
=cut

sub connect_sqlserver {

	my ( $host, $port, $database, $username, $password , $refconfig ) = @_;
	if ( $DB::log_flag eq 1 ) {
		$DB::log_msg{ log_msg } = $$refconfig{ log_msg };
		$$refconfig{ info_log_path } //= "/tmp/www/my_sql_info.log";
		$$refconfig{ err_log_path } //= "/tmp/www/my_sql_error.log";
		$DB::file_logger = Log::Mini->new(file => $$refconfig{ info_log_path }, level => 'info', synced => 1);
		$DB::error_logger = Log::Mini->new(file => $$refconfig{ err_log_path }, synced => 1);
	}
	if ( $DB::dbh != undef ) {		# 单例模式
		return 1;
	}

	# 驱动程序对象的句柄
	my $dsn = "Driver={ODBC Driver 17 for SQL Server};server=$host;port=$port;database=$database;charset=gbk";
	# my $dsn = "database=$database;charset=utf-8";
   	# 连接数据库,{ RaiseError => 1, AutoCommit => 1} ;
	$dbh = DBI->connect( "DBI:ODBC:$dsn", $username, $password, { RaiseError => 1, AutoCommit => 1}) or $err_msg="$DBI::errstr";
	# $dbh->{LongReadLen} = 5242880;
	# $dbh->{LongTruncOk} = 0;
	if ( !ref($dbh) =~ m/DBI::db/ ) {
		if ( $DB::log_flag eq 1 ) {
			$DB::error_logger->error("$DB::err_msg $log_msg");
		}
		return 0;
	}
	return 1;
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
		if ( $DB::log_flag eq 1 ) {
			$DB::error_logger->error("$DB::err_msg $log_msg");
		}
		return 0;
	} else {
		$DB::err_msg = "DB not connected";
		return 0;
	}
}

=cut

=head1 执行操作类语句

	传入参数
	增删改类型sql语句, 不支持执行查询操作
	操作成功返回true
=cut
sub execute {
	if ( ! defined $DB::dbh){		# 句柄为空 数据库为连接
		$DB::err_msg = "DB not connected";
		warn($DB::err_msg);
		return 0;
	}
	my ( $sql_str ) = @_;
	if( $sql_str =~ /\s*select\s*/gi ) {
		$DB::err_msg = "execute only for not queries";
		return 0;
	}
	my $sth;
	my $rtn = eval {
		$sth = $DB::dbh->prepare( $sql_str ) or $DB::err_msg = $DBI::errstr; 	# sql预处理
		$sth->execute() or $DB::err_msg = "$sql_str  ".$DBI::errstr;
		$sth->finish;
	};
	if (! defined $rtn){
		if( $DB::log_flag eq 1 ) {
			$DB::error_logger->error("$DB::err_msg $log_msg");
		}
		return -1;
	} else {
		if( $DB::log_flag eq 1 ) {
			$DB::file_logger->info("$sql_str $log_msg");
		}
		return $sth->rows;
	}
}


=cut

=head1 执行操作类语句

	传入参数
	增删改类型sql语句, 不支持执行查询操作 预处理绑定防止sql注入
	操作成功返回true
=cut
sub api_execute {
	if ( ! defined $DB::dbh ) {		# 句柄为空 数据库为连接
		$DB::err_msg = "DB not connected";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str, $params ) = @_;
	if( $sql_str =~ /\s*select\s*/gi ) {
		$DB::err_msg = "execute only for not queries";
		return 0;
	}
	my $sth;
	my $rtn = eval {
		$sth = $DB::dbh->prepare( $sql_str ) or $DB::err_msg = $DBI::errstr; 	# sql预处理
		$sth->execute(split('&&@@', $params)) or $DB::err_msg = "$sql_str  ".$DBI::errstr;
		$sth->finish;
	};
	if (! defined $rtn){
		if( $DB::log_flag eq 1 ) {
			$DB::error_logger->error("$DB::err_msg $log_msg");
		}
		return -1;
	} else {
		if( $DB::log_flag eq 1 ) {
			$DB::file_logger->info("$sql_str $log_msg");
		}
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
		$DB::err_msg = "DB not connected, excute SQL failed";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str ) = @_;
	if ( $sql_str =~ m/\s*update\s*|\s*delete\s*|\s*insert\s*/ig ){
		$DB::err_msg = "get_json func only queries";
		return 0;
	}
	my $sth;
	my $data = "";
	my $rtn = eval{
					if ( $sql_str =~ m/\s+ROWNUM/ig ){
						$sth = $DB::dbh->prepare( $sql_str ); 	# sql预处理, 自动处理ROWNUM
					}
					else {
						$sth = $DB::dbh->prepare("SELECT ROWNUM , t.* from (".$sql_str.") t" ) or $DB::err_msg = $DBI::errstr;
					}
					$sth->execute() or $DB::err_msg = $DBI::errstr;
					my $rt = eval {
						$data = $sth->fetchall_hashref("ROWNUM"); # hash键 该值排除hash冲突
					};
					if ( ! defined $rt ) {
						$DB::err_msg = "查询列不包括ROWNUM, HASH返回失败";
						if( $DB::log_flag eq 1 ) {
							$DB::error_logger->error("$DB::err_msg $log_msg");
						}
					}
				};
	if(! defined $rtn){
		if( $DB::log_flag eq 1 ) {
			$DB::error_logger->error($DB::err_msg);
		}
		return 0;
	};
	if ( $DB::log_flag eq 1 ) {
		$DB::file_logger->info($sql_str);
	}
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

=cut

=head1 获取数组

	获取行数组
=cut

sub get_row_list {
	if ( ! defined $DB::dbh ){		# 句柄为空 数据库为连接
		$DB::err_msg = "DB not connected";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str ) = @_;
	my $sth = "";
	my $rtn = eval{
		$sth = $DB::dbh->prepare( $sql_str ) or $DB::err_msg = $DBI::errstr; 	# sql预处理
		$sth->execute() or $DB::err_msg= $DBI::errstr;
	};
	if ( ! defined $rtn){
		if ( $DB::log_flag eq 1 ) {
			$DB::error_logger->error("$DB::err_msg $log_msg");
		}
		return 0;
	} else {
		my $data = $sth->fetchall_arrayref();
		$sth->finish;
		if ( $DB::log_flag eq 1 ) {
			$DB::file_logger->info("$sql_str $log_msg");
		}
		return $data;
	}
}


=head1 获取列数组

	获取列数组
=cut

sub get_col_list {
	if ( ! defined $DB::dbh ){		# 句柄为空 数据库为连接
		$DB::err_msg = "DB not connected";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str ) = @_;
	my $sth = "";
	my $rtn = eval{
		$sth = $DB::dbh->prepare( $sql_str ) or $DB::err_msg = $DBI::errstr; 	# sql预处理
		$sth->execute() or $DB::err_msg= $DBI::errstr;
	};
	if ( ! defined $rtn){
		if ( $DB::log_flag eq 1 ) {
			$DB::error_logger->error("$DB::err_msg $log_msg");
		}
		return 0;
	} else {
		my $data = $sth->fetchall_arrayref();
		$sth->finish;
		if ( $DB::log_flag eq 1 ) {
			$DB::file_logger->info("$sql_str $log_msg");
		}
		my @result;
		foreach my $value ( @$data ) {
			push( @result, $value->[0]);
		}
		return \@result;
	}
}


=head1 mssql_api_get_json

	防SQL注入版sqlserver get_json
	第一个参数：预处理SQL
	第二个参数：参数
=cut
sub mssql_api_get_json {
	if ( ! defined $DB::dbh ){		# 句柄为空 数据库为连接
		$DB::err_msg = "DB not connected, excute SQL failed";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str, $params ) = @_;
	if ( $sql_str =~ m/\s*update\s*|\s*delete\s*|\s*insert\s*/ig ){
		$DB::err_msg = "get_json func only queries";
		return 0;
	}
	my $sth;
	my $data = "";
	my $rtn = eval{
					if ( $sql_str =~ m/\s+ROWNUM/ig ){
						$sth = $DB::dbh->prepare( $sql_str ) or $DB::err_msg = $DBI::errstr; 	# sql预处理, 自动处理ROWNUM
					}
					else {
						$sth = $DB::dbh->prepare("SELECT NEWID() as ROWNUM , t.* from (".$sql_str.") t" ) or $DB::err_msg = $DBI::errstr;
					}
					$sth->execute( split( '&&@@', $params ) ) or $DB::err_msg = $DBI::errstr;
					my $rt = eval {
						$data = $sth->fetchall_hashref("ROWNUM"); # hash键 该值排除hash冲突
					};
					if ( ! defined $rt ) {
						$DB::err_msg = "查询列不包括ROWNUM, HASH返回失败";
						if ( $DB::log_flag eq 1 ) {
							$DB::error_logger->error(" $DB::err_msg $sql_str $log_msg ");
						}
					}
				};
	if(! defined $rtn ){
		if ( $DB::log_flag eq 1 ) {
			$DB::error_logger->error($DB::err_msg . "  $params");
		}
		return 0;
	};
	if ( $DB::log_flag eq 1 ) {
		$DB::file_logger->info($sql_str . " $params");
	}
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

=head1 oracle_api_get_json

	防SQL注入版oracle get_json
	第一个参数：预处理SQL
	第二个参数：参数
=cut
sub oracle_api_get_json {
	if ( ! defined $DB::dbh ){		# 句柄为空 数据库为连接
		$DB::err_msg = "DB not connected, excute SQL failed";
		warn( $DB::err_msg );
		return 0;
	}
	my ( $sql_str, $params ) = @_;
	if ( $sql_str =~ m/\s*update\s*|\s*delete\s*|\s*insert\s*/ig ){
		$DB::err_msg = "get_json func only queries";
		return 0;
	}
	my $sth;
	my $data = "";
	my $rtn = eval{
					if ( $sql_str =~ m/\s+ROWNUM/ig ){
						$sth = $DB::dbh->prepare( $sql_str ); 	# sql预处理, 自动处理ROWNUM
					}
					else {
						$sth = $DB::dbh->prepare("SELECT ROWNUM , t.* from (".$sql_str.") t" ) or $DB::err_msg = $DBI::errstr;
					}
					$sth->execute( split( '&&@@', $params ) ) or $DB::err_msg = $DBI::errstr;
					my $rt = eval {
						$data = $sth->fetchall_hashref("ROWNUM"); # hash键 该值排除hash冲突
					};
					if ( ! defined $rt ) {
						$DB::err_msg = "查询列不包括ROWNUM, HASH返回失败";
						if ( $DB::log_flag eq 1 ) {
							$DB::error_logger->error("$DB::err_msg $sql_str $log_msg ");
						}
					}
				};
	if(! defined $rtn ){
		if ( $DB::log_flag eq 1 ) {
			$DB::error_logger->error($DB::err_msg . "  $params");
		}
		return 0;
	};
	if ( $DB::log_flag eq 1 ) {
		$DB::file_logger->info($sql_str . " $params");
	}
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
1;
