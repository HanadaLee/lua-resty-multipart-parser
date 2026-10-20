use lib 'test-nginx/lib';
use Test::Nginx::Socket::Lua;
repeat_each(2);
plan tests => repeat_each() * (3 * blocks());
our $HttpConfig = qq{ lua_package_path "lib/?.lua;t/lib/?.lua;;"; };
no_long_string();
run_tests();
__DATA__

=== TEST 1: quoted parameters cannot introduce other parameters
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body('Content-Disposition: form-data; name="x; filename=evil"; filename="good.txt"'), ct))
            local data, name, mime, filename = p:parse_part()
            assert(data == "abc" and name == "x; filename=evil" and filename == "good.txt")
            p = assert(parser.new(body('Content-Disposition: form-data; filename="x; name=spoof"; name="actual"'), ct))
            data, name, mime, filename = p:parse_part()
            assert(name == "actual" and filename == "x; name=spoof")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 2: escaped quotes and backslashes
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body('Content-Disposition: form-data; name="file"; filename="a\\"b\\\\c.txt"'), ct))
            local _, _, _, filename = p:parse_part()
            assert(filename == 'a"b\\c.txt', filename)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 3: complete unquoted tokens and empty quoted values
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body("Content-Disposition: form-data; name=a.b+z; filename=a.txt"), ct))
            local _, name, _, filename = p:parse_part()
            assert(name == "a.b+z" and filename == "a.txt")
            p = assert(parser.new(body('Content-Disposition: form-data; name=""; filename=""', ""), ct))
            local data
            data, name, _, filename = p:parse_part()
            assert(data == "" and name == "" and filename == "")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 4: duplicate filename and name parameters are rejected
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(body(header .. '; FILENAME="bad.php"'), ct, "duplicate header parameter: filename")
            rejected(body(header .. '; name="other"'), ct, "duplicate header parameter: name")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 5: duplicate boundary and Content-Type headers are rejected
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(body(header), ct .. "; BOUNDARY=C", "duplicate header parameter: boundary")
            rejected(body(header), {ct, ct}, "expected one Content-Type header")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 6: duplicate part metadata is rejected
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(body(header .. "\r\n" .. header), ct, "duplicate part header: content-disposition")
            rejected(body(header .. "\r\nContent-Type: text/plain\r\ncontent-type: image/png"), ct, "duplicate part header: content-type")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 7: normal EOF is stable and releases the input
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body(header), ct))
            assert(p:parse_part() == "abc")
            assert(p.body == nil)
            for i = 1, 3 do
                local value, err = p:parse_part()
                assert(value == nil and err == nil)
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 8: epilogue is never parsed as another part
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local value = body(header) .. 'Content-Disposition: form-data; name="ghost"\r\n\r\nHIDDEN\r\n--B--\r\n'
            local p = assert(parser.new(value, ct))
            assert(p:parse_part() == "abc")
            local data, err = p:parse_part()
            assert(data == nil and err == nil)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 9: missing closing boundary reports truncation
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected('--B\r\n' .. header .. '\r\n\r\nabc', ct, "missing closing boundary")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 10: boundary suffix is validated
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(body(header, "abc\r\n--BXYZ\r\ndef"), ct, "invalid boundary delimiter")
            rejected(body(header):gsub("B%-%-\r\n$", "B--garbage\r\n"), ct, "invalid boundary delimiter")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 11: first boundary must start a line
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local skipped = assert(parser.new("prefix" .. body(header), ct))
            assert(skipped:parse_part() == nil)
            local p = assert(parser.new("preamble--B\r\nignored\r\n" .. body(header), ct))
            assert(p:parse_part() == "abc")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 12: closing boundary without final CRLF and transport padding
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local value = body(header):gsub("^%-%-B\r\n", "--B \t\r\n"):gsub("B%-%-\r\n$", "B-- \t")
            local p = assert(parser.new(value, ct))
            assert(p:parse_part() == "abc")
            assert(p:parse_part() == nil)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 13: binary data and non-delimiter boundary strings survive
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local value = "\255\216\0\128abc--B\r\n--other\r\ndef"
            local p = assert(parser.new(body(header, value), ct))
            assert(p:parse_part() == value)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 14: empty multipart body
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new("--B--", ct))
            local data, err = p:parse_part()
            assert(data == nil and err == nil and p.body == nil)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 15: multiple parts with the same field name preserve order
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local value = '--B\r\n' .. header .. '\r\n\r\none\r\n--B\r\n' .. header .. '\r\n\r\ntwo\r\n--B--\r\n'
            local p = assert(parser.new(value, ct))
            local data, name = p:parse_part()
            assert(data == "one" and name == "file")
            data, name = p:parse_part()
            assert(data == "two" and name == "file")
            assert(p:parse_part() == nil)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 16: invalid body types fail in the constructor
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(nil, ct, "request body must be a string")
            rejected({}, ct, "request body must be a string")
            rejected(42, ct, "request body must be a string")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 17: missing or non-multipart Content-Type is rejected
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(body(header), nil, "no Content-Type")
            rejected(body(header), {}, "expected one Content-Type")
            rejected(body(header), "text/plain; boundary=B", "not multipart")
            rejected(body(header), "multipart/form-data", "no boundary")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 18: boundary grammar and length are checked
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            for _, boundary in ipairs({"", "x ", "x@y", "x\0y", string.rep("x", 71)}) do
                rejected(body(header), 'multipart/form-data; boundary="' .. boundary .. '"', boundary:find("\0", 1, true) and "control character" or "invalid multipart boundary")
            end
            local boundary = string.rep("x", 70)
            local p = assert(parser.new(body(header, "abc", boundary), "multipart/form-data; boundary=" .. boundary))
            assert(p:parse_part() == "abc")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 19: malformed parameters fail instead of being partially matched
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            for _, suffix in ipairs({'; filename="broken', '; filename="a"junk', '; filename=', '; filename', ';'}) do
                rejected(body('Content-Disposition: form-data; name="file"' .. suffix), ct, "parameter")
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 20: folded MIME headers and case-insensitive names
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body('cOnTeNt-DiSpOsItIoN: FoRm-DaTa;\r\n\tNAME="file";\r\n filename="good.txt"\r\nContent-Type: text/plain; charset=UTF-8'), {ct}))
            local data, name, mime, filename = p:parse_part()
            assert(data == "abc" and name == "file" and mime == "text/plain" and filename == "good.txt")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 21: invalid header syntax and control characters
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(body("\tcontinuation"), ct, "continuation without a field")
            rejected(body("Content-Disposition : form-data; name=x"), ct, "invalid part header")
            rejected(body(header .. "\0"), ct, "invalid control character")
            rejected(body(header .. "\nX-Test: yes"), ct, "invalid control character")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 22: form-data requires a name and correct disposition
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected(body("X-Test: yes"), ct, "missing form-data name")
            rejected(body('Content-Disposition: attachment; name="file"'), ct, "expected form-data")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 23: other multipart types may omit form-data metadata
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new("--B\r\n\r\nabc\r\n--B--", "multipart/mixed; boundary=B"))
            local data, name, mime, filename = p:parse_part()
            assert(data == "abc" and name == nil and mime == nil and filename == nil)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 24: header size limit includes exact-limit headers
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body(header), ct, {max_header_size = #header}))
            assert(p:parse_part() == "abc")
            rejected(body(header .. "x"), ct, "part headers too large", {max_header_size = #header})
            rejected(body(header), ct .. '; charset="' .. string.rep("a", 100) .. '"', "Content-Type header too large", {max_header_size = 80})

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 25: part count limit is enforced without rejecting the exact limit
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local one = '--B\r\n' .. header .. '\r\n\r\nabc\r\n'
            local p = assert(parser.new(one .. one .. "--B--", ct, {max_parts = 1}))
            assert(p:parse_part() == "abc")
            local data, err = p:parse_part()
            assert(data == nil and err == "too many multipart parts")
            p = assert(parser.new(body(header), ct, {max_parts = 1}))
            assert(p:parse_part() == "abc")
            data, err = p:parse_part()
            assert(data == nil and err == nil)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 26: invalid resource limit options are rejected
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            for _, value in ipairs({false, 0, -1, 1.5, math.huge, "2"}) do
                rejected(body(header), ct, "max_parts", {max_parts=value})
                rejected(body(header), ct, "max_header_size", {max_header_size=value})
            end
            rejected(body(header), ct, "options must be a table", false)
            rejected(body(header), ct, "max_parts", {max_parts=0/0})

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 27: incomplete headers and body report errors
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            rejected('--B\r\n' .. header .. '\r\n', ct, "incomplete part headers")
            rejected('', ct, "missing initial boundary")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 28: quoted boundary escaping and quoted UTF-8 values
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body(header, "abc", "a+b"), 'multipart/form-data; boundary="a\\+b"'))
            assert(p:parse_part() == "abc")
            p = assert(parser.new(body('Content-Disposition: form-data; name="文件"; filename="图片.jpg"'), ct))
            local _, name, _, filename = p:parse_part()
            assert(name == "文件" and filename == "图片.jpg")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

=== TEST 29: unknown MIME fields may repeat
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local test = require "test_multipart"
            local parser, ct, header = test.parser, test.content_type, test.header
            local body, rejected = test.body, test.rejected

            local p = assert(parser.new(body(header .. "\r\nX-Test: one\r\nX-Test: two"), ct))
            assert(p:parse_part() == "abc")

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
