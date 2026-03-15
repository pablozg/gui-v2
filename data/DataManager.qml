/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS
import Victron.Mock

Item {
	id: root

	readonly property bool _dataObjectsReady: !!Global.acInputs
			&& !!Global.dcInputs
			&& !!Global.environmentInputs
			&& !!Global.evChargers
			&& !!Global.generators
			&& !!Global.inverterChargers
			&& !!Global.notifications
			&& !!Global.solarInputs
			&& !!Global.system
			&& !!Global.systemSettings
			&& !!Global.switches
			&& !!Global.tanks
			&& !!Global.venusPlatform
			&& !!RuntimeDeviceModel // ensure singleton is created

	readonly property bool _ready: _dataObjectsReady
			&& Global.backendReady
			&& (BackendConnection.type !== BackendConnection.MockSource || mockSetupLoader.mockLoaded)

	on_DataObjectsReadyChanged: if (_dataObjectsReady) console.info("DataManager: data objects ready")
	on_ReadyChanged: {
		if (_ready) {
			BackendConnection.ensureGraphHistorySettings()
			console.info("DataManager: loading complete")
			Global.dataManagerLoaded = true
		}
	}

	// Global data types
	AcInputs {}
	DcInputs {}
	EnvironmentInputs {}
	EvChargers {}
	Generators {}
	InverterChargers {}
	Notifications {}
	SolarInputs {}
	Switches {}
	System {}
	SystemSettings {}
	Tanks {}
	VenusPlatform {}

	// Persistent graph data collector — inline to avoid new type registration
	// (deploy-to-gx copies QML files but cannot update the qmldir)
	// Uses QtObject to avoid Item hierarchy issues on GX device
			QtObject {
				id: graphHistory

				readonly property int modelLength: 120
				readonly property int samplesPerPoint: 60
				readonly property int checkpointEveryPoints: 720

				readonly property bool acInputShowsFeedIn: _nonGeneratorInput
						&& _nonGeneratorInput.inputInfo.minimumCurrent < 0
				readonly property real acInputInitialModelValue: acInputShowsFeedIn ? 0.5 : 0
				readonly property real acInputThreshold: isNaN(_acInputMaxAboveZeroMidPoint) ? 0 : 0.5
				readonly property bool _publishesRuntimeHistory: BackendConnection.type === BackendConnection.DBusSource
				readonly property bool _readsRuntimeHistory: BackendConnection.type === BackendConnection.MqttSource
				readonly property string _runtimeHistoryServiceUid: _readsRuntimeHistory
						? BackendConnection.serviceUidForType("graphhistory")
						: ""

			property var solarModel: _normalizedModel([], "solarModel")
			property var acInputModel: _normalizedModel([], "acInputModel")
			property var dcInputModel: _normalizedModel([], "dcInputModel")
			property var acLoadsModel: _normalizedModel([], "acLoadsModel")
			property var dcLoadsModel: _normalizedModel([], "dcLoadsModel")

		readonly property var _nonGeneratorInput: Global.acInputs
			? (Global.acInputs.input1?.source !== VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input1
				: Global.acInputs.input2?.source !== VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input2
				: null)
			: null

		readonly property real _acInputMaxAboveZeroMidPoint: _nonGeneratorInput
			&& _nonGeneratorInput.inputInfo.minimumCurrent < 0
			&& _nonGeneratorInput.inputInfo.maximumCurrent > 0
				? Math.max(Math.abs(_nonGeneratorInput.inputInfo.minimumCurrent), _nonGeneratorInput.inputInfo.maximumCurrent)
				: NaN

			// Dynamic max tracking for channels whose Settings maximum may be NaN
			property real _solarDynMax: NaN
			property real _dcInputDynMax: NaN
			property real _dcLoadDynMax: NaN
			property real _acLoadDynMax: NaN

			function _initialValueForChannel(channelName) {
				return channelName === "acInputModel" ? acInputInitialModelValue : 0
			}

			function _normalizedModel(data, channelName) {
				const initialValue = _initialValueForChannel(channelName)
				if (!Array.isArray(data)) {
					return Array(modelLength).fill(initialValue)
				}
				if (data.length === modelLength) {
					return data.slice(0)
				}
				if (data.length > modelLength) {
					return data.slice(data.length - modelLength)
				}
				return Array(modelLength - data.length).fill(initialValue).concat(data)
			}

			function _ratioWithDynMax(value, settingsMax, dynMaxProp) {
				if (isNaN(value) || value <= 0) return 0
				if (!isNaN(settingsMax) && settingsMax > 0)
					return Math.min(value / settingsMax, 1)
					var currentMax = graphHistory[dynMaxProp]
					if (isNaN(currentMax) || value > currentMax) {
						graphHistory[dynMaxProp] = value
						currentMax = value
					}
					return currentMax > 0 ? value / currentMax : 0
				}

				property real _acPrevGraphMin: 0
				property real _acPrevGraphMax: 0

			function _scaleAcInputHistoricalData(prevMin, prevMax, newMin, newMax) {
				let temp = _normalizedModel(acInputModel, "acInputModel")
				for (let i = 0; i < temp.length; ++i) {
					const ratio = temp[i]
					const currentInAmps = FastUtils.scaleNumber(ratio, 0, 1, prevMin, prevMax)
					temp[i] = FastUtils.scaleNumber(currentInAmps, prevMin, prevMax, newMin, newMax)
				}
				acInputModel = temp
			}

				property int _solarAcc: 0; property real _solarSum: 0
				property int _acInputAcc: 0; property real _acInputSum: 0
				property int _dcInputAcc: 0; property real _dcInputSum: 0
				property int _acLoadsAcc: 0; property real _acLoadsSum: 0
				property int _dcLoadsAcc: 0; property real _dcLoadsSum: 0
				property bool _dirty: false
				property int _dirtyPointCount: 0
				property bool _needsRuntimeSeed: false

				function _hasMeaningfulData(model, channelName) {
					const initialValue = _initialValueForChannel(channelName)
					const normalized = _normalizedModel(model, channelName)
					for (let i = 0; i < normalized.length; ++i) {
						if (Math.abs((normalized[i] ?? initialValue) - initialValue) > 0.0001) {
							return true
						}
					}
					return false
				}

				function _pushValue(channelName, value) {
					let temp = _normalizedModel(graphHistory[channelName], channelName)
					temp.push(value)
					temp.shift()
					graphHistory[channelName] = temp
					_dirty = true
				}

				function _serializedModel(model, channelName) {
					var rounded = graphHistory._normalizedModel(model, channelName).map(function(v) {
						return Math.round(v * 10000) / 10000
					})
					return JSON.stringify(rounded)
				}

				function _parsedModelFromValue(value, channelName) {
					if (!value) {
						return null
					}
					try {
						var saved = JSON.parse(value)
						if (Array.isArray(saved) && saved.length > 0) {
							return graphHistory._normalizedModel(saved, channelName)
						}
					} catch(e) {
					}
					return null
				}

				function _restoreFromItem(item, channelName) {
					if (!item || !item.valid) {
						return { restored: false, meaningful: false }
					}
					var parsed = _parsedModelFromValue(item.value, channelName)
					if (!parsed) {
						return { restored: false, meaningful: false }
					}
					graphHistory[channelName] = parsed
					return {
						restored: true,
						meaningful: graphHistory._hasMeaningfulData(parsed, channelName)
					}
				}

				function _publishRuntimeAll(force) {
					if (!_publishesRuntimeHistory) {
						return false
					}
					if (!force && !_dirty) {
						return true
					}

					let allPublished = true
					function _publish(channel, model, channelName) {
						if (!BackendConnection.setGraphHistoryValue(channel, graphHistory._serializedModel(model, channelName))) {
							allPublished = false
						}
					}

					_publish("solar", solarModel, "solarModel")
					_publish("acInput", acInputModel, "acInputModel")
					_publish("dcInput", dcInputModel, "dcInputModel")
					_publish("acLoads", acLoadsModel, "acLoadsModel")
					_publish("dcLoads", dcLoadsModel, "dcLoadsModel")

					if (allPublished) {
						_needsRuntimeSeed = false
					} else if (force || _dirty) {
						_needsRuntimeSeed = true
					}

					return allPublished
				}

			function _sample() {
				let pushedPoint = false
				var solarPower = Global.system ? (Global.system.solar.power ?? NaN) : NaN
				if (isNaN(solarPower)) {
					solarPower = 0
				}
				var solarMax = Global.system ? (Global.system.solar.maximumPower || NaN) : NaN
				_solarSum += _ratioWithDynMax(solarPower, solarMax, "_solarDynMax")
				_solarAcc++
				if (_solarAcc >= samplesPerPoint) {
					_pushValue("solarModel", _solarSum / _solarAcc)
					pushedPoint = true
					_solarSum = 0; _solarAcc = 0
				}

				var acInputPower = graphHistory._nonGeneratorInput ? graphHistory._nonGeneratorInput.totalPhasePower() : NaN
				var graphMin = 0
				var graphMax = 0
				if (graphHistory.acInputShowsFeedIn) {
					var acInputAbsPower = Math.abs(acInputPower || 0)
					var currentAbsGraphLimit = Math.max(Math.abs(_acPrevGraphMin), _acPrevGraphMax)
					if (acInputAbsPower > currentAbsGraphLimit) {
						graphMin = -acInputAbsPower
						graphMax = acInputAbsPower
					} else {
						graphMin = _acPrevGraphMin
						graphMax = _acPrevGraphMax
					}
				} else {
					var positiveAcInputPower = (!isNaN(acInputPower) && acInputPower > 0) ? acInputPower : 0
					graphMin = 0
					graphMax = Math.max(_acPrevGraphMax, positiveAcInputPower)
				}
				if (_acPrevGraphMin !== graphMin || _acPrevGraphMax !== graphMax) {
					if (_acPrevGraphMin !== 0 || _acPrevGraphMax !== 0) {
						_scaleAcInputHistoricalData(_acPrevGraphMin, _acPrevGraphMax, graphMin, graphMax)
					}
					_acPrevGraphMin = graphMin
					_acPrevGraphMax = graphMax
				}
				var acInputRatio = (isNaN(acInputPower) || (_acPrevGraphMin === 0 && _acPrevGraphMax === 0))
					? acInputInitialModelValue
					: FastUtils.scaleNumber(acInputPower, _acPrevGraphMin, _acPrevGraphMax, 0, 1)
				_acInputSum += acInputRatio
				_acInputAcc++
				if (_acInputAcc >= samplesPerPoint) {
					_pushValue("acInputModel", _acInputSum / _acInputAcc)
					pushedPoint = true
					_acInputSum = 0; _acInputAcc = 0
				}

			var dcInPower = Global.dcInputs ? (Global.dcInputs.power || 0) : 0
			var dcInMax = Global.dcInputs ? (Global.dcInputs.maximumPower || NaN) : NaN
				_dcInputSum += _ratioWithDynMax(dcInPower, dcInMax, "_dcInputDynMax")
				_dcInputAcc++
				if (_dcInputAcc >= samplesPerPoint) {
					_pushValue("dcInputModel", _dcInputSum / _dcInputAcc)
					pushedPoint = true
					_dcInputSum = 0; _dcInputAcc = 0
				}

				var acLoadPower = (Global.system && Global.system.load && Global.system.load.ac)
					? Global.system.load.ac.totalPhasePower()
					: NaN
				if (isNaN(acLoadPower)) {
					acLoadPower = 0
				}
				_acLoadsSum += _ratioWithDynMax(acLoadPower, NaN, "_acLoadDynMax")
				_acLoadsAcc++
				if (_acLoadsAcc >= samplesPerPoint) {
					_pushValue("acLoadsModel", _acLoadsSum / _acLoadsAcc)
					pushedPoint = true
					_acLoadsSum = 0; _acLoadsAcc = 0
				}

			var dcLoadPower = Global.system ? (Global.system.dc.power || 0) : 0
			var dcLoadMax = Global.system ? (Global.system.dc.maximumPower || NaN) : NaN
				_dcLoadsSum += _ratioWithDynMax(dcLoadPower, dcLoadMax, "_dcLoadDynMax")
				_dcLoadsAcc++
				if (_dcLoadsAcc >= samplesPerPoint) {
					_pushValue("dcLoadsModel", _dcLoadsSum / _dcLoadsAcc)
					pushedPoint = true
					_dcLoadsSum = 0; _dcLoadsAcc = 0
				}

				if (pushedPoint) {
					_dirtyPointCount++
					if (!_publishRuntimeAll(false)) {
						_needsRuntimeSeed = true
					}
				}
			}

			readonly property VeQuickItem _solarRuntimeHistory: VeQuickItem { uid: graphHistory._runtimeHistoryServiceUid ? graphHistory._runtimeHistoryServiceUid + "/History/solar" : "" }
			readonly property VeQuickItem _acInputRuntimeHistory: VeQuickItem { uid: graphHistory._runtimeHistoryServiceUid ? graphHistory._runtimeHistoryServiceUid + "/History/acInput" : "" }
			readonly property VeQuickItem _dcInputRuntimeHistory: VeQuickItem { uid: graphHistory._runtimeHistoryServiceUid ? graphHistory._runtimeHistoryServiceUid + "/History/dcInput" : "" }
			readonly property VeQuickItem _acLoadsRuntimeHistory: VeQuickItem { uid: graphHistory._runtimeHistoryServiceUid ? graphHistory._runtimeHistoryServiceUid + "/History/acLoads" : "" }
			readonly property VeQuickItem _dcLoadsRuntimeHistory: VeQuickItem { uid: graphHistory._runtimeHistoryServiceUid ? graphHistory._runtimeHistoryServiceUid + "/History/dcLoads" : "" }

			readonly property VeQuickItem _solarCheckpointHistory: VeQuickItem { uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui2/GraphHistory/solar" : "" }
			readonly property VeQuickItem _acInputCheckpointHistory: VeQuickItem { uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui2/GraphHistory/acInput" : "" }
			readonly property VeQuickItem _dcInputCheckpointHistory: VeQuickItem { uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui2/GraphHistory/dcInput" : "" }
			readonly property VeQuickItem _acLoadsCheckpointHistory: VeQuickItem { uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui2/GraphHistory/acLoads" : "" }
			readonly property VeQuickItem _dcLoadsCheckpointHistory: VeQuickItem { uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui2/GraphHistory/dcLoads" : "" }

				function _saveAll(force) {
					if (!_dirty) return
					if (!force && _dirtyPointCount < checkpointEveryPoints) return
					let allSaved = true
					function _save(item, model, channelName) {
						if (!item || !item.uid || !item.valid) {
							allSaved = false
							return
						}
						item.setValue(graphHistory._serializedModel(model, channelName))
					}
					_save(_solarCheckpointHistory, solarModel, "solarModel")
					_save(_acInputCheckpointHistory, acInputModel, "acInputModel")
					_save(_dcInputCheckpointHistory, dcInputModel, "dcInputModel")
					_save(_acLoadsCheckpointHistory, acLoadsModel, "acLoadsModel")
					_save(_dcLoadsCheckpointHistory, dcLoadsModel, "dcLoadsModel")
					if (allSaved) {
						_dirty = false
						_dirtyPointCount = 0
					}
				}

				function _restoreAll() {
					let restoredFromCheckpoint = false

					function _restoreChannel(runtimeItem, checkpointItem, channelName) {
						let result = graphHistory._restoreFromItem(runtimeItem, channelName)
						if (result.restored) {
							return
						}
						result = graphHistory._restoreFromItem(checkpointItem, channelName)
						if (result.restored) {
							restoredFromCheckpoint = true
						}
					}

					_restoreChannel(_solarRuntimeHistory, _solarCheckpointHistory, "solarModel")
					_restoreChannel(_acInputRuntimeHistory, _acInputCheckpointHistory, "acInputModel")
					_restoreChannel(_dcInputRuntimeHistory, _dcInputCheckpointHistory, "dcInputModel")
					_restoreChannel(_acLoadsRuntimeHistory, _acLoadsCheckpointHistory, "acLoadsModel")
					_restoreChannel(_dcLoadsRuntimeHistory, _dcLoadsCheckpointHistory, "dcLoadsModel")

					if (_publishesRuntimeHistory && restoredFromCheckpoint) {
						_needsRuntimeSeed = true
						_publishRuntimeAll(true)
					}
				}

		readonly property Timer _sampleTimer: Timer {
			running: Global.dataManagerLoaded && BackendConnection.type !== BackendConnection.MqttSource
			repeat: true; interval: 1000
			onTriggered: graphHistory._sample()
		}

			readonly property Timer _saveTimer: Timer {
				running: Global.dataManagerLoaded && BackendConnection.type !== BackendConnection.MqttSource
				repeat: true; interval: 60000
				onTriggered: graphHistory._saveAll(false)
			}

			readonly property Timer _restoreTimer: Timer {
				interval: 500
				onTriggered: graphHistory._restoreAll()
			}

			readonly property Connections _solarRuntimeHistoryConnection: Connections {
				target: graphHistory._solarRuntimeHistory
				function onValidChanged() {
					if (graphHistory._solarRuntimeHistory.valid) {
						graphHistory._restoreAll()
						if (graphHistory._needsRuntimeSeed) {
							graphHistory._publishRuntimeAll(true)
						}
					}
				}
				function onValueChanged() {
					graphHistory._restoreFromItem(graphHistory._solarRuntimeHistory, "solarModel")
				}
			}

			readonly property Connections _acInputRuntimeHistoryConnection: Connections {
				target: graphHistory._acInputRuntimeHistory
				function onValidChanged() {
					if (graphHistory._acInputRuntimeHistory.valid) {
						graphHistory._restoreAll()
						if (graphHistory._needsRuntimeSeed) {
							graphHistory._publishRuntimeAll(true)
						}
					}
				}
				function onValueChanged() {
					graphHistory._restoreFromItem(graphHistory._acInputRuntimeHistory, "acInputModel")
				}
			}

			readonly property Connections _dcInputRuntimeHistoryConnection: Connections {
				target: graphHistory._dcInputRuntimeHistory
				function onValidChanged() {
					if (graphHistory._dcInputRuntimeHistory.valid) {
						graphHistory._restoreAll()
						if (graphHistory._needsRuntimeSeed) {
							graphHistory._publishRuntimeAll(true)
						}
					}
				}
				function onValueChanged() {
					graphHistory._restoreFromItem(graphHistory._dcInputRuntimeHistory, "dcInputModel")
				}
			}

			readonly property Connections _acLoadsRuntimeHistoryConnection: Connections {
				target: graphHistory._acLoadsRuntimeHistory
				function onValidChanged() {
					if (graphHistory._acLoadsRuntimeHistory.valid) {
						graphHistory._restoreAll()
						if (graphHistory._needsRuntimeSeed) {
							graphHistory._publishRuntimeAll(true)
						}
					}
				}
				function onValueChanged() {
					graphHistory._restoreFromItem(graphHistory._acLoadsRuntimeHistory, "acLoadsModel")
				}
			}

			readonly property Connections _dcLoadsRuntimeHistoryConnection: Connections {
				target: graphHistory._dcLoadsRuntimeHistory
				function onValidChanged() {
					if (graphHistory._dcLoadsRuntimeHistory.valid) {
						graphHistory._restoreAll()
						if (graphHistory._needsRuntimeSeed) {
							graphHistory._publishRuntimeAll(true)
						}
					}
				}
				function onValueChanged() {
					graphHistory._restoreFromItem(graphHistory._dcLoadsRuntimeHistory, "dcLoadsModel")
				}
			}

			readonly property Connections _solarCheckpointHistoryConnection: Connections {
				target: graphHistory._solarCheckpointHistory
				function onValidChanged() {
					if (graphHistory._solarCheckpointHistory.valid) {
						graphHistory._restoreAll()
					}
				}
			}

			readonly property Connections _acInputCheckpointHistoryConnection: Connections {
				target: graphHistory._acInputCheckpointHistory
				function onValidChanged() {
					if (graphHistory._acInputCheckpointHistory.valid) {
						graphHistory._restoreAll()
					}
				}
			}

			readonly property Connections _dcInputCheckpointHistoryConnection: Connections {
				target: graphHistory._dcInputCheckpointHistory
				function onValidChanged() {
					if (graphHistory._dcInputCheckpointHistory.valid) {
						graphHistory._restoreAll()
					}
				}
			}

			readonly property Connections _acLoadsCheckpointHistoryConnection: Connections {
				target: graphHistory._acLoadsCheckpointHistory
				function onValidChanged() {
					if (graphHistory._acLoadsCheckpointHistory.valid) {
						graphHistory._restoreAll()
					}
				}
			}

			readonly property Connections _dcLoadsCheckpointHistoryConnection: Connections {
				target: graphHistory._dcLoadsCheckpointHistory
				function onValidChanged() {
					if (graphHistory._dcLoadsCheckpointHistory.valid) {
						graphHistory._restoreAll()
					}
				}
			}

				readonly property Connections _appVisibilityConnection: Connections {
					target: BackendConnection
					function onApplicationVisibleChanged() {
						if (!BackendConnection.applicationVisible) {
							graphHistory._saveAll(true)
						}
					}
				}

				Component.onCompleted: {
					Global.graphHistory = graphHistory
					_restoreTimer.start()
				}
			Component.onDestruction: _saveAll(true)
		}

	Loader {
		id: mockSetupLoader
		active: root._dataObjectsReady && BackendConnection.type === BackendConnection.MockSource
		asynchronous: true
		sourceComponent: MockSetup {}
		property bool mockLoaded
		onLoaded: { console.info("DataManager: mock setup loaded!"); mockLoaded = true }
		onStatusChanged: {
			if (status === Loader.Error) {
				console.warn("DataManager: Unable to load mock setup:", errorString())
			}
		}
	}
}
