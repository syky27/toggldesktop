// Copyright 2026 Toggl Desktop -> Redmine fork

#include "./calendarview.h"

#include <QColor>
#include <QDateTime>
#include <QFont>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QPushButton>
#include <QScrollArea>
#include <QTime>
#include <QVBoxLayout>

#include "./toggl.h"

static const int kGutter = 56;          // left hour-label column width
static const int64_t kSecondsPerDay = 86400;

DayGrid::DayGrid(QWidget *parent) : QWidget(parent), dayStart_(0) {
    // ~26 px per hour so a full day is comfortably scrollable.
    setMinimumHeight(24 * 26);
    setAttribute(Qt::WA_StyledBackground, true);
    setStyleSheet("background:#ffffff;");
}

void DayGrid::setDay(int64_t dayStartEpoch, QVector<TimeEntryView *> entries) {
    dayStart_ = dayStartEpoch;
    entries_ = entries;
    update();
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

    // Time-entry blocks.
    for (TimeEntryView *te : entries_) {
        if (!te || te->IsHeader || te->Group) continue;
        int64_t dur = te->DurationInSeconds;
        if (dur < 0) continue;  // running entry: not shown on the day grid

        int64_t startInto = static_cast<int64_t>(te->Started) - dayStart_;
        if (startInto < 0) startInto = 0;
        if (startInto > kSecondsPerDay) continue;
        int64_t endInto = startInto + dur;
        if (endInto > kSecondsPerDay) endInto = kSecondsPerDay;

        int y = static_cast<int>((startInto / double(kSecondsPerDay)) * h);
        int bh = static_cast<int>(((endInto - startInto) / double(kSecondsPerDay)) * h);
        if (bh < 3) bh = 3;
        QRect r(kGutter + 4, y, w - kGutter - 8, bh);

        QColor color(te->Color.isEmpty() ? QString("#9e9e9e") : te->Color);
        if (!color.isValid()) color = QColor("#9e9e9e");
        p.fillRect(r, color);
        p.setPen(color.darker(130));
        p.drawRect(r);

        QString label = !te->Description.isEmpty() ? te->Description
                        : (!te->TaskLabel.isEmpty() ? te->TaskLabel
                                                    : te->ProjectLabel);
        if (bh >= 13 && !label.isEmpty()) {
            QRect textRect = r.adjusted(4, 1, -4, -1);
            p.setPen(QColor("#ffffff"));
            QFontMetrics fm(p.font());
            p.drawText(textRect, Qt::AlignLeft | Qt::AlignTop,
                       fm.elidedText(label, Qt::ElideRight, textRect.width()));
        }
    }
}

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
