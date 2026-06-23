#include "autocompletecombobox.h"
#include "autocompletelistmodel.h"
#include "autocompletelistview.h"
#include "toggl.h"

#include <QDebug>

AutocompleteComboBox::AutocompleteComboBox(QWidget *parent)
    : QComboBox(parent)
    , completer(new AutocompleteCompleter(this))
    , proxyModel(new AutocompleteProxyModel(this))
    , listView(qobject_cast<AutocompleteListView*>(completer->popup()))
{
    setEditable(true);
    completer->installEventFilter(this);
    listView->installEventFilter(this);
    lineEdit()->installEventFilter(this);
    lineEdit()->setFrame(false);
    completer->setModel(proxyModel);
    setCompleter(completer);
    disconnect(completer, SIGNAL(highlighted(QString)), lineEdit(), nullptr);
    connect(listView, &AutocompleteListView::visibleChanged, this, &AutocompleteComboBox::onDropdownVisibleChanged);
    connect(lineEdit(), &QLineEdit::textEdited, proxyModel, &AutocompleteProxyModel::setFilterFixedString);

    // Live Redmine issue search runs in parallel with the client-side filter
    // above: debounce typing, then ask the core to fetch matching issues.
    searchTimer = new QTimer(this);
    searchTimer->setSingleShot(true);
    searchTimer->setInterval(300);
    connect(searchTimer, &QTimer::timeout, this, &AutocompleteComboBox::onSearchTimerTimeout);
    connect(lineEdit(), &QLineEdit::textEdited, this, &AutocompleteComboBox::onTextEdited);

    connect(listView, &AutocompleteListView::selected, this, &AutocompleteComboBox::onDropdownSelected);
}

void AutocompleteComboBox::setModel(QAbstractItemModel *model) {
    proxyModel->setSourceModel(model);
}

void AutocompleteComboBox::showPopup() {
    completer->complete();
}

bool AutocompleteComboBox::eventFilter(QObject *o, QEvent *e) {
    // this is an ugly hack, this SHOULD happen in the FocusIn event but that actually never occurs
    if (o == lineEdit()) {
        auto retval = QComboBox::eventFilter(o, e);
        disconnect(completer, SIGNAL(highlighted(QString)), lineEdit(), nullptr);
        // there were text rendering glitches, this fixes the issue by forcing a repaint on every keypress
        if (e->type() == QEvent::KeyPress) {
            lineEdit()->repaint();
        }
        return retval;
    }
    else if (e->type() == QEvent::KeyPress) {
        auto ke = reinterpret_cast<QKeyEvent*>(e);
        switch (ke->key()) {
        case Qt::Key_Tab:
            cancelSelection();
            focusNextChild();
            break;
        case Qt::Key_Escape:
            cancelSelection();
            return true;
        case Qt::Key_Enter:
        case Qt::Key_Return: {
            if (ke->modifiers() & Qt::CTRL) {
                cancelSelection();
                e->ignore();
                return true;
            }
            if (listView->currentIndex().isValid()) {
                listView->keyPressEvent(ke);
            }
            else {
                listView->hide();
                emit returnPressed();
            }
            return true;
        }
        case Qt::Key_PageDown:
        case Qt::Key_PageUp:
        case Qt::Key_Up:
        case Qt::Key_Down:
            if (!listView->isVisible())
                completer->complete();
            else
                listView->keyPressEvent(ke);
            return true;
        case Qt::Key_Home:
        case Qt::Key_End:
            if (!listView->isVisible())
                lineEdit()->event(e);
            else
                listView->event(e);
            return true;
        default:
            QComboBox::keyPressEvent(ke);
            //lineEdit()->keyPressEvent(ke);
            return true;
        }
    }
    return QComboBox::eventFilter(o, e);
}

AutocompleteView *AutocompleteComboBox::currentView() {
    return qvariant_cast<AutocompleteView*>(listView->currentIndex().data(Qt::UserRole));
}

void AutocompleteComboBox::keyPressEvent(QKeyEvent *event) {
    switch (event->key()) {
    case Qt::Key_Enter:
    case Qt::Key_Return:
        if (event->modifiers() & Qt::CTRL) {
            event->ignore();
            return;
        }
        emit returnPressed();
        break;
    case Qt::Key_PageDown:
    case Qt::Key_PageUp:
    case Qt::Key_Down:
    case Qt::Key_Up:
        if (!listView->isVisible())
            completer->complete();
        else
            listView->keyPressEvent(event);
        break;
    default:
        QComboBox::keyPressEvent(event);
    }
}

