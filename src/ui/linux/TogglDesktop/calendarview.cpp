// Copyright 2026 Toggl Desktop -> Redmine fork

#include "./calendarview.h"

#include <QColor>
#include <QCursor>
#include <QDateTime>
#include <QFont>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QLabel>
#include <QMouseEvent>
#include <QPainter>
#include <QPushButton>
#include <QScrollArea>
#include <QTime>
#include <QVBoxLayout>

#include "./toggl.h"

static const int kGutter = 56;              // left hour-label column width
static const int64_t kSecondsPerDay = 86400;
static const int64_t kSnapSeconds = 300;    // snap edits to 5-minute steps
static const int kEdgePx = 6;               // resize-handle thickness
static const int64_t kMinDuration = 300;    // smallest entry the grid allows

// ----------------------------- DayGrid --------------------------------------

DayGrid::DayGrid(QWidget *parent)
    : QWidget(parent), dayStart_(0), mode_(None),
      origStart_(0), origStop_(0), previewStart_(0), previewStop_(0),
      pressY_(0), moved_(false), pressed_(false) {
    setMinimumHeight(24 * 26);  // ~26 px/hour, scrollable
    setMouseTracking(true);
    setAttribute(Qt::WA_StyledBackground, true);
    setStyleSheet("background:#ffffff;");
}

void DayGrid::setDay(int64_t dayStartEpoch, QVector<TimeEntryView *> entries) {
    dayStart_ = dayStartEpoch;
    entries_ = entries;
    update();
}

int DayGrid::yForSeconds(int64_t secIntoDay) const {
    return static_cast<int>((secIntoDay / double(kSecondsPerDay)) * height());
}

int64_t DayGrid::entryStop(const TimeEntryView *te) const {
    int64_t dur = te->DurationInSeconds > 0 ? te->DurationInSeconds : 0;
    return static_cast<int64_t>(te->Started) + dur;
}

QRect DayGrid::rectFor(int64_t startEpoch, int64_t stopEpoch) const {
    int64_t s = qBound<int64_t>(0, startEpoch - dayStart_, kSecondsPerDay);
    int64_t e = qBound<int64_t>(0, stopEpoch - dayStart_, kSecondsPerDay);
    int top = yForSeconds(s);
    int h = yForSeconds(e) - top;
    if (h < 3) h = 3;
    return QRect(kGutter + 4, top, width() - kGutter - 8, h);
}

int64_t DayGrid::snap(int64_t epoch) const {
    int64_t rel = epoch - dayStart_;
    rel = ((rel + kSnapSeconds / 2) / kSnapSeconds) * kSnapSeconds;
    return dayStart_ + rel;
}

DayGrid::DragMode DayGrid::hitTest(const QPoint &pos, TimeEntryView **hit) const {
    for (int i = entries_.size() - 1; i >= 0; --i) {
        TimeEntryView *te = entries_[i];
        if (!te || te->IsHeader || te->Group || te->DurationInSeconds < 0)
            continue;
        QRect r = rectFor(te->Started, entryStop(te));
        if (!r.contains(pos)) continue;
        if (hit) *hit = te;
        if (pos.y() - r.top() <= kEdgePx) return ResizeTop;
        if (r.bottom() - pos.y() <= kEdgePx) return ResizeBottom;
        return Move;
    }
    if (hit) *hit = nullptr;
    return None;
}

