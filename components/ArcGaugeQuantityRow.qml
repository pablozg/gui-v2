/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Controls.impl as CP
import Victron.VenusOS

Column {
	id: root

	property int alignment: Qt.AlignTop | Qt.AlignLeft
	property alias icon: icon
	property alias quantityLabel: quantityLabel

	// Extra data: voltage and current to show below the main value
	property var extraDataObject: null
	property bool extraIsAc: false

	// Use x/y bindings as the layout sometimes did not update dynamically when multiple anchor
	// bindings were used instead.
	x: root.alignment & Qt.AlignLeft
	   ? Theme.geometry_briefPage_edgeGauge_quantityLabel_horizontalMargin
	   : parent.width - width - Theme.geometry_briefPage_edgeGauge_quantityLabel_horizontalMargin
	y: alignment & Qt.AlignVCenter
	   ? parent.height/2 - height/2
	   : alignment & Qt.AlignBottom
		 ? parent.height - height - Theme.geometry_briefPage_edgeGauge_quantityLabel_bottomMargin
		 : Theme.geometry_briefPage_edgeGauge_quantityLabel_topMargin    // root.alignment & Qt.AlignTop

	spacing: 6

	Row {
		spacing: Theme.geometry_briefPage_edgeGauge_quantityLabel_spacing
		layoutDirection: root.alignment & Qt.AlignRight ? Qt.RightToLeft : Qt.LeftToRight

		CP.ColorImage {
			id: icon

			anchors.verticalCenter: parent.verticalCenter
			width: Theme.geometry_widgetHeader_icon_width
			fillMode: Image.Pad
			color: Theme.color_font_primary
		}

		ElectricalQuantityLabel {
			id: quantityLabel

			height: icon.height
			anchors.verticalCenter: parent.verticalCenter
			font.pixelSize: Theme.font_briefPage_quantityLabel_size
		}
	}

	// Secondary row: show voltage and current
	Row {
		spacing: Theme.geometry_quantityLabel_spacing
		layoutDirection: root.alignment & Qt.AlignRight ? Qt.RightToLeft : Qt.LeftToRight
		anchors {
			left: root.alignment & Qt.AlignLeft ? parent.left : undefined
			right: root.alignment & Qt.AlignRight ? parent.right : undefined
			leftMargin: root.alignment & Qt.AlignLeft ? icon.width + Theme.geometry_briefPage_edgeGauge_quantityLabel_spacing : 0
			rightMargin: root.alignment & Qt.AlignRight ? icon.width + Theme.geometry_briefPage_edgeGauge_quantityLabel_spacing : 0
		}
		visible: root.extraDataObject !== null
				&& root.extraDataObject !== undefined
				&& (_extraVoltageValid || _extraCurrentValid)

		readonly property bool _extraVoltageValid: root.extraDataObject !== null
				&& root.extraDataObject !== undefined
				&& !isNaN(root.extraDataObject.voltage)
		readonly property bool _extraCurrentValid: root.extraDataObject !== null
				&& root.extraDataObject !== undefined
				&& !isNaN(root.extraDataObject.current)

		QuantityLabel {
			visible: parent._extraVoltageValid
			font.pixelSize: Theme.font_size_caption
			valueColor: Theme.color_font_secondary
			unitColor: Theme.color_font_secondary
			unit: root.extraIsAc ? VenusOS.Units_Volt_AC : VenusOS.Units_Volt_DC
			value: root.extraDataObject ? (root.extraDataObject.voltage ?? NaN) : NaN
		}

		QuantityLabel {
			visible: parent._extraCurrentValid
			font.pixelSize: Theme.font_size_caption
			valueColor: Theme.color_font_secondary
			unitColor: Theme.color_font_secondary
			unit: VenusOS.Units_Amp
			value: root.extraDataObject ? (root.extraDataObject.current ?? NaN) : NaN
		}
	}
}
