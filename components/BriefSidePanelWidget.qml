/*
** Copyside (C) 2024 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS

Column {
	id: root

	property alias title: header.title
	property alias icon: header.icon
	property alias quantityLabel: quantityLabel
	property alias sideComponent: sideLoader.sourceComponent
	property alias bottomComponent: bottomLoader.sourceComponent
	property bool loadersActive

	// Extra data: voltage and current to show below the main value
	property var extraDataObject: null
	property bool extraIsAc: false

	width: parent.width
	bottomPadding: Theme.geometry_sidePanel_verticalMargin

	WidgetHeader {
		id: header
		z: 1    // place the title above the side component if it overflows
	}

	Row {
		width: parent.width
		height: quantityLabel.height

		ElectricalQuantityLabel {
			id: quantityLabel
			font.pixelSize: Theme.font_briefPage_sidePanel_quantityLabel_size
			width: parent.width - sideLoader.width
			alignment: Qt.AlignLeft
		}

		Loader {
			id: sideLoader
			anchors {
				top: parent.top
				bottom: parent.bottom
				bottomMargin: Theme.geometry_sidePanel_sideWidget_bottomMargin
			}
			width: Theme.geometry_sidePanel_sideWidget_width
			active: root.loadersActive
		}
	}

	// Secondary row: show voltage and current when the main label shows watts
	Row {
		width: parent.width
		spacing: Theme.geometry_quantityLabel_spacing * 3
		visible: root.extraDataObject !== null
				&& root.extraDataObject !== undefined
				&& !quantityLabel._unitAmps
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
			alignment: Qt.AlignLeft
		}

		QuantityLabel {
			visible: parent._extraCurrentValid
			font.pixelSize: Theme.font_size_caption
			valueColor: Theme.color_font_secondary
			unitColor: Theme.color_font_secondary
			unit: VenusOS.Units_Amp
			value: root.extraDataObject ? (root.extraDataObject.current ?? NaN) : NaN
			alignment: Qt.AlignLeft
		}
	}

	Item {
		width: 1
		height: bottomLoader.status === Loader.Ready ? Theme.geometry_sidePanel_quantityLabel_bottomMargin : 0
	}

	Loader {
		id: bottomLoader
		width: parent.width
		active: root.loadersActive
	}
}
