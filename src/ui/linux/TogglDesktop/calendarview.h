// Copyright 2026 Toggl Desktop -> Redmine fork

#ifndef SRC_UI_LINUX_TOGGLDESKTOP_CALENDARVIEW_H_
#define SRC_UI_LINUX_TOGGLDESKTOP_CALENDARVIEW_H_

#include <stdint.h>

#include <QWidget>
#include <QVector>
#include <QDate>
#include <QString>
#include <QRect>
#include <QPoint>

#include "./timeentryview.h"

class QLabel;

// DayGrid paints a single day as an hour-scaled column of time-entry blocks and
// supports drag-to-move and edge-resize to reorganize time. All edits are
// clamped to the displayed day (an entry never crosses midnight via the grid),
// snapped to 5-minute steps, and pushed to the core on release.
class DayGrid : public QWidget {
    Q_OBJECT

 public:
    explicit DayGrid(QWidget *parent = nullptr);
    // dayStartEpoch: unix seconds at local 00:00 of the shown day.
    void setDay(int64_t dayStartEpoch, QVector<TimeEntryView *> entries);

 protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

 private:
    enum DragMode { None, Move, ResizeTop, ResizeBottom };

    int yForSeconds(int64_t secIntoDay) const;
    int64_t entryStop(const TimeEntryView *te) const;
    QRect rectFor(int64_t startEpoch, int64_t stopEpoch) const;
    int64_t snap(int64_t epoch) const;
    DragMode hitTest(const QPoint &pos, TimeEntryView **hit) const;

    int64_t dayStart_;
    QVector<TimeEntryView *> entries_;

    // Drag state (kept as values/GUID, never as a dangling pointer across
    // a mid-drag list refresh).
    DragMode mode_;
    QString dragGuid_;
    int64_t origStart_;
    int64_t origStop_;
    int64_t previewStart_;
    int64_t previewStop_;
    int pressY_;
    bool moved_;

    // Click-to-edit / click-empty-to-create: a press that ends without a drag is
    // treated as a click. We remember where the press landed and, for blocks,
    // which entry, so release can open the editor or create a new entry.
    bool pressed_;
    QPoint pressPos_;
    QString pressGuid_;  // empty when the press landed on empty space
};

// CalendarView is a standalone window: a day header (prev/next/today) above a
// scrollable, editable DayGrid. It mirrors the time-entry list.
class CalendarView : public QWidget {
    Q_OBJECT

 public:
    explicit CalendarView(QWidget *parent = nullptr);

 public slots:  // NOLINT
    void displayTimeEntryList(bool open,
                              QVector<TimeEntryView *> list,
                              bool show_load_more_button);

 private slots:  // NOLINT
    void previousDay();
    void nextDay();
    void today();

 private:
    void refresh();

    QLabel *dateLabel_;
    DayGrid *grid_;
    QVector<TimeEntryView *> all_;
    QDate date_;
};

#endif  // SRC_UI_LINUX_TOGGLDESKTOP_CALENDARVIEW_H_
