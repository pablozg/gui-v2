/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Shapes
import Victron.VenusOS

Item {
	id: root

	property var model: []
	property real initialModelValue: 0.0
	property real offsetFraction: 0.0
	property real threshold: 0.8
	property int dotSize: Theme.geometry_briefPage_sidePanel_loadGraph_dotSize
	property color aboveThresholdFillColor: Theme.color_orange
	property color belowThresholdFillColor: Theme.color_blue
	property color backgroundColor: Theme.color_briefPage_background
	property color horizontalGradientColor1: backgroundColor
	property color horizontalGradientColor2: "transparent"
	property bool zeroCentered
	property bool invertValues: false
	property bool normalizeToVisibleMaximum: false
	property bool trimLeadingInitialValues: false
	property bool animationEnabled: true
	property int modelLength: Theme.animation_loadGraph_model_length
	property bool externalSource: false

	readonly property var _displayedModel: _displayModel(model)
	readonly property real _maxDisplayedValue: {
		let maxValue = 0
		for (let i = 0; i < _displayedModel.length; ++i) {
			const value = _displayedModel[i]
			if (!isNaN(value) && value > maxValue) {
				maxValue = value
			}
		}
		return maxValue
	}

	function _normalizedModel(data) {
		if (!Array.isArray(data)) {
			return Array(modelLength).fill(initialModelValue)
		}
		if (data.length === modelLength) {
			return data.slice(0)
		}
		if (data.length > modelLength) {
			return data.slice(data.length - modelLength)
		}
		return Array(modelLength - data.length).fill(initialModelValue).concat(data)
	}

	function _displayModel(data) {
		let normalized = _normalizedModel(data)
		if (trimLeadingInitialValues && !zeroCentered) {
			let firstMeaningfulIndex = -1
			for (let i = 0; i < normalized.length; ++i) {
				const value = normalized[i]
				if (!isNaN(value) && Math.abs(value - initialModelValue) > 0.0001) {
					firstMeaningfulIndex = i
					break
				}
			}

			if (firstMeaningfulIndex > 0) {
				normalized = normalized.slice(firstMeaningfulIndex)
			}

			if (normalized.length < 2) {
				normalized = _normalizedModel(data).slice(-2)
			}
		}

		if (!normalizeToVisibleMaximum || zeroCentered) {
			return _transformDisplayedModel(normalized)
		}

		let maxValue = 0
		for (let i = 0; i < normalized.length; ++i) {
			const value = normalized[i]
			if (!isNaN(value) && value > maxValue) {
				maxValue = value
			}
		}

		if (!(maxValue > 0)) {
			return _transformDisplayedModel(normalized)
		}

		return _transformDisplayedModel(normalized.map(function(value) {
			return isNaN(value) ? initialModelValue : Math.min(value / maxValue, 1)
		}))
	}

	function _transformDisplayedModel(values) {
		if (!invertValues) {
			return values
		}
		return values.map(function(value) {
			return isNaN(value) ? initialModelValue : 1 - value
		})
	}

	clip: true
	implicitWidth: Theme.geometry_briefPage_sidePanel_loadGraph_width
	implicitHeight: Theme.geometry_briefPage_sidePanel_loadGraph_height

	Rectangle {
		anchors.fill: parent
		color: root.backgroundColor

		LoadGraphShapePath {
			id: orangePath
			anchors.fill: parent
			visible: threshold === 0.0 || root._maxDisplayedValue > threshold
			model: root._displayedModel
			strokeColor: aboveThresholdFillColor
			offsetFraction: root.offsetFraction
			fillGradient: LinearGradient {
				x1: 0; y1: 0
				x2: 0; y2: height
				GradientStop { position: 0; color: aboveThresholdFillColor }
				GradientStop { position: 1; color: "transparent" }
			}
		}
	}

	Rectangle {
		anchors.bottom: parent.bottom
		visible: threshold > 0.0
		width: parent.width
		height: root.height * threshold
		clip: true
		color: root.backgroundColor

		LoadGraphShapePath {
			id: bluePath

			anchors {
				left: parent.left
				right: parent.right
				bottom: parent.bottom
			}
			height: root.height
			model: root._displayedModel
			strokeColor: belowThresholdFillColor
			zeroCentered: root.zeroCentered
			offsetFraction: root.offsetFraction
			fillGradient: LinearGradient {
				x1: 0; y1: 0
				x2: 0; y2: height
				GradientStop { position: 0; color: bluePath.zeroCentered ? "transparent" : belowThresholdFillColor }
				GradientStop {
					position: 1 - threshold + (dottedLine.height / height)
					color: bluePath.zeroCentered
						? Qt.rgba(belowThresholdFillColor.r, belowThresholdFillColor.g, belowThresholdFillColor.b, belowThresholdFillColor.a * 0.5)
						: belowThresholdFillColor
				}
				GradientStop { position: 1; color: bluePath.zeroCentered ? belowThresholdFillColor : "transparent" }
			}
		}

		Row {
			id: dottedLine
			width: parent.width
			height: dotSize
			spacing: Global.isGxDevice ? dotSize * 2 : dotSize

			Repeater {
				model: dottedLine.width / (dotSize + dottedLine.spacing)
				delegate: Rectangle {
					implicitWidth: dotSize
					implicitHeight: dotSize
					color: Theme.color_briefPage_sidePanel_loadGraph_dotColor
				}
			}
		}
	}

	Rectangle {
		visible: !Global.isGxDevice
		anchors.fill: parent
		gradient: Gradient {
			orientation: Gradient.Horizontal
			GradientStop { position: 0; color: horizontalGradientColor1 }
			GradientStop {
				position: Theme.geometry_briefPage_sidePanel_loadGraph_horizontalGradient_width / width
				color: horizontalGradientColor2
			}
			GradientStop {
				position: 1 - Theme.geometry_briefPage_sidePanel_loadGraph_horizontalGradient_width / width
				color: horizontalGradientColor2
			}
			GradientStop { position: 1; color: horizontalGradientColor1 }
		}
	}

	onExternalSourceChanged: {
		if (externalSource) {
			offsetFraction = 0.0
		}
	}

	onModelChanged: offsetFraction = 0.0

	Component.onCompleted: offsetFraction = 0.0
}
