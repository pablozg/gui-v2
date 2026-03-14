/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Shapes
import Victron.VenusOS

Item {
	id: root

	property var model: [] // contains 12 values that define the shape of our bendy graph
	property real initialModelValue: 0.0
	property real offsetFraction
	property real threshold: 0.8    // same as 80% warning level for gauges
	property int dotSize: Theme.geometry_briefPage_sidePanel_loadGraph_dotSize
	property color aboveThresholdFillColor: Theme.color_orange
	property color belowThresholdFillColor: Theme.color_blue
	property color horizontalGradientColor1: Theme.color_briefPage_background
	property color horizontalGradientColor2: "transparent"
	property bool zeroCentered
	property alias animationEnabled: graphAnimation.running

	// Number of data points shown in the graph.
	// Default 12 = original behavior. Set to 120 for 2-hour history at 1 point/min.
	property int modelLength: Theme.animation_loadGraph_model_length

	// Number of raw samples to average into one visual data point.
	// Default 1 = original behavior (1 sample/point, 12 seconds visible).
	// Set to 60 for 1-minute averaging (60 × 1s = 1 min per point).
	property int samplesPerPoint: 1

	// Persistence key. When set, the graph history is saved/restored via
	// Settings/Gui/GraphHistory/<key> so it survives page reloads and
	// remote console (WASM) reconnections.
	property string persistKey: ""

	signal nextValueRequested()

	property int _accCount: 0
	property real _accSum: 0.0
	property bool _dirty: false

	function addValue(value) {
		if (samplesPerPoint <= 1) {
			_pushValue(value)
		} else {
			_accSum += value
			_accCount++
			if (_accCount >= samplesPerPoint) {
				_pushValue(_accSum / _accCount)
				_accSum = 0.0
				_accCount = 0
			}
		}
	}

	function _pushValue(value) {
		let temp = model
		temp.push(value)
		temp.shift()
		model = temp
		_dirty = true
	}

	function _saveHistory() {
		if (!persistKey || !_dirty || !_historyItem) return
		// Compact JSON: round to 4 decimals to save space
		const rounded = model.map(function(v) { return Math.round(v * 10000) / 10000 })
		_historyItem.setValue(JSON.stringify(rounded))
		_dirty = false
	}

	function _restoreHistory() {
		if (!persistKey || !_historyItem || !_historyItem.value) return
		try {
			const saved = JSON.parse(_historyItem.value)
			if (Array.isArray(saved) && saved.length === modelLength) {
				model = saved
			}
		} catch(e) { /* ignore parse errors, start fresh */ }
	}

	// VeQuickItem for persisting graph data in Settings
	property var _historyItem: persistKey ? _historyItemComponent.createObject(root) : null

	Component {
		id: _historyItemComponent
		VeQuickItem {
			uid: Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/" + root.persistKey
		}
	}

	// Save every 60 seconds when data has changed
	Timer {
		running: root.persistKey !== "" && root.visible
		repeat: true
		interval: 60000
		onTriggered: root._saveHistory()
	}

	clip: true // we have to clip if we don't use a layer in LoadGraphShapePath.
	implicitWidth: Theme.geometry_briefPage_sidePanel_loadGraph_width
	implicitHeight: Theme.geometry_briefPage_sidePanel_loadGraph_height

	// Internal 1-second sampler for long-history mode
	Timer {
		id: longHistorySampler
		running: root.samplesPerPoint > 1 && root.visible
		repeat: true
		interval: 1000
		onTriggered: root.nextValueRequested()
	}

	Timer {
		id: pausedAnimationTimer
		running: root.samplesPerPoint <= 1 && !root.animationEnabled // even if !Global.timersEnabled, to avoid discontinuities
		repeat: true
		interval: Theme.geometry_briefPage_sidePanel_loadGraph_intervalMs
		onTriggered: {
			// step the graph and request the next value.
			root.offsetFraction = 1.0
			root.nextValueRequested();
		}
	}

	SequentialAnimation {
		id: graphAnimation

		running: root.samplesPerPoint <= 1
		loops: Animation.Infinite

		NumberAnimation {
			target: root
			property: "offsetFraction"
			from: 0.0
			to: 1.0
			duration: Theme.geometry_briefPage_sidePanel_loadGraph_intervalMs
		}

		ScriptAction {
			script: root.nextValueRequested()
		}
	}

	Rectangle {
		anchors.fill: parent
		color: Theme.color_briefPage_background

		LoadGraphShapePath {
			id: orangePath // .. or entire graph if no threshold is set.

			anchors.fill: parent

			visible: threshold === 0.0 || minYValue < (root.height - (root.height * threshold))
			calculateMinYValue: true
			model: root.model
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
		clip: true // we have to clip this, because we can't rely on setting minYValue of bluePath.
		color: Theme.color_briefPage_background

		LoadGraphShapePath {
			id: bluePath

			anchors {
				left: parent.left
				right: parent.right
				bottom: parent.bottom
			}
			height: root.height // larger than parent.

			//minYValue: (root.height - (root.height * threshold)) // we would like to do this, but the cubic pathing causes orange edge mismatch.
			model: root.model
			strokeColor: belowThresholdFillColor
			zeroCentered: root.zeroCentered
			offsetFraction: root.offsetFraction
			fillGradient: LinearGradient {
				x1: 0; y1: 0
				x2: 0; y2: height
				GradientStop { position: 0; color: bluePath.zeroCentered ? "transparent" : belowThresholdFillColor }
				GradientStop {
					position: 1 - threshold + (dottedLine.height / height)
					color: bluePath.zeroCentered ? Qt.rgba(belowThresholdFillColor.r, belowThresholdFillColor.g, belowThresholdFillColor.b, belowThresholdFillColor.a * 0.5) : belowThresholdFillColor
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

	Rectangle { // the graph fades out on the sides
		visible: !Global.isGxDevice
		anchors.fill: parent
		gradient: Gradient {
			orientation: Gradient.Horizontal
			GradientStop { position: 0; color: horizontalGradientColor1 }
			GradientStop {
				position: Theme.geometry_briefPage_sidePanel_loadGraph_horizontalGradient_width/width
				color: horizontalGradientColor2
			}
			GradientStop {
				position: 1 - Theme.geometry_briefPage_sidePanel_loadGraph_horizontalGradient_width/width
				color: horizontalGradientColor2
			}
			GradientStop { position: 1; color: horizontalGradientColor1 }
		}
	}

	Component.onCompleted: {
		model = Array(modelLength).fill(initialModelValue)
		if (persistKey) {
			// Delay restore slightly to ensure VeQuickItem has connected
			_restoreTimer.start()
		}
	}

	Component.onDestruction: _saveHistory()

	Timer {
		id: _restoreTimer
		interval: 500
		onTriggered: root._restoreHistory()
	}
}
