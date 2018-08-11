--[[============================================================

	$Id: utf8.lua 179 2009-04-03 18:10:03Z pasta $

	Provides UTF-8 aware string functions implemented in pure Lua:
	- utf8.char( unicode, ... )
	- utf8.charlen( str, bytePos )
	- utf8.charpattern  // Not a function.
	- utf8.codes( str )
	- utf8.find( str, pattern, init, plain )
	- utf8.gensub( str, sliceLen )
	- utf8.gmatch( str, pattern, all )
	- utf8.gsub( str, pattern, repl, limit )
	- utf8.len( str )
	- utf8.match( str, pattern, init )
	- utf8.offset( str, i, bytePos )
	- utf8.offsetend( str, i, bytePos )
	- utf8.pos( str, bytePos )
	- utf8.reverse( str )
	- utf8.sub( str, i, j, bytePos )
	- utf8.codepoint( str, i, j, bytePos )

	All functions behave as their non UTF-8 aware counterparts with the exception that
	UTF-8 characters are used instead of bytes for all units, unless otherwise specified.

	Unchanged functions:
	- dump( str )
	- format( format, ... )
	- lower( str )
	- rep( str, times )
	- upper( str )

	Copyright © 2006-2007, Kyle Smith
	All rights reserved.

	Contributors:
		Alimov Stepan
		Marcus Thunström (2018-07-14)

	License:

	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:

	    * Redistributions of source code must retain the above copyright notice,
	      this list of conditions and the following disclaimer.
	    * Redistributions in binary form must reproduce the above copyright
	      notice, this list of conditions and the following disclaimer in the
	      documentation and/or other materials provided with the distribution.
	    * Neither the name of the author nor the names of its contributors may be
	      used to endorse or promote products derived from this software without
	      specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
	AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
	IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
	FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
	DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
	SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
	OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
	OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	ABNF from RFC 3629:

	UTF8-octets = *( UTF8-char )
	UTF8-char   = UTF8-1 / UTF8-2 / UTF8-3 / UTF8-4
	UTF8-1      = %x00-7F
	UTF8-2      = %xC2-DF UTF8-tail
	UTF8-3      = %xE0 %xA0-BF UTF8-tail / %xE1-EC 2( UTF8-tail ) /
	              %xED %x80-9F UTF8-tail / %xEE-EF 2( UTF8-tail )
	UTF8-4      = %xF0 %x90-BF 2( UTF8-tail ) / %xF1-F3 3( UTF8-tail ) /
	              %xF4 %x80-8F 2( UTF8-tail )
	UTF8-tail   = %x80-BF

--============================================================]]

local sbyte    = string.byte
local schar    = string.char
local sdump    = string.dump
local sfind    = string.find
local sformat  = string.format
local slower   = string.lower
local srep     = string.rep
local ssub     = string.sub
local supper   = string.upper



--==============================================================

local utf8char
local utf8charbytes
local utf8codepoint
local utf8codes
local utf8find
local utf8gensub
local utf8gmatch
local utf8gsub
local utf8len
local utf8match
local utf8offset
local utf8pos
local utf8reverse
local utf8subAndBounds, utf8sub



