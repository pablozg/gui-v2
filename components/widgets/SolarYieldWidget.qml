/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS

OverviewWidget {
	id: root
	property var solarDataObject: Global.system.solar
	property bool phaseDataEnabled: true
	property bool historyEnabled: true
	property bool currentGaugeEnabled: true
	property bool forceListNavigation: false

	readonly property PvInverter _singlePvInverter: PvInverter {
		serviceUid: Global.solarInputs.pvInverterDevices.firstObject?.serviceUid ?? ""
	}
	readonly property bool _showPhaseData: root.phaseDataEnabled
			&& Global.solarInputs.pvInverterDevices.count === 1
			&& Global.solarInputs.devices.count === 0
			&& _singlePvInverter.phases.count > 1
	readonly property bool _showCurrentGauge: root.currentGaugeEnabled
			&& root.size >= VenusOS.OverviewWidget_Size_M
			&& root.solarDataObject !== null
			&& root.solarDataObject !== undefined
			&& !isNaN(root.solarDataObject.current)
			&& !isNaN(root.solarDataObject.maximumCurrent)
			&& root.solarDataObject.maximumCurrent > 0
	readonly property real _sideGaugeInset: _showCurrentGauge
			? Theme.geometry_barGauge_vertical_width_large + Theme.geometry_overviewPage_widget_sideGauge_margins
			: 0
	readonly property int _currentGaugeStatus: Theme.getValueStatus(solarCurrentRange.valueAsRatio * 100, VenusOS.Gauges_ValueType_RisingPercentage)

	onClicked: {
		if (root.forceListNavigation) {
			Global.pageManager.pushPage("/pages/solar/SolarInputListPage.qml", { "title": root.title })
			return
		}
		const singleDeviceOnly = (Global.solarInputs.devices.count + Global.solarInputs.pvInverterDevices.count) === 1
		if (singleDeviceOnly && Global.solarInputs.devices.count === 1) {
			Global.pageManager.pushPage("/pages/solar/SolarDevicePage.qml",
					{ "serviceUid": Global.solarInputs.devices.firstObject.serviceUid })
		} else if (singleDeviceOnly && Global.solarInputs.pvInverterDevices.count === 1) {
			Global.pageManager.pushPage("/pages/solar/PvInverterPage.qml",
					{ "serviceUid": Global.solarInputs.pvInverterDevices.firstObject.serviceUid })
		} else {
			Global.pageManager.pushPage("/pages/solar/SolarInputListPage.qml", { "title": root.title })
		}
	}

	//% "Solar yield"
	title: qsTrId("overview_widget_solaryield_title")
	icon.source: "qrc:/images/solaryield.svg"
	type: VenusOS.OverviewWidget_Type_Solar
	enabled: true
	rightPadding: root._sideGaugeInset
	quantityLabel.dataObject: root.size !== VenusOS.OverviewWidget_Size_Zero ? root.solarDataObject : null
	overviewExtraDataObject: root.size !== VenusOS.OverviewWidget_Size_Zero ? root.solarDataObject : null
	overviewExtraIsAc: root.size !== VenusOS.OverviewWidget_Size_Zero && !!root.solarDataObject && root.solarDataObject.voltageIsAc
	preferredSize: extraContentLoader.status !== Loader.Null
			? VenusOS.OverviewWidget_PreferredSize_PreferLarge
			: VenusOS.OverviewWidget_PreferredSize_Any

	// Per-side widgets use the same component, but the history model is only meaningful for the
	// overall solar total. In split mode the caller disables history/phase data.
	extraContentChildren: [
		Loader {
			id: extraContentLoader

			anchors {
				left: parent.left
				leftMargin: sourceComponent === historyComponent ? Theme.geometry_overviewPage_widget_content_horizontalMargin : 0
				right: parent.right
				rightMargin: sourceComponent === historyComponent
						? Theme.geometry_overviewPage_widget_content_horizontalMargin
						: 0
				bottom: parent.bottom
				bottomMargin: sourceComponent === historyComponent
					? Theme.geometry_overviewPage_widget_content_verticalMargin
					: root.verticalMargin
			}
			active: root._showPhaseData
					? root.size >= VenusOS.OverviewWidget_Size_L
					: root.historyEnabled && root.size >= VenusOS.OverviewWidget_Size_M
			sourceComponent: {
				if (root._showPhaseData) {
					return phaseComponent
				}
				return root.historyEnabled ? historyComponent : null
			}
		}

	]

	Component {
		id: phaseComponent

		ThreePhaseDisplay {
			leftPadding: Theme.geometry_overviewPage_widget_content_horizontalMargin
			rightPadding: Theme.geometry_overviewPage_widget_content_horizontalMargin
			model: root._singlePvInverter.phases
			visible: model.count > 1
			widgetSize: root.size
		}
	}

	Component {
		id: historyComponent

		LoadGraph {
			anchors {
				left: parent.left
				right: parent.right
				bottom: parent.bottom
			}
			height: Theme.geometry_briefPage_sidePanel_loadGraph_height
			externalSource: true
			backgroundColor: Theme.color_overviewPage_widget_background
			model: Global.graphHistory ? Global.graphHistory.solarModel : []
			modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
			animationEnabled: root.animationEnabled
			threshold: 0
			normalizeToVisibleMaximum: true
			trimLeadingInitialValues: false
			aboveThresholdFillColor: "#FFD700"
		}
	}

	ValueRange {
		id: solarCurrentRange
		value: root._showCurrentGauge ? Math.abs(root.solarDataObject.current) : NaN
		minimumValue: 0
		maximumValue: root.solarDataObject ? root.solarDataObject.maximumCurrent : NaN
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
		sourceComponent: Global.isGxDevice ? cheapGauge : prettyGauge
	}

	Component {
		id: cheapGauge

		CheapBarGauge {
			foregroundColor: Theme.statusColorValue(root._currentGaugeStatus)
			backgroundColor: root._currentGaugeStatus === Theme.Ok
					? Theme.color_darkishBlue
					: Theme.statusColorValue(root._currentGaugeStatus, true)
			valueType: VenusOS.Gauges_ValueType_RisingPercentage
			value: solarCurrentRange.valueAsRatio
			orientation: Qt.Vertical
			animationEnabled: root.animationEnabled
		}
	}

	Component {
		id: prettyGauge

		BarGauge {
			foregroundColor: Theme.statusColorValue(root._currentGaugeStatus)
			backgroundColor: root._currentGaugeStatus === Theme.Ok
					? Theme.color_darkishBlue
					: Theme.statusColorValue(root._currentGaugeStatus, true)
			valueType: VenusOS.Gauges_ValueType_RisingPercentage
			value: solarCurrentRange.valueAsRatio
			orientation: Qt.Vertical
			animationEnabled: root.animationEnabled
		}
	}
}
