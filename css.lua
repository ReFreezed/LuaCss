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

	API:

	tokenize
		cssTokens = tokenize( cssString )

	serializeAndMinimize
		cssString = serializeAndMinimize( cssTokens [, strictErrors=false ] )

	minimize
		cssString = minimize( cssString [, strictErrors=false ] )

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

local css = {}



--==============================================================
--= Utilities ==================================================
--==============================================================

local findEnd
local getKeys
local indexOf
local inRange
local isValidCodepoint, isControlCharacterCodepoint, isSurrogateCodepoint
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
		return ("%03d%s"):format(#numStr, numStr)
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
	if not cp or cp < CP_NONASCII_START then  return nil, nil  end

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
		token = {type="number"}
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
			token.value          = utf8.char(unpack(cps))
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
			token.value          = utf8.char(unpack(cps))
			token.quoteCharacter = ""
			return token, ptr+1

		elseif substrCompareAsciiChar(s, ptr, " \t\n") then
			from, to = matchWs(s, ptr+1)
			ptr = to+1

			if ptr > #s or substrCompareAsciiChar(s, ptr, ")") then
				local token = {type="url"}
				token.value          = utf8.char(unpack(cps))
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
			return utf8.char(unpack(cps)), ptr
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

	local token = {type="comment"}
	token.value = comment

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
		elseif isNameStart(c1, 1) then
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

local formatNumberFromToken
local getNextToken, getNextNonWsToken, getNextNonWsOrSemicolonToken
local mustSeparateTokens



function formatNumberFromToken(token)
	local n    = token.value
	local repr = token.representation:gsub("^%+", "")

	local nStr = ("%.10g"):format(n)
	if #nStr > #repr or tonumber(nStr) ~= n then  nStr = repr  end

	nStr = nStr:gsub("0%.", ".")
	return nStr
end



function mustSeparateTokens(a, b)
	local at, av = a.type, a.value
	local bt, bv = b.type, b.value
	return
		(at == "ident" and (
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
		))
		or (at == "atKeyword" and (
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
		))
		or (at == "hash" and (
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
		))
		or (at == "dimension" and (
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
		))
		or (at == "delim" and av == "#" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"
		))
		-- or (at == "delim" and av == "-" and ( -- :W3cVal
		-- 	bt == "ident"               or
		-- 	bt == "function"            or
		-- 	bt == "url"                 or
		-- 	bt == "badUrl"              or
		-- 	bt == "number"              or
		-- 	bt == "percentage"          or
		-- 	bt == "dimension"           or
		-- 	bt == "unicodeRange"
		-- ))
		or (at == "number" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "unicodeRange"
		))
		or (at == "delim" and av == "@" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "url"                 or
			bt == "badUrl"              or
			-- bt == "delim" and bv == "-" or -- :W3cVal
			bt == "unicodeRange"
		))
		or (at == "unicodeRange" and (
			bt == "ident"               or
			bt == "function"            or
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"           or
			bt == "delim" and bv == "?"
		))
		or (at == "delim" and av == "." and (
			bt == "number"              or
			bt == "percentage"          or
			bt == "dimension"
		))
		-- or (at == "delim" and av == "+" and ( -- :W3cVal
		-- 	bt == "number"              or
		-- 	bt == "percentage"          or
		-- 	bt == "dimension"
		-- ))

		or (at == "delim" and bt == "delim" and (
			av == "$" and bv == "="     or
			av == "*" and bv == "="     or
			av == "^" and bv == "="     or
			av == "~" and bv == "="     or
			av == "|" and bv == "="     or
			av == "|" and bv == "|"     or
			av == "/" and bv == "*"
		))

		-- Silence the W3C CSS validator. :W3cVal
		or (at == "delim" and (av == "+" or av == "-"))
		or (bt == "delim" and (bv == "+" or bv == "-"))
end