-- Returns the number of bytes used by the UTF-8 character at byte i in str.
-- Also doubles as a UTF-8 character validator.
-- bytePos = utf8charbytes( str, i )
function utf8charbytes(s, i)
	i = i or 1

	if type(s) ~= "string" then
		error("bad argument #1 to 'utf8charbytes' (string expected, got "..type(s)..")", 2)
	end
	if type(i) ~= "number" then
		error("bad argument #2 to 'utf8charbytes' (number expected, got "..type(i)..")", 2)
	end

	local c = sbyte(s, i)
	if not c then  return nil  end

	-- Determine bytes needed for character, based on RFC 3629.
	-- Validate byte 1.
	if c > 0 and c <= 127 then
		-- UTF8-1.
		return 1

	elseif c >= 194 and c <= 223 then
		-- UTF8-2.
		local c2 = sbyte(s, i+1)

		if not c2 then
			error("UTF-8 string terminated early after position "..i.." (2-byte char)")
		end

		-- Validate byte 2.
		if c2 < 128 or c2 > 191 then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..")")
		end

		return 2

	elseif c >= 224 and c <= 239 then
		-- UTF8-3.
		local c2 = sbyte(s, i+1)
		local c3 = sbyte(s, i+2)

		if not c2 or not c3 then
			error("UTF-8 string terminated early after position "..i.." (3-byte char)")
		end

		-- Validate byte 2.
		if c == 224 and (c2 < 160 or c2 > 191) then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..")")
		elseif c == 237 and (c2 < 128 or c2 > 159) then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..")")
		elseif c2 < 128 or c2 > 191 then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..")")
		end

		-- Validate byte 3.
		if c3 < 128 or c3 > 191 then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..","..c3..")")
		end

		return 3

	elseif c >= 240 and c <= 244 then
		-- UTF8-4.
		local c2 = sbyte(s, i+1)
		local c3 = sbyte(s, i+2)
		local c4 = sbyte(s, i+3)

		if not c2 or not c3 or not c4 then
			error("UTF-8 string terminated early after position "..i.." (4-byte char)")
		end

		-- Validate byte 2.
		if     c == 240 and (c2 < 144 or c2 > 191) then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..")")
		elseif c == 244 and (c2 < 128 or c2 > 143) then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..")")
		elseif              (c2 < 128 or c2 > 191) then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..")")
		end

		-- Validate byte 3.
		if c3 < 128 or c3 > 191 then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..","..c3..")")
		end

		-- Validate byte 4.
		if c4 < 128 or c4 > 191 then
			error("invalid UTF-8 character at byte "..i.." ("..c..","..c2..","..c3..","..c4..")")
		end

		return 4

	else
		error("invalid UTF-8 character at byte "..i.." ("..c..")")
	end
end



-- Returns the number of characters in a UTF-8 string.
-- string.len
function utf8len(s)
	if type(s) ~= "string" then
		error("bad argument #1 to 'utf8len' (string expected, got "..type(s)..")", 2)
	end

	local bytePos    = 1
	local charLength = 0

	while bytePos <= #s do
		charLength = charLength+1
		bytePos = bytePos+utf8charbytes(s, bytePos)
	end

	return charLength
end



-- string.sub
function utf8sub(s, i, j, bytePos)
	return (utf8subAndBounds(s, i, j, bytePos))
end

function utf8subAndBounds(s, i, j, bytePos)
	j       = j or -1
	bytePos = bytePos or 1

	local charLen = (i >= 0 and j >= 0) or utf8len(s)
	local charPosStart = (i >= 0 and i or charLen+i+1)
	local charPosEnd   = (j >= 0 and j or charLen+j+1)

	-- Can't have start before end.
	if charPosStart > charPosEnd then  return ""  end

	-- Byte offsets to pass to string.sub().
	local byteStart = 1
	local byteEnd   = #s

	local charPos = 0

	while bytePos <= #s do
		charPos = charPos+1

		if charPos == charPosStart then
			byteStart = bytePos
		end

		bytePos = bytePos+utf8charbytes(s, bytePos)

		if charPos == charPosEnd then
			byteEnd = bytePos-1
			break
		end
	end

	if charPosStart > charPos then  byteStart = #s+1  end
	if charPosEnd   < 1       then  byteEnd   = 0     end

	return ssub(s, byteStart, byteEnd), byteStart, byteEnd
end



-- string.reverse
function utf8reverse(s)
	if type(s) ~= "string" then
		error("bad argument #1 to 'utf8reverse' (string expected, got "..type(s)..")", 2)
	end

	local bytePos   = #s
	local sReversed = ""
	local charLen, byte

	while bytePos > 0 do
		byte = sbyte(s, bytePos)

		while byte >= 128 and byte <= 191 do
			bytePos = bytePos-1
			byte    = sbyte(s, bytePos)
		end

		charLen   = utf8charbytes(s, bytePos)
		sReversed = sReversed..ssub(s, bytePos, bytePos+charLen-1) -- @Speed @Memory: Don't concaticate so much!
		bytePos   = bytePos-1
	end

	return sReversed
