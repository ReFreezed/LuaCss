--[[============================================================
--=
--=  LuaCss - CSS Tokenizing & Minimizing
--=  https://github.com/ReFreezed/LuaCss
--=
--=  References:
--=  - https://www.w3.org/TR/css-syntax-3/
--=  - https://drafts.csswg.org/cssom/ (Editor's draft, 2018-05-17)
--=
--=  MIT License:
--=  Copyright © 2018 Marcus 'ReFreezed' Thunström
--=
--=  Permission is hereby granted, free of charge, to any person obtaining a copy
--=  of this software and associated documentation files (the "Software"), to deal
--=  in the Software without restriction, including without limitation the rights
--=  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--=  copies of the Software, and to permit persons to whom the Software is
--=  furnished to do so, subject to the following conditions:
--=
--=  The above copyright notice and this permission notice shall be included in all
--=  copies or substantial portions of the Software.
--=
--=  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--=  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--=  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--=  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--=  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--=  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--=  SOFTWARE.
--=
--==============================================================


	API
	--------------------------------

	minimize
		cssString = minimize( cssString [, options ] )
		tokens    = minimize( tokens    [, options ] )

	serialize
		cssString = serialize( tokens [, options ] )

	serializeAndMinimize
		cssString = serializeAndMinimize( tokens [, options ] )

	tokenize
		tokens = tokenize( cssString )


	Options
	--------------------------------

	autoZero
		Convert '0px' and '0%' etc. to a simple '0' during minification.

	strict
		Trigger an error when a badString or badUrl token is encountered during minification.


--============================================================]]



local CP_NULL           = 0x00
local CP_DASH           = 0x2D
local CP_0              = 0x30
local CP_9              = 0x39
local CP_A              = 0x41
local CP_Z              = 0x5A
local CP_BACKSLASH      = 0x5C
local CP_UNDERSCORE     = 0x5F
local CP_a              = 0x61
local CP_z              = 0x7A
local CP_DELETE         = 0x7F
local CP_REPLACE        = 0xFFFD

local CP_NONASCII_START = 0x80

local CHAR_REPLACE      = "\239\191\189"



local path = ("."..assert(...,"Needs module path.")):gsub("[^.]+$","")
local utf8 = require((path.."utf8"):sub(2))

local F = string.format

local css = {VERSION="0.1.0"}



--==============================================================
--= Utilities ==================================================
--==============================================================

local findEnd
local getKeys
local indexOf
local inRange
local isAny
local isValidCodepoint, isControlCharacterCodepoint, isSurrogateCodepoint
local makeString
local newTokenComment, newTokenWhitespace, newTokenNumber
local printobj
local sort
local sortNatural, compareNatural
local substrCompareAsciiChar, substrCompareBytes



function indexOf(t, v)
	for i, item in ipairs(t) do
		if item == v then  return i  end
	end
	return nil
end



-- printobj( ... )
-- Note: Does not write to log.
do
	local out = io.stdout

	local _tostring = tostring
	local function tostring(v)
		return (_tostring(v):gsub('^table: ', ''))
	end

	local function compareKeys(a, b)
		return compareNatural(tostring(a), tostring(b))
	end

	local function _printobj(v, tables)
		local vType = type(v)

		if vType == "table" then
			if tables[v] then
				out:write(tostring(v), " ")
				return
			end

			out:write(tostring(v), "{ ")
			tables[v] = true

			local indices = {}
			for i = 1, #v do  indices[i] = true  end

			for _, k in ipairs(sort(getKeys(v), compareKeys)) do
				if not indices[k] then
					out:write(tostring(k), "=")
					_printobj(v[k], tables)
				end
			end

			for i = 1, #v do
				out:write(i, "=")
				_printobj(v[i], tables)
			end

			out:write("} ")

		elseif vType == "number" then
			out:write(F("%g ", v))

		elseif vType == "string" then
			out:write('"', v:gsub("%z", "\\0"):gsub("\n", "\\n"), '" ')

		else
			out:write(tostring(v), " ")
		end

	end

	function printobj(...)
		for i = 1, select("#", ...) do
			if i > 1 then  out:write("\t")  end

			_printobj(select(i, ...), {})
		end
		out:write("\n")
	end

end



function sort(t, ...)
	table.sort(t, ...)
	return t
end



