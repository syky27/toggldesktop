// Copyright 2014 Toggl Desktop developers.

#include "./timeentrycellwidget.h"
#include "./ui_timeentrycellwidget.h"

#include <QKeyEvent>
#include <QMessageBox>
#include <QListWidgetItem>
#include <QUrl>
#include <QFont>

#include "./toggl.h"
#include "./desktopservices.h"

TimeEntryCellWidget::TimeEntryCellWidget(QListWidgetItem *item) : QWidget(nullptr),
ui(new Ui::TimeEntryCellWidget),
item(item),
description(""),
project(""),
guid(""),
group(false),
groupOpen(false),
groupName(""),
timeEntry(nullptr) {
    ui->setupUi(this);
    setFocusProxy(ui->dataFrame);
    ui->dataFrame->installEventFilter(this);
    setStyleSheet(
        "* { font-size: 13px }"
        // Issue line on top (prominent), description underneath (secondary).
        // These explicit rules beat the blanket "*" font-size above; the
        // matching QFonts set below keep the ellipsis width math accurate.
        "ClickableLabel#project { font-size: 14px; font-weight: bold }"
        "ClickableLabel#description { font-size: 12px; color: #5a5a5a }"
        "QFrame { background-color:transparent; border:none; margin:0 }"
        "QPushButton#dataFrame { background-color:#fefefe; border: none; border-bottom:1px solid #cacaca; margin: 0 }"
        "QPushButton#dataFrame:flat { background-color:transparent; }"
    );
    ui->groupButton->setStyleSheet(
        "QPushButton { outline:none; border:none; font-size:11px; color:#a4a4a4 }"
        "QPushButton:!checked { background:url(:/images/group_icon_closed.svg) no-repeat; }"
        "QPushButton:checked { background:url(:/images/group_icon_open.svg) no-repeat; }"
    );

    // Keep the real QFont in sync with the stylesheet font-size so that
    // setEllipsisTextToLabel() (which measures with label->font()) elides at
    // the right width and the text never overflows the row.
    QFont projectFont = ui->project->font();
    projectFont.setPixelSize(14);
    projectFont.setBold(true);
    ui->project->setFont(projectFont);

    QFont descriptionFont = ui->description->font();
    descriptionFont.setPixelSize(12);
    ui->description->setFont(descriptionFont);

    // The project label doubles as a clickable Redmine issue link. Let the
    // label handle link clicks itself (so linkActivated fires) and open the
    // issue in the browser instead of following the link internally.
    ui->project->setOpenExternalLinks(false);
    ui->project->setTextInteractionFlags(Qt::LinksAccessibleByMouse);
    connect(ui->project, &QLabel::linkActivated,
            this, &TimeEntryCellWidget::issueLinkActivated);
}

void TimeEntryCellWidget::display(TimeEntryView *view) {
    setLoadMore(false);
    guid = view->GUID;
    groupName = view->GroupName;
    timeEntry = view;
    description =
        (view->Description.length() > 0) ?
        view->Description : "(no description)";
    project = view->ProjectAndTaskLabel;

    setEllipsisTextToLabel(ui->description, description);
    setProjectLabel(view);
    ui->duration->setText(view->Duration);

    ui->billable->setVisible(view->Billable);
    ui->tags->setVisible(!view->Tags.isEmpty());

    ui->headerFrame->setVisible(view->IsHeader);
    ui->date->setText(view->DateHeader);
    ui->dateDuration->setText(view->DateDuration);

    ui->unsyncedicon->setVisible(view->Unsynced);

    if (view->StartTimeString.length() > 0 &&
            view->EndTimeString.length() > 0) {
        ui->duration->setToolTip(
            QString("<p style='color:black;background-color:white;'>" +
                    view->StartTimeString + " - " +
                    view->EndTimeString+"</p>"));
    }

    ui->tags->setToolTip(
        QString("<p style='color:black;background-color:white;'>" +
                (view->Tags).replace(QString("\t"), QString(", ")) + "</p>"));
    if (view->Description.length() > 0) {
        ui->description->setToolTip(
            QString("<p style='color:white;background-color:black;'>" +
                    view->Description + "</p>"));
    }
    if (view->ProjectAndTaskLabel.length() > 0) {
        ui->project->setToolTip(
            QString("<p style='color:white;background-color:black;'>" +
                    view->ProjectAndTaskLabel + "</p>"));
    }
    setupGroupedMode(view);
}

