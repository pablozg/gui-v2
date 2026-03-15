/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import Victron.VenusOS

Instantiator {
	id: root

	required property string systemServiceUid
	property real totalPower: NaN
	property real totalCurrent: NaN
	property real voltage: NaN

	// AC power is the total power from Ac/PvOnGrid/L*/Power, Ac/PvOnGenset/L*/Power
	// and Ac/PvOnOutput/L*/Power.
	function _updateAcTotals() {
		let _totalPower = NaN
		let _totalCurrent = NaN
		let _voltage = NaN
		let _voltageMismatch = false

		for (let i = 0; i < count; ++i) {
			const acPv = objectAt(i)
			if (!!acPv) {
				_totalPower = Units.sumRealNumbers(_totalPower, acPv.totalPhasePower())
				_totalCurrent = Units.sumRealNumbers(_totalCurrent, acPv.current)
				if (!isNaN(acPv.voltage)) {
					if (isNaN(_voltage)) {
						_voltage = acPv.voltage
					} else if (Math.abs(_voltage - acPv.voltage) > 1) {
						_voltageMismatch = true
					}
				}
			}
		}

		if (_voltageMismatch) {
			_voltage = NaN
		}

		root.totalPower = _totalPower
		root.totalCurrent = _totalCurrent
		root.voltage = _voltage
	}

	model: [
		`${root.systemServiceUid}/Ac/PvOnGrid`,
		`${root.systemServiceUid}/Ac/PvOnGenset`,
		`${root.systemServiceUid}/Ac/PvOnOutput`
	]

	delegate: ObjectAcConnection {
		required property string modelData

		bindPrefix: modelData
		onPowerChanged: Qt.callLater(root._updateAcTotals)
		onCurrentChanged: Qt.callLater(root._updateAcTotals)
		onVoltageChanged: Qt.callLater(root._updateAcTotals)
	}
}