void AutocompleteComboBox::onDropdownVisibleChanged() {
    if (listView->isVisible()) {
        proxyModel->setFilterFixedString(currentText());
    }
}

void AutocompleteComboBox::onDropdownSelected(AutocompleteView *item) {
    if (searchTimer)
        searchTimer->stop();  // don't fire a stale search after a pick
    if (item) {
        switch (item->Type) {
        case 0:
            emit projectSelected(item->ProjectLabel, item->ProjectID, item->ProjectColor, item->TaskLabel, item->TaskID);
            emit billableChanged(item->Billable);
            emit tagsChanged(item->Tags);
            emit timeEntrySelected(item->Description);
            break;
        case 1:
            emit projectSelected(item->ProjectLabel, item->ProjectID, item->ProjectColor, item->TaskLabel, item->TaskID);
            emit billableChanged(item->Billable);
            break;
        case 2:
            emit projectSelected(item->Text, item->ProjectID, item->ProjectColor, QString(), 0);
            emit billableChanged(item->Billable);
            break;
        default:
            break;
        }
    }
    emit activated(listView->currentIndex().row());
}

void AutocompleteComboBox::cancelSelection() {
    listView->setVisible(false);
}

void AutocompleteComboBox::setLiveSearchEnabled(bool enabled) {
    liveSearchEnabled = enabled;
}

void AutocompleteComboBox::onTextEdited(const QString &text) {
    if (!liveSearchEnabled || suppressSearch)
        return;

    const QString trimmed = text.trimmed();

    bool allDigits = !trimmed.isEmpty();
    for (const QChar &c : trimmed) {
        if (!c.isDigit()) {
            allDigits = false;
            break;
        }
    }
    // Require >=2 chars for a text search, but allow a single-digit issue lookup.
    if (trimmed.isEmpty() || (trimmed.length() < 2 && !allDigits)) {
        searchTimer->stop();
        return;
    }

    pendingSearchText = trimmed;
    searchTimer->start();  // restart the debounce window on each keystroke
}

void AutocompleteComboBox::onSearchTimerTimeout() {
    if (!pendingSearchText.isEmpty())
        TogglApi::instance->searchIssues(pendingSearchText);
}

void AutocompleteComboBox::refreshKeepingEdit(QVector<AutocompleteView *> list) {
    const QString text = lineEdit()->text();
    const int cursor = lineEdit()->cursorPosition();

    suppressSearch = true;  // model/text churn below must not re-trigger search

    auto *model = qobject_cast<AutocompleteListModel*>(proxyModel->sourceModel());
    if (model)
        model->setList(list);

    // Re-apply the client-side filter so the popup reflects the new rows.
    proxyModel->setFilterFixedString(text);

    // Restore the user's edit text + caret (setList can disturb the line edit).
    if (lineEdit()->text() != text)
        lineEdit()->setText(text);
    lineEdit()->setCursorPosition(qMin(cursor, lineEdit()->text().length()));

    suppressSearch = false;

    // Show the dropdown whenever the refreshed list has matches. Gating on the
    // popup's current visibility would miss the key case: typing an issue number
    // with no cached match hides the popup, and the live result must re-open it.
    if (proxyModel->rowCount() > 0)
        completer->complete();
}

AutocompleteCompleter::AutocompleteCompleter(QWidget *parent)
    : QCompleter(parent)
{
    setMaxVisibleItems(20);
    setPopup(new AutocompleteListView(parent));
    setCompletionMode(QCompleter::UnfilteredPopupCompletion);
}

bool AutocompleteCompleter::eventFilter(QObject *o, QEvent *e) {
    // completely ignore key events in the filter and let the combobox handle them
    if (e->type() == QEvent::KeyPress) {
        return false;
    }
    return QCompleter::eventFilter(o, e);
}

AutocompleteProxyModel::AutocompleteProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent) {
    setFilterRole(Qt::UserRole);
}

bool AutocompleteProxyModel::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const {
    QString input = filterRegExp().pattern();
    QStringList words = input.split(" ");

    auto view = qvariant_cast<AutocompleteView*>(sourceModel()->data(sourceModel()->index(source_row, 0), Qt::UserRole));
    for (auto word : words) {
        if (word.isEmpty() && words.count() > 1)
            continue;
        if (view->_Children.isEmpty()) {
            if (view->Description.contains(word, Qt::CaseInsensitive))
                    return true;
            if (view->Text.contains(word, Qt::CaseInsensitive))
                    return true;
        }
        for (auto v : view->_Children) {
            if (v->Description.contains(word, Qt::CaseInsensitive))
                    return true;
            if (v->Text.contains(word, Qt::CaseInsensitive))
                    return true;
        }
    }

    return false;
}
