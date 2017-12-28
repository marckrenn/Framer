{_} = require "./Underscore"
{Color} = require "./Color"
{Layer, layerProperty, layerProxiedValue} = require "./Layer"
{SVG, SVGPath} = require "./SVG"

validFill = (value) ->
	Color.validColorValue(value) or _.startsWith(value, "url(")

toFill = (value) ->
	if _.startsWith(value, "url(")
		return value
	else
		return Color.toColor(value)

class exports.SVGLayer extends Layer

	constructor: (options={}) ->
		# Ugly: detect Vekter export with html intrinsic size
		if options.htmlIntrinsicSize? and options.backgroundColor?
			# Backwards compatibility for old Vekter exporter that would
			# set backgroundColor instead of color
			options.color ?= options.backgroundColor
			options.backgroundColor = null
		options.clip ?= false
		if options.svg? or options.html?
			options.backgroundColor ?= null
		super options
		@updateGradientSVG()

	@define "fill", layerProperty(@, "fill", "fill", null, validFill, toFill)
	@define "stroke", layerProperty(@, "stroke", "stroke", null, validFill, toFill)
	@define "strokeWidthMultiplier", @simpleProperty("strokeWidthMultiplier", 1)
	@define "strokeWidth", layerProperty(@, "strokeWidth", "strokeWidth", null, _.isNumber)
	@define "color", layerProperty(@, "color", "color", null, Color.validColorValue, Color.toColor, null, ((layer, value) -> layer.fill = value), "_elementHTML", true)

	@define "gradient",
		get: ->
			return layerProxiedValue(@_gradient, @, "gradient") if Gradient.isGradientObject(@_gradient)
			return null
		set: (value) -> # Copy semantics!
			if Gradient.isGradient(value)
				@_gradient = new Gradient(value)
			else if not value and Gradient.isGradientObject(@_gradient)
				@_gradient = null
			@updateGradientSVG()

	@define "svg",
		get: ->
			svgNode = _.first(@_elementHTML.children)
			if svgNode instanceof SVGElement
				return svgNode
			else
				return null
		set: (value) ->
			if typeof value is "string"
				@html = value
			else if value instanceof SVGElement
				@_createHTMLElementIfNeeded()
				while @_elementHTML.firstChild
					@_elementHTML.removeChild(@_elementHTML.firstChild)
				if value.parentNode?
					value = value.cloneNode(true)
				@_elementHTML.appendChild(value)

	@define "path",
		get: ->
			if @svg.children?.length isnt 1
				error = "SVGLayer.path can only be used on SVG's that have a single child"
				if Utils.isFramerStudio()
					throw new Error(error)
				else
					console.error(error)
			child = @svg.children[0]
			if not SVGPath.isPath(child)
				error = "SVGLayer.path can only be used on SVG's containing an SVGPathElement, not #{Utils.inspectObjectType(child)}"
				if Utils.isFramerStudio()
					throw new Error(error)
				else
					console.error(error)
			return child

	@define "pathStart",
		get: ->
			start = SVGPath.getStart(@path)
			return null if not start?
			point =
				x: @x + start.x
				y: @y + start.y
			return point

	@define "anchorpoints",

		get: ->

			# wonky / semi-broken:
			start = @html.indexOf(' d="')
			end = @html.indexOf('" fill')
			if end is -1 then end = @html.indexOf('"></path>')
			path = @html.substring(start + 4, end)
			array = path.split(" ")
			anchorpoints = []

			i = 0

			# Lazy / limited to low-complex SVGs due to "while" limitation. Rewrite as recursive function?
			while i < array.length

				unless Number(array[i])
					anchorpoint = {}
					anchorpoint.type = array[i]

					switch array[i]

						# Anchorpoints include their respective controlpoints

						when "M"
							# Controlpoints are included for "M" and "L" to allow hotswapping of anchorpoint type
							anchorpoint.x1 = {}
							anchorpoint.x2 = {}
							anchorpoint.x1.x = Number(array[i + 1])
							anchorpoint.x1.y = Number(array[i + 2])
							anchorpoint.x2.x = Number(array[i + 1])
							anchorpoint.x2.y = Number(array[i + 2])
							anchorpoint.x = Number(array[i + 1])
							anchorpoint.y = Number(array[i + 2])
							i += 2

						when "L"
							anchorpoint.x1 = {}
							anchorpoint.x2 = {}
							anchorpoint.x1.x = Number(array[i + 1])
							anchorpoint.x1.y = Number(array[i + 2])
							anchorpoint.x2.x = Number(array[i + 1])
							anchorpoint.x2.y = Number(array[i + 2])
							anchorpoint.x = Number(array[i + 1])
							anchorpoint.y = Number(array[i + 2])
							i += 2

						when "C"
							anchorpoint.x1 = {}
							anchorpoint.x2 = {}
							anchorpoint.x1.x = Number(array[i + 1])
							anchorpoint.x1.y = Number(array[i + 2])
							anchorpoint.x2.x = Number(array[i + 3])
							anchorpoint.x2.y = Number(array[i + 4])
							anchorpoint.x = Number(array[i + 5])
							anchorpoint.y = Number(array[i + 6])
							i += 6
						else i++

					anchorpoints.push(anchorpoint) 
				i++
			return anchorpoints

		set: (anchorpoints) ->

			# wonky / semi-broken:
			firstPartEnd = @html.indexOf(' d="')
			firstPart = @html.substring(0, firstPartEnd + 4)
			thirdPartStart =  @html.indexOf(' fill')
			if thirdPartStart is -1 then thirdPartStart = @html.indexOf('Z')
			thirdPart = @html.substring(thirdPartStart + 1, @html.length)

			path = ""

			for anchorpoint in anchorpoints
				switch anchorpoint.type
					when "M" then path += "#{anchorpoint.type} #{anchorpoint.x} #{anchorpoint.y} "
					when "L" then path += "#{anchorpoint.type} #{anchorpoint.x} #{anchorpoint.y} "

					when "C"
						anchorpoint.x1 ?= {}
						anchorpoint.x2 ?= {}
						anchorpoint.x1.x ?= anchorpoint.x
						anchorpoint.x1.y ?= anchorpoint.y
						anchorpoint.x2.x ?= anchorpoint.x
						anchorpoint.x2.y ?= anchorpoint.y
						path += "#{anchorpoint.type} #{anchorpoint.x1.x} #{anchorpoint.x1.y} #{anchorpoint.x2.x} #{anchorpoint.x2.y} #{anchorpoint.x} #{anchorpoint.y} "

					else path += "#{anchorpoint.type} "

			@html = "#{firstPart}#{path}#{thirdPart}"

	updateGradientSVG: ->
		return if @__constructor
		if not Gradient.isGradient(@gradient)
			@_elementGradientSVG?.innerHTML = ""
			return

		if not @_elementGradientSVG
			@_elementGradientSVG = document.createElementNS("http://www.w3.org/2000/svg", "svg")
			@_element.appendChild @_elementGradientSVG

		id = "#{@id}-gradient"
		@_elementGradientSVG.innerHTML = """
			<linearGradient id='#{id}' gradientTransform='rotate(#{@gradient.angle - 90}, 0.5, 0.5)' >
				<stop offset="0" stop-color='##{@gradient.start.toHex()}' stop-opacity='#{@gradient.start.a}' />
				<stop offset="1" stop-color='##{@gradient.end.toHex()}' stop-opacity='#{@gradient.end.a}' />
			</linearGradient>
		"""
		@fill = "url(##{id})"
