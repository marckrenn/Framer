{Layer, layerProperty} = require "./Layer"
{LayerStyle} = require "./LayerStyle"
{StyledText} = require "./StyledText"

validateFont = (arg) ->
	return _.isString(arg) or _.isObject(arg)

fontFamilyFromObject = (font) ->
	return if _.isObject(font) then font.fontFamily else font

textProperty = (obj, name, fallback, validator, transformer, set) ->
	layerProperty(obj, name, name, fallback, validator, transformer, {}, set, "_elementHTML")

asPadding = (value) ->
	return value if _.isNumber(value)
	return 0 if not _.isObject(value)
	result = {}
	isValidObject = false
	if value.horizontal?
		value.left ?= value.horizontal
		value.right ?= value.horizontal
	if value.vertical?
		value.top ?= value.vertical
		value.bottom ?= value.vertical
	for key in ["left", "right", "bottom", "top"]
		isValidObject ||= _.has(value, key)
		result[key] = value[key] ? 0
	return if not isValidObject then 0 else result

class exports.TextLayer extends Layer
	@_textProperties = [
		"text"
		"fontFamily"
		"fontSize"
		"fontWeight"
		"fontStyle"
		"lineHeight"
		"letterSpacing"
		"wordSpacing"
		"textAlign"
		"textTransform"
		"textIndent"
		"textDecoration"
		"textOverflow"
		"whiteSpace"
		"direction"
		"font"
		"borderWidth"
		"padding"
	]

	@_textStyleProperties = _.pull(_.clone(TextLayer._textProperties), "text").concat(["color", "shadowX", "shadowY", "shadowBlur", "shadowColor"])

	constructor: (options={}) ->
		_.defaults options,
			shadowType: "text"
			clip: false
			createHTMLElement: true
		if options.styledTextOptions?
			options.styledText = options.styledTextOptions
			delete options.styledTextOptions
		if options.styledText?
			delete options.text
			@styledTextOptions = options.styledText
			options.color ?= @_styledText.getStyle("color")
			options.fontSize ?= parseFloat(@_styledText.getStyle("fontSize"))
			options.fontFamily ?= @_styledText.getStyle("fontFamily")
			options.letterSpacing ?= parseFloat(@_styledText.getStyle("letterSpacing"))
			options.textAlign ?= @_styledText.textAlign
			fontWeight = @_styledText.getStyle("fontWeight")
			if fontWeight?
				options.fontWeight = parseFloat(fontWeight)

			lineHeight = @_styledText.getStyle("lineHeight")
			if not lineHeight? or lineHeight is "normal"
				lineHeight = 1.25
			else
				lineHeight = parseFloat(lineHeight)
			options.lineHeight ?= lineHeight
		else
			_.defaults options,
				backgroundColor: "transparent"
				text: "Hello World"
				color: "#888"
				fontSize: 40
				fontWeight: 400
				lineHeight: 1.25
				padding: 0
			if not options.font? and not options.fontFamily?
				options.fontFamily = @defaultFont()

			text = options.text
			text = String(text) if not _.isString(text)
			@_styledText.addBlock text, fontSize: "#{options.fontSize}px"

		super options
		@__constructor = true

		# the goal is:
		# - autoSize elements should not soft wrap, only hard wrap (based on newlines)
		# - fixed (given a box) elements should soft wrap
		# - when the height is not fixed, it should be allowed to grow

		if options.autoSize
			@autoWidth = true
			@autoHeight = true
		else if options.autoSize isnt false and not options.truncate
			# if not explicitly disabled auto sizing, auto size width/height, unless they were explicitly set
			if not options.autoWidth?
				explicitWidth = options.width? or _.isNumber(options.size) or options.size?.width? or options.frame?.width?
				@autoWidth = not explicitWidth
			if not options.autoHeight?
				explicitHeight = options.height? or _.isNumber(options.size) or options.size?.height? or options.frame?.height?
				@autoHeight = not explicitHeight

		# if constraints from design, autoHeight depends on if the element is allowed to grow in height
		constraintValues = options.constraintValues
		if constraintValues
			topAndBottom = _.isNumber(constraintValues.top) and _.isNumber(constraintValues.bottom)
			heightFactor = _.isNumber(constraintValues.heightFactor)
			@autoHeight = not (heightFactor or topAndBottom)

		if not options.styledText?
			@font ?= @fontFamily

		@_styledText.setElement(@_elementHTML)

		delete @__constructor

		@renderText()

		# Executing function properties like Align.center again
		for key, value of options
			if _.isFunction(value) and @[key]?
				@[key] = value

		for property in TextLayer._textStyleProperties
			do (property) =>
				@on "change:#{property}", (value) =>
					return if value is null
					# make an exception for fontSize, as it needs to be set on the inner style
					if not (property in ["fontSize", "font"])
						@_styledText.resetStyle(property)
					@renderText()

		@on "change:width", @updateAutoWidth
		@on "change:height", @updateAutoHeight
		@on "change:parent", @renderText

	updateAutoWidth: (value) =>
		return if @disableAutosizeUpdating
		@autoWidth = false

	updateAutoHeight: (value) =>
		return if @disableAutosizeUpdating
		@autoHeight = false

	copySingle: ->
		props = @props
		delete props["width"] if @autoWidth
		delete props["height"] if @autoHeight
		copy = new @constructor(props)
		copy.style = @style
		copy

	@define "_styledText",
		get: ->
			if not @__styledText?
				@__styledText = new StyledText()
			return @__styledText
		set: (value) ->
			return unless value instanceof StyledText
			@__styledText = value

	@define "styledTextOptions",
		get: -> @_styledText?.getOptions()
		set: (value) ->
			@_styledText = new StyledText(value)
			@_styledText.setElement(@_elementHTML)
			fonts = @_styledText.getFonts()
			promise = Utils.isFontFamilyLoaded(fonts)
			if _.isObject(promise)
				promise.then =>
					@renderText()

	#Vekter properties
	@define "autoWidth", @proxyProperty("_styledText.autoWidth",
		didSet: (layer, value) ->
			layer.renderText()
		)
	@define "autoHeight", @proxyProperty("_styledText.autoHeight",
		didSet: (layer, value) ->
			layer.renderText()
		)

	@define "autoSize",
		get: -> @autoWidth and @autoHeight
		set: (value) ->
			@autoWidth = value
			@autoHeight = value
			@renderText()

	@define "fontFamily", textProperty(@, "fontFamily", null, _.isString, fontFamilyFromObject, (layer, value) ->
		return if value is null
		layer.font = value
		promise = Utils.isFontFamilyLoaded(value)
		if _.isObject(promise)
			promise.then ->
				setTimeout(layer.renderText, 0)
	)
	@define "fontWeight", textProperty(@, "fontWeight", null)
	@define "fontStyle", textProperty(@, "fontStyle", "normal", _.isString)
	@define "textDecoration", textProperty(@, "textDecoration", null, _.isString)
	@define "fontSize", textProperty(@, "fontSize", null, _.isNumber, null, (layer, value) ->
		return if value is null or layer.__constructor
		style = LayerStyle["fontSize"](layer)
		layer._styledText.setStyle("fontSize", style)
	)
	@define "textAlign", textProperty(@, "textAlign", null)
	@define "letterSpacing", textProperty(@, "letterSpacing", null, _.isNumber)
	@define "lineHeight", textProperty(@, "lineHeight", null, _.isNumber)

	#Custom properties
	@define "wordSpacing", textProperty(@, "wordSpacing", null, _.isNumber)
	@define "textTransform", textProperty(@, "textTransform", "none", _.isString)
	@define "textIndent", textProperty(@, "textIndent", null, _.isNumber)
	@define "wordWrap", textProperty(@, "wordWrap", null, _.isString)

	@define "textOverflow",
		get: -> @_styledText.textOverflow
		set: (value) ->
			@clip = _.isString(value)
			@_styledText.setTextOverflow(value)
			@renderText(true)

	@define "truncate",
		get: -> @textOverflow is "ellipsis"
		set: (truncate) ->
			if truncate
				@autoSize = false
				@textOverflow = "ellipsis"
			else
				@textOverflow = null

	@define "whiteSpace", textProperty(@, "whiteSpace", null, _.isString)
	@define "direction", textProperty(@, "direction", null, _.isString)

	@define "html",
		get: ->
			@_elementHTML?.innerHTML or ""

	@define "font", layerProperty @, "font", null, null, validateFont, null, {}, (layer, value) ->
		return if value is null
		if _.isObject(value)
			layer.fontFamily = value.fontFamily
			layer.fontWeight = value.fontWeight
			return
		# Check if value contains number. We then assume proper use of font.
		# Otherwise, we default to setting the fontFamily.
		if /\d/.test(value)
			layer._styledText.setStyle("font", value)
		else
			layer.fontFamily = value
	, "_elementHTML"

	@define "textDirection",
		get: -> @direction
		set: (value) -> @direction = value

	@define "padding", layerProperty(@, "padding", "padding", 0, null, asPadding)

	@define "text",
		get: -> @_styledText.getText()
		set: (value) ->
			value = String(value) if not _.isString(value)
			@_styledText.setText(value)
			@renderText()
			@emit("change:text", value)

	renderText: (forceRender = false) =>
		return if @__constructor
		@_styledText.render()
		@_updateHTMLScale()
		if not @autoSize
			if @width < @_elementHTML.clientWidth or @height < @_elementHTML.clientHeight
				@clip = true
		return unless forceRender or @autoHeight or @autoWidth or @textOverflow isnt null
		padding = Utils.rectZero(Utils.parseRect(@padding))
		if @autoWidth
			constrainedWidth = null
		else
			constrainedWidth = @size.width - (padding.left + padding.right)
		if @autoHeight
			constrainedHeight = null
		else
			constrainedHeight = @size.height - (padding.top + padding.bottom)
		constraints =
			width: constrainedWidth
			height: constrainedHeight
			multiplier: @context.pixelMultiplier

		calculatedSize = @_styledText.measure constraints
		@disableAutosizeUpdating = true
		if calculatedSize.width?
			@width = calculatedSize.width + padding.left + padding.right
		if calculatedSize.height?
			@height = calculatedSize.height + padding.top + padding.bottom
		@disableAutosizeUpdating = false

	defaultFont: ->
		return Utils.deviceFont(Framer.Device.platform())

	textReplace: (search, replace) ->
		oldText = @text
		@_styledText.textReplace(search, replace)
		if @text isnt oldText
			@renderText()
			@emit("change:text", @text)

	# we remember the template data, and merge it with new data
	@define "template",
		get: -> _.clone(@_templateData)
		set: (data) ->
			if not @_templateData then @_templateData = {}

			firstName = @_styledText.buildTemplate()
			if not _.isObject(data)
				return unless firstName
				@_templateData[firstName] = data
			else
				_.assign(@_templateData, data)

			oldText = @text
			@_styledText.template(@_templateData)
			if @text isnt oldText
				@renderText()
				@emit("change:text", @text)

	@define "templateFormatter",
		get: -> @_templateFormatter
		set: (data) ->
			firstName = @_styledText.buildTemplate()
			if _.isFunction(data) or not _.isObject(data)
				return unless firstName
				tmp = {}; tmp[firstName] = data; data = tmp
			@_styledText.templateFormatter(data)