end



-- http://en.wikipedia.org/wiki/Utf8
-- http://developer.coronalabs.com/code/utf-8-conversion-utility
local bytes = {}

-- str = utf8.char( codepoint1, ... )
function utf8char(...)
	local bytePos = 1
	local cp

	for i = 1, select("#", ...) do
		cp = select(i, ...)

		if cp <= 0x7F then
			bytes[bytePos] = cp
			bytePos = bytePos+1

		elseif cp <= 0x7FF then
			bytes[bytePos  ] = 0xC0 + math.floor(cp / 0x40)
			bytes[bytePos+1] = 0x80 + cp % 0x40
			bytePos = bytePos+2

		elseif cp <= 0xFFFF then
			bytes[bytePos  ] = 0xE0 + math.floor(cp / 0x1000)
			bytes[bytePos+1] = 0x80 + math.floor(cp / 0x40) % 0x40
			bytes[bytePos+2] = 0x80 + cp % 0x40
			bytePos = bytePos+3

		elseif cp <= 0x10FFFF then
			bytes[bytePos+3] = 0x80 + cp % 0x40
			cp               = math.floor(cp / 0x40)
			bytes[bytePos+2] = 0x80 + cp % 0x40
			cp               = math.floor(cp / 0x40)
			bytes[bytePos+1] = 0x80 + cp % 0x40
			cp               = math.floor(cp / 0x40)
			bytes[bytePos  ] = 0xF0 + cp
			bytePos = bytePos+4

		else
			error("Unicode cannot be greater than U+10FFFF. ("..cp..")")
		end
	end

	return schar(unpack(bytes, 1, bytePos-1))
end



local SHIFT_6  = 2^6
local SHIFT_12 = 2^12
local SHIFT_18 = 2^18

-- string.byte
function utf8codepoint(s, i, j, bytePos)
	i = i or 1
	j = j or i
	if i > j then  return --[[void]]  end

	local c, charLen

	if bytePos then
		if bytePos > #s then  return  end

		charLen = utf8charbytes(s, bytePos)
		c       = ssub(s, bytePos, bytePos+charLen-1)
	else
		c, bytePos = utf8subAndBounds(s, i, i)
		charLen    = #c
	end

	local cp

	if charLen == 1 then
		cp = sbyte(c)

	elseif charLen == 2 then
		local byte1, byte2 = sbyte(c, 1, 2)
		local cp1,   cp2   = byte1-0xC0, byte2-0x80
		cp = cp1*SHIFT_6 + cp2

	elseif charLen == 3 then
		local byte1, byte2, byte3 = sbyte(c, 1, 3)
		local cp1,   cp2,   cp3   = byte1-0xE0, byte2-0x80, byte3-0x80
		cp = cp1*SHIFT_12 + cp2*SHIFT_6 + cp3

	elseif charLen == 4 then
		local byte1, byte2, byte3, byte4 = sbyte(c, 1, 4)
		local cp1,   cp2,   cp3,   cp4   = byte1-0xF0, byte2-0x80, byte3-0x80, byte4-0x80
		cp = cp1*SHIFT_18 + cp2*SHIFT_12 + cp3*SHIFT_6 + cp4
	end

	return cp, utf8codepoint(s, i+1, j, bytePos+charLen)
end



-- Returns an iterator which returns the next substring and its byte interval.
-- for slice, byteStart, byteEnd in utf8.gensub( str [, sliceLen=1 ] ) do
function utf8gensub(s, sliceLen)
	sliceLen = sliceLen or 1

	local bytePos = 1

	return function(skipBytes)
		if skipBytes then  bytePos = bytePos+skipBytes  end

		local from = bytePos

		for i = 1, sliceLen do
			if bytePos > #s then  return  end

			bytePos = bytePos+utf8charbytes(s, bytePos)
		end

		local to    = bytePos-1
		local slice = ssub(s, from, to)

		return slice, from, to
	end
end

