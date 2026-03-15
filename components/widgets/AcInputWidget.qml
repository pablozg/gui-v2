/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS

AcWidget {
	id: root

	readonly property AcInputSystemInfo inputInfo: input?.inputInfo ?? null
	property AcInput input
	readonly property bool inputOperational: input && input.operational
	readonly property bool _showHistoryGraph: inputOperational
			&& root.size >= VenusOS.OverviewWidget_Size_M
			&& root.phaseCount <= 1

	title: !!inputInfo ? Global.acInputs.sourceToText(inputInfo.source) : ""
	icon.source: !!inputInfo ? Global.acInputs.sourceIcon(inputInfo.source) : ""
	rightPadding: sideGaugeLoader.active ? Theme.geometry_overviewPage_widget_sideGauge_margins : 0
	quantityLabel.sourceType: VenusOS.ElectricalQuantity_Source_AcInputOnly
	quantityLabel.dataObject: inputOperational ? input : null
	quantityLabel.leftPadding: acInputDirectionIcon.visible ? (acInputDirectionIcon.width + Theme.geometry_acInputDirectionIcon_rightMargin) : 0
	overviewExtraDataObject: inputOperational ? input : null
	overviewExtraIsAc: true
	phaseCount: inputOperational ? input.phases.count : 0
	enabled: !!inputInfo
	extraContentLoader.active: root.phaseCount > 1 || root._showHistoryGraph
	extraContentLoader.sourceComponent: root.phaseCount > 1 ? phaseComponent : historyGraphComponent

	onClicked: {
		const inputServiceUid = BackendConnection.serviceUidFromName(root.inputInfo.serviceName, root.inputInfo.deviceInstance)
		if (root.inputInfo.serviceType === "acsystem") {
			Global.pageManager.pushPage("/pages/settings/devicelist/rs/PageRsSystem.qml",
					{ "bindPrefix": inputServiceUid })
		} else if (root.inputInfo.serviceType === "vebus") {
			Global.pageManager.pushPage( "/pages/vebusdevice/PageVeBus.qml", {
				"bindPrefix": inputServiceUid
			})
		} else if (root.inputInfo.serviceType === "genset") {
			Global.pageManager.pushPage( "/pages/settings/devicelist/PageGenset.qml", {
				"bindPrefix": inputServiceUid
			})
		} else {
			// Assume this is on a generic AC input
			Global.pageManager.pushPage("/pages/settings/devicelist/ac-in/PageAcIn.qml", {
				"bindPrefix": inputServiceUid
			})
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
		active: root.inputOperational && root.size >= VenusOS.OverviewWidget_Size_M
		sourceComponent: ThreePhaseBarGauge {
			valueType: VenusOS.Gauges_ValueType_NeutralPercentage
			phaseModel: root.input.phases
			minimumValue: root.inputInfo?.minimumCurrent ?? NaN
			maximumValue: root.inputInfo?.maximumCurrent ?? NaN
			inputMode: true
			animationEnabled: root.animationEnabled
			inOverviewWidget: true
		}
	}

	Component {
		id: phaseComponent

		ThreePhaseDisplay {
			width: parent.width
			model: root.input.phases
			widgetSize: root.size
			inputMode: true
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
			model: Global.graphHistory ? Global.graphHistory.acInputModel : []
			modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
			animationEnabled: root.animationEnabled
			aboveThresholdFillColor: Theme.color_blue
			belowThresholdFillColor: Global.graphHistory && Global.graphHistory.acInputShowsFeedIn ? Theme.color_green : Theme.color_blue
			initialModelValue: Global.graphHistory ? Global.graphHistory.acInputInitialModelValue : 0
			zeroCentered: Global.graphHistory ? Global.graphHistory.acInputShowsFeedIn : false
			threshold: Global.graphHistory ? Global.graphHistory.acInputThreshold : 0
		}
	}

	Label {
		anchors {
			top: root.extraContent.top
			topMargin: Theme.geometry_overviewPage_widget_extraContent_topMargin
			left: root.extraContent.left
			leftMargin: Theme.geometry_overviewPage_widget_content_horizontalMargin
			right: root.extraContent.right
			rightMargin: Theme.geometry_overviewPage_widget_content_horizontalMargin
		}
		elide: Text.ElideRight
		text: root.inputInfo && root.inputInfo.source === VenusOS.AcInputs_InputSource_Generator
				? CommonWords.stopped
				: CommonWords.disconnected
		visible: !root.inputOperational
	}

	AcInputDirectionIcon {
		id: acInputDirectionIcon
		parent: root.quantityLabel
		anchors.verticalCenter: parent.verticalCenter
		input: root.input
	}
}