-- array = sortNatural( array [, attribute ] )
do
	local function pad(numStr)
		return F("%03d%s", #numStr, numStr)
	end
	function compareNatural(a, b)
		return tostring(a):gsub("%d+", pad) < tostring(b):gsub("%d+", pad)
	end

	function sortNatural(t, k)
		if k then
			table.sort(t, function(a, b)
				return compareNatural(a[k], b[k])
			end)
		else
			table.sort(t, compareNatural)
		end
		return t
	end
end



function getKeys(t)
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	return keys
end



function inRange(n, min, max)
	return n >= min and n <= max
end



function isValidCodepoint(cp)
	return cp >= 0 and cp <= 0x10FFFF
end

function isControlCharacterCodepoint(cp)
	return inRange(cp, 0x01, 0x1F)
end

function isSurrogateCodepoint(cp)
	return cp >= 0xD800 and cp <= 0xDFFF
end



function substrCompareAsciiChar(s, i, chars)
	local c = s:sub(i, i)
	if c == "" then  return false  end

	return chars:find(c, 1, true) ~= nil

	--[[
	local b = s:byte(i)

	for charIndex = 1, #chars do
		if b == chars:byte(charIndex) then
			return true
		end
	end

	return false
	]]
end

--[[
-- endIndex = substrCompareBytes( string, startIndex, comparison )
function substrCompareBytes(s, i, comparison) -- Not used.
	if i < 1 or i > #s-#comparison+1 then  return nil  end

	for offset = 0, #comparison-1 do
		if s:byte(i+offset) ~= comparison:byte(1+offset) then
			return nil
		end
	end

	return i+#comparison-1
end
]]



function findEnd(s, ...)
	local _, i = s:find(...)
	return i
end



do
	local UNPACK_LIMIT = 8000
	local chars = {}

	function makeString(cps)
		if not cps[UNPACK_LIMIT] then
			return utf8.char(unpack(cps))
		end

		local toChar = utf8.char

		for i = 1, #cps do
			chars[i] = toChar(cps[i])
			assert(#chars[i] == 1)
		end

		return table.concat(chars, "", 1, #cps)
	end

	--[[ Test limit of unpack(). (Is this always the same though?)
	for i = 1, math.huge do
		chars[i] = true
		if not pcall(unpack, chars) then
			print("Max unpacks: "..i)
			os.exit(1)
		end
	end
	--]]
end



-- token = newTokenComment( [ comment="" ] )
function newTokenComment(comment)
	local token = {type="comment"}
	token.value = comment or ""
	return token
end

-- token = newTokenWhitespace( [ value="" ] )
function newTokenWhitespace(value)
	local token = {type="whitespace"}
	token.value = value or ""
	return token
end

-- token = newTokenNumber( [ number=0, numberRepresentation=auto, numberType=auto ] )
function newTokenNumber(n, nRepr, nType)
	local token = {type="number"}

	n     = n or 0
	nRepr = nRepr or F("%g ", n)

	token.representation = nRepr
	token.value          = n
	token.numberType     = nType  or nRepr:find"[^%d]" and "number"  or "integer"

	return token
end



function isAny(v, ...)
	for i = 1, select("#", ...) do
		if v == select(i, ...) then  return true  end
	end
	return false
end



--==============================================================
--= Tokenizer ==================================================
--==============================================================

local isEscapeStart
local isNameStart
local isIdentStart
local isNumberStart
local isName

local matchWs
local matchAlphaOrNonAscii
local matchNonPrintable
local matchPrintable

local consumeNumericToken
local consumeIdentLikeToken
local consumeStringToken
local consumeUrlToken
local consumeUnicodeRangeToken
local consumeEscape
local consumeName
local consumeNumber
local consumeRemnantsOfBadUrl
local consumeWhitespace
local consumeComment



function isEscapeStart(s, ptr)
	if not substrCompareAsciiChar(s, ptr,   "\\") then  return false  end
	if     substrCompareAsciiChar(s, ptr+1, "\n") then  return false  end
	return true
end

function isNameStart(s, ptr)
	return matchAlphaOrNonAscii(s, ptr) ~= nil
end

function isIdentStart(s, ptr)
	if substrCompareAsciiChar(s, ptr, "-") then
		return isNameStart(s, ptr+1) or isEscapeStart(s, ptr+1)

	elseif isNameStart(s, ptr) then
		return true

	elseif substrCompareAsciiChar(s, ptr, "\\") then
		return isEscapeStart(s, ptr)

	else
		return false
	end
end

function isNumberStart(s, ptr)
	if substrCompareAsciiChar(s, ptr, "+-") then
		if substrCompareAsciiChar(s, ptr+1, "0123456789") then
			return true
		elseif s:find("^%.%d", ptr+1) then
			return true
		else
			return false
		end

	elseif substrCompareAsciiChar(s, ptr, ".") then
		return substrCompareAsciiChar(s, ptr+1, "0123456789")

	elseif substrCompareAsciiChar(s, ptr, "0123456789") then
		return true

	else
		return false
	end
end

function isName(s, ptr)
	return isNameStart(s, ptr) or substrCompareAsciiChar(s, ptr, "0123456789-")
end



-- ws*
function matchWs(s, ptr)
	return s:find("^[ \t\n]*", ptr)
end

function matchAlphaOrNonAscii(s, ptr)
	if s:find("^[%a_]", ptr) then  return ptr, ptr  end

	local cp = utf8.codepoint(s, 1, 1, ptr)
	if not cp or cp < CP_NONASCII_START then  return nil  end

	return ptr, ptr+utf8.charlen(s, ptr)-1
end

function matchNonPrintable(s, ptr)
	if not s:find("^[%z\1-\8\11\14-\31\127]", ptr) then  return nil  end

	return ptr, ptr
end
-- function matchPrintable(s, ptr) -- Not used.
-- 	if not s:find("^[^%z\1-\8\11\14-\31\127]", ptr) then  return nil  end

-- 	return ptr, ptr
-- end



function consumeNumericToken(s, ptr)
	local nRepr, n, nType
	nRepr, n, nType, ptr = consumeNumber(s, ptr)

	local token

	if isIdentStart(s, ptr) then
		token = {type="dimension"}
		token.unit, ptr = consumeName(s, ptr)

	elseif substrCompareAsciiChar(s, ptr, "%") then
		token = {type="percentage"}
		ptr = ptr+1

	else
		token = newTokenNumber(n, nRepr, nType)
		return token, ptr
	end

	token.representation = nRepr
	token.value          = n
	token.numberType     = nType

	return token, ptr
end

function consumeIdentLikeToken(s, ptr)
	local name
	name, ptr = consumeName(s, ptr)

	local token

	if #name == 3 and substrCompareAsciiChar(s, ptr, "(") and name:lower() == "url" then
		token, ptr = consumeUrlToken(s, ptr+1) -- Note the previous consumption.

	elseif substrCompareAsciiChar(s, ptr, "(") then
		token, ptr = {type="function"}, ptr+1
		token.value = name

	else
		token = {type="ident"}
		token.value = name
	end

	return token, ptr
end

function consumeStringToken(s, ptr, quoteChar)
	-- Assume the initial quoteChar has been consumed.

	local cps = {}

	while true do
		if ptr > #s or substrCompareAsciiChar(s, ptr, quoteChar) then
			local token = {type="string"}
			token.value          = makeString(cps)
			token.quoteCharacter = quoteChar
			return token, ptr+1

		elseif substrCompareAsciiChar(s, ptr, "\n") then
			print("[css] Parse error: Invalid newline at position "..ptr..".")

			local token = {type="badString"}
			return token, ptr

		elseif substrCompareAsciiChar(s, ptr, "\\") then
			if ptr+1 > #s then
				-- void

			elseif substrCompareAsciiChar(s, ptr+1, "\n") then
				ptr = ptr+2

			elseif isEscapeStart(s, ptr) then
				local cp
				cp, ptr = consumeEscape(s, ptr+1)
				table.insert(cps, cp)

			else
				assert(false) -- Unspecified syntax.
			end

		else
			local cp = utf8.codepoint(s, 1, 1, ptr)
			table.insert(cps, cp)

			ptr = ptr+utf8.charlen(s, ptr)
		end
	end
end

function consumeUrlToken(s, ptr)
	-- Assume the initial "url(" has been consumed.

	local from, to = matchWs(s, ptr)
	ptr = to+1

	if ptr > #s then
		local token = {type="url"}
		token.value          = ""
		token.quoteCharacter = ""
		return token, ptr
	end

	if substrCompareAsciiChar(s, ptr, "\"'") then
		local quoteChar = s:sub(ptr, ptr)

		local strToken
		strToken, ptr = consumeStringToken(s, ptr+1, quoteChar)

		if strToken.type == "badString" then
			ptr = consumeRemnantsOfBadUrl(s, ptr)
			local token = {type="badUrl"}
			return token, ptr
		end

		local from, to = matchWs(s, ptr)
		ptr = to+1

		if ptr > #s or substrCompareAsciiChar(s, ptr, ")") then
			local token = {type="url"}
			token.value          = strToken.value
			token.quoteCharacter = quoteChar

			if token.value:find"^data:image/jpeg;base64," then
				token.value = token.value:gsub("%s+", "")
			end

			return token, ptr+1

		else
			ptr = consumeRemnantsOfBadUrl(s, ptr)
			local token = {type="badUrl"}
			return token, ptr
		end
	end

	local cps = {}

	while true do
		if ptr > #s or substrCompareAsciiChar(s, ptr, ")") then
			local token = {type="url"}
			token.value          = makeString(cps)
			token.quoteCharacter = ""
			return token, ptr+1

		elseif substrCompareAsciiChar(s, ptr, " \t\n") then
			from, to = matchWs(s, ptr+1)
			ptr = to+1

			if ptr > #s or substrCompareAsciiChar(s, ptr, ")") then
				local token = {type="url"}
				token.value          = makeString(cps)
				token.quoteCharacter = ""
				return token, ptr+1

			else
				ptr = consumeRemnantsOfBadUrl(s, ptr)
				local token = {type="badUrl"}
				return token, ptr
			end

		elseif substrCompareAsciiChar(s, ptr, "\"'(") or matchNonPrintable(s, ptr) then
			print("[css] Parse error: Invalid character at position "..ptr..".")

			ptr = consumeRemnantsOfBadUrl(s, ptr)
			local token = {type="badUrl"}
			return token, ptr

		elseif substrCompareAsciiChar(s, ptr, "\\") then
			if isEscapeStart(s, ptr) then
				local cp
				cp, ptr = consumeEscape(s, ptr+1)
				table.insert(cps, cp)

			else
				print("[css] Parse error: Invalid escape at position "..ptr..".")

				ptr = consumeRemnantsOfBadUrl(s, ptr)
				local token = {type="badUrl"}
				return token, ptr
			end

		else
			local cp = utf8.codepoint(s, 1, 1, ptr)
			table.insert(cps, cp)

			ptr = ptr+utf8.charlen(s, ptr)
		end
	end
end

function consumeUnicodeRangeToken(s, ptr)
	-- Assume the initial "U+" has been consumed, and we're at a hex or "?".

	local from, to, hex = s:find(
		"^([%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?)", ptr
	)
	local digitCount = to-from+1
	ptr = to+1

	from, to = s:find("^"..("%??"):rep(6-digitCount), ptr)
	local questionMarkCount = to-from+1
	ptr = to+1

	local token = {type="unicodeRange"}

	if questionMarkCount > 0 then
		token.from = tonumber(hex..("0"):rep(questionMarkCount), 16)
		token.to   = tonumber(hex..("F"):rep(questionMarkCount), 16)
		return token, ptr
	end

	token.from = tonumber(hex, 16)

	if s:find("^%-[%dA-Fa-f]", ptr) then
		ptr = ptr+1

		local hexRangeTo
		from, to, hexRangeTo = s:find(
			"^([%dA-Fa-f][%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?)", ptr
		)
		ptr = to+1

		token.to = tonumber(hexRangeTo, 16)

	else
		token.to = token.from
	end

	return token, ptr
end

function consumeEscape(s, ptr)
	-- Assume "\" has been consumed and we're not at a newline.

	if ptr > #s then
		return CP_REPLACE, ptr
	end

	if s:find("^[%dA-Fa-f]", ptr) then
		local hex = s:match(
			"^[%dA-Fa-f][%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?[%dA-Fa-f]?", ptr
		)
		ptr = ptr+#hex

		if substrCompareAsciiChar(s, ptr, " \t\n") then
			ptr = ptr+1
		end

		local cp = tonumber(hex, 16)
		if cp == CP_NULL or isSurrogateCodepoint(cp) or not isValidCodepoint(cp) then
			return CP_REPLACE, ptr
		else
			return cp, ptr
		end
	end

	local cp = utf8.codepoint(s, 1, 1, ptr)
	ptr = ptr+utf8.charlen(s, ptr)

	return cp, ptr
end

function consumeName(s, ptr)
	-- Note: No verification is being done.

	local cps = {}

	while true do
		if isName(s, ptr) then
			local cp = utf8.codepoint(s, 1, 1, ptr)
			table.insert(cps, cp)
			ptr = ptr+utf8.charlen(s, ptr)

		elseif isEscapeStart(s, ptr) then
			local cp
			cp, ptr = consumeEscape(s, ptr+1)
			table.insert(cps, cp)

		else
			return makeString(cps), ptr
		end

	end
end

function consumeNumber(s, ptr)
	-- Note: No verification is being done.

	local nRepr = {}
	local nType = "integer"

	local part = s:match("^[-+]?%d*", ptr) -- May be an empty string.
	table.insert(nRepr, part)
	ptr = ptr+#part

	if s:find("^%.%d", ptr) then
		part = s:match("^%.%d+", ptr)
		table.insert(nRepr, part)
		ptr = ptr+#part

		nType = "number"
	end

	if s:find("^[Ee][-+]?%d", ptr) then
		part = s:match("^[Ee][-+]?%d+", ptr)
		table.insert(nRepr, part)
		ptr = ptr+#part

		nType = "number"
	end

	nRepr = table.concat(nRepr)

	-- This probably works most of the time. Probably...  @Incomplete
	local n = tonumber(nRepr)
	assert(n, nRepr)

	return nRepr, n, nType, ptr
end

function consumeRemnantsOfBadUrl(s, ptr)
	while true do
		if ptr > #s or substrCompareAsciiChar(s, ptr, ")") then
			return ptr+1

		elseif isEscapeStart(s, ptr) then
			local cp
			cp, ptr = consumeEscape(s, ptr)
			-- Throw away the codepoint.

		else
			ptr = ptr+utf8.charlen(s, ptr)
		end
	end
end

function consumeWhitespace(s, ptr)
	local ws = s:match("^[ \t\n]+", ptr)
	ptr = ptr+#ws

	local token = {type="whitespace"}
	token.value = ws

	return token, ptr
end

function consumeComment(s, ptr)
	-- Assume the initial "/*" has been consumed.

	local comment

	local from, to = s:find("*/", ptr, true)
	if from then
		comment = s:sub(ptr, to-2)
		ptr = to+1
	else
		comment = s:sub(ptr)
		ptr = #s+1
	end

	token = newTokenComment(comment)
	return token, ptr
end



function css.tokenize(s)
	-- Preprocess stream. https://www.w3.org/TR/css-syntax-3/#input-preprocessing
	s = s
		:gsub("\r\n?", "\n")
		:gsub("\f",    "\n")
		:gsub("%z",    CHAR_REPLACE)

	-- Tokenize.
	-- https://www.w3.org/TR/css-syntax-3/#tokenization
	--
	-- <ident-token>
	-- <function-token>
	-- <at-keyword-token>
	-- <hash-token>
	-- <string-token>, <bad-string-token>
	-- <url-token>, <bad-url-token>
	-- <delim-token>
	-- <number-token>
	-- <percentage-token>
	-- <dimension-token>
	-- <unicode-range-token>
	-- <include-match-token>
	-- <dash-match-token>
	-- <prefix-match-token>
	-- <suffix-match-token>
	-- <substring-match-token>
	-- <column-token>
	-- <whitespace-token>
	-- <CDO-token>, <CDC-token>
	-- <colon-token>
	-- <semicolon-token>
	-- <comma-token>
	-- <[-token>, <]-token>
	-- <(-token>, <)-token>
	-- <{-token>, <}-token>
	--
	-- <ident-token>, <function-token>, <at-keyword-token>, <hash-token>, <string-token>, <url-token>: value = 0+ cps.
	-- <delim-token>: value = 1 cp.
	-- <number-token>, <percentage-token>, <dimension-token>: representation = one+ cps, value = numeric.
	-- <dimension-token>: additional unit = 1+ cps.
	-- <unicode-range-token>: start and end = 2 integers.
	local tokens = {}

	local ptr     = 1
	local ptrLast = 1

	while ptr <= #s do
		local c1 = s:sub(ptr,   ptr  ) -- We probably don't need to use utf8.sub() here.
		local c2 = s:sub(ptr+1, ptr+1)
		local c3 = s:sub(ptr+2, ptr+2)
		local c4 = s:sub(ptr+3, ptr+3)

		local token

		--------------------------------
		if c1 == " " or c1 == "\t" or c1 == "\n" then
			token, ptr = consumeWhitespace(s, ptr)

		--------------------------------
		elseif c1 == '"' or c1 == "'" then
			token, ptr = consumeStringToken(s, ptr+1, c1)

		--------------------------------
		elseif c1 == "#" then
			if isName(s, ptr+1) or isEscapeStart(s, ptr+1) then
				token = {type="hash"}

				token.idType = isIdentStart(s, ptr+1) and "id" or "unrestricted"
				token.value, ptr = consumeName(s, ptr+1)

			else
				token = {type="delim", value=c1}
			end

		--------------------------------
		elseif c1 == "$" then
			if c2 == "=" then
				token, ptr = {type="suffixMatch"}, ptr+2
			else
				token = {type="delim", value=c1}
			end

		elseif c1 == "*" then
			if c2 == "=" then
				token, ptr = {type="substringMatch"}, ptr+2
			else
				token = {type="delim", value=c1}
			end

		elseif c1 == "^" then
			if c2 == "=" then
				token, ptr = {type="prefixMatch"}, ptr+2
			else
				token = {type="delim", value=c1}
			end

		elseif c1 == "|" then
			if c2 == "=" then
				token, ptr = {type="dashMatch"}, ptr+2
			elseif c2 == "|" then
				token, ptr = {type="columnMatch"}, ptr+2
			else
				token = {type="delim", value=c1}
			end

		elseif c1 == "~" then
			if c2 == "=" then
				token, ptr = {type="includeMatch"}, ptr+2
			else
				token = {type="delim", value=c1}
			end

		--------------------------------
		elseif c1 == "(" then
			token = {type="("}
		elseif c1 == ")" then
			token = {type=")"}

		elseif c1 == "," then
			token = {type="comma"}

		elseif c1 == ":" then
			token = {type="colon"}
		elseif c1 == ";" then
			token = {type="semicolon"}

		elseif c1 == "[" then
			token = {type="["}
		elseif c1 == "]" then
			token = {type="]"}

		elseif c1 == "{" then
			token = {type="{"}
		elseif c1 == "}" then
			token = {type="}"}

		--------------------------------
		elseif c1 == "+" then
			if isNumberStart(s, ptr+1) then
				token, ptr = consumeNumericToken(s, ptr)
			else
				token = {type="delim", value=c1}
			end

		elseif c1 == "-" then
			if isNumberStart(s, ptr+1) then
				token, ptr = consumeNumericToken(s, ptr)
			elseif isIdentStart(s, ptr+1) then
				token, ptr = consumeIdentLikeToken(s, ptr)
			elseif c2 == "-" and c3 == ">" then
				token, ptr = {type="cdc"}, ptr+3
			else
				token = {type="delim", value=c1}
			end

		elseif c1 == "." then
			if isNumberStart(s, ptr+1) then
				token, ptr = consumeNumericToken(s, ptr)
			else
				token = {type="delim", value=c1}
			end

		--------------------------------
		elseif c1 == "/" then
			if c2 == "*" then
				token, ptr = consumeComment(s, ptr+2)
			else
				token = {type="delim", value=c1}
			end

		--------------------------------
		elseif c1 == "<" then
			if c2 == "!" and c3 == "-" and c4 == "-" then
				token, ptr = {type="cdo"}, ptr+4
			else
				token = {type="delim", value=c1}
			end

		--------------------------------
		elseif c1 == "@" then
			if isIdentStart(s, ptr+1) then
				token = {type="atKeyword"}

				token.value, ptr = consumeName(s, ptr+1)

			else
				token = {type="delim", value=c1}
			end

		--------------------------------
		elseif c1 == "\\" then
			if isEscapeStart(s, ptr) then
				token, ptr = consumeIdentLikeToken(s, ptr)

			else
				print("[css] Parse error: Invalid escape at position "..ptr..".")
				token = {type="delim", value=c1}
			end

		--------------------------------
		elseif substrCompareAsciiChar(c1, 1, "0123456789") then
			token, ptr = consumeNumericToken(s, ptr)

		--------------------------------
		elseif c1 == "U" or c1 == "u" then
			if c2 == "+" and substrCompareAsciiChar(c3, 1, "0123456789ABCDEFabcdef?") then
				token, ptr = consumeUnicodeRangeToken(s, ptr+2) -- Note the consumption.
			else
				token, ptr = consumeIdentLikeToken(s, ptr)
			end

		--------------------------------
		elseif isNameStart(s, ptr) then
			token, ptr = consumeIdentLikeToken(s, ptr)

		--------------------------------
		else
			token = {type="delim", value=c1}
		end
		--------------------------------

		assert(token)
		table.insert(tokens, token)

		if ptr == ptrLast then  ptr = ptr+#c1  end
		ptrLast = ptr
	end

	return tokens
end



--==============================================================
--= Serializer =================================================
--==============================================================

local canTrimBeforeNextToken
local formatNumberFromToken



function formatNumberFromToken(token)
	local n    = token.value
	local repr = token.representation:gsub("^%+", "")

	local nStr = F("%.10g", n)
	if #nStr > #repr or tonumber(nStr) ~= n then  nStr = repr  end

	nStr = nStr:gsub("0%.", ".")
	return nStr
end



function canTrimBeforeNextToken(tokens, i)
	local token = tokens[i+1]
	if not token then  return true  end

	return not isAny(token.type, "ident","function","url","badUrl","number","percentage","dimension","unicodeRange")
end



function css.serializeAndMinimize(tokens, options)
	options = options or {}
	return css.serialize(css.minimize(tokens, options), options)
end



function css.serialize(tokens, options)
	options = options or {}

	local out = {}

	local function write(v)
		table.insert(out, v)
	end

	-- https://drafts.csswg.org/cssom/#serialize-an-identifier
	local function writeName(v, unrestricted, trimTrailingSpace)
		local cps     = {}
		local firstCp = nil

		for cp, from, to, charPos in utf8.codes(v) do
			firstCp = firstCp or cp

			if cp == CP_NULL then
				table.insert(cps, CP_REPLACE)

			elseif
				isControlCharacterCodepoint(cp)
				or cp == CP_DELETE
				or (
					(
						charPos == 1 and not unrestricted
						or charPos == 2 and firstCp == CP_DASH
					)
					and inRange(cp, CP_0, CP_9)
				)
			then
				local escape = F("\\%X ", cp)
				for i = 1, #escape do
					table.insert(cps, escape:byte(i))
				end

			elseif charPos == 1 and cp == CP_DASH and #v == 1 then
				table.insert(cps, CP_BACKSLASH)
				table.insert(cps, cp)

			elseif
				cp >= CP_NONASCII_START
				or cp == CP_DASH
				or cp == CP_UNDERSCORE
				or inRange(cp, CP_0, CP_9)
				or inRange(cp, CP_A, CP_Z)
				or inRange(cp, CP_a, CP_z)
			then
				table.insert(cps, cp)

			else
				table.insert(cps, CP_BACKSLASH)
				table.insert(cps, cp)
			end
		end

		if trimTrailingSpace and cps[#cps] == 32 then
			table.remove(cps)
		end

		write(makeString(cps))
	end

	-- https://drafts.csswg.org/cssom/#serialize-a-string
	function writeString(v, quoteChar)
		if not quoteChar then
			-- http://tantek.com/CSS/Examples/boxmodelhack.html#content
			local ie5ParsingBugExploitQuoteChar = v:match"^([\"']).+[\"']$"

			local hasDouble = v:find('"', 1, true) ~= nil
			local hasSingle = v:find("'", 1, true) ~= nil
			quoteChar = ie5ParsingBugExploitQuoteChar or hasDouble and not hasSingle and "'" or '"'
		end

		v = v
			:gsub("%z", CHAR_REPLACE)
			:gsub("["..quoteChar.."\\]", "\\%0")
			:gsub("[\1-\31]", function(c)
				return F("\\%X ", c:byte())
			end)

		write(quoteChar)
		write(v)
		write(quoteChar)
	end

	function writePlainUrlValue(v)
		v = v
			:gsub("%z", CHAR_REPLACE)
			:gsub("[\\ ()\"']", "\\%0")
			:gsub("[\1-\31]", function(c)
				return F("\\%X ", c:byte())
			end)

		write(v)
	end

	for i, token in ipairs(tokens) do
		if token.type == "dimension" then
			local nRepr = formatNumberFromToken(token)
			write(nRepr)

			-- Eliminate ambiguity with scientific notation.
			if not nRepr:find("n", 2, true) and token.unit:find"^[Ee][-+]?%d" then
				write("e0") -- W3C CSS validator still complains...
			end

			writeName(token.unit, false, canTrimBeforeNextToken(tokens, i))

		elseif token.type == "percentage" then
			write(formatNumberFromToken(token))
			write("%")

		elseif token.type == "number" then
			write(formatNumberFromToken(token))

		elseif token.type == "function" then
			writeName(token.value, false, true)
			write("(")

		elseif token.type == "ident" then
			writeName(token.value, false, canTrimBeforeNextToken(tokens, i))

		elseif token.type == "string" then
			writeString(token.value, (options.preserveQuotes and token.quoteCharacter or nil))

		elseif token.type == "badString" then
			if options.strict then
				error("[css] BAD_STRING token at position "..i..".")
			else
				print("[css] Warning: BAD_STRING token at position "..i..".")
				write('""')
			end

		elseif token.type == "url" then
			local v = token.value
			write("url(")

			if options.preserveQuotes then
				if token.quoteCharacter ~= "" then
					writeString(v, token.quoteCharacter)
				elseif v ~= "" then
					writePlainUrlValue(v)
				end

			elseif v == "" then
				-- void

			elseif v:find"[ ()\"']" then
				-- https://drafts.csswg.org/cssom/#serialize-a-url
				writeString(v)

			else
				-- Custom serialization code. Hopefully works in all cases.
				-- Otherwise, we may have to revert to using writeString().
				writePlainUrlValue(v)
			end

			write(")")

		elseif token.type == "badUrl" then
			if options.strict then
				error("[css] BAD_URL token at position "..i..".")
			else
				print("[css] Warning: BAD_URL token at position "..i..".")
				write("url()")
			end

		elseif token.type == "unicodeRange" then
			local from = F("%X", token.from)
			local to   = F("%X", token.to)

			local preFrom = from :gsub("0+$", "")
			local preTo   = to   :gsub("F+$", "")

			write("U+")

			if from == to then
				write(from)

			-- U+12300-123FF => 123?? -- ok
			-- U+12390-123FF => 123/? -- fail
			-- U+01230-123FF => ////? -- fail
			elseif #from == #to and preFrom == preTo then
				write(preFrom)
				write(("?"):rep(#from-#preFrom))

			else
				write(from)
				write("-")
				write(to)
			end

		elseif token.type == "whitespace" then
			write(token.value)

		elseif token.type == "comment" then
			assert(not token.value:find"%*/")
			write("/*")
			write(token.value)
			write("*/")

		elseif token.type == "hash" then
			write("#")
			writeName(token.value, (token.idType == "unrestricted"), canTrimBeforeNextToken(tokens, i))

		elseif token.type == "suffixMatch" then
			write("$=")
		elseif token.type == "substringMatch" then
			write("*=")
		elseif token.type == "prefixMatch" then
			write("^=")
		elseif token.type == "dashMatch" then
			write("|=")
		elseif token.type == "includeMatch" then
			write("~=")

		elseif token.type == "columnMatch" then
			write("||")

		elseif token.type == "comma" then
			write(",")

		elseif token.type == "colon" then
			write(":")

		elseif token.type == "semicolon" then
			write(";")

		elseif token.type == "cdo" then
			write("<!--")
		elseif token.type == "cdc" then
			write("-->")

		elseif token.type == "atKeyword" then
			write("@")
			writeName(token.value, false, canTrimBeforeNextToken(tokens, i))

		elseif token.type == "(" or token.type == ")" then
			write(token.type)
		elseif token.type == "[" or token.type == "]" then
			write(token.type)
		elseif token.type == "{" or token.type == "}" then
			write(token.type)

		elseif token.type == "delim" then
			write(token.value)
			if token.value == "\\" then  write("\n")  end

		else
			error("[css][internal] Unknown token type '"..tostring(token.type).."'.")
		end
	end

	return table.concat(out)
end



--==============================================================
--= Minimizer ==================================================
--==============================================================

local getNextToken, getNextNonWsToken, getNextNonWsOrSemicolonToken
local isPreceededBy
local mustSeparateTokens



function mustSeparateTokens(a, b, isInRule)
	local at, av = a.type, a.value
	local bt, bv = b.type, b.value
	return
		at == "ident" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"        or
			bt == "cdc"                 or
			bt == "("                   or
			not isInRule and ( -- :SpacingFix
				bt == "hash"  or
				bt == "colon" or
				bt == "delim" and bv == "."
			)
		)
		or at == "atKeyword" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"        or
			bt == "cdc"
		)
		or at == "hash" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"        or
			bt == "cdc"                 or
			bt == "("                   or
			not isInRule and ( -- :SpacingFix
				bt == "hash"  or
				bt == "colon" or
				bt == "delim" and bv == "."
			)
		)
		or at == "dimension" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"        or
			bt == "cdc"                 or
			bt == "("
		)
		or at == "delim" and av == "#" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"
		)
		-- or at == "delim" and av == "-" and ( -- :W3cVal
		-- 	bt == "ident"               or
		-- 	bt == "function"            or
		-- 	bt == "url"                 or
		-- 	bt == "badUrl"              or
		-- 	bt == "number"              or
		-- 	bt == "percentage"          or
		-- 	bt == "dimension"           or
		-- 	bt == "unicodeRange"
		-- )
		or at == "number" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"
		)
		or at == "delim" and av == "@" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "unicodeRange"
		)
		or at == "unicodeRange" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "delim" and bv == "?"
		)
		or at == "delim" and av == "." and (
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"
		)
		-- or at == "delim" and av == "+" and ( -- :W3cVal
		-- 	bt == "number"              or
		-- 	bt == "percentage"          or
		-- 	bt == "dimension"
		-- )
		or not isInRule and ( -- :SpacingFix
			at == "]" and (
				bt == "ident"
			)
		)

		or at == "delim" and bt == "delim" and (
			av == "$" and bv == "=" or
			av == "*" and bv == "=" or
			av == "^" and bv == "=" or
			av == "~" and bv == "=" or
			av == "|" and bv == "=" or
			av == "|" and bv == "|" or
			av == "/" and bv == "*"
		)

		-- Silence the W3C CSS validator. :W3cVal
		or at == "delim" and (av == "+" or av == "-")
		or bt == "delim" and (bv == "+" or bv == "-")
