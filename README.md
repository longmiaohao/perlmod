## Perl开发工具包

### db.pm

| 函数           | 入参                                                         | 出参                          | 功能描述             |
| -------------- | ------------------------------------------------------------ | ----------------------------- | -------------------- |
| connect_oracle | 用户名 string，密码 string，ip string，port string，db string，config hash引用 | 连接成功返回1                 | 连接oracle数据库     |
| get_json       | sql字符串 string                                             | 查询结果的json字符串          | 查询返回json数据     |
| get_list       | sql字符串 string                                             | 返回查询结果的数组            | 查询返回数组数据     |
| execute        | sql字符串 string                                             | 成功返回生效条数， 错误返回-1 | 执行非查询操作语句   |
| close          | 无                                                           | 成功返回1，错误返回0          | 关闭操作句柄和db连接 |

### Log::Mini

| 函数                    | 入参                              | 出参         | 功能描述             |
| ----------------------- | --------------------------------- | ------------ | -------------------- |
| Log::Mini->new();       | file => 文件名, level => 日志级别 | 返回文件句柄 | 打开日志文件准备记录 |
| $file_logger->error()   | 日志数据(自带了时间)              | 无           | 记录error级别日志    |
| $file_logger->warning() | 日志数据(自带了时间)              | 无           | 记录警告级别日志     |
| $file_logger->info()    | 日志数据(自带了时间)              | 无           | 记录信息级日志       |
| $file_logger->debug()   | 日志数据(自带了时间)              | 无           | 记录调试日志         |

### ToolFunc

| 函数        | 入参                                                      | 出参                                 | 功能描述                                                     |
| ----------- | --------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------ |
| privilege   | sql string                                                | hash                                 | 传入sql获取用户权限，也可以自行连接数据库获取，对数据库操作的简单封装 |
| config_hash | path string                                               | hash                                 | 传入配置文件路径，获取到配置文件信息                         |
| get_session | sessionid string                                          | 成功返回1 错误返回-1 没有获取到返回0 | 从redis获取用户的session，                                   |
| set_session | session_id string session_value string expire_time scalar | 成功返回1 错误返回-1 没有获取到返回0 | 设置session，如果已经有session的将会不重新设置，默认有效期为一小时 |
|             |                                                           |                                      |                                                              |

