/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Shapes
import Victron.VenusOS

Item {
	id: gauges

	property alias value: arc.value
	property alias startAngle: arc.startAngle
	property alias endAngle: arc.endAngle
	property int status
	property alias animationEnabled: arc.animationEnabled
	property alias shineAnimationEnabled: arc.shineAnimationEnabled
	readonly property color _socStartColor: Theme.color_red
	readonly property color _socWarmColor: Theme.color_orange
	readonly property color _socMidColor: Qt.rgba(0.96, 0.84, 0.25, 1.0)
	readonly property color _socEndColor: Theme.color_green

	function _mixColors(colorA, colorB, amount) {
		const t = Math.max(0, Math.min(amount, 1))
		return Qt.rgba(
			colorA.r + ((colorB.r - colorA.r) * t),
			colorA.g + ((colorB.g - colorA.g) * t),
			colorA.b + ((colorB.b - colorA.b) * t),
			colorA.a + ((colorB.a - colorA.a) * t)
		)
	}

	function _gradientColorAt(position) {
		const t = Math.max(0, Math.min(position, 1))
		if (t <= 0.2) {
			return _mixColors(_socStartColor, _socWarmColor, t / 0.2)
		} else if (t <= 0.55) {
			return _mixColors(_socWarmColor, _socMidColor, (t - 0.2) / 0.35)
		}
		return _mixColors(_socMidColor, _socEndColor, (t - 0.55) / 0.45)
	}

	Item {
		id: antialiased
		anchors.fill: parent

		// Antialiasing without requiring multisample framebuffers.
		layer.enabled: !BackendConnection.msaaEnabled
		layer.smooth: true
		layer.textureSize: Qt.size(antialiased.width*2, antialiased.height*2)

		Item {
			id: arc

			width: gauges.width
			height: width
			anchors.centerIn: parent
			property real value
			property real startAngle: 0
			property real endAngle: 359
			property bool animationEnabled
			property bool shineAnimationEnabled
			readonly property real radius: width / 2
			readonly property real strokeWidth: Theme.geometry_circularSingularGauge_strokeWidth
			readonly property real _sweepAngle: Math.max(Math.abs(endAngle - startAngle), 0.01)
			readonly property real _angleDirection: endAngle >= startAngle ? 1 : -1
			readonly property real _progressFraction: Math.min(Math.max(value, 0.0), 100.0) / 100.0
			readonly property int _segmentCount: Math.max(24, Math.ceil(_sweepAngle / 10))

			function _angleForFraction(fraction) {
				const t = Math.max(0, Math.min(fraction, 1))
				return startAngle + (_angleDirection * _sweepAngle * t)
			}

			Repeater {
				model: arc._segmentCount
				delegate: Shape {
					required property int index
					readonly property real startFraction: index / arc._segmentCount
					readonly property real endFraction: (index + 1) / arc._segmentCount
					x: 0
					y: 0
					width: arc.width
					height: arc.height
					opacity: 0.28

					Arc {
						radius: arc.radius
						startAngle: arc._angleForFraction(startFraction)
						endAngle: arc._angleForFraction(endFraction)
						strokeWidth: arc.strokeWidth
						strokeColor: gauges._gradientColorAt((startFraction + endFraction) / 2)
						fillColor: "transparent"
					}
				}
			}

			Repeater {
				model: arc._segmentCount
				delegate: Shape {
					required property int index
					readonly property real startFraction: index / arc._segmentCount
					readonly property real endFraction: (index + 1) / arc._segmentCount
					readonly property real clampedEndFraction: Math.min(endFraction, arc._progressFraction)
					x: 0
					y: 0
					width: arc.width
					height: arc.height
					visible: arc._progressFraction > startFraction

					Arc {
						animationEnabled: arc.animationEnabled
						radius: arc.radius
						startAngle: arc._angleForFraction(startFraction)
						endAngle: arc._angleForFraction(clampedEndFraction)
						strokeWidth: arc.strokeWidth
						strokeColor: gauges._gradientColorAt((startFraction + endFraction) / 2)
						fillColor: "transparent"
					}
				}
			}
		}
	}
}
