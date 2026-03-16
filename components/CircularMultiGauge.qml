/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Controls.impl as CP
import Victron.VenusOS

Item {
	id: gauges

	property alias model: arcRepeater.model
	readonly property real strokeWidth: Theme.geometry_circularMultiGauge_strokeWidth
	property bool animationEnabled
	property real labelMargin
	property alias labelOpacity: textCol.opacity
	property int leftGaugeCount
	readonly property color _socStartColor: Theme.color_red
	readonly property color _socWarmColor: Theme.color_orange
	readonly property color _socMidColor: Qt.rgba(0.96, 0.84, 0.25, 1.0)
	readonly property color _socEndColor: Theme.color_green
	readonly property color _socTrackColor: Theme.color_darkishBlue

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

	// Step change in the size of the bounding boxes of successive gauges
	readonly property real _stepSize: 2 * (strokeWidth + Theme.geometry_circularMultiGauge_spacing)

	Item {
		id: antialiased
		anchors.fill: parent

		// Antialiasing without requiring multisample framebuffers.
		layer.enabled: !BackendConnection.msaaEnabled
		layer.smooth: true
		layer.textureSize: Qt.size(antialiased.width*2, antialiased.height*2)

		Repeater {
			id: arcRepeater
			width: parent.width
			delegate: Loader {
				id: loader
				property int gaugeStatus: Theme.getValueStatus(model.level, model.valueType)
				property real level: model.level // always draw the tank level (percentage).
				width: parent.width - (index*_stepSize)
				height: width
				anchors.centerIn: parent
				sourceComponent: model.tankType === VenusOS.Tank_Type_Battery ? shinyProgressArc : progressArc
				onStatusChanged: if (status === Loader.Error) console.warn("Unable to load circular multi gauge progress arc:", errorString())

				Component {
					id: shinyProgressArc
					Item {
						id: batteryArc
						width: loader.width
						height: loader.height
						property real radius: width / 2
						property real startAngle: 0
						property real endAngle: 270
						property real value: loader.level
						property real strokeWidth: gauges.strokeWidth
						property bool animationEnabled: gauges.animationEnabled
						property bool shineAnimationEnabled: Global.system.battery.mode === VenusOS.Battery_Mode_Charging
						readonly property real _sweepAngle: Math.max(Math.abs(endAngle - startAngle), 0.01)
						readonly property real _angleDirection: endAngle >= startAngle ? 1 : -1
						readonly property real _progressFraction: Math.min(Math.max(value, 0.0), 100.0) / 100.0
						readonly property int _segmentCount: Math.max(18, Math.ceil(_sweepAngle / 10))

						function _angleForFraction(fraction) {
							const t = Math.max(0, Math.min(fraction, 1))
							return startAngle + (_angleDirection * _sweepAngle * t)
						}

						Shape {
							x: 0
							y: 0
							width: loader.width
							height: loader.height

							Arc {
								radius: batteryArc.radius
								startAngle: batteryArc.startAngle
								endAngle: batteryArc.endAngle
								strokeWidth: batteryArc.strokeWidth
								strokeColor: gauges._socTrackColor
								fillColor: "transparent"
							}
						}

						Repeater {
							model: batteryArc._segmentCount
							delegate: Shape {
								required property int index
								readonly property real startFraction: index / batteryArc._segmentCount
								readonly property real endFraction: (index + 1) / batteryArc._segmentCount
								readonly property real clampedEndFraction: Math.min(endFraction, batteryArc._progressFraction)
								x: 0
								y: 0
								width: loader.width
								height: loader.height
								visible: batteryArc._progressFraction > startFraction

								Arc {
									animationEnabled: batteryArc.animationEnabled
									radius: batteryArc.radius
									startAngle: batteryArc._angleForFraction(startFraction)
									endAngle: batteryArc._angleForFraction(clampedEndFraction)
									strokeWidth: batteryArc.strokeWidth
									strokeColor: gauges._gradientColorAt((startFraction + endFraction) / 2)
									fillColor: "transparent"
								}
							}
						}
					}
				}

				Component {
					id: progressArc
					ProgressArc {
						radius: width/2
						startAngle: 0
						endAngle: 270
						value: loader.level
						progressColor: Theme.color_darkOk,Theme.statusColorValue(loader.gaugeStatus)
						remainderColor: Theme.color_darkOk,Theme.statusColorValue(loader.gaugeStatus, true)
						strokeWidth: gauges.strokeWidth
						animationEnabled: gauges.animationEnabled
					}
				}
			}
		}
	}

	Item {
		id: textCol

		anchors.top: parent.top
		anchors.topMargin: strokeWidth/2
		anchors.bottom: parent.verticalCenter
		anchors.left: parent.left
		anchors.leftMargin: Theme.geometry_circularMultiGauge_label_leftMargin
		anchors.right: parent.horizontalCenter
		anchors.rightMargin: Theme.geometry_circularMultiGauge_icon_rightMargin + gauges.labelMargin

		Repeater {
			model: gauges.model
			delegate: Row {
				anchors.verticalCenter: textCol.top
				anchors.verticalCenterOffset: index * _stepSize/2
				anchors.right: parent.right
				anchors.rightMargin: Math.max(0, Theme.geometry_circularMultiGauge_icons_maxWidth - iconImage.width)
				height: iconImage.height

				Label {
					anchors.verticalCenter: parent.verticalCenter
					rightPadding: Theme.geometry_circularMultiGauge_label_rightMargin
					horizontalAlignment: Text.AlignRight
					font.pixelSize: valueLabel.visible ? Theme.font_size_body1 : Theme.font_size_body2
					color: Theme.color_font_primary
					text: model.name

					// With three gauges on the left there is a risk that the last labels on
					// on the multi-gauge overlap with the labels on the top-left gauge.
					//
					// Increase the space for the two top-most labels or if there are less left gauges.
					width: textCol.width - valueLabel.width - iconImage.width
						+ (model.index < 2 || gauges.leftGaugeCount < 3 ? Theme.geometry_circularMultiGauge_label_extraWidth : 0)
					elide: Text.ElideRight
				}

				Label {
					id: valueLabel
					anchors.verticalCenter: parent.verticalCenter
					rightPadding: Theme.geometry_circularMultiGauge_value_rightMargin
					horizontalAlignment: Text.AlignRight
					font.pixelSize: Theme.font_size_body1
					color: Theme.color_font_primary
					visible: false

					property int unit
					property quantityInfo quantity

					states: State {
						when: Global.systemSettings.briefView.unit.value !== VenusOS.BriefView_Unit_None
						PropertyChanges {
							target: valueLabel

							visible: true
							text: quantity.number + quantity.unit
							quantity: Units.getDisplayText(unit, value)
							unit: {
								if (Global.systemSettings.briefView.unit.value === VenusOS.BriefView_Unit_Percentage) {
									return VenusOS.Units_Percentage
								} else if (model.tankType === VenusOS.Tank_Type_Battery) {
									return VenusOS.Units_Percentage
								} else {
									return Global.systemSettings.volumeUnit
								}
							}
						}
					}
				}

				CP.ColorImage {
					id: iconImage
					source: model.icon
					color: Theme.color_font_primary
				}
			}
		}
	}
}
