local test = require "test_multipart"
local parser = test.parser
local body = test.body
local ct = test.content_type
local header = test.header
local _M = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

local function check_header(headers, index, name, value)
    assert(headers[index].name == name, tostring(headers[index].name))
    assert(headers[index].value == value, tostring(headers[index].value))
end

function _M.form_data()
    local content_type = 'text/plain; charset="utf-8"'
    local p = assert(parser.new(body(header .. "\r\nContent-Type: " .. content_type), ct))
    assert(p:get_part_headers() == nil)
    local result = pack(p:parse_part())
    assert(result.n == 4 and result[1] == "abc" and result[2] == "file")
    assert(result[3] == "text/plain" and result[4] == "good.txt")
    local headers = assert(p:get_part_headers())
    assert(#headers == 2)
    check_header(headers, 1, "content-disposition", 'form-data; name="file"; filename="good.txt"')
    check_header(headers, 2, "content-type", content_type)
    assert(p.body == nil)
    assert(p:get_part_headers() == headers)
    result = pack(p:parse_part())
    assert(result.n == 1 and result[1] == nil)
    assert(p:get_part_headers() == nil)
    assert(p:parse_part() == nil and p:get_part_headers() == nil)
    check_header(headers, 2, "content-type", content_type)
end

function _M.byteranges()
    local first = "Content-Type: application/octet-stream\r\nContent-Range: bytes 7-9/10"
    local second = "Content-Type: application/octet-stream\r\nContent-Range: bytes 0-2/10"
    local value = body(first, "hij"):gsub("%-%-B%-%-\r\n$", "") .. body(second, "abc")
    local p = assert(parser.new(value, "multipart/byteranges; boundary=B"))
    local data, name, mime, filename = p:parse_part()
    assert(data == "hij" and name == nil and mime == "application/octet-stream" and filename == nil)
    local headers = p:get_part_headers()
    assert(#headers == 2)
    check_header(headers, 2, "content-range", "bytes 7-9/10")
    data, name, mime, filename = p:parse_part()
    assert(data == "abc" and name == nil and mime == "application/octet-stream" and filename == nil)
    local next_headers = p:get_part_headers()
    assert(headers ~= next_headers)
    check_header(next_headers, 2, "content-range", "bytes 0-2/10")
    check_header(headers, 2, "content-range", "bytes 7-9/10")
end

function _M.duplicate_headers()
    local h = "X-Trace: first\r\nContent-Type: application/json\r\nx-trace: second\r\nX-Trace: third"
    local p = assert(parser.new(body(h, "{}"), "multipart/mixed; boundary=B"))
    local data, name, mime, filename = p:parse_part()
    assert(data == "{}" and name == nil and mime == "application/json" and filename == nil)
    local headers = p:get_part_headers()
    assert(#headers == 4)
    check_header(headers, 1, "x-trace", "first")
    check_header(headers, 2, "content-type", "application/json")
    check_header(headers, 3, "x-trace", "second")
    check_header(headers, 4, "x-trace", "third")
end

function _M.folded_headers()
    local h = 'CONTENT-DISPOSITION: form-data;\r\n\tname="file"; filename="a.txt"\r\n'
              .. 'Content-Type: text/plain;\r\n charset="utf-8"\r\n'
              .. "X-Note:\t first \t\r\n\tsecond\t\r\nX-Empty: \t"
    local p = assert(parser.new(body(h), ct))
    local data, name, mime, filename = p:parse_part()
    assert(data == "abc" and name == "file" and mime == "text/plain" and filename == "a.txt")
    local headers = p:get_part_headers()
    assert(#headers == 4)
    check_header(headers, 1, "content-disposition", 'form-data; name="file"; filename="a.txt"')
    check_header(headers, 2, "content-type", 'text/plain; charset="utf-8"')
    check_header(headers, 3, "x-note", "first second")
    check_header(headers, 4, "x-empty", "")
end

function _M.empty_headers()
    local p = assert(parser.new("--B\r\n\r\nabc\r\n--B--\r\n", "multipart/mixed; boundary=B"))
    assert(p:parse_part() == "abc")
    local headers = p:get_part_headers()
    assert(type(headers) == "table" and #headers == 0)
    assert(p:parse_part() == nil and p:get_part_headers() == nil)
    assert(#headers == 0)
end

function _M.empty_body()
    local p = assert(parser.new(body('Content-Disposition: form-data; name=""; filename=""', ""), ct))
    local data, name, mime, filename = p:parse_part()
    assert(data == "" and name == "" and mime == nil and filename == "")
    check_header(p:get_part_headers(), 1, "content-disposition", 'form-data; name=""; filename=""')
    p = assert(parser.new("--B--\r\n", "multipart/mixed; boundary=B"))
    assert(p:parse_part() == nil and p:get_part_headers() == nil)
end

function _M.later_error()
    local first = body(header, "first"):gsub("%-%-B%-%-\r\n$", "")
    local bad = header .. "\r\nContent-Type: text/plain\r\ncontent-type: application/json"
    local p = assert(parser.new(first .. body(bad), ct))
    assert(p:parse_part() == "first")
    local headers = p:get_part_headers()
    local result = pack(p:parse_part())
    assert(result.n == 2 and result[1] == nil and result[2] == "duplicate part header: content-type")
    assert(p:get_part_headers() == nil and p.body == nil)
    local again = pack(p:parse_part())
    assert(again.n == 2 and again[2] == result[2] and p:get_part_headers() == nil)
    check_header(headers, 1, "content-disposition", 'form-data; name="file"; filename="good.txt"')
end

function _M.invalid_parts()
    local cases = {
        { body(header .. "\r\n" .. header), "duplicate part header: content-disposition" },
        { body(header .. "\r\nContent-Type: text/plain\r\nContent-Type: application/json"),
          "duplicate part header: content-type" },
        { body(header .. '; name="other"'), "duplicate header parameter: name" },
        { body(header .. "\r\nX-Bad: a\0b"), "invalid control character in part header" },
        { "--B\r\n" .. header .. "\r\n\r\ntruncated", "missing closing boundary" },
    }
    for _, case in ipairs(cases) do
        local p = assert(parser.new(case[1], ct))
        local data, err = p:parse_part()
        assert(data == nil and err == case[2], tostring(err))
        assert(p:get_part_headers() == nil)
    end
end

function _M.limits()
    local h = header .. "\r\nX-Test: first\r\nX-Test: second"
    local p = assert(parser.new(body(h), ct, {max_header_size = #h}))
    assert(p:parse_part() == "abc" and #p:get_part_headers() == 3)
    p = assert(parser.new(body(h .. "x"), ct, {max_header_size = #h}))
    local data, err = p:parse_part()
    assert(data == nil and err == "part headers too large" and p:get_part_headers() == nil)
    local first = body(header, "first"):gsub("%-%-B%-%-\r\n$", "")
    p = assert(parser.new(first .. body(header, "second"), ct, {max_parts = 1}))
    assert(p:parse_part() == "first")
    local headers = p:get_part_headers()
    data, err = p:parse_part()
    assert(data == nil and err == "too many multipart parts" and p:get_part_headers() == nil)
    assert(#headers == 1)
end

function _M.independent_results()
    local first = body(header .. "\r\nX-Part: first", "first"):gsub("%-%-B%-%-\r\n$", "")
    local p = assert(parser.new(first .. body(header .. "\r\nX-Part: second", "second"), ct))
    local other = assert(parser.new(body(header .. "\r\nX-Part: other"), ct))
    assert(p:parse_part() == "first" and other:parse_part() == "abc")
    local headers = p:get_part_headers()
    headers[1].name = "changed"
    headers[1].value = "changed"
    headers[2] = nil
    local data, name, mime, filename = p:parse_part()
    assert(data == "second" and name == "file" and mime == nil and filename == "good.txt")
    check_header(p:get_part_headers(), 2, "x-part", "second")
    check_header(other:get_part_headers(), 2, "x-part", "other")
    assert(headers[1].name == "changed" and headers[2] == nil)
end

return _M
