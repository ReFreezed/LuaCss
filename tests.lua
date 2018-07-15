--[[============================================================
--=
--=  LuaCss Testsuite
--=
--============================================================]]

local cssLib = require"css"
local utf8   = require"utf8"



local css = [[
div {
	background: red;
}

html >/* <=IE7 */ body small { font-size: 0.6rem; }

.cls {;
	;;/**/ ;;color:#8e8e8e;;
	color: green;
	background-color: rgba(100, 150,200.0, .9);
	background: transparent url(/images/dog.png) 5.30e+0% 0px;
	background-image: url( "/images/Cat's fur (2)]].."\1"..[[.png" );
	border:1px solid #999;; ;
}

body main>span   { font-family: "Arial"; }
body  main  >  span   { border-radius: 5.0px; }

#id {
	font-size: 3rem;
}

/* comment asdf */

@media screen and (min-width: 1000px) {
	a::after {
		text-decoration: underline;
		content: 'A cat\'s what?';
	}
}

a[href]:hover {
	font-weight: 200;
}
a[href$=".png"] {}
a[href*='/images/'] {}
a[href^="https://"] {}
div[class|=top] {}
article[data-tags~=news] {}

section


{
	margin: 0;
	/*! important comment wthin a rule */
	padding: 5px;
}


body > * {

}

<!--
#wrapper{width:50%!important;}
-->

a.\#hash\1 tag\1  span { height: .8125e+2px; }

heading { margin-left:calc(20px + 1em)  ; /*-xxx-what: 5.2e0e4m;*/ }

@font-face {
	font-family: "Ampersand";
	src: local('Times New Roman');
	unicode-range: U+26, u+123-abcd, U+01a??, u+012300-123fF;
}

.badStuff {
	background-image: url(/dog
		house.png);
	font-family: "Arial
}
]]

print("=================================")
print(css)
print("=================================")



--[[ Load large CSS.
local file = assert(io.open("test.css", "rb"))
css = file:read"*a"
print((#css/1000).." kB")
file:close()
--]]



local clock        = os.clock()
local tokens       = cssLib.tokenize(css)
local tokenizeTime = os.clock()-clock

--[[ Print classes.
local classSet = {}
for i, token in ipairs(tokens) do
	if i > 1 and token.type == "ident" and tokens[i-1].value == "." then
		classSet[token.value] = true
	end
end
local classes = {}
for k in pairs(classSet) do
	table.insert(classes, k)
end
table.sort(classes)
for i, class in ipairs(classes) do
	print("class", i, class)
end
--]]

-- [[ Print tokens.
for i, token in ipairs(tokens) do
	print(
		i,
		token.type,
		token.value and "'"..tostring(token.value):gsub("\n", "\\n").."'" or "",
		token.unit  and "'"..tostring(token.unit).."'" or ""
	)
end
--]]



css = cssLib.serializeAndMinimize(tokens)
print("------------")
print(css)



-- [[ Round-trip test.
print("------------")
local cssAgain = cssLib.minimize(css)
print(cssAgain)

if css ~= cssAgain then
	print("Parsing round-trip failed!")
	print("Byte diff: ", #cssAgain-#css)

	local testFrom = 1
	local testTo   = math.min(#css, #cssAgain)

	while testFrom < testTo do
		local mid = math.floor(testFrom+(testTo-testFrom)/2)
		if
			css:sub(mid, mid) == cssAgain:sub(mid, mid)
			and css:sub(math.max(mid-20, 1), mid) == cssAgain:sub(math.max(mid-20, 1), mid)
			and css:sub(1, mid) == cssAgain:sub(1, mid)
		then
			testFrom = mid+1
		else
			testTo = mid
		end
	end

	local similarUntilPos = testFrom

	local from   = utf8.offset(css, 0, math.max(similarUntilPos-50, 1))
	local before = css:sub(from, utf8.offsetend(css, 0, similarUntilPos))
	print(("First diff at: %d/%d (%.1f%%)"):format(similarUntilPos, #css, 100*similarUntilPos/#css))
	print(">", css:sub(
		from,
		utf8.offsetend(css, 0, similarUntilPos+50) or #css
	))
	print(">", cssAgain:sub(
		from,
		utf8.offsetend(cssAgain, 0, similarUntilPos+50) or #cssAgain
	))
	print(">", (" "):rep(utf8.len(before)-1).."^")

	error()
end
--]]



print("------------")
print("Tokenization time: "..tokenizeTime.." seconds")


