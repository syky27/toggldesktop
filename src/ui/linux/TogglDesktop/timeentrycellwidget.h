// Copyright 2014 Toggl Desktop developers.

#ifndef SRC_UI_LINUX_TOGGLDESKTOP_TIMEENTRYCELLWIDGET_H_
#define SRC_UI_LINUX_TOGGLDESKTOP_TIMEENTRYCELLWIDGET_H_

#include <QWidget>

#include "./timeentryview.h"
#include "./clickablelabel.h"

namespace Ui {
class TimeEntryCellWidget;
}

class QListWidgetItem;

class TimeEntryCellWidget : public QWidget {
    Q_OBJECT

 public:
    TimeEntryCellWidget(QListWidgetItem *item);
    ~TimeEntryCellWidget();

    void display(TimeEntryView *view);
    QSize getSizeHint(bool is_header);
    void labelClicked(QString field_name);
    void setLoadMore(bool load_more);

    QString entryGuid();
    void toggleGroup(bool open);

 public slots:
    void deleteTimeEntry();

 protected:
    virtual bool eventFilter(QObject *watched, QEvent *event) override;
    virtual void focusInEvent(QFocusEvent *event) override;
    virtual void resizeEvent(QResizeEvent *) override;

 private slots:  // NOLINT
    void on_continueButton_clicked();
    void on_groupButton_clicked();
    void on_loadMoreButton_clicked();
    void on_dataFrame_clicked();
    void issueLinkActivated(const QString &link);

 private:
    Ui::TimeEntryCellWidget *ui;
    QListWidgetItem *item;

    QString description;
    QString project;
    QString guid;
    bool group;
    bool groupOpen;
    QString groupName;
    TimeEntryView *timeEntry;
    // Plain "#id: name" text for the issue line (used for ellipsis measuring),
    // its resolved Redmine URL (empty when there's nothing to link to) and the
    // colour to render it in. Cached so resizeEvent() can re-elide/re-render.
    QString taskPlainText;
    QString issueUrl;
    QString projectColor;
    QString getProjectColor(QString color);

    void setupGroupedMode(TimeEntryView *view);
    void setEllipsisTextToLabel(ClickableLabel *label, QString text);
    void setProjectLabel(TimeEntryView *view);
    void renderProjectLabel();
};

#endif  // SRC_UI_LINUX_TOGGLDESKTOP_TIMEENTRYCELLWIDGET_H_
