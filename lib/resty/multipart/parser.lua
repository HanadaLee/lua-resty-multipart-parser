local byte = string.byte
local find = string.find
local lower = string.lower
local sub = string.sub
local concat = table.concat
local floor = math.floor
local huge = math.huge

local _M = { _VERSION = "1.1.0" }
local mt = { __index = _M }
local token_bytes = {}
local tokens = "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

for i = 1, #tokens do
    token_bytes[byte(tokens, i)] = true
end

local function skip_space(value, pos)
    while byte(value, pos) == 32 or byte(value, pos) == 9 do
        pos = pos + 1
    end
    return pos
end

local function trim_space(value)
    local first = skip_space(value, 1)
    local last = #value
    while last >= first and (byte(value, last) == 32 or byte(value, last) == 9) do
        last = last - 1
    end
    return sub(value, first, last)
end

local function read_token(value, pos)
    local first = pos
    while token_bytes[byte(value, pos)] do
        pos = pos + 1
    end
    if pos == first then
        return nil, pos
    end
    return sub(value, first, pos - 1), pos
end

local function read_quoted(value, pos)
    pos = pos + 1
    local first = pos
    local pieces
    while pos <= #value do
        local c = byte(value, pos)
        if c == 34 then
            local last = sub(value, first, pos - 1)
            if pieces then
                pieces[#pieces + 1] = last
                last = concat(pieces)
            end
            return last, pos + 1
        end
        if c == 92 then
            pieces = pieces or {}
            pieces[#pieces + 1] = sub(value, first, pos - 1)
            pos = pos + 1
            c = byte(value, pos)
            if not c then
                break
            end
            pieces[#pieces + 1] = sub(value, pos, pos)
            first = pos + 1
        end
        if (c < 32 and c ~= 9) or c == 127 then
            return nil, "invalid control character in quoted parameter"
        end
        pos = pos + 1
    end
    return nil, "unterminated quoted parameter"
end

local function parse_parameters(value, media_type)
    local main, pos = read_token(value, skip_space(value, 1))
    if not main then
        return nil, "missing header value"
    end
    if media_type then
        if byte(value, pos) ~= 47 then
            return nil, "invalid media type"
        end
        local subtype
        subtype, pos = read_token(value, pos + 1)
        if not subtype then
            return nil, "invalid media type"
        end
        main = main .. "/" .. subtype
    end
    local parameters = {}
    pos = skip_space(value, pos)
    while pos <= #value do
        if byte(value, pos) ~= 59 then
            return nil, "invalid header parameter separator"
        end
        local name
        name, pos = read_token(value, skip_space(value, pos + 1))
        if not name then
            return nil, "missing header parameter name"
        end
        name = lower(name)
        if parameters[name] ~= nil then
            return nil, "duplicate header parameter: " .. name
        end
        pos = skip_space(value, pos)
        if byte(value, pos) ~= 61 then
            return nil, "missing '=' after header parameter: " .. name
        end
        pos = skip_space(value, pos + 1)
        local parameter
        if byte(value, pos) == 34 then
            parameter, pos = read_quoted(value, pos)
            if parameter == nil then
                return nil, pos
            end
        else
            parameter, pos = read_token(value, pos)
            if not parameter then
                return nil, "missing header parameter value: " .. name
            end
        end
        parameters[name] = parameter
        pos = skip_space(value, pos)
    end
    return main, parameters
end

local function positive_integer(value)
    return type(value) == "number" and value > 0 and value < huge
           and value == floor(value)
end

function _M.new(body, content_type, options)
    if type(body) ~= "string" then
        return nil, "request body must be a string"
    end
    if options ~= nil and type(options) ~= "table" then
        return nil, "parser options must be a table"
    end
    options = options or {}
    local max_header_size = options.max_header_size
    local max_parts = options.max_parts
    if max_header_size == nil then
        max_header_size = 8192
    end
    if max_parts == nil then
        max_parts = 1000
    end
    if not positive_integer(max_header_size) then
        return nil, "max_header_size must be a positive integer"
    end
    if not positive_integer(max_parts) then
        return nil, "max_parts must be a positive integer"
    end
    if type(content_type) == "table" then
        if #content_type ~= 1 then
            return nil, "expected one Content-Type header"
        end
        content_type = content_type[1]
    end
    if type(content_type) ~= "string" then
        return nil, "no Content-Type header specified"
    end
    if #content_type > max_header_size then
        return nil, "Content-Type header too large"
    end
    local media_type, parameters = parse_parameters(content_type, true)
    if not media_type then
        return nil, parameters
    end
    media_type = lower(media_type)
    if sub(media_type, 1, 10) ~= "multipart/" then
        return nil, "Content-Type is not multipart"
    end
    local boundary = parameters.boundary
    if not boundary then
        return nil, "no boundary defined in Content-Type"
    end
    if #boundary == 0 or #boundary > 70 or sub(boundary, -1) == " "
       or find(boundary, "[^0-9A-Za-z'()+_,%-./:=? ]")
    then
        return nil, "invalid multipart boundary"
    end
    return setmetatable({
        boundary = "--" .. boundary,
        boundary2 = "\r\n--" .. boundary,
        body = body,
        form_data = media_type == "multipart/form-data",
        max_header_size = max_header_size,
        max_parts = max_parts,
        parts = 0,
    }, mt)
end

local function fail(self, err)
    self.err = err
    self.body = nil
    return nil, err
end

local function find_boundary(self, start, first)
    local body = self.body
    local delimiter = first and self.boundary or self.boundary2
    while true do
        local from, to = find(body, delimiter, start, true)
        if not from then
            return nil, first and "missing initial boundary" or "missing closing boundary"
        end
        if not first or from == 1 or sub(body, from - 2, from - 1) == "\r\n" then
            local pos = to + 1
            local closing = sub(body, pos, pos + 1) == "--"
            if closing then
                pos = pos + 2
            end
            pos = skip_space(body, pos)
            if sub(body, pos, pos + 1) == "\r\n" then
                return from, pos + 2, closing
            end
            if closing and pos == #body + 1 then
                return from, pos, true
            end
            return nil, "invalid boundary delimiter"
        end
        start = to + 1
    end
end

local function read_headers(self, start)
    local body = self.body
    -- Bound both the header search and the temporary allocation.
    local header = sub(body, start, start + self.max_header_size + 3)
    local last, body_start
    if sub(header, 1, 2) == "\r\n" then
        last, body_start = 0, start + 2
    else
        local from, to = find(header, "\r\n\r\n", 1, true)
        if not from then
            return nil, #header > self.max_header_size and "part headers too large"
                        or "incomplete part headers"
        end
        last, body_start = from - 1, start + to
    end
    if last > self.max_header_size then
        return nil, "part headers too large"
    end
    header = sub(header, 1, last)
    local headers = {}
    local current, values
    local pos = 1
    while pos <= #header do
        local line_end = find(header, "\r\n", pos, true) or #header + 1
        local line = sub(header, pos, line_end - 1)
        if find(line, "[%z\1-\8\10-\31\127]") then
            return nil, "invalid control character in part header"
        end
        if byte(line, 1) == 32 or byte(line, 1) == 9 then
            if not current then
                return nil, "part header continuation without a field"
            end
            values[#values + 1] = trim_space(line)
        else
            if current then
                headers[current] = concat(values, " ")
            end
            local name, next_pos = read_token(line, 1)
            if not name or byte(line, next_pos) ~= 58 then
                return nil, "invalid part header"
            end
            current = lower(name)
            if headers[current] ~= nil
               and (current == "content-disposition" or current == "content-type")
            then
                return nil, "duplicate part header: " .. current
            end
            values = { trim_space(sub(line, next_pos + 1)) }
        end
        pos = line_end + 2
    end
    if current then
        headers[current] = concat(values, " ")
    end
    return headers, body_start
end

function _M.parse_part(self)
    if self.err then
        return nil, self.err
    end
    if self.done then
        return nil
    end
    local start = self.start
    if not start then
        local from, closing
        from, start, closing = find_boundary(self, 1, true)
        if not from then
            return fail(self, start)
        end
        if closing then
            self.done = true
            self.body = nil
            return nil
        end
    end
    if self.parts >= self.max_parts then
        return fail(self, "too many multipart parts")
    end
    local headers, body_start = read_headers(self, start)
    if not headers then
        return fail(self, body_start)
    end
    local name, filename, mime
    if headers["content-disposition"] then
        local disposition, parameters = parse_parameters(headers["content-disposition"], false)
        if not disposition then
            return fail(self, parameters)
        end
        if self.form_data and lower(disposition) ~= "form-data" then
            return fail(self, "expected form-data Content-Disposition")
        end
        name, filename = parameters.name, parameters.filename
    end
    if self.form_data and name == nil then
        return fail(self, "missing form-data name parameter")
    end
    if headers["content-type"] then
        local err
        mime, err = parse_parameters(headers["content-type"], true)
        if not mime then
            return fail(self, err)
        end
    end
    local from, next_start, closing = find_boundary(self, body_start, false)
    if not from then
        return fail(self, next_start)
    end
    local part_body = sub(self.body, body_start, from - 1)
    self.parts = self.parts + 1
    self.start = next_start
    if closing then
        self.done = true
        self.body = nil
    end
    return part_body, name, mime, filename
end

return _M
