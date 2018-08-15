--[[============================================================
--=
--=  LuaCss Testsuite
--=
--============================================================]]

local cssLib = require"css"
local utf8   = require"utf8"



local function printFirstDiff(a, b)
	print("Byte diff: "..(#b-#a))

	a = a:gsub("\n", "\\n")
	b = b:gsub("\n", "\\n")

	local testFrom = 1
	local testTo   = math.min(#a, #b)

	while testFrom < testTo do
		local mid = math.floor(testFrom+(testTo-testFrom)/2)
		if
			a:sub(mid, mid) == b:sub(mid, mid)
			and a:sub(math.max(mid-20, 1), mid) == b:sub(math.max(mid-20, 1), mid)
			and a:sub(1, mid) == b:sub(1, mid)
		then
			testFrom = mid+1
		else
			testTo = mid
		end
	end

	local similarUntilPos = testFrom

	local from   = utf8.offset(a, 0, math.max(similarUntilPos-50, 1))
	local before = a:sub(from, utf8.offsetend(a, 0, similarUntilPos))
	print(("First diff at: %d/%d (%.1f%%)"):format(similarUntilPos, #a, 100*similarUntilPos/#a))
	print(">", a:sub(
		from,
		utf8.offsetend(a, 0, similarUntilPos+50) or #a
	))
	print(">", b:sub(
		from,
		utf8.offsetend(b, 0, similarUntilPos+50) or #b
	))
	print(">", (" "):rep(utf8.len(before)-1).."^")
end



local function runTest(css, printCss)
	if printCss then
		print("================================")
		print(css)
		print("================================")
	end

	local clock        = os.clock()
	local tokens       = cssLib.tokenize(css)
	local tokenizeTime = os.clock()-clock

	if printCss then
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
	end



	css = cssLib.serializeAndMinimize(tokens)

	if printCss then
		print("----------------")
		print(css)
	end



	-- [[ Round-trip test.
	local cssAgain = cssLib.minimize(css)

	if printCss then
		print("----------------")
		print(cssAgain)
	end

	if css ~= cssAgain then
		print("Parsing round-trip failed!")
		printFirstDiff(css, cssAgain)
		error()
	end
	--]]



	if printCss then
		print("----------------")
	end

	print("Tokenization time: "..tokenizeTime.." seconds")

	return css
end



local function runTestOnFile(path, printCss, skipLargeFiles)
	local file = assert(io.open(path, "rb"))
	local css  = file:read"*a"
	file:close()

	if skipLargeFiles and #css >= 10000 then  return nil  end

	print("Running test: "..path:gsub("^tests/", ""))
	return runTest(css, printCss), css
end



local function runTestsuite(skipLargeFiles)
	print("Running testsuite")

	local ok, lfs = pcall(require, "lfs")
	if not ok then
		error("Testsuite requires LuaFileSystem.")
	end

	lfs.mkdir("temp")
	local out = assert(io.open("temp/testsuiteMinified.css", "wb"))

	local function testDir(dir)
		for name in lfs.dir(dir) do
			if not (name == "." or name == "..") then
				local path = dir.."/"..name
				local mode = assert(lfs.attributes(path, "mode"))

				if mode == "file" and name:find"%.css$" then
					out:write("/* ", path:gsub("^tests/", ""), " */\n")

					local cssMinified, cssOriginal = runTestOnFile(path, false, skipLargeFiles)

					if not cssMinified then
						out:write("/* Skipping large file. */\n")

					else
						out:write(cssMinified, "\n")

						local file = assert(io.open(path..".min", "rb"))
						local cssExpected = file:read"*a"
						file:close()

						if cssMinified == cssExpected then
							out:write("/* OK! */\n")
						else
							print()
							print("Unexpected result!")
							printFirstDiff(cssMinified, cssExpected)
							print()

							out:write("/* Expected: */\n", cssExpected, "\n")
						end
					end

					out:write("\n")

				elseif mode == "directory" then
					testDir(path)
				end
			end
		end
	end

	testDir("tests")

	out:close()
end



local function runSmallTest()
	print("Running small test")

	local css = [[
	div {
		background: red;
	}

	html >/* <=IE7 */ body small { font-size: 0.6rem; }

	.sink .cls {;
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

	runTest(css, true)
end



-- runSmallTest()
-- runTestOnFile("test.css")
-- runTestOnFile("tests/yui/issue205.css", true)
runTestsuite(true)
