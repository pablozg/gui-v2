/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Layouts
import Victron.VenusOS

ColumnLayout {
	id: root

	property bool animationEnabled
	readonly property real _uniformCurrentGaugeHeight: Theme.geometry_barGauge_vertical_width_large

	readonly property AcInput generatorInput: Global.acInputs.input1?.source === VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input1
			: Global.acInputs.input2?.source === VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input2
			: null
	readonly property AcInput nonGeneratorInput: Global.acInputs.input1?.source !== VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input1
			: Global.acInputs.input2?.source !== VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input2
			: null

		BriefSidePanelWidget {
			//% "Solar yield"
			title: qsTrId("brief_solar_yield")
			icon.source: "qrc:/images/solaryield.svg"
			loadersActive: Global.solarInputs.inputCount > 0
			visible: Global.solarInputs.inputCount > 0 // show if there are any solar inputs (PV chargers, PV inverters, etc.)
			quantityLabel.dataObject: Global.system.solar
			extraDataObject: Global.system.solar
			extraIsAc: Global.system.solar.voltageIsAc
			sideComponent: LoadGraph {
				externalSource: true
				model: Global.graphHistory ? Global.graphHistory.solarModel : []
				modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
				animationEnabled: root.animationEnabled
				threshold: 0
				normalizeToVisibleMaximum: true
				aboveThresholdFillColor: "#FFD700"
			}

			bottomComponent: _currentGaugeVisible ? (Global.isGxDevice ? cheapSolarGauge : prettySolarGauge) : null

			readonly property bool _currentGaugeVisible: !isNaN(Global.system.solar.current)
					&& !isNaN(Global.system.solar.maximumCurrent)
					&& Global.system.solar.maximumCurrent > 0

			ValueRange {
				id: solarCurrentRange
				value: parent.visible ? Math.abs(Global.system.solar.current) : NaN
				minimumValue: 0
				maximumValue: Global.system.solar.maximumCurrent
			}

			Component {
				id: cheapSolarGauge
				CheapBarGauge {
					width: parent.width
					height: root._uniformCurrentGaugeHeight
					orientation: Qt.Horizontal
					valueType: VenusOS.Gauges_ValueType_RisingPercentage
					value: solarCurrentRange.valueAsRatio
					animationEnabled: root.animationEnabled
				}
			}

			Component {
				id: prettySolarGauge
				BarGauge {
					width: parent.width
					height: root._uniformCurrentGaugeHeight
					orientation: Qt.Horizontal
					valueType: VenusOS.Gauges_ValueType_RisingPercentage
					value: solarCurrentRange.valueAsRatio
					animationEnabled: root.animationEnabled
				}
			}
		}

	BriefSidePanelWidget {
		id: batteryWidget

		title: CommonWords.battery
		icon.source: "qrc:/images/icon_battery_24.svg"
		quantityLabel.sourceType: VenusOS.ElectricalQuantity_Source_Dc
		quantityLabel.dataObject: Global.system.battery
		quantityLabel.showAbsoluteValue: batteryDirectionIcon.visible
		quantityLabel.leftPadding: batteryDirectionIcon.visible ? (batteryDirectionIcon.width + Theme.geometry_acInputDirectionIcon_rightMargin) : 0
		extraDataObject: Global.system.battery
		extraIsAc: false
		loadersActive: !isNaN(Global.system.battery.power)
		visible: loadersActive

		BatteryDirectionIcon {
			id: batteryDirectionIcon
			parent: batteryWidget.quantityLabel
			anchors.verticalCenter: parent.verticalCenter
			battery: Global.system.battery
		}

		sideComponent: LoadGraph {
			externalSource: true
			model: Global.graphHistory ? Global.graphHistory.batteryModel : []
			modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
			animationEnabled: root.animationEnabled
			aboveThresholdFillColor: Theme.color_green
			belowThresholdFillColor: Theme.color_red
			initialModelValue: Global.graphHistory ? Global.graphHistory.batteryInitialModelValue : 0.5
			zeroCentered: true
			threshold: Global.graphHistory ? Global.graphHistory.batteryThreshold : 0.5
		}

		bottomComponent: _currentGaugeVisible ? (Global.isGxDevice ? cheapBatteryGauge : prettyBatteryGauge) : null

		readonly property bool _currentGaugeVisible: !isNaN(Global.system.battery.current)
				&& !isNaN(Global.system.battery.maximumCurrent)
				&& Global.system.battery.maximumCurrent > 0

		ValueRange {
			id: batteryCurrentRange
			value: parent.visible ? Math.abs(Global.system.battery.current) : NaN
			minimumValue: 0
			maximumValue: Global.system.battery.maximumCurrent
		}

		Component {
			id: cheapBatteryGauge
			CheapBarGauge {
				width: parent.width
				height: root._uniformCurrentGaugeHeight
				orientation: Qt.Horizontal
				valueType: VenusOS.Gauges_ValueType_RisingPercentage
				value: batteryCurrentRange.valueAsRatio
				animationEnabled: root.animationEnabled
			}
		}

		Component {
			id: prettyBatteryGauge
			BarGauge {
				width: parent.width
				height: root._uniformCurrentGaugeHeight
				orientation: Qt.Horizontal
				valueType: VenusOS.Gauges_ValueType_RisingPercentage
				value: batteryCurrentRange.valueAsRatio
				animationEnabled: root.animationEnabled
			}
		}
	}

	// In most cases there is only 1 generator, so don't worry about other ones here.
	BriefSidePanelWidget {
		id: generatorWidget

		title: Global.generators.model.firstObject?.name ?? ""
		icon.source: "qrc:/images/generator.svg"
		loadersActive: generatorInput && generatorInput.operational && Global.generators.model.firstObject
		visible: loadersActive
		quantityLabel.sourceType: VenusOS.ElectricalQuantity_Source_AcInputOnly
		quantityLabel.dataObject: generatorInput
		quantityLabel.leftPadding: generatorDirectionIcon.visible ? (generatorDirectionIcon.width + Theme.geometry_acInputDirectionIcon_rightMargin) : 0
		extraDataObject: generatorInput
		extraIsAc: true
		sideComponent: Item {
			width: generatorLabel.width
			height: generatorLabel.height

			GeneratorIconLabel {
				id: generatorLabel

				anchors {
					right: parent.right
					bottom: parent.bottom
				}
				generator: Generator {
					serviceUid: Global.generators.model.firstObject?.serviceUid ?? ""
				}
			}
		}
		bottomComponent: ThreePhaseBarGauge {
			width: parent.width
			height: root._uniformCurrentGaugeHeight
			orientation: Qt.Horizontal
			phaseModel: root.visible ? generatorInput.phases : null
			minimumValue: generatorInput.inputInfo.minimumCurrent
			maximumValue: generatorInput.inputInfo.maximumCurrent
			animationEnabled: root.animationEnabled
			inputMode: true
		}

		AcInputDirectionIcon {
			id: generatorDirectionIcon
			parent: generatorWidget.quantityLabel
			anchors.verticalCenter: parent.verticalCenter
			input: generatorInput
		}
	}

	BriefSidePanelWidget {
		id: acInputWidget

		title: loadersActive ? Global.acInputs.sourceToText(nonGeneratorInput.source) : ""
		icon.source: loadersActive ? Global.acInputs.sourceIcon(nonGeneratorInput.source) : ""
		quantityLabel.sourceType: VenusOS.ElectricalQuantity_Source_AcInputOnly
		quantityLabel.dataObject: nonGeneratorInput
		quantityLabel.leftPadding: acInputDirectionIcon.visible ? (acInputDirectionIcon.width + Theme.geometry_acInputDirectionIcon_rightMargin) : 0
		extraDataObject: nonGeneratorInput
		extraIsAc: true
		loadersActive: nonGeneratorInput && nonGeneratorInput.operational
		visible: loadersActive

		AcInputDirectionIcon {
			id: acInputDirectionIcon
			parent: acInputWidget.quantityLabel
			anchors.verticalCenter: parent.verticalCenter
			input: nonGeneratorInput
		}

		sideComponent: LoadGraph {
			externalSource: true
			model: Global.graphHistory ? Global.graphHistory.acInputModel : []
			modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
			animationEnabled: root.animationEnabled
			aboveThresholdFillColor: Global.graphHistory && Global.graphHistory.acInputShowsFeedIn ? Theme.color_green : Theme.color_red
			belowThresholdFillColor: Global.graphHistory && Global.graphHistory.acInputShowsFeedIn ? Theme.color_red : Theme.color_blue
			initialModelValue: Global.graphHistory ? Global.graphHistory.acInputInitialModelValue : 0
			invertValues: Global.graphHistory ? Global.graphHistory.acInputShowsFeedIn : false
			zeroCentered: Global.graphHistory ? Global.graphHistory.acInputShowsFeedIn : false
			threshold: Global.graphHistory ? Global.graphHistory.acInputThreshold : 0
		}

		bottomComponent: ThreePhaseBarGauge {
			width: parent.width
			height: root._uniformCurrentGaugeHeight
			orientation: Qt.Horizontal
			phaseModel: root.visible ? nonGeneratorInput.phases : null
			minimumValue: nonGeneratorInput.inputInfo.minimumCurrent
			maximumValue: nonGeneratorInput.inputInfo.maximumCurrent
			animationEnabled: root.animationEnabled
			inputMode: true
		}
	}

	BriefSidePanelWidget {
		title: Global.dcInputs.model.count === 1
				? VenusOS.dcMeter_typeToText(Global.dcInputs.model.firstMeterType)
				  //% "DC input"
				: qsTrId("brief_dc_input")
		icon.source: Global.dcInputs.model.count === 1
				? VenusOS.dcMeter_iconForType(Global.dcInputs.model.firstMeterType)
				: VenusOS.dcMeter_iconForMultipleTypes()
		loadersActive: Global.dcInputs.model.count > 0
		visible: loadersActive
		quantityLabel.sourceType: VenusOS.ElectricalQuantity_Source_Dc
		quantityLabel.dataObject: Global.dcInputs
		extraDataObject: Global.dcInputs
		extraIsAc: false
			sideComponent: LoadGraph {
				externalSource: true
					model: Global.graphHistory ? Global.graphHistory.dcInputModel : []
						modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
						animationEnabled: root.animationEnabled
						threshold: 0    // no threshold needed for inputs
						normalizeToVisibleMaximum: true
						aboveThresholdFillColor: Theme.color_blue   // warning color is not needed for inputs
					}

		bottomComponent: Global.isGxDevice ? cheapGaugeDcInput : prettyGaugeDcInput

		ValueRange {
			id: dcInputRange
			value: root.visible ? Global.dcInputs.power : NaN
			maximumValue: Global.dcInputs.maximumPower
		}

		Component {
			id: cheapGaugeDcInput
			CheapBarGauge {
				orientation: Qt.Horizontal
				value: dcInputRange.valueAsRatio
				animationEnabled: root.animationEnabled
			}
		}

		Component {
			id : prettyGaugeDcInput
			BarGauge {
				orientation: Qt.Horizontal
				value: dcInputRange.valueAsRatio
				animationEnabled: root.animationEnabled
			}
		}
	}

	BriefSidePanelWidget {
		//% "AC Loads"
		title: qsTrId("brief_ac_loads")
		icon.source: "qrc:/images/acloads.svg"
		quantityLabel.sourceType: VenusOS.ElectricalQuantity_Source_Ac
		quantityLabel.dataObject: Global.system.load.ac
		extraDataObject: Global.system.load.ac
		extraIsAc: true
		loadersActive: Global.system.hasAcLoads
		visible: loadersActive
		sideComponent: LoadGraph {
			externalSource: true
			model: Global.graphHistory ? Global.graphHistory.acLoadsModel : []
			modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
			animationEnabled: root.animationEnabled
			threshold: 0
			zeroCentered: false
			normalizeToVisibleMaximum: true
			aboveThresholdFillColor: Theme.color_green
		}
		bottomComponent: ThreePhaseBarGauge {
			width: parent.width
			height: root._uniformCurrentGaugeHeight
			orientation: Qt.Horizontal
			valueType: VenusOS.Gauges_ValueType_RisingPercentage
			phaseModel: root.visible ? Global.system.load.ac.phases : null
			maximumValue: Global.system.load.maximumAcCurrent
			animationEnabled: root.animationEnabled
		}
	}

	BriefSidePanelWidget {
		//% "DC Loads"
		title: qsTrId("brief_dc_loads")
		icon.source: "qrc:/images/dcloads.svg"
		loadersActive: Global.system.dc.hasPower
		visible: loadersActive
		quantityLabel.sourceType: VenusOS.ElectricalQuantity_Source_Dc
		quantityLabel.dataObject: Global.system.dc
		extraDataObject: Global.system.dc
		extraIsAc: false
			sideComponent: LoadGraph {
				externalSource: true
					model: Global.graphHistory ? Global.graphHistory.dcLoadsModel : []
						modelLength: Global.graphHistory ? Global.graphHistory.modelLength : 480
						animationEnabled: root.animationEnabled
						threshold: 0
						normalizeToVisibleMaximum: true
						aboveThresholdFillColor: Theme.color_blue
					}

		bottomComponent: Global.isGxDevice ? cheapGaugeDcLoad : prettyGaugeDcLoad

		ValueRange {
			id: dcLoadRange
			value: root.visible ? Global.system.dc.power : NaN
			maximumValue: Global.system.dc.maximumPower
		}

		Component {
			id: cheapGaugeDcLoad
			CheapBarGauge {
				orientation: Qt.Horizontal
				valueType: VenusOS.Gauges_ValueType_RisingPercentage
				value: dcLoadRange.valueAsRatio
				animationEnabled: root.animationEnabled
			}
		}

		Component {
			id : prettyGaugeDcLoad
			BarGauge {
				orientation: Qt.Horizontal
				valueType: VenusOS.Gauges_ValueType_RisingPercentage
				value: dcLoadRange.valueAsRatio
				animationEnabled: root.animationEnabled
			}
		}
	}
}
