# LuaCss

CSS tokenizing and minimizing library for Lua 5.1. No external dependencies - only pure Lua.

- [Usage](#usage)
- [API](#api)
- [Token Format](#token-format)
	- [Token Types](#token-types)



## Usage
`css.lua` is the library. `utf8.lua` is used by the library. Those are the only files you need.

```lua
local css = [[
div {
	color: blue;
	/* Blah. */
	background-color: #36B !important;
}

@media (min-width: 800px) {
	.box a:hover { text-decoration: underline; }
}
]]

local cssLib = require("css")
local minimizedCss = cssLib.minimize(css)

-- minimizedCss is:
-- div{color:blue;background-color:#36B!important}@media(min-width:800px){.box a:hover{text-decoration:underline}}
```



## API

### minimize
`cssString = minimize( cssString [, strictErrors=false ] )`

### serializeAndMinimize
`cssString = serializeAndMinimize( cssTokens [, strictErrors=false ] )`

### tokenize
`cssTokens = tokenize( cssString )`

```lua
local tokens = cssLib.tokenize(css)

for i, token in ipairs(tokens) do
	print(i, token.type, token.value, token.unit)
end
```



## Token Format
```lua
token = {
	-- Always present:
	type           = tokenType,

	-- Present in some token types:
	value          = tokenValue,
	from           = unicodeRangeStart,
	idType         = hashTokenIdentifierType,
	numberType     = numberType,
	quoteCharacter = stringQuoteCharacter,
	representation = originalNumberRepresentation,
	to             = unicodeRangeEnd,
	unit           = dimensionUnit,
}
```

### Token Types

| Type               | Value | Description |
| ------------------ | ----- |------------ |
| `"atKeyword"`      | The name, e.g. `"media"`. | `@whatever` |
| `"badString"`      | nothing | Malformed string. |
| `"badUrl"`         | nothing | Malformed `url()`. |
| `"cdo"`<br>`"cdc"` | nothing | Long ago people used to wrap embedded CSS code inside HTML comments, thus these tokens (`"<!--"` and `"-->"`, respectively). |
| `"colon"`          | nothing | `:` |
| `"columnMatch"`    | nothing | Token that exists to help with parsing: <code>&vert;&vert;</code>. |
| `"comma"`          | nothing | `,` |
| `"comment"`        | The contents of the comment. | `/* Blah. */`<br>Note that comments starting with `!` are preserved during minification, e.g. `/*! Copyright info. */`. |
| `"dashMatch"`      | nothing | <code>&vert;=</code> |
| `"dimension"`      | The number. | Numeric value with a unit.<br>This token has a `unit` field, e.g. with the value `"px"`.<br>This token also has the extra fields that the `number` type has. |
| `"function"`       | The name of the function, e.g. `"calc"`. | An identifier followed by a `(`. |
| `"hash"`           | The name, e.g. `"commentBox"` or `"A0FF5C"`. | Matches include ID selectors and color values.<br>This token also has an `idType` field with the value `"id"` or `"unrestricted"` (the latter *generally* meaning the value is a color starting with a number, e.g. `#2FBBAA`). |
| `"ident"`          | The name, e.g. `"div"` or `"font-size"`. | Any isolated identifier. |
| `"includeMatch"`   | nothing | `~=` |
| `"number"`         | The number. | Plain numeric value.<br>This token also has a `numberType` and `representation` field. `numberType` can be either `"integer"` or `"number"`. |
| `"percentage"`     | The number. | Numeric percentage value.<br>This token also has the extra fields that the `number` type has. |
| `"prefixMatch"`    | nothing | `^=` |
| `"semicolon"`      | nothing | `;` |
| `"string"`         | The contents of the string. | This token also has a `quoteCharacter` field whose value is either `"` (quote) or `'` (apostrophe).<br>Also see `badString`. |
| `"substringMatch"` | nothing | `*=` |
| `"suffixMatch"`    | nothing | `$=` |
| `"unicodeRange"`   | nothing | Unicode ranges has a `from` and a `to` field with Unicode code points. |
| `"url"`            | The URL. | This token also has a `quoteCharacter` field whose value is either `"` (quote), `'` (apostrophe) or an empty string.<br>Also see `badUrl`. |
| `"whitespace"`     | The contents of the whitespace sequence. | Whitespace characters are **space**, **horizontal tab** and **newline**. Note that all line endings are normalized into **newlines**. |
| `"("`, `")"`       | nothing | `(` and `)`, respectively. |
| `"["`, `"]"`       | nothing | `[` and `]`, respectively. |
| `"{"`, `"}"`       | nothing | `{` and `}`, respectively. |
| `"delim"`          | The delimiter. | Any other isolated punctuation character, e.g. `"."` or `"+"`. |