local function binsearch(sortedTable, item, comp)
	local head, tail = 1, #sortedTable
	local mid = math.floor((head+tail)/2)

	if not comp then
		while tail-head > 1 do
			if sortedTable[tonumber(mid)] > item then
				tail = mid
			else
				head = mid
			end
			mid = math.floor((head+tail)/2)
		end
	end

	if sortedTable[tonumber(head)] == item then
		return true, tonumber(head)

	elseif sortedTable[tonumber(tail)] == item then
		return true, tonumber(tail)

	else
		return false
	end
end
local function classMatchGenerator(class, plain)
	local codes       = {}
	local ranges      = {}
	local ignore      = false
	local range       = false
	local firstletter = true
	local unmatch     = false

	local it = utf8gensub(class)

	local skip
	for c, _, be in it do
		skip = be
		if not ignore and not plain then
			if c == "%" then
				ignore = true
			elseif c == "-" then
				table.insert(codes, utf8codepoint(c))
				range = true
			elseif c == "^" then
				if not firstletter then
					error("!!!")
				else
					unmatch = true
				end
			elseif c == "]" then
				break
			else
				if not range then
					table.insert(codes, utf8codepoint(c))
				else
					table.remove(codes) -- Removing '-'.
					table.insert(ranges, {table.remove(codes), utf8codepoint(c)})
					range = false
				end
			end
		elseif ignore and not plain then
			if c == "a" then -- %a: Represents all ASCII letters.
				table.insert(ranges, {65, 90})  -- A - Z
				table.insert(ranges, {97, 122}) -- a - z
			elseif c == "c" then -- %c: Represents all control characters.
				table.insert(ranges, {0, 31})
				table.insert(codes, 127)
			elseif c == "d" then -- %d: Represents all digits.
				table.insert(ranges, {48, 57}) -- 0 - 9
			elseif c == "g" then -- %g: Represents all printable characters except space.
				table.insert(ranges, {1, 8})
				table.insert(ranges, {14, 31})
				table.insert(ranges, {33, 132})
				table.insert(ranges, {134, 159})
				table.insert(ranges, {161, 5759})
				table.insert(ranges, {5761, 8191})
				table.insert(ranges, {8203, 8231})
				table.insert(ranges, {8234, 8238})
				table.insert(ranges, {8240, 8286})
				table.insert(ranges, {8288, 12287})
			elseif c == "l" then -- %l: Represents all lowercase ASCII letters.
				table.insert(ranges, {97, 122}) -- a - z
			elseif c == "p" then -- %p: Represents all ASCII punctuation characters.
				table.insert(ranges, {33, 47})
				table.insert(ranges, {58, 64})
				table.insert(ranges, {91, 96})
				table.insert(ranges, {123, 126})
			elseif c == "s" then -- %s: Represents all space characters.
				table.insert(ranges, {9, 13})
				table.insert(codes, 32)
				table.insert(codes, 133)
				table.insert(codes, 160)
				table.insert(codes, 5760)
				table.insert(ranges, {8192, 8202})
				table.insert(codes, 8232)
				table.insert(codes, 8233)
				table.insert(codes, 8239)
				table.insert(codes, 8287)
				table.insert(codes, 12288)
			elseif c == "u" then -- %u: Represents all uppercase ASCII letters.
				table.insert(ranges, {65, 90})  -- A - Z
			elseif c == "w" then -- %w: Represents all alphanumeric ASCII characters.
				table.insert(ranges, {48, 57})  -- 0 - 9
				table.insert(ranges, {65, 90})  -- A - Z
				table.insert(ranges, {97, 122}) -- a - z
			elseif c == "x" then -- %x: Represents all hexadecimal digits.
				table.insert(ranges, {48, 57})  -- 0 - 9
				table.insert(ranges, {65, 70})  -- A - F
				table.insert(ranges, {97, 102}) -- a - f
			else
				if not range then
					table.insert(codes, utf8codepoint(c))
				else
					table.remove(codes) -- Removing '-'.
					table.insert(ranges, {table.remove(codes), utf8codepoint(c)})
					range = false
				end
			end
			ignore = false
		else
			if not range then
				table.insert(codes, utf8codepoint(c))
			else
				table.remove(codes) -- Removing '-'.
				table.insert(ranges, {table.remove(codes), utf8codepoint(c)})
				range = false
			end
			ignore = false
		end

		firstletter = false
	end

	table.sort(codes)

	local function inRanges(charCode)
		for _,r in ipairs(ranges) do
			if r[1] <= charCode and charCode <= r[2] then
				return true
			end
		end
		return false
	end
	if not unmatch then
		return function(charCode)
			return binsearch(codes, charCode) or inRanges(charCode)
		end, skip
	else
		return function(charCode)
			return charCode ~= -1 and not (binsearch(codes, charCode) or inRanges(charCode))
		end, skip
	end
