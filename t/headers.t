use lib 'test-nginx/lib';
use Test::Nginx::Socket::Lua;

repeat_each(2);
plan tests => repeat_each() * (3 * blocks());
our $HttpConfig = qq{ lua_package_path "lib/?.lua;t/lib/?.lua;;"; };
no_long_string();
run_tests();

__DATA__

=== TEST 1: complete form-data metadata and unchanged return values
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").form_data()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 2: Content-Range headers on unnamed reordered byte ranges
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").byteranges()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 3: duplicate extension headers retain their order
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").duplicate_headers()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 4: folded headers, lowercase names, parameters and empty values
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").folded_headers()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 5: a valid headerless part has an empty header list
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").empty_headers()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 6: empty part values and a message without parts
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").empty_body()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 7: failed subsequent parts clear current headers and preserve snapshots
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").later_error()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 8: rejected headers and truncated bodies never expose partial metadata
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").invalid_parts()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 9: existing header-size and part-count limits remain effective
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").limits()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 10: returned lists are independent of later parsing and other parsers
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("test_multipart_headers").independent_results()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
