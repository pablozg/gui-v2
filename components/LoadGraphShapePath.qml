/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Shapes
import Victron.VenusOS

Shape {
	id: root

	property var model: []
	readonly property real segWidth: width / Math.max((model.length - 2), 1)
	property real offsetFraction: 0.0
	property real offset: segWidth * offsetFraction
	property alias strokeColor: shapePath.strokeColor
	property alias strokeWidth: shapePath.strokeWidth
	property alias fillGradient: shapePath.fillGradient
	property bool zeroCentered

	property bool calculateMinYValue: false // calculate vs clamp
	property var yValues: []
	property real minYValue: 0 // used to determine visibility for orange graphs, or clamp min value for blue graphs.

	onModelChanged: _recalculate()
	onHeightChanged: _recalculate()

	function _recalculate() {
		const n = model.length
		if (n === 0 || height <= 0) return

		const newYValues = FastUtils.calculateLoadGraphYValues(model, n, height)

		if (calculateMinYValue) {
			let tempMin = Theme.geometry_screen_height
			for (let i = 0; i < n; ++i) {
				if (newYValues[i] < tempMin) {
					tempMin = newYValues[i]
				}
			}
			yValues = newYValues
			// Set minYValue AFTER updating yValues
			// to ensure that visibility change occurs
			// after the ShapePath rendering updates.
			minYValue = tempMin
		} else {
			for (let j = 0; j < n; ++j) {
				if (newYValues[j] < minYValue) {
					newYValues[j] = minYValue
				}
			}
			yValues = newYValues
		}
	}

	// Dynamic SVG path rebuilt when data or offset changes
	property string _svgPath: ""
	onYValuesChanged: _updatePath()
	onOffsetChanged: _updatePath()

	function _updatePath() {
		const n = yValues.length
		if (n < 2 || width <= 0) { _svgPath = ""; return }

		const sw = segWidth
		const off = offset
		const stw = shapePath.strokeWidth
		const bottomY = zeroCentered ? height / 2 : (height + stw)

		let d = "M 0 " + yValues[0].toFixed(1)

		for (let i = 1; i < n; i++) {
			const cpx = ((i - 0.5) * sw - off).toFixed(1)
			const endx = (i * sw - off).toFixed(1)
			d += " C " + cpx + " " + yValues[i-1].toFixed(1)
				+ " " + cpx + " " + yValues[i].toFixed(1)
				+ " " + endx + " " + yValues[i].toFixed(1)
		}

		// Close shape for fill gradient
		const rEdge = (width + stw).toFixed(1)
		const lEdge = (-stw).toFixed(1)
		d += " L " + rEdge + " " + yValues[n - 1].toFixed(1)
		d += " L " + rEdge + " " + bottomY.toFixed(1)
		d += " L " + lEdge + " " + bottomY.toFixed(1)
		d += " L " + lEdge + " " + yValues[0].toFixed(1)
		d += " Z"

		_svgPath = d
	}

	ShapePath {
		id: shapePath

		strokeWidth: 1

		PathSvg {
			path: root._svgPath
		}
	}
}

