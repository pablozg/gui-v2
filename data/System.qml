/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS

QtObject {
	id: root

	readonly property string serviceUid: BackendConnection.serviceUidForType("system")
	readonly property int state: _systemState.valid ? _systemState.value : VenusOS.System_State_Off

	readonly property bool hasGridMeter: _gridDeviceType.valid
	readonly property bool hasAcOutSystem: _hasAcOutSystem.valid && _hasAcOutSystem.value === 1
	readonly property bool hasAcLoads: !_hasAcLoads.valid || _hasAcLoads.value === 1 // show AC loads by default if the path isn't valid
	readonly property bool hasVebusEss: _systemType.value === "ESS" || _systemType.value === "Hub-4"
	readonly property bool hasEss: hasVebusEss || _systemType.value === "AC System"
	readonly property bool showInputLoads: load.acIn.hasPower
			&& (hasVebusEss ? (hasGridMeter && _withoutGridMeter.value === 0) : hasGridMeter)
	readonly property bool feedbackEnabled: _feedbackEnabled.value === 1

	readonly property ActiveSystemBattery battery: ActiveSystemBattery {
		systemServiceUid: root.serviceUid
	}

	readonly property QtObject load: SystemLoad {
		systemServiceUid: root.serviceUid
	}

	readonly property QtObject dc: QtObject {
		// Regardless of the actual power value, regard the system as having DC power (and show
		// DC Loads in the UI) if any relevant DC services are present or if /HasDcSystem=1.
		readonly property bool hasPower: serviceModel.count > 0 || _hasDcSystem.value === 1

		readonly property real power: hasPower ? _dcSystemPower.value || 0 : NaN
		readonly property bool currentValid: !isNaN(power) && !isNaN(voltage) && (voltage !== 0)
		readonly property real current: currentValid ? power / voltage : NaN
		readonly property real voltage: _dcBatteryVoltage.valid ? _dcBatteryVoltage.value : NaN
		readonly property real maximumPower: _maximumDcPower.valid ? _maximumDcPower.value : NaN

		readonly property VeQuickItem _dcSystemPower: VeQuickItem {
			uid: root.serviceUid + "/Dc/System/Power"
		}

		readonly property VeQuickItem _dcBatteryVoltage: VeQuickItem {
			uid: root.serviceUid + "/Dc/Battery/Voltage"
		}

		readonly property VeQuickItem _maximumDcPower: VeQuickItem {
			uid: Global.systemSettings.serviceUid + "/Settings/Gui/Gauges/Dc/System/Power/Max"
		}

		readonly property VeQuickItem _hasDcSystem: VeQuickItem {
			uid: Global.systemSettings.serviceUid + "/Settings/SystemSetup/HasDcSystem"
		}

		readonly property FilteredServiceModel serviceModel: FilteredServiceModel {
			serviceTypes: ["dcload", "dcsystem", "dcdc"]
		}
	}

	readonly property QtObject solar: QtObject {
		id: solarData

		property real power: NaN
		property real acPower: NaN
		property real dcPower: NaN
		property real acCurrent: NaN
		property real dcCurrent: NaN
		property real current: NaN
		property real voltage: NaN
		property bool voltageIsAc: false
		property real maximumPower: NaN
		property real maximumCurrent: NaN
		readonly property bool hasAcInputPv: pvOnGrid.hasPower || pvOnGenset.hasPower
		readonly property bool hasAcOutputPv: pvOnOutput.hasPower
		readonly property bool hasDcPv: _dcPvPower.valid || _dcPvCurrent.valid
		readonly property bool hasInputSideSolar: hasAcInputPv || hasDcPv

		readonly property QtObject inputSide: QtObject {
			property real power: NaN
			property real acPower: NaN
			property real dcPower: NaN
			property real acCurrent: NaN
			property real dcCurrent: NaN
			property real current: NaN
			property real voltage: NaN
			property bool voltageIsAc: false
			property real maximumPower: NaN
			property real maximumCurrent: NaN
		}

		readonly property QtObject outputSide: QtObject {
			property real power: NaN
			property real acPower: NaN
			property real dcPower: NaN
			property real acCurrent: NaN
			property real dcCurrent: NaN
			property real current: NaN
			property real voltage: NaN
			property bool voltageIsAc: false
			property real maximumPower: NaN
			property real maximumCurrent: NaN
		}

		function _sumValues() {
			let total = NaN
			for (let i = 0; i < arguments.length; ++i) {
				total = Units.sumRealNumbers(total, arguments[i])
			}
			return total
		}

		function _mergeVoltages() {
			let mergedVoltage = NaN
			let voltageMismatch = false
			for (let i = 0; i < arguments.length; ++i) {
				const value = arguments[i]
				if (isNaN(value)) {
					continue
				}
				if (isNaN(mergedVoltage)) {
					mergedVoltage = value
				} else if (Math.abs(mergedVoltage - value) > 1) {
					voltageMismatch = true
				}
			}
			return voltageMismatch ? NaN : mergedVoltage
		}

		function _updateSource(target, acPowerValue, acCurrentValue, acVoltageValue, dcPowerValue, dcCurrentValue, maximumPowerValue) {
			target.acPower = acPowerValue
			target.acCurrent = acCurrentValue
			target.dcPower = dcPowerValue
			target.dcCurrent = dcCurrentValue
			target.maximumPower = maximumPowerValue
			target.power = _sumValues(acPowerValue, dcPowerValue)

			const acMeasurementsAvailable = !isNaN(acCurrentValue) || !isNaN(acVoltageValue)
			const dcMeasurementsAvailable = !isNaN(dcCurrentValue)
			if (acMeasurementsAvailable && !dcMeasurementsAvailable) {
				target.current = acCurrentValue
				target.voltage = acVoltageValue
				target.voltageIsAc = !isNaN(acVoltageValue)
			} else if (dcMeasurementsAvailable && !acMeasurementsAvailable) {
				target.current = dcCurrentValue
				target.voltage = NaN
				target.voltageIsAc = false
			} else {
				// Mixed AC+DC solar has no single meaningful V/A pair to display.
				target.current = NaN
				target.voltage = NaN
				target.voltageIsAc = false
			}

			const configuredMaximumCurrent = (!isNaN(maximumPowerValue) && !isNaN(target.voltage) && target.voltage !== 0)
					? Math.abs(maximumPowerValue / target.voltage)
					: NaN
			const absoluteCurrent = Math.abs(target.current)
			let nextMaximumCurrent = target.maximumCurrent
			if (!isNaN(configuredMaximumCurrent) && (isNaN(nextMaximumCurrent) || configuredMaximumCurrent > nextMaximumCurrent)) {
				nextMaximumCurrent = configuredMaximumCurrent
			}
			if (!isNaN(absoluteCurrent) && (isNaN(nextMaximumCurrent) || absoluteCurrent > nextMaximumCurrent)) {
				nextMaximumCurrent = absoluteCurrent
			}
			target.maximumCurrent = nextMaximumCurrent
		}

		function _refresh() {
			const inputAcPower = _sumValues(pvOnGrid.totalPhasePower(), pvOnGenset.totalPhasePower())
			const inputAcCurrent = _sumValues(pvOnGrid.current, pvOnGenset.current)
			const inputAcVoltage = _mergeVoltages(pvOnGrid.voltage, pvOnGenset.voltage)
			const outputAcPower = pvOnOutput.totalPhasePower()
			const outputAcCurrent = pvOnOutput.current
			const outputAcVoltage = pvOnOutput.voltage
			const dcPowerValue = _dcPvPower.valid ? _dcPvPower.value : NaN
			const dcCurrentValue = _dcPvCurrent.valid ? _dcPvCurrent.value : NaN
			const configuredMaximumPower = _maximumPower.valid ? _maximumPower.value : NaN

			_updateSource(
					inputSide,
					inputAcPower,
					inputAcCurrent,
					inputAcVoltage,
					dcPowerValue,
					dcCurrentValue,
					hasAcOutputPv ? NaN : configuredMaximumPower)

			_updateSource(
					outputSide,
					outputAcPower,
					outputAcCurrent,
					outputAcVoltage,
					NaN,
					NaN,
					hasInputSideSolar ? NaN : configuredMaximumPower)

			_updateSource(
					solarData,
					_sumValues(inputAcPower, outputAcPower),
					_sumValues(inputAcCurrent, outputAcCurrent),
					_mergeVoltages(inputAcVoltage, outputAcVoltage),
					dcPowerValue,
					dcCurrentValue,
					configuredMaximumPower)
		}

		readonly property VeQuickItem _maximumPower: VeQuickItem {
			uid: Global.systemSettings.serviceUid + "/Settings/Gui/Gauges/Pv/Power/Max"
		}

		readonly property ObjectAcConnection pvOnGrid: ObjectAcConnection {
			bindPrefix: root.serviceUid + "/Ac/PvOnGrid"
		}

		readonly property ObjectAcConnection pvOnGenset: ObjectAcConnection {
			bindPrefix: root.serviceUid + "/Ac/PvOnGenset"
		}

		readonly property ObjectAcConnection pvOnOutput: ObjectAcConnection {
			bindPrefix: root.serviceUid + "/Ac/PvOnOutput"
		}

		readonly property VeQuickItem _dcPvPower: VeQuickItem {
			uid: root.serviceUid + "/Dc/Pv/Power"
		}

		readonly property VeQuickItem _dcPvCurrent: VeQuickItem {
			uid: root.serviceUid + "/Dc/Pv/Current"
		}

		readonly property Connections _pvOnGridConnection: Connections {
			target: solarData.pvOnGrid
			function onPowerChanged() { solarData._refresh() }
			function onCurrentChanged() { solarData._refresh() }
			function onVoltageChanged() { solarData._refresh() }
			function onHasPowerChanged() { solarData._refresh() }
		}

		readonly property Connections _pvOnGensetConnection: Connections {
			target: solarData.pvOnGenset
			function onPowerChanged() { solarData._refresh() }
			function onCurrentChanged() { solarData._refresh() }
			function onVoltageChanged() { solarData._refresh() }
			function onHasPowerChanged() { solarData._refresh() }
		}

		readonly property Connections _pvOnOutputConnection: Connections {
			target: solarData.pvOnOutput
			function onPowerChanged() { solarData._refresh() }
			function onCurrentChanged() { solarData._refresh() }
			function onVoltageChanged() { solarData._refresh() }
			function onHasPowerChanged() { solarData._refresh() }
		}

		readonly property Connections _dcPvPowerConnection: Connections {
			target: solarData._dcPvPower
			function onValueChanged() { solarData._refresh() }
			function onValidChanged() { solarData._refresh() }
		}

		readonly property Connections _dcPvCurrentConnection: Connections {
			target: solarData._dcPvCurrent
			function onValueChanged() { solarData._refresh() }
			function onValidChanged() { solarData._refresh() }
		}

		readonly property Connections _maximumPowerConnection: Connections {
			target: solarData._maximumPower
			function onValueChanged() { solarData._refresh() }
			function onValidChanged() { solarData._refresh() }
		}

		readonly property Timer _refreshTimer: Timer {
			interval: 1000
			repeat: true
			running: BackendConnection.applicationVisible
			onTriggered: solarData._refresh()
		}

		Component.onCompleted: _refresh()
	}

	readonly property QtObject veBus: QtObject {
		readonly property string serviceUid: BackendConnection.serviceUidFromName(_serviceName.value || "", _deviceInstance.value || 0)

		readonly property VeQuickItem _serviceName: VeQuickItem { uid: root.serviceUid + "/VebusService" }
		readonly property VeQuickItem _deviceInstance: VeQuickItem { uid: root.serviceUid + "/VebusInstance" }
	}

	readonly property VeQuickItem _systemState: VeQuickItem {
		uid: root.serviceUid + "/SystemState/State"
	}

	readonly property VeQuickItem _systemType: VeQuickItem {
		uid: root.serviceUid + "/SystemType"
	}

	readonly property VeQuickItem _gridDeviceType: VeQuickItem {
		uid: root.serviceUid + "/Ac/Grid/DeviceType"
	}

	readonly property VeQuickItem _hasAcLoads: VeQuickItem {
		uid: root.serviceUid + "/Ac/HasAcLoads"
	}

	readonly property VeQuickItem _hasAcOutSystem: VeQuickItem {
		uid: Global.systemSettings.serviceUid + "/Settings/SystemSetup/HasAcOutSystem"
	}

	readonly property VeQuickItem _withoutGridMeter: VeQuickItem {
		uid: Global.systemSettings.serviceUid + "/Settings/CGwacs/RunWithoutGridMeter"
	}

	readonly property VeQuickItem _feedbackEnabled: VeQuickItem {
		uid: root.serviceUid + "/Ac/ActiveIn/FeedbackEnabled"
	}

	function systemStateToText(s) {
		switch (s) {
		case VenusOS.System_State_Off:
			return CommonWords.off
		case VenusOS.System_State_LowPower:
			//% "AES mode"
			return qsTrId("inverters_state_aes_mode")
		case VenusOS.System_State_FaultCondition:
			//% "Fault condition"
			return qsTrId("inverters_state_faultcondition")
		case VenusOS.System_State_BulkCharging:
			//% "Bulk charging"
			return qsTrId("inverters_state_bulkcharging")
		case VenusOS.System_State_AbsorptionCharging:
			//% "Absorption charging"
			return qsTrId("inverters_state_absorptioncharging")
		case VenusOS.System_State_FloatCharging:
			//% "Float charging"
			return qsTrId("inverters_state_floatcharging")
		case VenusOS.System_State_StorageMode:
			//% "Storage mode"
			return qsTrId("inverters_state_storagemode")
		case VenusOS.System_State_EqualizationCharging:
			//% "Equalization charging"
			return qsTrId("inverters_state_equalisationcharging")
		case VenusOS.System_State_PassThrough:
			//% "Pass-thru"
			return qsTrId("inverters_state_passthru")
		case VenusOS.System_State_Inverting:
			//% "Inverting"
			return qsTrId("inverters_state_inverting")
		case VenusOS.System_State_Assisting:
			//% "Assisting"
			return qsTrId("inverters_state_assisting")
		case VenusOS.System_State_PowerSupplyMode:
			//% "Power supply mode"
			return qsTrId("inverters_state_powersupplymode")
		case VenusOS.System_State_Sustain:
			//% "Sustain"
			return qsTrId("inverters_state_sustain")

		case VenusOS.System_State_Wakeup:
			//% "Wake up"
			return qsTrId("inverters_state_wakeup")
		case VenusOS.System_State_RepeatedAbsorption:
			//% "Repeated absorption"
			return qsTrId("inverters_state_repeatedabsorption")
		case VenusOS.System_State_AutoEqualize:
			//% "Auto equalize"
			return qsTrId("inverters_state_autoequalize")
		case VenusOS.System_State_BatterySafe:
			//% "Battery safe"
			return qsTrId("inverters_state_battery_safe")
		case VenusOS.System_State_LoadDetect:
			//% "Load detect"
			return qsTrId("inverters_state_loaddetect")
		case VenusOS.System_State_Blocked:
			//% "Blocked"
			return qsTrId("inverters_state_blocked")
		case VenusOS.System_State_Test:
			//% "Test"
			return qsTrId("inverters_state_test")
		case VenusOS.System_State_ExternalControl:
			//% "External control"
			return qsTrId("inverters_state_externalccontrol")

		case VenusOS.System_State_Discharging:
			return CommonWords.discharging
		case VenusOS.System_State_SystemSustain:
			//% "Sustain"
			return qsTrId("inverters_state_system_sustain")
		case VenusOS.System_State_Recharge:
			//% "Recharge"
			return qsTrId("inverters_state_recharge")
		case VenusOS.System_State_ScheduledCharge:
			//% "Scheduled"
			return qsTrId("inverters_state_scheduledcharge")
		case VenusOS.System_State_DynamicESS:
			//% "Dynamic ESS"
			return qsTrId("inverters_state_dynamic_ess")
		default:
			return CommonWords.unknown_status
		}
	}

	Component.onCompleted: Global.system = root
}
