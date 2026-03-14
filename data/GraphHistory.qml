/*
** Copyright (C) 2025 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS

/*
	Persistent graph data collector that runs independently of page visibility.
	Maintains 120-point history (2 hours at 1 point/min) for 5 graph channels:
	solar, acInput, dcInput, acLoads, dcLoads.
	Data persists to Settings/Gui/GraphHistory/<key> via VeQuickItem.
*/
Item {
	id: root

	readonly property int modelLength: 120
	readonly property int samplesPerPoint: 60

	// Exposed models for LoadGraph binding
	property var solarModel: Array(modelLength).fill(0)
	property var acInputModel: Array(modelLength).fill(0)
	property var dcInputModel: Array(modelLength).fill(0)
	property var acLoadsModel: Array(modelLength).fill(0)
	property var dcLoadsModel: Array(modelLength).fill(0)

	// AC input display properties (needed by BriefSidePanel for colors/thresholds)
	readonly property bool acInputShowsFeedIn: _acInputRange.minimumCurrent < 0
	readonly property real acInputInitialModelValue: acInputShowsFeedIn ? 0.5 : 0
	readonly property real acInputThreshold: isNaN(_acInputMaxAboveZeroMidPoint) ? 0 : 0.5

	// --- Internal: non-generator AC input reference ---
	readonly property AcInput _nonGeneratorInput: Global.acInputs
		? (Global.acInputs.input1?.source !== VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input1
			: Global.acInputs.input2?.source !== VenusOS.AcInputs_InputSource_Generator ? Global.acInputs.input2
			: null)
		: null

	readonly property real _acInputMaxAboveZeroMidPoint: _nonGeneratorInput
		&& _nonGeneratorInput.inputInfo.minimumCurrent < 0
		&& _nonGeneratorInput.inputInfo.maximumCurrent > 0
			? Math.max(Math.abs(_nonGeneratorInput.inputInfo.minimumCurrent), _nonGeneratorInput.inputInfo.maximumCurrent)
			: NaN

	// --- Value ranges ---
	ValueRange {
		id: solarRange
		value: Global.system ? (Global.system.solar.power || NaN) : NaN
		maximumValue: Global.system ? (Global.system.solar.maximumPower || NaN) : NaN
	}

	ValueRange {
		id: dcInputRange
		value: Global.dcInputs ? (Global.dcInputs.power || NaN) : NaN
		maximumValue: Global.dcInputs ? (Global.dcInputs.maximumPower || NaN) : NaN
	}

	ValueRange {
		id: dcLoadRange
		value: Global.system ? (Global.system.dc.power || NaN) : NaN
		maximumValue: Global.system ? (Global.system.dc.maximumPower || NaN) : NaN
	}

	AcPhasesCurrentRange {
		id: _acInputRange
		phaseModel: root._nonGeneratorInput ? root._nonGeneratorInput.phases : null
		minimumCurrent: isNaN(root._acInputMaxAboveZeroMidPoint)
			? (root._nonGeneratorInput ? root._nonGeneratorInput.inputInfo.minimumCurrent : 0)
			: -root._acInputMaxAboveZeroMidPoint
		maximumCurrent: isNaN(root._acInputMaxAboveZeroMidPoint)
			? (root._nonGeneratorInput ? root._nonGeneratorInput.inputInfo.maximumCurrent : 0)
			: root._acInputMaxAboveZeroMidPoint
	}

	AcPhasesCurrentRange {
		id: _acLoadRange
		phaseModel: Global.system ? Global.system.load.ac.phases : null
		maximumCurrent: Global.system ? Global.system.load.maximumAcCurrent : 0
	}

	// --- AC Input scaling state ---
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

	// --- Accumulators ---
	property int _solarAcc: 0
	property real _solarSum: 0
	property int _acInputAcc: 0
	property real _acInputSum: 0
	property int _dcInputAcc: 0
	property real _dcInputSum: 0
	property int _acLoadsAcc: 0
	property real _acLoadsSum: 0
	property int _dcLoadsAcc: 0
	property real _dcLoadsSum: 0
	property bool _dirty: false

	function _pushValue(channelName, value) {
		let temp = root[channelName]
		temp.push(value)
		temp.shift()
		root[channelName] = temp
		_dirty = true
	}

	// --- 1-second sampling timer (always running) ---
	Timer {
		running: Global.dataManagerLoaded
		repeat: true
		interval: 1000
		onTriggered: {
			// Solar
			root._solarSum += solarRange.valueAsRatio
			root._solarAcc++
			if (root._solarAcc >= root.samplesPerPoint) {
				root._pushValue("solarModel", root._solarSum / root._solarAcc)
				root._solarSum = 0
				root._solarAcc = 0
			}

			// AC Input (with scaling logic)
			const graphMin = _acInputRange.minimumCurrent || 0
			const graphMax = _acInputRange.maximumCurrent || 0
			if (root._acPrevGraphMin !== graphMin || root._acPrevGraphMax !== graphMax) {
				if (root._acPrevGraphMin !== 0 || root._acPrevGraphMax !== 0) {
					root._scaleAcInputHistoricalData(root._acPrevGraphMin, root._acPrevGraphMax, graphMin, graphMax)
				}
				root._acPrevGraphMin = graphMin
				root._acPrevGraphMax = graphMax
			}
			root._acInputSum += _acInputRange.averagePhaseCurrentAsRatio
			root._acInputAcc++
			if (root._acInputAcc >= root.samplesPerPoint) {
				root._pushValue("acInputModel", root._acInputSum / root._acInputAcc)
				root._acInputSum = 0
				root._acInputAcc = 0
			}

			// DC Input
			root._dcInputSum += dcInputRange.valueAsRatio
			root._dcInputAcc++
			if (root._dcInputAcc >= root.samplesPerPoint) {
				root._pushValue("dcInputModel", root._dcInputSum / root._dcInputAcc)
				root._dcInputSum = 0
				root._dcInputAcc = 0
			}

			// AC Loads
			root._acLoadsSum += _acLoadRange.averagePhaseCurrentAsRatio
			root._acLoadsAcc++
			if (root._acLoadsAcc >= root.samplesPerPoint) {
				root._pushValue("acLoadsModel", root._acLoadsSum / root._acLoadsAcc)
				root._acLoadsSum = 0
				root._acLoadsAcc = 0
			}

			// DC Loads
			root._dcLoadsSum += dcLoadRange.valueAsRatio
			root._dcLoadsAcc++
			if (root._dcLoadsAcc >= root.samplesPerPoint) {
				root._pushValue("dcLoadsModel", root._dcLoadsSum / root._dcLoadsAcc)
				root._dcLoadsSum = 0
				root._dcLoadsAcc = 0
			}
		}
	}

	// --- Persistence ---
	VeQuickItem {
		id: _solarHistory
		uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/solar" : ""
	}
	VeQuickItem {
		id: _acInputHistory
		uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/acInput" : ""
	}
	VeQuickItem {
		id: _dcInputHistory
		uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/dcInput" : ""
	}
	VeQuickItem {
		id: _acLoadsHistory
		uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/acLoads" : ""
	}
	VeQuickItem {
		id: _dcLoadsHistory
		uid: Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/GraphHistory/dcLoads" : ""
	}

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
		function _restore(item, channelName, initialValue) {
			if (!item || !item.value) return
			try {
				const saved = JSON.parse(item.value)
				if (Array.isArray(saved) && saved.length === root.modelLength) {
					root[channelName] = saved
				}
			} catch(e) { /* ignore parse errors, start fresh */ }
		}
		_restore(_solarHistory, "solarModel", 0)
		_restore(_acInputHistory, "acInputModel", acInputInitialModelValue)
		_restore(_dcInputHistory, "dcInputModel", 0)
		_restore(_acLoadsHistory, "acLoadsModel", 0)
		_restore(_dcLoadsHistory, "dcLoadsModel", 0)
	}

	// Save periodically
	Timer {
		running: Global.dataManagerLoaded
		repeat: true
		interval: 60000
		onTriggered: root._saveAll()
	}

	// Restore on startup with delay to let VeQuickItems connect
	Timer {
		id: _restoreTimer
		interval: 500
		onTriggered: root._restoreAll()
	}

	Component.onCompleted: {
		Global.graphHistory = root
		_restoreTimer.start()
	}

	Component.onDestruction: _saveAll()
}
