# LuaCss

CSS tokenizing and minimizing library for Lua 5.1.
No external dependencies - only pure Lua.
The library tries to closely follow the [CSS3 specification](https://www.w3.org/TR/css-syntax-3/).

- [Usage](#usage)
- [API](#api)
- [Options](#options)
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
`cssString = minimize( cssString [, options ] )`<br>
`tokens = minimize( tokens [, options ] )`

Minimize a CSS string or a token array.
In the case of tokens, the original array is unchanged and a new array is returned.
See available [options](#options).


### serialize
`cssString = serialize( tokens [, options ] )`

Convert a token array to CSS string.
See available [options](#options).


### serializeAndMinimize
`cssString = serializeAndMinimize( tokens [, options ] )`

Convert a token array to minimized CSS string.
See available [options](#options).


### tokenize
`tokens = tokenize( cssString )`

Convert a CSS string to tokens.

```lua
local tokens = cssLib.tokenize(css)

for i, token in ipairs(tokens) do
	print(i, token.type, token.value, token.unit)
end
```

Note that all instances of U+0000 (NULL) code points are converted to U+FFFD (replacement character) per the specification.



## Options
`options` is a table that can have any of these fields:

### autoZero
Enable automatic conversion of *zero* values (e.g. `0px` or `0%`) to become simply `0` during minification.
The default value is `true`.

### strict
Trigger an error if a `badString` or `badUrl` token is encountered during minification.
Otherwise, the error message is only printed.
The default value is `false`.



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


