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
			&& !!Global.graphHistory
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
	Item {
		id: graphHistory

		readonly property int modelLength: 120
		readonly property int samplesPerPoint: 60

		property var solarModel: Array(modelLength).fill(0)
		property var acInputModel: Array(modelLength).fill(0)
		property var dcInputModel: Array(modelLength).fill(0)
		property var acLoadsModel: Array(modelLength).fill(0)
		property var dcLoadsModel: Array(modelLength).fill(0)

		readonly property bool acInputShowsFeedIn: _acInputRange.minimumCurrent < 0
		readonly property real acInputInitialModelValue: acInputShowsFeedIn ? 0.5 : 0
		readonly property real acInputThreshold: isNaN(_acInputMaxAboveZeroMidPoint) ? 0 : 0.5

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

		ValueRange {
			id: _ghSolarRange
			value: Global.system ? (Global.system.solar.power || NaN) : NaN
			maximumValue: Global.system ? (Global.system.solar.maximumPower || NaN) : NaN
		}

		ValueRange {
			id: _ghDcInputRange
			value: Global.dcInputs ? (Global.dcInputs.power || NaN) : NaN
			maximumValue: Global.dcInputs ? (Global.dcInputs.maximumPower || NaN) : NaN
		}

		ValueRange {
			id: _ghDcLoadRange
			value: Global.system ? (Global.system.dc.power || NaN) : NaN
			maximumValue: Global.system ? (Global.system.dc.maximumPower || NaN) : NaN
		}

		AcPhasesCurrentRange {
			id: _acInputRange
			phaseModel: graphHistory._nonGeneratorInput ? graphHistory._nonGeneratorInput.phases : null
			minimumCurrent: isNaN(graphHistory._acInputMaxAboveZeroMidPoint)
				? (graphHistory._nonGeneratorInput ? graphHistory._nonGeneratorInput.inputInfo.minimumCurrent : 0)
				: -graphHistory._acInputMaxAboveZeroMidPoint
			maximumCurrent: isNaN(graphHistory._acInputMaxAboveZeroMidPoint)
				? (graphHistory._nonGeneratorInput ? graphHistory._nonGeneratorInput.inputInfo.maximumCurrent : 0)
				: graphHistory._acInputMaxAboveZeroMidPoint
		}

		AcPhasesCurrentRange {
			id: _acLoadRange
			phaseModel: Global.system ? Global.system.load.ac.phases : null
			maximumCurrent: Global.system ? Global.system.load.maximumAcCurrent : 0
		}

		property real _acPrevGraphMin: 0
		property real _acPrevGraphMax: 0

		function _scaleAcInputHistoricalData(prevMin, prevMax, newMin, newMax) {
			let temp = acInputModel
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

		function _pushValue(channelName, value) {
			let temp = graphHistory[channelName]
			temp.push(value)
			temp.shift()
			graphHistory[channelName] = temp
			_dirty = true
		}

		Timer {
			running: Global.dataManagerLoaded
			repeat: true
			interval: 1000
			onTriggered: {
				graphHistory._solarSum += _ghSolarRange.valueAsRatio
				graphHistory._solarAcc++
				if (graphHistory._solarAcc >= graphHistory.samplesPerPoint) {
					graphHistory._pushValue("solarModel", graphHistory._solarSum / graphHistory._solarAcc)
					graphHistory._solarSum = 0; graphHistory._solarAcc = 0
				}

				const graphMin = _acInputRange.minimumCurrent || 0
				const graphMax = _acInputRange.maximumCurrent || 0
				if (graphHistory._acPrevGraphMin !== graphMin || graphHistory._acPrevGraphMax !== graphMax) {
					if (graphHistory._acPrevGraphMin !== 0 || graphHistory._acPrevGraphMax !== 0) {
						graphHistory._scaleAcInputHistoricalData(graphHistory._acPrevGraphMin, graphHistory._acPrevGraphMax, graphMin, graphMax)
					}
					graphHistory._acPrevGraphMin = graphMin
					graphHistory._acPrevGraphMax = graphMax
				}
				graphHistory._acInputSum += _acInputRange.averagePhaseCurrentAsRatio
				graphHistory._acInputAcc++
				if (graphHistory._acInputAcc >= graphHistory.samplesPerPoint) {
					graphHistory._pushValue("acInputModel", graphHistory._acInputSum / graphHistory._acInputAcc)
					graphHistory._acInputSum = 0; graphHistory._acInputAcc = 0
				}

				graphHistory._dcInputSum += _ghDcInputRange.valueAsRatio
				graphHistory._dcInputAcc++
				if (graphHistory._dcInputAcc >= graphHistory.samplesPerPoint) {
					graphHistory._pushValue("dcInputModel", graphHistory._dcInputSum / graphHistory._dcInputAcc)
					graphHistory._dcInputSum = 0; graphHistory._dcInputAcc = 0
				}

				graphHistory._acLoadsSum += _acLoadRange.averagePhaseCurrentAsRatio
				graphHistory._acLoadsAcc++
				if (graphHistory._acLoadsAcc >= graphHistory.samplesPerPoint) {
					graphHistory._pushValue("acLoadsModel", graphHistory._acLoadsSum / graphHistory._acLoadsAcc)
					graphHistory._acLoadsSum = 0; graphHistory._acLoadsAcc = 0
				}

				graphHistory._dcLoadsSum += _ghDcLoadRange.valueAsRatio
				graphHistory._dcLoadsAcc++
				if (graphHistory._dcLoadsAcc >= graphHistory.samplesPerPoint) {
					graphHistory._pushValue("dcLoadsModel", graphHistory._dcLoadsSum / graphHistory._dcLoadsAcc)
					graphHistory._dcLoadsSum = 0; graphHistory._dcLoadsAcc = 0
				}
			}
		}

		VeQuickItem { id: _solarHistory; uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/solar" : "" }
		VeQuickItem { id: _acInputHistory; uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/acInput" : "" }
		VeQuickItem { id: _dcInputHistory; uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/dcInput" : "" }
		VeQuickItem { id: _acLoadsHistory; uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/acLoads" : "" }
		VeQuickItem { id: _dcLoadsHistory; uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/dcLoads" : "" }

		function _saveAll() {
			if (!_dirty) return
			function _save(item, model) {
				if (!item || !item.uid) return
				const rounded = model.map(function(v) { return Math.round(v * 10000) / 10000 })
				item.setValue(JSON.stringify(rounded))
			}
			_save(_solarHistory, solarModel)
			_save(_acInputHistory, acInputModel)
			_save(_dcInputHistory, dcInputModel)
			_save(_acLoadsHistory, acLoadsModel)
			_save(_dcLoadsHistory, dcLoadsModel)
			_dirty = false
		}

		function _restoreAll() {
			function _restore(item, channelName) {
				if (!item || !item.value) return
				try {
					const saved = JSON.parse(item.value)
					if (Array.isArray(saved) && saved.length === graphHistory.modelLength) {
						graphHistory[channelName] = saved
					}
				} catch(e) { /* ignore */ }
			}
			_restore(_solarHistory, "solarModel")
			_restore(_acInputHistory, "acInputModel")
			_restore(_dcInputHistory, "dcInputModel")
			_restore(_acLoadsHistory, "acLoadsModel")
			_restore(_dcLoadsHistory, "dcLoadsModel")
		}

		Timer {
			running: Global.dataManagerLoaded
			repeat: true; interval: 60000
			onTriggered: graphHistory._saveAll()
		}

		Timer {
			id: _ghRestoreTimer; interval: 500
			onTriggered: graphHistory._restoreAll()
		}

		Component.onCompleted: {
			Global.graphHistory = graphHistory
			_ghRestoreTimer.start()
		}
		Component.onDestruction: _saveAll()
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
