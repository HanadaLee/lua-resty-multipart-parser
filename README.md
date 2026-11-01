Name
====

lua-resty-multipart-parser - Simple multipart data parser for OpenResty/Lua

Table of Contents
=================

* [Name](#name)
* [Synopsis](#synopsis)
* [Description](#description)
* [Installation](#installation)
* [API](#api)
* [Testing](#testing)
* [Community](#community)
    * [English Mailing List](#english-mailing-list)
    * [Chinese Mailing List](#chinese-mailing-list)
* [Bugs and Patches](#bugs-and-patches)
* [Author](#author)
* [Copyright and License](#copyright-and-license)

Synopsis
========

```lua
local parser = require "resty.multipart.parser"

ngx.req.read_body()

local body = ngx.req.get_body_data()
if not body then
   ngx.say("request body is unavailable in memory")
   return
end

local p, err = parser.new(body, ngx.var.http_content_type)
if not p then
   ngx.say("failed to create parser: ", err)
   return
end

while true do
   local part_body, name, mime, filename = p:parse_part()
   if not part_body then
      if name then
         ngx.say("failed to parse multipart body: ", name)
      end
      break
   end
   ngx.say("== part ==")
   ngx.say("name: [", name, "]")
   ngx.say("file: [", filename, "]")
   ngx.say("mime: [", mime, "]")
   ngx.say("body: [", part_body, "]")
end
```

Description
===========

This Lua library provides a simple parser for the multipart data format. Unlike the [lua-resty-upload](https://github.com/openresty/lua-resty-upload) library,
this parser does not support streaming processing of file uploads using the multipart format. However, it is more flexible in that it can be used
to parse buffered request bodies read by the builtin request body reader of the NGINX core.

Anyway, be very careful when using this for large file uploads. Use `lua-resty-upload` instead.

Installation
------------

Install the release with LuaRocks configured for your OpenResty LuaJIT:

```sh
luarocks install lua-resty-multipart-parser 1.2.0-1
```

Ensure the installed Lua directory is included in `lua_package_path`. The
module is loaded as `require "resty.multipart.parser"`.

API
===

`parser.new(body, content_type, options?)` accepts a complete Lua string and a
multipart Content-Type value. A one-element Content-Type table is also accepted.
It returns a parser or `nil, err`. Reading a request body, including one stored
in an NGINX temporary file, is the caller's responsibility. Set an appropriate
`client_max_body_size` and check the body size before reading a temporary file
into memory. The parser does not perform file I/O.

The optional `options` table accepts positive integer limits:

* `max_header_size`: maximum Content-Type length and maximum header block length
  per part, in bytes. Defaults to 8192. The final CRLF separator is excluded
  from the part header block length.
* `max_parts`: maximum number of parts. Defaults to 1000.

`p:parse_part()` returns `part_body, name, mime, filename`. Empty bodies and empty
quoted parameter values are preserved as empty strings. Other multipart types
may omit form-data metadata; `multipart/form-data` requires a `form-data`
Content-Disposition with a `name` parameter.

Normal completion returns `nil` without an error, including on subsequent
calls. Invalid or truncated data returns `nil, err`; subsequent calls return the
same error. Consume all parts to validate the complete message before using a
selected field. Preamble and epilogue are ignored, and the input string is
released by the parser after completion or an error.

`p:get_part_headers()` returns the headers of the most recently parsed part as an ordered list of `{ name = string, value = string }` entries. Call it after a successful `parse_part()`. Header names are lowercase; values retain their parameters, with surrounding spaces and tabs removed and folded lines joined with a single space. Ordinary duplicate headers remain separate entries in their original order. Duplicate Content-Disposition and Content-Type fields are still rejected.

```lua
local part_body, name, mime, filename = p:parse_part()
if part_body ~= nil then
    for _, header in ipairs(p:get_part_headers()) do
        print(header.name, header.value)
    end
end
```

This also exposes headers such as `Content-Range` in `multipart/byteranges` and custom headers in `multipart/mixed`, including parts without a name. A valid part with no headers returns an empty list. The method returns `nil` before the first part and after a `parse_part()` call that returns completion or an error. Headers from the final part remain available until the next `parse_part()` call. Previously returned lists remain valid and are not reused for later parts; changing them does not change parser behavior. The existing four return values of `parse_part()` are unchanged, and `get_part_headers()` performs no parsing or I/O.

Quoted parameters support escaped characters. Duplicate parameters and duplicate
Content-Disposition or Content-Type fields are rejected. Multiple parts with
the same field name remain supported and are returned in their original order.
Boundary values are limited to the RFC 2046 grammar and 70 bytes.

Testing
-------

Install OpenResty and [Test::Nginx](https://github.com/openresty/test-nginx), then
run the integration suite:

```sh
TEST_NGINX_BINARY=/usr/local/openresty/nginx/sbin/nginx prove -r t
```

[Back to TOC](#table-of-contents)

Community
=========

[Back to TOC](#table-of-contents)

English Mailing List
--------------------

The [openresty-en](https://groups.google.com/group/openresty-en) mailing list is for English speakers.

[Back to TOC](#table-of-contents)

Chinese Mailing List
--------------------

The [openresty](https://groups.google.com/group/openresty) mailing list is for Chinese speakers.

[Back to TOC](#table-of-contents)

Bugs and Patches
================

Please report bugs or submit patches by

1. creating a ticket on the [GitHub Issue Tracker](https://github.com/HanadaLee/lua-resty-multipart-parser/issues),
1. or posting to the [OpenResty community](#community).

[Back to TOC](#table-of-contents)

Author
======

Yichun "agentzh" Zhang (章亦春) <agentzh@gmail.com>, CloudFlare Inc.

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2016, by Yichun "agentzh" Zhang, CloudFlare Inc.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)