void TimeEntryCellWidget::setLoadMore(bool load_more) {
    ui->headerFrame->setVisible(false);
    ui->loadMoreButton->setEnabled(load_more);
    ui->loadMoreButton->setVisible(load_more);
    ui->descProjFrame->setVisible(!load_more);
    ui->groupFrame->setVisible(!load_more);
    ui->frame->setVisible(!load_more);
    ui->dataFrame->setFlat(load_more);
    ui->dataFrame->setStyleSheet(load_more ? "QPushButton#dataFrame { border:none }" : "");
    ui->dataFrame->setFocusPolicy(load_more ? Qt::NoFocus : Qt::StrongFocus);
    if (load_more) {
        ui->unsyncedicon->setVisible(false);
    }
}

QString TimeEntryCellWidget::entryGuid() {
    return guid;
}

void TimeEntryCellWidget::deleteTimeEntry() {
    if (guid.isEmpty())
        return;

    if (timeEntry->confirmlessDelete() || QMessageBox::Ok == QMessageBox(
        QMessageBox::Question,
        "Delete this time entry?",
        "Deleted time entries cannot be restored.",
        QMessageBox::Ok|QMessageBox::Cancel).exec()) {
        TogglApi::instance->deleteTimeEntry(guid);
    }
}

bool TimeEntryCellWidget::eventFilter(QObject *watched, QEvent *event) {
    if (event->type() == QEvent::FocusIn) {
        auto fe = reinterpret_cast<QFocusEvent*>(event);
        if (fe->reason() == Qt::TabFocusReason || fe->reason() == Qt::BacktabFocusReason)
            focusInEvent(fe);
    }
    if (event->type() == QEvent::KeyPress) {
        auto ke = reinterpret_cast<QKeyEvent*>(event);
        if (watched == ui->dataFrame) {
            if (ke->key() == Qt::Key_Space) {
                TogglApi::instance->continueTimeEntry(guid);
                event->accept();
                return true;
            }
            else if (ke->key() == Qt::Key_Delete || ke->key() == Qt::Key_Backspace) {
                if (timeEntry->confirmlessDelete() || QMessageBox::Ok == QMessageBox(
                    QMessageBox::Question,
                    "Delete this time entry?",
                    "Deleted time entries cannot be restored.",
                    QMessageBox::Ok|QMessageBox::Cancel).exec()) {
                    TogglApi::instance->deleteTimeEntry(guid);
                }
            }
            else if (ke->key() == Qt::Key_Return || ke->key() == Qt::Key_Enter) {
                TogglApi::instance->editTimeEntry(guid, "description");
            }
        }
    }
    return QWidget::eventFilter(watched, event);
}

void TimeEntryCellWidget::focusInEvent(QFocusEvent *event) {
    item->listWidget()->scrollToItem(item, QAbstractItemView::PositionAtCenter);
}

void TimeEntryCellWidget::setupGroupedMode(TimeEntryView *view) {
    // Grouped Mode Setup
    group = view->Group;
    QString style = "#dataFrame{border-right:2px solid palette(alternate-base);border-bottom:2px solid palette(alternate-base);background-color: palette(base);}\n #dataFrame:focus{background-color: palette(highlight);}";
    QString count = "";
    QString continueIcon = ":/images/continue_light.svg";
    // Description is the secondary (under-the-issue) line: small + muted. This
    // per-widget stylesheet overrides the cell-level rule, so repeat the
    // size/colour here to keep it secondary.
    QString descriptionStyle = "border:none;font-size:12px;color:#5a5a5a;";
    int left = 0;
    if (view->GroupItemCount && view->GroupOpen && !view->Group) {
        left = 10;
        descriptionStyle = "border:none;font-size:12px;color:palette(mid);";
    }
    ui->description->setStyleSheet(descriptionStyle);
    ui->descProjFrame->layout()->setContentsMargins(left, 9, 9, 9);
    ui->dataFrame->setStyleSheet(style);

    if (view->Group) {
        ui->groupButton->setChecked(view->GroupOpen);
        if (!view->GroupOpen)
            count = QString::number(view->GroupItemCount);
        continueIcon = ":/images/continue_regular.svg";
    }
    ui->groupButton->setText(count);
    ui->continueButton->setIcon(QIcon(continueIcon));
    ui->groupFrame->setVisible(view->Group);
}