void DayGrid::paintEvent(QPaintEvent *) {
    QPainter p(this);
    const int w = width();
    const int h = height();
    const double hourH = h / 24.0;

    // Hour gridlines + labels.
    for (int hr = 0; hr <= 24; ++hr) {
        int y = static_cast<int>(hr * hourH);
        p.setPen(QColor("#e6e6e6"));
        p.drawLine(kGutter, y, w, y);
        if (hr < 24) {
            p.setPen(QColor("#9a9a9a"));
            p.drawText(QRect(0, y, kGutter - 6, static_cast<int>(hourH)),
                       Qt::AlignRight | Qt::AlignTop,
                       QString("%1:00").arg(hr, 2, 10, QChar('0')));
        }
    }

    for (TimeEntryView *te : entries_) {
        if (!te || te->IsHeader || te->Group || te->DurationInSeconds < 0)
            continue;
        int64_t start = te->Started;
        int64_t stop = entryStop(te);
        if (mode_ != None && te->GUID == dragGuid_) {  // show drag preview
            start = previewStart_;
            stop = previewStop_;
        }
        if (start - dayStart_ > kSecondsPerDay) continue;
        QRect r = rectFor(start, stop);

        QColor color(te->Color.isEmpty() ? QString("#9e9e9e") : te->Color);
        if (!color.isValid()) color = QColor("#9e9e9e");
        p.fillRect(r, color);
        p.setPen(color.darker(130));
        p.drawRect(r);

        QString label = !te->Description.isEmpty() ? te->Description
                        : (!te->TaskLabel.isEmpty() ? te->TaskLabel
                                                    : te->ProjectLabel);
        if (r.height() >= 13 && !label.isEmpty()) {
            QRect tr = r.adjusted(4, 1, -4, -1);
            p.setPen(QColor("#ffffff"));
            QFontMetrics fm(p.font());
            p.drawText(tr, Qt::AlignLeft | Qt::AlignTop,
                       fm.elidedText(label, Qt::ElideRight, tr.width()));
        }
    }
}

void DayGrid::mousePressEvent(QMouseEvent *event) {
    // Record the press for click detection (a press that ends without a drag is
    // a click: edit a block, or create an entry on empty space).
    pressed_ = true;
    pressPos_ = event->pos();
    moved_ = false;

    TimeEntryView *hit = nullptr;
    DragMode m = hitTest(event->pos(), &hit);
    if (m == None || !hit) {
        // Empty space: no drag, but remember it for a possible click-to-create.
        pressGuid_.clear();
        QWidget::mousePressEvent(event);
        return;
    }
    pressGuid_ = hit->GUID;
    mode_ = m;
    dragGuid_ = hit->GUID;
    origStart_ = hit->Started;
    origStop_ = entryStop(hit);
    previewStart_ = origStart_;
    previewStop_ = origStop_;
    pressY_ = event->pos().y();
}

void DayGrid::mouseMoveEvent(QMouseEvent *event) {
    if (mode_ == None) {  // hover: cursor feedback
        DragMode m = hitTest(event->pos(), nullptr);
        if (m == ResizeTop || m == ResizeBottom)
            setCursor(Qt::SizeVerCursor);
        else if (m == Move)
            setCursor(Qt::OpenHandCursor);
        else
            setCursor(Qt::ArrowCursor);
        return;
    }

    if (height() <= 0) return;
    int64_t deltaSec =
        static_cast<int64_t>(event->pos().y() - pressY_) * kSecondsPerDay / height();
    const int64_t dayEnd = dayStart_ + kSecondsPerDay;

    if (mode_ == Move) {
        int64_t dur = origStop_ - origStart_;
        int64_t ns = qBound<int64_t>(dayStart_, snap(origStart_ + deltaSec),
                                     dayEnd - dur);
        previewStart_ = ns;
        previewStop_ = ns + dur;
    } else if (mode_ == ResizeTop) {  // top edge moves, bottom (origStop_) fixed
        previewStart_ = qBound<int64_t>(dayStart_, snap(origStart_ + deltaSec),
                                        origStop_ - kMinDuration);
        previewStop_ = origStop_;
    } else {  // ResizeBottom: bottom edge moves, top (origStart_) fixed
        previewStop_ = qBound<int64_t>(origStart_ + kMinDuration,
                                       snap(origStop_ + deltaSec), dayEnd);
        previewStart_ = origStart_;
    }
    if (previewStart_ != origStart_ || previewStop_ != origStop_)
        moved_ = true;
    update();
}

