/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS

AcWidget {
	id: root

	readonly property ObjectAcConnection measurements: Global.system.showInputLoads
			? Global.system.load.acIn
			: Global.system.load.ac
	readonly property bool _showCurrentGauge: root.size >= VenusOS.OverviewWidget_Size_M
			&& !isNaN(Global.system.load.maximumAcCurrent)
			&& Global.system.load.maximumAcCurrent > 0
	readonly property real _sideGaugeInset: _showCurrentGauge
			? Theme.geometry_barGauge_vertical_width_large
			: 0
	readonly property bool _showHistoryGraph: root.size >= VenusOS.OverviewWidget_Size_M
			&& root.phaseCount <= 1
			&& !root.measurements.l2AndL1OutSummed

	//% "AC Loads"
	title: qsTrId("overview_widget_acloads_title")
	icon.source: "qrc:/images/acloads.svg"
	type: VenusOS.OverviewWidget_Type_AcLoads
	rightPadding: root._sideGaugeInset
	quantityLabel.dataObject: root.size !== VenusOS.OverviewWidget_Size_Zero ? root.measurements : null
	overviewExtraDataObject: root.size !== VenusOS.OverviewWidget_Size_Zero ? root.measurements : null
	overviewExtraIsAc: true
	phaseCount: root.measurements.phases.count
	extraContentLoader.active: root.phaseCount > 1 || root.measurements.l2AndL1OutSummed || root._showHistoryGraph
	extraContentLoader.sourceComponent: root.phaseCount > 1 || root.measurements.l2AndL1OutSummed
			? phaseComponent
			: historyGraphComponent

	// AC meters with Position=1 (AC input) are considered as "AC Loads", so they are
	// accessible from this AC Loads widget.
	// For 3-phase systems, the drilldown is always enabled.
	// For 1-phase systems, only enable the drilldown if there are devices to be shown.
	enabled: root.measurements.phaseCount > 1 || acLoadDevices.count > 0

	onClicked: {
		Global.pageManager.pushPage("/pages/loads/AcLoadListPage.qml", {
			title: root.title,
			measurements: root.measurements,
			model: acLoadDevices,
		})
	}

	FilteredDeviceModel {
		id: acLoadDevices
		serviceTypes: ["acload", "evcharger", "heatpump"]
		childFilterIds: Global.system.showInputLoads
				? { "acload": ["Position"], "evcharger": ["Position"], "heatpump": ["Position"] }
				: {}
		childFilterFunction: (device, childItems) => {
			// If a service does not have a /Position value, assume it is in the "input" position.
			const pos = childItems["Position"]
			return !pos || pos.value === undefined || pos.value === VenusOS.AcPosition_AcInput
		}
	 }

	Loader {
		id: sideGaugeLoader

		anchors {
			top: parent.top
			bottom: parent.bottom
			right: parent.right
			margins: Theme.geometry_overviewPage_widget_sideGauge_margins
		}
		active: root._showCurrentGauge
		sourceComponent: ThreePhaseBarGauge {
			valueType: VenusOS.Gauges_ValueType_RisingPercentage
			phaseModel: root.measurements.phases
			maximumValue: Global.system.load.maximumAcCurrent
			animationEnabled: root.animationEnabled
			inOverviewWidget: true
		}
	}

	Component {
		id: phaseComponent

		ThreePhaseDisplay {
			model: root.measurements.phases
			widgetSize: root.size
			valueType: VenusOS.Gauges_ValueType_RisingPercentage
			maximumValue: Global.system.load.maximumAcCurrent
		}
	}

	Component {
		id: historyGraphComponent

		LoadGraph {
			anchors {
				left: parent.left
				right: parent.right
				bottom: parent.bottom
			}
			height: Theme.geometry_briefPage_sidePanel_loadGraph_height
			externalSource: true
			backgroundColor: Theme.color_overviewPage_widget_background
			model: Global.graphHistory ? Global.graphHistory.acLoadsModel : []
			modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
			animationEnabled: root.animationEnabled
			threshold: 0
			zeroCentered: false
			aboveThresholdFillColor: Theme.color_green
		}
	}
}