void TimeEntryCellWidget::setEllipsisTextToLabel(ClickableLabel *label, QString text)
{
    QFontMetrics metrix(label->font());
    int width = label->width() - 2;
    QString clippedText = metrix.elidedText(text, Qt::ElideRight, width);
    label->setText(clippedText);
}

void TimeEntryCellWidget::setProjectLabel(TimeEntryView *view) {
    // The prominent top line is the Redmine issue (Toggl "task"): "#id: name".
    // Fall back to the combined project/task label, then the project, so the
    // line is never empty for entries without an issue.
    taskPlainText = view->TaskLabel;
    if (taskPlainText.isEmpty())
        taskPlainText = view->ProjectAndTaskLabel;
    if (taskPlainText.isEmpty())
        taskPlainText = view->ProjectLabel;

    // Build the issue URL only when we have an issue id and a configured base
    // URL; otherwise the line renders as plain (non-link) text.
    issueUrl.clear();
    QString baseUrl = TogglApi::instance->baseURL();
    if (view->TID > 0 && !baseUrl.isEmpty()) {
        issueUrl = baseUrl + "/issues/" + QString::number(view->TID);
    }

    projectColor = getProjectColor(view->Color);

    renderProjectLabel();
}

void TimeEntryCellWidget::renderProjectLabel() {
    // Elide against the label's actual font so the line never overflows, then
    // render either a Redmine issue link (rich text) or plain coloured text.
    QFontMetrics metrix(ui->project->font());
    int width = ui->project->width() - 2;
    QString elided = metrix.elidedText(taskPlainText, Qt::ElideRight, width);

    if (!issueUrl.isEmpty()) {
        ui->project->setText(
            QString("<a href=\"%1\" style=\"color:%2;text-decoration:none;\">%3</a>")
                .arg(issueUrl.toHtmlEscaped(),
                     projectColor,
                     elided.toHtmlEscaped()));
        ui->project->setStyleSheet("");
        ui->project->setCursor(Qt::PointingHandCursor);
    }
    else {
        ui->project->setText(elided.toHtmlEscaped());
        ui->project->setStyleSheet("color: '" + projectColor + "'");
        ui->project->setCursor(Qt::ArrowCursor);
    }
}

void TimeEntryCellWidget::issueLinkActivated(const QString &link) {
    if (link.isEmpty())
        return;
    QMetaObject::invokeMethod(DesktopServices::instance(), "openUrl",
                              Q_ARG(QUrl, QUrl(link)));
}

void TimeEntryCellWidget::labelClicked(QString field_name) {
    if (group) {
        on_groupButton_clicked();
        return;
    }
    TogglApi::instance->editTimeEntry(guid, field_name);
}

TimeEntryCellWidget::~TimeEntryCellWidget() {
    delete ui;
}

QSize TimeEntryCellWidget::getSizeHint(bool is_header) {
    if (is_header) {
        return QSize(minimumWidth(), sizeHint().height());
    }
    return QSize(minimumWidth(), ui->dataFrame->height());
}

void TimeEntryCellWidget::on_continueButton_clicked() {
    TogglApi::instance->continueTimeEntry(guid);
}

QString TimeEntryCellWidget::getProjectColor(QString color) {
    if (color.length() == 0) {
        return QString("#9d9d9d");
    }
    return color;
}

void TimeEntryCellWidget::toggleGroup(bool open)
{
    if (group && groupOpen != open) {
        groupOpen = open;
        TogglApi::instance->toggleEntriesGroup(groupName);
    }
}

void TimeEntryCellWidget::on_groupButton_clicked()
{
    TogglApi::instance->toggleEntriesGroup(groupName);
}

void TimeEntryCellWidget::resizeEvent(QResizeEvent* event)
{
    setEllipsisTextToLabel(ui->description, description);
    renderProjectLabel();
    QWidget::resizeEvent(event);
}

void TimeEntryCellWidget::on_loadMoreButton_clicked()
{
    TogglApi::instance->loadMore();
    ui->loadMoreButton->setEnabled(false);
    ui->loadMoreButton->setText("Loading ...");
}

void TimeEntryCellWidget::on_dataFrame_clicked() {
    if (group)
        on_groupButton_clicked();
    else
        TogglApi::instance->editTimeEntry(guid, "description");
}