void DayGrid::mouseReleaseEvent(QMouseEvent *event) {
    DragMode m = mode_;
    QString guid = dragGuid_;
    int64_t ps = previewStart_;
    int64_t pe = previewStop_;
    bool moved = moved_;
    bool pressed = pressed_;
    QString clickGuid = pressGuid_;

    mode_ = None;
    dragGuid_.clear();
    pressGuid_.clear();
    pressed_ = false;
    moved_ = false;
    setCursor(Qt::ArrowCursor);

    // A press that didn't turn into a drag is a click.
    if (pressed && !moved) {
        if (!clickGuid.isEmpty()) {
            // Click a block -> open its editor.
            TogglApi::instance->editTimeEntry(clickGuid, "description");
        } else {
            // Click empty space -> create a 30-min entry at the snapped click
            // time, then open the editor on the issue/project field so the user
            // picks an issue (the entry stays local until then).
            if (height() > 0) {
                int64_t clickSec = static_cast<int64_t>(event->pos().y())
                    * kSecondsPerDay / height();
                int64_t start = snap(dayStart_ + clickSec);
                int64_t end = start + 30 * 60;
                QString newGuid =
                    TogglApi::instance->createEmptyTimeEntry(start, end);
                if (!newGuid.isEmpty()) {
                    TogglApi::instance->editTimeEntry(newGuid, "project");
                }
            }
        }
        update();
        return;
    }

    if (m == None || !moved || guid.isEmpty()) {
        update();
        return;
    }

    // Push the edit to the core (which re-syncs to Redmine; the refreshed list
    // then repaints the block at its new position).
    switch (m) {
        case Move:  // keep duration, shift end
            TogglApi::instance->setTimeEntryStartTimestamp(guid, ps, false);
            break;
        case ResizeTop:  // keep end, change start/duration
            TogglApi::instance->setTimeEntryStartTimestamp(guid, ps, true);
            break;
        case ResizeBottom:  // keep start, change end/duration
            TogglApi::instance->setTimeEntryEndTimestamp(guid, pe);
            break;
        default:
            break;
    }
    update();
}

// --------------------------- CalendarView -----------------------------------

CalendarView::CalendarView(QWidget *parent)
    : QWidget(parent, Qt::Window), date_(QDate::currentDate()) {
    setWindowTitle("Calendar");
    resize(440, 680);

    auto *layout = new QVBoxLayout(this);

    auto *header = new QHBoxLayout();
    auto *prev = new QPushButton("<", this);
    auto *next = new QPushButton(">", this);
    auto *todayBtn = new QPushButton("Today", this);
    prev->setFixedWidth(36);
    next->setFixedWidth(36);
    dateLabel_ = new QLabel(this);
    dateLabel_->setAlignment(Qt::AlignCenter);
    QFont f = dateLabel_->font();
    f.setBold(true);
    dateLabel_->setFont(f);
    header->addWidget(prev);
    header->addWidget(dateLabel_, 1);
    header->addWidget(next);
    header->addWidget(todayBtn);
    layout->addLayout(header);

    auto *scroll = new QScrollArea(this);
    grid_ = new DayGrid(scroll);
    scroll->setWidget(grid_);
    scroll->setWidgetResizable(true);
    layout->addWidget(scroll, 1);

    connect(prev, &QPushButton::clicked, this, &CalendarView::previousDay);
    connect(next, &QPushButton::clicked, this, &CalendarView::nextDay);
    connect(todayBtn, &QPushButton::clicked, this, &CalendarView::today);

    connect(TogglApi::instance,
            SIGNAL(displayTimeEntryList(bool, QVector<TimeEntryView *>, bool)),
            this,
            SLOT(displayTimeEntryList(bool, QVector<TimeEntryView *>, bool)));

    refresh();
}

void CalendarView::displayTimeEntryList(bool, QVector<TimeEntryView *> list,
                                        bool) {
    all_ = list;
    refresh();
}

void CalendarView::previousDay() {
    date_ = date_.addDays(-1);
    refresh();
}

void CalendarView::nextDay() {
    date_ = date_.addDays(1);
    refresh();
}

void CalendarView::today() {
    date_ = QDate::currentDate();
    refresh();
}

void CalendarView::refresh() {
    dateLabel_->setText(date_.toString("dddd, d MMMM yyyy"));
    int64_t dayStart = QDateTime(date_, QTime(0, 0)).toSecsSinceEpoch();

    QVector<TimeEntryView *> dayEntries;
    for (TimeEntryView *te : all_) {
        if (!te || te->IsHeader || te->Group) continue;
        int64_t s = static_cast<int64_t>(te->Started);
        if (s >= dayStart && s < dayStart + kSecondsPerDay) {
            dayEntries.append(te);
        }
    }
    grid_->setDay(dayStart, dayEntries);
}