end



local cache      = setmetatable({}, {__mode="kv"})
local cachePlain = setmetatable({}, {__mode="kv"})

local function matcherGenerator(pat, plain)
	local matcher = {functions={}, captures={}}

	if not plain then
		cache[pat] = matcher
	else
		cachePlain[pat] = matcher
	end

	local function simple(func)
		return function(cC)
			if func(cC) then
				matcher:nextFunc()
				matcher:nextStr()
			else
				matcher:reset()
			end
		end
	end
	local function star(func)
		return function(cC)
			if func(cC) then
				matcher:fullResetOnNextFunc()
				matcher:nextStr()
			else
				matcher:nextFunc()
			end
		end
	end
	local function minus(func)
		return function(cC)
			if func(cC) then
				matcher:fullResetOnNextStr()
			end
			matcher:nextFunc()
		end
	end
	local function question(func)
		return function(cC)
			if func(cC) then
				matcher:fullResetOnNextFunc()
				matcher:nextStr()
			end
			matcher:nextFunc()
		end
	end

	local function capture(id)
		return function(_)
			local l        = matcher.captures[id][2]-matcher.captures[id][1]
			local captured = utf8sub(matcher.string, matcher.captures[id][1], matcher.captures[id][2])
			local check    = utf8sub(matcher.string, matcher.str, matcher.str+l)

			if captured == check then
				for _ = 0, l do
					matcher:nextStr()
				end
				matcher:nextFunc()

			else
				matcher:reset()
			end
		end
	end
	local function captureStart(id)
		return function(_)
			matcher.captures[id][1] = matcher.str
			matcher:nextFunc()
		end
	end
	local function captureStop(id)
		return function(_)
			matcher.captures[id][2] = matcher.str-1
			matcher:nextFunc()
		end
	end

	local function balancer(str)
		local sum  = 0
		local bc   = utf8sub(str, 1, 1)
		local ec   = utf8sub(str, 2, 2)
		local skip = #bc+#ec

		bc, ec = utf8codepoint(bc), utf8codepoint(ec)

		return function(cC)
			if cC == ec and sum > 0 then
				sum = sum-1
				if sum == 0 then
					matcher:nextFunc()
				end
				matcher:nextStr()
			elseif cC == bc then
				sum = sum+1
				matcher:nextStr()
			else
				if sum == 0 or cC == -1 then
					sum = 0
					matcher:reset()
				else
					matcher:nextStr()
				end
			end
		end, skip
	end

	matcher.functions[1] = function(_)
		matcher:fullResetOnNextStr()
		matcher.seqStart = matcher.str
		matcher:nextFunc()
		if (matcher.str > matcher.startStr and matcher.fromStart) or matcher.str >= matcher.stringLen then
			matcher.stop = true
			matcher.seqStart = nil
		end
	end

	local ignore = false
	local skip   = nil
	local lastFunc

	local it = (function()
		local gen = utf8gensub(pat)
		return function()
			return gen(skip)
		end
	end)()

	local cs = {}

	for c, bs, be in it do
		skip = nil
		if plain then
			table.insert(matcher.functions, simple(classMatchGenerator(c, plain)))
		else
			if ignore then
				if sfind("123456789", c, 1, true) then
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
						lastFunc = nil
					end
					table.insert(matcher.functions, capture(tonumber(c)))
				elseif c == "b" then
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
						lastFunc = nil
					end
					local b
					b, skip = balancer(ssub(pat, be+1, be+9))
					table.insert(matcher.functions, b)
				else
					lastFunc = classMatchGenerator("%"..c)
				end
				ignore = false
			else
				if c == "*" then
					if lastFunc then
						table.insert(matcher.functions, star(lastFunc))
						lastFunc = nil
					else
						error("invalid pat after "..ssub(pat, 1, bs))
					end
				elseif c == "+" then
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
						table.insert(matcher.functions, star(lastFunc))
						lastFunc = nil
					else
						error("invalid pat after "..ssub(pat, 1, bs))
					end
				elseif c == "-" then
					if lastFunc then
						table.insert(matcher.functions, minus(lastFunc))
						lastFunc = nil
					else
						error("invalid pat after "..ssub(pat, 1, bs))
					end
				elseif c == "?" then
					if lastFunc then
						table.insert(matcher.functions, question(lastFunc))
						lastFunc = nil
					else
						error("invalid pat after "..ssub(pat, 1, bs))
					end
				elseif c == "^" then
					if bs == 1 then
						matcher.fromStart = true
					else
						error("invalid pat after "..ssub(pat, 1, bs))
					end
				elseif c == "$" then
					if be == #pat then
						matcher.toEnd = true
					else
						error("invalid pat after "..ssub(pat, 1, bs))
					end
				elseif c == "[" then
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
					end
					lastFunc, skip = classMatchGenerator(ssub(pat, be+1))
				elseif c == "(" then
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
						lastFunc = nil
					end
					local matchCaps = matcher.captures
					table.insert(matchCaps, {})
					table.insert(cs, #matchCaps)
					table.insert(matcher.functions, captureStart(cs[#cs]))
					if ssub(pat, be+1, be+1) == ")" then  matchCaps[#matchCaps].empty = true  end
				elseif c == ")" then
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
						lastFunc = nil
					end
					local cap = table.remove(cs)
					if not cap then
						error("invalid capture: '(' missing")
					end
					table.insert(matcher.functions, captureStop(cap))
				elseif c == "." then
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
					end
					lastFunc = function(cC) return cC ~= -1 end
				elseif c == "%" then
					ignore = true
				else
					if lastFunc then
						table.insert(matcher.functions, simple(lastFunc))
					end
					lastFunc = classMatchGenerator(c)
				end
			end
		end
	end
	if #cs > 0 then
		error("invalid capture: ')' missing")
	end
	if lastFunc then
		table.insert(matcher.functions, simple(lastFunc))
	end

	table.insert(matcher.functions, function()
		if matcher.toEnd and matcher.str ~= matcher.stringLen then
			matcher:reset()
		else
			matcher.stop = true
		end
	end)

	matcher.nextFunc = function(self)
		self.func = self.func+1
	end
	matcher.nextStr = function(self)
		self.str = self.str+1
	end
	matcher.strReset = function(self)
		local oldReset = self.reset
		local str      = self.str

		self.reset = function(s)
			s.str = str
			s.reset = oldReset
		end
	end
	matcher.fullResetOnNextFunc = function(self)
		local oldReset = self.reset
		local func     = self.func +1
		local str      = self.str

		self.reset = function(s)
			s.func  = func
			s.str   = str
			s.reset = oldReset
		end
	end
	matcher.fullResetOnNextStr = function(self)
		local oldReset = self.reset
		local str      = self.str+1
		local func     = self.func

		self.reset = function(s)
			s.func = func
			s.str = str
			s.reset = oldReset
		end
	end

	matcher.process = function(self, str, start)
		start = start or 1

		self.func      = 1
		self.startStr  = start >= 0 and start or utf8len(str)+start+1
		self.seqStart  = self.startStr
		self.str       = self.startStr
		self.stringLen = utf8len(str)+1
		self.string    = str
		self.stop      = false

		self.reset = function(s)
			s.func = 1
		end

		local c
		while not self.stop do
			if self.str < self.stringLen then
				c = utf8sub(str, self.str,self.str)
				self.functions[self.func](utf8codepoint(c))
			else
				self.functions[self.func](-1)
			end
		end

		if self.seqStart then
			local captures = {}
			for _,pair in pairs(self.captures) do
				if pair.empty then
					table.insert(captures, pair[1])
				else
					table.insert(captures, utf8sub(str, pair[1], pair[2]))
				end
			end
			return self.seqStart, self.str-1, unpack(captures)
		end
	end

	return matcher
end

-- string.find
function utf8find(s, pat, init, plain)
	local matcher = cache[pat] or matcherGenerator(pat, plain)
	return matcher:process(s, init)
end



-- string.match
function utf8match(s, pat, init)
	init = init or 1

	local found = {utf8find(s, pat, init)}

	if found[1] then
		if found[3] then
			return unpack(found, 3)
		end

		return utf8sub(s, found[1], found[2])
	end
end



-- string.gmatch
function utf8gmatch(s, pat, includeRange)
	pat = utf8sub(pat, 1, 1) ~= "^" and pat or "%"..pat

	local lastChar = 1

	return function()
		local found = {utf8find(s, pat, lastChar)}

		if found[1] then
			lastChar = found[2]+1

			if found[includeRange and 1 or 3] then
				return unpack(found, includeRange and 1 or 3)
			end

			return utf8sub(s, found[1], found[2])
		end
	end
end



local function replace(repl, args)
	local ret = ""

	if type(repl) == "string" then
		local ignore = false
		local num
		for c in utf8gensub(repl) do
			if not ignore then
				if c == "%" then
					ignore = true
				else
					ret = ret..c
				end
			else
				num = tonumber(c)
				if num then
					ret = ret..args[num]
				else
					ret = ret..c
				end
				ignore = false
			end
		end

	elseif type(repl) == "table" then
		ret = repl[args[1] or args[0]] or ""

	elseif type(repl) == "function" then
		if #args > 0 then
			ret = repl(unpack(args, 1)) or ""
		else
			ret = repl(args[0]) or ""
		end
	end

	return ret
end

-- string.gsub
function utf8gsub(s, pat, repl, limit)
	limit = limit or -1

	local ret     = ""
	local prevEnd = 1
	local it      = utf8gmatch(s, pat, true)
	local found   = {it()}
	local n       = 0

	while #found > 0 and limit ~= n do
		local args = {[0] = utf8sub(s, found[1], found[2]), unpack(found, 3)}

		ret = ret
			.. utf8sub(s, prevEnd, found[1]-1)
			.. replace(repl, args)

		prevEnd = found[2]+1
		n       = n+1
		found   = {it()}
	end

	return ret..utf8sub(s, prevEnd), n
end



-- charPos = utf8.pos( str, bytePos )
function utf8pos(s, bytePosTarget)
	if type(s) ~= "string" then
		error("bad argument #1 to 'utf8pos' (string expected, got "..type(s)..")", 2)
	end
	if type(bytePosTarget) ~= "number" then
		error("bad argument #2 to 'utf8pos' (number expected, got "..type(bytePosTarget)..")", 2)
	end

	if bytePosTarget < 0 then
		bytePosTarget = #s+1+bytePosTarget
	end

	if bytePosTarget == 0 or bytePosTarget > #s then  return nil end

	local bytePos = 1
	local charPos = 0

	while bytePos <= bytePosTarget do
		charPos = charPos+1
		bytePos = bytePos+utf8charbytes(s, bytePos)
	end

	return charPos
end



-- bytePos = utf8.offset( str, charPos [, bytePos=1 ] )
-- charPos == 0 finds starting byte of character at bytePos.
function utf8offset(s, charPos, bytePos)
	bytePos = bytePos or 1

	if type(s) ~= "string" then
		error("bad argument #1 to 'utf8offset' (string expected, got "..type(s)..")", 2)
	end
	if type(charPos) ~= "number" then
		error("bad argument #2 to 'utf8offset' (number expected, got "..type(charPos)..")", 2)
	end
	if type(bytePos) ~= "number" then
		error("bad argument #3 to 'utf8offset' (number expected, got "..type(bytePos)..")", 2)
	end

	if bytePos < 0 then
		bytePos = #s+1+bytePos
	end

	-- Find starting byte of current character.
	if charPos == 0 then

		while true do
			local byte = s:byte(bytePos)

			if not byte then
				return nil -- End of string.

			elseif byte == 0 then
				error("invalid UTF-8 character at byte "..bytePos.." (NUL)", 2)

			elseif byte <= 127 then
				return bytePos

			else
				bytePos = bytePos-1
			end
		end

	-- Find starting byte of a character in front.
	elseif charPos > 0 then
		repeat
			charPos = charPos-1
			if charPos == 0 then  return bytePos  end

			bytePos = bytePos+utf8charbytes(s, bytePos)
		until bytePos > #s

		return nil -- charPos is outside the string.

	-- Find starting byte of a character behind.
	else
		error("negative charPos is not supported yet in 'utf8offset'.", 2)
	end
end

-- bytePos = utf8.offsetend( str, charPos [, bytePos=1 ] )
-- charPos == 0 finds ending byte of character at bytePos.
function utf8offsetend(s, charPos, bytePos)
	bytePos = utf8offset(s, charPos, bytePos)
	return bytePos and bytePos+utf8charbytes(s, bytePos)-1
end



-- for codepoint, fromByte, toByte, charPos in utf8codes( str ) do
function utf8codes(s)
	local bytePos = 1
	local charPos = 0

	return function(skipBytes)
		if skipBytes then  bytePos = bytePos+skipBytes  end

		if bytePos > #s then  return  end

		local cp   = utf8codepoint(s, 1, 1, bytePos)
		local from = bytePos

		bytePos = bytePos+utf8charbytes(s, bytePos)
		charPos = charPos+1

		return cp, from, bytePos-1, charPos
	end
end



--==============================================================

--[[ Tests.
assert(utf8char(46, 1080) == ".и")

assert(utf8charbytes("и") == 2)

local iter = utf8codes(".и")
assert(iter() == 46)
assert(iter() == 1080)
assert(iter() == nil)

local from, to = utf8find("1и aи", "a[Uи*]")
assert(from == 4)
assert(to   == 5)

local iter = utf8gensub(".и")
assert(iter() == ".")
assert(iter() == "и")
assert(iter() == nil)

local iter = utf8gmatch("9f.и", "..")
assert(iter() == "9f")
assert(iter() == ".и")
assert(iter() == nil)

assert(utf8gsub("9fи.", "[и9]", "字") == "字f字.")

assert(utf8len(".и.") == 3)

assert(utf8match("9fи.", "f[9и]") == "fи")

assert(utf8offset("и.", 2) == 3)
assert(utf8offset("и.", 99) == nil)
assert(utf8offsetend("и.", 1) == 2)

assert(utf8pos("и.", #"и"+1) == 2)
assert(utf8pos("и.", 99) == nil)

assert(utf8reverse("汉字漢字") == "字漢字汉")

assert(utf8sub("汉字漢字", 2, 3, 1) == "字漢")
assert(utf8sub("汉字漢字", 4, 5, 1) == "字")
assert(utf8sub("汉字漢字", 2, 2, #"汉"+1) == "漢")
assert(utf8sub("汉字漢字", 0, 99) == "汉字漢字")
assert(utf8sub("汉字漢字", 1, 1, 99) == "")
assert(utf8sub("汉字漢字", 1) == "汉字漢字")

assert(utf8codepoint("и") == 1080)
--]]

return {
	charpattern = "[\0-\x7F\xC2-\xF4][\x80-\xBF]*",

	char      = utf8char,
	charlen   = utf8charbytes,
	codes     = utf8codes,
	find      = utf8find,
	gensub    = utf8gensub,
	gmatch    = utf8gmatch,
	gsub      = utf8gsub,
	len       = utf8len,
	match     = utf8match,
	offset    = utf8offset,
	offsetend = utf8offsetend,
	pos       = utf8pos,
	reverse   = utf8reverse,
	sub       = utf8sub,
	codepoint = utf8codepoint,

	dump      = sdump,
	format    = sformat,
	lower     = slower,
	rep       = srep,
	upper     = supper,
}
