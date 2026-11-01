use lib 'test-nginx/lib';
use Test::Nginx::Socket::Lua;

repeat_each(2);
plan tests => repeat_each() * (3 * blocks());
our $HttpConfig = qq{ lua_package_path "lib/?.lua;;"; };
no_long_string();
run_tests();

__DATA__

=== TEST 1: binary request body in memory
--- http_config eval: $::HttpConfig
--- config
    location /t {
        client_body_buffer_size 16k;
        content_by_lua_block {
            local parser = require "resty.multipart.parser"
            ngx.req.read_body()
            local body = assert(ngx.req.get_body_data())
            assert(ngx.req.get_body_file() == nil)
            local p = assert(parser.new(body, ngx.var.http_content_type))
            local data, name, mime, filename = p:parse_part()
            assert(data == "\255\216\0\128binary\r\n", tostring(data))
            assert(name == "file" and mime == "application/octet-stream")
            assert(filename == "image.bin")
            local headers = p:get_part_headers()
            assert(#headers == 2 and headers[2].name == "content-type")
            assert(headers[2].value == "application/octet-stream")
            local next_part, err = p:parse_part()
            assert(next_part == nil and err == nil)
            assert(p:get_part_headers() == nil)
            ngx.say("ok")
        }
    }
--- more_headers
Content-Type: multipart/form-data; boundary=B
--- request eval
"POST /t\n--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n\xff\xd8\x00\x80binary\r\n\r\n--B--\r\n"
--- response_body
ok
--- no_error_log
[error]

=== TEST 2: file-backed request body requires the caller to supply a string
--- http_config eval: $::HttpConfig
--- config
    location /t {
        client_body_in_file_only clean;
        content_by_lua_block {
            local parser = require "resty.multipart.parser"
            ngx.req.read_body()
            assert(ngx.req.get_body_data() == nil)
            local p, err = parser.new(ngx.req.get_body_data(), ngx.var.http_content_type)
            assert(p == nil and err == "request body must be a string")

            -- Read the small fixture explicitly; the parser does no file I/O.
            local file = assert(io.open(assert(ngx.req.get_body_file()), "rb"))
            local body = assert(file:read("*a"))
            assert(file:close())
            p = assert(parser.new(body, ngx.var.http_content_type))
            local data, name, mime, filename = p:parse_part()
            assert(data == "\255\216\0\128binary\r\n", tostring(data))
            assert(name == "file" and mime == "application/octet-stream")
            assert(filename == "image.bin")
            local headers = p:get_part_headers()
            assert(#headers == 2 and headers[2].name == "content-type")
            assert(headers[2].value == "application/octet-stream")
            local next_part
            next_part, err = p:parse_part()
            assert(next_part == nil and err == nil)
            assert(p:get_part_headers() == nil)
            ngx.say("ok")
        }
    }
--- more_headers
Content-Type: multipart/form-data; boundary=B
--- request eval
"POST /t\n--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n\xff\xd8\x00\x80binary\r\n\r\n--B--\r\n"
--- response_body
ok
--- no_error_log
[error]
