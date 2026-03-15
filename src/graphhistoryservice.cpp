/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

#include "graphhistoryservice.h"

#include <QCoreApplication>
#include <QtDebug>

#if !defined(VENUS_WEBASSEMBLY_BUILD)
#include "veutil/qt/ve_qitem.hpp"
#include "veutil/qt/ve_qitem_exported_dbus_services.hpp"
#endif

namespace Victron {
namespace VenusOS {

GraphHistoryService::GraphHistoryService(QObject *parent)
	: QObject(parent)
{
}

GraphHistoryService::~GraphHistoryService()
{
#if !defined(VENUS_WEBASSEMBLY_BUILD)
	delete m_exportedServices;
	m_exportedServices = nullptr;
	delete m_localProducer;
	m_localProducer = nullptr;
	delete m_exportRoot;
	m_exportRoot = nullptr;
#endif
}

bool GraphHistoryService::start(const QString &dbusAddress)
{
#if defined(VENUS_WEBASSEMBLY_BUILD)
	Q_UNUSED(dbusAddress);
	return false;
#else
	if (m_started) {
		return true;
	}

	ensureTree();

	const QString exportAddress = dbusAddress.isEmpty()
			? QStringLiteral("system")
			: dbusAddress;
	m_exportedServices->open(exportAddress);
	m_started = true;

	qInfo() << "Graph history service: exporting com.victronenergy.graphhistory on" << exportAddress;
	return true;
#endif
}

bool GraphHistoryService::isStarted() const
{
#if defined(VENUS_WEBASSEMBLY_BUILD)
	return false;
#else
	return m_started;
#endif
}

bool GraphHistoryService::setHistoryValue(const QString &channel, const QString &value)
{
#if defined(VENUS_WEBASSEMBLY_BUILD)
	Q_UNUSED(channel);
	Q_UNUSED(value);
	return false;
#else
	ensureTree();

	VeQItem *item = m_serviceRoot->itemGet(QStringLiteral("History/%1").arg(channel));
	if (!item) {
		qWarning() << "Graph history service: missing channel" << channel;
		return false;
	}

	item->setValue(value);
	return true;
#endif
}

void GraphHistoryService::ensureTree()
{
#if !defined(VENUS_WEBASSEMBLY_BUILD)
	if (m_serviceRoot) {
		return;
	}

	m_exportRoot = new VeQItemLocal(nullptr);
	m_localProducer = new VeQItemProducer(m_exportRoot, QStringLiteral("export"), this);
	m_serviceRoot = m_localProducer->services()->itemGetOrCreate(QStringLiteral("com.victronenergy.graphhistory"), false);
	m_serviceRoot->produceValue(1);

	const QString processName = QCoreApplication::applicationName().isEmpty()
			? QStringLiteral("gui-v2")
			: QCoreApplication::applicationName();
	const QString processVersion = QCoreApplication::applicationVersion().isEmpty()
			? QStringLiteral("unknown")
			: QCoreApplication::applicationVersion();

	m_serviceRoot->itemGetOrCreateAndProduce(QStringLiteral("Connected"), 1);
	m_serviceRoot->itemGetOrCreateAndProduce(QStringLiteral("DeviceInstance"), 0);
	m_serviceRoot->itemGetOrCreateAndProduce(QStringLiteral("ProductName"), QStringLiteral("GUI v2 graph history"));
	m_serviceRoot->itemGetOrCreateAndProduce(QStringLiteral("Mgmt/ProcessName"), processName);
	m_serviceRoot->itemGetOrCreateAndProduce(QStringLiteral("Mgmt/ProcessVersion"), processVersion);

	const QStringList channels {
		QStringLiteral("solar"),
		QStringLiteral("battery"),
		QStringLiteral("acInput"),
		QStringLiteral("dcInput"),
		QStringLiteral("acLoads"),
		QStringLiteral("dcLoads"),
	};
	for (const QString &channel : channels) {
		m_serviceRoot->itemGetOrCreateAndProduce(QStringLiteral("History/%1").arg(channel), QString());
	}

	m_exportedServices = new VeQItemExportedDbusServices(m_localProducer->services(), this);
#endif
}

} // namespace VenusOS
} // namespace Victron