function getNextToken(tokens, i, dir)
	for i = i+dir, (dir < 0 and 1 or #tokens), dir do
		local token = tokens[i]

		if token.type ~= "comment" then
			return token, i
		end
	end

	return nil
end

function getNextNonWsToken(tokens, i, dir)
	for i = i+dir, (dir < 0 and 1 or #tokens), dir do
		local token = tokens[i]

		if token.type ~= "comment" and token.type ~= "whitespace" then
			return token, i
		end
	end

	return nil
end

function getNextNonWsOrSemicolonToken(tokens, i, dir)
	for i = i+dir, (dir < 0 and 1 or #tokens), dir do
		local token = tokens[i]

		if token.type ~= "comment" and token.type ~= "whitespace" and token.type ~= "semicolon" then
			return token, i
		end
	end

	return nil
end



function css.serializeAndMinimize(tokens, strict)
	local out = {}

	local function write(v)
		table.insert(out, v)
	end

	-- https://drafts.csswg.org/cssom/#serialize-an-identifier
	local function writeName(v, unrestricted)
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
				local escape = ("\\%X "):format(cp)
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

		write(utf8.char(unpack(cps)))
	end

	-- https://drafts.csswg.org/cssom/#serialize-a-string
	function writeString(v)
		local hasDouble = v:find('"', 1, true) ~= nil
		local hasSingle = v:find("'", 1, true) ~= nil
		local quoteChar = hasDouble and not hasSingle and "'" or '"'

		v = v
			:gsub("%z", CHAR_REPLACE)
			:gsub("["..quoteChar.."\\]", "\\%0")
			:gsub("[\1-\31]", function(c)
				return ("\\%X "):format(c:byte())
			end)

		write(quoteChar)
		write(v)
		write(quoteChar)
	end

	function writePlainUrlValue(v)
		v = v
			:gsub("%z", CHAR_REPLACE)
			:gsub("\\", "\\\\")
			:gsub("[\1-\31]", function(c)
				return ("\\%X "):format(c:byte())
			end)

		write(v)
	end

	for i, token in ipairs(tokens) do
		if token.type == "dimension" then
			if token.value == 0 then
				write("0")
			else
				local nRepr = formatNumberFromToken(token)
				write(nRepr)

				-- Eliminate ambiguity with scientific notation.
				if not nRepr:find("n", 2, true) and token.unit:find"^[Ee][-+]?%d" then
					write("e0") -- W3C CSS validator still complains...
				end

				writeName(token.unit)
			end

		elseif token.type == "percentage" then
			if token.value == 0 then
				write("0")
			else
				write(formatNumberFromToken(token))
				write("%")
			end

		elseif token.type == "number" then
			write(formatNumberFromToken(token))

		elseif token.type == "function" then
			writeName(token.value)
			write("(")

		elseif token.type == "ident" then
			writeName(token.value)

		elseif token.type == "string" then
			writeString(token.value)

		elseif token.type == "badString" then
			if strict then
				error("[css] BAD_STRING token at position "..i..".")
			else
				print("[css] Warning: BAD_STRING token at position "..i..".")
				write('""')
			end

		elseif token.type == "url" then
			local v = token.value
			write("url(")

			if v == "" then
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
			if strict then
				error("[css] BAD_URL token at position "..i..".")
			else
				print("[css] Warning: BAD_URL token at position "..i..".")
				write("url()")
			end

		elseif token.type == "unicodeRange" then
			local from = ("%X"):format(token.from)
			local to   = ("%X"):format(token.to)

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

			-- Note: There shouldn't ever be two whitespace tokens after
			-- each other (I think), but there could be two or more
			-- whitespace tokens with comments in-between.
			local tokenPrev = getNextToken(tokens, i, -1)
			local tokenNext = getNextNonWsToken(tokens, i, 1)

			if tokenPrev and tokenNext and mustSeparateTokens(tokenPrev, tokenNext) then
				write(" ")
			end

		elseif token.type == "comment" then
			local tokenPrev = getNextToken(tokens, i, -1) -- Could be whitespace.

			if substrCompareAsciiChar(token.value, 1, "!") then
				write("/*")
				write(token.value)
				write("*/")

			-- Child selector hack for IE7 and below.
			-- html >/**/ body p {
			elseif tokenPrev and tokenPrev.type == "delim" and tokenPrev.value == ">" then
				write("/**/")
			end

		elseif token.type == "hash" then
			write("#")
			writeName(token.value, (token.idType == "unrestricted"))

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
			local tokenPrev = getNextNonWsOrSemicolonToken(tokens, i, -1)
			local tokenNext = getNextNonWsToken(tokens, i,  1)

			if
				tokenNext and tokenNext.type ~= "}" and tokenNext.type ~= "semicolon"
				and not (tokenPrev and tokenPrev.type == "{")
			then
				write(";")
			end

		elseif token.type == "cdo" then
			write("<!--")
		elseif token.type == "cdc" then
			write("-->")

		elseif token.type == "atKeyword" then
			write("@")
			writeName(token.value)

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
--= Additionals ================================================
--==============================================================



function css.minimize(s, strict)
	return css.serializeAndMinimize(css.tokenize(s), strict)
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
