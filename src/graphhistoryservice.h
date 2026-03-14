/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

#ifndef GRAPHHISTORYSERVICE_H
#define GRAPHHISTORYSERVICE_H

#include <QObject>
#include <QString>

class VeQItem;
class VeQItemLocal;
class VeQItemProducer;
class VeQItemExportedDbusServices;

namespace Victron {
namespace VenusOS {

class GraphHistoryService : public QObject
{
	Q_OBJECT

public:
	explicit GraphHistoryService(QObject *parent = nullptr);
	~GraphHistoryService() override;

	bool start(const QString &dbusAddress);
	bool isStarted() const;
	bool setHistoryValue(const QString &channel, const QString &value);

private:
	void ensureTree();

#if !defined(VENUS_WEBASSEMBLY_BUILD)
	VeQItemLocal *m_exportRoot = nullptr;
	VeQItemProducer *m_localProducer = nullptr;
	VeQItem *m_serviceRoot = nullptr;
	VeQItemExportedDbusServices *m_exportedServices = nullptr;
	bool m_started = false;
#endif
};

} // namespace VenusOS
} // namespace Victron

#endif // GRAPHHISTORYSERVICE_H
