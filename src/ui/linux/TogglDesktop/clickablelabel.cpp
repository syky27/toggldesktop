// Copyright 2014 Toggl Desktop developers.

#include "./clickablelabel.h"
#include "./toggl.h"
#include "./timeentrycellwidget.h"

ClickableLabel::ClickableLabel(QWidget * parent) : QLabel(parent) {
}

ClickableLabel::~ClickableLabel() {
}

void ClickableLabel::mousePressEvent(QMouseEvent * event) {
    // When this label carries a clickable link (the Redmine issue line), let
    // the base QLabel handle the press so it can emit linkActivated and open
    // the issue in the browser, instead of opening the time-entry editor.
    if ((textInteractionFlags() & Qt::LinksAccessibleByMouse) &&
            text().contains("<a ", Qt::CaseInsensitive)) {
        QLabel::mousePressEvent(event);
        return;
    }

    Q_UNUSED(event);
    QWidget* parentObject = this->parentWidget();

    while (parentObject->objectName().compare("TimeEntryCellWidget") != 0) {
        parentObject = parentObject->parentWidget();
    }

    TimeEntryCellWidget *Cell =
        qobject_cast<TimeEntryCellWidget *>(parentObject);
    Cell->labelClicked(this->objectName());
}
