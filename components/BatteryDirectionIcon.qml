/*
** Copyright (C) 2026 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Controls.impl as CP

// Match the AC input direction language: positive power means the battery is charging
// (power flowing into the battery), negative power means it is discharging.
CP.ColorImage {
	required property QtObject battery

	readonly property real _power: battery?.power ?? NaN

	visible: !isNaN(_power) && _power !== 0
	source: _power < 0 ? "qrc:/images/icon_to_grid.svg" : "qrc:/images/icon_from_grid.svg"
	color: _power < 0 ? Theme.color_red : Theme.color_green
}
