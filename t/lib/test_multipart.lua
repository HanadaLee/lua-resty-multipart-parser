local parser = require "resty.multipart.parser"
local ct = "multipart/form-data; boundary=B"
local header = 'Content-Disposition: form-data; name="file"; filename="good.txt"'
local function body(h, value, boundary)
    boundary = boundary or "B"
    return "--" .. boundary .. "\r\n" .. h .. "\r\n\r\n" .. (value or "abc")
           .. "\r\n--" .. boundary .. "--\r\n"
end
local function rejected(value, content_type, expected, options)
    local p, err = parser.new(value, content_type, options)
    if p then
        local data
        data, err = p:parse_part()
        assert(data == nil, "unexpected part: " .. tostring(data))
        local again, next_err = p:parse_part()
        assert(again == nil and next_err == err, "unstable parser error")
    end
    assert(type(err) == "string" and err:find(expected, 1, true), tostring(err))
end

return { parser=parser, content_type=ct, header=header, body=body, rejected=rejected }