end



function getNextToken(tokens, i, dir)
	for i = i, (dir < 0 and 1 or #tokens), dir do
		local token = tokens[i]

		if token.type ~= "comment" then
			return token, i
		end
	end

	return nil
end

function getNextNonWsToken(tokens, i, dir)
	for i = i, (dir < 0 and 1 or #tokens), dir do
		local token = tokens[i]

		if token.type ~= "comment" and token.type ~= "whitespace" then
			return token, i
		end
	end

	return nil
end

function getNextNonWsOrSemicolonToken(tokens, i, dir)
	for i = i, (dir < 0 and 1 or #tokens), dir do
		local token = tokens[i]

		if token.type ~= "comment" and token.type ~= "whitespace" and token.type ~= "semicolon" then
			return token, i
		end
	end

	return nil
end



-- bool = isPreceededBy( tokens, tokIndex, matchSequence... )
-- Match sequences:
--  * [ doNotMatch=="!" ], tokenType
--  * [ doNotMatch=="!" ], tokenType=="atKeyword", tokenValue
--  * [ doNotMatch=="!" ], tokenType=="delim",     tokenValue
--  * [ doNotMatch=="!" ], tokenType=="ident",     tokenValue
-- Note that the traversal is going backwards.
local function isPreceededBy(tokens, tokIndex, ...)
	local argCount = select("#", ...)
	local argIndex = 1

	print("~~~~~~~~~~~~~~~~~~~~~~~~")
	print("isPreceededBy", argCount, "|", ...)

	while argIndex <= argCount do
		local token = tokens[tokIndex]
		if not token then  return false  end

		print("arg "..argIndex)

		if token.type ~= "comment" then
			local tokType = select(argIndex, ...)
			argIndex = argIndex+1

			local wantMatch = true
			if tokType == "!" then
				wantMatch = false

				tokType = select(argIndex, ...)
				argIndex = argIndex+1
			end

			print(wantMatch and "want:typ  " or "nowant:typ", tokType)
			print("got:typ", token.type)

			if (token.type == tokType) ~= wantMatch then
				print("nope")
				return false
			end

			if isAny(tokType, "ident","delim","atKeyword") then
				print(wantMatch and "want:val  " or "nowant:val", select(argIndex, ...))
				print("got:val", token.value)
				if (token.value == select(argIndex, ...)) ~= wantMatch then
					print("nope")
					return false
				end

				argIndex = argIndex+1
			end
		end

		tokIndex = tokIndex-1
	end

	print("YYEEESSS")
	return true
end



-- css    = minimize( css    [, options ] )
-- tokens = minimize( tokens [, options ] )
function css.minimize(tokensIn, options)
	-- @Incomplete:
	-- * Less prop values:
	--      "background-position:0 0 0 0"  =>  "background-position:0 0"
	--      "margin:0 0 0 0"  =>  "margin:0"
	-- * No empty rules:  "body div{}"  =>  ""
	-- * Simplify rgb colors:  "rgb(123,123,123)"  =>  "#7b7b7b"
	-- * Simplify opacity in colors:  "hsla(0,0,0,1)"/"rgba(0,0,0,1)"  => "hsla(0,0,0)"/"rgba(0,0,0)"
	-- * Unstring font names, if possible:  '"Arial"'  =>  'Arial'
	-- * Omit space after escape sometimes:  "4px\9 }"  =>  "4px\9}"
	-- * Maybe preserve space:  "src:url()format()"  =>  "src:url() format()"
	-- * Maybe don't replace NUL bytes:  "�"  =>  "\0 "
	-- * Do magical things with -ms-filter props. Ugh...
	-- * Don't always remove "%":
	--      "flex-basis:0;"  =>  "flex-basis:0%;"
	--      "flex:0;"  =>  "flex:0%;"

	if type(tokensIn) == "string" then
		return css.serializeAndMinimize(css.tokenize(tokensIn), options)
	end

	local tokensOut      = {}
	local tokenSourceSet = {}
	local scopeStack     = {{name="file"}}

	local function enter(scope)
		assert(scope.name)
		assert(scope.exit)
		table.insert(scopeStack, scope)
	end

	local function exit(symbol, i)
		local scope = table.remove(scopeStack)
		if scope.exit ~= symbol then
			error(F(
				"[css] Unbalanced scopes at position %d. (expected to exit '%s' scope with '%s', but got '%s')",
				i, scope.name, tostring(scope.exit), symbol
			), 2)
		end
	end

	local function isAt(scopeName)
		return scopeStack[#scopeStack].name == scopeName
	end
	local function isInside(scopeName)
		for _, scope in ipairs(scopeStack) do
			if scope.name == scopeName then  return true  end
		end
		return false
	end

	-- Create minimized token array.
	--------------------------------

	local function add(token)
		if tokenSourceSet[token] then
			local tokSource = token
			token = {}

			for k, v in pairs(tokSource) do
				token[k] = v
			end
		end

		table.insert(tokensOut, token)
		return token
	end

	local currentProperty  = nil
	local currentAtKeyword = nil

	local keepNextComment  = false
	local colonsAfterProp  = 0

	for i, tokIn in ipairs(tokensIn) do
		local tokType = tokIn.type

		tokenSourceSet[tokIn] = true

		if tokType == "dimension" or tokType == "percentage" then
			if
				options.autoZero ~= false
				and tokIn.value == 0
				and not (isInside"function" or isInside"(" or isInside"@keyframes")
			then
				add(newTokenNumber(0))

			else
				add(tokIn)
			end

		elseif tokType == "number" then
			add(tokIn)

		elseif tokType == "function" then
			local tokOut = add(tokIn)

			-- Lower-case function names, except for crazy things like filter:progid:DXImageTransform.Microsoft.matrix().
			if colonsAfterProp == 1 or isAt"file" or isAt"@media" or isAt"@supports" or isAt"@document" then
				tokOut.value = tokOut.value:lower()

				-- Fix letter case for rotateX etc.
				if
					substrCompareAsciiChar(tokOut.value, #tokOut.value, "xyz")
					and isAny(tokOut.value:sub(1, #tokOut.value-1), "rotate","scale","skew","translate")
				then
					tokOut.value = tokOut.value:gsub(".$", string.upper)
				end
			end

			table.insert(scopeStack, {name="function", exit=")"})

		elseif tokType == "ident" then
			local tokPrev = getNextToken(tokensOut, #tokensOut, -1)
			local tokNext = getNextNonWsToken(tokensIn, i+1, 1)

			if isAt"rule" and not currentProperty then
				local tokOut = add(tokIn)
				tokOut.value = tokOut.value:lower()
				currentProperty = tokOut.value

			elseif currentAtKeyword == "media" then
				-- Is this ok or must we check for specific keywords, like "screen" etc.?
				local tokOut = add(tokIn)
				tokOut.value = tokOut.value:lower()

			elseif tokPrev and tokPrev.type == "colon" and not isAt"rule" then
				-- Both ':' and '::'.
				local tokOut = add(tokIn)
				tokOut.value = tokOut.value:lower()

			elseif
				currentProperty
				and #tokIn.value == 4 and tokIn.value:lower() == "none"
				and isAny(currentProperty, "background","border","border-top","border-right","border-bottom","border-left")
				and (not tokNext or tokNext.type == "semicolon" or tokNext.type == "}")
			then
				add(newTokenNumber(0))

			else
				add(tokIn)
			end

		elseif tokType == "string" then
			add(tokIn)

		elseif tokType == "badString" then
			if options.strict then
				error("[css] BAD_STRING token at position "..i..".")
			else
				print("[css] Warning: BAD_STRING token at position "..i..".")
				add(tokIn)
			end

		elseif tokType == "url" then
			add(tokIn)

		elseif tokType == "badUrl" then
			if options.strict then
				error("[css] BAD_URL token at position "..i..".")
			else
				print("[css] Warning: BAD_URL token at position "..i..".")
				add(tokIn)
			end

		elseif tokType == "unicodeRange" then
			add(tokIn)

		elseif tokType == "whitespace" then

			-- Note: There shouldn't ever be two whitespace tokens after
			-- each other (I think), but there could be two or more
			-- whitespace tokens with comments in-between.
			local tokPrev = getNextToken(tokensOut, #tokensOut, -1)
			local tokNext = getNextNonWsToken(tokensIn, i+1, 1)

			if
				tokPrev and tokNext and (
					(
						mustSeparateTokens(tokPrev, tokNext, isInside"rule")
						or tokensOut[#tokensOut].type == "number" and (
							tokNext.type == "dimension"
							or tokNext.type == "percentage"
							or tokNext.type == "number"
						)
					)
					and not (
						tokensOut[#tokensOut].type == "comment"
						and tokensIn[i+1].type == "comment"
						and tokensIn[i+1].value:find"^!"
					)
				)
			then
				add(newTokenWhitespace(" "))
			end

		elseif tokType == "comment" then
			local tokPrev = getNextToken(tokensOut, #tokensOut, -1) -- Could be whitespace.

			-- Important comment.
			if substrCompareAsciiChar(tokIn.value, 1, "!") then
				add(tokIn)

			-- Child selector hack for IE7 and below.
			-- html >/**/ body p {
			elseif tokPrev and tokPrev.type == "delim" and tokPrev.value == ">" then
				add(newTokenComment())

			-- Comment parsing hack for IE Mac.
			-- /*\*/ hidden /**/
			elseif tokIn.value:find"\\$" then
				add(newTokenComment("\\"))
				keepNextComment = true

			elseif keepNextComment then
				add(newTokenComment())
			end

		elseif tokType == "hash" then
			if currentProperty and isAt"rule" then
				local tokOut = add(tokIn)
				tokOut.value = tokOut.value:lower()

				-- Note: It seems CSS4 will add #RRGGBBAA and #RGBA formats, so this code will probably have to be updated.
				if #tokOut.value == 6 then
					if
						tokOut.value:byte(1) == tokOut.value:byte(2) and
						tokOut.value:byte(3) == tokOut.value:byte(4) and
						tokOut.value:byte(5) == tokOut.value:byte(6)
					then
						tokOut.value = tokOut.value:gsub("(.).", "%1")
					end

				elseif #tokOut.value ~= 3 then
					print("Warning: Color value looks incorrect: #"..tokOut.value)
				end

			else
				add(tokIn)
			end

		elseif tokType == "suffixMatch" then
			add(tokIn)
		elseif tokType == "substringMatch" then
			add(tokIn)
		elseif tokType == "prefixMatch" then
			add(tokIn)
		elseif tokType == "dashMatch" then
			add(tokIn)
		elseif tokType == "includeMatch" then
			add(tokIn)

		elseif tokType == "columnMatch" then
			add(tokIn)

		elseif tokType == "comma" then
			add(tokIn)

		elseif tokType == "colon" then
			add(tokIn)

			if currentProperty and isAt"rule" then
				colonsAfterProp = colonsAfterProp+1
			end

		elseif tokType == "semicolon" then
			if isAt"rule" then
				currentProperty = nil
				colonsAfterProp = 0
			end

			currentAtKeyword = nil -- Possible end of @charset ""; or similar.

			local tokPrev = getNextNonWsOrSemicolonToken(tokensOut, #tokensOut, -1)
			local tokNext = getNextNonWsToken(tokensIn, i+1, 1)

			if
				tokNext and tokNext.type ~= "}" and tokNext.type ~= "semicolon"
				and not (tokPrev and tokPrev.type == "{")
			then
				add(tokIn)
			end

		elseif tokType == "cdo" then
			add(tokIn)
		elseif tokType == "cdc" then
			add(tokIn)

		elseif tokType == "atKeyword" then
			local tokOut = add(tokIn)
			tokOut.value = tokOut.value:lower()

			currentAtKeyword = tokOut.value

		elseif tokType == "(" then
			add(tokIn)
			enter{ name="(", exit=")" }

		elseif tokType == ")" then
			add(tokIn)
			exit(")", i)

		elseif tokType == "[" then
			add(tokIn)
			enter{ name="[", exit="]" }

		elseif tokType == "]" then
			add(tokIn)
			exit("]", i)

		elseif tokType == "{" then
			add(tokIn)

			if not currentAtKeyword then
				enter{ name="rule", exit="}" }

			-- Note: @document is experimental and Firefox-only as of 2018-07-18.
			elseif isAny(currentAtKeyword, "media","supports","document") then
				enter{ name="condGroup", exit="}" }

			elseif isAny(currentAtKeyword, "font-face","page") then
				enter{ name="rule", exit="}" }

			else
				enter{ name="@"..currentAtKeyword, exit="}" }
			end

			currentAtKeyword = nil

		elseif tokType == "}" then
			if isAt"rule" then
				currentProperty = nil
				colonsAfterProp = 0
			end

			add(tokIn)
			exit("}", i)

		elseif tokType == "delim" then
			add(tokIn)

		else
			error("[css][internal] Unknown token type '"..tostring(tokType).."'.")
		end
		assert(#scopeStack >= 1)
	end

	-- assert(#scopeStack == 1) -- DEBUG: EOF can appear inside a scope.

	-- Fix IE6 :first-line and :first-letter.
	-- https://github.com/stoyan/yuicompressor/blob/master/ports/js/cssmin.js
	--------------------------------
	for i = #tokensOut-1, 2, -1 do
		local token = tokensOut[i]
		if
			tokensOut[i-1] and tokensOut[i+1]
			and tokensOut[i].type == "ident" and isAny(tokensOut[i].value, "first-letter","first-line")
			and tokensOut[i-1].type == "colon"
			and (not tokensOut[i-2] or tokensOut[i-2].type ~= "colon")
			and tokensOut[i+1].type ~= "whitespace"
		then
			table.insert(tokensOut, i+1, newTokenWhitespace(" "))
		end
			-- isPreceededBy(tokensOut, #tokensOut, "ident","first-letter", "colon", "!","colon") or
			-- isPreceededBy(tokensOut, #tokensOut, "ident","first-line",   "colon", "!","colon")
	end

	-- Put @charset first.
	--------------------------------

	local charset = nil

	for i = #tokensOut-1, 1, -1 do
		if
			tokensOut[i+1]
			and tokensOut[i].type == "atKeyword" and tokensOut[i].value == "charset"
			and tokensOut[i+1].type == "string"
			and (not tokensOut[i+2] or tokensOut[i+2].type == "semicolon")
		then
			if charset and tokensOut[i+1].value ~= charset then
				if options.strict then
					error(F("[css] Conflicting @charset values. ('%s' and '%s')", tokensOut[i+1].value, charset))
				else
					print(F("[css] Warning: Conflicting @charset values. ('%s' and '%s')", tokensOut[i+1].value, charset))
				end
			end

			charset = tokensOut[i+1].value -- Note: We want the first charset value, and we're going backwards.

			table.remove(tokensOut, i+1)
			table.remove(tokensOut, i)

			if tokensOut[i] then
				table.remove(tokensOut, i)
			end
		end
	end

	if charset then
		table.insert(tokensOut, 1, {type="atKeyword", value="charset"})
		table.insert(tokensOut, 2, newTokenWhitespace(" "))
		table.insert(tokensOut, 3, {type="string", value=charset, quoteCharacter='"'})
		table.insert(tokensOut, 4, {type="semicolon"})
	end

	--------------------------------

	return tokensOut
end



--==============================================================
--= Tests ======================================================
--==============================================================



--[[
local function assertRange(from1, to1, from2, to2)
	if from1 then
		assert(to1)
		if from1 ~= from2 then
			error(tostring(from1).."-"..tostring(to1).." from="..tostring(from2), 2)
		end
		if to1 ~= to2 then
			error(tostring(from1).."-"..tostring(to1).." to="..tostring(to2), 2)
		end
	else
		assert(not to1)
		if from2 then
			error(tostring(from1).."-"..tostring(to1).." from="..tostring(from2), 2)
		end
		if to2 then
			error(tostring(from1).."-"..tostring(to1).." to="..tostring(to2), 2)
		end
	end
end

assertRange(1,   0,   matchWs("a c", 1))
assertRange(2,   2,   matchWs("a c", 2))
assertRange(2,   1,   matchWs("abc", 2))

-- print(".sÜи", utf8.codepoint(".sÜи", 1, 4))
assertRange(nil, nil, matchAlphaOrNonAscii("и.s.", #"и"+1))
assertRange(4,   4,   matchAlphaOrNonAscii("и.s.", #"и"+2))
assertRange(4,   5,   matchAlphaOrNonAscii("и.Ü.", #"и"+2))
assertRange(nil, nil, matchAlphaOrNonAscii(":7:", 2))

local token, ptr = consumeStringToken("a:'hel\\\nlo'", 4, "'")
assert(token.value == "hello", token.value)
assert(ptr == 12, ptr)

local token, ptr = consumeUrlToken("a:url(foo)", 7)
assert(token.value == "foo", token.value)
assert(ptr == 11, ptr)
local token, ptr = consumeUrlToken("a:url( 'foo' )", 7)
assert(token.value == "foo", token.value)
assert(ptr == 15, ptr)
local token, ptr = consumeUrlToken("a:url( 'fo\\\no' ", 8)
assert(token.value == "foo", token.value)
assert(ptr > 13, ptr)

local token, ptr = consumeUnicodeRangeToken(":12abCD; derp:", 2)
assert(token.from == 0x12ABCD, token.from)
assert(token.to   == 0x12ABCD, token.to)
assert(ptr        == 8,        ptr)
local token, ptr = consumeUnicodeRangeToken(":12??????; derp:", 2)
assert(token.from == 0x120000, token.from)
assert(token.to   == 0x12FFFF, token.to)
assert(ptr        == 8,        ptr)
local token, ptr = consumeUnicodeRangeToken("1234-5678", 1)
assert(token.from == 0x1234,   token.from)
assert(token.to   == 0x5678,   token.to)
assert(ptr        == 10,       ptr)
local token, ptr = consumeUnicodeRangeToken("12??-5678", 1)
assert(token.from == 0x1200,   token.from)
assert(token.to   == 0x12FF,   token.to)
assert(ptr        == 5,        ptr)

local cp, ptr = consumeEscape("\\001aBи789", 2)
assert(cp  == 0x1AB, cp)
assert(ptr == 7,     ptr)

local name, ptr = consumeName(":-foo;", 2)
assert(name == "-foo", name)
assert(ptr  == 6,      ptr)

local nRepr, n, nType, ptr = consumeNumber(":.6e+2;", 2)
assert(nRepr == ".6e+2",  nRepr)
assert(n     == .6e2,     n)
assert(nType == "number", nType)
assert(ptr   == 7,        ptr)

local ptr = consumeRemnantsOfBadUrl(":url('foo\n');", 10)
assert(ptr == 13, ptr)

print("[css] All tests passed!")
os.exit(1) -- Not a "normal" run, thus the 1.
--]]



--[[
local function timeIt(loops, f, ...)
	local clock = os.clock()
	for i = 1, loops do
		f(...)
	end
	return os.clock()-clock
end

-- ...
--]]



--==============================================================
--==============================================================
--==============================================================


return css
